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
import '../utils/image_blur_util.dart';
import '../utils/audio_format_parser.dart';
import 'audio_format_gain_service.dart';
import 'exclusive_audio_service.dart';
import 'usb_dac_audio_manager.dart';
import 'mpv_config_service.dart';
import 'log_service.dart';
import 'audio_player_handler.dart';
import 'audio_queue_manager.dart';
import 'audio_hi_res_manager.dart';
import 'audio_crossfade_manager.dart';
import 'audio_gain_manager.dart';
import 'replay_gain_service.dart';

final _log = LogService.instance;

class AudioPlayerService {
  static AudioPlayerService? _instance;
  static AudioPlayerService get instance =>
      _instance ??= AudioPlayerService._();

  AudioPlayerService._() {
    _initManagers();
  }

  final AudioPlayer _player = AudioPlayer();
  AudioHandler? _audioHandler;
  String? _tempPlaybackFilePath;
  Directory? _tempAudioDirectory;
  bool _isSwitchingTrack = false;
  bool _completionHandled = false;
  Timer? _completionCheckTimer;
  DateTime _lastStateUpdate = DateTime(2000);

  static const List<String> _lyricExtensions = [
    '.lrc', '.srt', '.vtt', '.ass', '.ssa',
  ];

  // ── SMTC (Windows) ──
  SMTCWindows? _smtc;
  StreamSubscription? _smtcSubscription;

  // ── Privacy ──
  bool _privacyEnabled = false;
  bool _privacyBlurCover = true;
  bool _privacyMaskTitle = true;
  String _privacyCustomTitle = '正在播放音频';

  // ── USB DAC ──
  final UsbDacAudioManager _usbDacManager = UsbDacAudioManager.instance;
  bool _libusbDacActive = false;
  bool _dacConnected = false;
  bool _dacResumeInFlight = false;
  bool _autoEnabledLibusb = false;
  int _lastSavedDacPositionMs = 0;
  StreamSubscription<UsbDacManagerState>? _libusbStateSub;

  // ── Exclusive Mode ──
  final ExclusiveAudioService _exclusiveService = ExclusiveAudioService.instance;
  bool _exclusiveModeEnabled = false;

  // ── Managers ──
  late final AudioQueueManager _queueManager;
  late final AudioHiResManager _hiResManager;
  late final AudioCrossfadeManager _crossfadeManager;
  late final AudioGainManager _gainManager;

  // ── Unified Streams ──
  final StreamController<Duration> _unifiedPositionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _unifiedDurationController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _unifiedPlayerStateController =
      StreamController<PlayerState>.broadcast();
  StreamSubscription<Duration>? _justAudioPositionSub;
  StreamSubscription<Duration?>? _justAudioDurationSub;

  final StreamController<bool> _trackLoadingController =
      StreamController<bool>.broadcast();
  final StreamController<AudioFormatInfo?> _audioFormatController =
      StreamController<AudioFormatInfo?>.broadcast();

  // ── Initialization ──

  Future<void> initialize() async {
    _audioHandler = await AudioService.init(
      builder: () => AudioPlayerHandler(this),
      config: const AudioServiceConfig(
        androidNotificationChannelId:
            'com.example.kikoeru_flutter.channel.audio',
        androidNotificationChannelName: 'Kikoeru Audio',
        androidNotificationOngoing: false,
        androidStopForegroundOnPause: false,
        androidShowNotificationBadge: true,
      ),
    );

    setHiResEnabled(true);
    if (_hiResManager.hiResEnabled) {
      _log.info(
          '[AudioPlayerService] Hi-Res ExoPlayer enabled on Android — ALAC/FLAC/WAV will use FFmpeg decoder');
    }

    _updatePlaybackState();

    if (Platform.isWindows) {
      _initSmtc();
    }

    _setupPlayerListeners();
    _setupLibusbListener();
  }

