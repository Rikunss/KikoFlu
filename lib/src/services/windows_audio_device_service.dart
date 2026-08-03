import 'dart:convert';
import 'dart:ffi';
import 'dart:io' show Platform;

import 'package:ffi/ffi.dart';

/// A Windows audio output device (WASAPI render endpoint).
///
/// Enumerated via the native Core Audio helper compiled into the runner
/// (`windows/runner/audio_device_enum.cpp`).
class WindowsAudioDevice {
  /// mpv-style device id: the raw endpoint id (`IMMDevice::GetId()`) with the
  /// `{0.0.0.00000000}.` prefix stripped — this is exactly the id mpv uses to
  /// match `audio-device=wasapi/<id>` (see mpv `ao_wasapi_utils.c`).
  final String id;

  /// Raw `IMMDevice::GetId()` string (unchanged).
  final String fullId;

  /// Display name — the most descriptive of friendly name / device desc
  /// (e.g. "TempoTec HD USB AUDIO Headphones" for a USB DAC).
  final String name;

  /// Raw friendly name (`PKEY_Device_FriendlyName`) — may be generic.
  final String friendlyName;

  /// Raw device description (`PKEY_Device_DeviceDesc`).
  final String desc;

  /// Device (interface) friendly name — vendor/model string like
  /// "TempoTec HD USB AUDIO" (`{b3f8fa53-...},6`).
  final String iface;

  /// Endpoint form factor (`PKEY_AudioEndpoint_FormFactor`).
  final int formFactor;

  /// Whether this is the Windows default output device.
  final bool isDefault;

  const WindowsAudioDevice({
    required this.id,
    required this.fullId,
    required this.name,
    this.friendlyName = '',
    this.desc = '',
    this.iface = '',
    this.formFactor = -1,
    this.isDefault = false,
  });

  /// The value to pass to mpv's `audio-device` option.
  String get mpvDeviceId => 'wasapi/$id';

  /// Heuristic: USB DACs usually expose form factor SPDIF/HDMI/Unknown
  /// digital and/or have "USB" / "DAC" in the name.
  bool get isLikelyUsbDac {
    final lower = name.toLowerCase();
    final usbInName = lower.contains('usb') || lower.contains('dac');
    const dacLikeFormFactor = {7, 8, 9}; // UnknownDigital, SPDIF, HDMI
    return usbInName || dacLikeFormFactor.contains(formFactor);
  }

  /// Pick the most informative name among the friendly name, device
  /// description and device interface name. Prefers strings mentioning
  /// "USB"/"DAC" (most useful for identifying a USB DAC), then the longest.
  static String _bestName(String friendlyName, String desc, String iface) {
    final candidates = [friendlyName, desc, iface]
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty)
        .toList();
    if (candidates.isEmpty) return 'Unknown';
    bool specific(String s) {
      final lower = s.toLowerCase();
      return lower.contains('usb') || lower.contains('dac');
    }

    final specificOnes = candidates.where(specific).toList();
    final pool = specificOnes.isNotEmpty ? specificOnes : candidates;
    pool.sort((a, b) => b.length.compareTo(a.length));
    return pool.first;
  }

  /// Human-readable form factor label (EndpointFormFactor enum).
  String get formFactorLabel => switch (formFactor) {
        0 => 'Remote device',
        1 => 'Speakers',
        2 => 'Line level',
        3 => 'Headphones',
        4 => 'Microphone',
        5 => 'Headset',
        6 => 'Handset',
        7 => 'Digital (unknown)',
        8 => 'SPDIF',
        9 => 'HDMI',
        10 => 'Unknown',
        _ => '#$formFactor',
      };
}

/// Enumerates Windows WASAPI audio output (render) devices.
///
/// The heavy lifting (Core Audio COM) happens in a tiny C++ helper compiled
/// into the runner exe, exported as plain C functions. Dart only does plain
/// FFI calls (no COM vtable dispatch), which is reliable on every toolchain.
///
/// The returned device ids follow mpv's wasapi convention, so a selected
/// device can be passed straight to mpv via `audio-device=wasapi/<id>`.
class WindowsAudioDeviceService {
  WindowsAudioDeviceService._();

  static final WindowsAudioDeviceService instance =
      WindowsAudioDeviceService._();

  /// Prefix mpv strips from the raw endpoint id (`{0.0.0.00000000}.`).
  static const String _deviceIdPrefix = '{0.0.0.00000000}.';

  static DynamicLibrary? _lib;
  static _EnumerateDart? _enumerate;
  static _FreeDart? _free;

  bool get isSupported => Platform.isWindows;

  static bool _load() {
    if (_lib != null) return true;
    try {
      final lib = DynamicLibrary.process();
      _enumerate = lib.lookupFunction<_EnumerateNative, _EnumerateDart>(
        'kikoflu_enumerate_audio_devices',
      );
      _free = lib.lookupFunction<_FreeNative, _FreeDart>(
        'kikoflu_free_string',
      );
      _lib = lib;
      return true;
    } catch (_) {
      // Symbols missing (e.g. running under `dart run` without the native
      // helper) — degrade to an empty device list.
      _lib = DynamicLibrary.process();
      return false;
    }
  }

  /// Enumerate active WASAPI render (output) devices.
  ///
  /// Returns an empty list on any failure (helper not available, no devices).
  List<WindowsAudioDevice> getOutputDevices() {
    if (!isSupported || !_load()) return [];
    final Pointer<Utf16> ptr;
    try {
      ptr = _enumerate!();
    } catch (_) {
      return [];
    }
    if (ptr == nullptr) return [];
    try {
      final raw = ptr.toDartString();
      if (raw.isEmpty) return [];
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return [];
      final defaultId = decoded['default'] is String ? decoded['default'] as String : '';
      final list = decoded['devices'];
      if (list is! List) return [];
      return [
        for (final item in list)
          if (item is Map)
            _fromMap(item, defaultFullId: defaultId),
      ];
    } catch (_) {
      return [];
    } finally {
      _free!(ptr);
    }
  }

  WindowsAudioDevice _fromMap(Map map, {required String defaultFullId}) {
    final fullId = map['fullId'] is String ? map['fullId'] as String : '';
    final friendlyName = map['name'] is String ? map['name'] as String : '';
    final desc = map['desc'] is String ? map['desc'] as String : '';
    final iface = map['iface'] is String ? map['iface'] as String : '';
    final formFactor = map['formFactor'] is num
        ? (map['formFactor'] as num).toInt()
        : -1;
    final isDefault = map['isDefault'] == true;
    return WindowsAudioDevice(
      id: _mpvStyleId(fullId),
      fullId: fullId,
      name: WindowsAudioDevice._bestName(friendlyName, desc, iface),
      friendlyName: friendlyName,
      desc: desc,
      iface: iface,
      formFactor: formFactor,
      isDefault: isDefault || (fullId.isNotEmpty && fullId == defaultFullId),
    );
  }

  /// Strip the `{0.0.0.00000000}.` prefix mpv removes from endpoint ids.
  String _mpvStyleId(String fullId) => fullId.startsWith(_deviceIdPrefix)
      ? fullId.substring(_deviceIdPrefix.length)
      : fullId;
}

typedef _EnumerateNative = Pointer<Utf16> Function();
typedef _EnumerateDart = Pointer<Utf16> Function();
typedef _FreeNative = Void Function(Pointer<Utf16>);
typedef _FreeDart = void Function(Pointer<Utf16>);
