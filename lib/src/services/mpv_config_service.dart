import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/platform_utils.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Service for configuring MPV audio player on desktop platforms.
class MpvConfigService {
  MpvConfigService._();

  /// Configure mpv.conf based on user preferences (e.g., audio passthrough).
  ///
  /// Creates the mpv config directory and writes the appropriate config file.
  /// This must be called before any audio playback starts.
  static Future<void> configure() async {
    if (!Platform.isWindows && !Platform.isMacOS && !Platform.isLinux) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final passthrough = prefs.getBool('audio_passthrough_enabled') ?? false;

      final configDir = await _getConfigDir();

      if (!await configDir.exists()) {
        await configDir.create(recursive: true);
      }

      final configFile = File(p.join(configDir.path, 'mpv.conf'));

      // Force set MPV_HOME to ensure config is read
      setEnv('MPV_HOME', configDir.path);
      _log.info('Set MPV_HOME to: ${configDir.path}', tag: 'Audio');

      if (passthrough) {
        await configFile.writeAsString(_passthroughConfig(configDir.path));
        _log.info('Updated mpv.conf: Exclusive Mode ENABLED (Forced)', tag: 'Audio');
      } else {
        await configFile.writeAsString(_normalConfig(configDir.path));
        _log.info('Updated mpv.conf: Video Disabled', tag: 'Audio');
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

  /// Config content for audio passthrough mode.
  static String _passthroughConfig(String configDirPath) {
    if (Platform.isWindows) {
      return '''ao=wasapi
audio-exclusive=yes
audio-spdif=ac3,dts,eac3
log-file=mpv_debug.log
msg-level=all=v
video=no
sub-auto=no
''';
    } else if (Platform.isLinux) {
      return '''audio-spdif=ac3,dts,eac3
log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
    } else {
      // macOS
      return '''ao=coreaudio
audio-exclusive=yes
audio-spdif=ac3,dts,eac3
log-file=${p.join(configDirPath, 'mpv_debug.log')}
msg-level=all=v
video=no
sub-auto=no
''';
    }
  }

  /// Config content for normal mode (video disabled).
  static String _normalConfig(String configDirPath) {
    if (Platform.isWindows) {
      return '''log-file=mpv_debug.log
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
