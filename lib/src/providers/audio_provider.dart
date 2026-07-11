import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:permission_handler/permission_handler.dart';

import '../models/audio_track.dart';
import '../models/work.dart';
import '../services/log_service.dart';
import '../services/audio_player_service.dart';
import '../services/playback_history_service.dart';
import '../services/progress_sync_service.dart';
import '../services/home_widget_service.dart';
import '../utils/audio_format_parser.dart';
import 'settings_provider.dart';
import 'history_provider.dart';
import '../services/kikoeru_api_service.dart';

/// Provider that tracks whether the hi-res ExoPlayer path is currently active.
/// Unlike [hiResPlaybackStateProvider] (which only reports `isPlaying`),
/// this provider emits `true` even when the hi-res track is paused,
/// because the ExoPlayer is still configured and ready.
final hiResActiveProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.hiResActiveStream;
});

final audioPlayerServiceProvider = Provider<AudioPlayerService>((ref) {
  final service = AudioPlayerService.instance;
  return service;
});

final currentTrackProvider = StreamProvider<AudioTrack?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.currentTrackStream;
});

/// Player State Provider.
///
/// When hi-res is active, uses a dedicated stream controller
/// ([HiResAudioService.playbackStateStream]) for accurate state reporting.
/// Otherwise, forwards [just_audio.playerStateStream].
final playerStateProvider = StreamProvider<PlayerState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.playerStateStream;
});

/// Position Provider — always reads from [AudioPlayerService.positionStream].
///
/// This stream is backed by a single unified [StreamController] that
/// collects position updates from both just_audio forwarding AND
/// hi-res polling. No provider switching needed — the UI always
/// subscribes to the same stream.
final positionProvider = StreamProvider<Duration>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.positionStream;
});

/// Duration Provider — always reads from [AudioPlayerService.durationStream].
/// Same unified-controller approach as positionProvider.
final durationProvider = StreamProvider<Duration?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.durationStream;
});

final queueProvider = StreamProvider<List<AudioTrack>>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.queueStream;
});

final isPlayingProvider = Provider<bool>((ref) {
  final playerState = ref.watch(playerStateProvider);
  return playerState.when(
    data: (state) => state.playing,
    loading: () => false,
    error: (_, __) => false,
  );
});

final audioFormatInfoProvider = StreamProvider<AudioFormatInfo?>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);

  Stream<AudioFormatInfo?> createStream() async* {
    final cached = service.lastAudioFormat;
    if (cached != null) {
      yield cached;
    }
    yield* service.audioFormatStream;
  }

  return createStream();
});

final isTrackLoadingProvider = StreamProvider<bool>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return service.trackLoadingStream;
});

/// Combined playback progress — position + duration in one provider.
/// Widgets that need both values (slider, time labels) watch ONE provider
/// instead of two, halving the listen count and reducing rebuilds.
final playbackProgressProvider =
    Provider<({Duration position, Duration? duration})>((ref) {
  final position = ref.watch(positionProvider);
  final duration = ref.watch(durationProvider);
  return (
    position: position.valueOrNull ?? Duration.zero,
    duration: duration.valueOrNull,
  );
});

final progressProvider = Provider<double>((ref) {
  final position = ref.watch(positionProvider);
  final duration = ref.watch(durationProvider);

  return position.when(
    data: (pos) => duration.when(
      data: (dur) => dur != null && dur.inMilliseconds > 0
          ? pos.inMilliseconds / dur.inMilliseconds
          : 0.0,
      loading: () => 0.0,
      error: (_, __) => 0.0,
    ),
    loading: () => 0.0,
    error: (_, __) => 0.0,
  );
});

/// 是否可以播放下一首（列表未结束或开启了循环模式）
final canSkipNextProvider = Provider<bool>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  final repeatMode = ref.watch(
    audioPlayerControllerProvider.select((s) => s.repeatMode),
  );
  ref.watch(queueProvider);
  ref.watch(currentTrackProvider);

  if (repeatMode == LoopMode.all ||
      repeatMode == LoopMode.one) {
    return true;
  }

  return service.hasNext;
});

class AudioPlayerController extends StateNotifier<AudioPlayerState> {
  final AudioPlayerService _service;
  final Ref _ref;
  StreamSubscription? _playerStateSub;
  StreamSubscription? _trackSub;

