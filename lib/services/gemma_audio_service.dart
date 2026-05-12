import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

const String kBundledGemmaAssetName = 'gemma-4-E2B-it.litertlm';
const String kBundledGemmaModelName = 'gemma-4-E2B.litertlm';
const String kBundledGemmaDisplayName = 'Gemma 4 E2B';

/// Result from Gemma 4 audio processing.
class GemmaAudioResult {
  /// Raw response from the model
  final String response;

  /// Extracted transcript (if structured output was requested)
  final String? transcript;

  /// Generated title for the recording
  final String? title;

  /// Extracted summary (if structured output was requested)
  final String? summary;

  /// Extracted key points (if structured output was requested)
  final List<String> keyPoints;

  /// Extracted action items (if structured output was requested)
  final String? actionItems;

  GemmaAudioResult({
    required this.response,
    this.transcript,
    this.title,
    this.summary,
    this.keyPoints = const [],
    this.actionItems,
  });

  factory GemmaAudioResult.fromMap(Map<dynamic, dynamic> map) {
    return GemmaAudioResult(
      response: map['response'] as String? ?? '',
      transcript: map['transcript'] as String?,
      title: map['title'] as String?,
      summary: map['summary'] as String?,
      keyPoints:
          (map['keyPoints'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      actionItems: map['actionItems'] as String?,
    );
  }

  /// Check if we have structured output
  bool get hasStructuredOutput =>
      transcript != null || summary != null || keyPoints.isNotEmpty;

  static GemmaAudioResult parse(String response, {required String transcript}) {
    final lines = response.split(RegExp(r'\r?\n'));
    var section = '';
    String? titleLine;
    final summaryLines = <String>[];
    final keyPointLines = <String>[];
    final actionLines = <String>[];

    for (final line in lines) {
      final trimmed = line.trim();
      final lower = trimmed.toLowerCase();

      if (lower.contains('## title') ||
          lower.contains('**title**') ||
          lower.startsWith('title:') ||
          lower == 'title') {
        section = 'title';
        continue;
      }
      if (lower.contains('## summary') ||
          lower.contains('**summary**') ||
          lower.startsWith('summary:') ||
          lower == 'summary') {
        section = 'summary';
        continue;
      }
      if (lower.contains('## key points') ||
          lower.contains('**key points**') ||
          lower.startsWith('key points:') ||
          lower == 'key points') {
        section = 'keypoints';
        continue;
      }
      if (lower.contains('## action items') ||
          lower.contains('**action items**') ||
          lower.startsWith('action items:') ||
          lower == 'action items') {
        section = 'actions';
        continue;
      }

      if (trimmed.isEmpty || trimmed.startsWith('##')) continue;

      final cleaned = trimmed.replaceFirst(RegExp(r'^[•\-\*]\s*'), '').trim();
      if (cleaned.isEmpty) continue;

      switch (section) {
        case 'title':
          titleLine ??= cleaned;
          break;
        case 'summary':
          summaryLines.add(cleaned);
          break;
        case 'keypoints':
          keyPointLines.add(cleaned);
          break;
        case 'actions':
          if (!cleaned.toLowerCase().contains('none')) {
            actionLines.add(cleaned);
          }
          break;
        default:
          if (summaryLines.length < 3) {
            summaryLines.add(cleaned);
          }
      }
    }

    titleLine ??= summaryLines.isNotEmpty
        ? summaryLines.first.length > 50
              ? summaryLines.first.substring(0, 50)
              : summaryLines.first
        : transcript.split(RegExp(r'\s+')).take(6).join(' ');

    final title = titleLine.trim();

    return GemmaAudioResult(
      response: response,
      transcript: transcript,
      title: title.isNotEmpty ? title : null,
      summary: summaryLines.isNotEmpty
          ? summaryLines.join(' ')
          : 'No summary generated.',
      keyPoints: keyPointLines.take(5).toList(),
      actionItems: actionLines.isNotEmpty ? actionLines.join('\n') : 'None',
    );
  }

  @override
  String toString() {
    if (hasStructuredOutput) {
      return 'GemmaAudioResult(transcript: ${transcript?.substring(0, (transcript?.length ?? 0).clamp(0, 50))}..., summary: ${summary?.substring(0, (summary?.length ?? 0).clamp(0, 50))}...)';
    }
    return 'GemmaAudioResult(response: ${response.substring(0, response.length.clamp(0, 100))}...)';
  }
}

/// Model download progress information.
class ModelDownloadProgress {
  final String modelName;
  final int bytesDownloaded;
  final int totalBytes;
  final int progress; // 0-100, or -1 if unknown
  final String status; // 'downloading', 'complete', 'error'
  final String? error;

  ModelDownloadProgress({
    required this.modelName,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.progress,
    required this.status,
    this.error,
  });

  factory ModelDownloadProgress.fromMap(Map<dynamic, dynamic> map) {
    return ModelDownloadProgress(
      modelName: map['modelName'] as String? ?? '',
      bytesDownloaded: (map['bytesDownloaded'] as num?)?.toInt() ?? 0,
      totalBytes: (map['totalBytes'] as num?)?.toInt() ?? 0,
      progress: (map['progress'] as num?)?.toInt() ?? -1,
      status: map['status'] as String? ?? 'unknown',
      error: map['error'] as String?,
    );
  }

  bool get isComplete => status == 'complete';
  bool get hasError => status == 'error';
  bool get isDownloading => status == 'downloading';

  String get formattedProgress {
    if (progress >= 0) {
      return '$progress%';
    }
    if (totalBytes > 0) {
      final percent = (bytesDownloaded / totalBytes * 100)
          .clamp(0, 100)
          .round();
      return '$percent%';
    }
    final mb = bytesDownloaded / (1024 * 1024);
    return '${mb.toStringAsFixed(1)} MB';
  }
}

/// Available Gemma model information.
class GemmaModelInfo {
  final String name;
  final String filename;
  final String? bundledAsset;
  final bool downloaded;
  final String description;
  final String estimatedSize;

  GemmaModelInfo({
    required this.name,
    required this.filename,
    this.bundledAsset,
    required this.downloaded,
    required this.description,
    required this.estimatedSize,
  });

  factory GemmaModelInfo.fromMap(Map<dynamic, dynamic> map) {
    return GemmaModelInfo(
      name: map['name'] as String? ?? '',
      filename: map['filename'] as String? ?? '',
      bundledAsset: map['bundledAsset'] as String?,
      downloaded: map['downloaded'] as bool? ?? false,
      description: map['description'] as String? ?? '',
      estimatedSize: map['estimatedSize'] as String? ?? '',
    );
  }
}

/// Service for Gemma 4 multimodal audio inference.
///
/// Provides:
/// - Model downloading and management
/// - Audio transcription
/// - Audio transcription + summarization
/// - Custom audio + text prompts
///
/// Note: Currently Android-only. iOS falls back to Whisper + LFM2.
class GemmaAudioService {
  static const _audioChannel = MethodChannel(
    'com.voicenotesummarizer/gemma_audio',
  );
  static const _modelChannel = MethodChannel(
    'com.voicenotesummarizer/gemma_model_manager',
  );
  static const _progressChannel = EventChannel(
    'com.voicenotesummarizer/gemma_model_manager/progress',
  );
  static const _streamChannel = EventChannel(
    'com.voicenotesummarizer/gemma_audio/chat_stream',
  );

  bool _initialized = false;
  String? _modelPath;
  StreamSubscription<dynamic>? _progressSubscription;

  static const int _bytesPerSecond16kMonoPcm = 32000;

  /// Whether the service is initialized with a loaded model
  bool get isInitialized => _initialized;

  /// Path to the currently loaded model
  String? get modelPath => _modelPath;

  /// Check if we're on a supported platform (Android)
  static bool get isPlatformSupported => Platform.isAndroid;

  LongAudioConfig longAudioConfig = const LongAudioConfig();

  // ============================================================
  // Model Management
  // ============================================================

  /// Get list of available Gemma models.
  Future<List<GemmaModelInfo>> getAvailableModels() async {
    if (!isPlatformSupported) return [];

    try {
      final result = await _modelChannel.invokeMethod('getAvailableModels');
      final list = result as List<dynamic>;
      return list.map((e) => GemmaModelInfo.fromMap(e as Map)).toList();
    } on PlatformException catch (e) {
      debugPrint('GemmaAudioService: Failed to get models: ${e.message}');
      return [];
    }
  }

  /// Check if a specific model is downloaded.
  Future<bool> isModelDownloaded({String? modelName}) async {
    if (!isPlatformSupported) return false;

    try {
      final result = await _modelChannel.invokeMethod('isModelDownloaded', {
        'modelName': modelName ?? kBundledGemmaModelName,
      });
      return (result as Map)['downloaded'] as bool? ?? false;
    } on PlatformException catch (e) {
      debugPrint('GemmaAudioService: Failed to check model: ${e.message}');
      return false;
    }
  }

  /// Get the local path for a model.
  Future<String> getModelPath({String? modelName}) async {
    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }

    try {
      final result = await _modelChannel.invokeMethod('getModelPath', {
        'modelName': modelName ?? kBundledGemmaModelName,
      });
      return result as String;
    } on PlatformException catch (e) {
      throw Exception('Failed to get model path: ${e.message}');
    }
  }

  /// Copy the bundled model from APK assets to app storage.
  /// This is the primary method for loading the model since it's bundled in the APK.
  Future<String> copyBundledModel({
    void Function(ModelDownloadProgress)? onProgress,
  }) async {
    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }

    // Set up progress listener if callback provided
    if (onProgress != null) {
      _progressSubscription?.cancel();
      _progressSubscription = _progressChannel.receiveBroadcastStream().listen((
        event,
      ) {
        if (event is Map) {
          onProgress(ModelDownloadProgress.fromMap(event));
        }
      });
    }

    try {
      debugPrint('GemmaAudioService: Copying bundled model from assets...');
      final result = await _modelChannel.invokeMethod('copyBundledModel', {
        'assetName': kBundledGemmaAssetName,
        'destName': kBundledGemmaModelName,
      });

      final map = result as Map;
      if (map['success'] == true) {
        final path = map['path'] as String;
        final alreadyExists = map['alreadyExists'] as bool? ?? false;
        debugPrint(
          'GemmaAudioService: Model ${alreadyExists ? "already exists" : "copied"} at $path',
        );
        return path;
      } else {
        throw Exception('Copy failed');
      }
    } on PlatformException catch (e) {
      throw Exception('Model copy failed: ${e.message}');
    } finally {
      _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  /// Download a Gemma model from HuggingFace.
  ///
  /// [modelName] - The model filename (e.g., 'gemma-4-E2B.litertlm')
  /// [hfToken] - Optional HuggingFace token for authenticated downloads
  /// [onProgress] - Callback for download progress updates
  Future<String> downloadModel({
    String? modelName,
    String? hfToken,
    void Function(ModelDownloadProgress)? onProgress,
  }) async {
    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }

    // Set up progress listener if callback provided
    if (onProgress != null) {
      _progressSubscription?.cancel();
      _progressSubscription = _progressChannel.receiveBroadcastStream().listen((
        event,
      ) {
        if (event is Map) {
          onProgress(ModelDownloadProgress.fromMap(event));
        }
      });
    }

    try {
      final result = await _modelChannel.invokeMethod('downloadModel', {
        'modelName': modelName ?? kBundledGemmaModelName,
        if (hfToken != null) 'hfToken': hfToken,
      });

      final map = result as Map;
      if (map['success'] == true) {
        return map['path'] as String;
      } else {
        throw Exception('Download failed');
      }
    } on PlatformException catch (e) {
      throw Exception('Model download failed: ${e.message}');
    } finally {
      _progressSubscription?.cancel();
      _progressSubscription = null;
    }
  }

  /// Delete a downloaded model.
  Future<bool> deleteModel({String? modelName}) async {
    if (!isPlatformSupported) return false;

    try {
      final result = await _modelChannel.invokeMethod('deleteModel', {
        'modelName': modelName ?? kBundledGemmaModelName,
      });
      return (result as Map)['deleted'] as bool? ?? false;
    } on PlatformException catch (e) {
      debugPrint('GemmaAudioService: Failed to delete model: ${e.message}');
      return false;
    }
  }

  // ============================================================
  // Inference
  // ============================================================

  /// Initialize the bundled Gemma 4 model for inference.
  ///
  /// [modelPath] - Path to the .task model file
  Future<void> initialize(String modelPath) async {
    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }

    debugPrint('GemmaAudioService: Initializing with model: $modelPath');

    try {
      final result = await _audioChannel.invokeMethod('initialize', {
        'modelPath': modelPath,
      });

      final map = result as Map;
      if (map['success'] == true) {
        _initialized = true;
        _modelPath = modelPath;
        debugPrint('GemmaAudioService: Initialized successfully');
      } else {
        throw Exception('Initialization failed');
      }
    } on PlatformException catch (e) {
      _initialized = false;
      _modelPath = null;
      throw Exception('Failed to initialize Gemma: ${e.message}');
    }
  }

