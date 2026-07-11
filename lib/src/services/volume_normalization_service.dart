import 'dart:math' show pow;

import '../utils/audio_format_parser.dart';

/// Service for volume normalization (peak-based loudness management).
///
/// When ReplayGain metadata is unavailable, this service provides a fallback
/// normalization strategy based on the audio file's bit depth and estimated
/// dynamic range. The goal is to bring quieter tracks up and prevent
/// excessively loud tracks from clipping.
///
/// For files with known bit depth:
/// - 16-bit → theoretical dynamic range ~96 dB → mild boost
/// - 24-bit → theoretical dynamic range ~144 dB → mild boost
///
/// The normalization target is -14 LUFS (streaming standard) as a reference,
/// implemented as a fixed gain adjustment based on bit depth heuristics.
class VolumeNormalizationService {
  static VolumeNormalizationService? _instance;
  static VolumeNormalizationService get instance =>
      _instance ??= VolumeNormalizationService._();

  VolumeNormalizationService._();

  bool _enabled = false;

  /// Target loudness level in dB (relative to full scale).
  /// Standard streaming target is -14 LUFS ≈ -14 dBFS average.
  double _targetLevelDb = -14.0;

  /// The calculated volume multiplier for the current track.
  double _currentMultiplier = 1.0;

  bool get enabled => _enabled;
  double get targetLevelDb => _targetLevelDb;
  double get currentMultiplier => _currentMultiplier;

  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _currentMultiplier = 1.0;
    }
  }

  void setTargetLevel(double db) {
    _targetLevelDb = db.clamp(-24.0, -6.0);
  }

  /// Calculate normalization multiplier based on file characteristics.
  ///
  /// Uses bit depth as a heuristic for headroom:
  /// - 16-bit: assume ~12 dB of headroom from typical mastering
  /// - 24-bit: assume ~18 dB of headroom
  /// - Unknown: assume ~6 dB (conservative, no clipping)
  ///
  /// The multiplier brings the assumed average level up to the target.
  Future<double> calculateMultiplier(String? filePath,
      {int? bitDepth, double? replayGainPeak}) async {
    if (!_enabled) {
      _currentMultiplier = 1.0;
      return 1.0;
    }

    if (replayGainPeak != null && replayGainPeak > 0) {
      final targetPeak = _dbToLinear(-1.0);
      _currentMultiplier = (targetPeak / replayGainPeak).clamp(0.5, 2.0);
      return _currentMultiplier;
    }

    if (bitDepth != null) {
      final double assumedLevel;
      switch (bitDepth) {
        case 16:
          assumedLevel = -12.0;
          break;
        case 24:
          assumedLevel = -18.0;
          break;
        default:
          assumedLevel = -12.0;
      }
      final adjustmentDb = _targetLevelDb - assumedLevel;
      _currentMultiplier = _dbToLinear(adjustmentDb).clamp(0.5, 2.0);
      return _currentMultiplier;
    }

    if (filePath != null) {
      final formatInfo = await AudioFormatInfo.fromFile(filePath);
      final detectedBitDepth = formatInfo.bitDepth;
      if (detectedBitDepth != null) {
        final assumedLevel = detectedBitDepth >= 24 ? -18.0 : -12.0;
        final adjustmentDb = _targetLevelDb - assumedLevel;
        _currentMultiplier = _dbToLinear(adjustmentDb).clamp(0.5, 2.0);
        return _currentMultiplier;
      }
    }

    _currentMultiplier = 1.15;
    return _currentMultiplier;
  }

  static double _dbToLinear(double db) {
    return pow(10.0, db / 20.0).toDouble();
  }

  void dispose() {
    _currentMultiplier = 1.0;
  }
}