import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/usb_dac_service.dart';
import '../services/usb_dac_audio_manager.dart';

/// Provider for the UsbDacAudioManager singleton.
final usbDacAudioManagerProvider = Provider<UsbDacAudioManager>((ref) {
  return UsbDacAudioManager.instance;
});

/// Provider for the UsbDacService singleton.
final usbDacServiceProvider = Provider<UsbDacService>((ref) {
  return UsbDacService.instance;
});

/// Stream provider that emits the USB DAC manager state reactively.
///
/// Tracks:
/// - Connection state (connected / disconnected)
/// - Streaming state (active / inactive)
/// - Device name
/// - Initialization status
final usbDacManagerStateProvider = StreamProvider<UsbDacManagerState>((ref) {
  final manager = ref.watch(usbDacAudioManagerProvider);
  return manager.stateStream;
});

/// Stream provider that emits the list of connected USB audio devices.
///
/// Fires when devices are plugged in or unplugged.
final usbDacDevicesProvider = StreamProvider<List<UsbDacDevice>>((ref) {
  final service = ref.watch(usbDacServiceProvider);
  return service.devicesStream;
});

/// Stream provider that emits the USB DAC state (connected, active, format info).
final usbDacStateProvider = StreamProvider<UsbDacState>((ref) {
  final service = ref.watch(usbDacServiceProvider);
  return service.stateStream;
});

/// A computed provider that emits the active bit-perfect source.
///
/// Returns a string describing which audio path is currently providing
/// bit-perfect audio: 'libusb_usb_dac', 'aaudio_exclusive', 'preferred_mixer', or 'none'.
final activeBitPerfectSourceProvider = Provider<String>((ref) {
  final managerState = ref.watch(usbDacManagerStateProvider);
  final dacManagerState = managerState.when(
    data: (s) => s,
    loading: () => const UsbDacManagerState(),
    error: (_, __) => const UsbDacManagerState(),
  );

  if (dacManagerState.dacActive) return 'libusb_usb_dac';

  return 'none';
});

/// Provider that checks whether the libusb USB DAC is the active audio output.
final isLibusbActiveProvider = Provider<bool>((ref) {
  final activeSource = ref.watch(activeBitPerfectSourceProvider);
  return activeSource == 'libusb_usb_dac';
});