import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:audio_waveforms/audio_waveforms.dart';

/// Service for handling native audio recording using audio_waveforms package.
/// Provides integrated waveform visualization via RecorderController.
class AudioRecorderService {
  static const Duration _operationTimeout = Duration(seconds: 3);

  RecorderController _recorderController = RecorderController();

  bool _isRecording = false;
  bool _isPaused = false;
  bool _isDisposed = false;
  bool _isStopInProgress = false;
  String? _currentRecordingPath;
  DateTime? _recordingStartTime;
  Duration _pausedDuration = Duration.zero;
  DateTime? _pauseStartTime;

  // Stream controllers for UI updates
  final StreamController<Duration> _durationController =
      StreamController<Duration>.broadcast();
  final StreamController<RecordingState> _stateController =
      StreamController<RecordingState>.broadcast();

  Timer? _durationTimer;

  // Getters
  bool get isRecording => _isRecording;
  bool get isPaused => _isPaused;
  Stream<Duration> get durationStream => _durationController.stream;
  Stream<RecordingState> get stateStream => _stateController.stream;

  RecorderController get _controller => _recorderController;

  /// Check and request microphone permission
  Future<bool> requestPermission() async {
    return await _controller.checkPermission();
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    return await _controller.checkPermission();
  }

  /// Start recording audio
  Future<bool> startRecording() async {
    if (_isDisposed) return false;

    try {
      // Check permission first
      if (!await hasPermission()) {
        debugPrint('AudioRecorder: Microphone permission denied');
        return false;
      }

      // Generate unique file path
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${dir.path}/recording_$timestamp.m4a';

      // Start recording with RecorderController
      await _controller.record(path: _currentRecordingPath)
          .timeout(_operationTimeout);

      _isRecording = true;
      _isPaused = false;
      _recordingStartTime = DateTime.now();
      _pausedDuration = Duration.zero;

      _startDurationTimer();
      _emitState(RecordingState.recording);

      debugPrint('AudioRecorder: Started recording to $_currentRecordingPath');
      return true;
    } on TimeoutException catch (e) {
      debugPrint(
        'AudioRecorder: Start timed out after ${_operationTimeout.inSeconds}s: $e',
      );
      await _recoverController('start timeout');
      return false;
    } catch (e) {
      debugPrint('AudioRecorder: Failed to start recording: $e');
      await _recoverController('start failure');
      return false;
    }
  }

