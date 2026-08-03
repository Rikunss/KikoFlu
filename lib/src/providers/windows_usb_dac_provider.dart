import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/log_service.dart';

/// Bit-perfect USB DAC routing on Windows.
///
/// Unlike Android (libusb), Windows routing is implemented by pointing mpv's
/// WASAPI audio output at the selected output device in exclusive mode:
/// `ao=wasapi`, `audio-exclusive=yes`, `audio-device=wasapi/<id>`.
/// [deviceId] follows mpv's wasapi id convention (raw endpoint id without the
/// `{0.0.0.00000000}.` prefix).
class WindowsUsbDacSettings {
  final bool enabled;
  final String? deviceId;
  final String? deviceName;

  const WindowsUsbDacSettings({
    this.enabled = false,
    this.deviceId,
    this.deviceName,
  });

  WindowsUsbDacSettings copyWith({
    bool? enabled,
    String? deviceId,
    String? deviceName,
  }) {
    return WindowsUsbDacSettings(
      enabled: enabled ?? this.enabled,
      deviceId: deviceId ?? this.deviceId,
      deviceName: deviceName ?? this.deviceName,
    );
  }

  /// Whether a target device has actually been selected.
  bool get hasDevice => deviceId != null && deviceId!.isNotEmpty;
}

class WindowsUsbDacNotifier extends StateNotifier<WindowsUsbDacSettings> {
  static const String enabledKey = 'windows_usb_dac_enabled';
  static const String deviceIdKey = 'windows_usb_dac_device_id';
  static const String deviceNameKey = 'windows_usb_dac_device_name';

  WindowsUsbDacNotifier() : super(const WindowsUsbDacSettings()) {
    _loadPreference();
  }

  Future<void> _loadPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      state = WindowsUsbDacSettings(
        enabled: prefs.getBool(enabledKey) ?? false,
        deviceId: prefs.getString(deviceIdKey),
        deviceName: prefs.getString(deviceNameKey),
      );
    } catch (e) {
      state = const WindowsUsbDacSettings();
    }
  }

  /// Enable/disable Windows USB DAC routing.
  Future<void> toggle(bool enabled) async {
    state = state.copyWith(enabled: enabled);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(enabledKey, enabled);
    } catch (e) {
      LogService.instance.warning(
        '[WindowsUsbDac] Failed to save enabled: $e',
        tag: 'Settings',
      );
    }
  }

  /// Select the target WASAPI output device.
  Future<void> setDevice({String? deviceId, String? deviceName}) async {
    state = state.copyWith(deviceId: deviceId, deviceName: deviceName);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (deviceId != null && deviceId.isNotEmpty) {
        await prefs.setString(deviceIdKey, deviceId);
        await prefs.setString(deviceNameKey, deviceName ?? '');
      } else {
        await prefs.remove(deviceIdKey);
        await prefs.remove(deviceNameKey);
      }
    } catch (e) {
      LogService.instance.warning(
        '[WindowsUsbDac] Failed to save device: $e',
        tag: 'Settings',
      );
    }
  }

  /// Reset everything.
  Future<void> clear() async {
    state = const WindowsUsbDacSettings();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(enabledKey);
      await prefs.remove(deviceIdKey);
      await prefs.remove(deviceNameKey);
    } catch (e) {
      LogService.instance.warning(
        '[WindowsUsbDac] Failed to clear: $e',
        tag: 'Settings',
      );
    }
  }
}

/// Windows USB DAC routing provider.
final windowsUsbDacProvider =
    StateNotifierProvider<WindowsUsbDacNotifier, WindowsUsbDacSettings>((ref) {
  return WindowsUsbDacNotifier();
});
