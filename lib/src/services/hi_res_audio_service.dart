import 'dart:async';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service that wraps the native Android Hi-Res Audio ExoPlayer plugin.
///
/// Provides a secondary playback pathway that uses AndroidX Media3 (ExoPlayer)
/// configured with hi-res audio flags ({@code FLAG_HW_AV_SYNC}) for improved
/// audio output quality on supporting hardware.
///
/// Only available on Android.
final _log = LogService.instance;

class HiResAudioService {
  static HiResAudioService? _instance;
  static HiResAudioService get instance => _instance ??= HiResAudioService._();

  static const MethodChannel _channel =
      MethodChannel('com.kikoeru.flutter/hires_audio');

  // Stream controllers for state changes from native
  final StreamController<bool> _playbackStateController =
      StreamController<bool>.broadcast();
  final StreamController<HiResFormatInfo?> _formatInfoController =
      StreamController<HiResFormatInfo?>.broadcast();
  final StreamController<bool> _bufferingController =
      StreamController<bool>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();
  final StreamController<List<UsbAudioDevice>> _usbDevicesController =
      StreamController<List<UsbAudioDevice>>.broadcast();
  final StreamController<UsbRoutingState> _usbRoutingController =
      StreamController<UsbRoutingState>.broadcast();
  final StreamController<String> _outputDeviceController =
      StreamController<String>.broadcast();

  bool _isPlaying = false;
  bool _isUsbRouted = false;

  HiResAudioService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Stream of playback state changes (isPlaying).
  Stream<bool> get playbackStateStream => _playbackStateController.stream;

  /// Stream of audio format info updates from the native player.
  Stream<HiResFormatInfo?> get formatInfoStream =>
      _formatInfoController.stream;

  /// Stream of buffering state changes.
  Stream<bool> get bufferingStream => _bufferingController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Stream of USB device list changes.
  Stream<List<UsbAudioDevice>> get usbDevicesStream =>
      _usbDevicesController.stream;

  /// Stream of USB routing state changes.
  Stream<UsbRoutingState> get usbRoutingStream =>
      _usbRoutingController.stream;

  /// Stream of active audio output device type changes.
  /// Values: 'usb_dac', 'usb_detected', 'wired_headphones', 'bluetooth', 'builtin', 'unknown'
  Stream<String> get outputDeviceStream =>
      _outputDeviceController.stream;

  /// Whether the player is currently playing.
  bool get isPlaying => _isPlaying;

  /// Whether audio is currently routed to a USB DAC.
  bool get isUsbRouted => _isUsbRouted;