  /// Pause recording
  Future<void> pauseRecording() async {
    if (_isDisposed || !_isRecording || _isPaused) return;

    try {
      await _controller.pause().timeout(_operationTimeout);
      _isPaused = true;
      _pauseStartTime = DateTime.now();
      _durationTimer?.cancel();
      _emitState(RecordingState.paused);
      debugPrint('AudioRecorder: Paused');
    } on TimeoutException catch (e) {
      debugPrint(
        'AudioRecorder: Pause timed out after ${_operationTimeout.inSeconds}s: $e',
      );
    } catch (e) {
      debugPrint('AudioRecorder: Failed to pause: $e');
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    if (_isDisposed || !_isRecording || !_isPaused) return;

    try {
      await _controller.record().timeout(_operationTimeout);
      _isPaused = false;

      // Track paused duration
      if (_pauseStartTime != null) {
        _pausedDuration += DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }

      _startDurationTimer();
      _emitState(RecordingState.recording);
      debugPrint('AudioRecorder: Resumed');
    } on TimeoutException catch (e) {
      debugPrint(
        'AudioRecorder: Resume timed out after ${_operationTimeout.inSeconds}s: $e',
      );
    } catch (e) {
      debugPrint('AudioRecorder: Failed to resume: $e');
    }
  }

  /// Stop recording and return the file (converted to WAV)
  Future<File?> stopRecording() async {
    if (_isDisposed || !_isRecording || _isStopInProgress) return null;

    _isStopInProgress = true;

    try {
      final path = await _controller.stop().timeout(_operationTimeout);
      final resolvedPath = (path != null && path.isNotEmpty)
          ? path
          : _currentRecordingPath;
      _finishRecordingSession();

      if (resolvedPath != null && resolvedPath.isNotEmpty) {
        final file = File(resolvedPath);
        if (await file.exists()) {
          debugPrint('AudioRecorder: Stopped recording at $resolvedPath');
          // Return raw file immediately - let ProcessingState handle conversion in background
          return file;
        }
      }

      debugPrint('AudioRecorder: Stopped but no file returned');
      return null;
    } on TimeoutException catch (e) {
      debugPrint(
        'AudioRecorder: Stop timed out after ${_operationTimeout.inSeconds}s: $e',
      );
      await _recoverController('stop timeout');
      return null;
    } catch (e) {
      debugPrint('AudioRecorder: Failed to stop: $e');
      await _recoverController('stop failure');
      return null;
    } finally {
      _isStopInProgress = false;
    }
  }

  /// Cancel recording and delete the file
  Future<void> cancelRecording() async {
    if (_isDisposed || !_isRecording) return;

    // If a stop is already in flight, do not wait on it.
    // Force the UI back to idle and recreate the controller immediately.
    if (_isStopInProgress) {
      debugPrint('AudioRecorder: Forcing cancel while stop is in progress');
      await _recoverController('forced cancel while stopping', deleteFile: true);
      return;
    }

    try {
      await _controller.stop().timeout(_operationTimeout);
      await _finishRecordingSession(deleteFile: true);
      debugPrint('AudioRecorder: Cancelled and deleted file');
    } on TimeoutException catch (e) {
      debugPrint(
        'AudioRecorder: Cancel timed out after ${_operationTimeout.inSeconds}s: $e',
      );
      await _recoverController('cancel timeout', deleteFile: true);
    } catch (e) {
      debugPrint('AudioRecorder: Failed to cancel: $e');
      await _recoverController('cancel failure', deleteFile: true);
    } finally {
      if (!_isDisposed) {
        _isStopInProgress = false;
      }
    }
  }

  /// Get current recording duration
  Duration get currentDuration {
    if (_recordingStartTime == null) return Duration.zero;

    final elapsed = DateTime.now().difference(_recordingStartTime!);
    return elapsed - _pausedDuration;
  }

  void _startDurationTimer() {
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (
      _,
    ) async {
      if (_isRecording && !_isPaused) {
        _durationController.add(currentDuration);
      }
    });
  }

  Future<void> _finishRecordingSession({bool deleteFile = false}) async {
    _durationTimer?.cancel();
    _isRecording = false;
    _isPaused = false;
    _recordingStartTime = null;
    _pausedDuration = Duration.zero;
    _pauseStartTime = null;
    final path = _currentRecordingPath;
    _currentRecordingPath = null;

    if (deleteFile && path != null) {
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
      }
    }

    _emitState(RecordingState.idle);
    await _resetController('recording session finished');
  }

  Future<void> _recoverController(
    String reason, {
    bool deleteFile = false,
  }) async {
    await _finishRecordingSession(deleteFile: deleteFile);
    debugPrint('AudioRecorder: Recovered controller after $reason');
  }

  void _emitState(RecordingState state) {
    if (_isDisposed || _stateController.isClosed) return;
    _stateController.add(state);
  }

  Future<void> _resetController(String reason) async {
    if (_isDisposed) return;

    final oldController = _recorderController;
    try {
      oldController.dispose();
    } catch (e) {
      debugPrint('AudioRecorder: Failed to dispose controller after $reason: $e');
    }
    _recorderController = RecorderController();
    debugPrint('AudioRecorder: Reset recorder controller after $reason');
  }

  /// Dispose resources
  void dispose() {
    _isDisposed = true;
    _durationTimer?.cancel();
    try {
      _recorderController.dispose();
    } catch (_) {}
    _durationController.close();
    _stateController.close();
  }
}

/// Recording state enum for UI
enum RecordingState { idle, recording, paused }
