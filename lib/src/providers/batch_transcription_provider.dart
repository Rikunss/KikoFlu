import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:wakelock_plus/wakelock_plus.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../models/work.dart';
import '../services/ai_model_service.dart';
import '../services/batch_transcription_notification_service.dart';
import '../services/log_service.dart';

final _log = LogService.instance;

/// Status of a single file in a batch transcription job.
enum BatchFileStatus { queued, transcribing, done, failed }

/// Represents one audio file to transcribe in a batch.
class BatchFile {
  final String audioPath;
  final String displayName;
  final BatchFileStatus status;
  final String? errorMessage;

  const BatchFile({
    required this.audioPath,
    required this.displayName,
    this.status = BatchFileStatus.queued,
    this.errorMessage,
  });

  BatchFile copyWith({
    BatchFileStatus? status,
    String? errorMessage,
  }) {
    return BatchFile(
      audioPath: audioPath,
      displayName: displayName,
      status: status ?? this.status,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Status of the overall batch transcription job.
enum BatchJobStatus { idle, running, completed, cancelled }

/// The current state of batch transcription.
class BatchTranscriptionState {
  /// Overall job status.
  final BatchJobStatus status;

  /// The work ID being transcribed (if any).
  final int? workId;

  /// All files in the batch, with their individual status.
  final List<BatchFile> files;

  /// Index of the file currently being processed (or -1 if not running).
  final int currentIndex;

  /// Number of successfully transcribed files.
  final int doneCount;

  /// Number of failed files.
  final int failedCount;

  const BatchTranscriptionState({
    this.status = BatchJobStatus.idle,
    this.workId,
    this.files = const [],
    this.currentIndex = -1,
    this.doneCount = 0,
    this.failedCount = 0,
  });

  int get totalFiles => files.length;

  int get queuedCount => totalFiles - doneCount - failedCount;

  double get progressPercent =>
      totalFiles > 0 ? (doneCount + failedCount) / totalFiles : 0.0;

  BatchTranscriptionState copyWith({
    BatchJobStatus? status,
    int? workId,
    List<BatchFile>? files,
    int? currentIndex,
    int? doneCount,
    int? failedCount,
  }) {
    return BatchTranscriptionState(
      status: status ?? this.status,
      workId: workId ?? this.workId,
      files: files ?? this.files,
      currentIndex: currentIndex ?? this.currentIndex,
      doneCount: doneCount ?? this.doneCount,
      failedCount: failedCount ?? this.failedCount,
    );
  }
}

/// Riverpod provider for batch transcription state.
final batchTranscriptionProvider =
    StateNotifierProvider<BatchTranscriptionNotifier, BatchTranscriptionState>(
        (ref) {
  return BatchTranscriptionNotifier(ref);
});

class BatchTranscriptionNotifier
    extends StateNotifier<BatchTranscriptionState> {
  final Ref _ref;
  Completer<void>? _batchCompleter;
  bool _cancelled = false;

  BatchTranscriptionNotifier(this._ref) : super(const BatchTranscriptionState());

  /// Start batch transcription for a list of audio files.
  ///
  /// [files] — list of (audioPath, displayName) pairs.
  /// [workId] — the work's RJ number for subtitle library saving.
  /// [model] — the Whisper model to use.
  /// [threads] — number of CPU threads.
  /// [splitOnWord] — whether to generate per-word timestamps.
  Future<void> startBatch({
    required List<({String path, String title})> files,
    required int? workId,
    required WhisperModel model,
    required int threads,
    required bool splitOnWord,
  }) async {
    if (files.isEmpty) return;
    if (state.status == BatchJobStatus.running) {
      _log.warning('[BatchTranscription] Already running, ignoring start',
          tag: 'AI');
      return;
    }

    _cancelled = false;

    final batchFiles = files
        .map((f) => BatchFile(audioPath: f.path, displayName: f.title))
        .toList();

    state = BatchTranscriptionState(
      status: BatchJobStatus.running,
      workId: workId,
      files: batchFiles,
      currentIndex: 0,
    );

    _batchCompleter = Completer<void>();

    try {
      await WakelockPlus.enable();
    } catch (e) {
      _log.warning('[BatchTranscription] Failed to acquire wakelock: $e',
          tag: 'AI');
    }

    try {
      await BatchTranscriptionNotificationService.instance.initialize();
    } catch (e) {
      _log.warning(
          '[BatchTranscription] Failed to init notification: $e', tag: 'AI');
    }

    for (int i = 0; i < state.files.length; i++) {
      if (_cancelled) break;

      final batchFile = state.files[i];

      final updatedFiles = List<BatchFile>.from(state.files);
      updatedFiles[i] = batchFile.copyWith(status: BatchFileStatus.transcribing);
      state = state.copyWith(
        files: updatedFiles,
        currentIndex: i,
      );

      try {
        await BatchTranscriptionNotificationService.instance.showProgress(
          currentIndex: i,
          totalFiles: state.totalFiles,
          currentFile: batchFile.displayName,
        );
      } catch (e) {
        LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
      }

      final aiService = _ref.read(aiModelServiceProvider);

      try {
        final result = await aiService.transcribeAndSave(
          audioPath: batchFile.audioPath,
          audioFileName: batchFile.displayName,
          workId: workId,
          model: model,
          threads: threads,
          splitOnWord: splitOnWord,
        );

        if (_cancelled) break;

        if (result != null) {
          updatedFiles[i] =
              batchFile.copyWith(status: BatchFileStatus.done);
          state = state.copyWith(
            files: updatedFiles,
            doneCount: state.doneCount + 1,
          );
          _log.info(
            '[BatchTranscription] Done: ${batchFile.displayName}',
            tag: 'AI',
          );
        } else {
          updatedFiles[i] = batchFile.copyWith(
            status: BatchFileStatus.failed,
            errorMessage: 'Transcription returned null',
          );
          state = state.copyWith(
            files: updatedFiles,
            failedCount: state.failedCount + 1,
          );
          _log.warning(
            '[BatchTranscription] Failed (null result): ${batchFile.displayName}',
            tag: 'AI',
          );

          try {
            await BatchTranscriptionNotificationService.instance.showFileFailed(
              fileName: batchFile.displayName,
              error: 'Transcription returned null',
            );
          } catch (e) {
            LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
          }
        }
      } catch (e) {
        if (_cancelled) break;

        updatedFiles[i] = batchFile.copyWith(
          status: BatchFileStatus.failed,
          errorMessage: e.toString(),
        );
        state = state.copyWith(
          files: updatedFiles,
          failedCount: state.failedCount + 1,
        );
        _log.error(
          '[BatchTranscription] Error: ${batchFile.displayName}: $e',
          tag: 'AI',
        );

        try {
            await BatchTranscriptionNotificationService.instance.showFileFailed(
              fileName: batchFile.displayName,
              error: e.toString(),
            );
          } catch (e) {
            LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
          }
      }
    }

    try {
      await WakelockPlus.disable();
    } catch (e) {
      LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
    }

    if (_cancelled) {
      state = state.copyWith(
        status: BatchJobStatus.cancelled,
        currentIndex: -1,
      );
      try {
        await BatchTranscriptionNotificationService.instance.showCancelled();
      } catch (e) {
        LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
      }
    } else {
      state = state.copyWith(
        status: BatchJobStatus.completed,
        currentIndex: -1,
      );
      try {
        await BatchTranscriptionNotificationService.instance.showCompleted(
          totalFiles: state.totalFiles,
          failedFiles: state.failedCount,
        );
      } catch (e) {
        LogService.instance.warning('[BatchTranscriptionNotifier] error: $e', tag: 'BatchTranscription');
      }
    }

    if (!_batchCompleter!.isCompleted) {
      _batchCompleter!.complete();
    }
  }

  /// Cancel the currently running batch.
  Future<void> cancel() async {
    if (state.status != BatchJobStatus.running) return;
    _cancelled = true;
    _log.info('[BatchTranscription] Cancellation requested', tag: 'AI');
  }

  /// Clear the completed/cancelled state and return to idle.
  void clear() {
    if (state.status == BatchJobStatus.running) return;
    state = const BatchTranscriptionState();
  }
}

/// Helper to collect audio files from a Work for batch transcription.
///
/// For local imported works, resolves absolute paths using [localImportPath].
/// For downloaded works, resolves paths using the download directory.
class BatchTranscriptionHelper {
  /// Collect all audio files from a work's children tree.
  ///
  /// Returns a list of (path, title) pairs suitable for [startBatch].
  static Future<List<({String path, String title})>> collectAudioFiles({
    required Work work,
    required String? localImportPath,
  }) async {
    final files = <({String path, String title})>[];

    if (work.children == null || work.children!.isEmpty) return files;

    final basePath = localImportPath;

    void walkFiles(List<AudioFile> children, String parentPath) {
      for (final child in children) {
        if (child.isFolder && child.children != null) {
          final folderPath = parentPath.isEmpty
              ? child.title
              : '$parentPath/${child.title}';
          walkFiles(child.children!, folderPath);
        } else if (child.isAudio) {
          final relativePath = parentPath.isEmpty
              ? child.title
              : '$parentPath/${child.title}';
          final fullPath = basePath != null
              ? '$basePath/$relativePath'
              : relativePath;
          files.add((path: fullPath, title: child.title));
        }
      }
    }

    walkFiles(work.children!, '');
    return files;
  }

  /// Check if any of the audio files exist on disk.
  static Future<bool> anyFilesExist({
    required List<({String path, String title})> files,
  }) async {
    for (final file in files) {
      try {
        if (await File(file.path).exists()) return true;
      } catch (e) {
        LogService.instance.warning('[BatchTranscriptionHelper] error: $e', tag: 'BatchTranscription');
      }
    }
    return false;
  }
}