import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vm_summ/providers/processing_state.dart';
import 'package:vm_summ/services/audio_converter.dart';
import 'package:vm_summ/services/gemma_audio_service.dart';
import 'package:vm_summ/services/share_handler_service.dart';
import 'package:vm_summ/services/summary_storage_service.dart';

const MethodChannel _pathProviderChannel =
    MethodChannel('plugins.flutter.io/path_provider');

class FakeAudioConverter extends AudioConverter {
  @override
  Future<void> initialize() async {}

  @override
  Future<File> convertTo16kMonoWav(File inputFile) async => inputFile;
}

class FakeGemmaAudioService extends GemmaAudioService {
  String? lastSystemInstruction;
  String? lastQueryInstruction;
  String? lastTranscriptionSystem;
  String? lastTranscriptionPrompt;
  bool initialized = false;

  @override
  Future<void> initializeWithBundledModel({
    void Function(ModelDownloadProgress)? onProgress,
  }) async {
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

    return GemmaAudioResult(
      response: 'response',
      transcript: 'transcript',
      title: null,
      summary: 'Test summary',
      keyPoints: const ['Point one'],
      actionItems: 'None',
    );
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

class ThrowingShareHandlerService extends ShareHandlerService {
  @override
  Future<void> initialize() async {
    throw Exception('share handler unavailable');
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
      await File('${docsDir.path}/processing.lock')
          .writeAsString(DateTime.now().toIso8601String());

      final state = ProcessingState(enableBackgroundServices: false);
      await state.startupReady;

      expect(state.queueItems, hasLength(1));
      expect(state.queueItems.single.status, QueueItemStatus.failed);
      expect(state.queueItems.single.errorMessage, 'Interrupted by app restart');
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
      await File('${tempDir.path}/queue.json').writeAsString(
        jsonEncode([existingItem.toJson()]),
      );

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

  test('startup still completes when share handler initialization fails', () async {
    final state = ProcessingState(
      shareHandlerService: ThrowingShareHandlerService(),
      enableBackgroundServices: true,
      enableNotifications: false,
    );

    await state.startupReady;

    expect(state.processedFilePathsDebug, isEmpty);
  });
}
