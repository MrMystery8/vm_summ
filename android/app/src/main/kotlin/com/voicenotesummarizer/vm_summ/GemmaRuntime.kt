package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File
import java.util.concurrent.Executors

/**
 * Single-flight engine initialization.
 * All callers wait for the same init operation - no concurrent engine creation.
 * Uses single-threaded dispatcher for all engine operations.
 */
object GemmaRuntime {
    private const val TAG = "GemmaRuntime"
    
    private val initLock = Mutex()
    @Volatile private var engineDeferred: CompletableDeferred<Engine>? = null
    @Volatile private var forceCpuOnly = false
    
    // Single thread for ALL engine operations - prevents GPU race conditions
    private val dispatcher = Executors.newSingleThreadExecutor().asCoroutineDispatcher()
    val scope = CoroutineScope(SupervisorJob() + dispatcher)
    
    /**
     * Get or create engine - single-flight pattern.
     * All callers wait for the same initialization.
     */
    suspend fun getEngine(context: Context, modelFile: File): Engine {
        // Fast path - already ready
        engineDeferred?.let { 
            return it.await() 
        }
        
        val (deferred, isLeader) = initLock.withLock {
            engineDeferred?.let { return@withLock it to false }
            val d = CompletableDeferred<Engine>()
            engineDeferred = d
            d to true
        }
        
        if (isLeader) {
            try {
                Log.d(TAG, "Creating engine on single thread...")
                
                // IMPORTANT: Create engine on the single thread
                val engine = withContext(dispatcher) {
                    val useCpuOnly = forceCpuOnly || isEmulator()
                    Log.d(TAG, "Engine backend mode: ${if (useCpuOnly) "CPU_ONLY" else "GPU_MAIN"}")
                    val config = EngineConfig(
                        modelPath = modelFile.absolutePath,
                        backend = if (useCpuOnly) Backend.CPU() else Backend.GPU(),
                        visionBackend = if (useCpuOnly) Backend.CPU() else Backend.GPU(),
                        audioBackend = Backend.CPU(),
                        maxNumTokens = 2048,
                        cacheDir = context.cacheDir.absolutePath
                    )
                    Engine(config).also { it.initialize() }
                }
                
                Log.d(TAG, "Engine ready")
                deferred.complete(engine)
            } catch (t: Throwable) {
                Log.e(TAG, "Engine creation failed", t)
                initLock.withLock { engineDeferred = null }
                deferred.completeExceptionally(t)
            }
        }
        
        return deferred.await()
    }
    
    /**
     * Check if engine is ready (non-blocking)
     */
    fun isReady(): Boolean = engineDeferred?.isCompleted == true
    
    /**
     * Reset to allow retry after failure
     */
    suspend fun reset() {
        initLock.withLock {
            try {
                engineDeferred?.await()?.close()
            } catch (_: Exception) {}
            engineDeferred?.cancel()
            engineDeferred = null
        }
    }

    suspend fun forceCpuFallback() {
        forceCpuOnly = true
        reset()
    }

    fun shouldFallbackToCpu(t: Throwable): Boolean {
        if (forceCpuOnly) return false
        val message = t.message?.lowercase() ?: return false
        return "opencl" in message || "sampler" in message
    }

    private fun isEmulator(): Boolean {
        return Build.FINGERPRINT.contains("generic", ignoreCase = true) ||
            Build.MODEL.contains("emulator", ignoreCase = true) ||
            Build.HARDWARE.equals("ranchu", ignoreCase = true) ||
            Build.HARDWARE.equals("goldfish", ignoreCase = true) ||
            Build.PRODUCT.contains("sdk", ignoreCase = true)
    }
}
