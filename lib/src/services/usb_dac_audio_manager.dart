import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' show min;
import 'dart:typed_data';
import 'package:shared_preferences/shared_preferences.dart';

import '../providers/settings_provider.dart';
import 'usb_dac_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Integration manager that bridges [UsbDacService] (libusb-based USB DAC
/// bit-perfect audio) with the existing audio pipeline ([AudioPlayerService],
/// [HiResAudioService], [ExclusiveAudioService]).
///
/// Responsibilities:
/// 1. Monitors USB DAC device connection state via [UsbDacService]
/// 2. When a USB DAC is detected AND [BitPerfectPlaybackSettings] is enabled,
///    auto-initializes the DAC and prepares for streaming
/// 3. When the DAC disconnects, falls back to system default audio output
/// 4. Manages audio routing priority: libusb USB DAC > AAudio Exclusive > System default
/// 5. Provides unified status updates for the Audio Info sheet
///
/// Audio routing priority:
///   libusb (UsbDacService)  →  AAudio Exclusive  →  Hi-Res ExoPlayer  →  System default
///   (true bit-perfect)         (mixer bypass)        (high quality)       (normal)
///
/// The priority is determined by what's available and enabled:
/// - If libusb USB DAC is connected AND bit-perfect enabled → use libusb
/// - Else if AAudio exclusive mode enabled → use AAudio exclusive
/// - Else if hi-res ExoPlayer is active → use ExoPlayer
/// - Else → system default (just_audio)
class UsbDacAudioManager {
  static UsbDacAudioManager? _instance;
  static UsbDacAudioManager get instance =>
      _instance ??= UsbDacAudioManager._();

  // ── Dependencies ──
  final UsbDacService _usbDac = UsbDacService.instance;

  // ── State ──
  bool _initialized = false;
  bool _autoDacEnabled = false;
  String _activeDeviceName = '';
  /// The device ID of the currently active USB DAC (0 if none).
  /// Written during connection/reconnection for use by reconnect logic.
  // ignore: unused_field
  int _activeDeviceId = 0;
  int _lastVendorId = 0;
  int _lastProductId = 0;
  UsbDacState _currentDacState = const UsbDacState();

  // ── Auto-Reconnect State ──
  bool _isReconnecting = false;
  int _reconnectAttempt = 0;
  static const int _maxReconnectAttempts = 10;
  static const int _reconnectBaseDelayMs = 500;      // 0.5s first attempt
  static const int _reconnectMaxDelayMs = 30 * 1000;  // 30s cap
  Timer? _reconnectTimer;

  // Stream subscriptions
  StreamSubscription<List<UsbDacDevice>>? _devicesSub;
  StreamSubscription<UsbDacState>? _stateSub;
  StreamSubscription<String>? _errorSub;

  // Broadcast stream for external listeners (UI)
  final StreamController<UsbDacManagerState> _stateController =
      StreamController<UsbDacManagerState>.broadcast();

  UsbDacAudioManager._();

  /// Stream of USB DAC manager state.
  Stream<UsbDacManagerState> get stateStream => _stateController.stream;

  /// Whether a USB DAC is currently connected and ready.
  bool get isDacConnected => _currentDacState.connected;

  /// Whether the USB DAC is actively streaming audio.
  bool get isDacActive => _currentDacState.active;

  /// Name of the connected USB DAC device.
  String get activeDeviceName => _activeDeviceName;

  /// Whether auto-DAC mode is enabled.
  bool get autoDacEnabled => _autoDacEnabled;

  /// Current USB DAC state.
  UsbDacState get currentDacState => _currentDacState;

