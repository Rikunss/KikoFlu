import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/log_service.dart';
import '../services/audio_player_service.dart';
import '../services/kikoeru_api_service.dart';

final _log = LogService.instance;

/// Service that syncs playback progress (position) to the Kikoeru server
/// so that cross-device resume works seamlessly.
///
/// Sync is triggered on:
/// - Pause / Stop (instant)
/// - Seek commit (instant)
/// - Periodic timer every 15 seconds during playback
///
/// The user can disable sync via a settings toggle.
class ProgressSyncService {
  static ProgressSyncService? _instance;
  static ProgressSyncService get instance =>
      _instance ??= ProgressSyncService._();

  ProgressSyncService._();

  WidgetRef? _ref;
  bool _enabled = true;
  Timer? _periodicTimer;
  int? _currentWorkId;
  int _lastSyncedPositionMs = 0;
  bool _isSyncing = false;

  /// Initialize with a Riverpod [WidgetRef] so the service can read providers.
  void init(WidgetRef ref) {
    _ref = ref;
  }

  /// Whether progress sync is enabled.
  bool get enabled => _enabled;

  /// Enable or disable progress sync.
  void setEnabled(bool value) {
    _enabled = value;
    if (!_enabled) {
      _stopPeriodicSync();
    } else if (_currentWorkId != null) {
      _startPeriodicSync();
    }
  }

  /// Called when a new work/track starts playing.
  void onTrackStarted(int workId) {
    if (!_enabled) return;
    _currentWorkId = workId;
    _lastSyncedPositionMs = 0;
    _startPeriodicSync();
  }

  /// Called when playback is paused or stopped — instant sync.
  Future<void> onPaused() async {
    if (!_enabled || _currentWorkId == null) return;
    final positionMs = AudioPlayerService.instance.position.inMilliseconds;
    await _syncProgress(_currentWorkId!, positionMs);
    _lastSyncedPositionMs = positionMs;
  }

  /// Called when user seeks — instant sync after a short debounce.
  Timer? _seekDebounce;

  Future<void> onSeekCommitted(Duration position) async {
    if (!_enabled || _currentWorkId == null) return;
    _seekDebounce?.cancel();
    _seekDebounce = Timer(const Duration(milliseconds: 500), () async {
      final posMs = position.inMilliseconds;
      await _syncProgress(_currentWorkId!, posMs);
      _lastSyncedPositionMs = posMs;
    });
  }

  /// Called when a track finishes / work changes — stops periodic sync.
  void onTrackEnded() {
    _stopPeriodicSync();
    _currentWorkId = null;
    _lastSyncedPositionMs = 0;
  }

  // ==========================================================================
  // Periodic sync
  // ==========================================================================

  void _startPeriodicSync() {
    _stopPeriodicSync();
    _periodicTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!_enabled || _currentWorkId == null) return;
      final service = AudioPlayerService.instance;
      if (!service.playing) return;
      final positionMs = service.position.inMilliseconds;
      // Only sync if position has moved by at least 5 seconds
      if ((positionMs - _lastSyncedPositionMs).abs() < 5000) return;
      unawaited(_syncProgress(_currentWorkId!, positionMs));
      _lastSyncedPositionMs = positionMs;
    });
  }

  void _stopPeriodicSync() {
    _periodicTimer?.cancel();
    _periodicTimer = null;
  }

  // ==========================================================================
  // Core sync — push progress to server
  // ==========================================================================

  Future<void> _syncProgress(int workId, int positionMs) async {
    if (_isSyncing) return;
    _isSyncing = true;
    try {
      final duration = AudioPlayerService.instance.duration;
      double progress = 0.0;
      if (duration != null && duration.inMilliseconds > 0) {
        progress = (positionMs / duration.inMilliseconds).clamp(0.0, 1.0);
      }

      // Use the stored Ref to read the API provider.
      // init(ref) is called from main.dart before any playback, so _ref
      // is always available at runtime.
      if (_ref != null) {
        final api = _ref!.read(kikoeruApiServiceProvider);
        await api.updateProgress(workId, progress);
      }
    } catch (e) {
      _log.debug('Progress sync failed (non-critical): $e', tag: 'ProgressSync');
    } finally {
      _isSyncing = false;
    }
  }

  // ==========================================================================
  // Cleanup
  // ==========================================================================

  void dispose() {
    _stopPeriodicSync();
    _seekDebounce?.cancel();
    _instance = null;
  }
}