  AudioPlayerController(this._service, this._ref)
      : super(const AudioPlayerState()) {
    _ref.listen<PrivacyModeSettings>(
      privacyModeSettingsProvider,
      (previous, next) {
        _service.updatePrivacySettings(
          enabled: next.enabled,
          blurCover: next.blurCover,
          maskTitle: next.maskTitle,
          customTitle: next.customTitle,
        );
      },
    );

    _ref.listen<bool>(
      audioPassthroughProvider,
      (previous, next) {
        if (previous != next) {
          _service.updateAudioSessionConfig(next);
        }
      },
    );

    _ref.listen<int>(
      crossfadeDurationProvider,
      (previous, next) {
        if (previous != next) {
          _service.setCrossfadeDuration(Duration(milliseconds: next));
          state = state.copyWith(crossfadeDuration: Duration(milliseconds: next));
        }
      },
    );

  }

  Future<void> initialize() async {
    unawaited(Permission.notification.request());

    await _service.initialize();

    final privacySettings = _ref.read(privacyModeSettingsProvider);
    await _service.updatePrivacySettings(
      enabled: privacySettings.enabled,
      blurCover: privacySettings.blurCover,
      maskTitle: privacySettings.maskTitle,
      customTitle: privacySettings.customTitle,
    );

    final crossfadeMs = _ref.read(crossfadeDurationProvider);
    await _service.setCrossfadeDuration(Duration(milliseconds: crossfadeMs));
    state = state.copyWith(crossfadeDuration: Duration(milliseconds: crossfadeMs));

    _playerStateSub = _service.playerStateStream.listen((_) {
    });

    _trackSub = _service.currentTrackStream.listen((track) {
      if (track?.workId != null) {
        ProgressSyncService.instance.onTrackStarted(track!.workId!);
      }
      HomeWidgetService.instance.updateTrackState(
        track: track,
        isPlaying: _service.playing,
      );
    });
  }

  Future<void> playTrack(AudioTrack track) async {
    final shouldAppend = state.appendMode && queue.isNotEmpty;

    if (shouldAppend) {
      final indexMap = await _service.appendTracks([track]);
      final targetIndex = indexMap[track.id];
      if (targetIndex != null) {
        await _service.skipToIndex(targetIndex);
      }
    } else {
      await _service.updateQueue([track]);
      await _service.play();
    }
    if (track.workId != null) {
      try {
        final api = _ref.read(kikoeruApiServiceProvider);
        final json = await api.getWork(track.workId!);
        final work = Work.fromJson(json);
        _ref.read(historyProvider.notifier).addOrUpdate(work,
            track: track, positionMs: _service.position.inMilliseconds);
      } catch (e) {
        LogService.instance.warning(
            'Failed to record history for playTrack (id=${track.workId}): $e', tag: 'Playback');

      }
    }
  }

  Future<void> playTracks(List<AudioTrack> tracks,
      {int startIndex = 0, Work? work}) async {
    LogService.instance.debug(
        '[AudioController] playTracks调用: ${tracks.length}个轨道, startIndex=$startIndex', tag: 'Playback');
    LogService.instance.debug(
        '[AudioController] 第一个轨道: title="${tracks.first.title}", url="${tracks.first.url}"', tag: 'Playback');

    final shouldAppend = state.appendMode && queue.isNotEmpty;

    if (shouldAppend) {
      final indexMap = await _service.appendTracks(tracks);
      final targetTrack = tracks[startIndex.clamp(0, tracks.length - 1)];
      final targetIndex = indexMap[targetTrack.id];
      if (targetIndex != null) {
        await _service.skipToIndex(targetIndex);
      }
    } else {
      await _service.updateQueue(tracks, startIndex: startIndex);
      LogService.instance.debug('[AudioController] updateQueue完成', tag: 'Playback');
      await _service.play();
      LogService.instance.debug('[AudioController] play完成', tag: 'Playback');
    }

    if (work != null) {
      _ref.read(historyProvider.notifier).addOrUpdate(work);
    }
  }

  Future<void> play() async {
    await _service.play();
    _updateWidget();
  }

  Future<void> pause() async {
    await _service.pause();
    _updateWidget();
    PlaybackHistoryService.instance.onPaused();
    await ProgressSyncService.instance.onPaused();
  }

  Future<void> stop() async {
    await _service.stop();
    PlaybackHistoryService.instance.onStopped();
  }

  Future<void> seek(Duration position) async {
    await _service.seek(position);
  }

  /// seek 并立即持久化历史（用于用户显式拖动进度条）
  Future<void> seekAndPersist(Duration position) async {
    await _service.seek(position);
    await PlaybackHistoryService.instance.onSeekCommitted(position);
    await ProgressSyncService.instance.onSeekCommitted(position);
  }

  Future<void> seekForward(Duration duration) async {
    await _service.seekForward(duration);
  }

  Future<void> seekBackward(Duration duration) async {
    await _service.seekBackward(duration);
  }

  Future<void> skipToNext() async {
    await _service.skipToNext();
  }

  Future<void> skipToPrevious() async {
    await _service.skipToPrevious();
  }

