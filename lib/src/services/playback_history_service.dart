import 'dart:async';
import '../models/audio_track.dart';
import '../models/history_record.dart';
import '../models/work.dart';
import 'audio_player_service.dart';
import 'history_database.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// 历史写入触发原因
enum FlushReason {
  checkpoint,
  seekCommitted,
  paused,
  stopped,
  trackChanged,
  appBackground,
  dispose,
}

/// 播放历史服务 - 负责播放历史的写入、节流和即时落盘
///
/// 职责:
/// 1. 管理当前播放会话 snapshot
/// 2. 接收播放器事件 (position tick, seek, pause, stop, track change)
/// 3. 周期性 checkpoint (5s) + 关键事件立即 flush
/// 4. 统一调用 HistoryDatabase 写入
/// 5. 对外发出轻量 "历史已更新" 通知
class PlaybackHistoryService {
  static PlaybackHistoryService? _instance;
  static PlaybackHistoryService get instance =>
      _instance ??= PlaybackHistoryService._();

  PlaybackHistoryService._();

  int? _currentWorkId;
  AudioTrack? _currentTrack;
  int _playlistIndex = 0;
  int _playlistTotal = 0;
  int _lastKnownPositionMs = 0;
  int _lastPersistedPositionMs = 0;
  Work? _currentWork;
  bool _dirty = false;

  /// Timestamp of the last checkpoint tick while playing. Used to compute
  /// wall-clock delta for cumulative listening time.
  DateTime? _lastCheckpointTime;

  /// Accumulated listening time (ms) for the current session's current work.
  /// Reset on track change. Added to the DB's [totalListenedMs] on each persist.
  int _sessionListenedMs = 0;

  StreamSubscription? _positionSubscription;
  StreamSubscription? _trackSubscription;
  Timer? _checkpointTimer;

  final StreamController<int?> _historyUpdatedController =
      StreamController<int?>.broadcast();

  /// 当历史记录被更新时发出通知，携带 workId
  Stream<int?> get historyUpdatedStream => _historyUpdatedController.stream;

  /// 用于从 API 获取 Work 对象的回调（由外部注入，避免服务层直接依赖 API）
  Future<Work> Function(int workId)? onFetchWork;

