import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:flutter/material.dart'; // For MaterialPageRoute
import 'package:path_provider/path_provider.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/audio_converter.dart';
import '../services/gemma_audio_service.dart';
import '../services/summary_storage_service.dart';
import '../services/notification_service.dart';
import '../main.dart'; // For navigatorKey
import '../services/share_handler_service.dart';
import '../screens/summary_result_screen.dart';

// Callback for foreground service init
@pragma('vm:entry-point')
void startCallback() {
  FlutterForegroundTask.setTaskHandler(AudioProcessingTaskHandler());
}

class AudioProcessingTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, SendPort? sendPort) async {
    // Keep service alive
  }

  @override
  void onRepeatEvent(DateTime timestamp, SendPort? sendPort) {
    // Optional
  }

  @override
  Future<void> onDestroy(DateTime timestamp, SendPort? sendPort) async {
    // Cleanup
  }
}

/// Processing status for the voice note pipeline
enum ProcessingStatus {
  idle,
  receivingFile,
  convertingAudio,
  initializingModel,
  processing,
  complete,
  error,
}

/// Model download/ready status
enum ModelStatus { notDownloaded, copying, ready, error }

/// Status of a queue item
enum QueueItemStatus { pending, processing, completed, failed }

/// Queue item with metadata for UI display
class QueueItem {
  final String id;
  final File file;
  final String fileName;
  final int fileSizeBytes;
  final DateTime addedAt;
  final Duration? estimatedDuration;
  QueueItemStatus status;
  String? errorMessage;

  QueueItem({
    required this.id,
    required this.file,
    required this.fileName,
    required this.fileSizeBytes,
    required this.addedAt,
    this.estimatedDuration,
    this.status = QueueItemStatus.pending,
    this.errorMessage,
  });

  /// Estimate processing time: ~30 seconds per minute of audio
  /// For unknown duration, estimate based on file size (~100KB per minute of audio)
  Duration get estimatedProcessingTime {
    if (estimatedDuration != null) {
      // 30s processing per minute of audio
      return Duration(
        seconds: (estimatedDuration!.inSeconds * 0.5).round().clamp(10, 300),
      );
    }
    // Estimate based on file size: 100KB ≈ 1 minute audio
    final estimatedMinutes = fileSizeBytes / 100000;
    return Duration(seconds: (estimatedMinutes * 30).round().clamp(10, 300));
  }

  // Serialization for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'filePath': file.path,
      'fileName': fileName,
      'fileSizeBytes': fileSizeBytes,
      'addedAt': addedAt.toIso8601String(),
      'status': status.index,
      'errorMessage': errorMessage,
    };
  }

  static QueueItem fromJson(Map<String, dynamic> json) {
    return QueueItem(
      id: json['id'],
      file: File(json['filePath']),
      fileName: json['fileName'],
      fileSizeBytes: json['fileSizeBytes'],
      addedAt: DateTime.parse(json['addedAt']),
      status: QueueItemStatus.values[json['status']],
      errorMessage: json['errorMessage'],
    );
  }

  String get formattedEstimate {
    final secs = estimatedProcessingTime.inSeconds;
    if (secs < 60) return '~${secs}s';
    return '~${(secs / 60).toStringAsFixed(1)}m';
  }
}

/// Main state provider for voice note processing using Gemma 4
class ProcessingState extends ChangeNotifier {
  final AudioConverter _audioConverter;
  final GemmaAudioService _gemmaService;
  final SummaryStorageService _storageService;
  final NotificationService _notificationService;
  final ShareHandlerService _shareHandlerService;
  final bool _enableBackgroundServices;
  final bool _enableNotifications;
  late final Future<void> _startupFuture;
  Future<void>? _notificationReady;
  Future<void> _queuePersistenceChain = Future.value();
  bool _startupCompleted = false;

  // Polling timer for queue syncing
  Timer? _queuePollTimer;

  // Processing state
  ProcessingStatus _status = ProcessingStatus.idle;
  String _statusMessage = '';
  double _progress = 0.0;
  String? _errorMessage;
  String? _currentAudioPath;

  // Model state
  ModelStatus _modelStatus = ModelStatus.notDownloaded;
  String _modelStatusMessage = 'Model not initialized';
  double _modelDownloadProgress = 0.0;

  // Results from Gemma
  GemmaAudioResult? _gemmaResult;

  // Queue system with mutex lock for strict sequential processing
  final List<QueueItem> _queueItems = [];
  bool _isProcessingQueue = false;
  Completer<void>? _processingLock; // Mutex for sequential processing
  QueueItem? _currentItem;
  DateTime? _currentProcessingStartTime;

  // Deduplication - track recently processed files
  final Set<String> _processedFilePaths = {};

  // File-based lock for cross-instance synchronization
  static const String _lockFileName = 'processing.lock';
  static const int _lockTimeoutSeconds = 300; // 5 minute timeout

  // Average processing time tracking
  // Average processing time tracking
  final List<Duration> _recentProcessingTimes = [];

  // Default Prompts (Matches Native Kotlin)
  static const String defaultSystemInstruction =
      """You are a concise summarization assistant.

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
(or write "None" if no action items were mentioned)""";

  static const String defaultQueryInstruction = "Analyze this transcript:";

  static const String defaultTranscriptionSystem =
      """TRANSCRIBE VERBATIM. DO NOT TRANSLATE.

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

OUTPUT: Only the romanized transcript. Nothing else.""";