  Future<void> skipToIndex(int index) async {
    await _service.skipToIndex(index);
  }

  Future<void> removeTrackAt(int index) async {
    await _service.removeTrackAt(index);
  }

  Future<void> moveTrack(int oldIndex, int newIndex) async {
    await _service.moveTrack(oldIndex, newIndex);
  }

  /// Clear all tracks from the queue and stop playback.
  Future<void> clearQueue() async {
    await _service.clearQueue();
  }

  /// Save current queue as a new playlist on the server.
  /// Collects unique work IDs from all tracks, then calls createPlaylist.
  Future<void> saveQueueAsPlaylist({
    required String name,
    int privacy = 0,
    String? description,
  }) async {
    final tracks = _service.queue;
    final workIds = tracks
        .map((t) => t.workId)
        .where((id) => id != null)
        .cast<int>()
        .toSet()
        .toList();

    final api = _ref.read(kikoeruApiServiceProvider);
    await api.createPlaylist(
      name: name,
      privacy: privacy,
      description: description,
      works: workIds.isNotEmpty ? workIds : null,
    );
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    await _service.setRepeatMode(mode);
    state = state.copyWith(repeatMode: mode);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _service.setShuffleMode(enabled);
    state = state.copyWith(shuffleMode: enabled);
  }

  bool toggleAppendMode() {
    final newValue = !state.appendMode;
    final shouldShowHint = newValue && !state.hasShownAppendHint;
    state = state.copyWith(
      appendMode: newValue,
      hasShownAppendHint: state.hasShownAppendHint || shouldShowHint,
    );
    return shouldShowHint;
  }

  Future<void> setVolume(double volume) async {
    await _service.setVolume(volume);
    state = state.copyWith(volume: volume);
  }

  Future<void> setSpeed(double speed) async {
    await _service.setSpeed(speed);
    state = state.copyWith(speed: speed);
  }

  Future<void> setCrossfadeDuration(Duration duration) async {
    await _service.setCrossfadeDuration(duration);
    state = state.copyWith(crossfadeDuration: duration);
  }

  @override
  void dispose() {
    _playerStateSub?.cancel();
    _trackSub?.cancel();
    ProgressSyncService.instance.onTrackEnded();
    super.dispose();
  }

  bool get isPlaying => _service.playing;
  PlayerState get playerState => _service.playerState;
  AudioTrack? get currentTrack => _service.currentTrack;
  List<AudioTrack> get queue => _service.queue;
  Stream<PlayerState> get playerStateStream => _service.playerStateStream;
  Stream<AudioTrack?> get currentTrackStream => _service.currentTrackStream;

  /// Update the Android home screen widget with current track state.
  void _updateWidget() {
    HomeWidgetService.instance.updateTrackState(
      track: _service.currentTrack,
      isPlaying: _service.playing,
    );
  }
}

class AudioPlayerState {
  final LoopMode repeatMode;
  final bool shuffleMode;
  final double volume;
  final double speed;
  final bool appendMode;
  final bool hasShownAppendHint;
  final Duration crossfadeDuration;

  const AudioPlayerState({
    this.repeatMode = LoopMode.off,
    this.shuffleMode = false,
    this.volume = 1.0,
    this.speed = 1.0,
    this.appendMode = false,
    this.hasShownAppendHint = false,
    this.crossfadeDuration = Duration.zero,
  });

  AudioPlayerState copyWith({
    LoopMode? repeatMode,
    bool? shuffleMode,
    double? volume,
    double? speed,
    bool? appendMode,
    bool? hasShownAppendHint,
    Duration? crossfadeDuration,
  }) {
    return AudioPlayerState(
      repeatMode: repeatMode ?? this.repeatMode,
      shuffleMode: shuffleMode ?? this.shuffleMode,
      volume: volume ?? this.volume,
      speed: speed ?? this.speed,
      appendMode: appendMode ?? this.appendMode,
      hasShownAppendHint: hasShownAppendHint ?? this.hasShownAppendHint,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
    );
  }
}

final audioPlayerControllerProvider =
    StateNotifierProvider<AudioPlayerController, AudioPlayerState>((ref) {
  final service = ref.watch(audioPlayerServiceProvider);
  return AudioPlayerController(service, ref);
});

class MiniPlayerVisibilityController extends StateNotifier<bool> {
  MiniPlayerVisibilityController() : super(true);

  void show() => state = true;
  void hide() => state = false;
}

final miniPlayerVisibilityProvider =
    StateNotifierProvider<MiniPlayerVisibilityController, bool>((ref) {
  return MiniPlayerVisibilityController();
});

/// Provider to track when the fullscreen player route is active.
final isFullscreenPlayerActiveProvider = StateProvider<bool>((ref) => false);

