import 'dart:io';

import 'package:flutter/material.dart';
import 'package:kikoeru_flutter/src/services/windows_audio_device_service.dart';

/// End-to-end probe: run the Windows app with this target to verify the
/// native C++ Core Audio enumeration works through Dart FFI inside the real
/// app binary (DynamicLibrary.process()).
///
/// Usage: flutter run -d windows -t tool/native_probe_main.dart
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final devices = WindowsAudioDeviceService.instance.getOutputDevices();
  final buf = StringBuffer('NATIVE_DEVICES_COUNT=${devices.length}\n');
  for (final d in devices) {
    buf.writeln(
      'DEV id=${d.id} | name=${d.name} | ff=${d.formFactor} '
      '| default=${d.isDefault} | mpv=${d.mpvDeviceId} '
      '| usb=${d.isLikelyUsbDac}',
    );
  }
  debugPrint(buf.toString());
  try {
    File('build/native_probe_result.txt').writeAsStringSync(buf.toString());
  } catch (_) {}
  exit(0);
}