  static const String defaultTranscriptionPrompt =
      "Transcribe the audio exactly as spoken, preserving English-Hindi code switching and romanizing Hindi words without translating them.";

  // Prompt Settings
  String _systemInstruction = defaultSystemInstruction;
  String _queryInstruction = defaultQueryInstruction;
  String _transcriptionSystemInstruction = defaultTranscriptionSystem;
  String _transcriptionPrompt = defaultTranscriptionPrompt;
  List<PromptPreset> _userPresets = [];

  // Predefined built-in presets
  static final List<PromptPreset> predefinedPresets = [
    PromptPreset(
      name: '📋 Meeting Minutes',
      systemInstruction: '''You are a meeting notes specialist.

Extract and organize meeting information in this format:

## TITLE
Brief meeting title (3-6 words)

## ATTENDEES
List people mentioned or speaking

## SUMMARY
2-3 sentence overview of the meeting

## DECISIONS MADE
- Key decisions reached

## ACTION ITEMS
- Task: [person responsible] - [deadline if mentioned]

## NEXT STEPS
Upcoming meetings or follow-ups mentioned''',
      queryInstruction: 'Extract meeting notes from this transcript:',
      transcriptionSystem: defaultTranscriptionSystem,
      transcriptionPrompt: defaultTranscriptionPrompt,
      isBuiltIn: true,
    ),
    PromptPreset(
      name: '🌐 Translate to English',
      systemInstruction: '''You are a professional translator.

Translate the entire content to English while:
- Preserving the original meaning and tone
- Keeping proper nouns unchanged
- Maintaining paragraph structure
- Noting any idioms or cultural references

Output format:
## TRANSLATION
[Full English translation]

## NOTES
Any translation notes or cultural context''',
      queryInstruction: 'Translate this transcript to English:',
      transcriptionSystem:
          'Transcribe the audio exactly as spoken in the original language. Do not translate.',
      transcriptionPrompt: 'Transcribe verbatim in the original language.',
      isBuiltIn: true,
    ),
    PromptPreset(
      name: '⚡ Quick Summary',
      systemInstruction: '''You are a concise summarization assistant.

Provide an ultra-brief summary in this format:

## TITLE
2-4 word title

## TL;DR
One sentence summary (max 20 words)

## KEY POINTS
- Point 1
- Point 2
- Point 3
(maximum 3 points, each under 8 words)''',
      queryInstruction: 'Give a quick summary:',
      transcriptionSystem: defaultTranscriptionSystem,
      transcriptionPrompt: defaultTranscriptionPrompt,
      isBuiltIn: true,
    ),
    PromptPreset(
      name: '📚 Lecture Notes',
      systemInstruction: '''You are an academic note-taking assistant.

Organize lecture content in this format:

## TITLE
Lecture topic (3-6 words)

## MAIN CONCEPTS
### Concept 1
Definition and explanation

### Concept 2
Definition and explanation

## KEY TERMS
- **Term**: Definition

## EXAMPLES MENTIONED
- Example and its context

## QUESTIONS TO REVIEW
- Important questions raised''',
      queryInstruction: 'Create lecture notes from this transcript:',
      transcriptionSystem: defaultTranscriptionSystem,
      transcriptionPrompt: defaultTranscriptionPrompt,
      isBuiltIn: true,
    ),
    PromptPreset(
      name: '🎤 Interview Notes',
      systemInstruction: '''You are an interview documentation specialist.

Organize interview content in this format:

## TITLE
Interview subject/topic

## PARTICIPANTS
- Interviewer(s)
- Interviewee(s)

## Q&A SUMMARY
**Q:** Question asked
**A:** Key points from answer

(Repeat for major questions)

## KEY INSIGHTS
- Notable quotes or insights

## FOLLOW-UP TOPICS
- Areas for further exploration''',
      queryInstruction: 'Extract interview notes from this transcript:',
      transcriptionSystem: defaultTranscriptionSystem,
      transcriptionPrompt: defaultTranscriptionPrompt,
      isBuiltIn: true,
    ),
  ];

  String get systemInstruction => _systemInstruction;
  String get queryInstruction => _queryInstruction;
  String get transcriptionSystem => _transcriptionSystemInstruction;
  String get transcriptionPrompt => _transcriptionPrompt;

  /// All presets: predefined + user-created
  List<PromptPreset> get presets => [...predefinedPresets, ..._userPresets];

  /// Only user-created presets
  List<PromptPreset> get userPresets => _userPresets;

  Future<void> updateSystemInstruction(String value) async {
    _systemInstruction = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('systemInstruction', value);
    notifyListeners();
  }

  Future<void> updateQueryInstruction(String value) async {
    _queryInstruction = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('queryInstruction', value);
    notifyListeners();
  }

  Future<void> updateTranscriptionSystem(String value) async {
    _transcriptionSystemInstruction = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transcriptionSystem', value);
    notifyListeners();
  }

  Future<void> updateTranscriptionPrompt(String value) async {
    _transcriptionPrompt = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('transcriptionPrompt', value);
    notifyListeners();
  }

