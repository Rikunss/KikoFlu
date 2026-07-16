import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';

/// Manages Android system notification for WAV→FLAC conversion progress.
///
/// Shows a notification with a progress bar when conversion starts,
/// updates it in realtime, and dismisses it on completion/failure.
class ConversionNotificationService {
  static ConversionNotificationService? _instance;
  static ConversionNotificationService get instance =>
      _instance ??= ConversionNotificationService._();

  ConversionNotificationService._();

  static const _channelId = 'audio_conversion';
  static const _notificationId = 1001;

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Must be called once at app startup.
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

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      LogService.instance.warning('[ConversionNotification] Permission request failed: $e', tag: 'Conversion');
    }

    _initialized = true;
  }

  /// Show or update a notification with conversion progress.
  Future<void> showProgress({
    required String fileName,
    required double progress,
    String? eta,
  }) async {
    if (!_initialized) return;
    final percent = (progress * 100).round().clamp(0, 100);
    final etaText = (eta != null && progress > 0.01 && progress < 1.0)
        ? ' — ETA: $eta'
        : '';

    await _plugin.show(
      _notificationId,
      'Converting Audio',
      '$fileName — $percent%$etaText',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Audio Conversion',
          channelDescription: 'Shows audio file conversion progress',
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

  /// Show notification when conversion completes successfully.
  Future<void> showCompleted({required String fileName, String formatName = 'FLAC'}) async {
    if (!_initialized) return;
    await _plugin.show(
      _notificationId,
      'Conversion Complete',
      '$fileName → $formatName ✓',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Audio Conversion',
          channelDescription: 'Shows audio file conversion progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: false,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 2));
    await dismiss();
  }

  /// Show notification when conversion fails.
  Future<void> showFailed({required String fileName, String formatName = ''}) async {
    if (!_initialized) return;
    final formatMsg = formatName.isNotEmpty ? ' ($formatName)' : '';
    await _plugin.show(
      _notificationId,
      'Conversion Failed$formatMsg',
      '$fileName — Keeping original WAV',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Audio Conversion',
          channelDescription: 'Shows audio file conversion progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: false,
          ongoing: false,
          autoCancel: true,
          onlyAlertOnce: true,
        ),
      ),
    );
    await Future<void>.delayed(const Duration(seconds: 3));
    await dismiss();
  }

  /// Dismiss the conversion notification.
  Future<void> dismiss() async {
    await _plugin.cancel(_notificationId);
  }
}