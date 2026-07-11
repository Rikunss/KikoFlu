import 'dart:isolate';

import '../models/audio_track.dart';
import '../utils/audio_format_parser.dart';
import 'cache_service.dart';
import 'replay_gain_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Runs HTTP Range request for audio format detection in an isolate so
/// network I/O doesn't block the main thread during track loading.
/// Local/cached file reads stay on the main thread (faster than isolate overhead).
Future<AudioFormatInfo?> _detectFormatInIsolate(String streamUrl) async {
  try {
    return await AudioFormatInfo.fromStreamUrl(streamUrl);
  } catch (_) {
    return null;
  }
}

/// Runs ReplayGain file analysis in an isolate so file I/O (opening and
/// parsing FLAC/MP3 metadata up to ~64KB) doesn't block the main thread
/// during track loading. Each isolate has its own [ReplayGainService] singleton
/// via the standard `instance` getter.
Future<ReplayGainData?> _analyzeGainInIsolate(String filePath) async {
  try {
    return await ReplayGainService.instance.analyzeFile(filePath);
  } catch (_) {
    return null;
  }
}

/// Extracted audio format detection and ReplayGain analysis logic.
///
/// These operations involve file I/O or HTTP requests that should not block
/// the main thread. Heavy operations are offloaded to isolates.
///
/// All methods are static — the class is a stateless utility.
class AudioFormatGainService {
  /// Detect audio format from a track's local/cached file or streaming URL.
  ///
  /// **Fast path:** local or cached file reads on the main thread (~1ms).
  /// **Slow path:** HTTP Range requests run in an isolate.
  /// **Fallback:** URL extension parsing (no I/O).
  static Future<AudioFormatInfo?> detectFormatDirect(AudioTrack track) async {
    try {
      if (track.url.startsWith('file://')) {
        final localPath = track.url.substring(7);
        return await AudioFormatInfo.fromFile(localPath);
      }
      if (track.hash != null && track.hash!.isNotEmpty) {
        final cachedPath =
            await CacheService.getCachedAudioFile(track.hash!);
        if (cachedPath != null) {
          return await AudioFormatInfo.fromFile(cachedPath);
        }
      }
    } catch (e) {
      _log.error('Failed to detect audio format from file: $e', tag: 'Audio');
    }

    try {
      final result = await Isolate.run(
        () => _detectFormatInIsolate(track.url),
      );
      if (result != null) return result;
    } catch (e) {
      _log.error(
        'Failed to detect audio format in isolate: $e',
        tag: 'Audio',
      );
    }

    return AudioFormatInfo.fromUrl(track.url);
  }

  /// Run ReplayGain file analysis in an isolate.
  ///
  /// Returns the parsed [ReplayGainData] or `null` if no ReplayGain metadata
  /// is found or if the file is inaccessible.
  static Future<ReplayGainData?> analyzeGain(String filePath) async {
    try {
      return await Isolate.run(
        () => _analyzeGainInIsolate(filePath),
      );
    } catch (e) {
      _log.error(
        'Failed to analyze ReplayGain in isolate: $e',
        tag: 'Audio',
      );
      return null;
    }
  }
}