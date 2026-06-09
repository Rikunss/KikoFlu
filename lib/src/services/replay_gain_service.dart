import 'dart:io';
import 'dart:async';
import 'dart:math' show pow;
import 'package:flutter/foundation.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// Result of ReplayGain analysis for a single track.
class ReplayGainData {
  /// Track gain in dB (e.g., -2.34).
  final double? trackGain;

  /// Track peak (0.0 – 1.0, e.g., 0.998).
  final double? trackPeak;

  bool get hasReplayGain => trackGain != null;

  const ReplayGainData({this.trackGain, this.trackPeak});

  /// Calculate the volume multiplier to apply for ReplayGain.
  /// [preamp] is an optional additional boost/cut (default 0 dB).
  double volumeMultiplier({double preampDb = 0.0}) {
    if (trackGain == null) return 1.0;
    // ReplayGain: apply gain + preamp, convert dB to linear
    final totalDb = trackGain! + preampDb;
    return _dbToLinear(totalDb);
  }

  static double _dbToLinear(double db) {
    if (db <= -120.0) return 0.0;
    return pow(10.0, db / 20.0).toDouble();
  }

  @override
  String toString() =>
      'ReplayGain(${trackGain?.toStringAsFixed(2) ?? "N/A"} dB, peak: ${trackPeak?.toStringAsFixed(4) ?? "N/A"})';
}

/// Service that detects and applies ReplayGain from audio file metadata.
///
/// Parses local/cached audio files for ReplayGain tags:
/// - FLAC: Vorbis Comment metadata block (REPLAYGAIN_TRACK_GAIN, etc.)
/// - MP3: ID3v2 TXXX frames
///
/// The calculated volume multiplier is exposed so the [AudioPlayerService]
/// can apply it via [AudioPlayer.setVolume].
class ReplayGainService {
  static ReplayGainService? _instance;
  static ReplayGainService get instance => _instance ??= ReplayGainService._();

  ReplayGainService._();

  /// Whether ReplayGain processing is enabled.
  bool _enabled = false;

  /// Pre-amp boost/cut in dB applied on top of ReplayGain.
  double _preampDb = 0.0;

  /// The latest detected ReplayGain data for the current track.
  ReplayGainData? _currentGain;

  bool get enabled => _enabled;
  double get preampDb => _preampDb;
  ReplayGainData? get currentGain => _currentGain;

  /// Enable or disable ReplayGain.
  void setEnabled(bool value) {
    _enabled = value;
    if (!value) {
      _currentGain = null;
    }
  }

  /// Set pre-amp in dB.
  void setPreampDb(double db) {
    _preampDb = db.clamp(-12.0, 12.0);
  }

  /// Store the result of a ReplayGain analysis (called after isolate returns).
  void setCurrentGain(ReplayGainData? data) {
    _currentGain = data;
  }

