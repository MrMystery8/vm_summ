package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.util.Log
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.EventChannel
import kotlinx.coroutines.*
import okhttp3.OkHttpClient
import okhttp3.Request
import java.io.File
import java.io.FileOutputStream
import java.util.concurrent.TimeUnit

/**
 * Manages Gemma 4 model packaging and caching.
 * 
 * Downloads models from HuggingFace and caches them locally.
 * Supports progress reporting via EventChannel.
 */
class GemmaModelManager : FlutterPlugin, MethodCallHandler, EventChannel.StreamHandler {
    
    private lateinit var methodChannel: MethodChannel
    private lateinit var eventChannel: EventChannel
    private lateinit var context: Context
    private var eventSink: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.IO + SupervisorJob())
    
    private val client = OkHttpClient.Builder()
        .connectTimeout(30, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()
    
    companion object {
        const val METHOD_CHANNEL = "com.voicenotesummarizer/gemma_model_manager"
        const val EVENT_CHANNEL = "com.voicenotesummarizer/gemma_model_manager/progress"
        private const val TAG = "GemmaModelManager"
    }
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        
        methodChannel = MethodChannel(flutterPluginBinding.binaryMessenger, METHOD_CHANNEL)
        methodChannel.setMethodCallHandler(this)
        
        eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, EVENT_CHANNEL)
        eventChannel.setStreamHandler(this)
        
        Log.d(TAG, "GemmaModelManager attached to engine")
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        methodChannel.setMethodCallHandler(null)
        eventChannel.setStreamHandler(null)
        scope.cancel()
        Log.d(TAG, "GemmaModelManager detached from engine")
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getModelPath" -> getModelPath(call, result)
            "isModelDownloaded" -> isModelDownloaded(call, result)
            "copyBundledModel" -> copyBundledModel(call, result)
            "downloadModel" -> downloadModel(call, result)
            "deleteModel" -> deleteModel(call, result)
            "getModelSize" -> getModelSize(call, result)
            "getAvailableModels" -> getAvailableModels(result)
            else -> result.notImplemented()
        }
    }
    
    override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
        eventSink = events
    }
    
    override fun onCancel(arguments: Any?) {
        eventSink = null
    }
    
    /**
     * Get the local path for a model.
     * Returns the path even if the model isn't downloaded yet.
     */
    private fun getModelPath(call: MethodCall, result: Result) {
        val modelName = call.argument<String>("modelName") ?: GemmaModelConfig.LOCAL_FILENAME
        val modelsDir = GemmaModelConfig.modelsDir(context)
        val modelPath = File(modelsDir, modelName).absolutePath
        result.success(modelPath)
    }
    
    /**
     * Check if a model is already downloaded.
     */
    private fun isModelDownloaded(call: MethodCall, result: Result) {
        val modelName = call.argument<String>("modelName") ?: GemmaModelConfig.LOCAL_FILENAME
        val modelsDir = GemmaModelConfig.modelsDir(context)
        val modelFile = File(modelsDir, modelName)
        val markerFile = File(modelsDir, modelName + GemmaModelConfig.CACHE_MARKER_SUFFIX)
        
        val exists = modelFile.exists() && modelFile.length() > 0 && markerFile.exists()
        result.success(mapOf(
            "downloaded" to exists,
            "path" to modelFile.absolutePath,
            "size" to if (exists) modelFile.length() else 0
        ))
    }
    
    /**
     * Get the size of a downloaded model.
     */
    private fun getModelSize(call: MethodCall, result: Result) {
        val modelName = call.argument<String>("modelName") ?: GemmaModelConfig.LOCAL_FILENAME
        val modelsDir = GemmaModelConfig.modelsDir(context)
        val modelFile = File(modelsDir, modelName)
        
        if (modelFile.exists()) {
            result.success(modelFile.length())
        } else {
            result.success(0L)
        }
    }
    
    /**
     * Get list of available models with their download status.
     */
    private fun getAvailableModels(result: Result) {
        val modelsDir = GemmaModelConfig.modelsDir(context)
        
        val models = listOf(
            mapOf(
                "name" to GemmaModelConfig.DISPLAY_NAME,
                "filename" to GemmaModelConfig.LOCAL_FILENAME,
                "bundledAsset" to GemmaModelConfig.BUNDLED_ASSET,
                "downloaded" to run {
                    val file = File(modelsDir, GemmaModelConfig.LOCAL_FILENAME)
                    val marker = File(
                        modelsDir,
                        GemmaModelConfig.LOCAL_FILENAME + GemmaModelConfig.CACHE_MARKER_SUFFIX,
                    )
                    file.exists() && file.length() > 0 && marker.exists()
                },
                "description" to GemmaModelConfig.DESCRIPTION,
                "estimatedSize" to GemmaModelConfig.ESTIMATED_SIZE
            )
        )
        
        result.success(models)
    }
    
    /**
     * Copy the bundled model from assets to app storage.
     * This is the primary method since the model is bundled in the APK.
     */
    private fun copyBundledModel(call: MethodCall, result: Result) {
        val assetName = call.argument<String>("assetName") ?: GemmaModelConfig.BUNDLED_ASSET
        val destName = call.argument<String>("destName") ?: GemmaModelConfig.LOCAL_FILENAME
        
        val modelsDir = GemmaModelConfig.modelsDir(context)
        modelsDir.mkdirs()
        val destFile = File(modelsDir, destName)
        val tmpFile = File(modelsDir, "$destName.tmp")
        val markerFile = File(modelsDir, destName + GemmaModelConfig.CACHE_MARKER_SUFFIX)
        
        // Check if already copied
        if (
            destFile.exists() &&
            destFile.length() > 100 * 1024 * 1024 &&
            markerFile.exists()
        ) {
            Log.d(TAG, "Model already copied: ${destFile.absolutePath} (${destFile.length()} bytes)")
            result.success(mapOf(
                "success" to true,
                "path" to destFile.absolutePath,
                "size" to destFile.length(),
                "alreadyExists" to true
            ))
            return
        }
        
        scope.launch {
            try {
                Log.d(TAG, "Copying bundled model: $assetName -> ${destFile.absolutePath}")
                
                // Delete partial file if exists
                if (destFile.exists()) {
                    destFile.delete()
                }
                if (tmpFile.exists()) {
                    tmpFile.delete()
                }
                if (markerFile.exists()) {
                    markerFile.delete()
                }
                
                // Copy from assets using chunked reading into a temp file first.
                context.assets.open(assetName).use { input ->
                    FileOutputStream(tmpFile).use { output ->
                        val buffer = ByteArray(65536) // 64KB buffer
                        var bytesRead: Int
                        var totalBytes = 0L
                        var lastProgressUpdate = 0L
                        
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            totalBytes += bytesRead
                            
                            // Report progress every 50MB
                            if (totalBytes - lastProgressUpdate >= 50 * 1024 * 1024) {
                                lastProgressUpdate = totalBytes
                                Log.d(TAG, "Copied ${totalBytes / 1024 / 1024} MB...")
                                
                                withContext(Dispatchers.Main) {
                                    eventSink?.success(mapOf(
                                        "modelName" to destName,
                                        "bytesDownloaded" to totalBytes,
                                        "status" to "copying"
                                    ))
                                }
                            }
                        }
                        output.flush()
                        Log.d(TAG, "Copy complete: ${totalBytes / 1024 / 1024} MB")
                    }
                }

                if (tmpFile.length() == 0L) {
                    throw IllegalStateException("Model copy failed: 0 bytes copied")
                }

                if (destFile.exists()) {
                    destFile.delete()
                }
                if (!tmpFile.renameTo(destFile)) {
                    throw IllegalStateException(
                        "Atomic rename failed: ${tmpFile.absolutePath} -> ${destFile.absolutePath}",
                    )
                }

                markerFile.writeText(
                    "asset=$assetName\nbytes=${destFile.length()}\nversion=1\n",
                )
                
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf(
                        "modelName" to destName,
                        "bytesDownloaded" to destFile.length(),
                        "status" to "complete"
                    ))
                    
                    result.success(mapOf(
                        "success" to true,
                        "path" to destFile.absolutePath,
                        "size" to destFile.length(),
                        "alreadyExists" to false
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Copy failed: ${e.message}", e)
                
                // Clean up partial file
                if (destFile.exists()) {
                    destFile.delete()
                }
                if (tmpFile.exists()) {
                    tmpFile.delete()
                }
                if (markerFile.exists()) {
                    markerFile.delete()
                }
                
                withContext(Dispatchers.Main) {
                    result.error("COPY_FAILED", e.message, e.stackTraceToString())
                }
            }
        }
    }
    
    /**
     * Download a model from HuggingFace.
     * 
     * Arguments:
     * - modelName: String - Filename for the model
     * - url: String - Custom URL (required for downloading)
     * - hfToken: String? - HuggingFace token for authenticated downloads
     */
    private fun downloadModel(call: MethodCall, result: Result) {
        val modelName = call.argument<String>("modelName") ?: GemmaModelConfig.LOCAL_FILENAME
        val url = call.argument<String>("url")
        val hfToken = call.argument<String>("hfToken")
        
        if (url == null) {
            result.error(
                "MISSING_URL", 
                "URL is required for downloading. Use copyBundledModel for the bundled model.", 
                null
            )
            return
        }
        
        val modelsDir = GemmaModelConfig.modelsDir(context)
        modelsDir.mkdirs()
        val modelFile = File(modelsDir, modelName)
        val markerFile = File(modelsDir, modelName + GemmaModelConfig.CACHE_MARKER_SUFFIX)
        
        scope.launch {
            try {
                Log.d(TAG, "Starting download: $url -> ${modelFile.absolutePath}")
                
                val requestBuilder = Request.Builder().url(url)
                
                // Add HuggingFace token if provided
                if (hfToken != null) {
                    requestBuilder.header("Authorization", "Bearer $hfToken")
                }
                
                val request = requestBuilder.build()
                val response = client.newCall(request).execute()
                
                if (!response.isSuccessful) {
                    throw Exception("Download failed: ${response.code} ${response.message}")
                }
                
                val body = response.body ?: throw Exception("Empty response body")
                val contentLength = body.contentLength()
                
                Log.d(TAG, "Content length: $contentLength bytes")
                
                // Write with progress reporting
                FileOutputStream(modelFile).use { output ->
                    body.byteStream().use { input ->
                        val buffer = ByteArray(8192)
                        var bytesRead: Int
                        var totalBytesRead = 0L
                        var lastProgressUpdate = 0L
                        
                        while (input.read(buffer).also { bytesRead = it } != -1) {
                            output.write(buffer, 0, bytesRead)
                            totalBytesRead += bytesRead
                            
                            // Update progress every 1MB to avoid flooding
                            if (totalBytesRead - lastProgressUpdate >= 1_000_000) {
                                val progress = if (contentLength > 0) {
                                    (totalBytesRead.toDouble() / contentLength * 100).toInt()
                                } else {
                                    -1
                                }
                                
                                lastProgressUpdate = totalBytesRead
                                
                                withContext(Dispatchers.Main) {
                                    eventSink?.success(mapOf(
                                        "modelName" to modelName,
                                        "bytesDownloaded" to totalBytesRead,
                                        "totalBytes" to contentLength,
                                        "progress" to progress,
                                        "status" to "downloading"
                                    ))
                                }
                            }
                        }
                }
                }
                
                Log.d(TAG, "Download complete: ${modelFile.absolutePath} (${modelFile.length()} bytes)")
                markerFile.writeText(
                    "downloaded=true\nbytes=${modelFile.length()}\nversion=1\n",
                )
                
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf(
                        "modelName" to modelName,
                        "bytesDownloaded" to modelFile.length(),
                        "totalBytes" to modelFile.length(),
                        "progress" to 100,
                        "status" to "complete"
                    ))
                    
                    result.success(mapOf(
                        "success" to true,
                        "path" to modelFile.absolutePath,
                        "size" to modelFile.length()
                    ))
                }
            } catch (e: Exception) {
                Log.e(TAG, "Download failed: ${e.message}", e)
                
                // Clean up partial download
                if (modelFile.exists()) {
                    modelFile.delete()
                }
                if (markerFile.exists()) {
                    markerFile.delete()
                }
                
                withContext(Dispatchers.Main) {
                    eventSink?.success(mapOf(
                        "modelName" to modelName,
                        "status" to "error",
                        "error" to e.message
                    ))
                    
                    result.error("DOWNLOAD_FAILED", e.message, e.stackTraceToString())
                }
            }
        }
    }
    
    /**
     * Delete a downloaded model.
     */
    private fun deleteModel(call: MethodCall, result: Result) {
        val modelName = call.argument<String>("modelName") ?: GemmaModelConfig.LOCAL_FILENAME
        val modelsDir = GemmaModelConfig.modelsDir(context)
        val modelFile = File(modelsDir, modelName)
        val markerFile = File(modelsDir, modelName + GemmaModelConfig.CACHE_MARKER_SUFFIX)
        
        if (modelFile.exists()) {
            val deleted = modelFile.delete()
            if (markerFile.exists()) {
                markerFile.delete()
            }
            result.success(mapOf(
                "deleted" to deleted,
                "path" to modelFile.absolutePath
            ))
        } else {
            if (markerFile.exists()) {
                markerFile.delete()
            }
            result.success(mapOf(
                "deleted" to false,
                "path" to modelFile.absolutePath,
                "reason" to "File does not exist"
            ))
        }
    }
}