  Future<void> savePreset(String name) async {
    final newPreset = PromptPreset(
      name: name,
      systemInstruction: _systemInstruction,
      queryInstruction: _queryInstruction,
      transcriptionSystem: _transcriptionSystemInstruction,
      transcriptionPrompt: _transcriptionPrompt,
      isBuiltIn: false,
    );
    _userPresets.add(newPreset);
    await _savePresets();
    notifyListeners();
  }

  Future<void> deletePreset(PromptPreset preset) async {
    // Don't allow deleting built-in presets
    if (preset.isBuiltIn) return;
    _userPresets.removeWhere((p) => p.name == preset.name);
    await _savePresets();
    notifyListeners();
  }

  void applyPreset(PromptPreset preset) {
    updateSystemInstruction(preset.systemInstruction);
    updateQueryInstruction(preset.queryInstruction);
    updateTranscriptionSystem(preset.transcriptionSystem);
    updateTranscriptionPrompt(preset.transcriptionPrompt);
  }

  Future<void> _savePresets() async {
    final prefs = await SharedPreferences.getInstance();
    // Only save user presets (not built-in)
    final jsonList = _userPresets.map((p) => p.toJson()).toList();
    await prefs.setString('prompt_presets', jsonEncode(jsonList));
  }

  Future<void> resetSettings() async {
    _systemInstruction = defaultSystemInstruction;
    _queryInstruction = defaultQueryInstruction;
    _transcriptionSystemInstruction = defaultTranscriptionSystem;
    _transcriptionPrompt = defaultTranscriptionPrompt;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('systemInstruction');
    await prefs.remove('queryInstruction');
    await prefs.remove('transcriptionSystem');
    await prefs.remove('transcriptionPrompt');
    notifyListeners();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _systemInstruction =
        prefs.getString('systemInstruction') ?? defaultSystemInstruction;
    _queryInstruction =
        prefs.getString('queryInstruction') ?? defaultQueryInstruction;
    _transcriptionSystemInstruction =
        prefs.getString('transcriptionSystem') ?? defaultTranscriptionSystem;
    _transcriptionPrompt =
        prefs.getString('transcriptionPrompt') ?? defaultTranscriptionPrompt;

    // Load user presets (predefined are always available)
    final presetsJson = prefs.getString('prompt_presets');
    if (presetsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(presetsJson);
        _userPresets = decoded
            .map((item) => PromptPreset.fromJson(item))
            .toList();
      } catch (e) {
        debugPrint('Error loading presets: $e');
      }
    }
    notifyListeners();
  }

  Future<void> _bootstrapStartup() async {
    try {
      await _loadSettings();
      await _loadQueue();
      await _clearOrphanedLock();

      if (_enableBackgroundServices) {
        try {
          await _initShareHandler();
        } catch (e) {
          debugPrint('Queue: Share handler init error: $e');
        }
        _startPolling();

        if (_enableNotifications) {
          _initForegroundTask();
          _notificationReady = _notificationService.initialize(
            onDidReceiveNotificationResponse: (details) async {
              if (details.payload != null) {
                final summaryId = details.payload!;
                debugPrint('Notification tapped with payload: $summaryId');

                // Find the summary record
                final record = await _storageService.getRecord(summaryId);
                if (record != null && navigatorKey.currentState != null) {
                  navigatorKey.currentState!.push(
                    MaterialPageRoute(
                      builder: (_) => SummaryResultScreen(record: record),
                    ),
                  );
                }
              }
            },
          );
        } else {
          _notificationReady = Future.value();
        }
      }
    } catch (e) {
      debugPrint('Queue: Startup error: $e');
    } finally {
      _startupCompleted = true;
    }
  }

  // Initialize Foreground Service
  Future<void> _initForegroundTask() async {
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: 'voice_note_processing',
        channelName: 'Voice Note Processing',
        channelDescription: 'Processing voice notes in background',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
      ),
      iosNotificationOptions: const IOSNotificationOptions(
        showNotification: true,
        playSound: false,
      ),
      foregroundTaskOptions: const ForegroundTaskOptions(
        interval: 5000,
        isOnceEvent: false,
        autoRunOnBoot: false,
        allowWakeLock: true,
        allowWifiLock: true,
      ),
    );
  }

  /// Start foreground service to keep app alive
  Future<void> _startForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) return;

    await FlutterForegroundTask.startService(
      notificationTitle: 'Processing Voice Notes',
      notificationText: 'Please wait...',
      callback: startCallback,
    );
  }

  /// Stop foreground service
  Future<void> _stopForegroundService() async {
    if (await FlutterForegroundTask.isRunningService) {
      await FlutterForegroundTask.stopService();
    }
  }

  // Queue getters for UI
  List<QueueItem> get queueItems => List.unmodifiable(_queueItems);
  int get queueCount => _queueItems.length;
  bool get hasQueuedFiles => _queueItems.isNotEmpty;
  QueueItem? get currentItem => _currentItem;

  @visibleForTesting
  Future<void> get startupReady => _startupFuture;

  @visibleForTesting
  Set<String> get processedFilePathsDebug =>
      Set.unmodifiable(_processedFilePaths);

  @visibleForTesting
  Future<void> get queuePersistenceIdle => _queuePersistenceChain;

  /// Estimate total time for all queued items
  Duration get totalQueueEstimate {
    if (_queueItems.isEmpty) return Duration.zero;
    return _queueItems.fold(
      Duration.zero,
      (total, item) => total + item.estimatedProcessingTime,
    );
  }

  // Persistent queue file
  Future<File> get _queueFile async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/queue.json');
  }

  /// Load queue from disk
  /// Load queue from disk
  Future<void> _loadQueue() async {
    try {
      final file = await _queueFile;
      if (await file.exists()) {
        final content = await file.readAsString();
        final List<dynamic> json = jsonDecode(content);
        final loadedItems = json.map((e) => QueueItem.fromJson(e)).toList();
        final activeLoadedItems = loadedItems
            .where((item) => item.status != QueueItemStatus.completed)
            .toList();

        // 1. Add new items
        for (var item in activeLoadedItems) {
          if (!_queueItems.any((existing) => existing.id == item.id)) {
            _queueItems.add(item);
          }
        }

        // 2. Update existing items (status, error message)
        for (var loadedItem in activeLoadedItems) {
          final existingIndex = _queueItems.indexWhere(
            (e) => e.id == loadedItem.id,
          );
          if (existingIndex != -1) {
            final existing = _queueItems[existingIndex];

            // If we are currently processing this item, DO NOT overwrite our local state
            // with disk state (which might be stale 'pending')
            if (_currentItem?.id == existing.id) continue;

            // Otherwise, update status from disk
            if (existing.status != loadedItem.status) {
              existing.status = loadedItem.status;
            }
            if (loadedItem.errorMessage != null) {
              existing.errorMessage = loadedItem.errorMessage;
            }
          }
        }

        // 3. Remove items that are no longer in disk queue
        // (unless we are processing them, which shouldn't happen if logic is correct,
        // but extra safety: don't remove current item)
        _queueItems.removeWhere((existing) {
          if (_currentItem?.id == existing.id) return false;
          if (!_startupCompleted) return false;
          final isInDisk = activeLoadedItems.any(
            (loaded) => loaded.id == existing.id,
          );
          return !isInDisk;
        });

        // Sort by addedAt
        _queueItems.sort((a, b) => a.addedAt.compareTo(b.addedAt));
        _syncProcessedFilePaths();

        notifyListeners();
        debugPrint(
          'Queue: Synced (Merged/Updated) ${activeLoadedItems.length} items from disk',
        );
      }
    } catch (e) {
      debugPrint('Queue: Error loading queue: $e');
    }
  }

  /// Save queue to disk
  Future<void> _saveQueue() async {
    try {
      final file = await _queueFile;
      final itemsToSave = _queueItems.toList();
      final tempFile = File(
        '${file.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
      );
      final json = jsonEncode(itemsToSave.map((e) => e.toJson()).toList());
      await tempFile.writeAsString(json);
      if (await file.exists()) {
        await file.delete();
      }
      await tempFile.rename(file.path);
      debugPrint('Queue: Saved ${itemsToSave.length} items to disk');
    } catch (e) {
      debugPrint('Queue: Error saving queue: $e');
    }
  }

  Future<void> _enqueueQueuePersistence() {
    _queuePersistenceChain = _queuePersistenceChain.then((_) => _saveQueue());
    return _queuePersistenceChain;
  }

  void _persistQueueMutation() {
    if (_startupCompleted) {
      unawaited(_enqueueQueuePersistence());
      return;
    }

    unawaited(
      _startupFuture.then((_) {
        _enqueueQueuePersistence();
      }),
    );
  }

  void _syncProcessedFilePaths() {
    _processedFilePaths
      ..clear()
      ..addAll(_queueItems.map((item) => item.file.path));
  }

  ProcessingState({
    AudioConverter? audioConverter,
    GemmaAudioService? gemmaService,
    SummaryStorageService? storageService,
    NotificationService? notificationService,
    ShareHandlerService? shareHandlerService,
    bool enableBackgroundServices = true,
    bool enableNotifications = true,
  }) : _audioConverter = audioConverter ?? AudioConverter(),
       _gemmaService = gemmaService ?? GemmaAudioService(),
       _storageService = storageService ?? SummaryStorageService(),
       _notificationService = notificationService ?? NotificationService(),
       _shareHandlerService = shareHandlerService ?? ShareHandlerService(),
       _enableBackgroundServices = enableBackgroundServices,
       _enableNotifications = enableNotifications {
    _startupFuture = _bootstrapStartup();
  }

  // Initialize and listen to share handler
  Future<void> _initShareHandler() async {
    if (!_enableBackgroundServices) return;
    _shareHandlerService.onFileReceived = (File file) {
      debugPrint('ShareHandler: Received file ${file.path}');
      queueFile(file);
    };
    await _shareHandlerService.initialize();
  }

  void _startPolling() {
    if (!_enableBackgroundServices) return;
    _queuePollTimer?.cancel();
    _queuePollTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      // Only poll if we are NOT the active processor
      // (Active processor drives the state, so it doesn't need to poll)
      if (!_isProcessingQueue) {
        _loadQueue();
      }
    });
  }

  // Getters
  ProcessingStatus get status => _status;
  String get statusMessage => _statusMessage;
  double get progress => _progress;
  String? get errorMessage => _errorMessage;
  String? get currentAudioPath => _currentAudioPath;
  double get modelDownloadProgress => _modelDownloadProgress;
  ModelStatus get modelStatus => _modelStatus;
  String get modelStatusMessage => _modelStatusMessage;

  // Expose service for chat
  GemmaAudioService get gemmaService => _gemmaService;

  /// Get transcript from Gemma result (for UI compatibility)
  TranscriptionResult? get transcriptionResult {
    if (_gemmaResult == null) return null;
    return TranscriptionResult(
      text: _gemmaResult!.transcript ?? _gemmaResult!.response,
    );
  }

  /// Get summary from Gemma result (for UI compatibility)
  SummaryResult? get summaryResult {
    if (_gemmaResult == null) return null;
    return SummaryResult(
      title: _gemmaResult!.title ?? 'Untitled',
      summary: _gemmaResult!.summary ?? '',
      keyPoints: _gemmaResult!.keyPoints,
      actionItems: _gemmaResult!.actionItems ?? 'None',
      transcript: _gemmaResult!.transcript ?? _gemmaResult!.response,
      response: _gemmaResult!.response,
    );
  }

  bool get isProcessing =>
      _status != ProcessingStatus.idle &&
      _status != ProcessingStatus.complete &&
      _status != ProcessingStatus.error;

  bool get enableBackgroundServices => _enableBackgroundServices;
  bool get enableNotifications => _enableNotifications;

  // Guard against multiple initializations
  bool _isInitializing = false;

  /// Initialize Gemma model (copy from bundled assets)
  Future<void> initialize() async {
    await _startupFuture;

    // Prevent multiple concurrent init calls
    if (_isInitializing) {
      debugPrint('Model already initializing, skipping');
      return;
    }

    // If already ready, skip
    if (_modelStatus == ModelStatus.ready) {
      debugPrint('Model already ready');
      return;
    }

    _isInitializing = true;
    int retryCount = 0;
    const maxRetries = 3;

    while (retryCount < maxRetries) {
      try {
        if (_enableBackgroundServices) {
          await (_notificationReady ?? Future.value());
          await _notificationService.showProcessingNotification(
            title: 'Preparing Voice Notes',
            body: 'Loading Gemma 4 E2B model...',
          );
        }

        _updateModelStatus(
          ModelStatus.copying,
          retryCount > 0
              ? 'Retrying initialization (${retryCount + 1}/$maxRetries)...'
              : 'Copying Gemma model from assets...',
          0.1,
        );

        // Initialize audio converter
        await _audioConverter.initialize();

        _updateModelStatus(
          ModelStatus.copying,
          'Loading Gemma 4 E2B model...',
          0.3,
        );

        // Initialize Gemma with bundled model
        await _gemmaService.initializeWithBundledModel(
          onProgress: (progress) {
            _updateModelStatus(
              ModelStatus.copying,
              'Copying model: ${progress.formattedProgress}',
              0.3 + (progress.progress / 100) * 0.6,
            );
          },
        );

        _updateModelStatus(ModelStatus.ready, 'Gemma 4 E2B ready', 1.0);

        // Auto-process any queued files after init
        // We use the file-lock safe method _startProcessingQueue
        if (_queueItems.any(
          (item) => item.status == QueueItemStatus.pending,
        )) {
          debugPrint(
            'Model ready - processing ${_queueItems.length} queued files',
          );
          _startProcessingQueue();
        }

        _isInitializing = false;
        return; // Success - exit
      } catch (e) {
        retryCount++;
        debugPrint('Gemma initialization error (attempt $retryCount): $e');

        if (retryCount >= maxRetries) {
          _updateModelStatus(ModelStatus.error, 'Model error: $e', 0.0);
          _isInitializing = false;
          return;
        }

        // Wait before retry
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }

    _isInitializing = false;
  }

  /// Retry initialization after error
  Future<void> retryInitialize() async {
    if (_modelStatus == ModelStatus.error) {
      _modelStatus = ModelStatus.notDownloaded;
      notifyListeners();
    }
    await initialize();
  }

  /// Download/initialize model manually (triggers copy from assets)
  Future<void> downloadModel() async {
    await initialize();
  }

  /// Add a file to the processing queue with deduplication and format checks.
  /// Returns the QueueItem if added, or null if skipped.
  QueueItem? queueFile(File file) {
    if (!AudioConverter.isSupportedInputPath(file.path)) {
      _setError(
        'Unsupported audio format for ${file.path.split('/').last}. '
        'Supported formats: ${AudioConverter.supportedExtensionsLabel}.',
      );
      return null;
    }

    // Deduplication check
    if (_processedFilePaths.contains(file.path)) {
      debugPrint('Queue: Skipping duplicate file ${file.path}');
      return null;
    }

    // Create unique ID
    final id =
        '${DateTime.now().millisecondsSinceEpoch}_${file.path.hashCode.abs()}';

    final item = QueueItem(
      id: id,
      file: file,
      fileName: file.path.split('/').last,
      fileSizeBytes: file.existsSync() ? file.lengthSync() : 0,
      addedAt: DateTime.now(),
    );

    _queueItems.add(item);
    _syncProcessedFilePaths();

    // Save to disk
    _persistQueueMutation();

    debugPrint(
      'Queue: Added ${item.fileName} (${_queueItems.length} in queue)',
    );
    notifyListeners();

    // Start processing if model ready and not already processing
    // Use Future.microtask to avoid recursive/nested calls that cause race conditions
    if (_modelStatus == ModelStatus.ready && !_isProcessingQueue) {
      unawaited(
        _startupFuture.then((_) {
          if (_modelStatus == ModelStatus.ready &&
              !_isProcessingQueue &&
              _queueItems.any((item) => item.status == QueueItemStatus.pending)) {
            _startProcessingQueue();
          }
        }),
      );
    }

    return item;
  }

  /// Remove a file from the queue by ID
  bool removeFromQueue(String id) {
    // Don't remove currently processing item
    if (_currentItem?.id == id) {
      debugPrint('Queue: Cannot remove currently processing item');
      return false;
    }

    final index = _queueItems.indexWhere((item) => item.id == id);
    if (index == -1) return false;

    _queueItems.removeAt(index);
    _syncProcessedFilePaths();
    debugPrint('Queue: Removed item $id');

    // Save to disk
    _persistQueueMutation();

    notifyListeners();
    return true;
  }

  /// Reorder items in the queue
  void reorderQueue(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= _queueItems.length) return;
    if (newIndex < 0 || newIndex > _queueItems.length) return;

    // Don't move currently processing item
    if (_queueItems[oldIndex].status == QueueItemStatus.processing) return;

    final item = _queueItems.removeAt(oldIndex);
    final adjustedNewIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    _queueItems.insert(adjustedNewIndex, item);
    _syncProcessedFilePaths();

    // Save to disk
    _persistQueueMutation();

    notifyListeners();
  }

  /// Clear all items from queue (except currently processing one)
  void clearQueue() {
    _queueItems.removeWhere((item) {
      // Don't remove the actual in-memory current item
      if (_currentItem != null && item.id == _currentItem!.id) return false;
      return true;
    });
    _syncProcessedFilePaths();

    // Save to disk
    _persistQueueMutation();

    notifyListeners();
  }

  /// Clear orphan lock on startup
  Future<void> _clearOrphanedLock() async {
    try {
      final lockFile = await _getLockFile();
      if (await lockFile.exists()) {
        debugPrint('Queue: Clearing orphaned file lock from previous run');
        await lockFile.delete();

        // Fix any "processing" items in the loaded queue (stuck from crash)
        bool changed = false;
        for (var item in _queueItems) {
          if (item.status == QueueItemStatus.processing) {
            item.status = QueueItemStatus.failed;
            item.errorMessage = 'Interrupted by app restart';
            changed = true;
          }
        }
        if (changed) {
          await _saveQueue();
          notifyListeners();
        }
      }
    } catch (e) {
      debugPrint('Queue: Error clearing orphaned lock: $e');
    }
  }

  /// Internal method to start the processing queue
  /// This sets the flag synchronously before any async work
  void _startProcessingQueue() {
    // Double-check the in-memory lock synchronously
    if (_isProcessingQueue) {
      debugPrint('Queue: In-memory lock held, skipping');
      return;
    }
    if (_queueItems.isEmpty) return;
    if (_modelStatus != ModelStatus.ready) return;

    // CRITICAL: Set in-memory flag SYNCHRONOUSLY before any async work
    _isProcessingQueue = true;
    debugPrint('Queue: Acquired in-memory lock');

    // Check and acquire file-based lock (async but we've already claimed in-memory)
    _acquireFileLockAndProcess();
  }

  /// Acquire file-based lock and start processing
  Future<void> _acquireFileLockAndProcess() async {
    try {
      final lockFile = await _getLockFile();

      // Check if another instance has the lock
      if (await lockFile.exists()) {
        final lastModified = await lockFile.lastModified();
        final age = DateTime.now().difference(lastModified);

        if (age.inSeconds < _lockTimeoutSeconds) {
          // Another instance is processing, release our in-memory lock
          debugPrint(
            'Queue: File lock held by another instance (${age.inSeconds}s old), backing off',
          );
          _isProcessingQueue = false;
          return;
        } else {
          // Stale lock, we can take over
          debugPrint(
            'Queue: Stale file lock detected (${age.inSeconds}s old), taking over',
          );
        }
      }

      // Create/update lock file with our PID
      await lockFile.writeAsString(DateTime.now().toIso8601String());
      debugPrint('Queue: Acquired file lock, starting processing');

      if (_enableBackgroundServices) {
        // Start foreground service to keep alive
        await _startForegroundService();
        await (_notificationReady ?? Future.value());
        await _notificationService.showProcessingNotification(
          title: 'Processing Voice Notes',
          body: 'Gemma 4 is processing your shared audio...',
        );
      }

      // Now start the async processing
      await _processQueueInternal();
    } catch (e) {
      debugPrint('Queue: Error acquiring file lock: $e');
      _isProcessingQueue = false;
    }
  }

  /// Get the lock file
  Future<File> _getLockFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_lockFileName');
  }

  /// Release the file lock
  Future<void> _releaseFileLock() async {
    try {
      final lockFile = await _getLockFile();
      if (await lockFile.exists()) {
        await lockFile.delete();
        debugPrint('Queue: Released file lock');
      }
    } catch (e) {
      debugPrint('Queue: Error releasing file lock: $e');
    }
  }

  /// Public method to trigger queue processing
  Future<void> processQueue() async {
    await _startupFuture;
    _startProcessingQueue();
  }

  /// Process queue internal loop
  Future<void> _processQueueInternal() async {
    _processingLock = Completer<void>();
    debugPrint('Queue: Starting processing (${_queueItems.length} files)');

    // Reload queue from disk to pick up items from other instances
    await _loadQueue();

    while (_queueItems.isNotEmpty) {
      // Get next pending item
      final pendingIndex = _queueItems.indexWhere(
        (item) => item.status == QueueItemStatus.pending,
      );

      if (pendingIndex == -1) break; // No more pending items

      _currentItem = _queueItems[pendingIndex];
      _currentItem!.status = QueueItemStatus.processing;
      _currentProcessingStartTime = DateTime.now();
      debugPrint('Queue: Processing ${_currentItem!.fileName}');
      if (_enableBackgroundServices) {
        await (_notificationReady ?? Future.value());
        await _notificationService.showProcessingNotification(
          title: 'Processing Voice Notes',
          body: 'Processing ${_currentItem!.fileName}...',
        );
      }
      notifyListeners();

      // CRITICAL: Save 'Processing' status to disk immediately
      // so other instances see it as 'Processing' instead of 'Pending'
      await _saveQueue();

      try {
        await _processVoiceNoteInternal(_currentItem!.file);

        // Mark as completed
        _currentItem!.status = QueueItemStatus.completed;

        // Track processing time for better estimates
        final elapsed = DateTime.now().difference(_currentProcessingStartTime!);
        _recentProcessingTimes.add(elapsed);
        if (_recentProcessingTimes.length > 5) {
          _recentProcessingTimes.removeAt(0);
        }

        debugPrint('Queue: Completed ${_currentItem!.fileName}');
      } catch (e) {
        // Mark as failed
        _currentItem!.status = QueueItemStatus.failed;
        _currentItem!.errorMessage = e.toString();
        debugPrint('Queue: Failed ${_currentItem!.fileName}: $e');
      }

      // CRITICAL: Reload from disk to get items added by other instances
      // before we save our changes (removal of completed item)
      await _loadQueue();

      _queueItems.removeWhere(
        (item) => item.status == QueueItemStatus.completed,
      );
      _syncProcessedFilePaths();

      // Save updated queue (removed items)
      await _saveQueue();

      // Show notification for completion
      if (_currentItem!.status == QueueItemStatus.completed) {
        // Try to find the summary title if available, or just use filename
        String title = 'Processing Complete';
        String body = 'Processed ${_currentItem!.fileName}';

        // Use summary result if available
        if (_gemmaResult != null && _gemmaResult!.summary != null) {
          title = 'Summary Ready';
          // Use first few words of summary
          body = _gemmaResult!.summary!.length > 50
              ? '${_gemmaResult!.summary!.substring(0, 50)}...'
              : _gemmaResult!.summary!;
        }

        // Find the summary ID that corresponds to this file
        String? payload;
        try {
          // We assume the record was just saved and is the latest one with this filename
          final records = await _storageService.getAllRecords();
          if (records.isNotEmpty) {
            // Check if the most recent record matches our current file
            final latest = records.first;
            if (latest.sourceFileName == _currentItem!.fileName) {
              payload = latest.id;
            } else {
              // Fallback scan
              final match = records.firstWhere(
                (r) => r.sourceFileName == _currentItem!.fileName,
              );
              payload = match.id;
            }
          }
        } catch (e) {
          debugPrint('Queue: Error finding record for notification: $e');
        }

        if (_enableBackgroundServices) {
          _notificationService.showCompletionNotification(
            title: title,
            body: body,
            notificationId: 1001,
            payload: payload ?? _currentItem!.id,
          );
        }
      } else if (_currentItem!.status == QueueItemStatus.failed) {
        if (_enableBackgroundServices) {
          _notificationService.showErrorNotification(
            title: 'Processing Failed',
            body: 'Failed to process ${_currentItem!.fileName}',
            notificationId: 1001,
          );
        }
      }

      _currentItem = null;
      notifyListeners();

      // Small delay before next item
      await Future.delayed(const Duration(milliseconds: 300));

      // Reload queue to pick up new items
      await _loadQueue();
    }

    // Release mutex lock
    _isProcessingQueue = false;
    _processingLock?.complete();
    _processingLock = null;

    // Release file-based lock
    await _releaseFileLock();

    // Stop foreground service
    if (_enableBackgroundServices) {
      await _stopForegroundService();
    }

    debugPrint('Queue: All items processed');
    notifyListeners();
  }

  /// Public method: Queue the file for processing.
  /// All processing is serialized through the queue to prevent concurrency issues.
  Future<void> processVoiceNote(File audioFile) async {
    // Always queue the file. The queue manager will pick it up immediately
    // if the model is ready and no other file is processing.
    queueFile(audioFile);
  }

  /// Internal: Actually process a voice note file through Gemma 4
  Future<void> _processVoiceNoteInternal(File audioFile) async {
    _reset();
    _currentAudioPath = audioFile.path;
    notifyListeners();

    File? wavFile;
    try {
      // Step 1: Convert audio to WAV format
      _updateStatus(
        ProcessingStatus.convertingAudio,
        'Converting audio format...',
        0.2,
      );

      try {
        wavFile = await _audioConverter.convertTo16kMonoWav(audioFile);
        debugPrint('Converted audio to: ${wavFile.path}');
      } catch (e) {
        debugPrint('Audio conversion error: $e');
        _setError('Audio conversion failed: $e');
        rethrow;
      }

      // Step 2: Process with Gemma (transcription + summarization in one pass)
      _updateStatus(
        ProcessingStatus.processing,
        'Processing with Gemma 4 E2B...',
        0.5,
      );

      // Process with Gemma (using custom prompts if set)
      try {
        _gemmaResult = await _gemmaService.transcribeAndSummarize(
          wavFile,
          systemInstruction: _systemInstruction.isNotEmpty
              ? _systemInstruction
              : null,
          queryInstruction: _queryInstruction.isNotEmpty
              ? _queryInstruction
              : null,
          transcriptionSystem: _transcriptionSystemInstruction.isNotEmpty
              ? _transcriptionSystemInstruction
              : null,
          transcriptionPrompt: _transcriptionPrompt.isNotEmpty
              ? _transcriptionPrompt
              : null,
        );
        debugPrint(
          'Gemma result: ${_gemmaResult?.response.substring(0, _gemmaResult!.response.length.clamp(0, 100))}...',
        );
      } catch (e) {
        debugPrint('Gemma processing error: $e');
        _setError('Processing failed: $e');
        rethrow;
      }

      // Save to history
      try {
        final originalFileName = audioFile.path.split('/').last;
        // Use generated title if available, otherwise use original filename
        final displayName = _gemmaResult?.title?.isNotEmpty == true
            ? _gemmaResult!.title!
            : originalFileName;

        debugPrint('Saving record with title: $displayName');
        debugPrint(
          'Summary: ${_gemmaResult?.summary?.substring(0, (_gemmaResult?.summary?.length ?? 0).clamp(0, 50))}...',
        );

        await _storageService.saveRecord(
          sourceFileName: displayName,
          sourceFilePath: audioFile.path,
          transcript: _gemmaResult!.transcript ?? _gemmaResult!.response,
          summary: _gemmaResult!.summary ?? 'No summary generated',
          keyPoints: _gemmaResult!.keyPoints,
          actionItems: _gemmaResult!.actionItems ?? 'None',
        );
        debugPrint('Saved summary to history');
      } catch (e) {
        debugPrint('Failed to save summary: $e');
      }

      // Complete
      _updateStatus(ProcessingStatus.complete, 'Processing complete!', 1.0);
    } catch (e) {
      debugPrint('Processing error: $e');
      if (_errorMessage == null || _errorMessage!.isEmpty) {
        _setError('Processing failed: $e');
      }
      rethrow;
    } finally {
      try {
        if (wavFile != null && wavFile.path != audioFile.path) {
          await wavFile.delete();
        }
      } catch (_) {}
    }
  }

  void _updateStatus(ProcessingStatus status, String message, double progress) {
    _status = status;
    _statusMessage = message;
    _progress = progress;
    _errorMessage = null;
    notifyListeners();
  }

  void _updateModelStatus(ModelStatus status, String message, double progress) {
    _modelStatus = status;
    _modelStatusMessage = message;
    _modelDownloadProgress = progress;
    notifyListeners();
  }

  void _setError(String message) {
    _status = ProcessingStatus.error;
    _errorMessage = message;
    _statusMessage = 'Error occurred';
    notifyListeners();
  }

  void _reset() {
    _status = ProcessingStatus.idle;
    _statusMessage = '';
    _progress = 0.0;
    _errorMessage = null;
    _gemmaResult = null;
    notifyListeners();
  }

  /// Clear results and reset to idle
  void clear() {
    _currentAudioPath = null;
    _reset();
  }

  @override
  void dispose() {
    _gemmaService.dispose();
    _queuePollTimer?.cancel();
    super.dispose();
  }
}

