import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart' show ProcessingState;
import '../models/audio_track.dart';
import 'audio_player_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// States the streaming speed indicator can be in.
enum SpeedIndicatorState {
  /// No streaming activity — either playing local/cached file or no track loaded.
  hidden,

  /// Actively streaming, buffer growing at a healthy rate (>1.5x realtime).
  streaming,

  /// Streaming but buffer growth is slow (<1.5x realtime).
  /// May indicate a congested network connection.
  slow,

  /// Player is in a buffering state (stalled playback).
  buffering,

  /// Entire file has been buffered — streaming is complete for this track.
  cached,
}

/// Immutable state snapshot emitted by [StreamingSpeedTracker].
class StreamingSpeedState {
  final SpeedIndicatorState state;
  final int speedKbps;

  const StreamingSpeedState({
    this.state = SpeedIndicatorState.hidden,
    this.speedKbps = 0,
  });

  /// Quick check whether the indicator should be visible in the UI.
  bool get isVisible => state != SpeedIndicatorState.hidden;

  /// Human-readable speed string, e.g. "3.2 Mbps" or "480 kbps".
  String get displaySpeed {
    if (speedKbps <= 0) return '';
    if (speedKbps >= 1000) {
      return '${(speedKbps / 1000).toStringAsFixed(1)} Mbps';
    }
    return '$speedKbps kbps';
  }
}

/// Tracks streaming download speed in real time by monitoring
/// [AudioPlayerService.bufferedPosition] and cross-referencing it with
/// the audio track's bitrate.
///
/// Algorithm:
/// 1. Every second, sample [(bufferedPosition, timestamp)].
/// 2. Calculate buffer growth rate: `bufferGrowth = bufferDelta / timeDelta`.
///    This gives "seconds of audio buffered per real second" (e.g. 3.2×).
/// 3. Multiply by [AudioFormatInfo.estimatedBitrateKbps] to estimate the
///    instantaneous download speed.
/// 4. Smooth over 3-5 samples via Exponential Moving Average (EMA).
///
/// Only emits meaningful values when:
/// - The current track is a network URL (not file:// or empty)
/// - The player is actively playing (buffer is being consumed + refilled)
/// - [estimatedBitrateKbps] is available (otherwise falls back to growth ratio)
class StreamingSpeedTracker {
  static StreamingSpeedTracker? _instance;
  static StreamingSpeedTracker get instance =>
      _instance ??= StreamingSpeedTracker._();

  // ── State ──
  final StreamController<StreamingSpeedState> _stateController =
      StreamController<StreamingSpeedState>.broadcast();

  StreamSubscription<AudioTrack?>? _trackSub;
  Timer? _sampleTimer;

  bool _isStreaming = false;
  bool _fullBufferReached = false;
  double _prevBufferSecs = 0;
  DateTime? _prevSampleTime;
  double _emaSpeedKbps = 0;
  int? _bitrateKbps;
  SpeedIndicatorState _cachedState = SpeedIndicatorState.hidden;

  /// Stream of speed state snapshots. Emits immediately when state changes
  /// and periodically (~1 s) while streaming.
  Stream<StreamingSpeedState> get stateStream => _stateController.stream;

  /// The last known [SpeedIndicatorState].
  SpeedIndicatorState get currentState => _cachedState;

  /// Whether the tracker is currently monitoring a streaming URL.
  bool get isActive => _isStreaming;

  StreamingSpeedTracker._();

  /// Start monitoring. Call once from [main.dart] or the player screen.
  void start() {
    if (_trackSub != null) return;
    _log.info('[SpeedTracker] Started', tag: 'SpeedTracker');

    // Initialize with the current track FIRST — if a track is already playing,
    // the stream subscription below won't fire for the initial value because
    // [_currentTrackController] is a broadcast stream that only emits NEW values.
    // Without this, [_isStreaming] stays false and the badge never appears.
    final currentTrack = AudioPlayerService.instance.currentTrack;
    if (currentTrack != null) {
      _onTrackChanged(currentTrack);
    }

    // Subscribe to future track changes
    _trackSub = AudioPlayerService.instance.currentTrackStream
        .listen(_onTrackChanged);
    _sampleTimer = Timer.periodic(const Duration(seconds: 1), _sample);
  }

  /// Stop monitoring and reset state.
  void stop() {
    _trackSub?.cancel();
    _trackSub = null;
    _sampleTimer?.cancel();
    _sampleTimer = null;
    _isStreaming = false;
    _fullBufferReached = false;
    _prevBufferSecs = 0;
    _prevSampleTime = null;
    _emaSpeedKbps = 0;
    _bitrateKbps = null;
    _cachedState = SpeedIndicatorState.hidden;
  }

  /// Clean up all resources.
  void dispose() {
    stop();
    _stateController.close();
  }

