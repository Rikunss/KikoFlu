import 'dart:async';
import 'dart:io';
import 'package:just_audio/just_audio.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:path/path.dart' as p;
import 'package:smtc_windows/smtc_windows.dart';

import '../models/audio_track.dart';
import 'cache_service.dart';
import 'equalizer_service.dart';
import 'playback_history_service.dart';
import '../utils/image_blur_util.dart';
import '../utils/audio_format_parser.dart';
import 'audio_format_gain_service.dart';
import 'hi_res_audio_service.dart';
import 'exclusive_audio_service.dart';
import 'mpv_config_service.dart';
import 'replay_gain_service.dart';
import 'volume_normalization_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

class AudioPlayerService {
  static AudioPlayerService? _instance;
  static AudioPlayerService get instance =>
      _instance ??= AudioPlayerService._();

  AudioPlayerService._();

  final AudioPlayer _player = AudioPlayer();
  final List<AudioTrack> _queue = [];
  int _currentIndex = 0;
  AudioHandler? _audioHandler;
  LoopMode _appLoopMode = LoopMode.off; // Track loop mode at app level
  String? _tempPlaybackFilePath; // 临时音频副本路径，用于规避字幕冲突
  Directory? _tempAudioDirectory;
  bool _isSwitchingTrack = false; // Flag to indicate track switching state

  static const List<String> _lyricExtensions = [
    '.lrc',
    '.srt',
    '.vtt',
    '.ass',
    '.ssa',
  ];

  // macOS specific: Track completion state to prevent duplicate triggers
  bool _completionHandled = false;
  Timer? _completionCheckTimer;

  // Timestamp for throttled position-based playback state updates (~1s interval)
  DateTime _lastStateUpdate = DateTime(2000); // macOS workaround for StreamAudioSource completion bug

  // Windows SMTC support
  SMTCWindows? _smtc;
  StreamSubscription? _smtcSubscription;

  // Privacy mode settings
  bool _privacyEnabled = false;
  bool _privacyBlurCover = true;
  bool _privacyMaskTitle = true;
  String _privacyCustomTitle = '正在播放音频';

  // Crossfade settings
  Duration _crossfadeDuration = Duration.zero;
  double _originalVolume = 1.0;
  bool _isCrossfading = false;
  bool _crossfadeCancelled = false;

  // ReplayGain & Volume Normalization
  final ReplayGainService _replayGainService = ReplayGainService.instance;
  final VolumeNormalizationService _volumeNormalizationService =
      VolumeNormalizationService.instance;
  double _userBaseVolume = 1.0;

  // Cached audio format info to avoid redundant file I/O
  AudioFormatInfo? _lastAudioFormat;
  AudioFormatInfo? get lastAudioFormat => _lastAudioFormat;

  // Exclusive audio mode (volume lock + USB routing)
  final ExclusiveAudioService _exclusiveService = ExclusiveAudioService.instance;
  bool _exclusiveModeEnabled = false;

  // Hi-Res audio playback (ExoPlayer for high sample rate files)
  final HiResAudioService _hiResService = HiResAudioService.instance;
  bool _hiResEnabled = false;
  bool _hiResActive = false;
  final StreamController<bool> _hiResActiveController =
      StreamController<bool>.broadcast()..add(false);
  Duration _lastHiResPosition = Duration.zero;
  Duration? _lastHiResDuration;
  Duration _lastHiResBufferedPosition = Duration.zero;
  StreamSubscription? _hiResPlaybackSub;
  StreamSubscription? _hiResBufferingSub;
  // Subscriptions to native-pushed position/duration (50ms interval from Kotlin Handler)
  StreamSubscription<int>? _nativePositionSub;
  StreamSubscription<int>? _nativeDurationSub;
  StreamSubscription<int>? _nativeBufferedPositionSub;
  StreamSubscription<bool>? _trackEndedSub;

  // ── Unified position & duration streams ──
  //
  // Instead of switching streams between just_audio and hi-res polling
  // (which requires provider rebuild tricks), we use a single controller
  // that both just_audio forwarding AND native-pushed events write to.
  // UI always reads from the same stream — no race conditions.
  //
  // Position is pushed from native Kotlin via Handler loop at 50ms intervals
  // (matching just_audio's ~50ms event-driven updates). Duration is pushed
  // once when ExoPlayer reports a valid value. No Dart-side polling necessary.
  final StreamController<Duration> _unifiedPositionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _unifiedDurationController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _unifiedPlayerStateController =
      StreamController<PlayerState>.broadcast();
  StreamSubscription<Duration>? _justAudioPositionSub;
  StreamSubscription<Duration?>? _justAudioDurationSub;

  // Stream controllers
  final StreamController<List<AudioTrack>> _queueController =
      StreamController.broadcast();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController.broadcast();
  final StreamController<bool> _trackLoadingController =
      StreamController<bool>.broadcast();
  final StreamController<AudioFormatInfo?> _audioFormatController =
      StreamController<AudioFormatInfo?>.broadcast();

  // Initialize the service
  Future<void> initialize() async {
    // Initialize audio service handler for system integration
    _audioHandler = await AudioService.init(
      builder: () => _AudioPlayerHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.kikoeru_flutter.channel.audio',
        androidNotificationChannelName: 'Kikoeru Audio',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
      ),
    );

    // Enable hi-res ExoPlayer on Android for lossless format support
    // (FLAC, WAV, ALAC via FFmpeg). Without this, ALAC files would go
    // through just_audio's ExoPlayer which uses the buggy Qualcomm decoder.
    setHiResEnabled(true);
    if (_hiResEnabled) {
      _log.info('[AudioPlayerService] Hi-Res ExoPlayer enabled on Android — ALAC/FLAC/WAV will use FFmpeg decoder');
    }

    // Set initial playback state for all platforms
    _updatePlaybackState();

    // Initialize Windows SMTC (System Media Transport Controls)
    if (Platform.isWindows) {
      try {
        _smtc = SMTCWindows(
          config: const SMTCConfig(
            fastForwardEnabled: false,
            nextEnabled: true,
            pauseEnabled: true,
            playEnabled: true,
            rewindEnabled: false,
            prevEnabled: true,
            stopEnabled: true,
          ),
        );

        // Register SMTC button callbacks
        _smtcSubscription = _smtc!.buttonPressStream.listen((button) {
          if (_instance == null) return; // Prevent callback after disposal
          switch (button) {
            case PressedButton.play:
              play();
              break;
            case PressedButton.pause:
              pause();
              break;
            case PressedButton.next:
              skipToNext();
              break;
            case PressedButton.previous:
              skipToPrevious();
              break;
            case PressedButton.stop:
              stop();
              break;
            default:
              break;
          }
        });

        // Enable SMTC
        _smtc!.enableSmtc();
      } catch (e) {
        _log.error('[AudioPlayerService] Failed to initialize SMTC: $e');
      }
    }

