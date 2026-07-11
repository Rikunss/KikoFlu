import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:image/image.dart' as img;

import 'log_service.dart';

final _log = LogService.instance;

/// Handles cover image resizing and processing for download works.
///
/// Scans import directories for the first supported image file, resizes it
/// to a maximum dimension (default 720px), and saves as JPEG quality 85.
/// Falls back to Flutter's platform decoder when the pure-Dart decoder fails
/// (e.g. CMYK JPEG, unusual PNG color types).
class DownloadCoverProcessor {
  /// Work IDs whose cover images are currently being resized/processed.
  final Set<int> _processingCovers = {};
  final StreamController<Set<int>> _processingCoversController =
      StreamController<Set<int>>.broadcast();

  /// Stream of workIds whose covers are currently being processed.
  Stream<Set<int>> get processingCoversStream =>
      _processingCoversController.stream;

  /// Current set of workIds with covers being processed.
  Set<int> get processingCovers => Set.unmodifiable(_processingCovers);

  /// Mark a work's cover as being processed (resized).
  void addProcessingCover(int workId) {
    _processingCovers.add(workId);
    _processingCoversController.add(Set.of(_processingCovers));
  }

  /// Mark a work's cover processing as complete.
  void removeProcessingCover(int workId) {
    _processingCovers.remove(workId);
    _processingCoversController.add(Set.of(_processingCovers));
  }

  /// Fire-and-forget: scan the import folder for the first image, resize it
  /// to max 720px, save as JPEG quality 85, then update the metadata and
  /// notify listeners so the card updates with the processed cover.
  ///
  /// [onMetadataUpdated] is called after the cover is resized so the caller
  /// can update tasks in memory.
  Future<void> processCoverForImport({
    required int workId,
    required String workDirPath,
    required Directory importDir,
    required void Function(Map<String, dynamic> metadata) onMetadataUpdated,
  }) async {
    try {
      final entities = await importDir.list(recursive: true).toList();
      entities.sort((a, b) {
        final aName = a.path.split(Platform.pathSeparator).last;
        final bName = b.path.split(Platform.pathSeparator).last;
        return _naturalCompare(aName, bName);
      });

      for (final entity in entities) {
        if (entity is! File) continue;
        final fName = entity.path.split(Platform.pathSeparator).last.toLowerCase();
        if (fName.endsWith('.jpg') || fName.endsWith('.jpeg') ||
            fName.endsWith('.png') || fName.endsWith('.webp') ||
            fName.endsWith('.bmp')) {
          await _resizeAndSaveCover(
            sourcePath: entity.path,
            destPath: '$workDirPath/cover.jpg',
            maxDimension: 720,
          );

          final metadataFile = File('$workDirPath/work_metadata.json');
          if (await metadataFile.exists()) {
            try {
              final content = await metadataFile.readAsString();
              final meta = jsonDecode(content) as Map<String, dynamic>;
              meta['localCoverPath'] = 'cover.jpg';
              await metadataFile.writeAsString(jsonEncode(meta));
              onMetadataUpdated(meta);
            } catch (e) {
              _log.warning('Failed to update metadata after cover resize: $e', tag: 'Download');
            }
          }

          _log.info('Cover image resized and saved as JPEG: $fName (max 720px)', tag: 'Download');
          break;
        }
      }
    } catch (e) {
      _log.warning('Failed to process cover image: $e', tag: 'Download');
    } finally {
      removeProcessingCover(workId);
    }
  }

  /// Resize a cover image to [maxDimension] pixels on the longest edge and
  /// save as JPEG quality 85. This prevents large images (>1MB) from causing
  /// silent decode failures in Image.file() on Android with Impeller/Vulkan.
  ///
  /// If the pure-Dart [img.decodeImage] fails (e.g. CMYK JPEG, unusual PNG
  /// color types), falls back to Flutter's platform decoder (dart:ui) which
  /// supports more formats. If both decoders fail, the cover is skipped
  /// entirely — no fallback copy of the original large file.
  Future<void> _resizeAndSaveCover({
    required String sourcePath,
    required String destPath,
    int maxDimension = 720,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    final Uint8List bytes = await sourceFile.readAsBytes();

    img.Image? result = img.decodeImage(bytes);

    if (result == null) {
      _log.warning('Pure-Dart decoder failed, trying platform decoder: $sourcePath',
          tag: 'Download');
      try {
        final codec = await ui.instantiateImageCodec(
          bytes,
          targetWidth: maxDimension * 2,
        );
        final frame = await codec.getNextFrame();
        final rgbaData = await frame.image.toByteData(
          format: ui.ImageByteFormat.rawRgba,
        );
        if (rgbaData != null) {
          result = img.Image.fromBytes(
            width: frame.image.width,
            height: frame.image.height,
            bytes: rgbaData.buffer,
            numChannels: 4,
          );
          _log.info(
            'Platform decoder succeeded: ${frame.image.width}x${frame.image.height}',
            tag: 'Download',
          );
        }
      } catch (e) {
        _log.warning('Platform decoder also failed: $e', tag: 'Download');
      }
    }

    if (result == null) {
      _log.warning('Skipping cover (could not decode): $sourcePath',
          tag: 'Download');
      return;
    }

    if (result.width > maxDimension || result.height > maxDimension) {
      result = img.copyResize(result,
        width: result.width > result.height ? maxDimension : null,
        height: result.height >= result.width ? maxDimension : null,
      );
    }

    const maxBytes = 500 * 1024;
    int quality = 85;
    Uint8List jpegBytes;

    do {
      jpegBytes = img.encodeJpg(result, quality: quality);
      if (jpegBytes.length <= maxBytes) break;
      quality -= 10;
    } while (quality >= 25);

    await File(destPath).writeAsBytes(jpegBytes);

    _log.info(
      'Cover resized: ${result.width}x${result.height} '
      '(${(bytes.length / 1024).toStringAsFixed(1)}KB -> '
      '${(jpegBytes.length / 1024).toStringAsFixed(1)}KB, '
      'quality=$quality)',
      tag: 'Download',
    );
  }

  /// Natural sort comparator for file names.
  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+|[^\d]+)');
    final aParts = pattern
        .allMatches(a.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();
    final bParts = pattern
        .allMatches(b.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();

    final len = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < len; i++) {
      final aNum = int.tryParse(aParts[i]);
      final bNum = int.tryParse(bParts[i]);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aParts[i].compareTo(bParts[i]);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  /// Clean up resources.
  void dispose() {
    _processingCoversController.close();
  }
}