import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Result from Gemma 3n audio processing.
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

/// Service for Gemma 3n multimodal audio inference.
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

  bool _initialized = false;
  String? _modelPath;
  StreamSubscription<dynamic>? _progressSubscription;

  /// Whether the service is initialized with a loaded model
  bool get isInitialized => _initialized;

  /// Path to the currently loaded model
  String? get modelPath => _modelPath;

  /// Check if we're on a supported platform (Android)
  static bool get isPlatformSupported => Platform.isAndroid;

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
        'modelName': modelName ?? 'gemma-3n-E2B.litertlm',
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
        'modelName': modelName ?? 'gemma-3n-E2B.litertlm',
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
        'assetName': 'gemma-3n-E2B-it-int4.litertlm',
        'destName': 'gemma-3n-E2B.litertlm',
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
  /// [modelName] - The model filename (e.g., 'gemma-3n-E2B.task')
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
        'modelName': modelName ?? 'gemma-3n-E2B.litertlm',
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
        'modelName': modelName ?? 'gemma-3n-E2B.litertlm',
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

  /// Initialize the Gemma 3n model for inference.
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

    const modelName = 'gemma-3n-E2B.litertlm';

    // Check if already copied
    final downloaded = await isModelDownloaded(modelName: modelName);

    String path;
    if (!downloaded) {
      debugPrint('GemmaAudioService: Model not found, copying from assets...');
      path = await copyBundledModel(onProgress: onProgress);
    } else {
      path = await getModelPath(modelName: modelName);
    }

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
    _ensureInitialized();

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
    _ensureInitialized();

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

  /// Process audio with a custom prompt.
  ///
  /// [audioFile] - Mono WAV file (≤30s for optimal results)
  /// [prompt] - Custom prompt for the model
  Future<GemmaAudioResult> generateResponse(
    File audioFile,
    String prompt,
  ) async {
    _ensureInitialized();

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

  /// Process audio in chunks for files longer than 30 seconds.
  ///
  /// Automatically splits audio into 30s chunks and combines results.
  /// Note: This is a simple concatenation - context is not shared between chunks.
  Future<GemmaAudioResult> transcribeAndSummarizeLongAudio(
    File audioFile, {
    String? language,
    int chunkDurationSeconds = 30,
  }) async {
    _ensureInitialized();

    // TODO: Implement actual chunking with audio duration detection
    // For now, just process as single chunk
    debugPrint(
      'GemmaAudioService: Long audio chunking not yet implemented, processing as single chunk',
    );
    return transcribeAndSummarize(audioFile, language: language);
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

  void _ensureInitialized() {
    if (!isPlatformSupported) {
      throw UnsupportedError('Gemma audio is only supported on Android');
    }
    if (!_initialized) {
      throw StateError(
        'GemmaAudioService not initialized. Call initialize() first.',
      );
    }
  }
}