  /// Initialize with auto-copy of bundled model if not present.
  ///
  /// Copies the bundled E2B model from assets if not already copied, then initializes.
  Future<void> initializeWithBundledModel({
    void Function(ModelDownloadProgress)? onProgress,
  }) async {
    // Skip if already initialized
    if (_initialized) {
      debugPrint('GemmaAudioService: Already initialized, skipping');
      return;
    }

    const modelName = kBundledGemmaModelName;

    // Check if already copied
    final downloaded = await isModelDownloaded(modelName: modelName);

    String path;
    if (!downloaded) {
      debugPrint('GemmaAudioService: Model not found, copying from assets...');
      path = await copyBundledModel(onProgress: onProgress);
    } else {
      path = await getModelPath(modelName: modelName);
    }

    onProgress?.call(
      ModelDownloadProgress(
        modelName: modelName,
        bytesDownloaded: 0,
        totalBytes: 0,
        progress: -1,
        status: 'initializing',
      ),
    );
    await initialize(path);
  }

  /// Transcribe audio to text.
  ///
  /// [audioFile] - Mono WAV file (≤30s for optimal results)
  /// [language] - Optional language hint (e.g., 'Hindi', 'Urdu', 'English')
  Future<GemmaAudioResult> transcribe(
    File audioFile, {
    String? language,
  }) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod('transcribe', {
        'audioPath': audioFile.path,
        if (language != null) 'language': language,
      });