  void _initManagers() {
    _queueManager = AudioQueueManager(
      onLoadTrack: (track, {int startPositionMs = 0}) =>
          _loadTrack(track, startPositionMs: startPositionMs),
      onPlay: () => play(),
    );

    _hiResManager = AudioHiResManager();
    _hiResManager.onPositionChanged = (pos) {
      _unifiedPositionController.add(pos);
    };
    _hiResManager.onDurationChanged = (dur) {
      _unifiedDurationController.add(dur);
    };
    _hiResManager.onBufferedPositionChanged = (_) {};
    _hiResManager.onPlaybackStateChanged = (isPlaying) {
      _unifiedPlayerStateController.add(PlayerState(
        isPlaying,
        ProcessingState.ready,
      ));
      _updatePlaybackState();
    };
    _hiResManager.onBufferingChanged = (buffering) {
      _unifiedPlayerStateController.add(PlayerState(
        _hiResManager.isPlaying,
        buffering ? ProcessingState.buffering : ProcessingState.ready,
      ));
    };
    _hiResManager.onFallbackLoadTrack = (
      AudioTrack track, {
      int startPositionMs = 0,
    }) async {
      await _loadTrack(track, startPositionMs: startPositionMs);
    };
    _hiResManager.onErrorFallbackStarted = () {};
    _hiResManager.onTrackCompleted = () {
      _handleTrackCompletion();
    };

    _crossfadeManager = AudioCrossfadeManager(_player);
    _gainManager = AudioGainManager(_player);
  }

