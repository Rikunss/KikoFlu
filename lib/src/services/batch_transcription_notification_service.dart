import 'dart:io' show Platform;
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'log_service.dart';

/// Manages Android system notification for batch AI transcription progress.
///
/// Shows a notification with a progress bar when a batch is running,
/// updates it per-file, and dismisses/updates on completion or failure.
/// This lets the user monitor batch transcription even after minimising
/// the app or turning off the screen.
class BatchTranscriptionNotificationService {
  static BatchTranscriptionNotificationService? _instance;
  static BatchTranscriptionNotificationService get instance =>
      _instance ??= BatchTranscriptionNotificationService._();

  BatchTranscriptionNotificationService._();

  static const _channelId = 'batch_transcription';
  static const _notificationId = 1003;

  final _plugin = FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  /// Whether the plugin is ready.
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

    try {
      final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    } catch (e) {
      LogService.instance.warning('[BatchTranscriptionNotification] Permission request failed: $e', tag: 'BatchTranscription');
    }

    _initialized = true;
  }

  /// Show or update a notification with batch transcription progress.
  ///
  /// [currentIndex] — 0-based index of the file currently being processed.
  /// [totalFiles] — total number of files to transcribe.
  /// [currentFile] — display name of the current file.
  Future<void> showProgress({
    required int currentIndex,
    required int totalFiles,
    required String currentFile,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;

    await _plugin.show(
      _notificationId,
      'AI Transcribing Batch',
      'File ${currentIndex + 1}/$totalFiles — $currentFile',
      NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Batch Transcription',
          channelDescription: 'Shows batch AI transcription progress',
          importance: Importance.low,
          priority: Priority.low,
          showProgress: true,
          indeterminate: false,
          maxProgress: totalFiles,
          progress: currentIndex + 1,
          ongoing: true,
          autoCancel: false,
          onlyAlertOnce: true,
          playSound: false,
        ),
      ),
    );
  }

  /// Show notification when batch completes successfully.
  Future<void> showCompleted({
    required int totalFiles,
    required int failedFiles,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;

    final title = failedFiles > 0
        ? 'Batch Complete — $failedFiles failed'
        : 'Batch Complete ✓';
    final body = failedFiles > 0
        ? '${totalFiles - failedFiles}/$totalFiles files transcribed successfully'
        : 'All $totalFiles files transcribed successfully';

    await _plugin.show(
      _notificationId,
      title,
      body,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Batch Transcription',
          channelDescription: 'Shows batch AI transcription progress',
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

  /// Show notification when batch is cancelled.
  Future<void> showCancelled() async {
    if (!Platform.isAndroid || !_initialized) return;
    await _plugin.show(
      _notificationId,
      'Batch Cancelled',
      'Transcription was cancelled by the user',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          'Batch Transcription',
          channelDescription: 'Shows batch AI transcription progress',
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

  /// Show notification when a file fails during batch.
  Future<void> showFileFailed({
    required String fileName,
    required String error,
  }) async {
    if (!Platform.isAndroid || !_initialized) return;

    await _plugin.show(
      _notificationId + 1,
      'Transcription Failed',
      '$fileName: $error',
      const NotificationDetails(
        android: AndroidNotificationDetails(
          '$_channelId.errors',
          'Batch Transcription Errors',
          channelDescription: 'Shows individual file transcription errors',
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
    await _plugin.cancel(_notificationId + 1);
  }

  /// Remove the batch transcription notification.
  Future<void> dismiss() async {
    await _plugin.cancel(_notificationId);
  }
}