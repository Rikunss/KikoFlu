import 'dart:async';
import 'dart:io';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'log_service.dart';

final _log = LogService.instance;

/// Background message handler — must be a top-level function.
/// Called when a message is received while the app is in the background or terminated.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  _log.info(
    '[FCM] Background message: ${message.messageId}',
    tag: 'FCM',
  );
  _log.info(
    '[FCM]   title: ${message.notification?.title}',
    tag: 'FCM',
  );
  _log.info(
    '[FCM]   body: ${message.notification?.body}',
    tag: 'FCM',
  );
  _log.info(
    '[FCM]   data: ${message.data}',
    tag: 'FCM',
  );
}

/// Service that manages Firebase Cloud Messaging (FCM) for push notifications.
///
/// Handles:
/// - FCM token management (get, refresh, save)
/// - Foreground message handling
/// - Background message handling
/// - Notification display (via flutter_local_notifications)
/// - Message stream for UI consumption
class FcmService {
  static FcmService? _instance;
  static FcmService get instance => _instance ??= FcmService._();

  FcmService._();

  final FirebaseMessaging _messaging = FirebaseMessaging.instance;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();

  String? _fcmToken;
  bool _initialized = false;

  /// Stream controller for incoming messages.
  final StreamController<RemoteMessage> _messageController =
      StreamController<RemoteMessage>.broadcast();

  /// Stream of incoming messages (foreground).
  Stream<RemoteMessage> get onMessage => _messageController.stream;

  /// Current FCM token. Returns null if not initialized.
  String? get fcmToken => _fcmToken;