    _setupPlayerListeners();
  }

  /// 更新音频会话配置（直通/独占模式）
  Future<void> updateAudioSessionConfig(bool enablePassthrough) async {
    // ── Windows: WASAPI exclusive via MPV config ──
    if (Platform.isWindows) {
      _log.info('[AudioPlayerService] Windows passthrough ${enablePassthrough ? "enabled" : "disabled"} — regenerating mpv.conf');
      await MpvConfigService.configure();
      _log.info('[AudioPlayerService] mpv.conf regenerated. Restart playback for WASAPI exclusive to take effect.');
      return;
    }

    // ── macOS: CoreAudio exclusive via MPV config ──
    if (Platform.isMacOS) {
      _log.info('[AudioPlayerService] macOS passthrough ${enablePassthrough ? "enabled" : "disabled"} — regenerating mpv.conf');
      await MpvConfigService.configure();
      _log.info('[AudioPlayerService] mpv.conf regenerated. Restart playback for CoreAudio exclusive to take effect.');
      return;
    }

    // ── Linux: currently not supported ──
    if (Platform.isLinux) return;

    // ── Android/iOS: AudioSession config ──
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      _log.info('Updating AudioSession config. Passthrough enabled: $enablePassthrough', tag: 'AudioPlayerService');
      final session = await AudioSession.instance;

      if (enablePassthrough) {
        // 开启直通/独占模式配置 (Movie/Media)
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.moviePlayback,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.movie,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ));
      } else {
        // 恢复默认配置 (Music/Media) - 适合普通音乐播放
        await session.configure(const AudioSessionConfiguration(
          avAudioSessionCategory: AVAudioSessionCategory.playback,
          avAudioSessionCategoryOptions:
              AVAudioSessionCategoryOptions.duckOthers,
          avAudioSessionMode: AVAudioSessionMode.defaultMode,
          androidAudioAttributes: AndroidAudioAttributes(
            contentType: AndroidAudioContentType.music,
            flags: AndroidAudioFlags.none,
            usage: AndroidAudioUsage.media,
          ),
          androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
          androidWillPauseWhenDucked: true,
        ));
      }
      _log.info('AudioSession updated successfully.', tag: 'AudioPlayerService');
    } catch (e) {
      _log.error('Error updating AudioSession: $e', tag: 'AudioPlayerService');
    }
  }

  void _setupPlayerListeners() {
    // Listen to player state changes — forward to unified controller
    _player.playerStateStream.listen((state) {
      // Forward to unified player state controller for non-hi-res playback
      if (!_hiResActive) {
        _unifiedPlayerStateController.add(state);
      }

      if (state.processingState == ProcessingState.completed) {
        if (Platform.isMacOS) {
          // macOS: Use dedicated handler to prevent duplicate triggers
          if (!_completionHandled) {
            _completionHandled = true;
            _handleTrackCompletion();
          }
        } else {
          // Other platforms: Use simple direct handling
          _handleTrackCompletion();
        }
      }

      // Update audio service playback state
      _updatePlaybackState();
    });

    // Forward just_audio position to the unified stream controller
    // so the UI always gets position updates from a single stream.
    // When hi-res is active, the polling timer writes to this same controller.
    _justAudioPositionSub = _player.positionStream.listen((position) {
      if (!_hiResActive) {
        _unifiedPositionController.add(position);
      }

      // Throttled playback state update (~1s interval)
      final now = DateTime.now();
      if (now.difference(_lastStateUpdate) >= const Duration(seconds: 1)) {
        _lastStateUpdate = now;
        _updatePlaybackState();
      }
    });

    // Forward just_audio duration to the unified stream controller
    _justAudioDurationSub = _player.durationStream.listen((duration) {
      if (!_hiResActive) {
        _unifiedDurationController.add(duration);
      }
    });

    // macOS specific: periodic completion check timer
    if (Platform.isMacOS) {
      _startCompletionCheckTimer();
    }
  }

  // Update audio service playback state for system controls
  void _updatePlaybackState() {
    if (_audioHandler == null) return;

    final playing = _hiResActive ? _hiResService.isPlaying : _player.playing;
    final processingState = _hiResActive
        ? ProcessingState.ready
        : _player.processingState;

    // Determine the effective processing state
    // If we are switching tracks, force buffering state to keep system controls active
    final effectiveProcessingState = _isSwitchingTrack
        ? AudioProcessingState.buffering
        : {
              ProcessingState.idle: AudioProcessingState.idle,
              ProcessingState.loading: AudioProcessingState.loading,
              ProcessingState.buffering: AudioProcessingState.buffering,
              ProcessingState.ready: AudioProcessingState.ready,
              ProcessingState.completed: AudioProcessingState.completed,
            }[processingState] ??
            AudioProcessingState.idle;

    (_audioHandler as _AudioPlayerHandler).playbackState.add(PlaybackState(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: effectiveProcessingState,
          playing: playing,
          updatePosition: _hiResActive ? _lastHiResPosition : _player.position,
          bufferedPosition:
              _hiResActive ? _lastHiResBufferedPosition : _player.bufferedPosition,
          speed: _hiResActive ? 1.0 : _player.speed,
        ));

    // Update Windows SMTC playback status
    if (Platform.isWindows && _smtc != null) {
      _smtc!.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused,
      );
    }
  }

  // Queue management
  Future<void> updateQueue(List<AudioTrack> tracks,
      {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);

    _queueController.add(List.from(_queue));

    // Load the current track
    if (tracks.isNotEmpty && _currentIndex < tracks.length) {
      await _loadTrack(tracks[_currentIndex]);
    }
  }

  Future<void> _loadTrack(AudioTrack track) async {
    _log.info('_loadTrack: title="${track.title}"', tag: 'Audio');

    // Emit track immediately so MiniPlayer appears right away
    _currentTrackController.add(track);
    _trackLoadingController.add(true);

    // Check if this track should be routed through hi-res audio
    final useHiRes = await _shouldUseHiResForTrack(track);
    if (useHiRes) {
      await _loadHiResTrack(track);
      return;
    }

    // If hi-res was active but this track is NOT hi-res, stop hi-res player
    if (_hiResActive) {
      await _stopHiResPlayback();
    }

    // Set switching flag and update state to buffering immediately
    _isSwitchingTrack = true;
    _updatePlaybackState();

    // Reset completion flag for new track (macOS specific)
    if (Platform.isMacOS) {
      _completionHandled = false;
    }

    // 清理上一首歌创建的临时文件
    await _cleanupTempPlaybackFile();

    try {
      // Update media item immediately to show new track info
      await _updateMediaItem(
        track,
        privacyEnabled: _privacyEnabled,
        blurCover: _privacyBlurCover,
        maskTitle: _privacyMaskTitle,
        customTitle: _privacyCustomTitle,
      );

      String? audioFilePath;
      bool loaded = false;

      if (track.url.startsWith('file://')) {
        final rawPath = track.url.substring(7);
        final localPath = p.normalize(rawPath);
        final localFile = File(localPath);
        _log.info('检查本地文件: $localPath', tag: 'Audio');

        if (await localFile.exists()) {
          final fileStat = await localFile.stat();
          _log.info('本地文件存在: size=${fileStat.size} bytes, modified=${fileStat.modified}', tag: 'Audio');
          final isolatedPath =
              await _prepareLocalPlaybackPath(localPath) ?? localPath;
          await _player.setFilePath(isolatedPath);
          _log.info('使用本地文件播放: ${track.title}', tag: 'Audio');
          loaded = true;
        } else {
          _log.warning('本地文件不存在: $localPath', tag: 'Audio');
        }
      }

      if (!loaded && track.hash != null && track.hash!.isNotEmpty) {
        audioFilePath = await CacheService.getCachedAudioFile(track.hash!);

        if (audioFilePath != null) {
          // Cache hit — play from local file
          await _player.setFilePath(audioFilePath);
          _log.info('使用缓存文件播放: ${track.title}', tag: 'Audio');
          loaded = true;
        }
      }

      if (!loaded) {
        await _player.setUrl(track.url);
        _log.info('流式播放: ${track.url}', tag: 'Audio');
      }

    } catch (e) {
      _log.error('Error loading audio source: $e');
    } finally {
      _isSwitchingTrack = false;
      _trackLoadingController.add(false);
      _updatePlaybackState();
      _detectAudioFormat(track);
      if (Platform.isAndroid) {
        try {
          final sessionId = _player.androidAudioSessionId;
          if (sessionId != null && sessionId > 0) {
            EqualizerService.instance.setAudioSessionId(sessionId);
          }
        } catch (e) {
          _log.warning('Failed to set audio session ID for equalizer: $e', tag: 'Audio');
        }
      }
      // Apply ReplayGain and Volume Normalization after track is loaded
      _applyAudioGain(track);
    }
  }

  // Update media item for system notification
  // privacySettings: 可选的防社死设置，如果提供则应用隐私保护
  Future<void> _updateMediaItem(
    AudioTrack track, {
    bool privacyEnabled = false,
    bool blurCover = true,
    bool maskTitle = true,
    String customTitle = '正在播放音频',
  }) async {
    if (_audioHandler == null) return;

    // 应用防社死设置
    String displayTitle = track.title;
    String? displayArtworkUrl = track.artworkUrl;

    if (privacyEnabled) {
      // 替换标题
      if (maskTitle) {
        displayTitle = customTitle;
      }

      // 模糊封面
      if (blurCover && displayArtworkUrl != null) {
        try {
          // 生成模糊后的封面并保存到临时文件
          final blurredFilePath =
              await ImageBlurUtil.blurNetworkImageToFile(displayArtworkUrl);
          if (blurredFilePath != null) {
            displayArtworkUrl = blurredFilePath;
          } else {
            // 模糊失败，隐藏封面
            displayArtworkUrl = null;
          }
        } catch (e) {
          _log.error('模糊封面失败: $e');
          displayArtworkUrl = null;
        }
      }
    }

    (_audioHandler as _AudioPlayerHandler).mediaItem.add(MediaItem(
          id: track.id,
          album: track.album ?? '',
          title: displayTitle,
          artist: track.artist ?? '',
          duration: track.duration,
          artUri:
              displayArtworkUrl != null ? Uri.parse(displayArtworkUrl) : null,
        ));

    // Update Windows SMTC media info
    if (Platform.isWindows && _smtc != null) {
      _smtc!.updateMetadata(
        MusicMetadata(
          title: displayTitle,
          artist: track.artist ?? '',
          album: track.album ?? '',
          thumbnail: displayArtworkUrl,
        ),
      );
    }

    // Update playback state immediately after media item change
    _updatePlaybackState();
  }

  /// Set crossfade duration (0 = off / gapless)
  Future<void> setCrossfadeDuration(Duration duration) async {
    _crossfadeDuration = duration;
    _log.info('Crossfade duration set to: ${duration.inMilliseconds}ms', tag: 'Audio');
  }

  /// Apply fade-out effect before switching tracks.
  /// Returns a Future that completes once the fade-out is done.
  Future<void> _fadeOut() async {
    if (_crossfadeDuration <= Duration.zero || _crossfadeCancelled) return;

    _crossfadeCancelled = false;
    _isCrossfading = true;
    _originalVolume = _player.volume;

    final fadeSteps = (_crossfadeDuration.inMilliseconds / 50).round().clamp(1, 100);
    final stepDuration = Duration(
      milliseconds: (_crossfadeDuration.inMilliseconds / fadeSteps).round().clamp(10, 100),
    );
    final volumeStep = _originalVolume / fadeSteps;

    for (int i = 1; i <= fadeSteps; i++) {
      await Future.delayed(stepDuration);
      if (_crossfadeCancelled) return;
      final newVolume = (_originalVolume - (volumeStep * i)).clamp(0.0, _originalVolume);
      await _player.setVolume(newVolume);
    }

    if (!_crossfadeCancelled) {
      await _player.setVolume(0.0);
    }
  }

  /// Apply fade-in effect after switching tracks.
  Future<void> _fadeIn() async {
    if (_crossfadeDuration <= Duration.zero || _crossfadeCancelled) {
      _isCrossfading = false;
      return;
    }

    _crossfadeCancelled = false;

    final fadeSteps = (_crossfadeDuration.inMilliseconds / 50).round().clamp(1, 100);
    final stepDuration = Duration(
      milliseconds: (_crossfadeDuration.inMilliseconds / fadeSteps).round().clamp(10, 100),
    );
    final volumeStep = _originalVolume / fadeSteps;

    await _player.setVolume(0.0);

    for (int i = 1; i <= fadeSteps; i++) {
      await Future.delayed(stepDuration);
      if (_crossfadeCancelled) return;
      final newVolume = (volumeStep * i).clamp(0.0, _originalVolume);
      await _player.setVolume(newVolume);
    }

    if (!_crossfadeCancelled) {
      await _player.setVolume(_originalVolume);
    }
    _isCrossfading = false;
  }

  /// Perform a crossfade transition to the next track.
  /// Fades out → switches track → fades in.
  Future<void> _crossfadeTo(int nextIndex) async {
    if (_queue.isEmpty || nextIndex < 0 || nextIndex >= _queue.length) return;

    _currentIndex = nextIndex;

    // Fade out if crossfade is enabled
    if (_crossfadeDuration > Duration.zero) {
      await _fadeOut();
      if (_crossfadeCancelled) return;
    }

    // Load next track
    await _loadTrack(_queue[_currentIndex]);
    await play();

    // Fade in if crossfade is enabled
    if (_crossfadeDuration > Duration.zero) {
      await _fadeIn();
    }
  }

  // Handle track completion logic
  Future<void> _handleTrackCompletion() async {
    if (_isCrossfading) return; // Guard against re-entry

    // For hi-res tracks — don't cancel native subs here because
    // LoopMode.one needs them active after seek+play.
    // _stopHiResPlayback() handles cleanup when actually switching tracks.

    if (_appLoopMode == LoopMode.one) {
      // Single track repeat - replay current track
      if (Platform.isMacOS) {
        _completionHandled = false;
      }
      seek(Duration.zero);
      play();
    } else if (_currentIndex < _queue.length - 1) {
      // Has next track
      _currentIndex++;
      await _loadTrack(_queue[_currentIndex]);
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false;
        _isCrossfading = true;
        _originalVolume = _player.volume;
        await play();
        await _fadeIn();
      } else {
        await play();
      }
    } else if (_appLoopMode == LoopMode.all && _queue.isNotEmpty) {
      // List repeat - go back to first track
      _currentIndex = 0;
      await _loadTrack(_queue[0]);
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false;
        _isCrossfading = true;
        _originalVolume = _player.volume;
        await play();
        await _fadeIn();
      } else {
        await play();
      }
    } else {
      // Reached the end of the queue with no repeat - pause
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false;
        _isCrossfading = true;
        _originalVolume = _player.volume;
        await _fadeOut();
        if (!_crossfadeCancelled) {
          pause();
          _player.setVolume(_originalVolume);
        }
        _isCrossfading = false;
      } else {
        pause();
      }
    }
  }

  // macOS specific: Start periodic timer to check for track completion
  // This is needed because StreamAudioSource on macOS doesn't properly fire completion events
  void _startCompletionCheckTimer() {
    if (!Platform.isMacOS) return;

    _completionCheckTimer?.cancel();
    _completionCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      final position = _player.position;
      final duration = _player.duration;
      final processingState = _player.processingState;
      final playing = _player.playing;

      if (playing && !_completionHandled) {
        // Check if track is completed
        if (processingState == ProcessingState.completed) {
          _completionHandled = true;
          _handleTrackCompletion();
        } else if (duration != null &&
            duration > Duration.zero &&
            position >= duration - const Duration(milliseconds: 50)) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
    });
  }

  // Playback controls
  Future<void> play() async {
    if (_hiResActive) {
      await _hiResService.resume();
      _updatePlaybackState();
      return;
    }

    // macOS specific: Ensure completion check timer is running
    if (Platform.isMacOS &&
        (_completionCheckTimer == null || !_completionCheckTimer!.isActive)) {
      _startCompletionCheckTimer();
    }

    await _player.play();
    _updatePlaybackState();

    // macOS specific: Check if track completed immediately (workaround for immediate completion bug)
    if (Platform.isMacOS &&
        _player.processingState == ProcessingState.completed) {
      Future.delayed(const Duration(milliseconds: 100), () {
        if (!_completionHandled) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      });
    }
  }

  /// Cancel any in-progress crossfade and restore volume.
  void _cancelCrossfade() {
    if (_isCrossfading) {
      _crossfadeCancelled = true;
      _player.setVolume(_originalVolume);
      _isCrossfading = false;
    }
  }

  Future<void> pause() async {
    _cancelCrossfade();
    if (_hiResActive) {
      await _hiResService.pause();
      _updatePlaybackState();
      return;
    }
    await _player.pause();
    _updatePlaybackState();
  }

  Future<void> stop() async {
    _cancelCrossfade();
    if (_hiResActive) {
      // Use _stopHiResPlayback() which properly cancels subscriptions,
      // stops the native ExoPlayer, and sets _hiResActive = false.
      // Without resetting _hiResActive, _updatePlaybackState() would
      // report ProcessingState.ready instead of idle, which prevents
      // AudioService.java from calling stopSelf() and dismissing the
      // notification — leaving a stale notification behind.
      await _stopHiResPlayback();
      // Also stop just_audio so its processingState becomes idle.
      // AudioService._observePlaybackState() only calls stopSelf()
      // when the playback state transitions TO idle — without this
      // the foreground service & notification never get dismissed.
      await _player.stop();
      _updatePlaybackState();
      return;
    }
    await _player.stop();
    _updatePlaybackState();
  }

  Future<void> seek(Duration position) async {
    _cancelCrossfade();
    if (_hiResActive) {
      await _hiResService.seekTo(position.inMilliseconds);
      _lastHiResPosition = position;
      // Immediately emit position so the UI updates without waiting for next native push tick
      _unifiedPositionController.add(_lastHiResPosition);
      _updatePlaybackState();
      return;
    }
    // macOS specific: Reset completion flag when seeking to allow new completion detection
    if (Platform.isMacOS) {
      _completionHandled = false;
    }
    await _player.seek(position);
    // Immediately emit position so listeners (lyric display, position stream
    // subscribers) react without waiting for the next just_audio position
    // stream tick (~200ms interval). The hi-res path already does this.
    _unifiedPositionController.add(position);
    _updatePlaybackState();
  }

  Future<void> seekForward(Duration duration) async {
    final currentPosition = _hiResActive ? _lastHiResPosition : _player.position;
    final totalDuration = _hiResActive ? _lastHiResDuration : _player.duration;
    if (totalDuration != null) {
      final newPosition = currentPosition + duration;
      await seek(newPosition > totalDuration ? totalDuration : newPosition);
    }
  }

  Future<void> seekBackward(Duration duration) async {
    final currentPosition = _hiResActive ? _lastHiResPosition : _player.position;
    final newPosition = currentPosition - duration;
    await seek(newPosition < Duration.zero ? Duration.zero : newPosition);
  }

  Future<void> skipToNext() async {
    _cancelCrossfade();
    if (_hiResActive) {
      _nativePositionSub?.cancel();
      _nativePositionSub = null;
      _nativeDurationSub?.cancel();
      _nativeDurationSub = null;
      _nativeBufferedPositionSub?.cancel();
      _nativeBufferedPositionSub = null;
    }
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      if (_crossfadeDuration > Duration.zero) {
        await _crossfadeTo(_currentIndex + 1);
      } else {
        _currentIndex++;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
    } else {
      throw Exception('没有下一首可播放');
    }
  }

  Future<void> skipToPrevious() async {
    _cancelCrossfade();
    if (_hiResActive) {
      _nativePositionSub?.cancel();
      _nativePositionSub = null;
      _nativeDurationSub?.cancel();
      _nativeDurationSub = null;
      _nativeBufferedPositionSub?.cancel();
      _nativeBufferedPositionSub = null;
    }
    if (_queue.isNotEmpty && _currentIndex > 0) {
      if (_crossfadeDuration > Duration.zero) {
        await _crossfadeTo(_currentIndex - 1);
      } else {
        _currentIndex--;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
    } else {
      throw Exception('没有上一首可播放');
    }
  }

  Future<void> skipToIndex(int index) async {
    _cancelCrossfade();
    if (_hiResActive) {
      _nativePositionSub?.cancel();
      _nativePositionSub = null;
      _nativeDurationSub?.cancel();
      _nativeDurationSub = null;
      _nativeBufferedPositionSub?.cancel();
      _nativeBufferedPositionSub = null;
    }
    if (index >= 0 && index < _queue.length) {
      if (_crossfadeDuration > Duration.zero && currentTrack != null) {
        await _crossfadeTo(index);
      } else {
        _currentIndex = index;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
    }
  }

  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final wasCurrent = index == _currentIndex;
    final currentTrackId = (_queue.isNotEmpty && _currentIndex < _queue.length)
        ? _queue[_currentIndex].id
        : null;

    _queue.removeAt(index);
    _queueController.add(List.from(_queue));

    if (_queue.isEmpty) {
      _currentIndex = 0;
      await stop();
      _currentTrackController.add(null);
      return;
    }

    if (wasCurrent) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      await _loadTrack(_queue[_currentIndex]);
      await play();
      return;
    }

    if (currentTrackId != null) {
      final updatedIndex =
          _queue.indexWhere((track) => track.id == currentTrackId);
      if (updatedIndex != -1) {
        _currentIndex = updatedIndex;
      }
    }
  }

  /// Clear the entire queue and stop playback.
  Future<void> clearQueue() async {
    _cancelCrossfade();
    if (_hiResActive) {
      _nativePositionSub?.cancel();
      _nativePositionSub = null;
      _nativeDurationSub?.cancel();
      _nativeDurationSub = null;
      _nativeBufferedPositionSub?.cancel();
      _nativeBufferedPositionSub = null;
      await _hiResService.stop();
      _hiResActive = false;
      _hiResActiveController.add(false);
    }
    _queue.clear();
    _currentIndex = 0;
    _queueController.add(List.from(_queue));
    await stop();
    _currentTrackController.add(null);
  }

  Future<void> moveTrack(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;

    if (newIndex < 0) {
      newIndex = 0;
    } else if (newIndex > _queue.length) {
      newIndex = _queue.length;
    }

    if (newIndex > oldIndex) {
      newIndex -= 1;
    }

    if (oldIndex == newIndex) return;

    final currentTrackId = (_queue.isNotEmpty && _currentIndex < _queue.length)
        ? _queue[_currentIndex].id
        : null;

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    if (currentTrackId != null) {
      final updatedIndex =
          _queue.indexWhere((element) => element.id == currentTrackId);
      if (updatedIndex != -1) {
        _currentIndex = updatedIndex;
      }
    }

    _queueController.add(List.from(_queue));
  }

  /// Insert tracks right after the currently playing track ("Play Next").
  /// If the queue is empty, just update the queue with the new tracks.
  /// If tracks already exist in the queue, they are skipped to avoid duplicates.
  Future<void> insertTracksAfterCurrent(List<AudioTrack> tracks) async {
    _cancelCrossfade();
    if (tracks.isEmpty) return;

    // Filter out null/empty tracks and duplicates already in queue
    final existingIds = _queue.map((t) => t.id).toSet();
    final newTracks = tracks.where((t) => !existingIds.contains(t.id)).toList();

    if (newTracks.isEmpty) {
      // All tracks already exist — just skip to the first one
      if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
        _currentIndex++;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
      return;
    }

    if (_queue.isEmpty) {
      // Queue is empty — just start playing
      await updateQueue(newTracks, startIndex: 0);
      await play();
      return;
    }

    if (_currentIndex >= _queue.length - 1) {
      // At the end of queue — append
      final indexMap = await appendTracks(newTracks);
      final firstNewTrack = newTracks.first;
      final targetIndex = indexMap[firstNewTrack.id];
      if (targetIndex != null) {
        _currentIndex = targetIndex;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
      return;
    }

    // Insert after current index
    final insertPos = _currentIndex + 1;
    _queue.insertAll(insertPos, newTracks);
    _queueController.add(List.from(_queue));

    // Play the first new track
    _currentIndex = insertPos;
    await _loadTrack(_queue[_currentIndex]);
    await play();
  }

  Future<Map<String, int>> appendTracks(List<AudioTrack> tracks) async {
    final indexMap = <String, int>{};
    if (tracks.isEmpty) return indexMap;

    if (_queue.isEmpty) {
      await updateQueue(tracks);
      for (var i = 0; i < _queue.length; i++) {
        indexMap[_queue[i].id] = i;
      }
      return indexMap;
    }

    final existingIndex = <String, int>{};
    for (var i = 0; i < _queue.length; i++) {
      existingIndex[_queue[i].id] = i;
    }

    bool appended = false;
    for (final track in tracks) {
      final existing = existingIndex[track.id];
      if (existing != null) {
        indexMap[track.id] = existing;
        continue;
      }

      _queue.add(track);
      final newIndex = _queue.length - 1;
      existingIndex[track.id] = newIndex;
      indexMap[track.id] = newIndex;
      appended = true;
    }

    if (appended) {
      _queueController.add(List.from(_queue));
    }

    // Ensure we still report indexes for tracks that already existed
    for (final track in tracks) {
      indexMap[track.id] ??= existingIndex[track.id] ??
          _queue.indexWhere((element) => element.id == track.id);
    }

    return indexMap;
  }

  // Getters and Streams
  /// Unified player state stream — always reads from the same controller
  /// regardless of whether hi-res or just_audio is active.
  Stream<PlayerState> get playerStateStream => _unifiedPlayerStateController.stream;
  /// Unified position stream — always reads from the same controller
  /// regardless of whether hi-res or just_audio is active.
  Stream<Duration> get positionStream => _unifiedPositionController.stream;
  /// Unified duration stream — always reads from the same controller.
  Stream<Duration?> get durationStream => _unifiedDurationController.stream;
  Stream<List<AudioTrack>> get queueStream => _queueController.stream;
  Stream<AudioTrack?> get currentTrackStream => _currentTrackController.stream;
  Stream<bool> get trackLoadingStream => _trackLoadingController.stream;
  Stream<AudioFormatInfo?> get audioFormatStream => _audioFormatController.stream;

  Duration get position => _hiResActive ? _lastHiResPosition : _player.position;
  Duration? get duration => _hiResActive ? _lastHiResDuration : _player.duration;

  /// The buffered position reported by just_audio or the native hi-res ExoPlayer.
  /// For hi-res tracks, the native Kotlin Handler pushes [nativeBufferedPositionStream]
  /// every 50ms so the UI can track buffer health and estimate download speed.
  Duration get bufferedPosition =>
      _hiResActive ? _lastHiResBufferedPosition : _player.bufferedPosition;
  bool get playing => _hiResActive ? _hiResService.isPlaying : _player.playing;
  PlayerState get playerState => _hiResActive
      ? PlayerState(_hiResService.isPlaying, ProcessingState.ready)
      : _player.playerState;

  /// Enable or disable exclusive audio mode.
  ///
  /// On Android:
  /// - System media volume is locked at maximum
  /// - AAudio exclusive stream (mixer bypassed for bit-perfect)
  /// - PCM gain skipped for bit-perfect output
  ///
  /// On Windows:
  /// - Enables Audio Passthrough (WASAPI exclusive via MPV config)
  /// - PCM gain skipped for bit-perfect output
  ///
  /// NOTE: On both platforms, the change takes effect ONLY on the
  /// NEXT play() call (when the audio engine is recreated).
  Future<void> setExclusiveMode(bool enabled) async {
    final wasPlaying = _player.playing || _hiResActive;

    if (Platform.isAndroid) {
      // ── Android: AAudio exclusive mode ──
      if (enabled) {
        final success = await _exclusiveService.enable();
        _exclusiveModeEnabled = success;
        if (success) {
          await _hiResService.setUseAaudioSink(true);
          await _hiResService.setBitPerfectMode(true);
          await _player.setVolume(1.0);
        }
      } else {
        await _exclusiveService.disable();
        _exclusiveModeEnabled = false;
        await _hiResService.setUseAaudioSink(false);
        await _hiResService.setBitPerfectMode(false);
      }
    } else if (Platform.isWindows) {
      // ── Windows: WASAPI exclusive via MPV ──
      _exclusiveModeEnabled = enabled;
      await MpvConfigService.configure();
      if (enabled) {
        await _player.setVolume(1.0);
      }
      _log.info('Windows exclusive mode ${enabled ? "enabled" : "disabled"} — mpv.conf regenerated', tag: 'Audio');
    } else if (Platform.isMacOS) {
      // ── macOS: CoreAudio exclusive via MPV ──
      _exclusiveModeEnabled = enabled;
      await MpvConfigService.configure();
      if (enabled) {
        await _player.setVolume(1.0);
      }
    } else {
      // ── Other platforms: not supported ──
      return;
    }

    _log.info('Exclusive mode ${_exclusiveModeEnabled ? "enabled" : "disabled"}' 
        '(wasPlaying=$wasPlaying, restartNeeded=${wasPlaying && enabled})', tag: 'Audio');
  }

  /// Whether exclusive audio mode is currently active.
  bool get exclusiveModeEnabled => _exclusiveModeEnabled;

  /// Enable or disable hi-res playback (ExoPlayer for >48kHz files).
  void setHiResEnabled(bool enabled) {
    _hiResEnabled = enabled && Platform.isAndroid;
  }



  AudioTrack? get currentTrack =>
      _queue.isNotEmpty && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;

  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;

  /// Whether the hi-res ExoPlayer path is currently active.
  bool get hiResActive => _hiResActive;

  /// Stream that emits when the hi-res active state changes.
  /// Emits [hiResActive]'s current value on each change.
  Stream<bool> get hiResActiveStream => _hiResActiveController.stream;

  bool get hasNext => _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;


  /// Detect audio format info from the current track's cached or local file.
  Future<void> _detectAudioFormat(AudioTrack track) async {
    final info = await _detectAudioFormatDirect(track);
    _lastAudioFormat = info; // cache for _applyAudioGain
    _audioFormatController.add(info);
  }

  /// Delegates to [AudioFormatGainService.detectFormatDirect].
  /// Local/cached file reads run on the main thread (fast, ~1ms).
  /// HTTP Range requests run in an isolate to avoid blocking on network I/O.
  Future<AudioFormatInfo?> _detectAudioFormatDirect(AudioTrack track) async {
    return AudioFormatGainService.detectFormatDirect(track);
  }

  /// Check if the given track should be played using the hi-res ExoPlayer.
  Future<bool> _shouldUseHiResForTrack(AudioTrack track) async {
    if (!_hiResEnabled) return false;

    final formatInfo = await _detectAudioFormatDirect(track);
    if (formatInfo == null) return false;

    // Check codec first — lossless formats (FLAC, WAV, ALAC/M4A) should always
    // use the hi-res player for proper decoder support (e.g. FFmpeg for ALAC).
    final codec = formatInfo.codec.toUpperCase();
    if (codec == 'FLAC' || codec == 'WAV' || codec == 'M4A') {
      return true;
    }

    // For other formats, use sample rate as the hi-res indicator
    if (formatInfo.sampleRate != null) {
      return formatInfo.sampleRate! > 48000;
    }

    return false;
  }

  /// Load a track through the hi-res ExoPlayer instead of just_audio.
  Future<void> _loadHiResTrack(AudioTrack track) async {
    _log.info('_loadHiResTrack: title="${track.title}"', tag: 'Audio');

    // Stop previous hi-res playback
    await _stopHiResPlayback();

    _hiResActive = true;
    _hiResActiveController.add(true);

    // Update media item for system notification
    await _updateMediaItem(
      track,
      privacyEnabled: _privacyEnabled,
      blurCover: _privacyBlurCover,
      maskTitle: _privacyMaskTitle,
      customTitle: _privacyCustomTitle,
    );

    // Detect format for sample rate / bit depth hints
    final formatInfo = await _detectAudioFormatDirect(track);
    _audioFormatController.add(formatInfo);

    // Build the URL to pass to the native player
    String playUrl = track.url;
    if (playUrl.startsWith('file://')) {
      playUrl = playUrl.substring(7);
      playUrl = playUrl.replaceAll('/', Platform.isWindows ? '\\' : '/');
    }

    final success = await _hiResService.play(
      playUrl,
      sampleRate: formatInfo?.sampleRate ?? 0,
      bitDepth: formatInfo?.bitDepth ?? 0,
    );

    if (!success) {
      _log.warning('Hi-Res playback failed, falling back to just_audio', tag: 'Audio');
      _hiResActive = false;
      _hiResActiveController.add(false);
      // Temporarily disable hi-res to prevent infinite recursion
      final savedEnabled = _hiResEnabled;
      _hiResEnabled = false;
      await _loadTrack(track);
      _hiResEnabled = savedEnabled;
      return;
    }

    // Start native position push (Kotlin Handler pushes every 50ms)
    _nativePositionSub?.cancel();
    _nativePositionSub = _hiResService.nativePositionStream.listen((posMs) {
      if (!_hiResActive) return;
      _lastHiResPosition = Duration(milliseconds: posMs);
      _unifiedPositionController.add(_lastHiResPosition);
    });

    // Duration is pushed once from native when ExoPlayer is ready
    _nativeDurationSub?.cancel();
    _nativeDurationSub = _hiResService.nativeDurationStream.listen((durMs) {
      if (!_hiResActive) return;
      if (durMs > 0) {
        _lastHiResDuration = Duration(milliseconds: durMs);
        _unifiedDurationController.add(_lastHiResDuration);
      }
    });

    // Buffered position pushed from native at ~50ms intervals
    _nativeBufferedPositionSub?.cancel();
    _nativeBufferedPositionSub =
        _hiResService.nativeBufferedPositionStream.listen((bufPosMs) {
      if (!_hiResActive) return;
      _lastHiResBufferedPosition = Duration(milliseconds: bufPosMs);
    });

    // Listen to hi-res playback events — forward to _unifiedPlayerStateController only.
    // Do NOT use isPlaying changes for completion detection (too many false positives).
    _hiResPlaybackSub?.cancel();
    _hiResPlaybackSub = _hiResService.playbackStateStream.listen((isPlaying) {
      if (!_hiResActive) return;
      _unifiedPlayerStateController.add(PlayerState(isPlaying, ProcessingState.ready));
    });

    // Listen to reliable track-ended event from native STATE_ENDED.
    _trackEndedSub?.cancel();
    _trackEndedSub = _hiResService.trackEndedStream.listen((_) {
      if (!_hiResActive) return;
      _handleTrackCompletion();
    });

    // Subscribe to buffering events
    _hiResBufferingSub?.cancel();
    _hiResBufferingSub = _hiResService.bufferingStream.listen((buffering) {
      if (!_hiResActive) return;
      _unifiedPlayerStateController.add(PlayerState(
        _hiResService.isPlaying,
        buffering ? ProcessingState.buffering : ProcessingState.ready,
      ));
    });

    _isSwitchingTrack = false;
    _trackLoadingController.add(false);
    _updatePlaybackState();
  }

  /// Stop the hi-res player and clean up resources.
  Future<void> _stopHiResPlayback() async {
    _nativePositionSub?.cancel();
    _nativePositionSub = null;
    _nativeDurationSub?.cancel();
    _nativeDurationSub = null;
    _nativeBufferedPositionSub?.cancel();
    _nativeBufferedPositionSub = null;
    _hiResPlaybackSub?.cancel();
    _hiResPlaybackSub = null;
    _hiResBufferingSub?.cancel();
    _hiResBufferingSub = null;
    _trackEndedSub?.cancel();
    _trackEndedSub = null;

    if (_hiResActive) {
      await _hiResService.stop();
      _hiResActive = false;
      _hiResActiveController.add(false);
      _lastHiResPosition = Duration.zero;
      _lastHiResDuration = null;
      _lastHiResBufferedPosition = Duration.zero;
      // Emit zero position so the UI resets
      _unifiedPositionController.add(Duration.zero);
      _unifiedDurationController.add(null);
    }
  }

  // Audio settings
  Future<void> setRepeatMode(LoopMode mode) async {
    // Store the mode at app level
    _appLoopMode = mode;
    // Always keep the player's loop mode off to prevent single-track looping
    // We handle all repeat logic in the app layer via playerStateStream listener
    await _player.setLoopMode(LoopMode.off);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  /// Get the current ReplayGain data (for display in Audio Info sheet).
  ReplayGainData? get currentReplayGain => _replayGainService.currentGain;

  /// Get the current volume normalization multiplier (for display).
  double get currentVolumeNormalizationMultiplier =>
      _volumeNormalizationService.currentMultiplier;

  /// Whether ReplayGain is enabled and active for the current track.
  bool get replayGainActive =>
      _replayGainService.enabled && _replayGainService.currentGain != null;

  /// Whether Volume Normalization is enabled and active.
  bool get volumeNormalizationActive => _volumeNormalizationService.enabled;

  /// Re-apply audio gain (ReplayGain + Volume Normalization) to the current track.
  /// Call this when the user changes pre-amp or volume normalization settings
  /// so the change takes effect immediately without waiting for the next track.
  Future<void> reapplyAudioGain() async {
    if (_hiResActive) return; // hi-res tracks handled by native player
    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) return;
    await setVolume(_userBaseVolume);
    _log.info('Re-applied gain: ${_calculateGainMultiplier().toStringAsFixed(3)}x', tag: 'AudioGain');
  }

  Future<void> setVolume(double volume) async {
    _userBaseVolume = volume.clamp(0.0, 1.0);

    // When exclusive mode is active, bypass ALL digital gain to preserve
    // bit-perfect audio output. Volume is handled by the volume-lock mechanism
    // (system volume at max) and app-level volume via the AAudio AudioSink.
    // In bit-perfect mode, the AudioSink itself also skips gain, so we set
    // volume to 1.0 here to avoid double-processing at the just_audio level.
    if (_exclusiveModeEnabled) {
      await _player.setVolume(1.0);
      return;
    }

    // Calculate effective volume including ReplayGain and Volume Normalization
    final gainMultiplier = _calculateGainMultiplier();
    final effectiveVolume = (_userBaseVolume * gainMultiplier).clamp(0.0, 1.0);
    await _player.setVolume(effectiveVolume);
  }

  /// Calculate combined gain multiplier from ReplayGain and Volume Normalization.
  double _calculateGainMultiplier() {
    // When exclusive mode is active, all gain processing is bypassed
    // to preserve bit-perfect audio output.
    if (_exclusiveModeEnabled) return 1.0;

    double multiplier = 1.0;
    if (_replayGainService.enabled) {
      multiplier *= _replayGainService.effectiveVolumeMultiplier;
    }
    if (_volumeNormalizationService.enabled) {
      multiplier *= _volumeNormalizationService.currentMultiplier;
    }
    return multiplier;
  }

  /// Apply audio gain (ReplayGain + Volume Normalization) after a track loads.
  ///
  /// File path resolution runs on the main thread (fast — string ops +
  /// CacheService lookup). ReplayGain file I/O (opening + reading metadata
  /// headers) runs in an isolate to avoid blocking the UI thread. Volume
  /// normalization stays on the main thread since it's pure math when
  /// [_lastAudioFormat] already provides the bit depth.
  Future<void> _applyAudioGain(AudioTrack track) async {
    // Exclusive mode bypasses all DSP/gain processing for bit-perfect output
    if (_exclusiveModeEnabled) {
      _log.info('Exclusive mode active — skipping gain processing', tag: 'AudioGain');
      return;
    }

    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) {
      return; // Nothing to do
    }
    try {
      // ── Fast path: resolve file path on main thread (string + cache lookup) ──
      String? filePath;
      if (track.url.startsWith('file://')) {
        filePath = track.url.substring(7);
      } else if (track.hash != null && track.hash!.isNotEmpty) {
        filePath = await CacheService.getCachedAudioFile(track.hash!);
      }

      ReplayGainData? gainData;

      // ── ReplayGain analysis: file I/O in isolate ──
      if (_replayGainService.enabled && filePath != null) {
        gainData = await AudioFormatGainService.analyzeGain(filePath);
        // Store result back into the service (was previously never stored — bug fix)
        _replayGainService.setCurrentGain(gainData);
      } else {
        // No file available — clear any stale gain data from previous track
        _replayGainService.setCurrentGain(null);
      }

      // ── Volume normalization: pure math with known bitDepth ──
      if (_volumeNormalizationService.enabled) {
        await _volumeNormalizationService.calculateMultiplier(
          filePath,
          bitDepth: _lastAudioFormat?.bitDepth,
          replayGainPeak: gainData?.trackPeak,
        );
      }

      // Apply combined gain using setVolume to avoid race conditions
      await setVolume(_userBaseVolume);

      _log.info('ReplayGain: ${gainData?.trackGain?.toStringAsFixed(2) ?? "N/A"} dB, '
          'Norm: ${_volumeNormalizationService.currentMultiplier.toStringAsFixed(3)}x, '
          'Effective vol: ${(_userBaseVolume * _calculateGainMultiplier() * 100).round()}%', tag: 'AudioGain');
    } catch (e) {
      _log.error('Error applying gain: $e', tag: 'AudioGain');
    }
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  // Privacy mode settings
  /// 更新防社死设置
  Future<void> updatePrivacySettings({
    required bool enabled,
    required bool blurCover,
    required bool maskTitle,
    required String customTitle,
  }) async {
    _privacyEnabled = enabled;
    _privacyBlurCover = blurCover;
    _privacyMaskTitle = maskTitle;
    _privacyCustomTitle = customTitle;

    // 如果当前有正在播放的音轨，立即更新媒体信息
    if (currentTrack != null) {
      await _updateMediaItem(
        currentTrack!,
        privacyEnabled: _privacyEnabled,
        blurCover: _privacyBlurCover,
        maskTitle: _privacyMaskTitle,
        customTitle: _privacyCustomTitle,
      );
    }
  }

  /// The audio handler registered with AudioService (for system controls).
  AudioHandler? get audioHandler => _audioHandler;

  // Cleanup
  Future<void> dispose() async {
    _cancelCrossfade();
    _completionCheckTimer?.cancel();
    _smtcSubscription?.cancel();
    _smtcSubscription = null;
    _justAudioPositionSub?.cancel();
    _justAudioDurationSub?.cancel();
    await _stopHiResPlayback();
    await _cleanupTempPlaybackFile();
    await _hiResActiveController.close();
    await _unifiedPositionController.close();
    await _unifiedDurationController.close();
    await _unifiedPlayerStateController.close();
    await _queueController.close();
    await _currentTrackController.close();
    await _audioFormatController.close();
    await _player.dispose();
  }

  Future<void> _cleanupTempPlaybackFile() async {
    if (_tempPlaybackFilePath == null) return;
    try {
      final tempFile = File(_tempPlaybackFilePath!);
      if (await tempFile.exists()) {
        await tempFile.delete();
        _log.info('已删除临时音频文件: $_tempPlaybackFilePath', tag: 'Audio');
      }
    } catch (e) {
      _log.error('删除临时音频文件失败: $e', tag: 'Audio');
    } finally {
      _tempPlaybackFilePath = null;
    }
  }

  Future<String?> _prepareLocalPlaybackPath(String originalPath) async {
    final lowerPath = originalPath.toLowerCase();
    final shouldInspect = lowerPath.endsWith('.wav') ||
        lowerPath.endsWith('.flac') ||
        lowerPath.endsWith('.m4a') ||
        lowerPath.endsWith('.aac') ||
        lowerPath.endsWith('.ogg') ||
        lowerPath.endsWith('.opus') ||
        lowerPath.endsWith('.mp3');

    if (!shouldInspect) {
      return null;
    }

    final file = File(originalPath);
    final directory = file.parent;
    final baseName = p.basenameWithoutExtension(originalPath);
    final ext = p.extension(originalPath);

    // 检查文件名是否包含非 ASCII 字符（可能导致 MPV 崩溃）
    final hasNonAscii = baseName.codeUnits.any((c) => c > 127);

    // 检查是否有同名字幕文件
    bool hasLyricFile = false;
    for (final lyricExt in _lyricExtensions) {
      final lyricPath = p.join(directory.path, '$baseName$lyricExt');
      final lyricFile = File(lyricPath);
      if (await lyricFile.exists()) {
        hasLyricFile = true;
        _log.info('检测到同名字幕文件: $lyricPath', tag: 'Audio');
        break;
      }
    }

    // 如果有非 ASCII 字符或同名字幕文件，复制到临时目录使用纯 ASCII 文件名
    if (hasNonAscii || hasLyricFile) {
      final reason = hasNonAscii ? '文件名含非ASCII字符' : '存在同名字幕文件';
      _log.info('$reason，需要使用临时文件', tag: 'Audio');

      final tempDir = await _getTempAudioDirectory();
      // 使用纯 ASCII 文件名：时间戳 + 简单哈希
      final hash = originalPath.hashCode.abs().toRadixString(16);
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final newName = 'audio_${timestamp}_$hash$ext';
      final tempPath = p.join(tempDir.path, newName);

      try {
        await file.copy(tempPath);
        _tempPlaybackFilePath = tempPath;
        _log.info('已复制音频到临时路径: $tempPath', tag: 'Audio');
        return tempPath;
      } catch (e) {
        _log.error('复制文件失败: $e', tag: 'Audio');
        return null;
      }
    }

    return null;
  }

  Future<Directory> _getTempAudioDirectory() async {
    if (_tempAudioDirectory != null) return _tempAudioDirectory!;
    final dir =
        Directory(p.join(Directory.systemTemp.path, 'kikoflu_audio_temp'));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    _tempAudioDirectory = dir;
    return dir;
  }
}

