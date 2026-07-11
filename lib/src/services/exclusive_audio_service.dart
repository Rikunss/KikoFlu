import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service that wraps the native Android Exclusive Audio plugin.
///
/// Provides true AAudio exclusive-mode audio:
/// - System volume is locked at max (volume keys don't affect loudness)
/// - AAudio stream opened with AAUDIO_SHARING_MODE_EXCLUSIVE (if device supports)
/// - When exclusive: Android mixer is bypassed for bit-perfect output
/// - Reports accurate exclusive/AAudio status in real-time
///
/// Only available on Android.
final _log = LogService.instance;

class ExclusiveAudioService {
  static ExclusiveAudioService? _instance;
  static ExclusiveAudioService get instance =>
      _instance ??= ExclusiveAudioService._();

  static const MethodChannel _channel =
      MethodChannel('com.kikoeru.flutter/exclusive_audio');

  final StreamController<ExclusiveModeState> _stateController =
      StreamController<ExclusiveModeState>.broadcast();
  final StreamController<String> _usbAttachedController =
      StreamController<String>.broadcast();
  final StreamController<void> _usbDetachedController =
      StreamController<void>.broadcast();

  bool _enabled = false;
  bool _volumeLocked = false;
  bool _aaudioAvailable = false;
  bool _aaudioActive = false;
  bool _aaudioExclusive = false;
  bool _mixerBypassed = false;
  int _aaudioSampleRate = 0;
  String _activeUsbDacName = '';

  ExclusiveAudioService._() {
    _aaudioAvailable = Platform.isAndroid;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Whether exclusive mode is currently enabled.
  bool get enabled => _enabled;

  /// Whether system volume is locked.
  bool get volumeLocked => _volumeLocked;

  /// Whether the device supports AAudio (Android 8.1+).
  bool get aaudioAvailable => _aaudioAvailable;

  /// Whether AAudio stream is active.
  bool get aaudioActive => _aaudioActive;

  /// Whether AAudio exclusive mode was granted (mixer bypassed).
  bool get aaudioExclusive => _aaudioExclusive;

  /// Whether the Android mixer is bypassed (true when AAudio exclusive).
  bool get mixerBypassed => _mixerBypassed;

  /// The actual sample rate of the AAudio stream.
  int get aaudioSampleRate => _aaudioSampleRate;

  /// The name of the actively targeted USB DAC (empty if none).
  String get activeUsbDacName => _activeUsbDacName;

  /// Stream of exclusive mode state changes.
  Stream<ExclusiveModeState> get stateStream => _stateController.stream;

  /// Stream of USB device attached events (during exclusive mode).
  Stream<String> get usbAttachedStream => _usbAttachedController.stream;

  /// Stream of USB device detached events (during exclusive mode).
  Stream<void> get usbDetachedStream => _usbDetachedController.stream;

  /// Handle incoming method calls from native side.
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onExclusiveModeChanged':
        final args = call.arguments;
        if (args is! Map) break;
        _enabled = args['enabled'] == true;
        _volumeLocked = args['volumeLocked'] == true;
        _aaudioAvailable = args['aaudioAvailable'] == true;
        _aaudioActive = args['aaudioActive'] == true;
        _aaudioExclusive = args['aaudioExclusive'] == true;
        _mixerBypassed = args['mixerBypassed'] == true;
        _stateController.add(ExclusiveModeState(
          enabled: _enabled,
          volumeLocked: _volumeLocked,
          aaudioAvailable: _aaudioAvailable,
          aaudioActive: _aaudioActive,
          aaudioExclusive: _aaudioExclusive,
          mixerBypassed: _mixerBypassed,
        ));
        _log.info(
            'Exclusive mode ${_enabled ? "enabled" : "disabled"} '
            '(volLock: $_volumeLocked, AAudio: avail=$_aaudioAvailable active=$_aaudioActive exclusive=$_aaudioExclusive)',
            tag: 'ExclusiveAudio');
        break;
      case 'onUsbDeviceAttached':
        final args = call.arguments;
        if (args is! Map) break;
        final name = args['deviceName'] as String? ?? 'USB DAC';
        final usbDeviceId = args['deviceId'] as int? ?? 0;
        _activeUsbDacName = name;
        _log.info('USB DAC auto-detected: $name (#$usbDeviceId)',
            tag: 'ExclusiveAudio');
        _usbAttachedController.add(name);
        break;
      case 'onUsbDeviceDetached':
        final detachArgs = call.arguments;
        final detachedId = (detachArgs is Map) ? (detachArgs['deviceId'] as int? ?? 0) : 0;
        _activeUsbDacName = '';
        _log.info('USB DAC detached (was #$detachedId) — AAudio reset to default',
            tag: 'ExclusiveAudio');
        _usbDetachedController.add(null);
        break;
      default:
        break;
    }
    return null;
  }

  /// Check if the native plugin is supported.
  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result == true;
    } catch (e) {
      _log.error('isSupported error: $e', tag: 'ExclusiveAudio');
      return false;
    }
  }

  /// Enable exclusive audio mode.
  ///
  /// When enabled:
  /// - System media volume is locked at maximum
  /// - Volume keys do not affect playback loudness
  /// - AAudio exclusive stream requested (if device supports)
  /// - USB audio devices are automatically detected
  Future<bool> enable() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('enable');
      if (result == true) {
        _enabled = true;
        _log.info('Exclusive mode enabled', tag: 'ExclusiveAudio');
      }
      return result == true;
    } catch (e) {
      _log.error('enable error: $e', tag: 'ExclusiveAudio');
      return false;
    }
  }

  /// Disable exclusive audio mode.
  ///
  /// Restores original system volume, closes AAudio stream, cleans up.
  Future<bool> disable() async {
    if (!Platform.isAndroid) return false;
    try {
      final result = await _channel.invokeMethod<bool>('disable');
      if (result == true) {
        _enabled = false;
        _volumeLocked = false;
        _aaudioActive = false;
        _aaudioExclusive = false;
        _mixerBypassed = false;
        _log.info('Exclusive mode disabled', tag: 'ExclusiveAudio');
      }
      return result == true;
    } catch (e) {
      _log.error('disable error: $e', tag: 'ExclusiveAudio');
      return false;
    }
  }

  /// Check if exclusive mode is currently active.
  Future<bool> isActive() async {
    try {
      final result = await _channel.invokeMethod<bool>('isActive');
      _enabled = result == true;
      return _enabled;
    } catch (e) {
      _log.error('isActive error: $e', tag: 'ExclusiveAudio');
      return false;
    }
  }

  /// Get detailed exclusive mode status.
  Future<ExclusiveModeState> getStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStatus');
      if (result != null) {
        _enabled = result['enabled'] == true;
        _volumeLocked = result['volumeLocked'] == true;
        _aaudioAvailable = result['aaudioAvailable'] == true;
        _aaudioActive = result['aaudioActive'] == true;
        _aaudioExclusive = result['aaudioExclusive'] == true;
        _mixerBypassed = result['mixerBypassed'] == true;
        _aaudioSampleRate = (result['aaudioSampleRate'] as int?) ?? 0;
        return ExclusiveModeState(
          enabled: _enabled,
          volumeLocked: _volumeLocked,
          aaudioAvailable: _aaudioAvailable,
          aaudioActive: _aaudioActive,
          aaudioExclusive: _aaudioExclusive,
          mixerBypassed: _mixerBypassed,
          aaudioSampleRate: _aaudioSampleRate,
          aaudioLatencyMs: (result['aaudioLatencyMs'] as num?)?.toDouble() ?? 0.0,
          currentVolume: (result['currentVolume'] as int?) ?? 0,
          maxVolume: (result['maxVolume'] as int?) ?? 0,
          androidSdk: (result['androidSdk'] as int?) ?? 0,
        );
      }
    } catch (e) {
      _log.error('getStatus error: $e', tag: 'ExclusiveAudio');
    }
    return const ExclusiveModeState();
  }

  /// Set the USB DAC device ID for AAudio stream targeting.
  /// Pass 0 to use the default device (system speaker).
  /// The AAudio stream will be re-initialized to target this device.
  Future<void> setAaudioDeviceId(int deviceId) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('setAaudioDeviceId', {'deviceId': deviceId});
    } catch (e) {
      _log.error('setAaudioDeviceId error: $e', tag: 'ExclusiveAudio');
    }
  }

  /// Notify the native plugin that a volume key was pressed.
  Future<void> onVolumeKeyPressed() async {
    try {
      await _channel.invokeMethod('onVolumeKeyPressed');
    } catch (e) {
      _log.error('onVolumeKeyPressed error: $e', tag: 'ExclusiveAudio');
    }
  }

  /// Read the current Android system media volume level.
  /// Returns (currentVolume, maxVolume) or (0, 0) on failure.
  Future<Map<String, int>> getSystemVolume() async {
    if (!Platform.isAndroid) return {'currentVolume': 0, 'maxVolume': 0};
    try {
      final result = await _channel.invokeMethod<Map>('getSystemVolume');
      if (result != null) {
        return {
          'currentVolume': (result['currentVolume'] as int?) ?? 0,
          'maxVolume': (result['maxVolume'] as int?) ?? 0,
        };
      }
    } catch (e) {
      _log.error('getSystemVolume error: $e', tag: 'ExclusiveAudio');
    }
    return {'currentVolume': 0, 'maxVolume': 0};
  }

  /// Clean up resources.
  void dispose() {
    disable();
    _stateController.close();
    _usbAttachedController.close();
    _usbDetachedController.close();
  }
}