  /// Handle incoming method calls from native side (events).
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onPlaybackStateChanged':
        _isPlaying = call.arguments['isPlaying'] ?? false;
        _playbackStateController.add(_isPlaying);
        break;
      case 'onFormatInfo':
        final args = call.arguments;
        if (args is! Map) break;
        _formatInfoController.add(HiResFormatInfo(
          sampleRate: (args['sampleRate'] as int?) ?? 0,
          bitDepth: (args['bitDepth'] as int?) ?? 0,
          channels: (args['channels'] as int?) ?? 2,
        ));
        break;
      case 'onBuffering':
        _bufferingController.add(call.arguments['buffering'] ?? false);
        break;
      case 'onError':
        _errorController
            .add(call.arguments['message'] as String? ?? 'Unknown error');
        break;
      case 'onUsbDevicesChanged':
        final args = call.arguments;
        if (args is! Map) break;
        final devices = (args['devices'] as List?)
                ?.map((d) => UsbAudioDevice.fromMap(d as Map))
                .toList() ??
            [];
        _log.info('USB devices changed: ${devices.length} device(s)',
            tag: 'USB');
        for (final d in devices) {
          _log.info('  └ ${d.productName} (${d.maxSampleRate}Hz, ${d.maxChannelCount}ch)',
              tag: 'USB');
        }
        _usbDevicesController.add(devices);
        break;
      case 'onUsbRoutingChanged':
        final args = call.arguments;
        if (args is! Map) break;
        final routed = args['routed'] == true;
        final deviceName = args['deviceName'] as String? ?? '';
        final mixerApplied = args['mixerAttributesApplied'] == true;
        _isUsbRouted = routed;
        if (routed) {
          _log.info('USB routing changed: routed to $deviceName'
              '${mixerApplied ? ' (bit-perfect API applied)' : ''}',
              tag: 'USB');
        } else {
          _log.info('USB routing changed: reverted to system default',
              tag: 'USB');
        }
        _usbRoutingController.add(UsbRoutingState(
          routed: _isUsbRouted,
          deviceName: deviceName,
          mixerAttributesApplied: mixerApplied,
        ));
        break;
      case 'onOutputDeviceChanged':
        final outArgs = call.arguments;
        if (outArgs is! Map) break;
        final deviceType = outArgs['activeDeviceType'] as String? ?? 'unknown';
        _log.info('Output device changed: $deviceType', tag: 'USB');
        _outputDeviceController.add(deviceType);
        break;
      default:
        break;
    }
    return null;
  }

  /// Check if the native plugin is supported (Android only).
  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result == true;
    } catch (e) {
      _log.error('isSupported error: $e', tag: 'HiResAudio');
      return false;
    }
  }

  /// Play a URL (or file path) through the hi-res ExoPlayer.
  ///
  /// [url] can be an http(s) URL or a file:// path.
  /// [sampleRate] and [bitDepth] are optional hints for the player.
  Future<bool> play(String url, {int sampleRate = 0, int bitDepth = 0}) async {
    try {
      final result = await _channel.invokeMethod<bool>('play', {
        'url': url,
        'sampleRate': sampleRate,
        'bitDepth': bitDepth,
      });
      return result == true;
    } catch (e) {
      _log.error('play error: $e', tag: 'HiResAudio');
      return false;
    }
  }

  /// Pause playback.
  Future<void> pause() async {
    try {
      await _channel.invokeMethod('pause');
      _isPlaying = false;
      _playbackStateController.add(false);
    } catch (e) {
      _log.error('pause error: $e', tag: 'HiResAudio');
    }
  }

  /// Resume playback after pause.
  Future<void> resume() async {
    try {
      await _channel.invokeMethod('resume');
    } catch (e) {
      _log.error('resume error: $e', tag: 'HiResAudio');
    }
  }

  /// Stop playback and reset position.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
      _isPlaying = false;
      _playbackStateController.add(false);
    } catch (e) {
      _log.error('stop error: $e', tag: 'HiResAudio');
    }
  }

  /// Seek to a position in milliseconds.
  Future<void> seekTo(int positionMs) async {
    try {
      await _channel.invokeMethod('seekTo', {'positionMs': positionMs});
    } catch (e) {
      _log.error('seekTo error: $e', tag: 'HiResAudio');
    }
  }

  /// Get the current playback position in milliseconds.
  Future<int> getPosition() async {
    try {
      final result = await _channel.invokeMethod<int>('getPosition');
      return result ?? 0;
    } catch (e) {
      _log.error('getPosition error: $e', tag: 'HiResAudio');
      return 0;
    }
  }

  /// Get the total duration in milliseconds.
  Future<int> getDuration() async {
    try {
      final result = await _channel.invokeMethod<int>('getDuration');
      return result ?? 0;
    } catch (e) {
      _log.error('getDuration error: $e', tag: 'HiResAudio');
      return 0;
    }
  }

  /// Set playback volume (0.0 – 1.0).
  Future<void> setVolume(double volume) async {
    try {
      await _channel.invokeMethod('setVolume', {'volume': volume});
    } catch (e) {
      _log.error('setVolume error: $e', tag: 'HiResAudio');
    }
  }

  /// Set the preferred sample rate hint for the native player.
  Future<void> setSampleRate(int sampleRate) async {
    try {
      await _channel.invokeMethod('setSampleRate', {'sampleRate': sampleRate});
    } catch (e) {
      _log.error('setSampleRate error: $e', tag: 'HiResAudio');
    }
  }

  // ── USB DAC Bypass methods ──

  /// Get the list of connected USB audio devices.
  Future<List<UsbAudioDevice>> getUsbAudioDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('getUsbAudioDevices');
      if (result == null) return [];
      final devices = result
          .map((d) => UsbAudioDevice.fromMap(d as Map))
          .toList();
      _log.info('Queried USB devices: found ${devices.length} device(s)',
          tag: 'USB');
      for (final d in devices) {
        _log.info(
            '  └ #${d.id} ${d.productName} (${d.maxSampleRate}Hz, ${d.maxChannelCount}ch)',
            tag: 'USB');
      }
      return devices;
    } catch (e) {
      _log.error('getUsbAudioDevices failed: $e', tag: 'USB');
      return [];
    }
  }

  /// Enable or disable USB DAC bypass mode.
  ///
  /// When enabled, audio will be routed to the specified [deviceId] if provided,
  /// otherwise to the first available USB DAC.
  Future<bool> setUsbBypassMode(bool enabled, {int? deviceId}) async {
    try {
      final args = <String, dynamic>{'enabled': enabled};
      if (deviceId != null && deviceId > 0) {
        args['deviceId'] = deviceId;
      }
      final result =
          await _channel.invokeMethod<bool>('setUsbBypassMode', args);
      if (enabled) {
        final deviceStr = deviceId != null ? ' (device #$deviceId)' : '';
        _log.info('USB DAC bypass enabled$deviceStr', tag: 'USB');
      } else {
        _log.info('USB DAC bypass disabled', tag: 'USB');
      }
      return result == true;
    } catch (e) {
      _log.error('setUsbBypassMode failed: $e', tag: 'USB');
      return false;
    }
  }

  /// Route audio to a specific USB audio device by its ID.
  Future<bool> routeToUsbDevice(int deviceId) async {
    try {
      _log.info('Routing to USB device #$deviceId...', tag: 'USB');
      final result =
          await _channel.invokeMethod<bool>('routeToUsbDevice', {
        'deviceId': deviceId,
      });
      if (result == true) {
        _log.info('Successfully routed to USB device #$deviceId', tag: 'USB');
      } else {
        _log.warning('Failed to route to USB device #$deviceId', tag: 'USB');
      }
      return result == true;
    } catch (e) {
      _log.error('routeToUsbDevice failed: $e', tag: 'USB');
      return false;
    }
  }

  /// Clear USB audio device routing (revert to system default).
  Future<void> clearUsbRouting() async {
    try {
      await _channel.invokeMethod('clearUsbRouting');
      _isUsbRouted = false;
      _log.info('USB DAC routing cleared (reverted to system default)',
          tag: 'USB');
      _usbRoutingController.add(const UsbRoutingState(
        routed: false,
        deviceName: '',
      ));
    } catch (e) {
      _log.error('clearUsbRouting failed: $e', tag: 'USB');
    }
  }

  /// Refresh and check if audio is currently routed to a USB DAC.
  Future<bool> checkUsbRouted() async {
    try {
      final result = await _channel.invokeMethod<bool>('isUsbRouted');
      _isUsbRouted = result == true;
      _log.info('USB routing check: ${_isUsbRouted ? "routed" : "not routed"}',
          tag: 'USB');
      return _isUsbRouted;
    } catch (e) {
      _log.error('checkUsbRouted failed: $e', tag: 'USB');
      return false;
    }
  }

  // ── Hardware Sample Rate methods ──

  /// Get the native sample rate used by Android's AudioTrack for STREAM_MUSIC.
  /// This tells us what the Android mixer is outputting at.
  Future<int> getOutputSampleRate() async {
    try {
      final result = await _channel.invokeMethod<int>('getOutputSampleRate');
      return result ?? 0;
    } catch (e) {
      _log.error('getOutputSampleRate error: $e', tag: 'HiResAudio');
      return 0;
    }
  }

  /// Get the active output device's hardware sample rate.
  /// Queries the actual sample rate of the physical output (speaker, USB DAC, etc.).
  Future<int> getHardwareSampleRate() async {
    try {
      final result = await _channel.invokeMethod<int>('getHardwareSampleRate');
      return result ?? 0;
    } catch (e) {
      _log.error('getHardwareSampleRate error: $e', tag: 'HiResAudio');
      return 0;
    }
  }

  /// Enable or disable the AAudio exclusive AudioSink for true bit-perfect playback.
  /// When enabled, ExoPlayer will route decoded PCM audio to the AAudio
  /// exclusive stream instead of the default Android AudioTrack.
  Future<void> setUseAaudioSink(bool enabled) async {
    try {
      await _channel.invokeMethod('setUseAaudioSink', {'enabled': enabled});
    } catch (e) {
      _log.error('setUseAaudioSink error: $e', tag: 'HiResAudio');
    }
  }

  /// Enable or disable bit-perfect mode in the AAudio AudioSink.
  ///
  /// When enabled, the AudioSink will skip ALL digital volume gain on PCM data,
  /// ensuring the audio output is bit-identical to the source file.
  /// Must be used together with [setUseAaudioSink] and exclusive mode.
  /// Only takes effect on the next ExoPlayer creation (next play() call).
  Future<void> setBitPerfectMode(bool enabled) async {
    try {
      await _channel.invokeMethod('setBitPerfectMode', {'enabled': enabled});
    } catch (e) {
      _log.error('setBitPerfectMode error: $e', tag: 'HiResAudio');
    }
  }

  /// Test the PreferredMixerAttributes API on a specific USB device.
  /// Returns a human-readable result string.
  Future<String> testPreferredMixerAttributes({
    required int deviceId,
    required int sampleRate,
    required int bitDepth,
  }) async {
    try {
      final result = await _channel.invokeMethod<Map>(
        'setPreferredMixerAttributes',
        {
          'deviceId': deviceId,
          'sampleRate': sampleRate,
          'bitDepth': bitDepth,
        },
      );
      if (result == null) return '❌ No response from native plugin';
      final success = result['success'] == true;
      final apiSupported = result['apiSupported'] == true;
      if (!apiSupported) {
        return '❌ API not supported (requires Android 14+)';
      }
      return success
          ? '✅ Bit-perfect mixer attributes APPLIED'
          : '⚠️ API supported but REJECTED by system';
    } catch (e) {
      _log.error('testPreferredMixerAttributes failed: $e', tag: 'USB');
      return '❌ Test failed: ${e.toString().replaceAll('Exception: ', '')}';
    }
  }

  /// Release the native ExoPlayer instance.
  Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
      _isPlaying = false;
    } catch (e) {
      _log.error('release error: $e', tag: 'HiResAudio');
    }
  }

  /// Clean up resources.
  void dispose() {
    release();
    _playbackStateController.close();
    _formatInfoController.close();
    _bufferingController.close();
    _errorController.close();
    _usbDevicesController.close();
    _usbRoutingController.close();
    _outputDeviceController.close();
  }
}

