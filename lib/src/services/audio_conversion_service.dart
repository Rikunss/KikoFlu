import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show MethodChannel;

import 'log_service.dart';

import 'package:ffmpeg_kit_flutter_new_min/ffmpeg_kit.dart';
import 'package:ffmpeg_kit_flutter_new_min/return_code.dart';
import 'package:ffmpeg_kit_flutter_new_min/session.dart';

final _log = LogService.instance;

/// Available WAV conversion target formats.
///
/// - [none]: Keep the original WAV file as-is.
/// - [flac]: Lossless FLAC.
/// - [opus]: High-efficiency lossy Opus.
/// - [mp3]: Universal lossy MP3 (LAME).
/// - [alac]: Apple Lossless ALAC (desktop/Android via ffmpeg, iOS via AVFoundation).
/// - [aac]:  Advanced Audio Codec.
enum WavConversionFormat {
  none('Keep WAV', 'none', '.wav'),
  flac('FLAC', 'flac', '.flac'),
  opus('Opus', 'opus', '.opus'),
  mp3('MP3', 'mp3', '.mp3'),
  alac('ALAC', 'alac', '.m4a'),
  aac('AAC', 'aac', '.m4a');

  final String displayName;
  final String value;
  final String extension;
  const WavConversionFormat(this.displayName, this.value, this.extension);
}

/// Service that handles WAV → target format audio conversion after download.
///
/// Platform strategies:
///   Desktop (Win/Mac/Linux): System `ffmpeg` via [Process.run] — all formats.
///   Android:                 Bundled `ffmpeg-kit` (FFmpegKit Flutter) — all formats via Dart API.
///   iOS:                     MethodChannel → AVFoundation (ALAC / AAC).
class AudioConversionService {
  static AudioConversionService? _instance;
  static AudioConversionService get instance =>
      _instance ??= AudioConversionService._();

  AudioConversionService._();

  static const _channel = MethodChannel('com.kikoeru.flutter/audio_conversion');

  /// Returns the file extension for a given format.
  String extensionFor(WavConversionFormat format) => format.extension;

  /// Returns the output file path for a given format.
  /// Uses simple string ops for reliability across platforms.
  String outputPath(String wavPath, WavConversionFormat format) {
    final dir = File(wavPath).parent.path;
    final basename = wavPath.split(RegExp(r'[/\\]')).last;
    final stem = basename.toLowerCase().endsWith('.wav')
        ? basename.substring(0, basename.length - 4)
        : basename;
    final result = '$dir/$stem${format.extension}';
    _log.info('[AudioConversion] outputPath: $wavPath → $result', tag: 'AudioConv');
    return result;
  }

  final Map<String, bool> _encoderCache = {};