  /// 绑定播放器服务，启动监听
  void attachPlayer(AudioPlayerService playerService) {
    detach();

    _trackSubscription =
        playerService.currentTrackStream.listen((track) {
      if (track != null && track.workId != null) {
        _onTrackChanged(track, playerService);
      }
    });

    _checkpointTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _onCheckpointTick(playerService);
    });
  }

  /// 周期性 checkpoint: measure wall-clock delta for cumulative listening
  /// time, then persist if position moved enough.
  void _onCheckpointTick(AudioPlayerService playerService) {
    if (_currentWorkId == null || _currentWork == null) return;

    final now = DateTime.now();

    if (playerService.playing) {
      if (_lastCheckpointTime != null) {
        final deltaMs = now.difference(_lastCheckpointTime!).inMilliseconds;
        _sessionListenedMs += deltaMs.clamp(0, 15000);
      }
    }
    _lastCheckpointTime = now;

    if (!playerService.playing) return;

    final positionMs = playerService.position.inMilliseconds;
    if ((positionMs - _lastPersistedPositionMs).abs() < 3000) return;

    _lastKnownPositionMs = positionMs;
    _dirty = true;
    _persistNow(FlushReason.checkpoint);
  }

  /// 当轨道切换时，先 flush 上一首的进度，再更新会话
  Future<void> _onTrackChanged(
      AudioTrack track, AudioPlayerService playerService) async {
    if (_dirty && _currentWork != null) {
      await _persistNow(FlushReason.trackChanged);
    }

    _sessionListenedMs = 0;
    _lastCheckpointTime = null;

    _currentTrack = track;
    _currentWorkId = track.workId;
    _playlistIndex = playerService.currentIndex;
    _playlistTotal = playerService.queue.length;
    _lastKnownPositionMs = playerService.position.inMilliseconds;
    _lastPersistedPositionMs = 0;
    _lastCheckpointTime = DateTime.now();
    _dirty = true;

    await _ensureWork(track.workId!);

    if (_currentWork != null) {
      await _persistNow(FlushReason.trackChanged);
    }
  }

  /// 确保有 Work 对象（先从 DB 查，再从 API 拉）
  Future<void> _ensureWork(int workId) async {
    if (_currentWork != null && _currentWork!.id == workId) return;

    final dbRecord = await HistoryDatabase.instance.getHistoryByWorkId(workId);
    if (dbRecord != null) {
      _currentWork = dbRecord.work;
      return;
    }

    if (onFetchWork != null) {
      try {
        _currentWork = await onFetchWork!(workId);
      } catch (e) {
        _log.error('Failed to fetch work $workId: $e', tag: 'PlaybackHistoryService');
        _currentWork = null;
      }
    }
  }

  /// seek 提交后调用，立即落盘
  Future<void> onSeekCommitted(Duration position) async {
    _lastKnownPositionMs = position.inMilliseconds;
    _dirty = true;
    await _persistNow(FlushReason.seekCommitted);
  }

  /// 暂停时调用
  Future<void> onPaused() async {
    final playerService = AudioPlayerService.instance;
    _lastKnownPositionMs = playerService.position.inMilliseconds;
    _dirty = true;
    await _persistNow(FlushReason.paused);
  }

  /// 停止时调用
  Future<void> onStopped() async {
    final playerService = AudioPlayerService.instance;
    _lastKnownPositionMs = playerService.position.inMilliseconds;
    _dirty = true;
    await _persistNow(FlushReason.stopped);
  }

  /// 应用进入后台时调用
  Future<void> flushNow({FlushReason reason = FlushReason.appBackground}) async {
    if (_currentWorkId == null || _currentWork == null) return;

    final playerService = AudioPlayerService.instance;
    _lastKnownPositionMs = playerService.position.inMilliseconds;
    _dirty = true;
    await _persistNow(reason);
  }

  Future<void> _persistNow(FlushReason reason) async {
    if (!_dirty || _currentWork == null) return;

    final now = DateTime.now();

    int accumulatedMs = _sessionListenedMs;
    try {
      final existing =
          await HistoryDatabase.instance.getHistoryByWorkId(_currentWork!.id);
      if (existing != null) {
        accumulatedMs += existing.totalListenedMs;
      }
    } catch (e) {
      _log.warning('Failed to read existing history for cumulative time: $e',
          tag: 'PlaybackHistoryService');
    }

    final record = HistoryRecord(
      work: _currentWork!,
      lastPlayedTime: now,
      lastTrack: _currentTrack,
      lastPositionMs: _lastKnownPositionMs,
      playlistIndex: _playlistIndex,
      playlistTotal: _playlistTotal,
      totalListenedMs: accumulatedMs,
    );

    try {
      await HistoryDatabase.instance.addOrUpdate(record);
      _lastPersistedPositionMs = _lastKnownPositionMs;
      _sessionListenedMs = 0;
      _dirty = false;

      _historyUpdatedController.add(_currentWorkId);
    } catch (e) {
      _log.error('Failed to persist ($reason): $e', tag: 'PlaybackHistoryService');
    }
  }

  /// 清理资源
  void detach() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _trackSubscription?.cancel();
    _trackSubscription = null;
    _checkpointTimer?.cancel();
    _checkpointTimer = null;
  }

  /// 销毁服务（含最终 flush）
  Future<void> dispose() async {
    if (_dirty && _currentWork != null) {
      await _persistNow(FlushReason.dispose);
    }
    detach();
    await _historyUpdatedController.close();
    _instance = null;
  }

  /// 仅用于测试：重置单例
  static void resetForTest() {
    _instance?.detach();
    _instance = null;
  }

  /// 仅用于测试：获取当前 session 状态
  int? get currentWorkId => _currentWorkId;
  int get lastKnownPositionMs => _lastKnownPositionMs;
  int get lastPersistedPositionMs => _lastPersistedPositionMs;
  bool get dirty => _dirty;
  Work? get currentWork => _currentWork;
  AudioTrack? get currentTrack => _currentTrack;

  /// 仅用于测试：直接设置会话状态
  void setSessionForTest({
    required int workId,
    required Work work,
    AudioTrack? track,
    int positionMs = 0,
  }) {
    _currentWorkId = workId;
    _currentWork = work;
    _currentTrack = track;
    _lastKnownPositionMs = positionMs;
    _lastPersistedPositionMs = 0;
    _dirty = false;
  }
}