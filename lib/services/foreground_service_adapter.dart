import 'package:flutter/foundation.dart';
import 'package:flutter_foreground_task/flutter_foreground_task.dart';

abstract class ForegroundServiceAdapter {
  Future<void> initialize();
  Future<bool> isRunning();
  Future<void> startService({
    required String notificationTitle,
    required String notificationText,
    required TaskHandler Function() callback,
  });
  Future<void> stopService();
}

class FlutterForegroundServiceAdapter implements ForegroundServiceAdapter {
  bool _initialized = false;

  @override
  Future<void> initialize() async {
    if (_initialized) return;

    try {
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
      _initialized = true;
    } catch (e) {
      debugPrint('ForegroundService: init unavailable: $e');
    }
  }

  @override
  Future<bool> isRunning() async {
    try {
      return await FlutterForegroundTask.isRunningService;
    } catch (e) {
      debugPrint('ForegroundService: status unavailable: $e');
      return false;
    }
  }

  @override
  Future<void> startService({
    required String notificationTitle,
    required String notificationText,
    required TaskHandler Function() callback,
  }) async {
    try {
      if (await isRunning()) return;

      await FlutterForegroundTask.startService(
        notificationTitle: notificationTitle,
        notificationText: notificationText,
        callback: callback,
      );
    } catch (e) {
      debugPrint('ForegroundService: start unavailable: $e');
    }
  }

  @override
  Future<void> stopService() async {
    try {
      if (await FlutterForegroundTask.isRunningService) {
        await FlutterForegroundTask.stopService();
      }
    } catch (e) {
      debugPrint('ForegroundService: stop unavailable: $e');
    }
  }
}
