import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/windows_usb_dac_provider.dart';
import '../utils/platform_utils.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Service for configuring MPV audio player on desktop platforms.
class MpvConfigService {
  MpvConfigService._();

  /// Configure mpv.conf based on user preferences (e.g., audio passthrough,
  /// Windows USB DAC exclusive routing).
  ///
  /// Creates the mpv config directory and writes the appropriate config file.
  /// This must be called before any audio playback starts.
  static Future<void> configure() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final passthrough = prefs.getBool('audio_passthrough_enabled') ?? false;
      final usbDacEnabled =
          prefs.getBool(WindowsUsbDacNotifier.enabledKey) ?? false;
      final usbDacDeviceId = prefs.getString(
        WindowsUsbDacNotifier.deviceIdKey,
      );

      final configDir = await _getConfigDir();

      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final configFile = File(p.join(configDir.path, 'mpv.conf'));

      setEnv('MPV_HOME', configDir.path);
      _log.info('Set MPV_HOME to: ${configDir.path}', tag: 'Audio');

      if (Platform.isWindows) {
        final useExclusive = passthrough || usbDacEnabled;
        if (useExclusive) {
          await configFile.writeAsString(_windowsExclusiveConfig(
            configDir.path,
            usbDacDeviceId: usbDacEnabled ? usbDacDeviceId : null,
          ));
          _log.info(
            'Updated mpv.conf: Windows WASAPI exclusive mode '
            '(passthrough=$passthrough, usbDac=$usbDacEnabled, '
            'device="$usbDacDeviceId")',
            tag: 'Audio',
          );
        } else {
          await configFile.writeAsString(_normalConfig(configDir.path));
          _log.info('Updated mpv.conf: Video Disabled', tag: 'Audio');
        }
      } else if (Platform.isMacOS) {
        if (passthrough) {
          await configFile.writeAsString(_macPassthroughConfig(configDir.path));
          _log.info('Updated mpv.conf: Exclusive Mode ENABLED (Forced)', tag: 'Audio');
        } else {
          await configFile.writeAsString(_normalConfig(configDir.path));
          _log.info('Updated mpv.conf: Video Disabled', tag: 'Audio');
        }
      } else {
        if (passthrough) {
          await configFile.writeAsString(_linuxPassthroughConfig(configDir.path));
          _log.info('Updated mpv.conf: Passthrough ENABLED', tag: 'Audio');
        } else {
          await configFile.writeAsString(_normalConfig(configDir.path));
          _log.info('Updated mpv.conf: Video Disabled', tag: 'Audio');
        }
      }
    } catch (e) {
      _log.error('Error configuring mpv: $e', tag: 'Audio');
    }
  }

  /// Get or create the MPV config directory.
  static Future<Directory> _getConfigDir() async {
    if (Platform.isWindows) {
      final exePath = Platform.resolvedExecutable;
      final exeDir = p.dirname(exePath);
      return Directory(p.join(exeDir, 'portable_config'));
    } else {
      final appSupportDir = await getApplicationSupportDirectory();
      return Directory(p.join(appSupportDir.path, 'mpv_config'));
    }
  }

  /// Windows config with WASAPI exclusive mode.
  /// When [usbDacDeviceId] is provided (mpv wasapi id), audio is routed to
  /// that device — used for bit-perfect USB DAC output.
  static String _windowsExclusiveConfig(
    String configDirPath, {
    String? usbDacDeviceId,
  }) {
    final deviceLine = (usbDacDeviceId != null && usbDacDeviceId.isNotEmpty)
        ? 'audio-device=wasapi/$usbDacDeviceId\n'
        : '';
    return '''ao=wasapi
audio-exclusive=yes
${deviceLine}audio-spdif=ac3,dts,eac3
log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
  }

  /// macOS config for audio passthrough mode.
  static String _macPassthroughConfig(String configDirPath) {
    return '''ao=coreaudio
audio-exclusive=yes
audio-spdif=ac3,dts,eac3
log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
  }

  /// Linux config for audio passthrough mode.
  static String _linuxPassthroughConfig(String configDirPath) {
    return '''audio-spdif=ac3,dts,eac3
log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
  }

  /// Config content for normal mode (video disabled).
  static String _normalConfig(String configDirPath) {
    if (Platform.isWindows) {
      return '''log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
    } else {
      return '''log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
    }
  }
}
