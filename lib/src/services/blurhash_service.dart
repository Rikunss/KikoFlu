import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart' as img;
import 'log_service.dart';
import 'storage_service.dart';
import 'cookie_service.dart';

final _log = LogService.instance;

/// Top-level function yang dijalankan di Isolate terpisah via [compute].
/// Tidak boleh menangkap referensi dari class (harus top-level atau static).
String? _generateBlurHashInIsolate(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final blurHash = BlurHash.encode(image, numCompX: 6, numCompY: 5);
  return blurHash.hash;
}

/// Service for generating and caching BlurHash strings from cover images.
///
/// When a cover image is loaded (e.g., via CachedNetworkImage), this service
/// can generate a blurhash in the background and persist it, so that
/// subsequent visits show a nice colorful placeholder instead of a grey box.
class BlurHashService {
  static final BlurHashService instance = BlurHashService._();
  BlurHashService._();

  static const String _storageKey = 'blurhash_cache';

  /// In-memory cache: workId → blurHash string
  final Map<int, String> _cache = {};

  /// Tracks work IDs that have already failed generation, to avoid retrying them.
  final Set<int> _failedWorkIds = {};

  /// Tracks work IDs currently being generated, to prevent duplicate processing.
  final Set<int> _pendingWorkIds = {};

  bool _initialized = false;

  /// Initialize: load cached blurhashes from persistent storage.
  Future<void> init() async {
    if (_initialized) return;
    final raw = StorageService.getString(_storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          final workId = int.tryParse(entry.key);
          final hash = entry.value as String?;
          if (workId != null && hash != null && hash.isNotEmpty) {
            _cache[workId] = hash;
          }
        }
      } catch (e) {
        _log.error('Failed to decode cached data: $e', tag: 'BlurHash');
      }
    }
    _initialized = true;
    _log.info('Loaded ${_cache.length} cached hashes', tag: 'BlurHash');
  }

  /// Get cached blurhash for a work (synchronous, in-memory).
  String? getBlurHash(int workId) => _cache[workId];

  /// Check if a blurhash exists for this work.
  bool hasBlurHash(int workId) => _cache.containsKey(workId);

  /// Generate blurhash for a work if not already cached.
  /// Fires and forgets — runs in background.
  Future<void> generateIfNeeded(int workId, String imageUrl) async {
    if (_cache.containsKey(workId)) return;
    if (_failedWorkIds.contains(workId)) return;
    if (_pendingWorkIds.contains(workId)) return;

    _pendingWorkIds.add(workId);
    try {
      final hash = await _generate(imageUrl);
      if (hash != null && hash.isNotEmpty) {
        _cache[workId] = hash;
        await _persist();
        _log.info('Generated hash for work $workId: ${hash.length} chars', tag: 'BlurHash');
      } else {
        _failedWorkIds.add(workId);
      }
    } catch (e) {
      _log.error('Failed to generate for work $workId: $e', tag: 'BlurHash');
      _failedWorkIds.add(workId);
    } finally {
      _pendingWorkIds.remove(workId);
    }
  }

  /// Generate blurhash from an image URL.
  ///
  /// Download bytes di main isolate (HTTP client), lalu decode + encode
  /// blurhash di Isolate terpisah via [compute] agar tidak blocking UI.
  Future<String?> _generate(String imageUrl) async {
    final httpClient = HttpClient();
    httpClient.autoUncompress = true;

    try {
      final uri = Uri.parse(imageUrl);
      final request = await httpClient.getUrl(uri);

      final cookie = await CookieService.getCookie();
      if (cookie != null && cookie.isNotEmpty) {
        request.headers.set('Cookie', cookie);
      }

      final response = await request.close();

      if (response.statusCode != 200) {
        _log.warning('HTTP ${response.statusCode} for $imageUrl', tag: 'BlurHash');
        return null;
      }

      final bytes = await consolidateHttpClientResponseBytes(response);

      final hash = await compute(_generateBlurHashInIsolate, bytes);
      return hash;
    } catch (e) {
      _log.error('Generation error: $e', tag: 'BlurHash');
      return null;
    } finally {
      httpClient.close();
    }
  }

  /// Batch-generate blurhashes for a list of works.
  ///
  /// Only generates for works not already cached. Processes with [concurrency]
  /// parallel requests at a time to avoid overwhelming the network.
  Future<void> generateBatch(
    List<({int workId, String imageUrl})> items, {
    int concurrency = 3,
  }) async {
    final toProcess = <({int workId, String imageUrl})>[];
    for (final item in items) {
      if (!_cache.containsKey(item.workId) &&
          !_pendingWorkIds.contains(item.workId)) {
        toProcess.add(item);
      }
    }

    if (toProcess.isEmpty) return;

    _log.info('Batch generating up to ${toProcess.length} hashes (concurrency: $concurrency)', tag: 'BlurHash');

    for (int i = 0; i < toProcess.length; i += concurrency) {
      final end = i + concurrency > toProcess.length
          ? toProcess.length
          : i + concurrency;
      final batch = toProcess.sublist(i, end);
      await Future.wait(
        batch.map((item) => generateIfNeeded(item.workId, item.imageUrl)),
      );
    }

    _log.info('Batch generation completed for ${toProcess.length} works', tag: 'BlurHash');
  }

  /// Persist in-memory cache to SharedPreferences.
  Future<void> _persist() async {
    final data = _cache.map((k, v) => MapEntry(k.toString(), v));
    await StorageService.setString(_storageKey, jsonEncode(data));
  }
}