class TranscriptionResult {
  final String text;
  TranscriptionResult({required this.text});
}

class PromptPreset {
  final String name;
  final String systemInstruction;
  final String queryInstruction;
  final String transcriptionSystem;
  final String transcriptionPrompt;
  final bool isBuiltIn;

  PromptPreset({
    required this.name,
    required this.systemInstruction,
    required this.queryInstruction,
    this.transcriptionSystem = '',
    this.transcriptionPrompt = '',
    this.isBuiltIn = false,
  });

  Map<String, dynamic> toJson() => {
    'name': name,
    'systemInstruction': systemInstruction,
    'queryInstruction': queryInstruction,
    'transcriptionSystem': transcriptionSystem,
    'transcriptionPrompt': transcriptionPrompt,
    'isBuiltIn': isBuiltIn,
  };

  factory PromptPreset.fromJson(Map<String, dynamic> json) {
    return PromptPreset(
      name: json['name'] as String,
      systemInstruction: json['systemInstruction'] as String,
      queryInstruction: json['queryInstruction'] as String,
      transcriptionSystem: json['transcriptionSystem'] as String? ?? '',
      transcriptionPrompt: json['transcriptionPrompt'] as String? ?? '',
      isBuiltIn: json['isBuiltIn'] as bool? ?? false,
    );
  }
}

/// Compatibility wrapper for SummaryResult
class SummaryResult {
  final String title;
  final String summary;
  final List<String> keyPoints;
  final String actionItems;
  final String transcript;
  final String response;

  SummaryResult({
    required this.title,
    required this.summary,
    required this.keyPoints,
    required this.actionItems,
    required this.transcript,
    required this.response,
  });

  /// Check if action items are present and meaningful
  bool get hasActionItems =>
      actionItems.isNotEmpty &&
      actionItems.toLowerCase() != 'none' &&
      actionItems.toLowerCase() != 'n/a';
}