  /// Returns true if the given format can be converted on the current platform.
  bool isFormatSupportedOnPlatform(WavConversionFormat format) {
    if (format == WavConversionFormat.none) return true;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) return true;
    if (Platform.isAndroid) {
      return format == WavConversionFormat.opus ? false : true;
    }
    if (Platform.isIOS) {
      return format == WavConversionFormat.alac || format == WavConversionFormat.aac;
    }
    return false;
  }

  /// Check if a specific encoder is available on Android at runtime.
  /// With bundled ffmpeg-kit (min variant), only built-in FFmpeg encoders
  /// (FLAC, ALAC, AAC) are available — MP3 (libmp3lame) and Opus (libopus)
  /// require the audio variant.
  Future<bool> checkEncoderAvailability(WavConversionFormat format) async {
    if (!Platform.isAndroid) return true;
    if (format == WavConversionFormat.none) return true;
    final available = format != WavConversionFormat.opus;
    _encoderCache[format.value] = available;
    return available;
  }

  /// Check all platform-appropriate encoders and cache results.
  Future<void> checkAllEncoders() async {
    if (Platform.isAndroid) {
      await checkEncoderAvailability(WavConversionFormat.flac);
      await checkEncoderAvailability(WavConversionFormat.opus);
      await checkEncoderAvailability(WavConversionFormat.mp3);
      await checkEncoderAvailability(WavConversionFormat.alac);
      await checkEncoderAvailability(WavConversionFormat.aac);
    }
  }

  /// Convert a WAV file to the target [format].
  ///
  /// Returns the path to the converted file, or `null` on failure.
  /// [onProgress] receives (progress 0.0–1.0, optional ETA string).
  Future<String?> convert(
    String wavPath,
    WavConversionFormat format, {
    void Function(double progress, {String? eta})? onProgress,
  }) async {
    if (format == WavConversionFormat.none) return null;

    try {
      final file = File(wavPath);
      if (!await file.exists()) {
        _log.error('[AudioConversion] WAV file not found: $wavPath', tag: 'AudioConv');
        return null;
      }

      if (!wavPath.toLowerCase().endsWith('.wav')) {
        return null;
      }

      final outPath = outputPath(wavPath, format);

      final outFile = File(outPath);
      if (await outFile.exists()) {
        try { await outFile.delete(); } catch (e) {
          _log.warning('[AudioConversion] Failed to delete stale output: $e', tag: 'AudioConv');
        }
      }

      _log.info('[AudioConversion] Starting: $wavPath → $outPath ($format)', tag: 'AudioConv');

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        return await _convertDesktop(wavPath, outPath, format, onProgress);
      } else if (Platform.isAndroid) {
        return await _convertAndroid(wavPath, outPath, format, onProgress);
      } else if (Platform.isIOS) {
        return await _convertIos(wavPath, outPath, format, onProgress);
      } else {
        _log.warning('[AudioConversion] Unsupported platform', tag: 'AudioConv');
        return null;
      }
    } catch (e) {
      _log.error('[AudioConversion] Failed: $e', tag: 'AudioConv');
      return null;
    }
  }

  List<String> _ffmpegArgsFor(String formatName, String input, String output) {
    switch (formatName) {
      case 'flac':
        return ['-i', input, '-compression_level', '8', '-f', 'flac', '-y', output];
      case 'opus':
        return ['-i', input, '-c:a', 'libopus', '-b:a', '128k', '-y', output];
      case 'mp3':
        return ['-i', input, '-c:a', 'mp3', '-b:a', '320k', '-y', output];
      case 'alac':
        return ['-i', input, '-c:a', 'alac', '-f', 'mp4', '-y', output];
      case 'aac':
        return ['-i', input, '-c:a', 'aac', '-b:a', '256k', '-y', output];
      default:
        return ['-i', input, '-y', output];
    }
  }

  /// Resolve symlinks so the real executable path is used. WinGet installs
  /// ffmpeg behind a symlink in `%LOCALAPPDATA%\Microsoft\WinGet\Links`, and
  /// Windows refuses to execute binaries reached through such untrusted
  /// mount points (ProcessException from Process.start).
  static Future<String> _resolveCommandPath(String path) async {
    try {
      final resolved = await File(path).resolveSymbolicLinks();
      if (resolved.isNotEmpty) return resolved;
    } catch (_) {
      // Keep the original path if resolution fails.
    }
    return path;
  }

  static const List<String> _knownFfmpegPaths = [
    r'C:\ffmpeg\bin\ffmpeg.exe',
    r'C:\Program Files\ffmpeg\bin\ffmpeg.exe',
    r'C:\ProgramData\chocolatey\bin\ffmpeg.exe',
    r'C:\Program Files\chocolatey\bin\ffmpeg.exe',
  ];

  /// Look for ffmpeg inside WinGet's package folders (real path, no symlink).
  static Future<String?> _findInWinGetPackages() async {
    try {
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (localAppData == null || localAppData.isEmpty) return null;
      final base = Directory('$localAppData\\Microsoft\\WinGet\\Packages');
      if (!await base.exists()) return null;
      await for (final sub in base.list()) {
        if (sub is! Directory) continue;
        // Either <package>/bin or <package>/<version>/bin.
        final candidates = <String>[sub.path];
        await for (final child in sub.list()) {
          if (child is Directory) candidates.add(child.path);
        }
        for (final dir in candidates) {
          final bin = Directory('$dir\\bin');
          if (!await bin.exists()) continue;
          await for (final f in bin.list()) {
            if (f is File && f.path.toLowerCase().endsWith('ffmpeg.exe')) {
              return f.path;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _findFfmpeg() async {
    // 1. PATH lookup, then resolve symlinks to the real executable.
    const candidates = ['ffmpeg', 'ffmpeg.exe'];
    for (final cmd in candidates) {
      try {
        if (Platform.isWindows) {
          final result = await Process.run('where', [cmd], runInShell: true);
          if (result.exitCode == 0 &&
              (result.stdout as String).trim().isNotEmpty) {
            final path =
                (result.stdout as String).trim().split('\n').first.trim();
            return _resolveCommandPath(path);
          }
        } else {
          final result = await Process.run('which', [cmd], runInShell: true);
          if (result.exitCode == 0 &&
              (result.stdout as String).trim().isNotEmpty) {
            return (result.stdout as String).trim();
          }
        }
      } catch (_) {}
    }

    // 2. Common install locations as fallback when not on PATH.
    if (Platform.isWindows) {
      for (final known in _knownFfmpegPaths) {
        if (await File(known).exists()) return known;
      }
      final winGet = await _findInWinGetPackages();
      if (winGet != null) return winGet;
    }
    return null;
  }

  Future<String?> _convertDesktop(
    String input,
    String output,
    WavConversionFormat format,
    void Function(double progress, {String? eta})? onProgress,
  ) async {
    final ffmpegPath = await _findFfmpeg();

    if (ffmpegPath == null) {
      _log.warning(
        '[AudioConversion] ffmpeg not found. Install FFmpeg to enable conversion.',
        tag: 'AudioConv',
      );
      return null;
    }

    final args = _ffmpegArgsFor(format.value, input, output);
    _log.info('[AudioConversion] ffmpeg: $ffmpegPath ${args.join(' ')}', tag: 'AudioConv');

    // Run without a shell (Dart quotes the executable path itself) and always
    // drain stdout/stderr: ffmpeg writes a lot of output, and if the pipes are
    // never read their buffers fill up, blocking ffmpeg forever.
    final process = await Process.start(ffmpegPath, args);
    final stdoutBuf = StringBuffer();
    final stderrBuf = StringBuffer();
    process.stdout
        .transform(const SystemEncoding().decoder)
        .listen(stdoutBuf.write);
    process.stderr
        .transform(const SystemEncoding().decoder)
        .listen(stderrBuf.write);
    final exitCode = await process.exitCode;

    if (exitCode == 0 && await File(output).exists()) {
      final originalSize = await File(input).length();
      final convertedSize = await File(output).length();
      final savedPercent = originalSize > 0
          ? ((1 - convertedSize / originalSize) * 100).toStringAsFixed(1)
          : '?';
      _log.info(
        '[AudioConversion] Success: $input → $output '
        '($originalSize → $convertedSize bytes, -$savedPercent%)',
        tag: 'AudioConv',
      );

      try {
        await File(input).delete();
        _log.info('[AudioConversion] Deleted original WAV', tag: 'AudioConv');
      } catch (e) {
        _log.warning('[AudioConversion] Could not delete original: $e', tag: 'AudioConv');
      }

      return output;
    } else {
      final errLines = stderrBuf.toString().trim().split('\n');
      final errTail = errLines.length > 8
          ? errLines.sublist(errLines.length - 8).join('\n')
          : errLines.join('\n');
      _log.error(
        '[AudioConversion] ffmpeg failed (exit $exitCode):\n$errTail',
        tag: 'AudioConv',
      );
      return null;
    }
  }

  /// Quote a path argument if it contains spaces, to be safe for shell-less cmd string.
  String _quotePath(String p) => p.contains(' ') ? '"$p"' : p;

  Future<String?> _convertAndroid(
    String input,
    String output,
    WavConversionFormat format,
    void Function(double progress, {String? eta})? onProgress,
  ) async {
    final formatName = format.value;
    try {
      final args = _ffmpegArgsFor(formatName, input, output);
      final cmd = args.map((a) => _quotePath(a)).join(' ');

      final inputFile = File(input);
      final inputLength = await inputFile.length();
      if (inputLength <= 0) {
        _log.error('[AudioConversion] Input file empty: $input', tag: 'AudioConv');
        return null;
      }

      final startTime = DateTime.now();
      String? lastEta;

      final completer = Completer<Session>();

      FFmpegKit.executeAsync(
        cmd,
        (session) {
          if (!completer.isCompleted) completer.complete(session);
        },
        (log) {},
        (statistics) {
          if (onProgress == null) return;
          final size = statistics.getSize();
          if (size > 0) {
            final progress = (size / inputLength).clamp(0.0, 1.0);
            final elapsed = DateTime.now().difference(startTime);
            final remaining = _estimateEta(elapsed, progress);
            if (remaining != null && remaining > Duration.zero) {
              lastEta = _formatDuration(remaining);
            }
            onProgress(progress, eta: lastEta);
          }
        },
      );

      final session = await completer.future;
      final returnCode = await session.getReturnCode();

      onProgress?.call(1.0, eta: 'Complete');

      if (ReturnCode.isSuccess(returnCode) && await File(output).exists()) {
        _log.info('[AudioConversion] Android $formatName success via ffmpeg-kit', tag: 'AudioConv');
        try { await inputFile.delete(); } catch (e) {
          _log.warning('[AudioConversion] Failed to delete input WAV: $e', tag: 'AudioConv');
        }
        return output;
      } else {
        _log.error('[AudioConversion] Android $formatName failed (rc=$returnCode)', tag: 'AudioConv');
        return null;
      }
    } catch (e) {
      _log.error('[AudioConversion] Android $formatName error: $e', tag: 'AudioConv');
      return null;
    }
  }

  /// Estimate remaining duration from elapsed time and current progress.
  Duration? _estimateEta(Duration elapsed, double progress) {
    if (progress <= 0.01) return null;
    final estimated = Duration(
        milliseconds: (elapsed.inMilliseconds / progress).round());
    return estimated - elapsed;
  }

  /// Format a Duration as a human-readable ETA string (e.g. "45s" or "2m 30s").
  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      final h = d.inHours;
      final m = d.inMinutes.remainder(60);
      return '${h}h ${m}m';
    } else if (d.inMinutes > 0) {
      final m = d.inMinutes;
      final s = d.inSeconds.remainder(60);
      return '${m}m ${s}s';
    } else {
      return '${d.inSeconds}s';
    }
  }

  Future<String?> _convertIos(
    String input,
    String output,
    WavConversionFormat format,
    void Function(double progress, {String? eta})? onProgress,
  ) async {
    final formatName = format.value;
    try {
      final result = await _channel.invokeMethod<String>('convertWav', {
        'inputPath': input,
        'outputPath': output,
        'format': formatName,
      });

      if (result == 'success' && await File(output).exists()) {
        _log.info('[AudioConversion] iOS $formatName success', tag: 'AudioConv');
        try { await File(input).delete(); } catch (e) {
          _log.warning('[AudioConversion] Failed to delete input file: $e', tag: 'AudioConv');
        }
        return output;
      }
    } catch (e) {
      _log.error('[AudioConversion] iOS $formatName error: $e', tag: 'AudioConv');
    }
    return null;
  }
}