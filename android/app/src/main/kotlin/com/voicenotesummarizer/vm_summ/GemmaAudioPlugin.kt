package com.voicenotesummarizer.vm_summ

import android.content.Context
import android.util.Log
import com.google.ai.edge.litertlm.Content
import com.google.ai.edge.litertlm.ConversationConfig
import com.google.ai.edge.litertlm.Engine
import com.google.ai.edge.litertlm.Message
import com.google.ai.edge.litertlm.MessageCallback
import com.google.ai.edge.litertlm.SamplerConfig
import io.flutter.embedding.engine.plugins.FlutterPlugin
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
 * Gemma 3n Audio Plugin - Uses single-flight initialization pattern.
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
        private const val TAG = "GemmaAudioPlugin"
        
        // System prompts
        private const val TRANSCRIPTION_SYSTEM = """DO NOT TRANSLATE. ROMANIZE ONLY.

You transcribe audio verbatim using ONLY English letters (A-Z).

RULES:
1. Write EXACTLY what is spoken. Do not change words.
2. Romanize non-English: "میں ٹھیک ہوں" = "Main theek hoon" (NOT "I am fine")
3. Keep code-switching: "Meeting hai at 3" stays as "Meeting hai at 3"
4. No summaries. No explanations. No corrections.

FORBIDDEN - never output these translations:
- Shukriya → Thank you (WRONG)
- Main aa raha hoon → I am coming (WRONG)  
- Kya haal hai → How are you (WRONG)

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
        Log.d(TAG, "Plugin attached")
    }
    
    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
        // Cleanup handled by GemmaRuntime singleton
    }
    
    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "initialize" -> initialize(result)
            "transcribe" -> transcribe(call, result)
            "transcribeAndSummarize" -> transcribeAndSummarize(call, result)
            "generateResponse" -> generateResponse(call, result)
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
    private fun initialize(result: Result) {
        GemmaRuntime.scope.launch {
            try {
                Log.d(TAG, "Initialize called - using single-flight pattern")
                
                // Step 1: Ensure model is ready (atomic copy)
                val modelFile = ModelStore.ensureModelReady(context)
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
        val audioPath = call.argument<String>("path")
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
                    mainHandler.post { result.success(transcript) }
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
    
    private fun generateResponse(call: MethodCall, result: Result) {
        val audioPath = call.argument<String>("path")
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
    
    // ========== CORE INFERENCE ==========
    
    private suspend fun doTranscribe(audioPath: String, systemInstruction: String?, promptInstruction: String?): String {
        val modelFile = ModelStore.ensureModelReady(context)
        val eng = GemmaRuntime.getEngine(context, modelFile)
        val audioBytes = File(audioPath).also { validateWav(it) }.readBytes()
        
        val sysMsg = systemInstruction ?: TRANSCRIPTION_SYSTEM
        val config = ConversationConfig(
            systemMessage = Message.of(sysMsg),
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.1)
        )
        
        val promptText = promptInstruction ?: "Transcribe the audio verbatim.\nIMPORTANT: Do NOT translate. Romanize non-English speech into English letters only.\nOutput ONLY the transcript."
        
        val message = Message.of(listOf(
            Content.AudioBytes(audioBytes),
            Content.Text(promptText)
        ))
        
        return runInference(eng, config, message)
    }
    
    private suspend fun doSummarize(transcript: String, systemInstruction: String?, queryInstruction: String?): Map<String, Any?> {
        val modelFile = ModelStore.ensureModelReady(context)
        val eng = GemmaRuntime.getEngine(context, modelFile)
        
        val sysMsg = systemInstruction ?: SUMMARIZATION_SYSTEM
        val config = ConversationConfig(
            systemMessage = Message.of(sysMsg),
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.3)
        )
        
        val userPromptPrefix = queryInstruction ?: "Analyze this transcript:"
        val prompt = "$userPromptPrefix\n\n$transcript"
        val response = runInference(eng, config, Message.of(prompt))
        
        Log.d(TAG, "Summary response: ${response.take(200)}...")
        return parseAnalysis(response)
    }
    
    private suspend fun runAudioInference(audioPath: String, prompt: String): String {
        val modelFile = ModelStore.ensureModelReady(context)
        val eng = GemmaRuntime.getEngine(context, modelFile)
        val audioBytes = File(audioPath).also { validateWav(it) }.readBytes()
        
        val config = ConversationConfig(
            samplerConfig = SamplerConfig(topK = 40, topP = 0.9, temperature = 0.3)
        )
        
        val message = Message.of(listOf(
            Content.AudioBytes(audioBytes),
            Content.Text(prompt)
        ))
        
        return runInference(eng, config, message)
    }
    
    private suspend fun runInference(engine: Engine, config: ConversationConfig, message: Message): String = 
        withContext(Dispatchers.IO) {
            val sb = StringBuilder()
            val latch = java.util.concurrent.CountDownLatch(1)
            var error: String? = null
            
            engine.createConversation(config).use { conv ->
                conv.sendMessageAsync(message, object : MessageCallback {
                    override fun onMessage(msg: Message) { sb.append(msg.toString()) }
                    override fun onDone() { latch.countDown() }
                    override fun onError(t: Throwable) { error = t.message; latch.countDown() }
                })
                
                if (!latch.await(90, java.util.concurrent.TimeUnit.SECONDS)) {
                    throw Exception("Timeout")
                }
                error?.let { throw Exception(it) }
            }
            
            sb.toString().trim()
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
            
            // Standardized Markdown Header Detection
            if (lower.startsWith("## title") || lower.startsWith("**title**") || lower.startsWith("title:")) { section = "title"; continue }
            if (lower.startsWith("## summary") || lower.startsWith("**summary**") || lower.startsWith("summary:")) { section = "summary"; continue }
            if (lower.startsWith("## key points") || lower.startsWith("**key points**") || lower.startsWith("key points:")) { section = "keypoints"; continue }
            if (lower.startsWith("## action items") || lower.startsWith("**action items**") || lower.startsWith("action items:")) { section = "actions"; continue }
            
            if (trimmed.isBlank()) continue
            if (trimmed.startsWith("##")) continue // Skip other headers
            
            val cleaned = trimmed.removePrefix("-").removePrefix("•").removePrefix("*").trim()
            if (cleaned.length < 2) continue // Relaxed length check
            
            when (section) {
                "title" -> if (titleLine == null) titleLine = cleaned
                "summary" -> summaryLines.add(cleaned)
                "keypoints" -> keyPointLines.add(cleaned)
                "actions" -> if (!cleaned.equals("none", true)) actionLines.add(cleaned)
            }
        }
        
        // Title
        result["title"] = titleLine?.take(100)
        
        // Build paragraph summary
        if (summaryLines.isNotEmpty()) {
            result["summary"] = summaryLines.joinToString(" ")
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
