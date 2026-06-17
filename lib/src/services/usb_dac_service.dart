import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';
import 'log_service.dart';

/// Service that wraps the native Android USB DAC plugin.
///
/// Provides direct USB Audio Class (UAC) communication with external USB DACs,
/// bypassing the Android audio mixer for bit-perfect audio output.
///
/// Uses:
/// - Android USB Host API (UsbManager) for device enumeration and permission
/// - Native C++ libusb driver for isochronous USB audio streaming
///
/// Architecture:
/// ```
/// Flutter/Dart: UsbDacService
///   ↕ MethodChannel "com.kikoeru.flutter/usb_dac"
/// Kotlin: UsbDacPlugin
///   ↕ JNI
/// C++ NDK: usb_dac_driver (libusb)
///   ↕ libusb (linux_usbfs backend)
/// USB DAC Hardware
/// ```
///
/// Only available on Android with USB Host support (API 12+).
final _log = LogService.instance;

/// A connected USB audio device.
class UsbDacDevice {
  final int deviceId;
  final String productName;
  final int vendorId;
  final int productId;
  final int deviceProtocol;
  final String serialNumber;
  final bool hasPermission;
  final List<UsbAudioEndpoint> audioEndpoints;

  const UsbDacDevice({
    required this.deviceId,
    required this.productName,
    this.vendorId = 0,
    this.productId = 0,
    this.deviceProtocol = 0,
    this.serialNumber = '',
    this.hasPermission = false,
    this.audioEndpoints = const [],
  });

  factory UsbDacDevice.fromMap(Map map) {
    final endpoints = (map['audioEndpoints'] as List?)
            ?.map((e) => UsbAudioEndpoint.fromMap(e as Map))
            .toList() ??
        [];
    return UsbDacDevice(
      deviceId: (map['deviceId'] as int?) ?? 0,
      productName: (map['productName'] as String?) ?? 'Unknown',
      vendorId: (map['vendorId'] as int?) ?? 0,
      productId: (map['productId'] as int?) ?? 0,
      deviceProtocol: (map['deviceProtocol'] as int?) ?? 0,
      serialNumber: (map['serialNumber'] as String?) ?? '',
      hasPermission: (map['hasPermission'] as bool?) ?? false,
      audioEndpoints: endpoints,
    );
  }

  @override
  String toString() =>
      'UsbDacDevice($productName, vendor=${vendorId.toRadixString(16)}:${productId.toRadixString(16)}, hasPermission=$hasPermission)';
}

/// A USB audio endpoint descriptor.
class UsbAudioEndpoint {
  final int address;
  final int type;
  final int maxPacketSize;

  const UsbAudioEndpoint({
    required this.address,
    required this.type,
    required this.maxPacketSize,
  });

  factory UsbAudioEndpoint.fromMap(Map map) {
    return UsbAudioEndpoint(
      address: (map['address'] as int?) ?? 0,
      type: (map['type'] as int?) ?? 0,
      maxPacketSize: (map['maxPacketSize'] as int?) ?? 0,
    );
  }
}

/// USB DAC connection state.
class UsbDacState {
  final bool connected;
  final bool active;
  final String deviceName;
  final int sampleRate;
  final int channelCount;
  final int bitDepth;

  const UsbDacState({
    this.connected = false,
    this.active = false,
    this.deviceName = '',
    this.sampleRate = 0,
    this.channelCount = 0,
    this.bitDepth = 0,
  });

  bool get isBitPerfect => connected && active;
}

class UsbDacService {
  static UsbDacService? _instance;
  static UsbDacService get instance =>
      _instance ??= UsbDacService._();

  static const MethodChannel _channel =
      MethodChannel('com.kikoeru.flutter/usb_dac');

  final StreamController<UsbDacState> _stateController =
      StreamController<UsbDacState>.broadcast();
  final StreamController<List<UsbDacDevice>> _devicesController =
      StreamController<List<UsbDacDevice>>.broadcast();
  final StreamController<String> _errorController =
      StreamController<String>.broadcast();

  bool _connected = false;
  bool _active = false;
  String _deviceName = '';
  int _lastDeviceId = 0;
  bool _canReconnect = false;

