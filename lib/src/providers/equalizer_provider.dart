import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/equalizer_service.dart';
import '../services/log_service.dart';

final _eqLog = LogService.instance;

/// EQ state provider
final equalizerStateProvider = StreamProvider<EqualizerState>((ref) {
  final service = EqualizerService.instance;
  return service.stateStream;
});

/// EQ enabled state provider
final equalizerEnabledProvider = Provider<bool>((ref) {
  final eqState = ref.watch(equalizerStateProvider);
  return eqState.when(
    data: (state) => state.enabled,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// EQ active preset name provider
final equalizerActivePresetProvider = Provider<String>((ref) {
  final eqState = ref.watch(equalizerStateProvider);
  return eqState.when(
    data: (state) => state.activePresetId,
    loading: () => 'normal',
    error: (_, __) => 'normal',
  );
});

/// EQ device support provider
final equalizerDeviceSupportProvider = Provider<bool>((ref) {
  final eqState = ref.watch(equalizerStateProvider);
  return eqState.when(
    data: (state) => state.deviceSupported,
    loading: () => false,
    error: (_, __) => false,
  );
});

/// EQ gains provider
final equalizerGainsProvider = Provider<List<double>>((ref) {
  final eqState = ref.watch(equalizerStateProvider);
  return eqState.when(
    data: (state) => state.gains,
    loading: () => List.filled(10, 0.0),
    error: (_, __) => List.filled(10, 0.0),
  );
});

/// EQ persisted settings provider (for restoring after app restart)
class EqualizerSettingsNotifier extends StateNotifier<EqualizerSettings> {
  static const String _enabledKey = 'eq_enabled';
  static const String _presetKey = 'eq_active_preset';
  static const String _gainsKey = 'eq_custom_gains';
  static const String _gainsSeparator = ',';

  EqualizerSettingsNotifier() : super(const EqualizerSettings()) {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final enabled = prefs.getBool(_enabledKey) ?? false;
      final preset = prefs.getString(_presetKey) ?? 'normal';
      final gainsStr = prefs.getString(_gainsKey);

      List<double> gains = List.filled(10, 0.0);
      if (gainsStr != null && gainsStr.isNotEmpty) {
        final parts = gainsStr.split(_gainsSeparator);
        if (parts.length == 10) {
          gains = parts.map((s) => double.tryParse(s) ?? 0.0).toList();
        }
      }

      state = EqualizerSettings(
        enabled: enabled,
        activePresetId: preset,
        gains: gains,
      );
    } catch (e) {
      _eqLog.warning('Failed to load persisted EQ settings: $e', tag: 'Equalizer');
      state = const EqualizerSettings();
    }
  }

  Future<void> saveSettings(EqualizerSettings settings) async {
    state = settings;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, settings.enabled);
      await prefs.setString(_presetKey, settings.activePresetId);
      await prefs.setString(
        _gainsKey,
        settings.gains.map((g) => g.toStringAsFixed(1)).join(_gainsSeparator),
      );
    } catch (e) {
      _eqLog.warning('Failed to save EQ settings: $e', tag: 'Equalizer');
    }
  }
}

class EqualizerSettings {
  final bool enabled;
  final String activePresetId;
  final List<double> gains;

  const EqualizerSettings({
    this.enabled = false,
    this.activePresetId = 'normal',
    this.gains = const [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
  });

  EqualizerSettings copyWith({
    bool? enabled,
    String? activePresetId,
    List<double>? gains,
  }) {
    return EqualizerSettings(
      enabled: enabled ?? this.enabled,
      activePresetId: activePresetId ?? this.activePresetId,
      gains: gains ?? this.gains,
    );
  }
}

final equalizerSettingsProvider =
    StateNotifierProvider<EqualizerSettingsNotifier, EqualizerSettings>((ref) {
  return EqualizerSettingsNotifier();
});
