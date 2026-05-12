import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:share_handler/share_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_summ/providers/processing_state.dart';
import 'package:vm_summ/services/audio_converter.dart';
import 'package:vm_summ/services/foreground_service_adapter.dart';
import 'package:vm_summ/services/gemma_audio_service.dart';
import 'package:vm_summ/services/notification_service.dart';
import 'package:vm_summ/services/share_handler_service.dart';
import 'package:vm_summ/services/summary_storage_service.dart';
import 'package:vm_summ/utils/notification_destination.dart';
import 'package:vm_summ/screens/history_screen.dart';
import 'package:vm_summ/screens/note_detail_screen.dart';

const MethodChannel _pathProviderChannel = MethodChannel(
  'plugins.flutter.io/path_provider',
);

class FakeAudioConverter extends AudioConverter {
  final List<String>? events;

  FakeAudioConverter({this.events});

  @override
  Future<void> initialize() async {
    events?.add('audio.initialize');
  }

  @override
  Future<File> convertTo16kMonoWav(File inputFile) async {
    events?.add('audio.convert');
    return inputFile;
  }
}

class FakeGemmaAudioService extends GemmaAudioService {
  final List<String>? events;
  final List<ModelDownloadProgress> modelProgressEvents;
  final Duration initializeDelay;
  final Duration transcribeDelay;
  String? lastSystemInstruction;
  String? lastQueryInstruction;
  String? lastTranscriptionSystem;
  String? lastTranscriptionPrompt;
  bool initialized = false;

  FakeGemmaAudioService({
    this.events,
    this.modelProgressEvents = const [],
    this.initializeDelay = Duration.zero,
    this.transcribeDelay = Duration.zero,
  });

  @override
  Future<void> initializeWithBundledModel({
    void Function(ModelDownloadProgress)? onProgress,
  }) async {
    events?.add('gemma.initialize');
    for (final progress in modelProgressEvents) {
      onProgress?.call(progress);
      await Future<void>.delayed(Duration.zero);
    }
    if (initializeDelay > Duration.zero) {
      await Future<void>.delayed(initializeDelay);
    }
    initialized = true;
  }

  @override
  Future<GemmaAudioResult> transcribeAndSummarize(
    File audioFile, {
    String? language,
    String? systemInstruction,
    String? queryInstruction,
    String? transcriptionSystem,
    String? transcriptionPrompt,
  }) async {
    lastSystemInstruction = systemInstruction;
    lastQueryInstruction = queryInstruction;
    lastTranscriptionSystem = transcriptionSystem;
    lastTranscriptionPrompt = transcriptionPrompt;
    events?.add('gemma.transcribeAndSummarize');
    if (transcribeDelay > Duration.zero) {
      await Future<void>.delayed(transcribeDelay);
    }

    return GemmaAudioResult(
      response: 'response',
      transcript: 'transcript',
      title: null,
      summary: 'Test summary',
      keyPoints: const ['Point one'],
      actionItems: 'None',
    );
  }

  @override
  Future<GemmaAudioResult> transcribe(
    File audioFile, {
    String? language,
  }) async {
    events?.add('gemma.transcribe');
    return GemmaAudioResult(
      response: 'transcript',
      transcript: 'transcript',
      title: null,
      summary: null,
      keyPoints: const [],
      actionItems: null,
    );
  }

  @override
  Future<GemmaAudioResult> transcribeAndSummarizeLongAudio(
    File audioFile, {
    String? language,
    String? systemInstruction,
    String? queryInstruction,
    String? transcriptionSystem,
    String? transcriptionPrompt,
    void Function(LongAudioPhaseUpdate update)? onPhaseUpdate,
  }) async {
    lastSystemInstruction = systemInstruction;
    lastQueryInstruction = queryInstruction;
    lastTranscriptionSystem = transcriptionSystem;
    lastTranscriptionPrompt = transcriptionPrompt;
    events?.add('gemma.transcribeAndSummarizeLongAudio');
    if (transcribeDelay > Duration.zero) {
      await Future<void>.delayed(transcribeDelay);
    }
    onPhaseUpdate?.call(const LongAudioPhaseUpdate(phase: 'transcribe'));
    onPhaseUpdate?.call(const LongAudioPhaseUpdate(phase: 'summarize'));

    return GemmaAudioResult(
      response: 'response',
      transcript: 'transcript',
      title: null,
      summary: 'Test summary',
      keyPoints: const ['Point one'],
      actionItems: 'None',
    );
  }