  UsbDacService._() {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Stream of USB DAC state changes.
  Stream<UsbDacState> get stateStream => _stateController.stream;

  /// Stream of device list changes.
  Stream<List<UsbDacDevice>> get devicesStream => _devicesController.stream;

  /// Stream of error messages.
  Stream<String> get errorStream => _errorController.stream;

  /// Whether a USB DAC is currently connected.
  bool get isConnected => _connected;

  /// Whether the USB DAC is actively streaming.
  bool get isActive => _active;

  /// The name of the connected USB DAC.
  String get deviceName => _deviceName;

  /// Whether the last disconnect was clean and can be reconnected (true if device
  /// was unplugged, false if explicitly disconnected by user).
  bool get canReconnect => _canReconnect;

  /// The device ID of the last connected DAC (0 if none).
  int get lastDeviceId => _lastDeviceId;

  /// Handle incoming method calls from native side (events).
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onDeviceConnected':
        final args = call.arguments;
        if (args is! Map) break;
        _connected = true;
        _canReconnect = false;
        _deviceName = (args['deviceName'] as String?) ?? 'USB DAC';
        // Only set active=true if streaming was already started.
        // This event fires after connect() succeeds but BEFORE start().
        // The start() method will emit .active=true separately.
        _stateController.add(UsbDacState(
          connected: true,
          active: _active, // preserve current streaming state
          deviceName: _deviceName,
          sampleRate: (args['sampleRate'] as int?) ?? 0,
          channelCount: (args['channelCount'] as int?) ?? 0,
          bitDepth: (args['bitDepth'] as int?) ?? 0,
        ));
        _log.info('USB DAC connected: $_deviceName', tag: 'UsbDac');
        break;
      case 'onDeviceDisconnected':
        final args = call.arguments;
        // Store disconnect metadata BEFORE clearing state
        _canReconnect = (args is Map) && (args['canReconnect'] == true);
        _connected = false;
        _active = false;
        _deviceName = (args is Map) ? (args['deviceName'] as String? ?? _deviceName) : _deviceName;
        _stateController.add(const UsbDacState());
        _log.info('USB DAC disconnected (canReconnect: $_canReconnect)', tag: 'UsbDac');
        break;
      case 'onDeviceAttached':
        final args = call.arguments;
        if (args is! Map) break;
        final devicesList = (args['devices'] as List?) ?? [];
        final devices = devicesList
            .map((d) => UsbDacDevice.fromMap(d as Map))
            .toList();
        _log.info('USB device attached with ${devices.length} audio device(s)', tag: 'UsbDac');
        _devicesController.add(devices);
        break;
      case 'onDeviceListRefreshed':
        final args = call.arguments;
        if (args is! Map) break;
        final devicesList = (args['devices'] as List?) ?? [];
        final devices = devicesList
            .map((d) => UsbDacDevice.fromMap(d as Map))
            .toList();
        _log.info('USB device list refreshed: ${devices.length} device(s) (permission may have updated metadata)',
            tag: 'UsbDac');
        // Log permission status for each device
        for (final d in devices) {
          _log.info('  └ #${d.deviceId} ${d.productName} (hasPermission=${d.hasPermission}, serial=${d.serialNumber})',
              tag: 'UsbDac');
        }
        _devicesController.add(devices);
        break;
      case 'onPermissionResult':
        final args = call.arguments;
        if (args is! Map) break;
        final deviceId = args['deviceId'];
        final deviceName = args['deviceName'] ?? 'Unknown';
        final granted = args['granted'] == true;
        final hasPermission = args['hasPermission'] == true;
        _log.info('USB permission result: device #$deviceId ($deviceName)'
            ', EXTRA_PERMISSION_GRANTED=$granted'
            ', hasPermission=$hasPermission',
            tag: 'UsbDac');
        break;
      case 'onError':
        final args = call.arguments;
        if (args is! Map) break;
        final message = (args['message'] as String?) ?? 'Unknown error';
        _errorController.add(message);
        _log.error('USB DAC error: $message', tag: 'UsbDac');
        break;
      default:
        break;
    }
    return null;
  }

  /// Check if USB DAC is supported on this device.
  Future<bool> isSupported() async {
    try {
      final result = await _channel.invokeMethod<bool>('isSupported');
      return result == true;
    } catch (e) {
      _log.error('isSupported error: $e', tag: 'UsbDac');
      return false;
    }
  }

  /// Get the list of connected USB audio devices.
  Future<List<UsbDacDevice>> getDevices() async {
    try {
      final result = await _channel.invokeMethod<List>('getDevices');
      if (result == null) return [];
      final devices = result
          .map((d) => UsbDacDevice.fromMap(d as Map))
          .toList();
      _log.info('Found ${devices.length} USB audio device(s)', tag: 'UsbDac');
      return devices;
    } catch (e) {
      _log.error('getDevices error: $e', tag: 'UsbDac');
      return [];
    }
  }

  /// Request permission to access a USB audio device.
  /// The user will see a system dialog.
  ///
  /// This now properly waits for the user to respond to the dialog before
  /// returning (the Kotlin side stores the MethodChannel result and resolves
  /// it from the broadcast receiver).
  ///
  /// If the user doesn't respond within 30 seconds, times out and returns
  /// false as a safety measure.
  Future<bool> requestPermission(int deviceId) async {
    _log.info('requestPermission(deviceId=$deviceId) called — awaiting user response...',
        tag: 'UsbDac');
    try {
      final result = await _channel
          .invokeMethod<bool>('requestPermission', {
            'deviceId': deviceId,
          })
          .timeout(const Duration(seconds: 30));
      if (result == true) {
        _log.info('USB permission GRANTED for device #$deviceId',
            tag: 'UsbDac');
      } else {
        _log.warning('USB permission DENIED for device #$deviceId',
            tag: 'UsbDac');
      }
      return result == true;
    } on TimeoutException {
      _log.warning('requestPermission timed out after 30s for device #$deviceId',
          tag: 'UsbDac');
      return false;
    } catch (e) {
      _log.error('requestPermission error for device #$deviceId: $e',
          tag: 'UsbDac');
      return false;
    }
  }

  /// Check if USB permission has already been granted for the given device.
  Future<bool> hasPermission(int deviceId) async {
    try {
      final result = await _channel.invokeMethod<bool>('hasPermission', {
        'deviceId': deviceId,
      });
      return result == true;
    } catch (e) {
      _log.error('hasPermission error: $e', tag: 'UsbDac');
      return false;
    }
  }

  /// Set the last known device ID (used for reconnection targeting).
  void setLastDeviceId(int deviceId) {
    _lastDeviceId = deviceId;
  }

  /// Connect to a USB audio device and prepare for streaming.
  Future<bool> connect(int deviceId, {
    int sampleRate = 48000,
    int channels = 2,
    int bitDepth = 16,
  }) async {
    try {
      final result = await _channel.invokeMethod<bool>('connect', {
        'deviceId': deviceId,
        'sampleRate': sampleRate,
        'channels': channels,
        'bitDepth': bitDepth,
      });
      if (result == true) {
        _connected = true;
      }
      return result == true;
    } catch (e) {
      _log.error('connect error: $e', tag: 'UsbDac');
      return false;
    }
  }

  /// Disconnect from the USB DAC.
  Future<void> disconnect() async {
    try {
      await _channel.invokeMethod('disconnect');
      _connected = false;
      _active = false;
    } catch (e) {
      _log.error('disconnect error: $e', tag: 'UsbDac');
    }
  }

  /// Check if a USB DAC is currently connected.
  Future<bool> isConnectedAsync() async {
    try {
      final result = await _channel.invokeMethod<bool>('isConnected');
      _connected = result == true;
      return _connected;
    } catch (e) {
      _log.error('isConnected error: $e', tag: 'UsbDac');
      return false;
    }
  }

  /// Start USB DAC audio streaming.
  /// Emits updated state with [active] set to true on success.
  Future<bool> start() async {
    try {
      final result = await _channel.invokeMethod<bool>('start');
      _active = result == true;
      if (_active) {
        _log.info('USB DAC streaming started', tag: 'UsbDac');
        _stateController.add(UsbDacState(
          connected: _connected,
          active: _active,
          deviceName: _deviceName,
        ));
      }
      return result == true;
    } catch (e) {
      _log.error('start error: $e', tag: 'UsbDac');
      return false;
    }
  }

  /// Stop USB DAC audio streaming.
  /// Emits updated state with [active] set to false.
  Future<void> stop() async {
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      _log.error('stop error: $e', tag: 'UsbDac');
    }
    _active = false;
    _log.info('USB DAC streaming stopped', tag: 'UsbDac');
    _stateController.add(UsbDacState(
      connected: _connected,
      active: false,
      deviceName: _deviceName,
    ));
  }

  /// Write PCM float data directly to the USB DAC.
  Future<int> writePcmFloat(Float32List buffer, int numFrames) async {
    try {
      final result = await _channel.invokeMethod<int>('writePcmFloat', {
        'buffer': buffer,
        'numFrames': numFrames,
      });
      return result ?? 0;
    } catch (e) {
      _log.error('writePcmFloat error: $e', tag: 'UsbDac');
      return -1;
    }
  }

  /// Write PCM I16 data directly to the USB DAC.
  Future<int> writePcmI16(Int16List buffer, int numFrames) async {
    try {
      final result = await _channel.invokeMethod<int>('writePcmI16', {
        'buffer': buffer,
        'numFrames': numFrames,
      });
      return result ?? 0;
    } catch (e) {
      _log.error('writePcmI16 error: $e', tag: 'UsbDac');
      return -1;
    }
  }

  /// Get the current USB DAC status.
  Future<UsbDacState> getStatus() async {
    try {
      final result = await _channel.invokeMethod<Map>('getStatus');
      if (result != null) {
        _connected = result['connected'] == true;
        _active = result['active'] == true;
        _deviceName = (result['deviceName'] as String?) ?? '';
        return UsbDacState(
          connected: _connected,
          active: _active,
          deviceName: _deviceName,
        );
      }
    } catch (e) {
      _log.error('getStatus error: $e', tag: 'UsbDac');
    }
    return const UsbDacState();
  }

  /// Release all resources.
  Future<void> release() async {
    try {
      await _channel.invokeMethod('release');
    } catch (e) {
      _log.error('release error: $e', tag: 'UsbDac');
    }
    _connected = false;
    _active = false;
    _deviceName = '';
  }

  /// Clean up resources.
  void dispose() {
    unawaited(release());
    _stateController.close();
    _devicesController.close();
    _errorController.close();
  }
}