  void _initSmtc() {
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
      _smtcSubscription = _smtc!.buttonPressStream.listen((button) {
        if (_instance == null) return;
        switch (button) {
          case PressedButton.play:
            play();
          case PressedButton.pause:
            pause();
          case PressedButton.next:
            skipToNext();
          case PressedButton.previous:
            skipToPrevious();
          case PressedButton.stop:
            stop();
          default:
            break;
        }
      });
      _smtc!.enableSmtc();
    } catch (e) {
      _log.error('[AudioPlayerService] Failed to initialize SMTC: $e');
    }
  }

  void _setupPlayerListeners() {
    _player.playerStateStream.listen((state) {
      if (!_hiResManager.hiResActive) {
        _unifiedPlayerStateController.add(state);
      }

      if (state.processingState == ProcessingState.completed) {
        if (Platform.isMacOS) {
          if (!_completionHandled) {
            _completionHandled = true;
            _handleTrackCompletion();
          }
        } else {
          _handleTrackCompletion();
        }
      }

      _updatePlaybackState();
    });

    _justAudioPositionSub = _player.positionStream.listen((position) {
      if (!_hiResManager.hiResActive) {
        _unifiedPositionController.add(position);
      }
      final now = DateTime.now();
      if (now.difference(_lastStateUpdate) >= const Duration(seconds: 1)) {
        _lastStateUpdate = now;
        _updatePlaybackState();
      }
    });

    _justAudioDurationSub = _player.durationStream.listen((duration) {
      if (!_hiResManager.hiResActive) {
        _unifiedDurationController.add(duration);
      }
    });

    if (Platform.isMacOS) _startCompletionCheckTimer();
  }

  void _setupLibusbListener() {
    _libusbStateSub = _usbDacManager.stateStream.listen((state) async {
      if (_dacResumeInFlight) {
        _log.info('[LIBUSB] re-entry suppressed — DAC re-plug already in flight',
            tag: 'Audio');
        return;
      }
      final wasActive = _libusbDacActive;
      final wasConnected = _dacConnected;
      _libusbDacActive = state.dacActive;
      _dacConnected = state.dacConnected;

      _log.info('[LIBUSB] stateStream: '
          'dacConnected=${state.dacConnected}, '
          'dacActive=${state.dacActive}, '
          'wasActive=$wasActive, '
          'wasConnected=$wasConnected, '
          'autoDacEnabled=${state.autoDacEnabled}, '
          'device="${state.deviceName}"',
          tag: 'Audio');

      if (state.dacActive && !wasActive) {
        _log.info(
            '[LIBUSB] >>> dacActive transitioned false→true — switching to LibusbAudioSink',
            tag: 'Audio');

        _dacResumeInFlight = true;
        try {
          await _hiResManager.hiResService.setUseAaudioSink(false);
          await _hiResManager.hiResService.setUseLibusbSink(true);
          await _hiResManager.hiResService.setBitPerfectMode(true);

          final track = currentTrack;
          if (track != null) {
            final resumeMs = _lastSavedDacPositionMs > 0
                ? _lastSavedDacPositionMs
                : _player.playing || _hiResManager.hiResActive
                    ? (_hiResManager.hiResActive
                        ? _hiResManager.freezePositionMs()
                        : _player.position.inMilliseconds)
                    : 0;
            _log.info(
                '[LIBUSB] DAC re-plug — restarting track through libusb '
                'at position ${resumeMs}ms',
                tag: 'Audio');
            if (resumeMs > 0 || _player.playing || _hiResManager.hiResActive) {
              await _loadTrack(track, startPositionMs: resumeMs);
              await play();
            }
            _lastSavedDacPositionMs = 0;
          }
        } finally {
          _dacResumeInFlight = false;
        }
      } else if (!state.dacConnected && wasConnected) {
        _log.info(
            '[LIBUSB] DAC physically detached — stopping playback and falling back',
            tag: 'Audio');
        final frozenMs = _hiResManager.hiResActive
            ? _hiResManager.freezePositionMs()
            : _player.position.inMilliseconds;
        if (frozenMs > 0) {
          _lastSavedDacPositionMs = frozenMs;
        }
        _log.info(
            '[LIBUSB] Audio frozen at ${frozenMs}ms on DAC detach '
            '(saved ${_lastSavedDacPositionMs}ms for re-plug resume)',
            tag: 'Audio');

        await _hiResManager.hiResService.setUseLibusbSink(false);
        if (_exclusiveModeEnabled) {
          await _hiResManager.hiResService.setUseAaudioSink(true);
        }

        if (_hiResManager.hiResActive) {
          await _hiResManager.stopHiResPlayback();
        }
        if (_player.playing) {
          await _player.pause();
        }
      } else if (state.dacConnected && !state.dacActive && wasActive) {
        _log.info(
            '[LIBUSB] dacActive transitioned true→false (DAC still attached) — disabling libusb sink',
            tag: 'Audio');
        await _hiResManager.hiResService.setUseLibusbSink(false);
      } else if (state.dacConnected) {
        _log.info(
            '[LIBUSB] DAC connected but idle (dacActive=${state.dacActive}, _libusbDacActive=$_libusbDacActive)',
            tag: 'Audio');
      }
    });
  }

  // ── Playback State (via AudioHandler) ──

  void _updatePlaybackState() {
    if (_audioHandler == null) return;

    final playing =
        _hiResManager.hiResActive ? _hiResManager.isPlaying : _player.playing;
    final processingState = _hiResManager.hiResActive
        ? ProcessingState.ready
        : _player.processingState;

    final effectiveState = _isSwitchingTrack
        ? AudioProcessingState.buffering
        : <ProcessingState, AudioProcessingState>{
            ProcessingState.idle: AudioProcessingState.idle,
            ProcessingState.loading: AudioProcessingState.loading,
            ProcessingState.buffering: AudioProcessingState.buffering,
            ProcessingState.ready: AudioProcessingState.ready,
            ProcessingState.completed: AudioProcessingState.completed,
          }[processingState] ?? AudioProcessingState.idle;

    (_audioHandler as AudioPlayerHandler).playbackState.add(PlaybackState(
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
      processingState: effectiveState,
      playing: playing,
      updatePosition:
          _hiResManager.hiResActive ? _hiResManager.position : _player.position,
      bufferedPosition: _hiResManager.hiResActive
          ? _hiResManager.bufferedPosition
          : _player.bufferedPosition,
      speed: _hiResManager.hiResActive ? 1.0 : _player.speed,
    ));

    if (Platform.isWindows && _smtc != null) {
      _smtc!.setPlaybackStatus(
        playing ? PlaybackStatus.Playing : PlaybackStatus.Paused,
      );
    }
  }

  Future<void> _updateMediaItem(
    AudioTrack track, {
    bool privacyEnabled = false,
    bool blurCover = true,
    bool maskTitle = true,
    String customTitle = '正在播放音频',
  }) async {
    if (_audioHandler == null) return;

    String displayTitle = track.title;
    String? displayArtworkUrl = track.artworkUrl;

    if (privacyEnabled) {
      if (maskTitle) displayTitle = customTitle;
      if (blurCover && displayArtworkUrl != null) {
        try {
          final blurredFilePath =
              await ImageBlurUtil.blurNetworkImageToFile(displayArtworkUrl);
          displayArtworkUrl = blurredFilePath;
        } catch (e) {
          _log.error('模糊封面失败: $e');
          displayArtworkUrl = null;
        }
      }
    }

    (_audioHandler as AudioPlayerHandler).mediaItem.add(MediaItem(
      id: track.id,
      album: track.album ?? '',
      title: displayTitle,
      artist: track.artist ?? '',
      duration: track.duration,
      artUri: displayArtworkUrl != null ? Uri.parse(displayArtworkUrl) : null,
    ));

    if (Platform.isWindows && _smtc != null) {
      _smtc!.updateMetadata(MusicMetadata(
        title: displayTitle,
        artist: track.artist ?? '',
        album: track.album ?? '',
        thumbnail: displayArtworkUrl,
      ));
    }

    _updatePlaybackState();
  }

  // ── Track Loading ──

  Future<void> _loadTrack(AudioTrack track, {int startPositionMs = 0}) async {
    _log.info(
        '_loadTrack: title="${track.title}" startPos=${startPositionMs}ms',
        tag: 'Audio');

    _lastSavedDacPositionMs = 0;

    _trackLoadingController.add(true);

    final useHiRes = await _hiResManager.shouldUseHiResForTrack(track);
    if (useHiRes) {
      await _updateMediaItem(
        track,
        privacyEnabled: _privacyEnabled,
        blurCover: _privacyBlurCover,
        maskTitle: _privacyMaskTitle,
        customTitle: _privacyCustomTitle,
      );
      final formatInfo = await _hiResManager.loadHiResTrack(
        track,
        startPositionMs: startPositionMs,
      );
      // null + not active = fallback (recursive _loadTrack handled it)
      if (formatInfo == null && !_hiResManager.hiResActive) {
        return;
      }
      if (formatInfo != null) {
        final rawInfo = await _detectAudioFormatDirect(track);
        final decodedInfo = AudioFormatInfo(
          codec: rawInfo?.codec ?? '',
          sampleRate: formatInfo.sampleRate,
          bitDepth: formatInfo.bitDepth,
          channels: formatInfo.channels,
        );
        _gainManager.setLastAudioFormat(decodedInfo);
        _audioFormatController.add(decodedInfo);
      }
      _isSwitchingTrack = false;
      _trackLoadingController.add(false);
      _updatePlaybackState();
      return;
    }

    if (_hiResManager.hiResActive) {
      await _hiResManager.stopHiResPlayback();
    }

    _isSwitchingTrack = true;
    _updatePlaybackState();
    if (Platform.isMacOS) _completionHandled = false;

    await _cleanupTempPlaybackFile();

    try {
      await _updateMediaItem(
        track,
        privacyEnabled: _privacyEnabled,
        blurCover: _privacyBlurCover,
        maskTitle: _privacyMaskTitle,
        customTitle: _privacyCustomTitle,
      );

      bool loaded = false;

      if (track.url.startsWith('file://')) {
        final localPath = p.normalize(track.url.substring(7));
        if (await File(localPath).exists()) {
          final isolatedPath =
              await _prepareLocalPlaybackPath(localPath) ?? localPath;
          await _player.setFilePath(isolatedPath);
          loaded = true;
        } else {
          _log.warning('本地文件不存在: $localPath', tag: 'Audio');
        }
      }

      if (!loaded && track.hash != null && track.hash!.isNotEmpty) {
        final cachedPath = await CacheService.getCachedAudioFile(track.hash!);
        if (cachedPath != null) {
          await _player.setFilePath(cachedPath);
          loaded = true;
        }
      }

      if (!loaded) await _player.setUrl(track.url);

      if (startPositionMs > 0) {
        try {
          await _player.seek(Duration(milliseconds: startPositionMs));
          _log.info(
              '_loadTrack [just_audio]: restored position ${startPositionMs}ms',
              tag: 'Audio');
        } catch (e) {
          _log.warning(
              '_loadTrack [just_audio]: seek to ${startPositionMs}ms failed: $e',
              tag: 'Audio');
        }
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
          _log.warning(
              'Failed to set audio session ID for equalizer: $e', tag: 'Audio');
        }
      }
      _gainManager.applyAudioGain(track);
    }
  }

  // ── Playback Control ──

  Future<void> play() async {
    if (_dacResumeInFlight) {
      _log.info('play() deferred — DAC re-plug in flight', tag: 'Audio');
      return;
    }
    if (_hiResManager.hiResActive) {
      await _hiResManager.hiResService.resume();
      _updatePlaybackState();
      return;
    }

    if (Platform.isMacOS &&
        (_completionCheckTimer == null || !_completionCheckTimer!.isActive)) {
      _startCompletionCheckTimer();
    }

    await _player.play();
    _updatePlaybackState();

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

  Future<void> pause() async {
    _crossfadeManager.cancel();
    if (_dacResumeInFlight) {
      _log.info('pause() deferred — DAC re-plug in flight', tag: 'Audio');
      return;
    }
    if (_hiResManager.hiResActive) {
      await _hiResManager.hiResService.pause();
      _updatePlaybackState();
      return;
    }
    await _player.pause();
    _updatePlaybackState();
  }

  Future<void> stop() async {
    _crossfadeManager.cancel();
    if (_hiResManager.hiResActive) {
      await _hiResManager.stopHiResPlayback();
      await _player.stop();
      _updatePlaybackState();
      return;
    }
    await _player.stop();
    _updatePlaybackState();
  }

  Future<void> seek(Duration position) async {
    _crossfadeManager.cancel();
    if (_hiResManager.hiResActive) {
      await _hiResManager.hiResService.seekTo(position.inMilliseconds);
      _unifiedPositionController.add(position);
      _updatePlaybackState();
      return;
    }
    if (Platform.isMacOS) _completionHandled = false;
    await _player.seek(position);
    _unifiedPositionController.add(position);
    _updatePlaybackState();
  }

  Future<void> seekForward(Duration duration) async {
    final current =
        _hiResManager.hiResActive ? _hiResManager.position : _player.position;
    final total =
        _hiResManager.hiResActive ? _hiResManager.duration : _player.duration;
    if (total != null) {
      final newPos = current + duration;
      await seek(newPos > total ? total : newPos);
    }
  }

  Future<void> seekBackward(Duration duration) async {
    final current =
        _hiResManager.hiResActive ? _hiResManager.position : _player.position;
    final newPos = current - duration;
    await seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  // ── Track Completion ──

  Future<void> _handleTrackCompletion() async {
    if (_crossfadeManager.isCrossfading) return;

    if (_queueManager.appLoopMode == LoopMode.one) {
      if (Platform.isMacOS) _completionHandled = false;
      seek(Duration.zero);
      play();
      return;
    }

    final next = await _queueManager.handleCompletion();
    if (next) {
      if (_crossfadeManager.crossfadeDuration > Duration.zero &&
          !_hiResManager.hiResActive) {
        await _crossfadeManager.fadeIn();
      }
    } else {
      if (_crossfadeManager.crossfadeDuration > Duration.zero &&
          !_hiResManager.hiResActive) {
        await _crossfadeManager.fadeOut();
      }
      pause();
      await _player.setVolume(_gainManager.userBaseVolume);
    }
  }

  // ── Audio Format Detection ──

  Future<void> _detectAudioFormat(AudioTrack track) async {
    final info = await _detectAudioFormatDirect(track);
    _gainManager.setLastAudioFormat(info);
    _audioFormatController.add(info);
  }

  Future<AudioFormatInfo?> _detectAudioFormatDirect(AudioTrack track) async {
    return AudioFormatGainService.detectFormatDirect(track);
  }

  // ── Queue Operations (delegate to manager) ──

  Future<void> updateQueue(List<AudioTrack> tracks, {int startIndex = 0}) async {
    await _queueManager.updateQueue(tracks, startIndex: startIndex);
  }

  Future<void> skipToNext() async {
    _crossfadeManager.cancel();
    _hiResManager.cancelNativeSubs();

    if (_crossfadeManager.crossfadeDuration > Duration.zero) {
      await _crossfadeManager.crossfadeTo(() async {
        await _queueManager.skipToNext();
      });
    } else {
      await _queueManager.skipToNext();
    }
  }

  Future<void> skipToPrevious() async {
    _crossfadeManager.cancel();
    _hiResManager.cancelNativeSubs();

    if (_crossfadeManager.crossfadeDuration > Duration.zero) {
      await _crossfadeManager.crossfadeTo(() async {
        await _queueManager.skipToPrevious();
      });
    } else {
      await _queueManager.skipToPrevious();
    }
  }

  Future<void> skipToIndex(int index) async {
    _crossfadeManager.cancel();
    _hiResManager.cancelNativeSubs();

    if (_crossfadeManager.crossfadeDuration > Duration.zero && currentTrack != null) {
      await _crossfadeManager.crossfadeTo(() async {
        await _queueManager.skipToIndex(index);
      });
    } else {
      await _queueManager.skipToIndex(index);
    }
  }

  Future<void> removeTrackAt(int index) async {
    await _queueManager.removeTrackAt(index);
  }

  Future<void> clearQueue() async {
    _crossfadeManager.cancel();
    if (_hiResManager.hiResActive) {
      _hiResManager.cancelNativeSubs();
      await _hiResManager.hiResService.stop();
    }
    await _queueManager.clearQueue();
    await stop();
  }

  Future<void> moveTrack(int oldIndex, int newIndex) async {
    await _queueManager.moveTrack(oldIndex, newIndex);
  }

  Future<void> insertTracksAfterCurrent(List<AudioTrack> tracks) async {
    _crossfadeManager.cancel();
    await _queueManager.insertTracksAfterCurrent(tracks);
  }

  Future<Map<String, int>> appendTracks(List<AudioTrack> tracks) async {
    return _queueManager.appendTracks(tracks);
  }

  // ── Crossfade ──

  Future<void> setCrossfadeDuration(Duration duration) async {
    await _crossfadeManager.setCrossfadeDuration(duration);
  }

  // ── Audio Gain ──

  ReplayGainData? get currentReplayGain => _gainManager.currentReplayGain;
  double get currentVolumeNormalizationMultiplier =>
      _gainManager.currentVolumeNormalizationMultiplier;
  bool get replayGainActive => _gainManager.replayGainActive;
  bool get volumeNormalizationActive => _gainManager.volumeNormalizationActive;

  Future<void> reapplyAudioGain() async {
    if (_hiResManager.hiResActive) return;
    await _gainManager.reapplyAudioGain();
  }

  Future<void> setVolume(double volume) async {
    if (_exclusiveModeEnabled) {
      await _gainManager.setDirectVolume(1.0);
      return;
    }
    await _gainManager.setVolume(volume);
  }

  Future<void> setSpeed(double speed) async {
    await _gainManager.setSpeed(speed);
  }

  // ── Exclusive Mode ──

  Future<void> setExclusiveMode(bool enabled) async {
    if (Platform.isAndroid) {
      if (enabled) {
        final success = await _exclusiveService.enable();
        _exclusiveModeEnabled = success;
        if (success) {
          await _hiResManager.hiResService.setUseAaudioSink(true);
          await _hiResManager.hiResService.setBitPerfectMode(true);
          await _gainManager.setDirectVolume(1.0);

          _log.info(
              '[LIBUSB] Exclusive Mode ON — '
              'initiating libusb USB DAC (jika ada perangkat fisik)',
              tag: 'Audio');
          await _usbDacManager.setAutoDacEnabled(true);
          _autoEnabledLibusb = true;
        }
      } else {
        await _exclusiveService.disable();
        _exclusiveModeEnabled = false;
        await _hiResManager.hiResService.setUseAaudioSink(false);
        await _hiResManager.hiResService.setBitPerfectMode(false);

        if (_autoEnabledLibusb) {
          _log.info(
              '[LIBUSB] Exclusive Mode OFF — disabling auto-enabled USB DAC Routing',
              tag: 'Audio');
          await _usbDacManager.setAutoDacEnabled(false);
          _autoEnabledLibusb = false;
        }
      }
    } else if (Platform.isWindows || Platform.isMacOS) {
      _exclusiveModeEnabled = enabled;
      await MpvConfigService.configure();
      if (enabled) await _gainManager.setDirectVolume(1.0);
    }
  }

  bool get exclusiveModeEnabled => _exclusiveModeEnabled;

  void setHiResEnabled(bool enabled) {
    _hiResManager.setHiResEnabled(enabled && Platform.isAndroid);
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    await _queueManager.setRepeatMode(mode);
    await _player.setLoopMode(LoopMode.off);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  // ── Privacy ──

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
    if (currentTrack != null) {
      await _updateMediaItem(currentTrack!,
          privacyEnabled: enabled,
          blurCover: blurCover,
          maskTitle: maskTitle,
          customTitle: customTitle);
    }
  }

  AudioHandler? get audioHandler => _audioHandler;

  // ── Convenience Getters (from managers) ──

  bool get libusbDacActive => _libusbDacActive;
  UsbDacAudioManager get usbDacManager => _usbDacManager;

  AudioFormatInfo? get lastAudioFormat => _gainManager.lastAudioFormat;

  Duration get position =>
      _hiResManager.hiResActive ? _hiResManager.position : _player.position;
  Duration? get duration =>
      _hiResManager.hiResActive ? _hiResManager.duration : _player.duration;
  Duration get bufferedPosition => _hiResManager.hiResActive
      ? _hiResManager.bufferedPosition
      : _player.bufferedPosition;
  bool get playing =>
      _hiResManager.hiResActive ? _hiResManager.isPlaying : _player.playing;
  PlayerState get playerState => _hiResManager.hiResActive
      ? _hiResManager.playerState
      : _player.playerState;

  AudioTrack? get currentTrack => _queueManager.currentTrack;
  List<AudioTrack> get queue => _queueManager.queue;
  int get currentIndex => _queueManager.currentIndex;
  bool get hiResActive => _hiResManager.hiResActive;
  Stream<bool> get hiResActiveStream => _hiResManager.hiResActiveStream;
  bool get hasNext => _queueManager.hasNext;
  bool get hasPrevious => _queueManager.hasPrevious;

  // ── Streams ──

  Stream<PlayerState> get playerStateStream =>
      _unifiedPlayerStateController.stream;
  Stream<Duration> get positionStream => _unifiedPositionController.stream;
  Stream<Duration?> get durationStream => _unifiedDurationController.stream;
  Stream<List<AudioTrack>> get queueStream => _queueManager.queueStream;
  Stream<AudioTrack?> get currentTrackStream =>
      _queueManager.currentTrackStream;
  Stream<bool> get trackLoadingStream => _trackLoadingController.stream;
  Stream<AudioFormatInfo?> get audioFormatStream =>
      _audioFormatController.stream;

  // ── Platform-Specific ──

  Future<void> updateAudioSessionConfig(bool enablePassthrough) async {
    if (Platform.isWindows || Platform.isMacOS) {
      await MpvConfigService.configure();
      return;
    }
    if (Platform.isLinux) return;
    if (!Platform.isAndroid && !Platform.isIOS) return;

    try {
      final session = await AudioSession.instance;
      await session.configure(enablePassthrough
          ? const AudioSessionConfiguration(
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
            )
          : const AudioSessionConfiguration(
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
    } catch (e) {
      _log.error('Error updating AudioSession: $e', tag: 'AudioPlayerService');
    }
  }

  // ── macOS Completion Check ──

  void _startCompletionCheckTimer() {
    if (!Platform.isMacOS) return;
    _completionCheckTimer?.cancel();
    _completionCheckTimer =
        Timer.periodic(const Duration(milliseconds: 500), (timer) {
      if (_player.playing && !_completionHandled) {
        if (_player.processingState == ProcessingState.completed) {
          _completionHandled = true;
          _handleTrackCompletion();
        } else if (_player.duration != null &&
            _player.duration! > Duration.zero &&
            _player.position >=
                _player.duration! - const Duration(milliseconds: 50)) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
    });
  }

  // ── Temp File Management ──

  Future<void> _cleanupTempPlaybackFile() async {
    if (_tempPlaybackFilePath == null) return;
    try {
      final f = File(_tempPlaybackFilePath!);
      if (await f.exists()) await f.delete();
    } catch (e) {
      _log.error('删除临时音频文件失败: $e', tag: 'Audio');
    } finally {
      _tempPlaybackFilePath = null;
    }
  }

  Future<String?> _prepareLocalPlaybackPath(String originalPath) async {
    final shouldInspect = [
      '.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.mp3'
    ].any((ext) => originalPath.toLowerCase().endsWith(ext));
    if (!shouldInspect) return null;

    final file = File(originalPath);
    final dir = file.parent;
    final baseName = p.basenameWithoutExtension(originalPath);
    final ext = p.extension(originalPath);
    final hasNonAscii = baseName.codeUnits.any((c) => c > 127);

    bool hasLyric = false;
    for (final lrc in _lyricExtensions) {
      if (await File(p.join(dir.path, '$baseName$lrc')).exists()) {
        hasLyric = true;
        break;
      }
    }

    if (hasNonAscii || hasLyric) {
      final tempDir = await _getTempAudioDirectory();
      final hash = originalPath.hashCode.abs().toRadixString(16);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final copyPath = p.join(tempDir.path, 'audio_${ts}_$hash$ext');
      try {
        await file.copy(copyPath);
        _tempPlaybackFilePath = copyPath;
        return copyPath;
      } catch (e) {
        _log.error('复制文件失败: $e', tag: 'Audio');
        return null;
      }
    }
    return null;
  }

  Future<Directory> _getTempAudioDirectory() async {
    if (_tempAudioDirectory != null) return _tempAudioDirectory!;
    final dir = Directory(
        p.join(Directory.systemTemp.path, 'kikoflu_audio_temp'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _tempAudioDirectory = dir;
    return dir;
  }

  // ── Dispose ──

  Future<void> dispose() async {
    _crossfadeManager.cancel();
    _completionCheckTimer?.cancel();
    _smtcSubscription?.cancel();
    _smtcSubscription = null;
    _justAudioPositionSub?.cancel();
    _justAudioDurationSub?.cancel();
    _libusbStateSub?.cancel();
    _libusbStateSub = null;
    await _hiResManager.stopHiResPlayback();
    await _cleanupTempPlaybackFile();
    _hiResManager.dispose();
    _queueManager.dispose();
    await _unifiedPositionController.close();
    await _unifiedDurationController.close();
    await _unifiedPlayerStateController.close();
    await _trackLoadingController.close();
    await _audioFormatController.close();
    await _player.dispose();
  }
}
