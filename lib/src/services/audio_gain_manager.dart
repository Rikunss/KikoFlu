import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';
import '../utils/audio_format_parser.dart';
import 'audio_format_gain_service.dart';
import 'cache_service.dart';
import 'replay_gain_service.dart';
import 'volume_normalization_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Manages audio gain — replay gain and volume normalization — for
/// [AudioPlayerService]. Operates on the just_audio [AudioPlayer].
class AudioGainManager {
  final AudioPlayer _player;
  final ReplayGainService _replayGainService;
  final VolumeNormalizationService _volumeNormalizationService;

  double _userBaseVolume = 1.0;
  AudioFormatInfo? _lastAudioFormat;

  AudioGainManager(this._player)
      : _replayGainService = ReplayGainService.instance,
        _volumeNormalizationService = VolumeNormalizationService.instance;

  // ── Getters ──

  double get userBaseVolume => _userBaseVolume;
  AudioFormatInfo? get lastAudioFormat => _lastAudioFormat;
  ReplayGainData? get currentReplayGain => _replayGainService.currentGain;
  double get currentVolumeNormalizationMultiplier =>
      _volumeNormalizationService.currentMultiplier;
  bool get replayGainActive =>
      _replayGainService.enabled && _replayGainService.currentGain != null;
  bool get volumeNormalizationActive => _volumeNormalizationService.enabled;

  void setLastAudioFormat(AudioFormatInfo? info) {
    _lastAudioFormat = info;
  }

  // ── Volume & Speed ──

  Future<void> setVolume(double volume) async {
    _userBaseVolume = volume.clamp(0.0, 1.0);
    final effective =
        (_userBaseVolume * _calculateGainMultiplier()).clamp(0.0, 1.0);
    await _player.setVolume(effective);
  }

  Future<void> setDirectVolume(double volume) async {
    await _player.setVolume(volume.clamp(0.0, 1.0));
  }

  Future<void> setSpeed(double speed) async {
    await _player.setSpeed(speed.clamp(0.5, 2.0));
  }

  double _calculateGainMultiplier() {
    double m = 1.0;
    if (_replayGainService.enabled) {
      m *= _replayGainService.effectiveVolumeMultiplier;
    }
    if (_volumeNormalizationService.enabled) {
      m *= _volumeNormalizationService.currentMultiplier;
    }
    return m;
  }

  Future<void> reapplyAudioGain() async {
    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) {
      return;
    }
    await setVolume(_userBaseVolume);
  }

  Future<void> applyAudioGain(AudioTrack track) async {
    if (!_replayGainService.enabled && !_volumeNormalizationService.enabled) {
      return;
    }

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
}
