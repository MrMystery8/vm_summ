package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Contents
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.ExperimentalApi
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.EventChannel.EventSink
import io.flutter.plugin.common.EventChannel.StreamHandler
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import java.io.File
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import android.os.Handler
import android.os.Looper

/**
 * Gemma 4 audio plugin - uses single-flight initialization pattern.
 * All init calls wait for the same operation via GemmaRuntime.
 * Model copy is atomic via ModelStore.
 */
class GemmaAudioPlugin : FlutterPlugin, MethodCallHandler {
    
    private lateinit var channel: MethodChannel
    private lateinit var context: Context
    
    private val mainHandler = Handler(Looper.getMainLooper())
    private val mutex = Mutex() // For inference serialization only
    
    companion object {
        const val CHANNEL_NAME = "com.voicenotesummarizer/gemma_audio"
        const val STREAM_CHANNEL_NAME = "com.voicenotesummarizer/gemma_audio/chat_stream"
        private const val TAG = "GemmaAudioPlugin"
        
        // System prompts
        private const val TRANSCRIPTION_SYSTEM = """TRANSCRIBE VERBATIM. DO NOT TRANSLATE.

You are transcribing a short voice note that may freely switch between English and Hindi.
Treat code-switching as normal and preserve it faithfully.

RULES:
1. Write exactly what is spoken, with the same meaning and order.
2. Keep English words, names, acronyms, product terms, dates, and numbers exactly as spoken.
3. Romanize Hindi words and phrases into clear Latin script. Do not translate Hindi into English.
4. Preserve mixed-language phrases at the word or clause level. Do not force the whole sentence into one language.
5. Keep fillers, hesitations, repetitions, and self-corrections when they are clearly spoken.
6. Preserve punctuation only when it is helpful for readability. Do not invent punctuation the speaker did not imply.
7. Do not summarize, paraphrase, clean up grammar, or rewrite for style.
8. If a word is uncertain, preserve the most likely spoken form rather than guessing a translation.
9. Output only the transcript text, with no labels or commentary.

EXAMPLES:
- "Let's meet kal at 3" -> "Let's meet kal at 3"
- "Main theek hoon, thanks" -> "Main theek hoon, thanks"
- "Aaj the call is delayed" -> "Aaj the call is delayed"
- "I'll send it abhi" -> "I'll send it abhi"
- "Please WhatsApp pe bhejo" -> "Please WhatsApp pe bhejo"

OUTPUT: Only the romanized transcript. Nothing else."""

        private const val SUMMARIZATION_SYSTEM = """You are a concise summarization assistant.

Your task is to analyze transcripts and extract key information.

Always provide output in this exact Markdown format:

## TITLE
A short descriptive title (3-6 words) for this recording.

## SUMMARY
Write a brief 2-3 sentence paragraph summarizing the main content and purpose.

## KEY POINTS
- Short phrase capturing first key point
- Short phrase capturing second key point
- Short phrase capturing third key point
(maximum 5 points, each under 10 words)

## ACTION ITEMS
- Task or follow-up item mentioned
(or write "None" if no action items were mentioned)"""
    }
    
    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        context = flutterPluginBinding.applicationContext
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
        