  /// Analyze a file path for ReplayGain metadata.
  /// Returns [ReplayGainData] or null if no ReplayGain tags found.
  Future<ReplayGainData?> analyzeFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) return null;

      final lowerPath = filePath.toLowerCase();
      if (lowerPath.endsWith('.flac')) {
        return _parseFlacReplayGain(file);
      } else if (lowerPath.endsWith('.mp3')) {
        return _parseMp3ReplayGain(file);
      }
    } catch (e) {
      _log.error('Error analyzing $filePath: $e', tag: 'ReplayGain');
    }
    return null;
  }

  /// Calculate the effective volume multiplier based on current settings and
  /// detected ReplayGain data.
  double get effectiveVolumeMultiplier {
    if (!_enabled || _currentGain == null) return 1.0;
    return _currentGain!.volumeMultiplier(preampDb: _preampDb);
  }

  // ── FLAC Vorbis Comment parser ──

  /// Parse FLAC file for ReplayGain from Vorbis Comments.
  ///
  /// FLAC metadata structure:
  /// - 4 bytes: "fLaC" magic
  /// - Then metadata blocks, each with:
  ///   1 byte header: bit 0 = is_last, bits 1-7 = block type
  ///   3 bytes: block length (big-endian 24-bit)
  ///   [block length] bytes: block data
  ///
  /// Block type 4 = Vorbis Comment
  /// Vorbis Comment format:
  ///   4 bytes: vendor string length (LE)
  ///   [vendor string]
  ///   4 bytes: number of tags (LE)
  ///   For each tag:
  ///     4 bytes: tag string length (LE)
  ///     [tag string] = "KEY=VALUE"
  Future<ReplayGainData?> _parseFlacReplayGain(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      // Read enough for metadata headers (typically < 8KB, read 32KB to be safe)
      const readSize = 32768;
      final data = await raf.read(readSize);
      if (data.length < 42) return null;

      // Verify FLAC magic
      if (data[0] != 0x66 || data[1] != 0x4C || data[2] != 0x61 || data[3] != 0x43) {
        return null;
      }

      int offset = 4;
      // Scan metadata blocks for Vorbis Comment (type 4)
      String? trackGain;
      String? trackPeak;

      while (offset + 4 <= data.length) {
        final isLast = (data[offset] & 0x80) != 0;
        final blockType = data[offset] & 0x7F;
        final blockLen = (data[offset + 1] << 16) | (data[offset + 2] << 8) | data[offset + 3];
        offset += 4;

        if (blockType == 4) {
          // Vorbis Comment block
          if (offset + blockLen > data.length) break;
          final tags = _parseVorbisComments(data, offset, blockLen);
          for (final tag in tags) {
            final key = tag.key.toUpperCase();
            if (key == 'REPLAYGAIN_TRACK_GAIN') {
              trackGain = tag.value;
            } else if (key == 'REPLAYGAIN_TRACK_PEAK') {
              trackPeak = tag.value;
            }
          }
          break; // Vorbis Comment is usually only one block
        }

        offset += blockLen;
        if (isLast) break;
        if (offset >= data.length) break;
      }

      if (trackGain != null) {
        final gainDb = _parseGainString(trackGain);
        final peak = trackPeak != null ? double.tryParse(trackPeak) : null;
        if (gainDb != null) {
          return ReplayGainData(trackGain: gainDb, trackPeak: peak);
        }
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  /// Parse Vorbis Comments from a data buffer.
  /// Returns list of (key, value) pairs.
  List<_VorbisTag> _parseVorbisComments(Uint8List data, int start, int length) {
    final tags = <_VorbisTag>[];
    int offset = start;
    final end = start + length;

    // Skip vendor string
    if (offset + 4 > end) return tags;
    final vendorLen = _read32LE(data, offset);
    offset += 4 + vendorLen;
    if (offset > end) return tags;

    // Number of tags
    if (offset + 4 > end) return tags;
    final numTags = _read32LE(data, offset);
    offset += 4;

    for (int i = 0; i < numTags && offset + 4 <= end; i++) {
      final tagLen = _read32LE(data, offset);
      offset += 4;
      if (offset + tagLen > end) break;
      final tagStr = String.fromCharCodes(data.sublist(offset, offset + tagLen));
      offset += tagLen;

      final eqPos = tagStr.indexOf('=');
      if (eqPos > 0) {
        tags.add(_VorbisTag(
          tagStr.substring(0, eqPos).trim(),
          tagStr.substring(eqPos + 1).trim(),
        ));
      }
    }
    return tags;
  }

  // ── MP3 ID3v2 TXXX parser ──

  /// Parse MP3 file for ReplayGain from ID3v2 TXXX frames.
  Future<ReplayGainData?> _parseMp3ReplayGain(File file) async {
    final raf = await file.open(mode: FileMode.read);
    try {
      // ID3v2 header is 10 bytes, read 64KB to cover typical tag size
      const readSize = 65536;
      final data = await raf.read(readSize);
      if (data.length < 10) return null;

      // Check for ID3v2 magic
      if (data[0] != 0x49 || data[1] != 0x44 || data[2] != 0x33) {
        return null;
      }

      // Parse ID3v2 header size (syncsafe integer)
      final tagSize = _readSynchsafe32(data, 6);
      if (tagSize <= 0) return null;

      final headerEnd = 10 + tagSize;
      final effectiveEnd = headerEnd > data.length ? data.length : headerEnd;

      // Check for extended header (ID3v2.3+)
      int frameOffset = 10;
      final majorVersion = data[3];
      if (majorVersion >= 3) {
        final flags = data[5];
        if ((flags & 0x40) != 0) {
          // Extended header present, skip it
          if (majorVersion == 3) {
            // ID3v2.3: extended header size (4 bytes, big-endian)
            if (frameOffset + 4 > effectiveEnd) return null;
            final extSize = _read32BE(data, frameOffset);
            frameOffset += extSize;
          } else {
            // ID3v2.4: extended header size (4 bytes, syncsafe)
            if (frameOffset + 4 > effectiveEnd) return null;
            final extSize = _readSynchsafe32(data, frameOffset);
            frameOffset += extSize;
          }
        }
      }

      String? trackGain;
      String? trackPeak;

      // Parse frames
      while (frameOffset + 8 <= effectiveEnd) {
        // Check for padding (0x00) or end of tag
        if (data[frameOffset] == 0x00) break;

        final frameId = String.fromCharCodes(data.sublist(frameOffset, frameOffset + 4));
        int frameSize;
        if (majorVersion >= 3) {
          frameSize = _read32BE(data, frameOffset + 4);
          // ID3v2.4 uses syncsafe integers for size, but many implementations
          // use regular ints. Try both.
        } else {
          frameSize = _read32BE(data, frameOffset + 4);
        }
        frameOffset += 10; // 4 (id) + 4 (size) + 2 (flags)

        if (frameSize <= 0 || frameOffset + frameSize > effectiveEnd) break;

        if (frameId == 'TXXX') {
          // TXXX frame: encoding (1 byte) + description (null-terminated) + value
          final frameData = data.sublist(frameOffset, frameOffset + frameSize);
          final nullPos = frameData.indexOf(0, 1); // skip encoding byte
          if (nullPos > 1) {
            final description = String.fromCharCodes(frameData.sublist(1, nullPos)).toUpperCase();
            final value = String.fromCharCodes(frameData.sublist(nullPos + 1)).trim();
            if (description == 'REPLAYGAIN_TRACK_GAIN') {
              trackGain = value;
            } else if (description == 'REPLAYGAIN_TRACK_PEAK') {
              trackPeak = value;
            }
          }
        }
        frameOffset += frameSize;
      }

      if (trackGain != null) {
        final gainDb = _parseGainString(trackGain);
        final peak = trackPeak != null ? double.tryParse(trackPeak) : null;
        if (gainDb != null) {
          return ReplayGainData(trackGain: gainDb, trackPeak: peak);
        }
      }
    } finally {
      await raf.close();
    }
    return null;
  }

  /// Parse a gain string like "-2.34 dB" → -2.34
  static double? _parseGainString(String s) {
    // Remove "dB" suffix and trim
    var clean = s.toUpperCase().replaceFirst('DB', '').trim();
    return double.tryParse(clean);
  }

  // ── Binary helpers ──

  static int _read32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  static int _read32BE(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Read a 32-bit synchsafe integer (7 bits per byte, MSB first).
  static int _readSynchsafe32(Uint8List data, int offset) {
    return (data[offset] & 0x7F) << 21 |
        (data[offset + 1] & 0x7F) << 14 |
        (data[offset + 2] & 0x7F) << 7 |
        (data[offset + 3] & 0x7F);
  }

  void dispose() {
    _currentGain = null;
  }
}

class _VorbisTag {
  final String key;
  final String value;
  const _VorbisTag(this.key, this.value);
}
