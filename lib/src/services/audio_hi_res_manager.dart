import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';
import 'audio_format_gain_service.dart';
import 'hi_res_audio_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Manages hi-res ExoPlayer playback and error fallback for
/// [AudioPlayerService].
///
/// Handles:
/// - Hi-res track loading and lifecycle
/// - Position/duration/buffered position tracking
/// - Playback state, buffering, and error event subscriptions
/// - Auto-fallback to just_audio on hi-res failure
///
/// Communicates with the parent via callbacks so the parent can
/// forward events to unified streams or trigger higher-level actions.
class AudioHiResManager {
  final HiResAudioService _hiResService;

  bool _hiResEnabled = false;
  bool _hiResActive = false;

  Duration _lastHiResPosition = Duration.zero;
  Duration? _lastHiResDuration;
  Duration _lastHiResBufferedPosition = Duration.zero;

  final StreamController<bool> _hiResActiveController =
      StreamController<bool>.broadcast()..add(false);

  StreamSubscription? _hiResPlaybackSub;
  StreamSubscription? _hiResBufferingSub;
  StreamSubscription? _hiResErrorSub;
  StreamSubscription<int>? _nativePositionSub;
  StreamSubscription<int>? _nativeDurationSub;
  StreamSubscription<int>? _nativeBufferedPositionSub;
  StreamSubscription<bool>? _trackEndedSub;

  bool _hiResFallbackInFlight = false;

  // ── Callbacks (set by parent) ──

  void Function(Duration position)? onPositionChanged;
  void Function(Duration? duration)? onDurationChanged;
  void Function(Duration bufferedPosition)? onBufferedPositionChanged;
  void Function(bool isPlaying)? onPlaybackStateChanged;
  void Function(bool buffering)? onBufferingChanged;
  Future<void> Function(AudioTrack track, {int startPositionMs})?
      onFallbackLoadTrack;
  void Function()? onErrorFallbackStarted;
  void Function()? onTrackCompleted;

  AudioHiResManager() : _hiResService = HiResAudioService.instance;

  // ── Getters ──

  bool get hiResEnabled => _hiResEnabled;
  bool get hiResActive => _hiResActive;
  Stream<bool> get hiResActiveStream => _hiResActiveController.stream;

  Duration get position => _lastHiResPosition;
  Duration? get duration => _lastHiResDuration;
  Duration get bufferedPosition => _lastHiResBufferedPosition;
  bool get isPlaying => _hiResService.isPlaying;
  PlayerState get playerState =>
      PlayerState(_hiResService.isPlaying, ProcessingState.ready);

  HiResAudioService get hiResService => _hiResService;

  // ── Settings ──

  void setHiResEnabled(bool enabled) {
    _hiResEnabled = enabled;
  }

  Future<bool> shouldUseHiResForTrack(AudioTrack track) async {
    if (!_hiResEnabled) return false;
    if (_hiResService.isUsbRouted) return true;

    final formatInfo = await AudioFormatGainService.detectFormatDirect(track);
    if (formatInfo == null) return false;

    final codec = formatInfo.codec.toUpperCase();
    if (codec == 'FLAC' || codec == 'WAV' || codec == 'M4A') return true;
    if (formatInfo.sampleRate != null) return formatInfo.sampleRate! > 48000;
    return false;
  }

  // ── Lifecycle ──

  /// Load a track through the hi-res ExoPlayer pathway.
  ///
  /// Returns format info if detected, null otherwise.
  /// The caller should emit format info on the audio format stream.
  Future<HiResFormatInfo?> loadHiResTrack(AudioTrack track,
      {int startPositionMs = 0}) async {
    _log.info(
        '_loadHiResTrack: title="${track.title}" startPos=${startPositionMs}ms',
        tag: 'Audio');

    await stopHiResPlayback(silent: true);
    _hiResActive = true;
    _hiResActiveController.add(true);

    final formatInfo = await _detectFormat(track);

    String playUrl = track.url;
    if (playUrl.startsWith('file://')) {
      playUrl = playUrl
          .substring(7)
          .replaceAll('/', track.url.contains('/') ? '/' : '\\');
    }

    final success = await _hiResService.play(
      playUrl,
      sampleRate: formatInfo?.sampleRate ?? 0,
      bitDepth: formatInfo?.bitDepth ?? 0,
      startPositionMs: startPositionMs,
    );

    if (!success) {
      _log.warning(
          'Hi-Res playback failed, falling back to just_audio at ${startPositionMs}ms',
          tag: 'Audio');
      await _fallback(track, startPositionMs: startPositionMs);
      return null; // null signals caller that fallback happened
    }

    _setupSubscriptions(track);
    return formatInfo;
  }

