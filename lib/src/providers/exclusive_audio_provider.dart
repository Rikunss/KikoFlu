import 'dart:async';
import 'dart:io' show Platform;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:audio_session/audio_session.dart';
import '../services/exclusive_audio_service.dart';
import '../services/hi_res_audio_service.dart';

/// Stream provider that emits the exclusive audio mode state reactively.
///
/// Watches [ExclusiveAudioService.stateStream] for changes to:
/// - [ExclusiveModeState.enabled]
/// - [ExclusiveModeState.aaudioExclusive]
/// - [ExclusiveModeState.aaudioActive]
/// - [ExclusiveModeState.aaudioAvailable]
/// - etc.
final exclusiveAudioStateProvider = StreamProvider<ExclusiveModeState>((ref) {
  return ExclusiveAudioService.instance.stateStream;
});

/// Stream provider that emits the currently active USB DAC name reactively.
///
/// Emits an empty string when no USB DAC is connected.
/// Fires automatically when a USB DAC is plugged in or unplugged,
/// without requiring the user to close and reopen any UI.
final activeUsbDacNameProvider = StreamProvider<String>((ref) {
  final controller = StreamController<String>();
  final ex = ExclusiveAudioService.instance;
  final hiRes = HiResAudioService.instance;

  // Emit current value immediately
  controller.add(ex.activeUsbDacName);

  // Listen for USB attach events from ExclusiveAudioService
  // (only fires when exclusive mode is enabled)
  final attachSub = ex.usbAttachedStream.listen((name) {
    controller.add(name);
  });

  // Listen for USB detach events from ExclusiveAudioService
  final detachSub = ex.usbDetachedStream.listen((_) {
    controller.add('');
  });

  // Listen for USB device list changes from HiResAudioService.
  // This fires on every USB attach/detach regardless of exclusive mode,
  // ensuring the provider emits even when exclusive mode is OFF.
  final usbDevicesSub = hiRes.usbDevicesStream.listen((devices) {
    if (devices.isNotEmpty) {
      controller.add(devices.first.productName);
    } else {
      controller.add('');
    }
  });

  ref.onDispose(() {
    attachSub.cancel();
    detachSub.cancel();
    usbDevicesSub.cancel();
    controller.close();
  });

  return controller.stream;
});

/// Stream provider that emits the hi-res USB routing state reactively.
///
/// Tracks whether audio is currently routed to a USB DAC via the
/// Hi-Res ExoPlayer pathway.
final hiResUsbRoutingProvider = StreamProvider<UsbRoutingState>((ref) {
  return HiResAudioService.instance.usbRoutingStream;
});

/// Stream provider that emits the hi-res playback state (isPlaying) reactively.
final hiResPlaybackStateProvider = StreamProvider<bool>((ref) {
  return HiResAudioService.instance.playbackStateStream;
});

/// Stream provider that emits the active audio output device type reactively.
///
/// Values: 'usb_dac', 'usb_detected', 'wired_headphones', 'bluetooth',
///         'builtin', 'speaker', 'headphones', 'unknown'
///
/// On Android: fires instantly via native AudioManager callback when
/// headphones/USB DAC/Bluetooth are plugged/unplugged.
/// On desktop: uses AudioSession's becomingNoisy events and platform APIs.
final activeOutputDeviceProvider = StreamProvider<String>((ref) {
  // On Android, use the native HiResAudioService for precise device detection
  if (Platform.isAndroid) {
    return HiResAudioService.instance.outputDeviceStream;
  }

  // On desktop/iOS, create a lightweight controller that listens to
  // AudioSession events and provides basic device type info.
  final controller = StreamController<String>.broadcast();

  // Emit 'speaker' as initial default (conservative assumption)
  controller.add('speaker');

  // Listen for headphone unplug events via AudioSession
  AudioSession.instance.then((session) {
    session.becomingNoisyEventStream.listen((_) {
      // becomingNoisy fires when headphones are UNPLUGGED → speaker now
      if (!controller.isClosed) controller.add('speaker');
    });
  }).catchError((_) {
    // AudioSession not available on this platform — keep default
  });

  ref.onDispose(() => controller.close());

  return controller.stream;
});