  /// Initialize the manager.
  /// Call this once during app startup (in main.dart).
  Future<void> initialize() async {
    if (_initialized) return;
    if (!Platform.isAndroid) {
      _log.info('UsbDacAudioManager: not Android, skipping', tag: 'UsbDacMgr');
      return;
    }

    _log.info('UsbDacAudioManager: initializing...', tag: 'UsbDacMgr');

    // Check if UsbDacService is supported
    final supported = await _usbDac.isSupported();
    if (!supported) {
      _log.warning('UsbDacAudioManager: UsbDacService not supported',
          tag: 'UsbDacMgr');
      return;
    }

    // Listen for USB device changes
    _devicesSub = _usbDac.devicesStream.listen((devices) {
      _onDevicesChanged(devices);
    });

    // Listen for USB DAC state changes
    _stateSub = _usbDac.stateStream.listen((state) {
      _currentDacState = state;
      _emitState();
    });

    // Listen for error events
    _errorSub = _usbDac.errorStream.listen((error) {
      _log.error('UsbDacAudioManager: $error', tag: 'UsbDacMgr');
    });

    // Set _initialized = true dulu agar setAutoDacEnabled() bisa jalan
    _initialized = true;

    // Cek apakah USB DAC Routing aktif di sesi sebelumnya (SharedPreferences).
    // Jika iya, panggil setAutoDacEnabled(true) → getDevices() →
    // requestPermission() → system dialog izin USB muncul (via libusb path).
    //
    // Ini menangani skenario: user colok USB DAC SEBELUM buka aplikasi.
    // Tanpa ini, tidak ada broadcast ACTION_USB_DEVICE_ATTACHED yang terkirim,
    // jadi UsbDacPlugin tidak tahu ada DAC yang perlu di-initialize.
    //
    // Key: 'bit_perfect_playback_enabled' (dari BitPerfectPlaybackNotifier)
    final prefs = await SharedPreferences.getInstance();
    final wasEnabled = prefs.getBool('bit_perfect_playback_enabled') ?? false;
    if (wasEnabled) {
      _log.info('UsbDacAudioManager: routing enabled — starting USB DAC init via libusb',
          tag: 'UsbDacMgr');
      // Ini akan memicu system dialog USB permission (jika belum pernah di-grant)
      // dan init driver libusb (connect + start).
      // _activeDeviceName di-set oleh _connectToDac().
      await setAutoDacEnabled(true);
    } else {
      // Routing OFF — initial scan tanpa auto-connect
      final devices = await _usbDac.getDevices();
      if (devices.isNotEmpty) {
        _onDevicesChanged(devices);
      }
    }

    _log.info('UsbDacAudioManager: initialized', tag: 'UsbDacMgr');
  }

  /// Enable or disable the auto USB DAC mode.
  /// When enabled, the manager will automatically connect to the first
  /// available USB DAC and route audio through the libusb bit-perfect path.
  Future<void> setAutoDacEnabled(bool enabled) async {
    if (!_initialized) return;
    _autoDacEnabled = enabled;

    if (enabled) {
      _log.info('UsbDacAudioManager: auto-DAC enabled', tag: 'UsbDacMgr');
      // Try to auto-connect if a device is available
      final devices = await _usbDac.getDevices();
      if (devices.isNotEmpty) {
        await _connectToDac(devices.first);
      }
    } else {
      _log.info('UsbDacAudioManager: auto-DAC disabled', tag: 'UsbDacMgr');
      await _disconnectDac();
    }

    _emitState();
  }

