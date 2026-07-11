import 'dart:io';
import 'dart:async';
import 'package:flutter/services.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// EQ band definition
class EqualizerBand {
  final int index;
  final String label;
  final double frequencyHz;

  const EqualizerBand({
    required this.index,
    required this.label,
    required this.frequencyHz,
  });
}

/// EQ preset with named curve
class EqualizerPreset {
  final String id;
  final String name;
  final List<double> gains;

  const EqualizerPreset({
    required this.id,
    required this.name,
    required this.gains,
  });
}

/// EQ state
class EqualizerState {
  final bool enabled;
  final String activePresetId;
  final List<double> gains;
  final List<double> deviceBands;
  final bool deviceSupported;

  const EqualizerState({
    this.enabled = false,
    this.activePresetId = 'normal',
    this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    this.deviceBands = const [],
    this.deviceSupported = false,
  });

  EqualizerState copyWith({
    bool? enabled,
    String? activePresetId,
    List<double>? gains,
    List<double>? deviceBands,
    bool? deviceSupported,
  }) {
    return EqualizerState(
      enabled: enabled ?? this.enabled,
      activePresetId: activePresetId ?? this.activePresetId,
      gains: gains ?? this.gains,
      deviceBands: deviceBands ?? this.deviceBands,
      deviceSupported: deviceSupported ?? this.deviceSupported,
    );
  }
}

/// Singleton service for managing audio equalizer
class EqualizerService {
  static EqualizerService? _instance;
  static EqualizerService get instance => _instance ??= EqualizerService._();

  static const MethodChannel _channel = MethodChannel('com.kikoeru.flutter/equalizer');

  static const List<double> standardBands = [
    31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000
  ];

  static const List<String> bandLabels = [
    '31Hz', '62Hz', '125Hz', '250Hz', '500Hz',
    '1kHz', '2kHz', '4kHz', '8kHz', '16kHz',
  ];

  static const List<EqualizerPreset> presets = [
    EqualizerPreset(id: 'normal', name: 'Normal', gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqualizerPreset(id: 'classical', name: 'Classical', gains: [0, 0, 0, 0, 0, 0, -1, -2, -3, -4]),
    EqualizerPreset(id: 'dance', name: 'Dance', gains: [4, 3, 1, 0, -1, 0, 1, 2, 3, 4]),
    EqualizerPreset(id: 'deep', name: 'Deep', gains: [5, 4, 2, 1, 0, 0, 0, 0, 0, 0]),
    EqualizerPreset(id: 'hiphop', name: 'Hip-Hop', gains: [3, 2, 0, -1, 0, 1, 2, 3, 2, 1]),
    EqualizerPreset(id: 'jazz', name: 'Jazz', gains: [2, 1, 1, 2, 2, 1, 1, 2, 3, 3]),
    EqualizerPreset(id: 'loudness', name: 'Loudness', gains: [3, 2, 1, 0, 0, 1, 2, 3, 3, 3]),
    EqualizerPreset(id: 'pop', name: 'Pop', gains: [-1, 0, 2, 3, 3, 2, 1, 0, -1, -1]),
    EqualizerPreset(id: 'rock', name: 'Rock', gains: [3, 2, 0, -1, -1, 0, 2, 3, 3, 2]),
    EqualizerPreset(id: 'vocal', name: 'Vocal', gains: [-1, -1, 1, 2, 3, 3, 2, 1, 0, -1]),
  ];

  EqualizerService._();

  bool _initialized = false;
  bool _deviceSupported = false;

  EqualizerState _state = const EqualizerState();

  final StreamController<EqualizerState> _stateController =
      StreamController<EqualizerState>.broadcast();

  Stream<EqualizerState> get stateStream => _stateController.stream;
  EqualizerState get state => _state;

  /// Initialize: query device capabilities
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (Platform.isAndroid) {
      try {
        final result = await _channel.invokeMethod('isSupported');
        _deviceSupported = result == true;
      } catch (e) {
        _log.warning('Failed to query equalizer support: $e', tag: 'Equalizer');
        _deviceSupported = false;
      }
    } else if (Platform.isIOS || Platform.isMacOS) {
      _deviceSupported = false;
    } else {
      _deviceSupported = false;
    }

    List<double> deviceBands = [];
    if (_deviceSupported) {
      try {
        final bands = await _channel.invokeMethod('getBands');
        if (bands is List) {
          deviceBands = bands.cast<double>();
        }
      } catch (e) {
        _log.warning('Failed to query equalizer bands: $e', tag: 'Equalizer');
      }
    }

    _state = _state.copyWith(
      deviceSupported: _deviceSupported,
      deviceBands: deviceBands.isNotEmpty ? deviceBands : standardBands,
    );
    _stateController.add(_state);
  }

  /// Apply a preset
  Future<void> applyPreset(String presetId) async {
    final preset = presets.where((p) => p.id == presetId).firstOrNull;
    if (preset == null) return;

    _state = _state.copyWith(
      enabled: true,
      activePresetId: presetId,
      gains: List.from(preset.gains),
    );

    await _applyGains(preset.gains);
    _stateController.add(_state);
  }

  /// Toggle EQ on/off
  Future<void> toggleEnabled() async {
    if (_state.enabled) {
      _state = _state.copyWith(enabled: false);
      await _applyGains(List.filled(10, 0));
    } else {
      _state = _state.copyWith(enabled: true);
      await _applyGains(_state.gains);
    }
    _stateController.add(_state);
  }

  /// Set a specific band gain
  Future<void> setBandGain(int bandIndex, double gainDb) async {
    if (bandIndex < 0 || bandIndex >= 10) return;

    final newGains = List<double>.from(_state.gains);
    newGains[bandIndex] = gainDb.clamp(-12.0, 12.0);

    String newPresetId = 'custom';
    for (final preset in presets) {
      if (_gainsEqual(preset.gains, newGains)) {
        newPresetId = preset.id;
        break;
      }
    }

    _state = _state.copyWith(
      enabled: true,
      activePresetId: newPresetId,
      gains: newGains,
    );

    if (_state.enabled) {
      await _applyGains(newGains);
    }
    _stateController.add(_state);
  }

  /// Set all band gains at once
  Future<void> setCustomGains(List<double> gains) async {
    if (gains.length != 10) return;

    final clamped = gains.map((g) => g.clamp(-12.0, 12.0)).toList();

    _state = _state.copyWith(
      enabled: true,
      activePresetId: 'custom',
      gains: clamped,
    );

    if (_state.enabled) {
      await _applyGains(clamped);
    }
    _stateController.add(_state);
  }

  /// Apply gains to native platform
  Future<void> _applyGains(List<double> gains) async {
    if (!_deviceSupported) return;

    try {
      await _channel.invokeMethod('setGains', {
        'gains': gains,
      });
    } catch (e) {
      _log.error('Failed to apply gains: $e', tag: 'Equalizer');
    }
  }

  bool _gainsEqual(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if ((a[i] - b[i]).abs() > 0.5) return false;
    }
    return true;
  }

  /// Reset to flat (Normal)
  Future<void> resetToFlat() async {
    await applyPreset('normal');
    _state = _state.copyWith(enabled: false);
    _stateController.add(_state);
  }

  /// Set the audio session ID from the audio player (Android)
  Future<void> setAudioSessionId(int sessionId) async {
    try {
      await _channel.invokeMethod('setAudioSessionId', {
        'sessionId': sessionId,
      });
    } catch (e) {
      _log.error('Failed to set audio session ID: $e', tag: 'Equalizer');
    }
  }

  bool get isDeviceSupported => _deviceSupported;

  void dispose() {
    _stateController.close();
  }
}