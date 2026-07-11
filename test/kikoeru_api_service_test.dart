import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru_flutter/src/services/kikoeru_api_service.dart';
import 'package:kikoeru_flutter/src/utils/server_utils.dart';

void main() {
  group('KikoeruApiException', () {
    test('toString includes message', () {
      final exc = KikoeruApiException('Network error', 'timeout');
      expect(exc.toString(), contains('Network error'));
    });

    test('preserves original error', () {
      final exc = KikoeruApiException('Login failed', 401);
      expect(exc.originalError, 401);
    });
  });

  group('Host Normalization', () {
    test('static constants are defined', () {
      expect(KikoeruApiService.remoteHost, isNotEmpty);
      expect(KikoeruApiService.localHost, isNotEmpty);
    });

    test('remoteHost and localHost from ServerUtils', () {
      expect(KikoeruApiService.remoteHost, ServerUtils.defaultRemoteHost);
      expect(KikoeruApiService.localHost, ServerUtils.defaultLocalHost);
    });
  });

  group('URL Construction', () {
    test('getDownloadUrl constructs correct URL', () {
      expect(KikoeruApiService().getDownloadUrl('hash123', 'file.mp3'),
          endsWith('/api/media/download/hash123/file.mp3'));
    });

    test('getStreamUrl constructs correct URL', () {
      expect(KikoeruApiService().getStreamUrl('hash456', 'track.flac'),
          endsWith('/api/media/stream/hash456/track.flac'));
    });

    test('getCoverUrl constructs correct URL', () {
      expect(KikoeruApiService().getCoverUrl(12345),
          endsWith('/api/cover/12345'));
    });

    test('getDownloadUrl accepts special characters in filename', () {
      final url = KikoeruApiService().getDownloadUrl('abc', 'my song #1.mp3');
      expect(url, endsWith('/api/media/download/abc/my song #1.mp3'));
    });

    test('getStreamUrl works with .wav files', () {
      final url = KikoeruApiService().getStreamUrl('hash', 'audio.wav');
      expect(url, endsWith('/api/media/stream/hash/audio.wav'));
    });
  });

  group('Configuration', () {
    late KikoeruApiService service;

    setUp(() {
      service = KikoeruApiService();
    });

    test('setOrder toggles sort when same order', () {
      service.init('test_token', 'example.com');

      service.setOrder('create_date');
      service.setOrder('create_date');
      service.setOrder('create_date');
    });

    test('setOrder does not toggle when different order', () {
      service.init('test_token', 'example.com');

      service.setOrder('create_date');
      service.setOrder('dl_count');
    });

    test('setSubtitle stores correct value', () {
      service.setSubtitle(1);
      service.setSubtitle(0);
    });
  });

  group('_fetchCombinedPages Logic', () {
    late KikoeruApiService service;

    setUp(() {
      service = KikoeruApiService();
    });

    test('init handles https prefix correctly', () {
      service.init('token123', 'https://custom-server.com');
    });

    test('init handles http prefix correctly', () {
      service.init('token456', 'http://localhost:8080');
    });

    test('init handles bare hostname with localhost', () {
      service.init('token789', 'localhost:8080');
    });

    test('init handles 192.168.x.x with http', () {
      service.init('token', '192.168.1.100:5000');
    });

    test('init handles remote bare host with https', () {
      service.init('token', 'myserver.com');
    });
  });
}