  /// Manually connect to a specific USB DAC device.
  Future<bool> connectToDevice(int deviceId, {
    int sampleRate = 48000,
    int channels = 2,
    int bitDepth = 24,
  }) async {
    if (!_initialized) return false;

    // First request USB permission from Android system
    final permissionGranted = await _usbDac.requestPermission(deviceId);
    if (!permissionGranted) {
      _log.error('Permission denied for USB device #$deviceId',
          tag: 'UsbDacMgr');
      return false;
    }

    // Permission granted! Jangan panggil _usbDac.connect() + _usbDac.start()
    // karena itu akan meng-claim USB interface via libusb driver, yang mencegah
    // decent-player UsbAudioSink mengakses device yang sama.
    //
    // Sebaliknya, langsung update state → trigger _libusbStateSub
    // → setUseLibusbSink(true) → ExoPlayer recreate dengan decent-player sink
    // → decent-player UsbAudioSink handle USB connection sendiri.

    _log.info('USB DAC permission granted — triggering ExoPlayer recreation via decent-player UsbAudioSink',
        tag: 'UsbDacMgr');

    // Update state for reconnection tracking
    _activeDeviceId = deviceId;
    _usbDac.setLastDeviceId(deviceId);
    // Set connected+active state to trigger _libusbStateSub
    _currentDacState = UsbDacState(
      connected: true,
      active: true,
      deviceName: _activeDeviceName,
      sampleRate: sampleRate,
      channelCount: channels,
      bitDepth: bitDepth,
    );
    _emitState();
    return true;
  }

  /// Disconnect from the current USB DAC and fall back to system audio.
  Future<void> disconnect() async {
    await _disconnectDac();
  }

  /// Called when audio pipeline has decoded PCM data ready to play.
  /// Writes float PCM data directly to the USB DAC.
  ///
  /// Returns the number of frames written, or -1 on error.
  /// Returns 0 if the DAC is not active (data goes to normal audio path).
  int writePcmFloat(Float32List buffer, int numFrames) {
    if (!_currentDacState.active) return 0;
    return _usbDac.writePcmFloat(buffer, numFrames) as int;
  }

  /// Called when audio pipeline has I16 PCM data ready to play.
  int writePcmI16(Int16List buffer, int numFrames) {
    if (!_currentDacState.active) return 0;
    return _usbDac.writePcmI16(buffer, numFrames) as int;
  }

  /// Get the current combined status of the USB DAC manager.
  UsbDacManagerStatus getStatus() {
    return UsbDacManagerStatus(
      isInitialized: _initialized,
      autoDacEnabled: _autoDacEnabled,
      dacConnected: _currentDacState.connected,
      dacActive: _currentDacState.active,
      deviceName: _activeDeviceName,
      sampleRate: _currentDacState.sampleRate,
      channelCount: _currentDacState.channelCount,
      bitDepth: _currentDacState.bitDepth,
    );
  }

  // ── Private ──

  void _onDevicesChanged(List<UsbDacDevice> devices) {
    _log.info('USB DAC devices changed: ${devices.length} device(s)',
        tag: 'UsbDacMgr');

    final hasDac = devices.isNotEmpty;
    final deviceName = devices.isNotEmpty ? devices.first.productName : '';

    if (hasDac && !_currentDacState.connected) {
      // USB DAC was just plugged in (or reconnected)
      _log.info('USB DAC connected: $deviceName', tag: 'UsbDacMgr');
      _activeDeviceName = deviceName;

      // Cancel any ongoing reconnect timer — we connected successfully
      _cancelReconnect();

      // Auto-connect if auto-DAC mode is enabled
      if (_autoDacEnabled) {
        _connectToDac(devices.first);
      }
    } else if (!hasDac && _currentDacState.connected) {
      // USB DAC was just unplugged
      _log.info('USB DAC disconnected', tag: 'UsbDacMgr');
      _activeDeviceName = '';
      _activeDeviceId = 0;
      _disconnectDac();

      // Start auto-reconnect if enabled
      if (_autoDacEnabled && _usbDac.canReconnect) {
        _startReconnect();
      }
    } else if (hasDac && _currentDacState.connected) {
      // Same device still connected
      _activeDeviceName = deviceName;
    } else if (hasDac && !_currentDacState.connected && _isReconnecting) {
      // Device appeared while we were waiting to retry — try immediately
      _log.info('USB DAC appeared during reconnect backoff — connecting now', tag: 'UsbDacMgr');
      _cancelReconnect();
      _activeDeviceName = deviceName;
      if (_autoDacEnabled) {
        _connectToDac(devices.first);
      }
    }

    _emitState();
  }