        val eventChannel = EventChannel(flutterPluginBinding.binaryMessenger, STREAM_CHANNEL_NAME)
        eventChannel.setStreamHandler(object : StreamHandler {
            override fun onListen(arguments: Any?, events: EventSink?) {
                eventSink = events
            }
            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
        
        Log.d(TAG, "Plugin attached")
    }
    
    // Sink for streaming responses
    private var eventSink: EventSink? = null
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Cleanup handled by GemmaRuntime singleton
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> initialize(call, result)
            "transcribe" -> transcribe(call, result)
            "transcribeSegment" -> transcribeSegment(call, result)
            "transcribeAndSummarize" -> transcribeAndSummarize(call, result)
            "summarizeTranscript" -> summarizeTranscript(call, result)
            "generateResponse" -> generateResponse(call, result)
            "chat" -> chat(call, result)
            "chatStream" -> chatStream(call, result)
            "isInitialized" -> result.success(GemmaRuntime.isReady())
            "dispose" -> dispose(result)
            else -> result.notImplemented()
        }
    }
    
    /**
     * Initialize using single-flight pattern.
     * Uses ModelStore for atomic copy, GemmaRuntime for engine creation.
     * All callers wait for the same operation - no concurrent inits.
     */
    private fun initialize(call: MethodCall, result: Result) {
        GemmaRuntime.scope.launch {
            try {
                Log.d(TAG, "Initialize called - using single-flight pattern")
                val modelPath = call.argument<String>("modelPath")
                
                // Step 1: Ensure model is ready (atomic copy)
                val modelFile = ModelStore.ensureModelReady(context, modelPath)
                Log.d(TAG, "Model file ready: ${modelFile.absolutePath}")
                
                // Step 2: Get or create engine (single-flight)
                GemmaRuntime.getEngine(context, modelFile)
                Log.d(TAG, "Engine ready via GemmaRuntime")
                
                mainHandler.post { 
                    result.success(mapOf("success" to true)) 
                }
            } catch (e: Exception) {
                Log.e(TAG, "Init failed", e)
                mainHandler.post { result.error("INIT_FAILED", e.message, null) }
            }
        }
    }

    private fun transcribe(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("path") ?: call.argument<String>("audioPath")
        val transcriptionSystem = call.argument<String>("transcriptionSystem")
        val transcriptionPrompt = call.argument<String>("transcriptionPrompt")
        
        if (audioPath == null) {
            result.error("INVALID_ARGS", "audioPath required", null)
            return
        }
        
        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    val transcript = doTranscribe(audioPath, transcriptionSystem, transcriptionPrompt)
                    mainHandler.post { result.success(mapOf("transcript" to transcript, "response" to transcript)) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("TRANSCRIPTION_FAILED", e.message, null) }
                }
            }
        }
    }

    private fun transcribeSegment(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("path") ?: call.argument<String>("audioPath")
        val segmentIndex = call.argument<Int>("segmentIndex") ?: -1
        val segmentCount = call.argument<Int>("segmentCount") ?: -1

        if (audioPath == null) {
            result.error("INVALID_ARGS", "audioPath required", null)
            return
        }
        if (segmentIndex <= 0 || segmentCount <= 0) {
            result.error("INVALID_ARGS", "segmentIndex and segmentCount required", null)
            return
        }

        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    Log.d(TAG, "Transcribing segment $segmentIndex/$segmentCount: $audioPath")
                    val transcript = doTranscribe(audioPath, null, null)
                    mainHandler.post {
                        result.success(
                            mapOf(
                                "transcript" to transcript,
                                "response" to transcript,
                                "segmentIndex" to segmentIndex,
                                "segmentCount" to segmentCount,
                            )
                        )
                    }
                } catch (e: Exception) {
                    mainHandler.post { result.error("TRANSCRIPTION_FAILED", e.message, null) }
                }
            }
        }
    }
    
    private fun transcribeAndSummarize(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("path")
        val systemInstruction = call.argument<String>("systemInstruction")
        val queryInstruction = call.argument<String>("queryInstruction")
        val transcriptionSystem = call.argument<String>("transcriptionSystem")
        val transcriptionPrompt = call.argument<String>("transcriptionPrompt")
        
        if (audioPath == null) {
            result.error("INVALID_ARGS", "audioPath required", null)
            return
        }
        
        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    val transcript = doTranscribe(audioPath, transcriptionSystem, transcriptionPrompt)
                    val summaryMap = doSummarize(transcript, systemInstruction, queryInstruction)
                    
                    val combined = summaryMap.toMutableMap()
                    combined["transcript"] = transcript
                    combined["response"] = transcript // redundant but safe
                    
                    mainHandler.post { result.success(combined) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("PROCESS_FAILED", e.message, null) }
                }
            }
        }
    }

    private fun summarizeTranscript(call: MethodCall, result: Result) {
        val transcript = call.argument<String>("transcript")
        val systemInstruction = call.argument<String>("systemInstruction")
        val queryInstruction = call.argument<String>("queryInstruction")

        if (transcript.isNullOrBlank()) {
            result.error("INVALID_ARGS", "transcript required", null)
            return
        }

        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    val summaryMap = doSummarize(transcript, systemInstruction, queryInstruction)
                    val combined = summaryMap.toMutableMap()
                    combined["transcript"] = transcript
                    combined["response"] = transcript
                    mainHandler.post { result.success(combined) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("PROCESS_FAILED", e.message, null) }
                }
            }
        }
    }
    
    private fun generateResponse(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("path") ?: call.argument<String>("audioPath")
        val prompt = call.argument<String>("prompt")
        
        if (audioPath == null || prompt == null) {
            result.error("INVALID_ARGS", "audioPath and prompt required", null)
            return
        }
        
        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    val response = runAudioInference(audioPath, prompt)
                    mainHandler.post { result.success(mapOf("success" to true, "response" to response)) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("INFERENCE_FAILED", e.message, null) }
                }
            }
        }
    }
    
    private fun chat(call: MethodCall, result: Result) {
        val transcript = call.argument<String>("transcript")
        val prompt = call.argument<String>("prompt")
        
        if (transcript == null || prompt == null) {
            result.error("INVALID_ARGS", "transcript and prompt required", null)
            return
        }
        
        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    val response = runTextInference(transcript, prompt)
                    mainHandler.post { result.success(mapOf("success" to true, "response" to response)) }
                } catch (e: Exception) {
                    mainHandler.post { result.error("INFERENCE_FAILED", e.message, null) }
                }
            }
        }
    }
    
    private fun chatStream(call: MethodCall, result: Result) {
        val transcript = call.argument<String>("transcript")
        val prompt = call.argument<String>("prompt")
        
        if (transcript == null || prompt == null) {
            result.error("INVALID_ARGS", "transcript and prompt required", null)
            return
        }
        
        if (eventSink == null) {
            result.error("NO_LISTENER", "No event sink registered. Listen to stream first.", null)
            return
        }
        
        // Return success immediately to indicate processing started
        result.success(true)
        
        GemmaRuntime.scope.launch {
            mutex.withLock {
                try {
                    runTextInferenceStream(transcript, prompt)
                } catch (e: Exception) {
                    mainHandler.post { eventSink?.error("INFERENCE_FAILED", e.message, null) }
                }
            }
        }
    }
    
    // ========== CORE INFERENCE ==========
    
    private suspend fun doTranscribe(audioPath: String, systemInstruction: String?, promptInstruction: String?): String {
        val modelFile = ModelStore.ensureModelReady(context)
        val audioBytes = File(audioPath).also { validateWav(it) }.readBytes()
        val transcriptionTimeoutSeconds = computeTranscriptionTimeoutSeconds(audioBytes.size)
        
        val sysMsg = systemInstruction ?: TRANSCRIPTION_SYSTEM
        val config = ConversationConfig(
            systemInstruction = Contents.of(sysMsg),
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.1)
        )
        
        val promptText = promptInstruction ?: "Transcribe the audio verbatim from this audio clip. Preserve speaker wording, keep mixed-language code switching, romanize non-English speech into English letters only, and output only the transcript."
        
        val message = Message.of(listOf(
            Content.AudioBytes(audioBytes),
            Content.Text(promptText)
        ))
        
        Log.d(
            TAG,
            "Transcription timeout budget: ${transcriptionTimeoutSeconds}s for audioBytes=${audioBytes.size}",
        )
        return withEngineRetry(modelFile) { eng ->
            runInference(
                engine = eng,
                config = config,
                message = message,
                timeoutSeconds = transcriptionTimeoutSeconds,
            )
        }
    }
    
    private suspend fun doSummarize(transcript: String, systemInstruction: String?, queryInstruction: String?): Map<String, Any?> {
        val modelFile = ModelStore.ensureModelReady(context)
        
        val sysMsg = systemInstruction ?: SUMMARIZATION_SYSTEM
        val config = ConversationConfig(
            systemInstruction = Contents.of(sysMsg),
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.3)
        )
        
        Log.d(TAG, "Transcript for summary (length=${transcript.length}): ${transcript.take(100)}...")
        
        if (transcript.isBlank() || transcript.length < 5) {
             Log.w(TAG, "Transcript is empty or too short. Skipping summarization.")
             return mapOf(
                 "title" to "Error: Empty Transcript",
                 "summary" to "The audio could not be transcribed or was silent.",
                 "keyPoints" to emptyList<String>(),
                 "actionItems" to "None"
             )
        }

        val userPromptPrefix = queryInstruction ?: "Analyze the following transcript and provide the summary, title, key points, and action items as requested:"
        val prompt = "$userPromptPrefix\n\n<TRANSCRIPT>\n$transcript\n</TRANSCRIPT>"
        val response = withEngineRetry(modelFile) { eng ->
            runInference(eng, config, Message.of(prompt))
        }
        
        Log.d(TAG, "Summary response: ${response.take(200)}...")
        return parseAnalysis(response)
    }
    
    private suspend fun runAudioInference(audioPath: String, prompt: String): String {
        val modelFile = ModelStore.ensureModelReady(context)
        val audioBytes = File(audioPath).also { validateWav(it) }.readBytes()
        
        val config = ConversationConfig(
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.3)
        )
        
        val message = Message.of(listOf(
            Content.AudioBytes(audioBytes),
            Content.Text(prompt)
        ))
        
        return withEngineRetry(modelFile) { eng -> runInference(eng, config, message) }
    }

    private suspend fun runTextInference(transcript: String, userPrompt: String): String {
        val modelFile = ModelStore.ensureModelReady(context)
        
        val config = ConversationConfig(
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.7) // Higher temp for creative chat
        )
        
        val fullPrompt = "Context (Transcript):\n$transcript\n\nUser Question: $userPrompt"
        
        val message = Message.of(fullPrompt)
        
        return withEngineRetry(modelFile) { eng -> runInference(eng, config, message) }
    }
    
    private suspend fun runInference(
        engine: Engine,
        config: ConversationConfig,
        message: Message,
        timeoutSeconds: Long = 300,
    ): String =
        withContext(Dispatchers.IO) {
            val sb = StringBuilder()
            val latch = java.util.concurrent.CountDownLatch(1)
            var error: String? = null
            
            engine.createConversation(config).use { conv ->
                conv.sendMessageAsync(message, object : MessageCallback {
                    override fun onMessage(msg: Message) { 
                        sb.append(msg.toString()) 
                    }
                    override fun onDone() { latch.countDown() }
                    override fun onError(t: Throwable) { error = t.message; latch.countDown() }
                })
                
                if (!latch.await(timeoutSeconds, java.util.concurrent.TimeUnit.SECONDS)) {
                    throw Exception("Inference Timeout after ${timeoutSeconds}s")
                }
                error?.let { throw Exception(it) }
            }
            
            sb.toString().trim()
        }

    private fun computeTranscriptionTimeoutSeconds(audioByteCount: Int): Long {
        // Converted WAV is 16kHz mono 16-bit PCM => ~32KB/sec.
        val approxDurationSeconds = (audioByteCount / 32_000.0).toLong().coerceAtLeast(1L)
        // Keep floor for short clips; scale up for longer recordings.
        return (approxDurationSeconds * 3).coerceIn(300L, 1200L)
    }
        
    private suspend fun runTextInferenceStream(transcript: String, userPrompt: String) {
        val modelFile = ModelStore.ensureModelReady(context)
        
        val config = ConversationConfig(
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.7)
        )
        
        val fullPrompt = "Context (Transcript):\n$transcript\n\nUser Question: $userPrompt"
        val message = Message.of(fullPrompt)
        
        withEngineRetry(modelFile) { eng ->
            runInferenceStream(eng, config, message)
        }
    }

    private suspend fun <T> withEngineRetry(modelFile: File, block: suspend (Engine) -> T): T {
        try {
            return block(GemmaRuntime.getEngine(context, modelFile))
        } catch (e: Exception) {
            if (!GemmaRuntime.shouldFallbackToCpu(e)) {
                throw e
            }
            Log.w(TAG, "Inference failed with GPU backend, retrying on CPU", e)
            GemmaRuntime.forceCpuFallback()
            return block(GemmaRuntime.getEngine(context, modelFile))
        }
    }

    private suspend fun runInferenceStream(engine: Engine, config: ConversationConfig, message: Message) = 
        withContext(Dispatchers.IO) {
             val latch = java.util.concurrent.CountDownLatch(1)
             
             engine.createConversation(config).use { conv ->
                conv.sendMessageAsync(message, object : MessageCallback {
                    override fun onMessage(msg: Message) { 
                        // Stream chunk to Flutter
                        val text = msg.toString()
                        if (text.isNotEmpty()) {
                            mainHandler.post { eventSink?.success(text) }
                        }
                    }
                    override fun onDone() { 
                        mainHandler.post { eventSink?.success("[DONE]") } // Signal completion
                        latch.countDown() 
                    }
                    override fun onError(t: Throwable) { 
                         mainHandler.post { eventSink?.error("GEN_ERROR", t.message, null) }
                         latch.countDown() 
                    }
                })
                
                if (!latch.await(90, java.util.concurrent.TimeUnit.SECONDS)) {
                    mainHandler.post { eventSink?.error("TIMEOUT", "Generation timed out", null) }
                }
             }
        }
    
    private fun validateWav(file: File) {
        val bytes = file.readBytes()
        require(bytes.size >= 44) { "Invalid WAV: too short" }
        require(String(bytes.copyOfRange(0, 4)) == "RIFF") { "Invalid WAV header" }
        require(String(bytes.copyOfRange(8, 12)) == "WAVE") { "Invalid WAV format" }
    }

    private fun parseAnalysis(response: String): Map<String, Any?> {
        val result = mutableMapOf<String, Any?>(
            "title" to null,
            "summary" to null,
            "keyPoints" to emptyList<String>(),
            "actionItems" to "None"
        )
        
        val lines = response.lines()
        var section = ""
        var titleLine: String? = null
        val summaryLines = mutableListOf<String>()
        val keyPointLines = mutableListOf<String>()
        val actionLines = mutableListOf<String>()
        
        for (line in lines) {
            val trimmed = line.trim()
            val lower = trimmed.lowercase()
            
            // Standardized Markdown Header Detection (More permissive)
            if (lower.contains("## title") || lower.contains("**title**") || lower.startsWith("title:") || lower == "title") { section = "title"; continue }
            if (lower.contains("## summary") || lower.contains("**summary**") || lower.startsWith("summary:") || lower == "summary") { section = "summary"; continue }
            if (lower.contains("## key points") || lower.contains("**key points**") || lower.startsWith("key points:") || lower == "key points") { section = "keypoints"; continue }
            if (lower.contains("## action items") || lower.contains("**action items**") || lower.startsWith("action items:") || lower == "action items") { section = "actions"; continue }
            
            if (trimmed.isBlank()) continue
            if (trimmed.startsWith("##")) continue // Skip other headers
            
            val cleaned = trimmed.removePrefix("-").removePrefix("•").removePrefix("*").trim()
            if (cleaned.length < 2) continue // Relaxed length check
            
            when (section) {
                "title" -> if (titleLine == null) titleLine = cleaned
                "summary" -> summaryLines.add(cleaned)
                "keypoints" -> keyPointLines.add(cleaned)
                "actions" -> if (!cleaned.equals("none", true)) actionLines.add(cleaned)
                else -> {
                    // Fallback: If no section header found yet, treat first few valid lines as Summary 
                    // (LLM sometimes forgets headers for short queries)
                    if (section.isEmpty() && summaryLines.size < 3) {
                        summaryLines.add(cleaned)
                    }
                }
            }
        }
        
        // Title Fallback: Use first key point or summary snippet if missing
        if (titleLine == null) {
            if (keyPointLines.isNotEmpty()) titleLine = keyPointLines.first().take(50)
            else if (summaryLines.isNotEmpty()) titleLine = summaryLines.first().take(40)
        }
        
        // Title
        result["title"] = titleLine?.take(100)
        
        // Build paragraph summary
        if (summaryLines.isNotEmpty()) {
            result["summary"] = summaryLines.joinToString(" ")
        } else {
             // Fallback if absolutely no summary
             result["summary"] = "No summary generated."
        }
        
        // Key points as list
        if (keyPointLines.isNotEmpty()) {
            result["keyPoints"] = keyPointLines.take(5)
        }
        
        // Action items
        result["actionItems"] = if (actionLines.isNotEmpty()) {
            actionLines.joinToString("\n• ", prefix = "• ")
        } else "None"
        
        Log.d(TAG, "Parsed: title=$titleLine, summary=${summaryLines.size}, keyPoints=${keyPointLines.size}")
        return result
    }
    
    private fun dispose(result: Result) {
        GemmaRuntime.scope.launch {
            try {
                GemmaRuntime.reset()
                ModelStore.reset()
                mainHandler.post { result.success(true) }
            } catch (e: Exception) {
                mainHandler.post { result.error("DISPOSE_FAILED", e.message, null) }
            }
        }
    }
}