  // ── Private ──

  void _onTrackChanged(AudioTrack? track) {
    _emaSpeedKbps = 0;
    _prevBufferSecs = 0;
    _prevSampleTime = null;
    _fullBufferReached = false;

    // Determine if this track qualifies as "streaming"
    if (track == null || track.url.isEmpty) {
      _isStreaming = false;
      _emitState();
      return;
    }

    final lower = track.url.toLowerCase();
    if (lower.startsWith('file://')) {
      _isStreaming = false;
      _emitState();
      return;
    }

    _isStreaming = true;

    // Read bitrate from cached audio format info
    final format = AudioPlayerService.instance.lastAudioFormat;
    _bitrateKbps = format?.estimatedBitrateKbps;

    if (_bitrateKbps == null || _bitrateKbps! <= 0) {
      _log.info(
        '[SpeedTracker] No bitrate info for ${track.title} — '
        'will show growth ratio instead',
        tag: 'SpeedTracker',
      );
    }

    _emitState();
  }

  void _sample(Timer _) {
    if (!_isStreaming) return;

    final service = AudioPlayerService.instance;
    final bufferedPos = service.bufferedPosition;
    final duration = service.duration;
    final track = service.currentTrack;

    // If track was removed mid-streaming, reset
    if (track == null || !_isStreaming) return;

    final bufferedSecs = bufferedPos.inMilliseconds / 1000.0;

    // ── Full buffer check ──
    if (duration != null &&
        bufferedPos >= duration - const Duration(milliseconds: 3000)) {
      _fullBufferReached = true;
      _emitState();
      return;
    }

    // Only calculate meaningful deltas while playing (buffer is being consumed)
    final isPlaying = service.playing;
    if (!isPlaying) {
      _prevSampleTime = null;
      return;
    }

    final now = DateTime.now();

    if (_prevSampleTime != null) {
      final timeDelta = now.difference(_prevSampleTime!).inMilliseconds / 1000.0;
      final bufferDelta = bufferedSecs - _prevBufferSecs;

      if (timeDelta > 0 && bufferDelta >= 0) {
        final growthRate = bufferDelta / timeDelta; // e.g. 3.2

        if (_bitrateKbps != null && _bitrateKbps! > 0) {
          // Estimate download speed: growthRate × bitrate
          final instantSpeed = growthRate * _bitrateKbps!;

          // EMA smoothing (α = 0.3 for responsiveness)
          if (_emaSpeedKbps <= 0) {
            _emaSpeedKbps = instantSpeed;
          } else {
            _emaSpeedKbps = _emaSpeedKbps * 0.7 + instantSpeed * 0.3;
          }
        } else {
          // No bitrate — show growth ratio encoded as "speed"
          // e.g. growthRate 3.2 → _emaSpeedKbps = 3200 (shown as "3.2×")
          final instantRatio = growthRate * 1000;
          if (_emaSpeedKbps <= 0) {
            _emaSpeedKbps = instantRatio;
          } else {
            _emaSpeedKbps = _emaSpeedKbps * 0.7 + instantRatio * 0.3;
          }
        }
      }
    }

    _prevBufferSecs = bufferedSecs;
    _prevSampleTime = now;
    _emitState();
  }

  void _emitState() {
    SpeedIndicatorState state;

    if (!_isStreaming) {
      state = SpeedIndicatorState.hidden;
    } else if (_fullBufferReached) {
      state = SpeedIndicatorState.cached;
    } else if (_emaSpeedKbps > 0) {
      final kbps = _bitrateKbps ?? 1000; // fallback for ratio mode
      if (_emaSpeedKbps < kbps * 1.2) {
        state = SpeedIndicatorState.slow;
      } else {
        state = SpeedIndicatorState.streaming;
      }
    } else {
      state = SpeedIndicatorState.hidden;
    }

    _cachedState = state;

    // Detect player buffering state — overrides other states
    final ps = AudioPlayerService.instance.playerState;
    if (ps.processingState == ProcessingState.buffering &&
        _isStreaming && !_fullBufferReached) {
      state = SpeedIndicatorState.buffering;
      _cachedState = state;
    }

    final speedVal = _bitrateKbps != null && _bitrateKbps! > 0
        ? _emaSpeedKbps.round()
        : (_emaSpeedKbps / 1000).round(); // ratio mode

    _stateController.add(StreamingSpeedState(
      state: state,
      speedKbps: speedVal,
    ));
  }
}

// ── Riverpod Provider ──

/// Reactive provider that exposes the current streaming speed state.
/// Rebuilds whenever the tracker emits a new sample.
final streamingSpeedProvider = StreamProvider<StreamingSpeedState>((ref) {
  final tracker = StreamingSpeedTracker.instance;
  return tracker.stateStream;
});