  Future<void> _connectToDac(UsbDacDevice device) async {
    _log.info('Auto-connecting to USB DAC: ${device.productName}',
        tag: 'UsbDacMgr');
    _activeDeviceName = device.productName;
    await connectToDevice(
      device.deviceId,
      sampleRate: 48000,
      channels: 2,
      bitDepth: 16,
    );
  }

  Future<void> _disconnectDac() async {
    if (!_currentDacState.connected) return;

    await _usbDac.stop();
    await _usbDac.disconnect();
    _log.info('USB DAC disconnected', tag: 'UsbDacMgr');
  }

  // ── Auto-Reconnect ──

  /// Start auto-reconnect with exponential backoff.
  /// Called when a USB DAC disconnects while auto-DAC mode is enabled.
  void _startReconnect() {
    if (_isReconnecting) return; // Already trying

    _reconnectAttempt = 0;
    _isReconnecting = true;
    _log.info('Auto-reconnect started (max $_maxReconnectAttempts attempts)', tag: 'UsbDacMgr');
    _emitState();
    _scheduleReconnect();
  }

  /// Schedule the next reconnect attempt with exponential backoff.
  void _scheduleReconnect() {
    if (!_isReconnecting) return;
    if (_reconnectAttempt >= _maxReconnectAttempts) {
      _log.warning('Auto-reconnect failed after $_maxReconnectAttempts attempts — giving up', tag: 'UsbDacMgr');
      _cancelReconnect();
      return;
    }

    // Exponential backoff: 500ms → 1s → 2s → 4s → ... → capped at 30s
    final delayMs = min(
      _reconnectBaseDelayMs * (1 << _reconnectAttempt),
      _reconnectMaxDelayMs,
    );

    _reconnectAttempt++;
    _log.info('Reconnect attempt $_reconnectAttempt/$_maxReconnectAttempts in ${delayMs}ms', tag: 'UsbDacMgr');

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(milliseconds: delayMs), () {
      _performReconnect();
    });
  }

  /// Attempt to reconnect to the USB DAC.
  Future<void> _performReconnect() async {
    if (!_isReconnecting || _currentDacState.connected) return;

    _log.info('Performing reconnect attempt $_reconnectAttempt...', tag: 'UsbDacMgr');

    try {
      // First, check if any audio device is connected now
      final devices = await _usbDac.getDevices();
      if (devices.isNotEmpty) {
        _log.info('Found ${devices.length} USB audio device(s) during reconnect', tag: 'UsbDacMgr');

        // Try to match by VID/PID first, then fall back to first device
        UsbDacDevice? targetDevice;
        if (_lastVendorId != 0 && _lastProductId != 0) {
          targetDevice = devices.cast<UsbDacDevice?>().firstWhere(
            (d) => d!.vendorId == _lastVendorId && d.productId == _lastProductId,
            orElse: () => null,
          );
        }
        targetDevice ??= devices.first;

        _activeDeviceName = targetDevice.productName;
        _activeDeviceId = targetDevice.deviceId;
        _usbDac.setLastDeviceId(targetDevice.deviceId);

        // Request permission (may fail if user hasn't granted yet)
        final permissionGranted = await _usbDac.requestPermission(targetDevice.deviceId);
        if (!permissionGranted) {
          _log.warning('Reconnect: permission denied for ${targetDevice.productName}', tag: 'UsbDacMgr');
          _scheduleReconnect(); // Try again later
          return;
        }

        // Permission granted! Skip libusb connect/start — decent-player handles USB.
        _log.info('USB DAC auto-reconnected: ${targetDevice.productName}', tag: 'UsbDacMgr');
        _activeDeviceId = targetDevice.deviceId;
        _usbDac.setLastDeviceId(targetDevice.deviceId);
        _currentDacState = UsbDacState(
          connected: true,
          active: true,
          deviceName: _activeDeviceName,
          sampleRate: 48000,
          channelCount: 2,
          bitDepth: 16,
        );
        _cancelReconnect();
        _emitState();
      } else {
        // No device yet — schedule next attempt
        _log.info('Reconnect: no USB audio devices found yet', tag: 'UsbDacMgr');
        _scheduleReconnect();
      }
    } catch (e) {
      _log.error('Reconnect attempt $_reconnectAttempt failed: $e', tag: 'UsbDacMgr');
      _scheduleReconnect();
    }
  }

  /// Cancel the auto-reconnect timer and reset state.
  void _cancelReconnect() {
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    _isReconnecting = false;
    _reconnectAttempt = 0;
  }

  /// Set the vendor/product IDs for device reconnection matching.
  /// Call this after connecting to a device so the auto-reconnect can
  /// identify the same device if it is reconnected.
  void setDeviceIds(int vendorId, int productId) {
    _lastVendorId = vendorId;
    _lastProductId = productId;
  }

  void _emitState() {
    _log.info('[USB-MGR] _emitState: '
        'dacConnected=${_currentDacState.connected}, '
        'dacActive=${_currentDacState.active}, '
        'autoDacEnabled=$_autoDacEnabled, '
        'deviceName="$_activeDeviceName", '
        'reconnecting=$_isReconnecting, '
        'attempt=$_reconnectAttempt/$_maxReconnectAttempts, '
        'lastVendorId=0x${_lastVendorId.toRadixString(16)}, '
        'lastProductId=0x${_lastProductId.toRadixString(16)}',
        tag: 'UsbDacMgr');

    _stateController.add(UsbDacManagerState(
      initialized: _initialized,
      autoDacEnabled: _autoDacEnabled,
      dacConnected: _currentDacState.connected,
      dacActive: _currentDacState.active,
      deviceName: _activeDeviceName,
      reconnecting: _isReconnecting,
      reconnectAttempt: _reconnectAttempt,
      maxReconnectAttempts: _maxReconnectAttempts,
    ));
  }

  /// Dispose resources.
  void dispose() {
    _cancelReconnect();
    _devicesSub?.cancel();
    _stateSub?.cancel();
    _errorSub?.cancel();
    _stateController.close();
  }
}