      return GemmaAudioResult.fromMap(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Transcription failed: ${e.message}');
    }
  }

  /// Transcribe a specific time range from an audio file.
  Future<GemmaAudioResult> transcribeSegment(
    File audioFile, {
    required int segmentIndex,
    required int segmentCount,
  }) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod('transcribeSegment', {
        'audioPath': audioFile.path,
        'segmentIndex': segmentIndex,
        'segmentCount': segmentCount,
      });
      return GemmaAudioResult.fromMap(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Segment transcription failed: ${e.message}');
    }
  }

  /// Transcribe and summarize audio in one pass.
  ///
  /// This is the recommended method for voice note processing.
  /// Returns structured output with transcript, summary, key points, and action items.
  ///
  /// [audioFile] - Mono WAV file (≤30s for optimal results)
  /// [language] - Optional language hint (e.g., 'Hindi', 'Urdu', 'English')
  Future<GemmaAudioResult> transcribeAndSummarize(
    File audioFile, {
    String? language,
    String? systemInstruction,
    String? queryInstruction,
    String? transcriptionSystem,
    String? transcriptionPrompt,
  }) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod(
        'transcribeAndSummarize',
        {
          'path': audioFile.path,
          if (language != null) 'language': language,
          if (systemInstruction != null) 'systemInstruction': systemInstruction,
          if (queryInstruction != null) 'queryInstruction': queryInstruction,
          if (transcriptionSystem != null)
            'transcriptionSystem': transcriptionSystem,
          if (transcriptionPrompt != null)
            'transcriptionPrompt': transcriptionPrompt,
        },
      );

      return GemmaAudioResult.fromMap(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Transcription and summarization failed: ${e.message}');
    }
  }

  /// Summarize an existing transcript with optional custom instructions.
  Future<GemmaAudioResult> summarizeTranscript(
    String transcript, {
    String? systemInstruction,
    String? queryInstruction,
  }) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod('summarizeTranscript', {
        'transcript': transcript,
        if (systemInstruction != null) 'systemInstruction': systemInstruction,
        if (queryInstruction != null) 'queryInstruction': queryInstruction,
      });
      return GemmaAudioResult.fromMap(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Transcript summarization failed: ${e.message}');
    }
  }

  /// Process audio with a custom prompt.
  ///
  /// [audioFile] - Mono WAV file (≤30s for optimal results)
  /// [prompt] - Custom prompt for the model
  Future<GemmaAudioResult> generateResponse(
    File audioFile,
    String prompt,
  ) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod('generateResponse', {
        'audioPath': audioFile.path,
        'prompt': prompt,
      });

      return GemmaAudioResult.fromMap(result as Map);
    } on PlatformException catch (e) {
      throw Exception('Response generation failed: ${e.message}');
    }
  }

  /// Chat with a note using its transcript.
  ///
  /// [transcript] - The full transcript of the note
  /// [userMessage] - The user's question or message
  Future<String> chatWithTranscript(
    String transcript,
    String userMessage,
  ) async {
    await _ensureReady();

    try {
      final result = await _audioChannel.invokeMethod('chat', {
        'transcript': transcript,
        'prompt': userMessage,
      });

      final map = result as Map;
      return map['response'] as String;
    } on PlatformException catch (e) {
      throw Exception('Chat failed: ${e.message}');
    }
  }

  /// Chat with a note (Streaming).
  ///
  /// Returns a stream of text chunks.
  Stream<String> chatWithTranscriptStream(
    String transcript,
    String userMessage,
  ) async* {
    await _ensureReady();

    final controller = StreamController<String>();

    // Subscribe to event channel
    final subscription = _streamChannel.receiveBroadcastStream().listen(
      (event) {
        if (event == '[DONE]') {
          controller.close();
        } else if (event is String) {
          controller.add(event);
        }
      },
      onError: (error) {
        controller.addError(error);
      },
    );

    try {
      // Trigger generation
      await _audioChannel.invokeMethod('chatStream', {
        'transcript': transcript,
        'prompt': userMessage,
      });
    } catch (e) {
      controller.addError(e);
      await subscription.cancel();
      await controller.close();
      return;
    }

    // Yield from controller
    yield* controller.stream;

    // Cleanup when stream completes or cancelled
    // Note: The controller is closed by [DONE] or error
  }

  /// Ensure service is initialized, checking native side if needed.
  Future<void> _ensureReady() async {
    if (_initialized) return;

    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }

    try {
      final isNativeReady = await _audioChannel.invokeMethod('isInitialized');
      if (isNativeReady == true) {
        _initialized = true;
        // Ideally we'd sync _modelPath here too, but it's optional
        return;
      }
    } catch (e) {
      debugPrint('Validation check failed: $e');
    }

    throw StateError(
      'GemmaAudioService not initialized. Call initialize() first.',
    );
  }

  /// Process long recordings by chunking the transcript when needed.
  Future<GemmaAudioResult> transcribeAndSummarizeLongAudio(
    File audioFile, {
    String? language,
    String? systemInstruction,
    String? queryInstruction,
    String? transcriptionSystem,
    String? transcriptionPrompt,
    void Function(LongAudioPhaseUpdate update)? onPhaseUpdate,
  }) async {
    await _ensureReady();

    onPhaseUpdate?.call(const LongAudioPhaseUpdate(phase: 'transcribe'));
    final fullTranscript = await _transcribeWithHybridStrategy(
      audioFile: audioFile,
      language: language,
      onPhaseUpdate: onPhaseUpdate,
    );
    if (fullTranscript.trim().length < 10) {
      return GemmaAudioResult(
        response: fullTranscript,
        transcript: fullTranscript,
        summary: 'No summary generated.',
      );
    }

    onPhaseUpdate?.call(const LongAudioPhaseUpdate(phase: 'summarize'));
    return _summarizeFromTranscript(
      fullTranscript,
      systemInstruction: systemInstruction,
      queryInstruction: queryInstruction,
    );
  }

  Future<String> _transcribeWithHybridStrategy({
    required File audioFile,
    String? language,
    void Function(LongAudioPhaseUpdate update)? onPhaseUpdate,
  }) async {
    final fileSize = await audioFile.length();
    final estimatedSeconds = fileSize / _bytesPerSecond16kMonoPcm;
    final shouldForceSegment =
        estimatedSeconds >= longAudioConfig.forceSegmentAtSeconds;

    if (!shouldForceSegment) {
      try {
        final oneShot = await transcribe(audioFile, language: language);
        return (oneShot.transcript ?? oneShot.response).trim();
      } catch (e) {
        if (!_isTimeoutError(e)) rethrow;
        debugPrint(
          'GemmaAudioService: One-shot transcription timed out, retrying with segment mode.',
        );
      }
    }

    return _transcribeBySegments(
      audioFile: audioFile,
      onPhaseUpdate: onPhaseUpdate,
    );
  }

  Future<String> _transcribeBySegments({
    required File audioFile,
    void Function(LongAudioPhaseUpdate update)? onPhaseUpdate,
  }) async {
    final segments = await _splitWavIntoSegments(audioFile);
    if (segments.isEmpty) {
      throw Exception('Long-audio segment split produced no segments.');
    }

    final transcripts = <String>[];
    for (var i = 0; i < segments.length; i++) {
      final segment = segments[i];
      onPhaseUpdate?.call(
        LongAudioPhaseUpdate(
          phase: 'transcribe_segment',
          segmentIndex: i + 1,
          segmentCount: segments.length,
        ),
      );
      final t = await _transcribeSegmentWithRetry(
        segment.file,
        segmentIndex: i + 1,
        segmentCount: segments.length,
      );
      transcripts.add(t);
    }

    onPhaseUpdate?.call(const LongAudioPhaseUpdate(phase: 'merge'));
    final merged = _mergeTranscripts(transcripts);
    for (final seg in segments) {
      try {
        await seg.file.delete();
      } catch (_) {}
    }
    return merged.trim();
  }

  Future<String> _transcribeSegmentWithRetry(
    File segmentFile, {
    required int segmentIndex,
    required int segmentCount,
  }) async {
    Object? lastError;
    for (
      var attempt = 0;
      attempt <= longAudioConfig.segmentRetries;
      attempt++
    ) {
      try {
        final result = await transcribeSegment(
          segmentFile,
          segmentIndex: segmentIndex,
          segmentCount: segmentCount,
        );
        return (result.transcript ?? result.response).trim();
      } catch (e) {
        lastError = e;
        if (attempt == longAudioConfig.segmentRetries) break;
      }
    }
    throw Exception(
      'Segment $segmentIndex/$segmentCount failed after retries: $lastError',
    );
  }

  bool _isTimeoutError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('inference timeout') || msg.contains('timeout');
  }

  Future<GemmaAudioResult> _summarizeFromTranscript(
    String fullTranscript, {
    String? systemInstruction,
    String? queryInstruction,
  }) async {
    const int kMaxWordsPerChunk = 3000;
    const int kOverlapWords = 100;

    final words = fullTranscript.split(RegExp(r'\s+'));
    if (words.length <= kMaxWordsPerChunk) {
      return summarizeTranscript(
        fullTranscript,
        systemInstruction: systemInstruction,
        queryInstruction: queryInstruction,
      );
    }

    debugPrint(
      'GemmaAudioService: Transcript is long (${words.length} words). Using chunked summarization.',
    );
    final chunks = <String>[];
    for (var i = 0; i < words.length; i += kMaxWordsPerChunk - kOverlapWords) {
      final end = (i + kMaxWordsPerChunk < words.length)
          ? i + kMaxWordsPerChunk
          : words.length;
      chunks.add(words.sublist(i, end).join(' '));
      if (end == words.length) break;
    }

    final chunkSummaries = <String>[];
    for (var i = 0; i < chunks.length; i++) {
      final chunkPrompt =
          'Summarize this section (${i + 1}/${chunks.length}) of a meeting transcript. '
          'Focus on key points, decisions, and action items. Keep it concise.';
      final chunkSummary = await chatWithTranscript(chunks[i], chunkPrompt);
      chunkSummaries.add('Section ${i + 1} Summary:\n$chunkSummary');
    }

    final finalMergePrompt =
        'Based on the following section summaries, create a single consolidated meeting summary. '
        'Use the exact Markdown format: ## TITLE, ## SUMMARY, ## KEY POINTS, ## ACTION ITEMS.';
    final finalResponse = await chatWithTranscript(
      chunkSummaries.join('\n\n---\n\n'),
      finalMergePrompt,
    );
    return GemmaAudioResult.parse(finalResponse, transcript: fullTranscript);
  }

  Future<List<_SegmentFile>> _splitWavIntoSegments(File wavFile) async {
    final bytes = await wavFile.readAsBytes();
    if (bytes.length < 44) {
      throw Exception('Invalid WAV: file too short');
    }

    final header = bytes.sublist(0, 44);
    final pcm = bytes.sublist(44);
    final bytesPerSecond = _bytesPerSecond16kMonoPcm;
    final segmentBytes = longAudioConfig.segmentSeconds * bytesPerSecond;
    final overlapBytes = longAudioConfig.overlapSeconds * bytesPerSecond;
    final stepBytes = (segmentBytes - overlapBytes).clamp(1, segmentBytes);

    final out = <_SegmentFile>[];
    var start = 0;
    var index = 0;
    while (start < pcm.length) {
      final end = (start + segmentBytes < pcm.length)
          ? start + segmentBytes
          : pcm.length;
      final segmentPcm = pcm.sublist(start, end);
      final segFile = File(
        '${wavFile.parent.path}/seg_${DateTime.now().microsecondsSinceEpoch}_$index.wav',
      );
      await _writeWav(segFile, header, segmentPcm);
      out.add(_SegmentFile(file: segFile));
      if (end == pcm.length) break;
      start += stepBytes;
      index++;
    }
    return out;
  }

  Future<void> _writeWav(File file, List<int> header44, List<int> pcm) async {
    final out = Uint8List(44 + pcm.length);
    out.setRange(0, 44, header44);
    out.setRange(44, out.length, pcm);
    final bd = ByteData.sublistView(out);
    bd.setUint32(4, 36 + pcm.length, Endian.little);
    bd.setUint32(40, pcm.length, Endian.little);
    await file.writeAsBytes(out, flush: true);
  }

  String _mergeTranscripts(List<String> transcripts) {
    if (transcripts.isEmpty) return '';
    var merged = transcripts.first.trim();
    for (var i = 1; i < transcripts.length; i++) {
      final current = transcripts[i].trim();
      merged = _appendWithOverlapDedupe(
        merged,
        current,
        overlapWindowWords: longAudioConfig.mergeOverlapWords,
      );
    }
    return merged;
  }

  String _appendWithOverlapDedupe(
    String left,
    String right, {
    required int overlapWindowWords,
  }) {
    final leftWords = left
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    final rightWords = right
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
    if (leftWords.isEmpty) return right;
    if (rightWords.isEmpty) return left;

    final maxK = math.min(
      overlapWindowWords,
      math.min(leftWords.length, rightWords.length),
    );
    var bestK = 0;
    for (var k = maxK; k >= 1; k--) {
      final leftTail = leftWords
          .sublist(leftWords.length - k)
          .join(' ')
          .toLowerCase();
      final rightHead = rightWords.sublist(0, k).join(' ').toLowerCase();
      if (leftTail == rightHead) {
        bestK = k;
        break;
      }
    }
    final dedupedRight = rightWords.sublist(bestK).join(' ');
    if (dedupedRight.isEmpty) return left;
    return '$left $dedupedRight'.trim();
  }

  /// Dispose of resources.
  Future<void> dispose() async {
    if (!isPlatformSupported) return;

    try {
      await _audioChannel.invokeMethod('dispose');
      _initialized = false;
      _modelPath = null;
      _progressSubscription?.cancel();
      debugPrint('GemmaAudioService: Disposed');
    } on PlatformException catch (e) {
      debugPrint('GemmaAudioService: Dispose failed: ${e.message}');
    }
  }
}

class LongAudioConfig {
  final int segmentSeconds;
  final int overlapSeconds;
  final int segmentRetries;
  final int forceSegmentAtSeconds;
  final int mergeOverlapWords;

  const LongAudioConfig({
    this.segmentSeconds = 45,
    this.overlapSeconds = 6,
    this.segmentRetries = 1,
    this.forceSegmentAtSeconds = 120,
    this.mergeOverlapWords = 40,
  });
}

class LongAudioPhaseUpdate {
  final String phase;
  final int? segmentIndex;
  final int? segmentCount;

  const LongAudioPhaseUpdate({
    required this.phase,
    this.segmentIndex,
    this.segmentCount,
  });
}

class _SegmentFile {
  final File file;
  _SegmentFile({required this.file});
}