/// State of the exclusive audio mode.
class ExclusiveModeState {
  final bool enabled;
  final bool volumeLocked;
  final bool aaudioAvailable;
  final bool aaudioActive;
  final bool aaudioExclusive;
  final bool mixerBypassed;
  final int aaudioSampleRate;
  final double aaudioLatencyMs;
  final int currentVolume;
  final int maxVolume;
  final int androidSdk;

  const ExclusiveModeState({
    this.enabled = false,
    this.volumeLocked = false,
    this.aaudioAvailable = false,
    this.aaudioActive = false,
    this.aaudioExclusive = false,
    this.mixerBypassed = false,
    this.aaudioSampleRate = 0,
    this.aaudioLatencyMs = 0.0,
    this.currentVolume = 0,
    this.maxVolume = 0,
    this.androidSdk = 0,
  });

  /// Human-readable summary of the exclusive mode state.
  String get summary {
    if (!enabled) return 'Off';
    final parts = <String>[];
    if (volumeLocked) parts.add('Vol Locked');
    if (aaudioExclusive) {
      parts.add('AAudio Exclusive');
    } else if (aaudioActive) {
      parts.add('AAudio Shared');
    } else if (aaudioAvailable) {
      parts.add('AAudio Ready');
    }
    if (mixerBypassed) parts.add('Mixer Bypassed');
    return parts.isNotEmpty ? parts.join(', ') : 'On';
  }

  @override
  String toString() =>
      'ExclusiveModeState(enabled: $enabled, volLocked: $volumeLocked, '
      'AAudio: avail=$aaudioAvailable active=$aaudioActive exclusive=$aaudioExclusive, '
      'mixerBypassed: $mixerBypassed, sampleRate: ${aaudioSampleRate}Hz)';
}