import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';

/// Service for handling native audio recording
class AudioRecorderService {
  final AudioRecorder _recorder = AudioRecorder();

  bool _isRecording = false;
  bool _isPaused = false;
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

  /// Check and request microphone permission
  Future<bool> requestPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Check if microphone permission is granted
  Future<bool> hasPermission() async {
    return await Permission.microphone.isGranted;
  }

  /// Start recording audio
  Future<bool> startRecording() async {
    try {
      // Check permission first
      if (!await hasPermission()) {
        final granted = await requestPermission();
        if (!granted) {
          debugPrint('AudioRecorder: Microphone permission denied');
          return false;
        }
      }

      // Check if recorder is available
      if (!await _recorder.hasPermission()) {
        debugPrint('AudioRecorder: Recorder permission check failed');
        return false;
      }

      // Generate unique file path
      final dir = await getApplicationDocumentsDirectory();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      _currentRecordingPath = '${dir.path}/recording_$timestamp.m4a';

      // Configure and start recording
      await _recorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: _currentRecordingPath!,
      );

      _isRecording = true;
      _isPaused = false;
      _recordingStartTime = DateTime.now();
      _pausedDuration = Duration.zero;

      _startDurationTimer();
      _stateController.add(RecordingState.recording);

      debugPrint('AudioRecorder: Started recording to $_currentRecordingPath');
      return true;
    } catch (e) {
      debugPrint('AudioRecorder: Failed to start recording: $e');
      return false;
    }
  }

  /// Pause recording
  Future<void> pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    try {
      await _recorder.pause();
      _isPaused = true;
      _pauseStartTime = DateTime.now();
      _durationTimer?.cancel();
      _stateController.add(RecordingState.paused);
      debugPrint('AudioRecorder: Paused');
    } catch (e) {
      debugPrint('AudioRecorder: Failed to pause: $e');
    }
  }

  /// Resume recording
  Future<void> resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    try {
      await _recorder.resume();
      _isPaused = false;

      // Track paused duration
      if (_pauseStartTime != null) {
        _pausedDuration += DateTime.now().difference(_pauseStartTime!);
        _pauseStartTime = null;
      }

      _startDurationTimer();
      _stateController.add(RecordingState.recording);
      debugPrint('AudioRecorder: Resumed');
    } catch (e) {
      debugPrint('AudioRecorder: Failed to resume: $e');
    }
  }

  /// Stop recording and return the file
  Future<File?> stopRecording() async {
    if (!_isRecording) return null;

    try {
      final path = await _recorder.stop();
      _cleanup();

      if (path != null && path.isNotEmpty) {
        final file = File(path);
        if (await file.exists()) {
          debugPrint('AudioRecorder: Stopped, file at $path');
          return file;
        }
      }

      debugPrint('AudioRecorder: Stopped but no file returned');
      return null;
    } catch (e) {
      debugPrint('AudioRecorder: Failed to stop: $e');
      _cleanup();
      return null;
    }
  }

  /// Cancel recording and delete the file
  Future<void> cancelRecording() async {
    if (!_isRecording) return;

    try {
      await _recorder.stop();

      // Delete the partial file
      if (_currentRecordingPath != null) {
        final file = File(_currentRecordingPath!);
        if (await file.exists()) {
          await file.delete();
          debugPrint('AudioRecorder: Cancelled and deleted file');
        }
      }
    } catch (e) {
      debugPrint('AudioRecorder: Failed to cancel: $e');
    } finally {
      _cleanup();
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
    _durationTimer = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (_isRecording && !_isPaused) {
        _durationController.add(currentDuration);
      }
    });
  }

  void _cleanup() {
    _durationTimer?.cancel();
    _isRecording = false;
    _isPaused = false;
    _currentRecordingPath = null;
    _recordingStartTime = null;
    _pausedDuration = Duration.zero;
    _pauseStartTime = null;
    _stateController.add(RecordingState.idle);
  }

  /// Dispose resources
  void dispose() {
    _durationTimer?.cancel();
    _durationController.close();
    _stateController.close();
    _recorder.dispose();
  }
}

/// Recording state enum for UI
enum RecordingState { idle, recording, paused }
