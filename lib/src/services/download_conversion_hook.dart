import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import 'audio_conversion_service.dart';
import 'conversion_notification_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Result of a WAV conversion attempt.
class ConversionResult {
  /// Path to the converted file, or null if conversion was skipped/failed.
  final String? convertedPath;

  /// The original file name (for updating DownloadTask metadata).
  final String originalFileName;

  const ConversionResult({this.convertedPath, required this.originalFileName});

  /// Whether conversion produced a new file.
  bool get wasConverted => convertedPath != null;
}

/// Handles WAV → FLAC/ALAC/Opus/MP3/AAC conversion after a download completes.
///
/// Reads the conversion format preference from SharedPreferences and
/// delegates to [AudioConversionService] for the actual conversion.
/// Reports progress to [ConversionNotificationService] and [onUpdate].
class DownloadConversionHook {
  final StreamController<String> _conversionController =
      StreamController<String>.broadcast();

  /// Stream of conversion events: "start:filename", "success:format:filename",
  /// "fail:format:filename", or "fail:filename".
  Stream<String> get conversionStream => _conversionController.stream;

  /// Perform WAV → target format conversion if the user has enabled it.
  ///
  /// [filePath] must point to a .wav file.
  /// [task] is the original download task (used to find current task state).
  /// [findTask] is a callback to look up the current task by id.
  /// [onUpdate] is called when the task status changes during conversion.
  ///
  /// Returns a [ConversionResult] with the converted path (or null if skipped).
  Future<ConversionResult> convertIfWav({
    required String filePath,
    required DownloadTask task,
    required DownloadTask Function(String taskId) findTask,
    required void Function(DownloadTask) onUpdate,
  }) async {
    final isWav = filePath.toLowerCase().endsWith('.wav');
    if (!isWav) {
      return ConversionResult(originalFileName: task.fileName);
    }

    try {
      final prefs = await SharedPreferences.getInstance();
      final formatStr = prefs.getString('wav_conversion_format') ?? 'none';
      final format = WavConversionFormat.values.firstWhere(
        (f) => f.value == formatStr,
        orElse: () => WavConversionFormat.none,
      );

      if (format == WavConversionFormat.none) {
        return ConversionResult(originalFileName: task.fileName);
      }

      // Update task status to show "Converting..." in the UI
      final currentTask = findTask(task.id);
      onUpdate(currentTask.copyWith(status: DownloadStatus.converting));

      _log.info('开始转换: $filePath → ${format.displayName}', tag: 'Download');
      _conversionController.add('start:${task.fileName}');
      unawaited(ConversionNotificationService.instance.showProgress(
        fileName: task.fileName, progress: 0.0,
      ));

      var lastProgressMs = 0;
      const progressThrottleMs = 200;
      String? currentEta;

      final convertedPath = await AudioConversionService.instance.convert(
        filePath, format,
        onProgress: (progress, {eta}) {
          final now = DateTime.now().millisecondsSinceEpoch;
          if (eta != null) currentEta = eta;
          if (now - lastProgressMs > progressThrottleMs || progress >= 1.0) {
            lastProgressMs = now;
            final t = findTask(task.id);
            onUpdate(t.copyWith(
              status: DownloadStatus.converting,
              downloadedBytes: (progress * 100).round(),
              totalBytes: 100,
              eta: currentEta,
            ));
            unawaited(ConversionNotificationService.instance.showProgress(
              fileName: task.fileName, progress: progress, eta: currentEta,
            ));
          }
        },
      );

      if (convertedPath != null) {
        _log.info('转换成功: $convertedPath', tag: 'Download');
        _conversionController.add('success:${format.displayName}:${task.fileName}');
        unawaited(ConversionNotificationService.instance.showCompleted(
          fileName: task.fileName,
          formatName: format.displayName,
        ));
      } else {
        _log.warning('转换失败，保留原始WAV: $filePath', tag: 'Download');
        _conversionController.add('fail:${format.displayName}:${task.fileName}');
        unawaited(ConversionNotificationService.instance.showFailed(
          fileName: task.fileName,
          formatName: format.displayName,
        ));
      }

      return ConversionResult(
        convertedPath: convertedPath,
        originalFileName: task.fileName,
      );
    } catch (e) {
      _log.error('转换异常: $e', tag: 'Download');
      _conversionController.add('fail:${task.fileName}');
      unawaited(ConversionNotificationService.instance.showFailed(
        fileName: task.fileName,
      ));
      // Reset task status so it doesn't stay stuck in "converting"
      try {
        final stuckTask = findTask(task.id);
        onUpdate(stuckTask.copyWith(status: DownloadStatus.completed));
      } catch (e) {
        LogService.instance.warning('[DownloadConversionHook] Failed to reset task status: $e', tag: 'Download');
      }
      return ConversionResult(originalFileName: task.fileName);
    }
  }

  /// Clean up resources.
  void dispose() {
    _conversionController.close();
  }
}
