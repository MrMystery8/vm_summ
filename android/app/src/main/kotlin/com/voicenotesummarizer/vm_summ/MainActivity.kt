package com.voicenotesummarizer.vm_summ

import android.util.Log
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.FileOutputStream

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.voicenotesummarizer/native_assets"
    private val TAG = "NativeAssets"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        // Register native audio converter plugin
        flutterEngine.plugins.add(AudioConverterPlugin())
        
        // Register bundled Gemma audio plugins
        flutterEngine.plugins.add(GemmaAudioPlugin())
        flutterEngine.plugins.add(GemmaModelManager())

        // Register platform channel for large file copy
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "copyAssetToFile" -> {
                    val assetName = call.argument<String>("assetName")
                    val destPath = call.argument<String>("destPath")
                    
                    if (assetName == null || destPath == null) {
                        result.error("INVALID_ARGS", "assetName and destPath are required", null)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        Log.d(TAG, "Starting copy of $assetName to $destPath")
                        copyAssetToFile(assetName, destPath)
                        Log.d(TAG, "Copy completed successfully")
                        result.success(true)
                    } catch (e: Exception) {
                        Log.e(TAG, "Copy failed: ${e.message}", e)
                        result.error("COPY_FAILED", e.message, e.stackTraceToString())
                    }
                }
                "assetExists" -> {
                    val assetName = call.argument<String>("assetName")
                    if (assetName == null) {
                        result.error("INVALID_ARGS", "assetName is required", null)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        val exists = assetExists(assetName)
                        Log.d(TAG, "Asset $assetName exists: $exists")
                        result.success(exists)
                    } catch (e: Exception) {
                        Log.e(TAG, "assetExists failed: ${e.message}")
                        result.success(false)
                    }
                }
                "getAssetSize" -> {
                    val assetName = call.argument<String>("assetName")
                    if (assetName == null) {
                        result.error("INVALID_ARGS", "assetName is required", null)
                        return@setMethodCallHandler
                    }
                    
                    try {
                        val size = getAssetSize(assetName)
                        Log.d(TAG, "Asset $assetName size: $size bytes")
                        result.success(size)
                    } catch (e: Exception) {
                        Log.e(TAG, "getAssetSize failed: ${e.message}")
                        // Return -1 if we can't get size (compressed assets)
                        result.success(-1L)
                    }
                }
                else -> result.notImplemented()
            }
        }
    }

    /**
     * Copy asset to file using chunked reading to avoid OOM.
     * This reads in 8KB chunks, never loading the entire file into memory.
     */
    private fun copyAssetToFile(assetName: String, destPath: String) {
        val destFile = File(destPath)
        destFile.parentFile?.mkdirs()
        
        Log.d(TAG, "Opening asset: $assetName")
        assets.open(assetName).use { inputStream ->
            Log.d(TAG, "Creating output file: $destPath")
            FileOutputStream(destFile).use { outputStream ->
                val buffer = ByteArray(65536) // 64KB buffer for faster copy
                var bytesRead: Int
                var totalBytes = 0L
                while (inputStream.read(buffer).also { bytesRead = it } != -1) {
                    outputStream.write(buffer, 0, bytesRead)
                    totalBytes += bytesRead
                    if (totalBytes % (50 * 1024 * 1024) == 0L) {
                        Log.d(TAG, "Copied ${totalBytes / 1024 / 1024} MB...")
                    }
                }
                outputStream.flush()
                Log.d(TAG, "Total copied: ${totalBytes / 1024 / 1024} MB")
            }
        }
    }

    /**
     * Check if asset exists in the native assets folder.
     */
    private fun assetExists(assetName: String): Boolean {
        return try {
            assets.open(assetName).use { true }
        } catch (e: Exception) {
            Log.e(TAG, "Asset not found: $assetName - ${e.message}")
            false
        }
    }

    /**
     * Get the size of an asset file.
     * Note: This may fail for compressed assets. Falls back to -1.
     */
    private fun getAssetSize(assetName: String): Long {
        return try {
            assets.openFd(assetName).use { it.length }
        } catch (e: Exception) {
            // Compressed assets don't support openFd
            // Try to get size by reading (more expensive)
            try {
                assets.open(assetName).use { 
                    it.available().toLong()
                }
            } catch (e2: Exception) {
                -1L
            }
        }
    }
}
