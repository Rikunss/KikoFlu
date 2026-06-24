import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';

/// Manages Android system notification for AI model download progress.
///
/// Shows a notification with a progress bar when the model is downloading,
/// updates it in realtime, and dismisses/updates on completion or failure.
/// This lets the user monitor the download even after minimising the app
/// or turning off the screen.
class AiDownloadNotificationService {
  static AiDownloadNotificationService? _instance;
  static AiDownloadNotificationService get instance =>
      _instance ??= AiDownloadNotificationService._();

  AiDownloadNotificationService._();

  static const _channelId = 'ai_model_download';
  static const _notificationId = 1002; // different from conversion (1001)

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Whether the plugin is ready.  The [ConversionNotificationService]
  /// already calls `_plugin.initialize()`, but we call it again here so
  /// this service works independently if conversion is not initialised.
  bool get isInitialized => _initialized;

  /// Must be called once at app startup, or lazily on first use.
  Future<void> initialize() async {
    if (_initialized) return;

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _plugin.initialize(
      const InitializationSettings(
        android: androidSettings,
        iOS: iosSettings,
      ),
    );

    // Request notification permission on Android 13+
    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      LogService.instance.warning('[AiDownloadNotification] Permission request failed: $e', tag: 'AiDownload');
    }

    _initialized = true;
  }

  /// Show or update a notification with download progress.
  ///
  /// [modelDisplayName] — human label like "Large V3 Turbo".
  /// [progress] — 0.0 to 1.0.
  /// [receivedBytes] / [totalBytes] — for the detail text.
  Future<void> showProgress({
    required String modelDisplayName,
    required double progress,
    int receivedBytes = 0,
    int totalBytes = 0,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;
    final percent = (progress * 100).round().clamp(0, 100);

    final detail = totalBytes > 0
        ? '${_formatBytes(receivedBytes)} / ${_formatBytes(totalBytes)}'
        : '$percent%';

    await _plugin.show(
      _notificationId,
      'Downloading $modelDisplayName…',
      '$percent% — $detail',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'AI Model Download',
          channelDescription: 'Shows AI model download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          indeterminate: progress <= 0.0,
          maxProgress: 100,
          progress: percent,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
        ),
      ),
    );
  }

  /// Show notification when download completes successfully.
  Future<void> showCompleted({required String modelDisplayName}) async {
    if (!Platform.isAndroid || !_initialized) return;
    await _plugin.show(
      _notificationId,
      'Download Complete ✓',
      '$modelDisplayName model is ready to use',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'AI Model Download',
          channelDescription: 'Shows AI model download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: false,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    // Auto-dismiss after 2 seconds
    await Future<void>.delayed(const Duration(seconds: 2));
    await dismiss();
  }

  /// Show notification when download fails.
  Future<void> showFailed({
    required String modelDisplayName,
    String? error,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;
    final errorSuffix = error != null ? ': $error' : '';
    await _plugin.show(
      _notificationId,
      'Download Failed',
      '$modelDisplayName$errorSuffix',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'AI Model Download',
          channelDescription: 'Shows AI model download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: false,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    // Keep the failure notification visible longer
    await Future<void>.delayed(const Duration(seconds: 4));
    await dismiss();
  }

  /// Show notification when download is paused.
  Future<void> showPaused({required String modelDisplayName}) async {
    if (!Platform.isAndroid || !_initialized) return;
    await _plugin.show(
      _notificationId,
      'Download Paused ⏸',
      '$modelDisplayName — tap Resume in app to continue',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'AI Model Download',
          channelDescription: 'Shows AI model download progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: false,
          ongoing: true,   // stays until user resumes or cancels
          autoCancel: false,
          onlyAlertOnce: true,
        ),
      ),
    );
  }

  /// Remove the download notification.
  Future<void> dismiss() async {
    await _plugin.cancel(_notificationId);
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}