/// Provider to toggle the blurred cover background in the fullscreen player.
final showBlurredBackgroundProvider = StateProvider<bool>((ref) => true);

class SleepTimerController extends StateNotifier<SleepTimerState> {
  final Ref _ref;
  Timer? _timer;
  Timer? _countdownTimer;
  StreamSubscription? _trackSubscription;

  SleepTimerController(this._ref) : super(const SleepTimerState());

  /// 设置定时器（按时长）
  void setTimer(Duration duration, {bool finishCurrentTrack = false}) {
    final endTime = DateTime.now().add(duration);
    _setTimerInternal(endTime, finishCurrentTrack: finishCurrentTrack);
  }

  /// 设置定时器（按指定时间）
  void setTimerUntil(DateTime targetTime, {bool finishCurrentTrack = false}) {
    _setTimerInternal(targetTime, finishCurrentTrack: finishCurrentTrack);
  }

  /// 内部方法：设置定时器到指定时间
  void _setTimerInternal(DateTime endTime, {bool finishCurrentTrack = false}) {
    cancelTimer();

    final duration = endTime.difference(DateTime.now());

    if (duration.isNegative || duration.inSeconds < 1) {
      return;
    }

    _timer = Timer(duration, () {
      if (state.finishCurrentTrack) {
        _waitForTrackEndAndPause();
      } else {
        final audioController =
            _ref.read(audioPlayerControllerProvider.notifier);
        audioController.pause();
        cancelTimer();
      }
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      final remaining = endTime.difference(DateTime.now());
      if (remaining.isNegative) {
        timer.cancel();
        return;
      }
      state = SleepTimerState(
        isActive: true,
        endTime: endTime,
        remainingTime: remaining,
        finishCurrentTrack: finishCurrentTrack,
      );
    });

    state = SleepTimerState(
      isActive: true,
      endTime: endTime,
      remainingTime: duration,
      finishCurrentTrack: finishCurrentTrack,
    );
  }

  /// 等待当前音轨播放结束并暂停
  void _waitForTrackEndAndPause() {
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;

    final audioController = _ref.read(audioPlayerControllerProvider.notifier);
    final initialTrack = audioController.currentTrack;

    if (initialTrack == null) {
      cancelTimer();
      return;
    }

    state = state.copyWith(
      waitingForTrackEnd: true,
      remainingTime: Duration.zero,
    );

    _trackSubscription?.cancel();
    _trackSubscription = audioController.currentTrackStream.listen(
      (track) {
        if (track?.id != initialTrack.id) {
          audioController.pause();
          cancelTimer();
        }
      },
    );
  }

  /// 取消定时器
  void cancelTimer() {
    _timer?.cancel();
    _timer = null;
    _countdownTimer?.cancel();
    _countdownTimer = null;
    _trackSubscription?.cancel();
    _trackSubscription = null;
    state = const SleepTimerState();
  }

  /// 添加时间（延长定时器）
  void addTime(Duration duration) {
    if (state.isActive && state.endTime != null) {
      final newEndTime = state.endTime!.add(duration);
      final newRemaining = newEndTime.difference(DateTime.now());

      setTimer(
        newRemaining,
        finishCurrentTrack: state.finishCurrentTrack,
      );
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _countdownTimer?.cancel();
    _trackSubscription?.cancel();
    super.dispose();
  }
}

class SleepTimerState {
  final bool isActive;
  final DateTime? endTime;
  final Duration? remainingTime;
  final bool finishCurrentTrack;
  final bool waitingForTrackEnd;

  const SleepTimerState({
    this.isActive = false,
    this.endTime,
    this.remainingTime,
    this.finishCurrentTrack = false,
    this.waitingForTrackEnd = false,
  });

  SleepTimerState copyWith({
    bool? isActive,
    DateTime? endTime,
    Duration? remainingTime,
    bool? finishCurrentTrack,
    bool? waitingForTrackEnd,
  }) {
    return SleepTimerState(
      isActive: isActive ?? this.isActive,
      endTime: endTime ?? this.endTime,
      remainingTime: remainingTime ?? this.remainingTime,
      finishCurrentTrack: finishCurrentTrack ?? this.finishCurrentTrack,
      waitingForTrackEnd: waitingForTrackEnd ?? this.waitingForTrackEnd,
    );
  }

  String get formattedTime {
    if (remainingTime == null) return '';

    final hours = remainingTime!.inHours;
    final minutes = remainingTime!.inMinutes.remainder(60);
    final seconds = remainingTime!.inSeconds.remainder(60);

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}

final sleepTimerProvider =
    StateNotifierProvider<SleepTimerController, SleepTimerState>((ref) {
  return SleepTimerController(ref);
});