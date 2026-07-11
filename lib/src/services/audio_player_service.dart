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
import 'hi_res_audio_service.dart';
import 'exclusive_audio_service.dart';
import 'usb_dac_audio_manager.dart';
import 'mpv_config_service.dart';
import 'replay_gain_service.dart';
import 'volume_normalization_service.dart';
import 'log_service.dart';
import 'audio_player_handler.dart';

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
  LoopMode _appLoopMode = LoopMode.off;
  String? _tempPlaybackFilePath;
  Directory? _tempAudioDirectory;
  bool _isSwitchingTrack = false;

  static const List<String> _lyricExtensions = [
    '.lrc', '.srt', '.vtt', '.ass', '.ssa',
  ];

  bool _completionHandled = false;
  Timer? _completionCheckTimer;
  DateTime _lastStateUpdate = DateTime(2000);

  SMTCWindows? _smtc;
  StreamSubscription? _smtcSubscription;

  bool _privacyEnabled = false;
  bool _privacyBlurCover = true;
  bool _privacyMaskTitle = true;
  String _privacyCustomTitle = '正在播放音频';

  Duration _crossfadeDuration = Duration.zero;
  double _originalVolume = 1.0;
  bool _isCrossfading = false;
  bool _crossfadeCancelled = false;

  final ReplayGainService _replayGainService = ReplayGainService.instance;
  final VolumeNormalizationService _volumeNormalizationService =
      VolumeNormalizationService.instance;
  double _userBaseVolume = 1.0;

  AudioFormatInfo? _lastAudioFormat;
  AudioFormatInfo? get lastAudioFormat => _lastAudioFormat;

  final ExclusiveAudioService _exclusiveService = ExclusiveAudioService.instance;
  bool _exclusiveModeEnabled = false;

  final UsbDacAudioManager _usbDacManager = UsbDacAudioManager.instance;
  bool _libusbDacActive = false;
  StreamSubscription<UsbDacManagerState>? _libusbStateSub;

  /// Whether libusb was auto-enabled by Exclusive Mode (vs user-enable via USB DAC Routing).
  /// Used to avoid disabling USB DAC Routing when Exclusive Mode is toggled off.
  bool _autoEnabledLibusb = false;

  /// Whether the libusb USB DAC is actively streaming bit-perfect audio.
  bool get libusbDacActive => _libusbDacActive;

  /// Whether ANY bit-perfect path is active (AAudio exclusive OR libusb).
  bool get _anyBitPerfectActive => _exclusiveModeEnabled || _libusbDacActive;

  /// The USB DAC manager — exposed for sink-selection logging.
  UsbDacAudioManager get usbDacManager => _usbDacManager;

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
  StreamSubscription? _hiResErrorSub;
  StreamSubscription<int>? _nativePositionSub;
  StreamSubscription<int>? _nativeDurationSub;
  StreamSubscription<int>? _nativeBufferedPositionSub;
  StreamSubscription<bool>? _trackEndedSub;

  final StreamController<Duration> _unifiedPositionController =
      StreamController<Duration>.broadcast();
  final StreamController<Duration?> _unifiedDurationController =
      StreamController<Duration?>.broadcast();
  final StreamController<PlayerState> _unifiedPlayerStateController =
      StreamController<PlayerState>.broadcast();
  StreamSubscription<Duration>? _justAudioPositionSub;
  StreamSubscription<Duration?>? _justAudioDurationSub;

  final StreamController<List<AudioTrack>> _queueController =
      StreamController.broadcast();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController.broadcast();
  final StreamController<bool> _trackLoadingController =
      StreamController<bool>.broadcast();
  final StreamController<AudioFormatInfo?> _audioFormatController =
      StreamController<AudioFormatInfo?>.broadcast();

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
    if (_hiResEnabled) {
      _log.info('[AudioPlayerService] Hi-Res ExoPlayer enabled on Android — ALAC/FLAC/WAV will use FFmpeg decoder');
    }

    _updatePlaybackState();

    if (Platform.isWindows) {
      try {
        _smtc = SMTCWindows(
          config: const SMTCConfig(
            fastForwardEnabled: false, nextEnabled: true,
            pauseEnabled: true, playEnabled: true,
            rewindEnabled: false, prevEnabled: true,
            stopEnabled: true,
          ),
        );
        _smtcSubscription = _smtc!.buttonPressStream.listen((button) {
          if (_instance == null) return;
          switch (button) {
            case PressedButton.play: play();
            case PressedButton.pause: pause();
            case PressedButton.next: skipToNext();
            case PressedButton.previous: skipToPrevious();
            case PressedButton.stop: stop();
            default: break;
          }
        });
        _smtc!.enableSmtc();
      } catch (e) {
        _log.error('[AudioPlayerService] Failed to initialize SMTC: $e');
      }
    }

    _setupPlayerListeners();

    _libusbStateSub = _usbDacManager.stateStream.listen((state) async {
      final wasActive = _libusbDacActive;
      _libusbDacActive = state.dacActive;

      _log.info('[LIBUSB] stateStream: '
          'dacConnected=${state.dacConnected}, '
          'dacActive=${state.dacActive}, '
          'wasActive=$wasActive, '
          'autoDacEnabled=${state.autoDacEnabled}, '
          'device="${state.deviceName}"',
          tag: 'Audio');

      if (state.dacActive && !wasActive) {
        _log.info('[LIBUSB] >>> dacActive transitioned false→true — switching to LibusbAudioSink',
            tag: 'Audio');

        await _hiResService.setUseAaudioSink(false);
        await _hiResService.setUseLibusbSink(true);
        await _hiResService.setBitPerfectMode(true);

        if (_player.playing || _hiResActive) {
          final track = currentTrack;
          if (track != null) {
            _log.info('[LIBUSB] Playback active — restarting track through libusb', tag: 'Audio');
            await _loadTrack(track);
            await play();
          }
        }
      } else if (state.dacConnected && !state.dacActive && wasActive) {
        _log.info('[LIBUSB] dacActive transitioned true→false — disabling libusb sink', tag: 'Audio');
        await _hiResService.setUseLibusbSink(false);
      } else if (!state.dacConnected && wasActive) {
        _log.info('[LIBUSB] DAC disconnected — falling back to default/AAudio', tag: 'Audio');
        await _hiResService.setUseLibusbSink(false);
        if (_exclusiveModeEnabled) {
          await _hiResService.setUseAaudioSink(true);
        }
      } else if (state.dacConnected) {
        _log.info('[LIBUSB] DAC connected but idle (dacActive=${state.dacActive}, _libusbDacActive=$_libusbDacActive)',
            tag: 'Audio');
      }
    });
  }

  void _setupPlayerListeners() {
    _player.playerStateStream.listen((state) {
      if (!_hiResActive) {
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
      if (!_hiResActive) {
        _unifiedPositionController.add(position);
      }
      final now = DateTime.now();
      if (now.difference(_lastStateUpdate) >= const Duration(seconds: 1)) {
        _lastStateUpdate = now;
        _updatePlaybackState();
      }
    });

    _justAudioDurationSub = _player.durationStream.listen((duration) {
      if (!_hiResActive) {
        _unifiedDurationController.add(duration);
      }
    });

    if (Platform.isMacOS) _startCompletionCheckTimer();
  }

  void _updatePlaybackState() {
    if (_audioHandler == null) return;

    final playing = _hiResActive ? _hiResService.isPlaying : _player.playing;
    final processingState = _hiResActive
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
        MediaAction.seek, MediaAction.seekForward, MediaAction.seekBackward,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: effectiveState,
      playing: playing,
      updatePosition: _hiResActive ? _lastHiResPosition : _player.position,
      bufferedPosition:
          _hiResActive ? _lastHiResBufferedPosition : _player.bufferedPosition,
      speed: _hiResActive ? 1.0 : _player.speed,
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

  Future<void> _loadTrack(AudioTrack track) async {
    _log.info('_loadTrack: title="${track.title}"', tag: 'Audio');

    _currentTrackController.add(track);
    _trackLoadingController.add(true);

    final useHiRes = await _shouldUseHiResForTrack(track);
    if (useHiRes) {
      await _loadHiResTrack(track);
      return;
    }

    if (_hiResActive) await _stopHiResPlayback();

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
      _applyAudioGain(track);
    }
  }

  Future<bool> _shouldUseHiResForTrack(AudioTrack track) async {
    if (!_hiResEnabled) return false;
    if (_hiResService.isUsbRouted) return true;

    final formatInfo = await _detectAudioFormatDirect(track);
    if (formatInfo == null) return false;

    final codec = formatInfo.codec.toUpperCase();
    if (codec == 'FLAC' || codec == 'WAV' || codec == 'M4A') return true;
    if (formatInfo.sampleRate != null) return formatInfo.sampleRate! > 48000;
    return false;
  }

  Future<void> _loadHiResTrack(AudioTrack track) async {
    _log.info('_loadHiResTrack: title="${track.title}"', tag: 'Audio');

    await _stopHiResPlayback();
    _hiResActive = true;
    _hiResActiveController.add(true);

    await _updateMediaItem(
      track,
      privacyEnabled: _privacyEnabled,
      blurCover: _privacyBlurCover,
      maskTitle: _privacyMaskTitle,
      customTitle: _privacyCustomTitle,
    );

    final formatInfo = await _detectAudioFormatDirect(track);
    _audioFormatController.add(formatInfo);

    String playUrl = track.url;
    if (playUrl.startsWith('file://')) {
      playUrl = playUrl.substring(7).replaceAll('/', Platform.isWindows ? '\\' : '/');
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
      final savedEnabled = _hiResEnabled;
      _hiResEnabled = false;
      await _loadTrack(track);
      _hiResEnabled = savedEnabled;
      return;
    }

    _nativePositionSub?.cancel();
    _nativePositionSub = _hiResService.nativePositionStream.listen((posMs) {
      if (!_hiResActive) return;
      _lastHiResPosition = Duration(milliseconds: posMs);
      _unifiedPositionController.add(_lastHiResPosition);
    });

    _nativeDurationSub?.cancel();
    _nativeDurationSub = _hiResService.nativeDurationStream.listen((durMs) {
      if (!_hiResActive) return;
      if (durMs > 0) {
        _lastHiResDuration = Duration(milliseconds: durMs);
        _unifiedDurationController.add(_lastHiResDuration);
      }
    });

    _nativeBufferedPositionSub?.cancel();
    _nativeBufferedPositionSub =
        _hiResService.nativeBufferedPositionStream.listen((bufPosMs) {
      if (!_hiResActive) return;
      _lastHiResBufferedPosition = Duration(milliseconds: bufPosMs);
    });

    _hiResPlaybackSub?.cancel();
    _hiResPlaybackSub = _hiResService.playbackStateStream.listen((isPlaying) {
      if (!_hiResActive) return;
      _unifiedPlayerStateController.add(PlayerState(isPlaying, ProcessingState.ready));
      _updatePlaybackState();
    });

    _trackEndedSub?.cancel();
    _trackEndedSub = _hiResService.trackEndedStream.listen((_) {
      if (!_hiResActive) return;
      _handleTrackCompletion();
    });

    _hiResBufferingSub?.cancel();
    _hiResBufferingSub = _hiResService.bufferingStream.listen((buffering) {
      if (!_hiResActive) return;
      _unifiedPlayerStateController.add(PlayerState(
        _hiResService.isPlaying,
        buffering ? ProcessingState.buffering : ProcessingState.ready,
      ));
    });

    _hiResErrorSub?.cancel();
    _hiResErrorSub = _hiResService.errorStream.listen((message) {
      if (!_hiResActive) return;
      _log.error('[HiRes] Player error: $message', tag: 'Audio');
      _hiResActive = false;
      _hiResActiveController.add(false);
      final savedEnabled = _hiResEnabled;
      _hiResEnabled = false;
      _loadTrack(track).then((_) {
        _hiResEnabled = savedEnabled;
      });
    });

    _isSwitchingTrack = false;
    _trackLoadingController.add(false);
    _updatePlaybackState();
  }

  Future<void> _stopHiResPlayback() async {
    _nativePositionSub?.cancel(); _nativePositionSub = null;
    _nativeDurationSub?.cancel(); _nativeDurationSub = null;
    _nativeBufferedPositionSub?.cancel(); _nativeBufferedPositionSub = null;
    _hiResPlaybackSub?.cancel(); _hiResPlaybackSub = null;
    _hiResBufferingSub?.cancel(); _hiResBufferingSub = null;
    _hiResErrorSub?.cancel(); _hiResErrorSub = null;
    _trackEndedSub?.cancel(); _trackEndedSub = null;

    if (_hiResActive) {
      await _hiResService.stop();
      _hiResActive = false;
      _hiResActiveController.add(false);
      _lastHiResPosition = Duration.zero;
      _lastHiResDuration = null;
      _lastHiResBufferedPosition = Duration.zero;
      _unifiedPositionController.add(Duration.zero);
      _unifiedDurationController.add(null);
    }
  }

  Future<void> _detectAudioFormat(AudioTrack track) async {
    final info = await _detectAudioFormatDirect(track);
    _lastAudioFormat = info;
    _audioFormatController.add(info);
  }

  Future<AudioFormatInfo?> _detectAudioFormatDirect(AudioTrack track) async {
    return AudioFormatGainService.detectFormatDirect(track);
  }

  Future<void> play() async {
    if (_hiResActive) {
      await _hiResService.resume();
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
      await _stopHiResPlayback();
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
      _unifiedPositionController.add(_lastHiResPosition);
      _updatePlaybackState();
      return;
    }
    if (Platform.isMacOS) _completionHandled = false;
    await _player.seek(position);
    _unifiedPositionController.add(position);
    _updatePlaybackState();
  }

  Future<void> seekForward(Duration duration) async {
    final current = _hiResActive ? _lastHiResPosition : _player.position;
    final total = _hiResActive ? _lastHiResDuration : _player.duration;
    if (total != null) {
      final newPos = current + duration;
      await seek(newPos > total ? total : newPos);
    }
  }

  Future<void> seekBackward(Duration duration) async {
    final current = _hiResActive ? _lastHiResPosition : _player.position;
    final newPos = current - duration;
    await seek(newPos < Duration.zero ? Duration.zero : newPos);
  }

  Future<void> updateQueue(List<AudioTrack> tracks, {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    _queueController.add(List.from(_queue));
    if (tracks.isNotEmpty && _currentIndex < tracks.length) {
      await _loadTrack(tracks[_currentIndex]);
    }
  }

  Future<void> skipToNext() async {
    _cancelCrossfade();
    _cancelHiResNativeSubs();
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
    _cancelHiResNativeSubs();
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
    _cancelHiResNativeSubs();
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
        ? _queue[_currentIndex].id : null;

    _queue.removeAt(index);
    _queueController.add(List.from(_queue));

    if (_queue.isEmpty) {
      _currentIndex = 0;
      await stop();
      _currentTrackController.add(null);
      return;
    }

    if (wasCurrent) {
      if (_currentIndex >= _queue.length) _currentIndex = _queue.length - 1;
      await _loadTrack(_queue[_currentIndex]);
      await play();
      return;
    }

    if (currentTrackId != null) {
      final updatedIndex = _queue.indexWhere((track) => track.id == currentTrackId);
      if (updatedIndex != -1) _currentIndex = updatedIndex;
    }
  }

  Future<void> clearQueue() async {
    _cancelCrossfade();
    if (_hiResActive) {
      _cancelHiResNativeSubs();
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
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final currentTrackId = (_queue.isNotEmpty && _currentIndex < _queue.length)
        ? _queue[_currentIndex].id : null;

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    if (currentTrackId != null) {
      final updatedIndex = _queue.indexWhere((element) => element.id == currentTrackId);
      if (updatedIndex != -1) _currentIndex = updatedIndex;
    }
    _queueController.add(List.from(_queue));
  }

  Future<void> insertTracksAfterCurrent(List<AudioTrack> tracks) async {
    _cancelCrossfade();
    if (tracks.isEmpty) return;

    final existingIds = _queue.map((t) => t.id).toSet();
    final newTracks = tracks.where((t) => !existingIds.contains(t.id)).toList();

    if (newTracks.isEmpty) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
        _currentIndex++;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
      return;
    }

    if (_queue.isEmpty) {
      await updateQueue(newTracks, startIndex: 0);
      await play();
      return;
    }

    if (_currentIndex >= _queue.length - 1) {
      final indexMap = await appendTracks(newTracks);
      final firstNew = newTracks.first;
      final targetIdx = indexMap[firstNew.id];
      if (targetIdx != null) {
        _currentIndex = targetIdx;
        await _loadTrack(_queue[_currentIndex]);
        await play();
      }
      return;
    }

    final insertPos = _currentIndex + 1;
    _queue.insertAll(insertPos, newTracks);
    _queueController.add(List.from(_queue));
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

    final existingIdx = <String, int>{};
    for (var i = 0; i < _queue.length; i++) {
      existingIdx[_queue[i].id] = i;
    }

    bool appended = false;
    for (final track in tracks) {
      final existing = existingIdx[track.id];
      if (existing != null) { indexMap[track.id] = existing; continue; }
      _queue.add(track);
      indexMap[track.id] = _queue.length - 1;
      appended = true;
    }

    if (appended) _queueController.add(List.from(_queue));

    for (final track in tracks) {
      indexMap[track.id] ??= existingIdx[track.id] ??
          _queue.indexWhere((e) => e.id == track.id);
    }
    return indexMap;
  }

  /// Cancel hi-res native subscriptions (position, duration, buffered).
  void _cancelHiResNativeSubs() {
    _nativePositionSub?.cancel(); _nativePositionSub = null;
    _nativeDurationSub?.cancel(); _nativeDurationSub = null;
    _nativeBufferedPositionSub?.cancel(); _nativeBufferedPositionSub = null;
  }

  Future<void> setCrossfadeDuration(Duration duration) async {
    _crossfadeDuration = duration;
    _log.info('Crossfade duration set to: ${duration.inMilliseconds}ms', tag: 'Audio');
  }

  Future<void> _fadeOut() async {
    if (_crossfadeDuration <= Duration.zero || _crossfadeCancelled) return;
    _crossfadeCancelled = false;
    _isCrossfading = true;
    _originalVolume = _player.volume;

    final steps = (_crossfadeDuration.inMilliseconds / 50).round().clamp(1, 100);
    final stepMs = (_crossfadeDuration.inMilliseconds / steps).round().clamp(10, 100);
    final volStep = _originalVolume / steps;

    for (int i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepMs));
      if (_crossfadeCancelled) return;
      await _player.setVolume((_originalVolume - volStep * i).clamp(0.0, _originalVolume));
    }
    if (!_crossfadeCancelled) await _player.setVolume(0.0);
  }

  Future<void> _fadeIn() async {
    if (_crossfadeDuration <= Duration.zero || _crossfadeCancelled) {
      _isCrossfading = false; return;
    }
    _crossfadeCancelled = false;

    final steps = (_crossfadeDuration.inMilliseconds / 50).round().clamp(1, 100);
    final stepMs = (_crossfadeDuration.inMilliseconds / steps).round().clamp(10, 100);
    final volStep = _originalVolume / steps;

    await _player.setVolume(0.0);
    for (int i = 1; i <= steps; i++) {
      await Future.delayed(Duration(milliseconds: stepMs));
      if (_crossfadeCancelled) return;
      await _player.setVolume((volStep * i).clamp(0.0, _originalVolume));
    }
    if (!_crossfadeCancelled) await _player.setVolume(_originalVolume);
    _isCrossfading = false;
  }

  Future<void> _crossfadeTo(int nextIndex) async {
    if (_queue.isEmpty || nextIndex < 0 || nextIndex >= _queue.length) return;
    _currentIndex = nextIndex;
    if (_crossfadeDuration > Duration.zero) {
      await _fadeOut();
      if (_crossfadeCancelled) return;
    }
    await _loadTrack(_queue[_currentIndex]);
    await play();
    if (_crossfadeDuration > Duration.zero) await _fadeIn();
  }

  void _cancelCrossfade() {
    if (_isCrossfading) {
      _crossfadeCancelled = true;
      _player.setVolume(_originalVolume);
      _isCrossfading = false;
    }
  }

  Future<void> _handleTrackCompletion() async {
    if (_isCrossfading) return;

    if (_appLoopMode == LoopMode.one) {
      if (Platform.isMacOS) _completionHandled = false;
      seek(Duration.zero);
      play();
    } else if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      await _loadTrack(_queue[_currentIndex]);
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false; _isCrossfading = true;
        _originalVolume = _player.volume;
        await play(); await _fadeIn();
      } else {
        await play();
      }
    } else if (_appLoopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      await _loadTrack(_queue[0]);
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false; _isCrossfading = true;
        _originalVolume = _player.volume;
        await play(); await _fadeIn();
      } else {
        await play();
      }
    } else {
      if (_crossfadeDuration > Duration.zero && !_hiResActive) {
        _crossfadeCancelled = false; _isCrossfading = true;
        _originalVolume = _player.volume;
        await _fadeOut();
        if (!_crossfadeCancelled) { pause(); _player.setVolume(_originalVolume); }
        _isCrossfading = false;
      } else {
        pause();
      }
    }
  }

  ReplayGainData? get currentReplayGain => _replayGainService.currentGain;
  double get currentVolumeNormalizationMultiplier =>
      _volumeNormalizationService.currentMultiplier;
  bool get replayGainActive =>
      _replayGainService.enabled && _replayGainService.currentGain != null;
  bool get volumeNormalizationActive => _volumeNormalizationService.enabled;

  Future<void> reapplyAudioGain() async {
    if (_hiResActive) return;
    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) return;
    await setVolume(_userBaseVolume);
  }

  Future<void> setVolume(double volume) async {
    _userBaseVolume = volume.clamp(0.0, 1.0);
    if (_exclusiveModeEnabled) {
      await _player.setVolume(1.0);
      return;
    }
    final effective = (_userBaseVolume * _calculateGainMultiplier()).clamp(0.0, 1.0);
    await _player.setVolume(effective);
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  double _calculateGainMultiplier() {
    if (_exclusiveModeEnabled) return 1.0;
    double m = 1.0;
    if (_replayGainService.enabled) m *= _replayGainService.effectiveVolumeMultiplier;
    if (_volumeNormalizationService.enabled) m *= _volumeNormalizationService.currentMultiplier;
    return m;
  }

  Future<void> _applyAudioGain(AudioTrack track) async {
    if (_exclusiveModeEnabled) return;
    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) return;

    try {
      String? filePath;
      if (track.url.startsWith('file://')) {
        filePath = track.url.substring(7);
      } else if (track.hash != null && track.hash!.isNotEmpty) {
        filePath = await CacheService.getCachedAudioFile(track.hash!);
      }

      ReplayGainData? gainData;
      if (_replayGainService.enabled && filePath != null) {
        gainData = await AudioFormatGainService.analyzeGain(filePath);
        _replayGainService.setCurrentGain(gainData);
      } else {
        _replayGainService.setCurrentGain(null);
      }

      if (_volumeNormalizationService.enabled) {
        await _volumeNormalizationService.calculateMultiplier(
          filePath,
          bitDepth: _lastAudioFormat?.bitDepth,
          replayGainPeak: gainData?.trackPeak,
        );
      }

      await setVolume(_userBaseVolume);
    } catch (e) {
      _log.error('Error applying gain: $e', tag: 'AudioGain');
    }
  }

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
              avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
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
              avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.duckOthers,
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

  Future<void> setExclusiveMode(bool enabled) async {
    if (Platform.isAndroid) {
      if (enabled) {
        final success = await _exclusiveService.enable();
        _exclusiveModeEnabled = success;
        if (success) {
          await _hiResService.setUseAaudioSink(true);
          await _hiResService.setBitPerfectMode(true);
          await _player.setVolume(1.0);

          _log.info('[LIBUSB] Exclusive Mode ON — '
              'initiating libusb USB DAC (jika ada perangkat fisik)',
              tag: 'Audio');
          await _usbDacManager.setAutoDacEnabled(true);
          _autoEnabledLibusb = true;
        }
      } else {
        await _exclusiveService.disable();
        _exclusiveModeEnabled = false;
        await _hiResService.setUseAaudioSink(false);
        await _hiResService.setBitPerfectMode(false);

        if (_autoEnabledLibusb) {
          _log.info('[LIBUSB] Exclusive Mode OFF — disabling auto-enabled USB DAC Routing',
              tag: 'Audio');
          await _usbDacManager.setAutoDacEnabled(false);
          _autoEnabledLibusb = false;
        }
      }
    } else if (Platform.isWindows || Platform.isMacOS) {
      _exclusiveModeEnabled = enabled;
      await MpvConfigService.configure();
      if (enabled) await _player.setVolume(1.0);
    } else {
      return;
    }
  }

  bool get exclusiveModeEnabled => _exclusiveModeEnabled;

  void setHiResEnabled(bool enabled) {
    _hiResEnabled = enabled && Platform.isAndroid;
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    _appLoopMode = mode;
    await _player.setLoopMode(LoopMode.off);
  }

  Future<void> setShuffleMode(bool enabled) async {
    await _player.setShuffleModeEnabled(enabled);
  }

  Future<void> updatePrivacySettings({
    required bool enabled, required bool blurCover,
    required bool maskTitle, required String customTitle,
  }) async {
    _privacyEnabled = enabled;
    _privacyBlurCover = blurCover;
    _privacyMaskTitle = maskTitle;
    _privacyCustomTitle = customTitle;
    if (currentTrack != null) {
      await _updateMediaItem(currentTrack!,
        privacyEnabled: enabled, blurCover: blurCover,
        maskTitle: maskTitle, customTitle: customTitle);
    }
  }

  AudioHandler? get audioHandler => _audioHandler;

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
            _player.position >= _player.duration! - const Duration(milliseconds: 50)) {
          _completionHandled = true;
          _handleTrackCompletion();
        }
      }
    });
  }

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
    final shouldInspect = ['.wav', '.flac', '.m4a', '.aac', '.ogg', '.opus', '.mp3']
        .any((ext) => originalPath.toLowerCase().endsWith(ext));
    if (!shouldInspect) return null;

    final file = File(originalPath);
    final dir = file.parent;
    final baseName = p.basenameWithoutExtension(originalPath);
    final ext = p.extension(originalPath);
    final hasNonAscii = baseName.codeUnits.any((c) => c > 127);

    bool hasLyric = false;
    for (final lrc in _lyricExtensions) {
      if (await File(p.join(dir.path, '$baseName$lrc')).exists()) {
        hasLyric = true; break;
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
    final dir = Directory(p.join(Directory.systemTemp.path, 'kikoflu_audio_temp'));
    if (!await dir.exists()) await dir.create(recursive: true);
    _tempAudioDirectory = dir;
    return dir;
  }

  Stream<PlayerState> get playerStateStream => _unifiedPlayerStateController.stream;
  Stream<Duration> get positionStream => _unifiedPositionController.stream;
  Stream<Duration?> get durationStream => _unifiedDurationController.stream;
  Stream<List<AudioTrack>> get queueStream => _queueController.stream;
  Stream<AudioTrack?> get currentTrackStream => _currentTrackController.stream;
  Stream<bool> get trackLoadingStream => _trackLoadingController.stream;
  Stream<AudioFormatInfo?> get audioFormatStream => _audioFormatController.stream;

  Duration get position => _hiResActive ? _lastHiResPosition : _player.position;
  Duration? get duration => _hiResActive ? _lastHiResDuration : _player.duration;
  Duration get bufferedPosition =>
      _hiResActive ? _lastHiResBufferedPosition : _player.bufferedPosition;
  bool get playing => _hiResActive ? _hiResService.isPlaying : _player.playing;
  PlayerState get playerState => _hiResActive
      ? PlayerState(_hiResService.isPlaying, ProcessingState.ready)
      : _player.playerState;

  AudioTrack? get currentTrack =>
      _queue.isNotEmpty && _currentIndex < _queue.length
          ? _queue[_currentIndex] : null;

  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  bool get hiResActive => _hiResActive;
  Stream<bool> get hiResActiveStream => _hiResActiveController.stream;
  bool get hasNext => _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;

  Future<void> dispose() async {
    _cancelCrossfade();
    _completionCheckTimer?.cancel();
    _smtcSubscription?.cancel();
    _smtcSubscription = null;
    _justAudioPositionSub?.cancel();
    _justAudioDurationSub?.cancel();
    _libusbStateSub?.cancel();
    _libusbStateSub = null;
    await _stopHiResPlayback();
    await _cleanupTempPlaybackFile();
    await _hiResActiveController.close();
    await _unifiedPositionController.close();
    await _unifiedDurationController.close();
    await _unifiedPlayerStateController.close();
    await _queueController.close();
    await _currentTrackController.close();
    await _trackLoadingController.close();
    await _audioFormatController.close();
    await _player.dispose();
  }
}