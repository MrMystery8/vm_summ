import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _isInitialized = false;

  Future<void> initialize({
    required void Function(NotificationResponse)?
    onDidReceiveNotificationResponse,
  }) async {
    if (_isInitialized) return;

    try {
      const AndroidInitializationSettings initializationSettingsAndroid =
          AndroidInitializationSettings('@mipmap/ic_launcher');

      final DarwinInitializationSettings initializationSettingsDarwin =
          DarwinInitializationSettings(
            requestAlertPermission: true,
            requestBadgePermission: true,
            requestSoundPermission: true,
          );

      final InitializationSettings initializationSettings =
          InitializationSettings(
            android: initializationSettingsAndroid,
            iOS: initializationSettingsDarwin,
            macOS: initializationSettingsDarwin,
          );

      await flutterLocalNotificationsPlugin.initialize(
        initializationSettings,
        onDidReceiveNotificationResponse: onDidReceiveNotificationResponse,
      );

      // Request permissions
      await _requestPermissions();

      _isInitialized = true;
      debugPrint('NotificationService initialized');
    } catch (e) {
      debugPrint('Error initializing NotificationService: $e');
    }
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      final androidImplementation = flutterLocalNotificationsPlugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();

      if (androidImplementation != null) {
        await androidImplementation.requestNotificationsPermission();
      }

      // Also check permission handler for Android 13+
      if (await Permission.notification.isDenied) {
        await Permission.notification.request();
      }
    }
  }

  Future<void> showCompletionNotification({
    required String title,
    required String body,
    String? payload, // Can be ID or Path to navigate to
  }) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'voice_note_processing', // id
          'Voice Note Processing', // name
          channelDescription: 'Notifications for voice note processing status',
          importance: Importance.high,
          priority: Priority.high,
          ticker: 'ticker',
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond, // unique id
      title,
      body,
      notificationDetails,
      payload: payload,
    );
  }

  Future<void> showErrorNotification({
    required String title,
    required String body,
  }) async {
    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
          'voice_note_errors', // id
          'Processing Errors', // name
          channelDescription: 'Notifications for processing errors',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    await flutterLocalNotificationsPlugin.show(
      DateTime.now().millisecond,
      title,
      body,
      notificationDetails,
    );
  }
}
