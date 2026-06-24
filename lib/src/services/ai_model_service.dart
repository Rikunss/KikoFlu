import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:wakelock_plus/wakelock_plus.dart';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';
import 'package:whisper_ggml_plus_ffmpeg/whisper_ggml_plus_ffmpeg.dart';

import 'log_service.dart';
import 'subtitle_library_service.dart';

final _log = LogService.instance;

/// Riverpod provider for AIModelService singleton.
final aiModelServiceProvider = Provider<AIModelService>((ref) {
  return AIModelService.instance;
});

/// Represents a single transcribed segment with timestamp.
class WhisperSegment {
  final double startSeconds;
  final double endSeconds;
  final String text;

  const WhisperSegment({
    required this.startSeconds,
    required this.endSeconds,
    required this.text,
  });
}

/// Result of a transcription.
class TranscriptionResult {
  final String fullText;
  final List<WhisperSegment> segments;
  final String lrcContent;

  const TranscriptionResult({
    required this.fullText,
    required this.segments,
    required this.lrcContent,
  });
}

/// Model configuration for display in UI.
class AiModelConfig {
  final WhisperModel model;
  final String displayName;
  final int approximateSizeBytes;
  final String minRam;
  final String speed;
  final String accuracy;

  const AiModelConfig({
    required this.model,
    required this.displayName,
    required this.approximateSizeBytes,
    required this.minRam,
    required this.speed,
    required this.accuracy,
  });

  String get sizeLabel {
    if (approximateSizeBytes < 1024 * 1024) {
      return '${(approximateSizeBytes / 1024).toStringAsFixed(0)} KB';
    }
    return '${(approximateSizeBytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }
}

/// All available model configurations.
const List<AiModelConfig> aiModelConfigs = [
  AiModelConfig(
    model: WhisperModel.tiny,
    displayName: 'Tiny',
    approximateSizeBytes: 75 * 1024 * 1024,
    minRam: '1 GB',
    speed: '⚡⚡⚡⚡⚡',
    accuracy: '★★☆☆☆',
  ),
  AiModelConfig(
    model: WhisperModel.base,
    displayName: 'Base',
    approximateSizeBytes: 150 * 1024 * 1024,
    minRam: '2 GB',
    speed: '⚡⚡⚡⚡',
    accuracy: '★★★☆☆',
  ),
  AiModelConfig(
    model: WhisperModel.small,
    displayName: 'Small',
    approximateSizeBytes: 500 * 1024 * 1024,
    minRam: '4 GB',
    speed: '⚡⚡⚡',
    accuracy: '★★★★☆',
  ),
  AiModelConfig(
    model: WhisperModel.medium,
    displayName: 'Medium',
    approximateSizeBytes: 1536 * 1024 * 1024,
    minRam: '6 GB',
    speed: '⚡⚡',
    accuracy: '★★★★☆',
  ),
  AiModelConfig(
    model: WhisperModel.large,
    displayName: 'Large V3',
    approximateSizeBytes: 3072 * 1024 * 1024,
    minRam: '8 GB',
    speed: '⚡',
    accuracy: '★★★★★',
  ),
  AiModelConfig(
    model: WhisperModel.largeV3Turbo,
    displayName: 'Large V3 Turbo',
    approximateSizeBytes: 1600 * 1024 * 1024,
    minRam: '6 GB',
    speed: '⚡⚡⚡',
    accuracy: '★★★★☆',
  ),
];

/// Get config for a model name string (e.g. "base", "small").
AiModelConfig? getConfigByModelName(String name) {
  try {
    final model = WhisperModel.values.firstWhere(
      (m) => m.name == name,
    );
    return aiModelConfigs.firstWhere((c) => c.model == model);
  } catch (_) {
    return null;
  }
}

/// Service for AI-powered speech-to-text transcription using whisper.cpp.
///
/// Handles:
/// - Downloading Whisper models (managed by whisper_ggml_plus)
/// - Transcribing a single audio file
/// - Generating LRC subtitle content
/// - Saving LRC files to the subtitle library
class AIModelService {
  static final AIModelService instance = AIModelService._();
  AIModelService._() {
    WhisperFFmpegConverter.register();
  }

  WhisperController? _controller;

  WhisperController get _ctrl => _controller ??= WhisperController();

  /// Check if a specific model is installed by probing for its file.
  Future<bool> checkModelInstalled({WhisperModel model = WhisperModel.base}) async {
    try {
      final path = await _ctrl.getPath(model);
      return await File(path).exists();
    } catch (_) {
      return false;
    }
  }