/// State of the USB DAC Manager.
class UsbDacManagerState {
  final bool initialized;
  final bool autoDacEnabled;
  final bool dacConnected;
  final bool dacActive;
  final String deviceName;
  final bool reconnecting;
  final int reconnectAttempt;
  final int maxReconnectAttempts;

  const UsbDacManagerState({
    this.initialized = false,
    this.autoDacEnabled = false,
    this.dacConnected = false,
    this.dacActive = false,
    this.deviceName = '',
    this.reconnecting = false,
    this.reconnectAttempt = 0,
    this.maxReconnectAttempts = 10,
  });

  /// Human-readable description of the USB DAC state.
  String get summary {
    if (!initialized) return 'Not initialized';
    if (reconnecting) return 'Reconnecting ($reconnectAttempt/$maxReconnectAttempts)';
    if (!dacConnected) return 'No USB DAC';
    if (dacActive) return 'Streaming to $deviceName';
    return 'Connected: $deviceName';
  }
}

/// Detailed status of the USB DAC manager.
class UsbDacManagerStatus {
  final bool isInitialized;
  final bool autoDacEnabled;
  final bool dacConnected;
  final bool dacActive;
  final String deviceName;
  final int sampleRate;
  final int channelCount;
  final int bitDepth;

  const UsbDacManagerStatus({
    this.isInitialized = false,
    this.autoDacEnabled = false,
    this.dacConnected = false,
    this.dacActive = false,
    this.deviceName = '',
    this.sampleRate = 0,
    this.channelCount = 0,
    this.bitDepth = 0,
  });

  bool get isBitPerfect => dacActive;
}
