import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

/// Status of an AI model download.
///
/// [idle] — no download in progress.
/// [downloading] — actively downloading bytes from the network.
/// [paused] — user paused the download; partial file kept on disk.
/// [completed] — finished successfully; state auto-clears.
/// [failed] — terminated with an error; user can retry.
enum AiDownloadStatus { idle, downloading, paused, completed, failed }

/// Global, persistent state for an AI model download.
///
/// This provider survives screen navigation so the user can leave the
/// AI Features screen and come back without losing progress.  State is
/// also persisted to SharedPreferences so a paused/failed download
/// survives an app restart.
class AiDownloadState {
  final AiDownloadStatus status;
  final String? modelName;          // whisper_ggml_plus name, e.g. "large-v3-turbo"
  final String? modelDisplayName;   // human label, e.g. "Large V3 Turbo"
  final int receivedBytes;
  final int totalBytes;
  final String? errorMessage;

  const AiDownloadState({
    this.status = AiDownloadStatus.idle,
    this.modelName,
    this.modelDisplayName,
    this.receivedBytes = 0,
    this.totalBytes = 0,
    this.errorMessage,
  });

  /// Download progress as a 0.0–1.0 fraction.
  double get progress =>
      totalBytes > 0 ? receivedBytes / totalBytes : 0.0;

  /// Human-readable progress string like "45% — 720 MB / 1.6 GB".
  String get progressLabel {
    if (totalBytes <= 0) {
      return '${(progress * 100).round()}%';
    }
    final recv = _formatBytes(receivedBytes);
    final total = _formatBytes(totalBytes);
    return '${(progress * 100).round()}% — $recv / $total';
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(0)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(0)} MB';
  }

  AiDownloadState copyWith({
    AiDownloadStatus? status,
    String? modelName,
    String? modelDisplayName,
    int? receivedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    return AiDownloadState(
      status: status ?? this.status,
      modelName: modelName ?? this.modelName,
      modelDisplayName: modelDisplayName ?? this.modelDisplayName,
      receivedBytes: receivedBytes ?? this.receivedBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

/// Notifier that controls [AiDownloadState].
///
/// Exposes flags that the download loop polls:
/// - [pauseRequested] — pause without deleting partial file.
/// - [cancelRequested] — abort and delete partial file.
class AiDownloadNotifier extends StateNotifier<AiDownloadState> {
  AiDownloadNotifier() : super(const AiDownloadState()) {
    _loadPersistedState();
  }

  // ── Persistence keys ──────────────────────────────────────────────
  static const String _kModel = 'ai_down_model';
  static const String _kDisplay = 'ai_down_display';
  static const String _kReceived = 'ai_down_received';
  static const String _kTotal = 'ai_down_total';
  static const String _kStatus = 'ai_down_status';

  // ── Control flags ─────────────────────────────────────────────────
  bool _pauseRequested = false;
  bool _cancelRequested = false;

  bool get isDownloadActive =>
      state.status == AiDownloadStatus.downloading;

  bool get canResume =>
      state.status == AiDownloadStatus.paused ||
      state.status == AiDownloadStatus.failed;

  /// Ask the download loop to pause (keeps partial file).
  void requestPause() => _pauseRequested = true;

  /// Ask the download loop to cancel (deletes partial file).
  void requestCancel() => _cancelRequested = true;

  bool get isPauseRequested => _pauseRequested;
  bool get isCancelRequested => _cancelRequested;

  void _acknowledgePause() => _pauseRequested = false;
  void _acknowledgeCancel() => _cancelRequested = false;

  // ── Progress updates ──────────────────────────────────────────────

  void updateProgress({
    required AiDownloadStatus status,
    String? modelName,
    String? modelDisplayName,
    int? receivedBytes,
    int? totalBytes,
    String? errorMessage,
  }) {
    state = state.copyWith(
      status: status,
      modelName: modelName,
      modelDisplayName: modelDisplayName,
      receivedBytes: receivedBytes,
      totalBytes: totalBytes,
      errorMessage: errorMessage,
    );
    _persist();
  }

  void markPaused() {
    state = state.copyWith(status: AiDownloadStatus.paused);
    _acknowledgePause();
    _persist();
  }

  void markCompleted() {
    state = const AiDownloadState();
    _acknowledgePause();
    _clearPersisted();
  }

  void markFailed(String error) {
    state = state.copyWith(
      status: AiDownloadStatus.failed,
      errorMessage: error,
    );
    _acknowledgePause();
    _persist();
  }

  /// Download was cancelled by user — reset everything and clean up.
  void markCancelled() {
    state = const AiDownloadState();
    _acknowledgeCancel();
    _acknowledgePause();
    _clearPersisted();
  }

  void reset() {
    state = const AiDownloadState();
    _acknowledgePause();
    _acknowledgeCancel();
    _clearPersisted();
  }

  // ── Persistence helpers ───────────────────────────────────────────

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kModel, state.modelName ?? '');
      if (state.modelDisplayName != null) {
        await prefs.setString(_kDisplay, state.modelDisplayName!);
      }
      await prefs.setInt(_kReceived, state.receivedBytes);
      await prefs.setInt(_kTotal, state.totalBytes);
      await prefs.setString(_kStatus, state.status.name);
    } catch (e) {
      LogService.instance.warning('[AiDownloadNotifier] error: $e', tag: 'AiDownload');
    }
  }

  Future<void> _loadPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final modelName = prefs.getString(_kModel);
      if (modelName == null || modelName.isEmpty) return;

      final statusStr = prefs.getString(_kStatus) ?? '';
      final status = AiDownloadStatus.values.firstWhere(
        (s) => s.name == statusStr,
        orElse: () => AiDownloadStatus.idle,
      );

      if (status == AiDownloadStatus.paused ||
          status == AiDownloadStatus.failed) {
        state = AiDownloadState(
          status: status,
          modelName: modelName,
          modelDisplayName: prefs.getString(_kDisplay),
          receivedBytes: prefs.getInt(_kReceived) ?? 0,
          totalBytes: prefs.getInt(_kTotal) ?? 0,
        );
      }
    } catch (e) {
      LogService.instance.warning('[AiDownloadNotifier] error: $e', tag: 'AiDownload');
    }
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_kModel);
      await prefs.remove(_kDisplay);
      await prefs.remove(_kReceived);
      await prefs.remove(_kTotal);
      await prefs.remove(_kStatus);
    } catch (e) {
      LogService.instance.warning('[AiDownloadNotifier] error: $e', tag: 'AiDownload');
    }
  }
}

final aiDownloadProvider =
    StateNotifierProvider<AiDownloadNotifier, AiDownloadState>(
  (_) => AiDownloadNotifier(),
);
