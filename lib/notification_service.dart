import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'fullscreen_alert_page.dart';

/// Top-level background message handler — must be a top-level function.
@pragma('vm:entry-point')
Future<void> firebaseBackgroundMessageHandler(RemoteMessage message) async {
  // Firebase is already initialized by the time this is called.
  NotificationService.instance.showLocalNotification(message);
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// A navigator key that must be set as [MaterialApp.navigatorKey].
  /// Used to navigate to [FullScreenAlertPage] without a BuildContext.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// Payload string embedded in every fullscreen intent notification.
  static const fullScreenPayload = 'fullscreen_alert';

  final FirebaseMessaging _fcm = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  /// Stream that emits every [RemoteMessage] the app receives while in the foreground.
  final StreamController<RemoteMessage> _foregroundMessageController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get foregroundMessages =>
      _foregroundMessageController.stream;

  /// Stream that emits a [RemoteMessage] when the app is opened via a notification.
  final StreamController<RemoteMessage> _notificationOpenedController =
      StreamController<RemoteMessage>.broadcast();

  Stream<RemoteMessage> get notificationOpened =>
      _notificationOpenedController.stream;

  static const _channelId = 'high_importance_channel';
  static const _channelName = 'High Importance Notifications';

  // Dedicated channel for full-screen intent notifications (calls, alarms, etc.)
  static const _fullScreenChannelId = 'fullscreen_intent_channel';
  static const _fullScreenChannelName = 'Full-Screen Alerts';

  // Native MethodChannel for USE_FULL_SCREEN_INTENT permission (Android 14+)
  static const _fullScreenMethodChannel = MethodChannel(
    'com.example.flutter_notification_app/full_screen_intent',
  );

  bool _fullScreenIntentGranted = false;
  bool _notificationPermissionGranted = false;

  /// Whether the USE_FULL_SCREEN_INTENT permission is currently granted.
  bool get canUseFullScreenIntent => _fullScreenIntentGranted;

  /// Whether the user has granted notification (alert/sound/badge) permission.
  bool get notificationPermissionGranted => _notificationPermissionGranted;

  Future<void> initialize() async {
    await _initLocalNotifications();
    await _requestPermissions();
    await _checkFullScreenIntentPermission();
    await _setupFcmHandlers();
  }

  // ─── Local notifications ──────────────────────────────────────────────────

  Future<void> _initLocalNotifications() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    // Standard high-importance channel
    const channel = AndroidNotificationChannel(
      _channelId,
      _channelName,
      importance: Importance.max,
    );

    // Full-screen intent channel — max importance required for lock-screen display
    const fullScreenChannel = AndroidNotificationChannel(
      _fullScreenChannelId,
      _fullScreenChannelName,
      importance: Importance.max,
    );

    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >();
    await androidPlugin?.createNotificationChannel(channel);
    await androidPlugin?.createNotificationChannel(fullScreenChannel);
  }

  void _onNotificationTapped(NotificationResponse response) {
    if (response.payload == fullScreenPayload) {
      debugPrint('pressed ok from the fullscreen notification');
      navigatorKey.currentState?.pushNamed(FullScreenAlertPage.routeName);
    }
  }

  void showLocalNotification(RemoteMessage message) {
    final notification = message.notification;
    if (notification == null) return;

    _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          importance: Importance.max,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
    );
  }

  /// Shows a full-screen intent notification that appears over the lock screen
  /// on Android. Falls back to a regular high-importance notification if the
  /// USE_FULL_SCREEN_INTENT permission is not granted (Android 14+).
  ///
  /// [id] must be unique per active notification.
  Future<void> showFullScreenNotification({
    required int id,
    required String title,
    required String body,
    String? payload,

    /// Category hint — use [AndroidNotificationCategory.call] for incoming
    /// calls, [AndroidNotificationCategory.alarm] for alarms, etc.
    AndroidNotificationCategory category = AndroidNotificationCategory.call,
  }) async {
    // Default payload so _onNotificationTapped can route to FullScreenAlertPage.
    final resolvedPayload = payload ?? fullScreenPayload;

    // On Android 14+ we can only use full-screen intent when the permission
    // is granted. On older Android versions it is always allowed.
    final useFullScreen = Platform.isAndroid && _fullScreenIntentGranted;

    await _localNotifications.show(
      id,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          useFullScreen ? _fullScreenChannelId : _channelId,
          useFullScreen ? _fullScreenChannelName : _channelName,
          importance: Importance.max,
          priority: Priority.max,
          category: category,
          icon: '@mipmap/ic_launcher',
          // fullScreenIntent triggers the lock-screen overlay on Android
          fullScreenIntent: useFullScreen,
          // Keep notification visible on the lock screen
          visibility: NotificationVisibility.public,
          // Wake screen and keep notification alive until dismissed
          ongoing: false,
          autoCancel: true,
        ),
        iOS: const DarwinNotificationDetails(
          interruptionLevel: InterruptionLevel.timeSensitive,
        ),
      ),
      payload: resolvedPayload,
    );
  }

  // ─── Permissions ──────────────────────────────────────────────────────────

  Future<void> _requestPermissions() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    _notificationPermissionGranted = settings.authorizationStatus ==
        AuthorizationStatus.authorized ||
        settings.authorizationStatus == AuthorizationStatus.provisional;
  }

  /// Re-requests notification permission.
  /// - If the system dialog is shown, waits for the user's answer.
  /// - If the permission is permanently denied, opens the app notification
  ///   settings page so the user can enable it manually.
  Future<void> requestNotificationPermission() async {
    await _requestPermissions();
    // If still not granted after the dialog, the user has permanently denied
    // it. Open the settings page as a fallback.
    if (!_notificationPermissionGranted) {
      await openNotificationSettings();
    }
  }

  /// Opens the system app notification settings page.
  Future<void> openNotificationSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _fullScreenMethodChannel.invokeMethod<void>('openNotificationSettings');
    } catch (_) {}
  }

  /// Checks the USE_FULL_SCREEN_INTENT permission (Android 14+ / API 34+).
  /// Uses a native MethodChannel so the real system value is always returned.
  Future<void> _checkFullScreenIntentPermission() async {
    if (!Platform.isAndroid) {
      _fullScreenIntentGranted = true;
      return;
    }
    try {
      final granted = await _fullScreenMethodChannel
          .invokeMethod<bool>('canUseFullScreenIntent');
      _fullScreenIntentGranted = granted ?? true;
    } catch (_) {
      _fullScreenIntentGranted = true;
    }
  }

  /// Re-checks the permission status (call after returning from Settings).
  Future<void> refreshFullScreenIntentPermission() =>
      _checkFullScreenIntentPermission();

  /// Opens the system Settings page where the user can grant
  /// USE_FULL_SCREEN_INTENT for this app (Android 14+).
  Future<bool> requestFullScreenIntentPermission() async {
    if (!Platform.isAndroid) return false;
    try {
      await _fullScreenMethodChannel
          .invokeMethod<void>('openFullScreenIntentSettings');
      return true;
    } catch (_) {
      return false;
    }
  }

  // ─── FCM handlers ─────────────────────────────────────────────────────────

  Future<void> _setupFcmHandlers() async {
    // Foreground messages — show a local notification because FCM suppresses UI.
    FirebaseMessaging.onMessage.listen((message) {
      showLocalNotification(message);
      _foregroundMessageController.add(message);
    });

    // App opened from a notification while it was in the background.
    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _notificationOpenedController.add(message);
    });

    // App launched from a terminated state via a notification.
    final initialMessage = await _fcm.getInitialMessage();
    if (initialMessage != null) {
      _notificationOpenedController.add(initialMessage);
    }

    // Register the background handler.
    FirebaseMessaging.onBackgroundMessage(firebaseBackgroundMessageHandler);
  }

  // ─── Helpers ──────────────────────────────────────────────────────────────

  /// Returns the FCM registration token for this device.
  Future<String?> getToken() => _fcm.getToken();

  /// Subscribe the device to a topic, e.g. 'all'.
  Future<void> subscribeToTopic(String topic) => _fcm.subscribeToTopic(topic);

  void dispose() {
    _foregroundMessageController.close();
    _notificationOpenedController.close();
  }
}