  Future<void> _fallback(AudioTrack track, {int startPositionMs = 0}) async {
    _hiResActive = false;
    _hiResActiveController.add(false);
    final savedEnabled = _hiResEnabled;
    _hiResEnabled = false;
    try {
      await onFallbackLoadTrack?.call(track, startPositionMs: startPositionMs);
    } finally {
      _hiResEnabled = savedEnabled;
    }
  }

  void _setupSubscriptions(AudioTrack track) {
    _nativePositionSub?.cancel();
    _nativePositionSub = _hiResService.nativePositionStream.listen((posMs) {
      if (!_hiResActive) return;
      _lastHiResPosition = Duration(milliseconds: posMs);
      onPositionChanged?.call(_lastHiResPosition);
    });

    _nativeDurationSub?.cancel();
    _nativeDurationSub = _hiResService.nativeDurationStream.listen((durMs) {
      if (!_hiResActive) return;
      if (durMs > 0) {
        _lastHiResDuration = Duration(milliseconds: durMs);
        onDurationChanged?.call(_lastHiResDuration);
      }
    });

    _nativeBufferedPositionSub?.cancel();
    _nativeBufferedPositionSub =
        _hiResService.nativeBufferedPositionStream.listen((bufPosMs) {
      if (!_hiResActive) return;
      _lastHiResBufferedPosition = Duration(milliseconds: bufPosMs);
      onBufferedPositionChanged?.call(_lastHiResBufferedPosition);
    });

    _hiResPlaybackSub?.cancel();
    _hiResPlaybackSub = _hiResService.playbackStateStream.listen((playing) {
      if (!_hiResActive) return;
      onPlaybackStateChanged?.call(playing);
    });

    _trackEndedSub?.cancel();
    _trackEndedSub = _hiResService.trackEndedStream.listen((_) {
      if (!_hiResActive) return;
      onTrackCompleted?.call();
    });

    _hiResBufferingSub?.cancel();
    _hiResBufferingSub = _hiResService.bufferingStream.listen((buffering) {
      if (!_hiResActive) return;
      onBufferingChanged?.call(buffering);
    });

    _hiResErrorSub?.cancel();
    _hiResErrorSub = _hiResService.errorStream.listen((message) {
      if (!_hiResActive) return;
      if (_hiResFallbackInFlight) {
        _log.info(
            '[HiRes] Error received while fallback already in-flight; skipping',
            tag: 'Audio');
        return;
      }
      _hiResFallbackInFlight = true;
      _log.error(
          '[HiRes] Player error: $message — falling back to just_audio',
          tag: 'Audio');
      final resumeMs = _lastHiResPosition.inMilliseconds;
      onErrorFallbackStarted?.call();
      _hiResActive = false;
      _hiResActiveController.add(false);
      final savedEnabled = _hiResEnabled;
      _hiResEnabled = false;
      onFallbackLoadTrack?.call(track, startPositionMs: resumeMs)
          .whenComplete(() {
        _hiResEnabled = savedEnabled;
        _hiResFallbackInFlight = false;
      });
    });
  }

  /// Stop hi-res playback. When [silent] is true, position/duration
  /// are NOT reset (caller will immediately load another hi-res track).
  Future<void> stopHiResPlayback({bool silent = false}) async {
    _cancelSubscriptions();
    if (_hiResActive) {
      await _hiResService.stop();
      _hiResActive = false;
      _hiResActiveController.add(false);
      if (!silent) {
        _lastHiResPosition = Duration.zero;
        _lastHiResDuration = null;
        _lastHiResBufferedPosition = Duration.zero;
      }
    }
  }

  /// Stop only the native subscription streams (used before track switch).
  void cancelNativeSubs() {
    _nativePositionSub?.cancel();
    _nativePositionSub = null;
    _nativeDurationSub?.cancel();
    _nativeDurationSub = null;
    _nativeBufferedPositionSub?.cancel();
    _nativeBufferedPositionSub = null;
  }

  void _cancelSubscriptions() {
    cancelNativeSubs();
    _hiResPlaybackSub?.cancel();
    _hiResPlaybackSub = null;
    _hiResBufferingSub?.cancel();
    _hiResBufferingSub = null;
    _hiResErrorSub?.cancel();
    _hiResErrorSub = null;
    _trackEndedSub?.cancel();
    _trackEndedSub = null;
  }

  /// Return the current hi-res position in milliseconds (used before stopping).
  int freezePositionMs() => _lastHiResPosition.inMilliseconds;

  void dispose() {
    _cancelSubscriptions();
    _hiResActiveController.close();
  }

  // ── Internal Helpers ──

  Future<HiResFormatInfo?> _detectFormat(AudioTrack track) async {
    final info = await AudioFormatGainService.detectFormatDirect(track);
    if (info == null) return null;
    return HiResFormatInfo(
      sampleRate: info.sampleRate ?? 0,
      bitDepth: info.bitDepth ?? 0,
      channels: info.channels ?? 2,
    );
  }
}
