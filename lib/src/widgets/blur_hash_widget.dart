import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:blurhash_dart/blurhash_dart.dart';
import 'package:image/image.dart' as img;
import '../services/log_service.dart';

/// Top-level function yang dijalankan di Isolate terpisah via [compute].
/// Melakukan decode blurhash + encode JPEG agar tidak memblokade main thread.
Uint8List? _decodeBlurHashInIsolate(String hash) {
  try {
    final blurHash = BlurHash.decode(hash);
    final image = blurHash.toImage(32, 32);
    return Uint8List.fromList(img.encodeJpg(image));
  } catch (e) {
    return null;
  }
}

/// Pure-Dart BlurHash widget that decodes and renders blurhash strings
/// entirely in Dart via `blurhash_dart`, avoiding the native `flutter_blurhash`
/// plugin which crashes with NullPointerException on some Android devices.
class BlurHashWidget extends StatefulWidget {
  final String hash;
  final BoxFit? imageFit;

  const BlurHashWidget({super.key, required this.hash, this.imageFit});

  @override
  State<BlurHashWidget> createState() => _BlurHashWidgetState();
}

class _BlurHashWidgetState extends State<BlurHashWidget> {
  Uint8List? _jpgBytes;
  bool _loading = true;
  bool _errored = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(BlurHashWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.hash != widget.hash) {
      _jpgBytes = null;
      _loading = true;
      _errored = false;
      _load();
    }
  }

  Future<void> _load() async {
    try {
      // Decode blurhash + encode JPEG di Isolate terpisah
      // agar tidak memblokade main thread saat rendering 40+ kartu
      final jpgBytes = await compute(_decodeBlurHashInIsolate, widget.hash);

      if (jpgBytes == null) {
        if (mounted) {
          setState(() {
            _loading = false;
            _errored = true;
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _jpgBytes = jpgBytes;
          _loading = false;
        });
      }
    } catch (e) {
      LogService.instance.error('[BlurHashWidget] Failed to decode hash: $e', tag: 'UI');
      if (mounted) {
        setState(() {
          _loading = false;
          _errored = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      final colorScheme = Theme.of(context).colorScheme;
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              colorScheme.surfaceContainerHighest,
              colorScheme.surfaceContainerHigh.withValues(alpha: 0.8),
              colorScheme.surfaceContainerHighest,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
      );
    }
    if (_errored || _jpgBytes == null) {
      return Container(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Center(
          child: Icon(
            Icons.audiotrack,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            size: 32,
          ),
        ),
      );
    }
    return Image.memory(
      _jpgBytes!,
      fit: widget.imageFit ?? BoxFit.cover,
    );
  }

  @override
  void dispose() {
    _jpgBytes = null;
    super.dispose();
  }
}
