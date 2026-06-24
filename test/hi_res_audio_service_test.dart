import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru_flutter/src/services/hi_res_audio_service.dart';

void main() {
  // Initialize the test binding for MethodChannel support
  TestWidgetsFlutterBinding.ensureInitialized();

  // ============================================================

  // ============================================================
  // UsbAudioDevice Model
  // ============================================================
  group('UsbAudioDevice', () {
    test('fromMap parses correctly', () {
      final device = UsbAudioDevice.fromMap({
        'id': 1,
        'productName': 'USB DAC',
        'address': '1-1',
        'type': 'usb_audio',
        'channelCounts': 2,
        'sampleRates': 192000,
      });

      expect(device.id, 1);
      expect(device.productName, 'USB DAC');
      expect(device.address, '1-1');
      expect(device.type, 'usb_audio');
      expect(device.maxChannelCount, 2);
      expect(device.maxSampleRate, 192000);
    });

    test('fromMap handles empty map', () {
      final device = UsbAudioDevice.fromMap({});
      expect(device.id, 0);
      expect(device.productName, 'Unknown');
      expect(device.address, '');
      expect(device.type, 'other');
      expect(device.maxChannelCount, 0);
      expect(device.maxSampleRate, 0);
    });

    test('fromMap handles null values', () {
      final device = UsbAudioDevice.fromMap({
        'id': null,
        'productName': null,
        'address': null,
        'type': null,
        'channelCounts': null,
        'sampleRates': null,
      });

      expect(device.id, 0);
      expect(device.productName, 'Unknown');
    });

    test('toString includes key fields', () {
      final device = UsbAudioDevice(
        id: 2,
        productName: 'FiiO KA5',
        address: '2-1',
        type: 'usb_audio',
        maxChannelCount: 2,
        maxSampleRate: 384000,
      );

      final str = device.toString();
      expect(str, contains('FiiO KA5'));
      expect(str, contains('384000'));
      expect(str, contains('2ch'));
    });
  });

  // ============================================================
  // UsbRoutingState Model
  // ============================================================
  group('UsbRoutingState', () {
    test('default state is not routed', () {
      const state = UsbRoutingState();
      expect(state.routed, false);
      expect(state.deviceName, '');
      expect(state.mixerAttributesApplied, false);
    });

    test('fully populated state', () {
      const state = UsbRoutingState(
        routed: true,
        deviceName: 'Topping E50',
        mixerAttributesApplied: true,
      );

      expect(state.routed, true);
      expect(state.deviceName, 'Topping E50');
      expect(state.mixerAttributesApplied, true);
    });
  });

  // ============================================================
  // UsbDacAutoRoutedEvent Model
  // ============================================================
  group('UsbDacAutoRoutedEvent', () {
    test('default values', () {
      const event = UsbDacAutoRoutedEvent();
      expect(event.deviceName, '');
      expect(event.vendorId, 0);
      expect(event.productId, 0);
    });

    test('populated event', () {
      const event = UsbDacAutoRoutedEvent(
        deviceName: 'Cayin RU7',
        vendorId: 0x1234,
        productId: 0x5678,
      );

      expect(event.deviceName, 'Cayin RU7');
      expect(event.vendorId, 0x1234);
      expect(event.productId, 0x5678);
    });
  });

  // ============================================================
  // HiResFormatInfo Model
  // ============================================================
  group('HiResFormatInfo', () {
    test('default state', () {
      const info = HiResFormatInfo();
      expect(info.sampleRate, 0);
      expect(info.bitDepth, 0);
      expect(info.channels, 2);
      expect(info.isValid, false);
    });

    test('valid when sampleRate > 0', () {
      const info = HiResFormatInfo(sampleRate: 96000, bitDepth: 24, channels: 2);
      expect(info.isValid, true);
      expect(info.toString(), contains('96000Hz'));
      expect(info.toString(), contains('24bit'));
      expect(info.toString(), contains('2ch'));
    });

    test('toString format', () {
      const info = HiResFormatInfo(sampleRate: 192000, bitDepth: 32, channels: 2);
      expect(info.toString(), 'HiResFormatInfo(192000Hz, 32bit, 2ch)');
    });
  });

  // ============================================================
  // HiResAudioService — Stream Controller Logic
  // ============================================================
  group('HiResAudioService Stream State', () {
    late HiResAudioService service;

    setUp(() {
      service = HiResAudioService.instance;
    });

    // Note: HiResAudioService is a singleton that uses MethodChannel.
      // We can't easily mock the MethodChannel, but we can verify
      // the stream controllers are set up and the initial state is correct.
    
    test('initial state is idle', () {
      expect(service.isPlaying, false);
      expect(service.isUsbRouted, false);
      expect(service.lastOutputDeviceType, 'unknown');
    });

    test('lastUsbRoutingState defaults to not routed', () {
      expect(service.lastUsbRoutingState.routed, false);
      expect(service.lastUsbRoutingState.deviceName, '');
    });
  });

  // ============================================================
  // USB Audio Device Helper Tests
  // ============================================================
  group('USB Audio Device Enumeration', () {
    test('fromMap handles all device type strings', () {
      final typeTests = [
        {'type': 'usb_dac', 'expected': 'usb_dac'},
        {'type': 'usb_audio', 'expected': 'usb_audio'},
        {'type': 'wired_headphones', 'expected': 'wired_headphones'},
        {'type': 'bluetooth', 'expected': 'bluetooth'},
        {'type': 'builtin_speaker', 'expected': 'builtin_speaker'},
        {'type': null, 'expected': 'other'},
        {'type': 'unknown_type', 'expected': 'unknown_type'},
      ];

      for (final testCase in typeTests) {
        final device = UsbAudioDevice.fromMap({
          'id': 1,
          'productName': 'Test',
          'address': '1-1',
          'type': testCase['type'],
        });
        expect(device.type, testCase['expected'],
            reason: 'type=${testCase['type']} should map to ${testCase['expected']}');
      }
    });

    test('device with zero sample rate is still valid', () {
      final device = UsbAudioDevice.fromMap({
        'id': 3,
        'productName': 'Generic USB Audio',
        'address': '3-1',
        'type': 'usb_audio',
      });
      expect(device.id, 3);
      expect(device.maxSampleRate, 0);
      expect(device.productName, 'Generic USB Audio');
    });
  });
}
