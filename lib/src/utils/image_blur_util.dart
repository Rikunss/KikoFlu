import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../services/log_service.dart';
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';
import 'package:image/image.dart' as img;

/// Top-level function that runs in a compute isolate.
/// Disini kita menggunakan pure-Dart [img.Image] processing karena
/// [dart:ui] APIs (Canvas, Picture, ImageFilter) tidak bisa diakses dari isolate.
///
/// Returns PNG bytes of the blurred image, or null on failure.
Future<Uint8List?> _blurImageInIsolate(Uint8List imageBytes) async {
  try {
    // Decode image using pure-Dart decoder
    final original = img.decodeImage(imageBytes);
    if (original == null) return null;

    // Downscale to ~200px wide for faster blur processing
    // Privacy blur doesn't need full resolution
    final thumb = img.copyResize(original, width: 200);

    // Apply heavy gaussian blur with large radius
    final blurred = img.gaussianBlur(thumb, radius: 50);

    // Encode back to PNG bytes
    final pngBytes = img.encodePng(blurred);
    return Uint8List.fromList(pngBytes);
  } catch (e) {
    LogService.instance.error('[ImageBlur] Isolate processing failed: $e', tag: 'UI');
    return null;
  }
}

/// 图片模糊处理工具类
class ImageBlurUtil {
  /// 对网络图片或本地图片应用高强度高斯模糊并保存到临时文件
  /// 返回模糊后的图片文件路径（file:// 协议）
  ///
  /// Image decoding + blurring dilakukan di Isolate terpisah via [compute]
  /// agar tidak memblokade main thread (UI).
  static Future<String?> blurNetworkImageToFile(String imageUrl) async {
    try {
      // Generate cache file name hash (quick — can stay on main thread)
      final urlHash = md5.convert(utf8.encode(imageUrl)).toString();
      final tempDir = await getTemporaryDirectory();
      final blurredFile = File('${tempDir.path}/blurred_$urlHash.png');

      // If already cached, return immediately (no processing needed)
      if (await blurredFile.exists()) {
        return 'file://${blurredFile.path}';
      }

      Uint8List imageData;

      // Download image bytes on main thread (async HTTP — non-blocking)
      if (imageUrl.startsWith('file://')) {
        final localPath = Uri.parse(imageUrl).toFilePath();
        final localFile = File(localPath);
        if (!await localFile.exists()) {
          LogService.instance.debug('[ImageBlur] Local file not found: $localPath', tag: 'UI');
          return null;
        }
        imageData = await localFile.readAsBytes();
      } else {
        final response = await http.get(Uri.parse(imageUrl)).timeout(
              const Duration(seconds: 30),
            );
        if (response.statusCode != 200) {
          LogService.instance.warning('[ImageBlur] HTTP ${response.statusCode}', tag: 'UI');
          return null;
        }
        imageData = response.bodyBytes;
      }

      // Process heavy work (decode → downscale → blur → encode PNG) in Isolate.
      // Menggunakan pure-Dart [image] package agar kompatibel dengan isolate.
      final pngBytes = await compute(_blurImageInIsolate, imageData);

      if (pngBytes == null || pngBytes.isEmpty) {
        LogService.instance.warning('[ImageBlur] Isolate returned null/empty', tag: 'UI');
        return null;
      }

      // Save to temp file (I/O — non-blocking)
      await blurredFile.writeAsBytes(pngBytes);
      return 'file://${blurredFile.path}';
    } catch (e) {
      LogService.instance.error('[ImageBlur] Failed: $e', tag: 'UI');
      return null;
    }
  }
}