// Custom AudioHandler for system integration
class _AudioPlayerHandler extends BaseAudioHandler with SeekHandler {
  final AudioPlayerService _service;

  _AudioPlayerHandler(this._service);

  @override
  Future<void> play() => _service.play();

  @override
  Future<void> pause() async {
    await _service.pause();
    // 系统通知栏/锁屏暂停时也要立即落盘历史
    PlaybackHistoryService.instance.onPaused();
  }

  @override
  Future<void> stop() async {
    await _service.stop();
    // 系统通知栏停止时立即落盘历史
    PlaybackHistoryService.instance.onStopped();
  }

  @override
  Future<void> onTaskRemoved() async {
    // Android: when the user swipes the app away from recent apps,
    // the native AudioService fires onTaskRemoved. Stop playback
    // and dismiss the notification immediately.
    await stop();
    // Clear the media item so even if the notification lingers
    // briefly, it shows no stale track info.
    mediaItem.add(null);
  }

  @override
  Future<void> seek(Duration position) async {
    await _service.seek(position);
    // 系统通知栏/锁屏 seek 时立即落盘历史
    PlaybackHistoryService.instance.onSeekCommitted(position);
  }

  @override
  Future<void> skipToNext() => _service.skipToNext();

  @override
  Future<void> skipToPrevious() => _service.skipToPrevious();
}