  /// Get the approximate model file size in bytes for the given model.
  Future<int?> getModelSize({WhisperModel model = WhisperModel.base}) async {
    try {
      final path = await _ctrl.getPath(model);
      final file = File(path);
      if (await file.exists()) {
        return await file.length();
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Download the specified Whisper model from HuggingFace with real progress.
  ///
  /// Supports:
  /// - **Resume** via HTTP Range headers (keeps `.downloading` file on failure).
  /// - **Pause** – the download loop polls [isPaused]; when `true` it stops
  ///   the stream and calls [onPaused] without deleting the partial file.
  /// - **Cancel** – the download loop polls [isCancelled]; when `true` it
  ///   deletes the partial file and calls [onCancelled].
  /// - **Wakelock** – keeps the device awake via `wakelock_plus`.
  Future<String> downloadModel({
    WhisperModel model = WhisperModel.base,
    void Function(int received, int total)? onProgress,
    bool Function()? isPaused,
    VoidCallback? onPaused,
    bool Function()? isCancelled,
    VoidCallback? onCancelled,
  }) async {
    final modelName = model.modelName;
    _log.info('Starting Whisper $modelName model download from HuggingFace',
        tag: 'AI');

    final savePath = await _ctrl.getPath(model);
    final tempPath = '$savePath.downloading';
    final file = File(savePath);
    final tempFile = File(tempPath);

    // If already exists, skip
    if (await file.exists()) {
      _log.info('Model already exists at: $savePath', tag: 'AI');
      onProgress?.call(100, 100);
      return modelName;
    }

    final modelUri = model.modelUri;
    _log.info('Download URL: ${modelUri.toString()}', tag: 'AI');

    // Ensure the parent directory exists
    await Directory(p.dirname(savePath)).create(recursive: true);

    // Acquire wakelock to prevent screen/during download
    bool wakelockAcquired = false;
    try {
      await WakelockPlus.enable();
      wakelockAcquired = true;
      _log.info('Wakelock acquired for download', tag: 'AI');
    } catch (e) {
      _log.warning('Failed to acquire wakelock: $e', tag: 'AI');
    }

    try {
      // ── Check for existing partial download (resume support) ──────
      int existingBytes = 0;
      if (await tempFile.exists()) {
        existingBytes = await tempFile.length();
        _log.info('Found existing partial download: $existingBytes bytes',
            tag: 'AI');
      }

      final client = HttpClient();
      client.userAgent = 'KikoFlu-Edge/1.0';
      client.connectionTimeout = const Duration(seconds: 30);

      final request = await client.getUrl(modelUri);

      // Send Range header if we have partial data
      if (existingBytes > 0) {
        request.headers.set('Range', 'bytes=$existingBytes-');
        _log.info('Resuming download from byte $existingBytes', tag: 'AI');
      }

      final response = await request.close();

      // Handle range / normal response
      int totalBytes;
      if (existingBytes > 0 && response.statusCode == 206) {
        // Server supports resume
        final reportedLen = response.contentLength;
        totalBytes = reportedLen > 0
            ? existingBytes + reportedLen
            : existingBytes;
        _log.info(
            'Server supports resume (206). Total: $totalBytes', tag: 'AI');
      } else if (existingBytes > 0 && response.statusCode == 200) {
        // Server doesn't support Range — start from scratch
        _log.info('Server does not support resume, starting from scratch',
            tag: 'AI');
        existingBytes = 0;
        totalBytes =
            response.contentLength > 0 ? response.contentLength : 0;
        // Delete the stale partial file
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      } else if (response.statusCode != 200) {
        throw HttpException(
          'Download failed with status: ${response.statusCode}',
          uri: modelUri,
        );
      } else {
        totalBytes =
            response.contentLength > 0 ? response.contentLength : 0;
      }

      var receivedBytes = existingBytes;

      // Open file in append mode when resuming, write mode when fresh
      final sink = tempFile.openWrite(
        mode: existingBytes > 0 ? FileMode.append : FileMode.write,
      );

      await for (final chunk in response) {
        // Check for cancel request (higher priority than pause)
        if (isCancelled != null && isCancelled()) {
          _log.info('Download cancelled at byte $receivedBytes', tag: 'AI');
          await sink.flush();
          await sink.close();
          // Delete the partial file
          if (await tempFile.exists()) {
            await tempFile.delete();
            _log.info('Partial file deleted: $tempPath', tag: 'AI');
          }
          onCancelled?.call();
          client.close(force: true);
          return modelName;
        }

        // Check for pause request
        if (isPaused != null && isPaused()) {
          _log.info('Download paused at byte $receivedBytes', tag: 'AI');
          await sink.flush();
          await sink.close();
          onPaused?.call();
          client.close(force: true);
          // Return WITHOUT throwing — paused is intentional, not an error.
          // Partial file is kept for later resume.
          return modelName;
        }

        sink.add(chunk);
        receivedBytes += chunk.length;
        onProgress?.call(receivedBytes, totalBytes);
      }

      await sink.flush();
      await sink.close();

      // Atomically rename temp file to final name
      if (await tempFile.exists()) {
        if (await file.exists()) {
          await file.delete();
        }
        await tempFile.rename(savePath);
      }

      client.close(force: true);

      _log.info(
        'Whisper $modelName model downloaded: $savePath '
        '(${receivedBytes ~/ 1048576} MB)',
        tag: 'AI',
      );
      return modelName;
    } on HttpException catch (e) {
      // Handle 416 Range Not Satisfiable — file is likely complete
      if (e.message.contains('status: 416')) {
        if (await tempFile.exists()) {
          if (await file.exists()) {
            await file.delete();
          }
          await tempFile.rename(savePath);
          _log.info(
              '416 Range Not Satisfiable — file already complete', tag: 'AI');
          return modelName;
        }
      }
      // Partial file kept on disk for resume — do NOT delete
      _log.error('Model download failed (HttpException): $e', tag: 'AI');
      rethrow;
    } catch (e) {
      // Partial file kept on disk for resume — do NOT delete
      _log.error('Model download failed: $e', tag: 'AI');
      rethrow;
    } finally {
      // Release wakelock
      if (wakelockAcquired) {
        try {
          await WakelockPlus.disable();
          _log.info('Wakelock released', tag: 'AI');
        } catch (e) {
          _log.warning('Failed to release wakelock: $e', tag: 'AI');
        }
      }
    }
  }

  /// Delete any partial download temp file for the given model.
  /// Safe to call even if no partial file exists.
  Future<void> cleanupPartialDownload({required WhisperModel model}) async {
    final savePath = await _ctrl.getPath(model);
    final tempPath = '$savePath.downloading';
    final tempFile = File(tempPath);
    if (await tempFile.exists()) {
      await tempFile.delete();
      _log.info('Partial file cleaned up: $tempPath', tag: 'AI');
    }
  }

  /// Import a model file that was downloaded externally (e.g. via browser)
  /// by copying it to the path expected by whisper_ggml_plus.
  ///
  /// Returns the destination path on success.
  Future<String> importModelFromFile({
    required String sourceFilePath,
    required WhisperModel model,
  }) async {
    final savePath = await _ctrl.getPath(model);
    final sourceFile = File(sourceFilePath);

    if (!await sourceFile.exists()) {
      throw Exception('Source file not found: $sourceFilePath');
    }

    // Ensure the parent directory exists
    await Directory(p.dirname(savePath)).create(recursive: true);

    // If a model already exists at the destination, remove it first
    final destFile = File(savePath);
    if (await destFile.exists()) {
      await destFile.delete();
    }

    // Copy the file (copy instead of rename in case source is on a
    // different volume, e.g. external SD card)
    await sourceFile.copy(savePath);

    _log.info(
      'Model imported: $sourceFilePath -> $savePath '
      '(${(await destFile.length()) ~/ 1048576} MB)',
      tag: 'AI',
    );

    return savePath;
  }

  /// Delete the downloaded model files for the given model.
  Future<void> deleteModel({WhisperModel model = WhisperModel.base}) async {
    try {
      // Get model path and delete the actual model file
      final path = await _ctrl.getPath(model);
      final file = File(path);
      if (await file.exists()) {
        await file.delete();
        _log.info('Model file deleted: $path', tag: 'AI');
      }

      // Also try the model directory (only if it's empty now)
      final dir = Directory(await WhisperController.getModelDir());
      if (await dir.exists()) {
        final contents = await dir.list().toList();
        if (contents.isEmpty) {
          await dir.delete();
        }
      }
    } catch (e) {
      _log.error('Failed to delete model: $e', tag: 'AI');
    }
  }

  /// Transcribe a single audio file using the specified model.
  Future<TranscriptionResult?> transcribeAudio(
    String audioPath, {
    WhisperModel model = WhisperModel.base,
    int threads = 4,
    bool splitOnWord = false,
  }) async {
    final audioFile = File(audioPath);
    if (!await audioFile.exists()) {
      _log.error('Audio file not found: $audioPath', tag: 'AI');
      return null;
    }

    try {
      final modelName = model.modelName;
      _log.info('Starting transcription with model $modelName: $audioPath (threads=$threads, splitOnWord=$splitOnWord)', tag: 'AI');

      final result = await _ctrl.transcribe(
        model: model,
        audioPath: audioPath,
        lang: 'ja',
        withTimestamps: true,
        splitOnWord: splitOnWord,
        threads: threads,
      );

      if (result == null) {
        _log.warning('Transcription returned null', tag: 'AI');
        return null;
      }

      final whisperText = result.transcription.text;
      if (whisperText.isEmpty) {
        _log.warning('Transcription returned empty text', tag: 'AI');
        return null;
      }

      // Convert segments
      final segments = <WhisperSegment>[];
      if (result.transcription.segments != null) {
        for (final seg in result.transcription.segments!) {
          segments.add(WhisperSegment(
            startSeconds: seg.fromTs.inMilliseconds / 1000.0,
            endSeconds: seg.toTs.inMilliseconds / 1000.0,
            text: seg.text,
          ));
        }
      }

      // Generate LRC
      final lrcContent = _segmentsToLrc(segments);

      _log.info(
        'Transcription complete: ${segments.length} segments, '
        '${whisperText.length} chars',
        tag: 'AI',
      );

      return TranscriptionResult(
        fullText: whisperText,
        segments: segments,
        lrcContent: lrcContent,
      );
    } catch (e) {
      _log.error('Transcription failed: $e', tag: 'AI');
      return null;
    }
  }

  /// Convert segments to LRC format.
  String _segmentsToLrc(List<WhisperSegment> segments) {
    final buffer = StringBuffer();
    buffer.writeln('[ti:AI-Generated Transcription]');
    buffer.writeln('[by:KikoFlu AI]');
    buffer.writeln('');

    for (final seg in segments) {
      if (seg.text.trim().isEmpty) continue;

      final totalMs = (seg.startSeconds * 1000).round();
      final minutes = (totalMs ~/ 60000);
      final seconds = ((totalMs % 60000) ~/ 1000);
      final hundredths = ((totalMs % 1000) ~/ 10);

      final timeStr = '${_pad(minutes)}:${_pad(seconds)}.${_pad(hundredths)}';
      buffer.writeln('[$timeStr]${seg.text.trim()}');
    }

    return buffer.toString();
  }

  String _pad(int value) => value.toString().padLeft(2, '0');

  /// Save LRC to subtitle library.
  Future<String?> saveLrcToSubtitleLibrary({
    required String lrcContent,
    required String audioFileName,
    required int? workId,
  }) async {
    try {
      final baseName = p.basenameWithoutExtension(audioFileName);
      final lrcFileName = '$baseName.lrc';

      final libraryDir = await SubtitleLibraryService.getSubtitleLibraryDirectory();

      String relativeDir;
      if (workId != null && workId > 0) {
        relativeDir = '${SubtitleLibraryService.parsedFolderName}/RJ$workId';
      } else {
        relativeDir = SubtitleLibraryService.unknownFolderName;
      }

      final outputDir = Directory(p.join(libraryDir.path, relativeDir));
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final outputPath = p.join(outputDir.path, lrcFileName);
      await File(outputPath).writeAsString(lrcContent, encoding: utf8);

      _log.info('LRC saved to: $outputPath', tag: 'AI');
      return outputPath;
    } catch (e) {
      _log.error('Failed to save LRC: $e', tag: 'AI');
      return null;
    }
  }

  /// Transcribe an audio file and save LRC alongside the audio file.
  ///
  /// Saves the LRC in two places:
  /// 1. **Primary** — same directory as the audio file (so it's in the
  ///    works folder and media players can auto-detect it).
  /// 2. **Backup** — subtitle library (for organization in KikoFlu).
  ///
  /// Returns the path to the primary (audio-side) LRC file.
  Future<String?> transcribeAndSave({
    required String audioPath,
    required String audioFileName,
    int? workId,
    WhisperModel model = WhisperModel.base,
    int threads = 4,
    bool splitOnWord = false,
  }) async {
    final result = await transcribeAudio(audioPath, model: model, threads: threads, splitOnWord: splitOnWord);
    if (result == null) return null;

    final baseName = p.basenameWithoutExtension(audioFileName);
    final lrcFileName = '$baseName.lrc';

    // 1. Save alongside the audio file (primary)
    final audioDir = p.dirname(audioPath);
    final lrcPath = p.join(audioDir, lrcFileName);
    await File(lrcPath).writeAsString(result.lrcContent, encoding: utf8);
    _log.info('LRC saved alongside audio: $lrcPath', tag: 'AI');

    // 2. Also save to subtitle library (backup / organization)
    await saveLrcToSubtitleLibrary(
      lrcContent: result.lrcContent,
      audioFileName: audioFileName,
      workId: workId,
    );

    return lrcPath;
  }

  /// Generate LRC for a local audio file.
  Future<String?> generateLrc(
    String audioPath,
    String audioFileName, {
    WhisperModel model = WhisperModel.base,
    int threads = 4,
    bool splitOnWord = false,
  }) async {
    return await transcribeAndSave(
      audioPath: audioPath,
      audioFileName: audioFileName,
      model: model,
      threads: threads,
      splitOnWord: splitOnWord,
    );
  }
}
