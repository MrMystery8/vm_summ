package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.util.Log
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import java.io.File

/**
 * Atomic model file management - ensures model is fully copied before use.
 * Uses tmp file + rename pattern for atomic availability.
 */
object ModelStore {
    private const val TAG = "ModelStore"
    private const val MODEL_ASSET = "gemma-3n-E2B-it-int4.litertlm"
    
    private val lock = Mutex()
    @Volatile private var ready: CompletableDeferred<File>? = null
    
    /**
     * Ensures model is ready - atomic copy with tmp file rename.
     * Multiple callers will wait for the same copy operation.
     */
    suspend fun ensureModelReady(context: Context): File {
        // Fast path - already ready
        ready?.let { return it.await() }
        
        val (deferred, isLeader) = lock.withLock {
            ready?.let { return@withLock it to false }
            val d = CompletableDeferred<File>()
            ready = d
            d to true
        }
        
        if (isLeader) {
            try {
                val finalFile = File(context.filesDir, MODEL_ASSET)
                
                Log.d(TAG, "Checking model: ${finalFile.absolutePath}")
                
                // Check if already exists with non-zero size (can't use available() for large files)
                if (finalFile.exists() && finalFile.length() > 0) {
                    Log.d(TAG, "Model already exists: ${finalFile.length()} bytes")
                    deferred.complete(finalFile)
                } else {
                    Log.d(TAG, "Copying model from assets...")
                    
                    finalFile.parentFile?.mkdirs()
                    val tmpFile = File(finalFile.parentFile, "${finalFile.name}.tmp")
                    
                    // Clean up any existing tmp file
                    if (tmpFile.exists()) tmpFile.delete()
                    
                    // Copy to tmp file
                    context.assets.open(MODEL_ASSET).use { input ->
                        tmpFile.outputStream().use { output ->
                            val buffer = ByteArray(1024 * 1024) // 1MB buffer
                            var totalCopied = 0L
                            var bytesRead: Int
                            while (input.read(buffer).also { bytesRead = it } != -1) {
                                output.write(buffer, 0, bytesRead)
                                totalCopied += bytesRead
                            }
                            output.flush()
                            Log.d(TAG, "Copied $totalCopied bytes to tmp file")
                        }
                    }
                    
                    // Verify copy succeeded (non-zero size)
                    if (tmpFile.length() == 0L) {
                        tmpFile.delete()
                        throw IllegalStateException("Model copy failed: 0 bytes copied")
                    }
                    
                    // Atomic rename
                    if (finalFile.exists()) finalFile.delete()
                    if (!tmpFile.renameTo(finalFile)) {
                        throw IllegalStateException(
                            "Atomic rename failed: ${tmpFile.absolutePath} -> ${finalFile.absolutePath}"
                        )
                    }
                    
                    Log.d(TAG, "Model ready: ${finalFile.absolutePath} (${finalFile.length()} bytes)")
                    deferred.complete(finalFile)
                }
            } catch (t: Throwable) {
                Log.e(TAG, "Model copy failed", t)
                // Allow retry later
                lock.withLock { ready = null }
                deferred.completeExceptionally(t)
            }
        }
        
        return deferred.await()
    }
    
    /**
     * Reset to allow retry after failure
     */
    suspend fun reset() {
        lock.withLock {
            ready?.cancel()
            ready = null
        }
    }
}