  @override
  Future<String> chatWithTranscript(String transcript, String prompt) async {
    events?.add('gemma.chat');
    return 'Chunk summary';
  }
}

class FakeSummaryStorageService extends SummaryStorageService {
  final List<SummaryRecord> _records = [];

  @override
  Future<SummaryRecord> saveRecord({
    required String sourceFileName,
    String? sourceFilePath,
    required String transcript,
    required String summary,
    required List<String> keyPoints,
    required String actionItems,
    int audioDurationSeconds = 0,
  }) async {
    final record = SummaryRecord(
      id: 'record_${_records.length + 1}',
      createdAt: DateTime.now(),
      sourceFileName: sourceFileName,
      sourceFilePath: sourceFilePath,
      transcript: transcript,
      summary: summary,
      keyPoints: keyPoints,
      actionItems: actionItems,
      transcriptLength: transcript.length,
      audioDurationSeconds: audioDurationSeconds,
    );
    _records.insert(0, record);
    return record;
  }

  @override
  Future<List<SummaryRecord>> getAllRecords() async =>
      List.unmodifiable(_records);

  @override
  Future<SummaryRecord?> getRecord(String id) async {
    try {
      return _records.firstWhere((record) => record.id == id);
    } catch (_) {
      return null;
    }
  }
}

class RecordingNotificationService extends NotificationService {
  final String? launchPayload;
  final List<Map<String, Object?>> completionNotifications = [];
  final List<Map<String, Object?>> processingNotifications = [];
  final List<Map<String, Object?>> errorNotifications = [];

  RecordingNotificationService({this.launchPayload}) : super.test();

  @override
  Future<void> initialize({
    required void Function(NotificationResponse)?
    onDidReceiveNotificationResponse,
  }) async {}

  @override
  String? get launchNotificationPayload => launchPayload;

  @override
  Future<void> showCompletionNotification({
    required String title,
    required String body,
    int notificationId = 1001,
    String? payload,
  }) async {
    completionNotifications.add({
      'title': title,
      'body': body,
      'notificationId': notificationId,
      'payload': payload,
    });
  }

  @override
  Future<void> showProcessingNotification({
    required String title,
    required String body,
  }) async {
    processingNotifications.add({'title': title, 'body': body});
  }

  @override
  Future<void> showErrorNotification({
    required String title,
    required String body,
    int notificationId = 1001,
  }) async {
    errorNotifications.add({
      'title': title,
      'body': body,
      'notificationId': notificationId,
    });
  }
}

class ThrowingShareHandlerService extends ShareHandlerService {
  @override
  Future<void> initialize() async {
    throw Exception('share handler unavailable');
  }
}

class EmittingShareHandlerService extends ShareHandlerService {
  final File fileToEmit;
  bool _emitted = false;

  EmittingShareHandlerService(this.fileToEmit);

  @override
  Future<void> initialize() async {
    if (_emitted) return;
    _emitted = true;
    onFileReceived?.call(fileToEmit);
  }
}

class SlowAudioConverter extends FakeAudioConverter {
  final Duration delay;

  SlowAudioConverter(this.delay, {super.events});

  @override
  Future<File> convertTo16kMonoWav(File inputFile) async {
    await Future<void>.delayed(delay);
    events?.add('audio.convert');
    return inputFile;
  }
}

class RecordingForegroundServiceAdapter extends ForegroundServiceAdapter {
  final List<String> events = [];
  bool running = false;

  @override
  Future<void> initialize() async {
    events.add('foreground.initialize');
  }

  @override
  Future<bool> isRunning() async {
    events.add('foreground.isRunning');
    return running;
  }

  @override
  Future<void> startService({
    required String notificationTitle,
    required String notificationText,
    required TaskHandler Function() callback,
  }) async {
    events.add('foreground.start:$notificationTitle|$notificationText');
    running = true;
  }

  @override
  Future<void> stopService() async {
    events.add('foreground.stop');
    running = false;
  }
}

Future<void> _setDocumentsDir(Directory dir) async {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(_pathProviderChannel, (call) async {
        switch (call.method) {
          case 'getApplicationDocumentsDirectory':
            return dir.path;
          default:
            return null;
        }
      });
}

