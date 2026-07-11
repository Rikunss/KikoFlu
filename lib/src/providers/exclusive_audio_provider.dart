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

  controller.add(ex.activeUsbDacName);

  final attachSub = ex.usbAttachedStream.listen((name) {
    controller.add(name);
  });

  final detachSub = ex.usbDetachedStream.listen((_) {
    controller.add('');
  });

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
  final hiRes = HiResAudioService.instance;
  final controller = StreamController<UsbRoutingState>();
  controller.add(hiRes.lastUsbRoutingState);
  final sub = hiRes.usbRoutingStream.listen((state) {
    controller.add(state);
  });
  ref.onDispose(() {
    sub.cancel();
    controller.close();
  });
  return controller.stream;
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
  if (Platform.isAndroid) {
    final hiRes = HiResAudioService.instance;
    final controller = StreamController<String>.broadcast();
    controller.add(hiRes.lastOutputDeviceType);

    var hasLiveData = false;

    hiRes.queryActiveOutputDeviceType().then((type) {
      if (!controller.isClosed && !hasLiveData) {
        controller.add(type);
      }
    });

    final sub = hiRes.outputDeviceStream.listen(
      (type) {
        if (!controller.isClosed) {
          hasLiveData = true;
          controller.add(type);
        }
      },
    );

    ref.onDispose(() {
      sub.cancel();
      controller.close();
    });

    return controller.stream;
  }

  final controller = StreamController<String>.broadcast();

  controller.add('speaker');

  AudioSession.instance.then((session) {
    session.becomingNoisyEventStream.listen((_) {
      if (!controller.isClosed) controller.add('speaker');
    });
  }).catchError((_) {
  });

  ref.onDispose(() => controller.close());

  return controller.stream;
});