/// A connected USB audio device.
class UsbAudioDevice {
  final int id;
  final String productName;
  final String address;
  final String type;
  final int maxChannelCount;
  final int maxSampleRate;

  const UsbAudioDevice({
    required this.id,
    required this.productName,
    required this.address,
    required this.type,
    this.maxChannelCount = 0,
    this.maxSampleRate = 0,
  });

  factory UsbAudioDevice.fromMap(Map map) {
    return UsbAudioDevice(
      id: (map['id'] as int?) ?? 0,
      productName: (map['productName'] as String?) ?? 'Unknown',
      address: (map['address'] as String?) ?? '',
      type: (map['type'] as String?) ?? 'other',
      maxChannelCount: (map['channelCounts'] as int?) ?? 0,
      maxSampleRate: (map['sampleRates'] as int?) ?? 0,
    );
  }

  @override
  String toString() => 'UsbAudioDevice($productName, $maxSampleRate Hz, ${maxChannelCount}ch)';
}

/// USB audio routing state.
class UsbRoutingState {
  final bool routed;
  final String deviceName;
  final bool mixerAttributesApplied;

  const UsbRoutingState({
    this.routed = false,
    this.deviceName = '',
    this.mixerAttributesApplied = false,
  });
}

/// Audio format info reported by the native hi-res player.
class HiResFormatInfo {
  final int sampleRate;
  final int bitDepth;
  final int channels;

  const HiResFormatInfo({
    this.sampleRate = 0,
    this.bitDepth = 0,
    this.channels = 2,
  });

  bool get isValid => sampleRate > 0;

  @override
  String toString() =>
      'HiResFormatInfo(${sampleRate}Hz, ${bitDepth}bit, ${channels}ch)';
}