  /// Initialize FCM service.
  ///
  /// Should be called once during app startup (after Firebase.initializeApp).
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid && !Platform.isIOS) {
      _log.info('[FCM] Platform not supported, skipping', tag: 'FCM');
      return;
    }

    // ignore: avoid_print
    print('[FCM] ===== Initializing FCM Service... =====');
    _log.info('[FCM] Initializing...', tag: 'FCM');

    try {
      // Request permission
      await _requestPermission();

      // Initialize local notifications
      await _initLocalNotifications();

      // Register background handler
      FirebaseMessaging.onBackgroundMessage(
          _firebaseMessagingBackgroundHandler);

      // Get token
      await _getToken();

      // Listen for token refresh
      _messaging.onTokenRefresh.listen((newToken) {
        _fcmToken = newToken;
        _log.info('[FCM] Token refreshed: ${_logToken(newToken)}', tag: 'FCM');
        _onTokenRefresh(newToken);
      });

      // Handle foreground messages
      FirebaseMessaging.onMessage.listen(_handleForegroundMessage);

      // Handle notification tap (app opened from notification)
      FirebaseMessaging.onMessageOpenedApp.listen(_handleNotificationTap);

      // Check if app was opened from a notification (terminated state)
      final initialMessage = await _messaging.getInitialMessage();
      if (initialMessage != null) {
        _log.info('[FCM] App opened from terminated state', tag: 'FCM');
        _handleNotificationTap(initialMessage);
      }

      _initialized = true;
      _log.info('[FCM] Initialized successfully', tag: 'FCM');
    } catch (e) {
      // ignore: avoid_print
      print('[FCM] ===== Init FAILED: $e =====');
      _log.error('[FCM] Initialization failed: $e', tag: 'FCM');
    }
  }

  /// Request notification permission.
  Future<void> _requestPermission() async {
    final settings = await _messaging.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      provisional: false,
      criticalAlert: true,
    );

    // ignore: avoid_print
    print('[FCM] ===== Permission: ${settings.authorizationStatus} =====');
    _log.info(
      '[FCM] Permission status: ${settings.authorizationStatus}',
      tag: 'FCM',
    );

    switch (settings.authorizationStatus) {
      case AuthorizationStatus.authorized:
        _log.info('[FCM] User granted permission', tag: 'FCM');
        break;
      case AuthorizationStatus.provisional:
        _log.info('[FCM] User granted provisional permission', tag: 'FCM');
        break;
      case AuthorizationStatus.denied:
        _log.warning('[FCM] User denied permission', tag: 'FCM');
        break;
      case AuthorizationStatus.notDetermined:
        _log.info('[FCM] Permission not determined', tag: 'FCM');
        break;
    }
  }

  /// Initialize local notifications for displaying notifications in foreground.
  Future<void> _initLocalNotifications() async {
    const androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _localNotifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (details) {
        _log.info(
          '[FCM] Notification tapped: ${details.payload}',
          tag: 'FCM',
        );
      },
    );

    // Create notification channel for Android
    if (Platform.isAndroid) {
      const androidChannel = AndroidNotificationChannel(
        'kikoflu_high_importance',
        'KikoFlu Notifications',
        description: 'Important notifications from KikoFlu',
        importance: Importance.high,
        enableVibration: true,
        playSound: true,
      );

      await _localNotifications
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.createNotificationChannel(androidChannel);
    }
  }

  /// Get FCM token.
  Future<void> _getToken() async {
    try {
      _fcmToken = await _messaging.getToken();
      if (_fcmToken != null) {
        final masked = _logToken(_fcmToken!);
        _log.info('[FCM] Token: $masked', tag: 'FCM');
        // ignore: avoid_print
        print('[FCM] ===== FCM TOKEN: $_fcmToken =====');
      } else {
        _log.warning('[FCM] getToken returned null', tag: 'FCM');
        // ignore: avoid_print
        print('[FCM] ===== getToken returned NULL =====');
      }
    } catch (e) {
      _log.error('[FCM] Failed to get token: $e', tag: 'FCM');
    }
  }

  /// Handle foreground messages — show local notification.
  void _handleForegroundMessage(RemoteMessage message) {
    _log.info(
      '[FCM] Foreground message: ${message.messageId}',
      tag: 'FCM',
    );
    _log.info(
      '[FCM]   title: ${message.notification?.title}',
      tag: 'FCM',
    );
    _log.info(
      '[FCM]   body: ${message.notification?.body}',
      tag: 'FCM',
    );
    _log.info(
      '[FCM]   data: ${message.data}',
      tag: 'FCM',
    );

    // Show local notification
    _showLocalNotification(message);

    // Add to stream for UI consumption
    _messageController.add(message);
  }

  /// Handle notification tap.
  void _handleNotificationTap(RemoteMessage message) {
    _log.info(
      '[FCM] Notification tapped: ${message.messageId}',
      tag: 'FCM',
    );
    _log.info(
      '[FCM]   data: ${message.data}',
      tag: 'FCM',
    );

    // Add to stream for UI consumption
    _messageController.add(message);
  }

  /// Show local notification from a remote message.
  Future<void> _showLocalNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const androidDetails = AndroidNotificationDetails(
      'kikoflu_high_importance',
      'KikoFlu Notifications',
      channelDescription: 'Important notifications from KikoFlu',
      importance: Importance.high,
      priority: Priority.high,
      icon: '@drawable/ic_launcher_foreground',
      color: Color(0xFF146683),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _localNotifications.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: message.data.toString(),
    );
  }

  /// Called when FCM token is refreshed.
  /// Override this to send the new token to your backend.
  void _onTokenRefresh(String newToken) {
    // TODO: Send new token to your backend server
    // Example: await apiService.updateFcmToken(newToken);
  }

  /// Send current token to backend server.
  ///
  /// Call this after login or when you need to register/update the token.
  Future<void> sendTokenToServer({
    required Future<void> Function(String token) onTokenReceived,
  }) async {
    if (_fcmToken == null) {
      await _getToken();
    }

    if (_fcmToken != null) {
      try {
        await onTokenReceived(_fcmToken!);
        _log.info('[FCM] Token sent to server', tag: 'FCM');
      } catch (e) {
        _log.error('[FCM] Failed to send token to server: $e', tag: 'FCM');
      }
    }
  }

  /// Subscribe to a topic.
  Future<void> subscribeToTopic(String topic) async {
    try {
      await _messaging.subscribeToTopic(topic);
      _log.info('[FCM] Subscribed to topic: $topic', tag: 'FCM');
    } catch (e) {
      _log.error('[FCM] Failed to subscribe to topic: $e', tag: 'FCM');
    }
  }

  /// Unsubscribe from a topic.
  Future<void> unsubscribeFromTopic(String topic) async {
    try {
      await _messaging.unsubscribeFromTopic(topic);
      _log.info('[FCM] Unsubscribed from topic: $topic', tag: 'FCM');
    } catch (e) {
      _log.error('[FCM] Failed to unsubscribe from topic: $e', tag: 'FCM');
    }
  }

  /// Delete FCM token (e.g., on logout).
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
      _fcmToken = null;
      _log.info('[FCM] Token deleted', tag: 'FCM');
    } catch (e) {
      _log.error('[FCM] Failed to delete token: $e', tag: 'FCM');
    }
  }

  /// Log token (truncated for security).
  String _logToken(String token) {
    if (token.length > 20) {
      return '${token.substring(0, 10)}...${token.substring(token.length - 10)}';
    }
    return token;
  }

  /// Dispose resources.
  void dispose() {
    _messageController.close();
  }
}
