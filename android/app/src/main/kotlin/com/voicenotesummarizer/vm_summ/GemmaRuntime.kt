package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.os.Build
import android.util.Log
import com.google.ai.edge.litertlm.Backend
import com.google.ai.edge.litertlm.Capabilities
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.EngineConfig
import com.google.ai.edge.litertlm.ExperimentalApi
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
    const val MAX_NUM_TOKENS = 8192
    
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
    @OptIn(ExperimentalApi::class)
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
                    val backend = if (useCpuOnly) Backend.CPU() else Backend.GPU()
                    val visionBackend = if (useCpuOnly) Backend.CPU() else Backend.GPU()
                    
                    val samplerLoadResult = if (useCpuOnly) {
                        SamplerLoadResult(false, false, false, false)
                    } else {
                        ensureSamplerLibrariesLoaded()
                    }
                    
                    val capabilitySupport = detectSpeculativeDecodingSupport(modelFile)
                    
                    val isEmulatorDevice = isEmulator()
                    
                    // Speculative-decoding readiness signal used for diagnostics.
                    val speculativeDecodingReady = when {
                        isEmulatorDevice -> false
                        useCpuOnly -> false
                        capabilitySupport == false -> false
                        !samplerLoadResult.bridgeLoaded && !samplerLoadResult.liteRtLoaded -> false
                        else -> true
                    }


                    Log.i(
                        TAG,
                        "Initializing LiteRT-LM v${BuildConfig.LITERT_LM_VERSION} " +
                            "with backend=${backend.name}, " +
                            "visionBackend=${visionBackend.name}, " +
                            "audioBackend=CPU, " +
                            "samplerLoaded=${samplerLoadResult.bridgeLoaded || samplerLoadResult.openClLoaded}, " +
                            "speculativeDecodingReady=$speculativeDecodingReady, " +
                            "maxNumTokens=$MAX_NUM_TOKENS",
                    )
                    val config = EngineConfig(
                        modelPath = modelFile.absolutePath,
                        backend = backend,
                        visionBackend = visionBackend,
                        audioBackend = Backend.CPU(),
                        maxNumTokens = MAX_NUM_TOKENS,
                        cacheDir = context.cacheDir.absolutePath
                    )
                    Engine(config).also { it.initialize() }
                }
                
                Log.i(TAG, "Engine ready")
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

    private fun detectSpeculativeDecodingSupport(modelFile: File): Boolean? {
        return try {
            Capabilities(modelFile.absolutePath).use { capabilities ->
                val supported = capabilities.hasSpeculativeDecodingSupport()
                Log.d(TAG, "Speculative decoding capability probe returned: $supported")
                supported
            }
        } catch (t: Throwable) {
            Log.w(TAG, "Speculative decoding capability probe failed", t)
            null
        }
    }

    private data class SamplerLoadResult(
        val bridgeLoaded: Boolean,
        val liteRtLoaded: Boolean,
        val openClLoaded: Boolean,
        val webGpuLoaded: Boolean,
    )

    private fun ensureSamplerLibrariesLoaded(): SamplerLoadResult {
        var liteRtLoaded = false
        var openClLoaded = false
        var webGpuLoaded = false
        var bridgeLoaded = false

        try {
            System.loadLibrary("litert_sampler_bridge")
            bridgeLoaded = true
            Log.d(TAG, "Loaded native sampler bridge: liblitert_sampler_bridge.so")
            
            // The bridge now dynamically loads the other libraries with RTLD_GLOBAL.
            // We can assume they are loaded if the bridge is loaded.
            liteRtLoaded = true
            openClLoaded = true
            webGpuLoaded = true
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to load native sampler bridge liblitert_sampler_bridge.so", t)
        }

        if (!bridgeLoaded) {
            // Fallback for older approach if bridge fails
            try {
                System.loadLibrary("LiteRt")
                liteRtLoaded = true
                Log.d(TAG, "Loaded core native library: libLiteRt.so")
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to load core native library libLiteRt.so", t)
            }

            try {
                System.loadLibrary("LiteRtTopKOpenClSampler")
                openClLoaded = true
                Log.d(TAG, "Loaded native sampler library: libLiteRtTopKOpenClSampler.so")
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to load sampler library libLiteRtTopKOpenClSampler.so", t)
            }

            try {
                System.loadLibrary("LiteRtTopKWebGpuSampler")
                webGpuLoaded = true
                Log.d(TAG, "Loaded native sampler library: libLiteRtTopKWebGpuSampler.so")
            } catch (t: Throwable) {
            }
        }
 
        return SamplerLoadResult(
            bridgeLoaded = bridgeLoaded,
            liteRtLoaded = liteRtLoaded,
            openClLoaded = openClLoaded,
            webGpuLoaded = webGpuLoaded,
        )
    }
}
