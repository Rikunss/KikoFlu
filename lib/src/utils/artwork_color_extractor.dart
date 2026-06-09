import 'dart:io';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import '../services/log_service.dart';

/// Extracts a gradient palette from album artwork by sampling horizontal
/// colour bands, similar to how Apple Music derives progress-bar colours.
///
/// Caches results keyed by the URL's MD5 hash so the same artwork is
/// processed only once per session.
class ArtworkColorExtractor {
  ArtworkColorExtractor._();

  static final Map<String, List<Color>> _cache = {};

  /// Pending extractions — deduplicates concurrent calls for the same URL
  /// so exactly one HTTP download happens regardless of caller count.
  static final Map<String, Future<List<Color>?>> _pending = {};

  /// Extract [numColors] evenly-spaced colours from the artwork at [imageUrl].
  ///
  /// If [preloadedBytes] is provided, it is used directly instead of fetching
  /// from the network — useful when the image is already cached on disk.
  /// Returns `null` on any failure (network error, decode failure, etc.).
  static Future<List<Color>?> extract(String imageUrl,
      {int numColors = 6, Uint8List? preloadedBytes}) async {
    final key = md5.convert(utf8.encode(imageUrl)).toString();
    if (_cache.containsKey(key)) return List.unmodifiable(_cache[key]!);
    if (_pending.containsKey(key)) return _pending[key]!;

    final future = _doExtract(imageUrl, key, numColors, preloadedBytes);
    _pending[key] = future;
    try {
      return await future;
    } finally {
      _pending.remove(key);
    }
  }

  static Future<List<Color>?> _doExtract(
      String imageUrl, String key, int numColors, Uint8List? preloadedBytes) async {
    try {
      final Uint8List imageBytes = preloadedBytes ??
          await _fetchBytes(imageUrl);
      if (imageBytes.isEmpty) return null;

      final colors =
          await compute(_extractColorsIsolate, _ExtractParams(imageBytes, numColors));
      if (colors == null || colors.isEmpty) return null;

      _cache[key] = colors;
      return List.unmodifiable(colors);
    } catch (e) {
      LogService.instance.error('[ArtworkColorExtractor] Failed: $e', tag: 'UI');
      return null;
    }
  }

  /// Clear the in-memory colour and pending-request caches.
  /// Call this before re-extracting to force a fresh HTTP download.
  static void clearCache() {
    _cache.clear();
    _pending.clear();
  }

  /// Fetch image bytes from local file or network.
  static Future<Uint8List> _fetchBytes(String imageUrl) async {
    if (imageUrl.startsWith('file://')) {
      final localPath = Uri.parse(imageUrl).toFilePath();
      final file = File(localPath);
      if (await file.exists()) return await file.readAsBytes();
      return Uint8List(0);
    }
    final response = await http
        .get(Uri.parse(imageUrl))
        .timeout(const Duration(seconds: 15));
    if (response.statusCode != 200) return Uint8List(0);
    return response.bodyBytes;
  }
}

/// Parameters passed to the isolate.
class _ExtractParams {
  final Uint8List bytes;
  final int numColors;
  const _ExtractParams(this.bytes, this.numColors);
}

/// Pure-Dart isolate entry — no Flutter APIs allowed.
List<Color>? _extractColorsIsolate(_ExtractParams params) {
  try {
    final image = img.decodeImage(params.bytes);
    if (image == null) return null;

    // Resize to a 1-pixel-tall strip — each column averages the vertical
    // slice of the artwork, giving us numColors representative colours.
    final strip = img.copyResize(image, width: params.numColors, height: 1);

    final colors = <Color>[];
    for (int x = 0; x < strip.width; x++) {
      final p = strip.getPixel(x, 0);
      colors.add(Color.fromARGB(
        p.a.toInt(),
        p.r.toInt(),
        p.g.toInt(),
        p.b.toInt(),
      ));
    }
    return colors;
  } catch (e) {
    // Isolate running in separate thread — cannot use LogService
    return null;
  }
}