Future<void> _waitForQueueToDrain(ProcessingState state) async {
  final deadline = DateTime.now().add(const Duration(seconds: 3));
  while (DateTime.now().isBefore(deadline)) {
    if (state.queueCount == 0 && state.currentItem == null) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Queue did not drain in time');
}

Future<void> _waitForCondition(
  bool Function() condition, {
  Duration timeout = const Duration(seconds: 3),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    if (condition()) return;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  fail('Condition was not satisfied in time');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('vm_summ_test_');
    await _setDocumentsDir(tempDir);
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_pathProviderChannel, null);
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('unknown model progress stays non-negative in the UI label', () async {
    final state = ProcessingState(
      audioConverter: FakeAudioConverter(),
      gemmaService: FakeGemmaAudioService(
        modelProgressEvents: [
          ModelDownloadProgress(
            modelName: 'gemma',
            bytesDownloaded: 128,
            totalBytes: 0,
            progress: -1,
            status: 'copying',
          ),
        ],
      ),
      storageService: FakeSummaryStorageService(),
      enableBackgroundServices: false,
      enableNotifications: false,
    );

    var sawUnknownEstimatedState = false;
    state.addListener(() {
      if (state.modelStatus == ModelStatus.copying &&
          state.modelStatusMessage == 'Copying model...' &&
          state.modelDownloadProgress >= 0.0) {
        sawUnknownEstimatedState = true;
      }
      expect(state.modelDownloadProgress, greaterThanOrEqualTo(-1.0));
    });

    await state.initialize();

    expect(sawUnknownEstimatedState, isTrue);
    expect(state.modelStatus, ModelStatus.ready);
    expect(state.modelProgressLabel, '100%');
  });

  test(
    'model copy progress maps bytes and total bytes without jumping to staged cap',
    () async {
      final state = ProcessingState(
        audioConverter: FakeAudioConverter(),
        gemmaService: FakeGemmaAudioService(
          modelProgressEvents: [
            ModelDownloadProgress(
              modelName: 'gemma',
              bytesDownloaded: 50,
              totalBytes: 100,
              progress: -1,
              status: 'copying',
            ),
          ],
        ),
        storageService: FakeSummaryStorageService(),
        enableBackgroundServices: false,
        enableNotifications: false,
      );

      final observedCopyProgress = <double>[];
      state.addListener(() {
        if (state.modelStatus == ModelStatus.copying &&
            state.hasDeterminateModelProgress) {
          observedCopyProgress.add(state.modelDownloadProgress);
        }
      });

      await state.initialize();

      expect(observedCopyProgress, contains(moreOrLessEquals(0.425)));
      expect(state.modelDownloadProgress, 1.0);
    },
  );

  test('engine startup progress advances smoothly and stays capped', () async {
    final state = ProcessingState(
      audioConverter: FakeAudioConverter(),
      gemmaService: FakeGemmaAudioService(
        initializeDelay: const Duration(milliseconds: 700),
      ),
      storageService: FakeSummaryStorageService(),
      enableBackgroundServices: false,
      enableNotifications: false,
    );

    final initFuture = state.initialize();
    await _waitForCondition(
      () =>
          state.modelStatus == ModelStatus.copying &&
          state.modelStatusMessage.contains('Preparing Gemma'),
    );
    final firstProgress = state.modelDownloadProgress;
    await Future<void>.delayed(const Duration(milliseconds: 350));

    expect(state.modelDownloadProgress, greaterThan(firstProgress));
    expect(state.modelDownloadProgress, lessThan(0.96));

    await initFuture;
    expect(state.modelDownloadProgress, 1.0);
  });

  test('overall queue progress advances during long active work', () async {
    final state = ProcessingState(
      audioConverter: SlowAudioConverter(const Duration(milliseconds: 300)),
      gemmaService: FakeGemmaAudioService(
        transcribeDelay: const Duration(milliseconds: 700),
      ),
      storageService: FakeSummaryStorageService(),
      enableBackgroundServices: false,
      enableNotifications: false,
    );

    final firstFile = File('${tempDir.path}/first.ogg');
    final secondFile = File('${tempDir.path}/second.ogg');
    await firstFile.writeAsString('audio');
    await secondFile.writeAsString('audio');

    expect(state.queueFile(firstFile), isNotNull);
    expect(state.queueFile(secondFile), isNotNull);
    final initFuture = state.initialize();

    await _waitForCondition(
      () =>
          state.currentItem != null &&
          state.status == ProcessingStatus.convertingAudio,
    );

    final firstProgress = state.queueProgress;
    await Future<void>.delayed(const Duration(milliseconds: 300));

    expect(state.queueProgress, greaterThan(firstProgress));
    expect(state.queueProgress, lessThan(0.5));
    expect(state.queuePositionLabel, 'Processing 1 of 2');

    await initFuture;
    await _waitForQueueToDrain(state);
    expect(state.displayQueueItems, isEmpty);
  });

  test('saving a processed summary increments history revision', () async {
    final state = ProcessingState(
      audioConverter: FakeAudioConverter(),
      gemmaService: FakeGemmaAudioService(),
      storageService: FakeSummaryStorageService(),
      enableBackgroundServices: false,
      enableNotifications: false,
    );

    final audioFile = File('${tempDir.path}/history_revision.ogg');
    await audioFile.writeAsString('audio');

    expect(state.historyRevision, 0);
    expect(state.queueFile(audioFile), isNotNull);
    await state.initialize();
    await _waitForQueueToDrain(state);

    expect(state.historyRevision, 1);
  });

  test(
    'startup recovery marks stale processing items as failed after queue load',
    () async {
      final docsDir = Directory(tempDir.path);
      final audioFile = File('${docsDir.path}/stale.ogg');
      await audioFile.writeAsString('audio');

      final queueFile = File('${docsDir.path}/queue.json');
      final staleItem = QueueItem(
        id: 'stale',
        file: audioFile,
        fileName: 'stale.ogg',
        fileSizeBytes: await audioFile.length(),
        addedAt: DateTime.now(),
        status: QueueItemStatus.processing,
      );
      await queueFile.writeAsString(jsonEncode([staleItem.toJson()]));
      await File(
        '${docsDir.path}/processing.lock',
      ).writeAsString(DateTime.now().toIso8601String());

      final state = ProcessingState(enableBackgroundServices: false);
      await state.startupReady;

      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.status, QueueItemStatus.failed);
      expect(
        state.queueItems.single.errorMessage,
        'Interrupted by app restart',
      );
      expect(state.processedFilePathsDebug, contains(audioFile.path));
    },
  );

  test('removing or clearing items clears dedupe paths', () async {
    final state = ProcessingState(enableBackgroundServices: false);
    await state.startupReady;

    final audioFile = File('${tempDir.path}/remove.ogg');
    await audioFile.writeAsString('audio');

    final item = state.queueFile(audioFile);
    expect(item, isNotNull);
    expect(state.processedFilePathsDebug, contains(audioFile.path));

    expect(state.removeFromQueue(item!.id), isTrue);
    expect(state.processedFilePathsDebug, isNot(contains(audioFile.path)));

    final queuedAgain = state.queueFile(audioFile);
    expect(queuedAgain, isNotNull);
    expect(state.queueCount, 1);

    final secondFile = File('${tempDir.path}/clear.ogg');
    await secondFile.writeAsString('audio');
    expect(state.queueFile(secondFile), isNotNull);
    expect(state.queueCount, 2);

    state.clearQueue();
    await state.queuePersistenceIdle;
    expect(state.queueCount, 0);
    expect(state.processedFilePathsDebug, isEmpty);
  });

  test(
    'initialize waits for persisted prompts before processing queued files',
    () async {
      SharedPreferences.setMockInitialValues({
        'systemInstruction': 'custom system',
        'queryInstruction': 'custom query',
        'transcriptionSystem': 'custom transcription system',
        'transcriptionPrompt': 'custom transcription prompt',
      });

      final gemmaService = FakeGemmaAudioService();
      final state = ProcessingState(
        audioConverter: FakeAudioConverter(),
        gemmaService: gemmaService,
        storageService: FakeSummaryStorageService(),
        enableBackgroundServices: false,
        enableNotifications: false,
      );

      final audioFile = File('${tempDir.path}/prompt.ogg');
      await audioFile.writeAsString('audio');

      expect(state.queueFile(audioFile), isNotNull);
      await state.initialize();
      await _waitForQueueToDrain(state);

      expect(gemmaService.initialized, isTrue);
      expect(gemmaService.lastSystemInstruction, 'custom system');
      expect(gemmaService.lastQueryInstruction, 'custom query');
      expect(
        gemmaService.lastTranscriptionSystem,
        'custom transcription system',
      );
      expect(
        gemmaService.lastTranscriptionPrompt,
        'custom transcription prompt',
      );
      expect(state.processedFilePathsDebug, isEmpty);

      final requeued = state.queueFile(audioFile);
      expect(requeued, isNotNull);
      await state.queuePersistenceIdle;
    },
  );

  test(
    'queue item added during startup is not removed by disk reconciliation',
    () async {
      final existingFile = File('${tempDir.path}/existing.ogg');
      await existingFile.writeAsString('audio');
      final existingItem = QueueItem(
        id: 'existing',
        file: existingFile,
        fileName: 'existing.ogg',
        fileSizeBytes: await existingFile.length(),
        addedAt: DateTime.now(),
      );
      await File(
        '${tempDir.path}/queue.json',
      ).writeAsString(jsonEncode([existingItem.toJson()]));

      final state = ProcessingState(enableBackgroundServices: false);
      final newFile = File('${tempDir.path}/new.ogg');
      await newFile.writeAsString('audio');

      final queued = state.queueFile(newFile);
      expect(queued, isNotNull);

      await state.startupReady;
      await state.queuePersistenceIdle;

      expect(
        state.queueItems.map((item) => item.file.path),
        containsAll([existingFile.path, newFile.path]),
      );
      expect(state.processedFilePathsDebug, contains(newFile.path));
    },
  );

  test(
    'startup still completes when share handler initialization fails',
    () async {
      final state = ProcessingState(
        shareHandlerService: ThrowingShareHandlerService(),
        enableBackgroundServices: true,
        enableNotifications: false,
      );

      await state.startupReady;

      expect(state.processedFilePathsDebug, isEmpty);
    },
  );

  test(
    'cold-start shared audio is queued and processed after model init',
    () async {
      final sharedAudio = File('${tempDir.path}/cold_start.ogg');
      await sharedAudio.writeAsString('audio');

      final state = ProcessingState(
        audioConverter: SlowAudioConverter(const Duration(milliseconds: 500)),
        gemmaService: FakeGemmaAudioService(),
        storageService: FakeSummaryStorageService(),
        shareHandlerService: EmittingShareHandlerService(sharedAudio),
        enableBackgroundServices: true,
        enableNotifications: false,
      );

      await state.startupReady;
      expect(state.queueCount, 1);
      expect(state.currentItem, isNull);
      expect(state.queueItems.single.status, QueueItemStatus.pending);

      final initFuture = state.initialize();
      await _waitForCondition(() => state.currentItem != null);

      expect(state.queueCount, 1);
      expect(state.displayQueueItems, hasLength(1));
      expect(state.displayQueueItems.single.id, state.currentItem!.id);

      await initFuture;
      await _waitForQueueToDrain(state);

      expect(state.queueCount, 0);
      expect(state.currentItem, isNull);
      expect(state.summaryResult, isNotNull);
    },
  );

  test(
    'completion notification payload uses the saved summary record id',
    () async {
      final storage = FakeSummaryStorageService();
      final notificationService = RecordingNotificationService();

      final state = ProcessingState(
        audioConverter: SlowAudioConverter(const Duration(milliseconds: 250)),
        gemmaService: FakeGemmaAudioService(),
        storageService: storage,
        notificationService: notificationService,
        enableBackgroundServices: true,
        enableNotifications: true,
      );

      final audioFile = File('${tempDir.path}/payload.ogg');
      await audioFile.writeAsString('audio');

      expect(state.queueFile(audioFile), isNotNull);
      await state.initialize();
      await _waitForQueueToDrain(state);

      expect(notificationService.completionNotifications, hasLength(1));
      final completion = notificationService.completionNotifications.single;
      expect(completion['payload'], isNotNull);
      expect(completion['payload'], isNot('payload.ogg'));

      final records = await storage.getAllRecords();
      expect(records, hasLength(1));
      expect(completion['payload'], records.single.id);
    },
  );

  test(
    'startup stores a launch notification payload for later navigation',
    () async {
      final storage = FakeSummaryStorageService();
      final savedRecord = await storage.saveRecord(
        sourceFileName: 'Launch payload',
        sourceFilePath: '/tmp/launch.ogg',
        transcript: 'transcript',
        summary: 'summary',
        keyPoints: const ['Point one'],
        actionItems: 'None',
      );

      final notificationService = RecordingNotificationService(
        launchPayload: savedRecord.id,
      );

      final state = ProcessingState(
        storageService: storage,
        notificationService: notificationService,
        enableBackgroundServices: true,
        enableNotifications: true,
      );

      await state.startupReady;

      expect(state.consumePendingSummaryNotificationPayload(), savedRecord.id);
      expect(await state.resolveSummaryRecord(savedRecord.id), isNotNull);
    },
  );

  test('queue display exposes the processing item only once', () async {
    final state = ProcessingState(
      audioConverter: SlowAudioConverter(const Duration(milliseconds: 500)),
      gemmaService: FakeGemmaAudioService(),
      storageService: FakeSummaryStorageService(),
      enableBackgroundServices: false,
      enableNotifications: false,
    );

    final audioFile = File('${tempDir.path}/visible.ogg');
    await audioFile.writeAsString('audio');

    expect(state.queueFile(audioFile), isNotNull);
    final initFuture = state.initialize();

    await _waitForCondition(() => state.currentItem != null);

    expect(state.queueCount, 1);
    expect(state.displayQueueItems, hasLength(1));
    expect(state.displayQueueItems.single.id, state.currentItem!.id);
    expect(
      state.displayQueueItems.map((item) => item.id).toSet(),
      hasLength(state.displayQueueItems.length),
    );

    await initFuture;
    await _waitForQueueToDrain(state);
  });

  test('shared audio attachment helper prefers audio type over extension', () {
    final audioAttachment = SharedAttachment(
      path: '/tmp/voice-message',
      type: SharedAttachmentType.audio,
    );
    final fallbackAttachment = SharedAttachment(
      path: '/tmp/voice-message.ogg',
      type: SharedAttachmentType.file,
    );
    final rejectedAttachment = SharedAttachment(
      path: '/tmp/voice-message.txt',
      type: SharedAttachmentType.file,
    );

    expect(assessSharedAudioAttachment(audioAttachment).accepted, isTrue);
    expect(assessSharedAudioAttachment(fallbackAttachment).accepted, isTrue);
    expect(assessSharedAudioAttachment(rejectedAttachment).accepted, isFalse);
  });

  test(
    'foreground service starts before model init and stops when no queue exists',
    () async {
      final events = <String>[];
      final foreground = RecordingForegroundServiceAdapter();
      final state = ProcessingState(
        audioConverter: FakeAudioConverter(events: events),
        gemmaService: FakeGemmaAudioService(events: events),
        storageService: FakeSummaryStorageService(),
        foregroundServiceAdapter: foreground,
        enableBackgroundServices: true,
        enableNotifications: false,
      );

      await state.initialize();

      expect(foreground.events, isNotEmpty);
      expect(foreground.events.first, startsWith('foreground.initialize'));
      expect(
        foreground.events,
        contains(
          'foreground.start:Preparing Voice Notes|Loading Gemma 4 E2B model...',
        ),
      );
      expect(foreground.events.last, 'foreground.stop');
      expect(
        events,
        containsAllInOrder(['audio.initialize', 'gemma.initialize']),
      );
      expect(foreground.running, isFalse);
    },
  );

  test(
    'foreground service stays alive until queued processing drains',
    () async {
      final events = <String>[];
      final foreground = RecordingForegroundServiceAdapter();
      final state = ProcessingState(
        audioConverter: SlowAudioConverter(
          const Duration(milliseconds: 250),
          events: events,
        ),
        gemmaService: FakeGemmaAudioService(events: events),
        storageService: FakeSummaryStorageService(),
        foregroundServiceAdapter: foreground,
        enableBackgroundServices: true,
        enableNotifications: false,
      );

      final audioFile = File('${tempDir.path}/foreground_queue.ogg');
      await audioFile.writeAsString('audio');

      expect(state.queueFile(audioFile), isNotNull);
      final initFuture = state.initialize();

      await _waitForCondition(() => state.currentItem != null);
      expect(foreground.running, isTrue);
      expect(
        foreground.events,
        contains(
          'foreground.start:Preparing Voice Notes|Loading Gemma 4 E2B model...',
        ),
      );
      expect(foreground.events, isNot(contains('foreground.stop')));

      await initFuture;
      await _waitForQueueToDrain(state);
      await _waitForCondition(() => !foreground.running);

      expect(foreground.running, isFalse);
      expect(foreground.events.last, 'foreground.stop');
      expect(events, contains('audio.convert'));
      expect(events, contains('gemma.transcribeAndSummarizeLongAudio'));
    },
  );

  test(
    'notification destination helper returns the history detail UI',
    () async {
      final storage = FakeSummaryStorageService();
      final savedRecord = await storage.saveRecord(
        sourceFileName: 'Notification payload',
        sourceFilePath: '${tempDir.path}/notification.ogg',
        transcript: 'transcript',
        summary: 'summary',
        keyPoints: const ['Point one'],
        actionItems: 'None',
      );

      final destination = notificationDestinationForRecord(savedRecord);
      final fallback = notificationFallbackDestination();

      expect(destination, isA<NoteDetailScreen>());
      expect(fallback, isA<HistoryScreen>());
    },
  );
}
