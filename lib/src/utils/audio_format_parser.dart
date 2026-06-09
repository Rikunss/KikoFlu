import 'dart:io';
import 'package:flutter/foundation.dart';
import '../services/log_service.dart';

/// Information about the current audio track's format.
class AudioFormatInfo {
  /// Codec name (e.g. FLAC, WAV, MP3, Opus).
  final String codec;

  /// Sample rate in Hz (e.g. 44100, 48000, 96000, 192000). May be null if unknown.
  final int? sampleRate;

  /// Bits per sample (e.g. 16, 24, 32). May be null if unknown.
  final int? bitDepth;

  /// Number of audio channels. May be null if unknown.
  final int? channels;

  /// Actual encoded bitrate in kbps (e.g. MP3 at 320kbps).
  /// Only populated for lossy codecs where the frame header contains
  /// the actual bitrate. For PCM-based codecs, use [estimatedBitrateKbps].
  final int? encodedBitrateKbps;

  const AudioFormatInfo({
    required this.codec,
    this.sampleRate,
    this.bitDepth,
    this.channels,
    this.encodedBitrateKbps,
  });

  /// Human-readable display string: "FLAC · 96.0kHz · 24bit"
  String get displayString {
    final parts = <String>[codec.toUpperCase()];
    if (sampleRate != null) {
      parts.add('${(sampleRate! / 1000).toStringAsFixed(1)}kHz');
    }
    if (bitDepth != null) {
      parts.add('${bitDepth}bit');
    }
    return parts.join(' · ');
  }

  /// Estimated bitrate in kbps.
  /// For PCM-based codecs (FLAC, WAV, AIFF): sampleRate × bitDepth × channels / 1000.
  /// For lossy codecs: falls back to [encodedBitrateKbps] (actual frame bitrate)
  /// when bitDepth is null. Returns null if neither source is available.
  int? get estimatedBitrateKbps {
    if (sampleRate != null && bitDepth != null) {
      return (sampleRate! * bitDepth! * (channels ?? 2)) ~/ 1000;
    }
    return encodedBitrateKbps;
  }

  /// Create format info from a URL by extracting the file extension from the
  /// URI path. Unlike the old implementation which naively used `split('.')`
  /// on the raw URL string (broken for IP-address hosts and hash-based
  /// streaming URLs), this parses the URL properly with [Uri.parse] and
  /// extracts the filename extension from the last path segment.
  static AudioFormatInfo fromUrl(String url) {
    String ext = '';
    try {
      final uri = Uri.parse(url);
      final path = uri.path;
      final filename = path.split('/').last;
      if (filename.contains('.')) {
        ext = filename.split('.').last.toLowerCase();
      }
    } catch (_) {
      // Fallback: try the old split method as a last resort
      final cleanUrl = url.split('?')[0].split('#')[0];
      ext = cleanUrl.split('.').last.toLowerCase();
    }

    switch (ext) {
      case 'flac':
        return const AudioFormatInfo(codec: 'FLAC');
      case 'wav':
        return const AudioFormatInfo(codec: 'WAV');
      case 'mp3':
        return const AudioFormatInfo(codec: 'MP3');
      case 'ogg':
        return const AudioFormatInfo(codec: 'OGG');
      case 'opus':
        return const AudioFormatInfo(codec: 'Opus');
      case 'm4a':
        return const AudioFormatInfo(codec: 'M4A');
      case 'aac':
        return const AudioFormatInfo(codec: 'AAC');
      default:
        return AudioFormatInfo(codec: ext.isNotEmpty ? ext.toUpperCase() : 'Unknown');
    }
  }

  /// Fetch audio format info from a streaming URL by requesting the first
  /// ~64 KB of the file via an HTTP Range header and parsing the header bytes.
  /// Falls back to [fromUrl] if the request fails or the server does not
  /// return parseable header data.
  static Future<AudioFormatInfo> fromStreamUrl(String url) async {
    final extensionInfo = fromUrl(url);

    try {
      final uri = Uri.parse(url);
      if (uri.scheme != 'http' && uri.scheme != 'https') {
        return extensionInfo;
      }

      final client = HttpClient();
      try {
        final request = await client
            .getUrl(uri)
            .timeout(const Duration(seconds: 5));
        request.headers.set('Range', 'bytes=0-65535');
        final response = await request
            .close()
            .timeout(const Duration(seconds: 5));

        if (response.statusCode != HttpStatus.partialContent &&
            response.statusCode != HttpStatus.ok) {
          return extensionInfo;
        }

        // Read up to ~64 KB
        final chunks = <List<int>>[];
        int totalRead = 0;
        await for (final chunk in response) {
          chunks.add(chunk);
          totalRead += chunk.length;
          if (totalRead >= 65536) break;
        }

        final bytes = Uint8List(totalRead);
        int offset = 0;
        for (final chunk in chunks) {
          bytes.setRange(offset, offset + chunk.length, chunk);
          offset += chunk.length;
        }

        final parsed = _parseFromBytes(bytes);
        if (parsed != null) return parsed;
      } finally {
        client.close();
      }
    } catch (e) {
      LogService.instance.warning('[AudioFormatParser] Failed to parse streaming URL headers: $e', tag: 'Playback');
    }

    return extensionInfo;
  }

  /// Try to detect format and parse header bytes from a raw [Uint8List].
  /// Returns null if the format cannot be determined from the bytes.
  static AudioFormatInfo? _parseFromBytes(Uint8List data) {
    if (data.length < 4) return null;

    // FLAC — magic "fLaC" at offset 0
    if (data[0] == 0x66 &&
        data[1] == 0x4C &&
        data[2] == 0x61 &&
        data[3] == 0x43) {
      return data.length >= 42 ? _parseFlacHeader(data) : null;
    }

    // WAV — magic "RIFF" at offset 0
    if (data[0] == 0x52 &&
        data[1] == 0x49 &&
        data[2] == 0x46 &&
        data[3] == 0x46) {
      return data.length >= 36 ? _parseWavHeader(data) : null;
    }

    // Ogg/Opus — magic "OggS" at offset 0
    if (data[0] == 0x4F &&
        data[1] == 0x67 &&
        data[2] == 0x67 &&
        data[3] == 0x53) {
      return _parseOggOpusHeader(data);
    }

    // M4A/MP4 — first box type "ftyp" at offset 4
    if (data.length >= 8 &&
        data[4] == 0x66 &&
        data[5] == 0x74 &&
        data[6] == 0x79 &&
        data[7] == 0x70) {
      return _parseM4aHeader(data);
    }

    // MP3 — ID3v2 tag "ID3" at offset 0
    if (data.length >= 3 &&
        data[0] == 0x49 &&
        data[1] == 0x44 &&
        data[2] == 0x33) {
      return _parseMp3Header(data);
    }

    // MP3 — raw sync word 0xFF at offset 0
    if (data[0] == 0xFF) {
      return _parseMp3Header(data);
    }

    // Fallback: check for MP4 with different box order
    if (data.length >= 8 && _isBoxType(data, 4, 'mp4a')) {
      return _parseM4aHeader(data);
    }

    return null;
  }

  /// Read a local audio file and parse its header to determine format details
  /// (sample rate, bit depth, channels). Falls back to [fromUrl] on failure.
  static Future<AudioFormatInfo> fromFile(String filePath) async {
    try {
      final file = File(filePath);
      if (!await file.exists()) {
        return fromUrl(filePath);
      }

      final raf = await file.open(mode: FileMode.read);
      try {
        const readSize = 32768;
        final data = await raf.read(readSize);
        if (data.length < 4) return fromUrl(filePath);

        final parsed = _parseFromBytes(data);
        if (parsed != null) return parsed;
      } finally {
        await raf.close();
      }
    } catch (e) {
      LogService.instance.warning('[AudioFormatParser] Error parsing file: $e', tag: 'Playback');
    }
    return fromUrl(filePath);
  }

  // ---------------------------------------------------------------------------
  // Internal helpers
  // ---------------------------------------------------------------------------

  /// Read a big-endian 32-bit unsigned integer.
  static int _read32(Uint8List data, int offset) {
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  /// Read a little-endian 32-bit unsigned integer.
  static int _read32LE(Uint8List data, int offset) {
    return data[offset] |
        (data[offset + 1] << 8) |
        (data[offset + 2] << 16) |
        (data[offset + 3] << 24);
  }

  /// Read a big-endian 16-bit unsigned integer.
  static int _read16(Uint8List data, int offset) {
    return (data[offset] << 8) | data[offset + 1];
  }

  /// Read a little-endian 16-bit unsigned integer.
  static int _read16LE(Uint8List data, int offset) {
    return data[offset] | (data[offset + 1] << 8);
  }

  /// Check if the 4 bytes at [offset] match the given ASCII [type].
  static bool _isBoxType(Uint8List data, int offset, String type) {
    if (offset + 4 > data.length) return false;
    for (int i = 0; i < 4; i++) {
      if (data[offset + i] != type.codeUnitAt(i)) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // FLAC parser
  // ---------------------------------------------------------------------------

  /// Parse FLAC STREAMINFO metadata block.
  /// File offset 0: "fLaC" (4 bytes)
  /// File offset 4: METADATA_BLOCK_HEADER (4 bytes: is_last|type|length)
  /// File offset 8: STREAMINFO (34 bytes)
  ///   sample_rate:       20 bits at offset 18, lower nibble of byte 18 + bytes 19-20
  ///   channels-1:         3 bits at offset 21 bits 7-5
  ///   bits-per-sample-1:  5 bits at offset 21 bits 4-0
  static AudioFormatInfo _parseFlacHeader(Uint8List data) {
    if (data.length < 42) {
      return const AudioFormatInfo(codec: 'FLAC');
    }

    final int sampleRate =
        ((data[18] & 0x0F) << 16) | (data[19] << 8) | data[20];
    final int channels = ((data[21] >> 5) & 0x07) + 1;
    final int bitsPerSample = (data[21] & 0x1F) + 1;

    return AudioFormatInfo(
      codec: 'FLAC',
      sampleRate: sampleRate > 0 ? sampleRate : null,
      bitDepth: bitsPerSample > 0 ? bitsPerSample : null,
      channels: channels > 0 ? channels : null,
    );
  }

  // ---------------------------------------------------------------------------
  // WAV parser
  // ---------------------------------------------------------------------------

  /// Parse WAV file header.
  /// "RIFF" at offset 0, then "WAVE" at 8, then "fmt " sub-chunk.
  static AudioFormatInfo _parseWavHeader(Uint8List data) {
    if (data.length < 36) {
      return const AudioFormatInfo(codec: 'WAV');
    }

    // Search for "fmt " chunk
    int offset = 12;
    bool found = false;
    while (offset + 8 <= data.length) {
      if (data[offset] == 0x66 &&
          data[offset + 1] == 0x6D &&
          data[offset + 2] == 0x74 &&
          data[offset + 3] == 0x20) {
        found = true;
        break;
      }
      if (offset + 8 > data.length - 4) break;
      final chunkSize = _read32LE(data, offset + 4);
      offset += 8 + chunkSize;
      if (offset > data.length) break;
    }

    if (!found || offset + 24 > data.length) {
      return const AudioFormatInfo(codec: 'WAV');
    }

    final int channels = _read16LE(data, offset + 10);
    final int sampleRate = _read32LE(data, offset + 12);
    final int bitsPerSample = _read16LE(data, offset + 22);

    return AudioFormatInfo(
      codec: 'WAV',
      sampleRate: sampleRate > 0 ? sampleRate : null,
      bitDepth: bitsPerSample > 0 ? bitsPerSample : null,
      channels: channels > 0 ? channels : null,
    );
  }

  // ---------------------------------------------------------------------------
  // Ogg / Opus parser
  // ---------------------------------------------------------------------------

  /// Parse the first Ogg page to find the OpusHead identification header.
  ///
  /// Ogg page header (27 bytes):
  ///   [0-3]   "OggS" magic
  ///   [4]     version (0x00)
  ///   [5]     header_type
  ///   [6-13]  granule_position (64-bit LE)
  ///   [14-17] bitstream_serial_number (32-bit LE)
  ///   [18-21] page_sequence_number (32-bit LE)
  ///   [22-25] CRC_checksum (32-bit LE)
  ///   [26]    page_segments (count)
  ///   [27+]   segment_table (sum = total packet data size)
  ///
  /// OpusHead packet:
  ///   [0-7]   "OpusHead" magic
  ///   [8]     version
  ///   [9]     channel count
  ///   [10-11] pre-skip (16-bit LE)
  ///   [12-15] input sample rate (32-bit LE)
  ///   [16-17] output gain (16-bit LE)
  ///   [18]    channel mapping family
  static AudioFormatInfo _parseOggOpusHeader(Uint8List data) {
    if (data.length < 27) {
      return const AudioFormatInfo(codec: 'Opus');
    }

    // Ogg page header is 27 bytes + segment table
    final pageSegments = data[26];
    final segmentTableEnd = 27 + pageSegments;
    if (segmentTableEnd > data.length) {
      return const AudioFormatInfo(codec: 'Opus');
    }

    // Calculate the packet data start and verify it's within bounds
    final packetStart = segmentTableEnd;

    if (packetStart + 8 > data.length) {
      return const AudioFormatInfo(codec: 'Opus');
    }

    // Check for "OpusHead" magic at packet start
    if (!_isBoxType(data, packetStart, 'Opus')) {
      return const AudioFormatInfo(codec: 'OGG');
    }
    // Verify "Head" suffix manually since _isBoxType checks 4 bytes only
    if (packetStart + 8 > data.length ||
        data[packetStart + 4] != 0x48 || // 'H'
        data[packetStart + 5] != 0x65 || // 'e'
        data[packetStart + 6] != 0x61 || // 'a'
        data[packetStart + 7] != 0x64) { // 'd'
      return const AudioFormatInfo(codec: 'OGG');
    }

    if (packetStart + 19 > data.length) {
      return const AudioFormatInfo(codec: 'Opus');
    }

    final channels = data[packetStart + 9];
    final sampleRate = _read32LE(data, packetStart + 12);

    return AudioFormatInfo(
      codec: 'Opus',
      sampleRate: sampleRate > 0 ? sampleRate : null,
      bitDepth: null, // Opus is a variable-bit-depth codec internally
      channels: channels > 0 ? channels : null,
    );
  }

  // ---------------------------------------------------------------------------
  // M4A / MP4 (ISOBMFF) parser
  // ---------------------------------------------------------------------------

  /// Recursively search the ISOBMFF box hierarchy for an `mp4a` box and parse
  /// its audio sample entry fields.
  ///
  /// Box header: size (4 bytes BE) + type (4 bytes ASCII)
  /// Container boxes we traverse: moov, trak, mdia, minf, dinf, stbl, stsd, udta
  ///
  /// mp4a (AudioSampleEntry) layout (after 8-byte header):
  ///   [0-5]   reserved (6 bytes)
  ///   [6-7]   data reference index
  ///   [8-9]   version
  ///   [10-11] revision
  ///   [12-15] vendor
  ///   [16-17] channel count
  ///   [18-19] sample size (bits per sample)
  ///   [20-21] compression ID
  ///   [22-23] packet size
  ///   [24-27] sample rate (16.16 fixed-point BE)
  static AudioFormatInfo _parseM4aHeader(Uint8List data) {
    // Recursively search for "mp4a" box within the ISOBMFF hierarchy
    Uint8List? mp4aBox = _findBox(data, 0, data.length, 'mp4a');
    if (mp4aBox == null || mp4aBox.length < 36) {
      return const AudioFormatInfo(codec: 'M4A');
    }

    // mp4a box fields relative to box data start (offset 8 from box header)
    // Since _findBox returns data starting from the box header,
    // the fields start at offset 8 (after size + type)
    const int base = 8;

    final channels = _read16(mp4aBox, base + 16);
    final bitsPerSample = _read16(mp4aBox, base + 18);
    final sampleRateFixed = _read32(mp4aBox, base + 24);
    final sampleRate = sampleRateFixed >> 16; // 16.16 fixed-point

    return AudioFormatInfo(
      codec: 'M4A',
      sampleRate: sampleRate > 0 ? sampleRate : null,
      bitDepth: bitsPerSample > 0 ? bitsPerSample : null,
      channels: channels > 0 ? channels : null,
    );
  }

  /// Depth-first search for an ISOBMFF box by [targetType] within [data] from
  /// [startOffset] to [endLimit]. Container boxes are entered recursively.
  /// Returns the entire box content (including its header) or null.
  static Uint8List? _findBox(
      Uint8List data, int startOffset, int endLimit, String targetType) {
    int i = startOffset;
    while (i + 8 <= endLimit) {
      final int size = _read32(data, i);
      if (size < 8) break; // invalid box

      final int end = (i + size > endLimit || size == 0) ? endLimit : i + size;

      // Check box type (4 bytes at i+4)
      bool typeMatches = true;
      for (int j = 0; j < 4; j++) {
        if (data[i + 4 + j] != targetType.codeUnitAt(j)) {
          typeMatches = false;
          break;
        }
      }

      if (typeMatches) {
        return data.sublist(i, end);
      }

      // Container boxes — recurse into their contents
      if (_isContainerBox(data, i + 4)) {
        final result = _findBox(data, i + 8, end, targetType);
        if (result != null) return result;
      }

      i = end;
      if (i >= endLimit) break;
    }
    return null;
  }

  /// Known ISOBMFF container box types that may contain audio sample entries.
  static bool _isContainerBox(Uint8List data, int typeOffset) {
    if (typeOffset + 4 > data.length) return false;
    // Read the 4-byte type at the given offset and compare
    const types = [
      'moov', 'trak', 'edts', 'mdia', 'minf',
      'dinf', 'stbl', 'udta', 'mvex', 'moof',
      'traf', 'mfra', 'skip', 'free', 'meta',
      'ipro', 'sinf', 'schi', 'wave',
    ];
    for (final t in types) {
      bool match = true;
      for (int j = 0; j < 4; j++) {
        if (data[typeOffset + j] != t.codeUnitAt(j)) {
          match = false;
          break;
        }
      }
      if (match) return true;
    }
    return false;
  }

  // ---------------------------------------------------------------------------
  // MP3 (MPEG Audio Layer III) parser
  // ---------------------------------------------------------------------------

  /// Parse the first valid MPEG audio frame header in the data to extract
  /// sample rate and channel mode.
  ///
  /// Handles ID3v2 tags by skipping the tag header using synchsafe integer.
  ///
  /// ID3v2 header (10 bytes):
  ///   [0-2]   "ID3"
  ///   [3]     major version
  ///   [4]     minor version
  ///   [5]     flags
  ///   [6-9]   size (synchsafe integer, 28 bits: 7 bits per byte)
  ///
  /// MPEG frame header (4 bytes, big-endian):
  ///   byte 0 bits 7-0: sync word (0xFF)
  ///   byte 1 bits 7-5: sync cont. (= 111)
  ///   byte 1 bits 4-3: MPEG version ID (00=2.5, 10=2, 11=1)
  ///   byte 1 bits 2-1: layer (01=III, 10=II, 11=I)
  ///   byte 1 bit 0:    protection
  ///   byte 2 bits 7-4: bitrate index
  ///   byte 2 bits 3-2: sample rate index (00/01/10)
  ///   byte 2 bits 1-0: padding + private
  ///   byte 3 bits 7-6: channel mode (00=Stereo, 01=Joint, 10=Dual, 11=Mono)
  ///   byte 3 bits 5-0: mode extension, copyright, original, emphasis
  static AudioFormatInfo _parseMp3Header(Uint8List data) {
    // Skip ID3v2 tag if present
    int offset = 0;
    if (data.length >= 10 &&
        data[0] == 0x49 &&
        data[1] == 0x44 &&
        data[2] == 0x33) {
      // Parse ID3v2 synchsafe size (bytes 6-9, 7 bits each)
      final int tagSize = (data[6] << 21) |
          (data[7] << 14) |
          (data[8] << 7) |
          data[9];
      offset = 10 + tagSize;
      // Clamp offset to data length
      if (offset >= data.length) {
        return const AudioFormatInfo(codec: 'MP3');
      }
    }

    // Search for valid sync word: 0xFF followed by (byte & 0xE0) == 0xE0
    final syncOffset = _findMp3Sync(data, offset);
    if (syncOffset < 0 || syncOffset + 4 > data.length) {
      return const AudioFormatInfo(codec: 'MP3');
    }

    // Parse the 4-byte frame header at syncOffset
    final b1 = data[syncOffset + 1];
    final b2 = data[syncOffset + 2];
    final b3 = data[syncOffset + 3];

    final int versionID = (b1 >> 3) & 0x03;
    final int layer = (b1 >> 1) & 0x03;
    final int sampleRateIndex = (b2 >> 2) & 0x03;
    final int channelMode = b3 >> 6;

    // Validate: version 01 is reserved, layer 00 is reserved,
    // sampleRateIndex 11 is reserved, bitrate index 0x0F is 'bad'
    if (versionID == 0x01 ||
        layer == 0x00 ||
        sampleRateIndex == 0x03 ||
        (b2 >> 4) == 0x0F) {
      return const AudioFormatInfo(codec: 'MP3');
    }

    // Sample rate lookup
    final int? sampleRate = _mp3SampleRate(versionID, sampleRateIndex);
    final int bitrateIndex = (b2 >> 4) & 0x0F;
    final int? bitrateKbps = _mp3Bitrate(versionID, layer, bitrateIndex);

    // Channel mode
    final int? channels;
    switch (channelMode) {
      case 3: // 11 = Single Channel (Mono)
        channels = 1;
        break;
      default: // 00 = Stereo, 01 = Joint Stereo, 10 = Dual Channel
        channels = 2;
    }

    String codecName;
    if (layer == 0x01) {
      codecName = 'MP3'; // Layer III
    } else if (layer == 0x02) {
      codecName = 'MP2'; // Layer II
    } else {
      codecName = 'MP1'; // Layer I
    }

    return AudioFormatInfo(
      codec: codecName,
      sampleRate: sampleRate,
      bitDepth: null, // MP3 decoded output is decoder-dependent
      channels: channels,
      encodedBitrateKbps: bitrateKbps,
    );
  }

  /// Look up the sample rate in Hz for a given MPEG version and sample rate
  /// index.
  ///
  /// versionID: 0=MPEG2.5, 2=MPEG2, 3=MPEG1
  /// index:     0=00, 1=01, 2=10 (3=reserved, caller should have excluded it)
  static int? _mp3SampleRate(int versionID, int index) {
    switch (versionID) {
      case 3: // MPEG 1
        return [44100, 48000, 32000][index];
      case 2: // MPEG 2
        return [22050, 24000, 16000][index];
      case 0: // MPEG 2.5
        return [11025, 12000, 8000][index];
      default:
        return null;
    }
  }

  /// Look up the actual encoded bitrate in kbps for a given MPEG version,
  /// layer, and bitrate index. Returns null for 'free' (index 0) or 'bad'
  /// (index 15) values.
  ///
  /// bitrateIndex: 0=free, 1-14=standard values, 15=bad
  /// versionID:    0=MPEG2.5, 2=MPEG2, 3=MPEG1
  /// layer:        1=Layer III, 2=Layer II, 3=Layer I
  static int? _mp3Bitrate(int versionID, int layer, int bitrateIndex) {
    if (bitrateIndex == 0 || bitrateIndex == 15) return null;

    // Layer I bitrates (all versions)
    if (layer == 0x03) {
      // MPEG1 Layer I: 32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448
      // MPEG2/2.5 Layer I: 32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256
      if (versionID == 3) {
        return [32, 64, 96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448][bitrateIndex - 1];
      }
      return [32, 48, 56, 64, 80, 96, 112, 128, 144, 160, 176, 192, 224, 256][bitrateIndex - 1];
    }

    // Layer II bitrates
    if (layer == 0x02) {
      if (versionID == 3) {
        return [32, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 384][bitrateIndex - 1];
      }
      return [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160][bitrateIndex - 1];
    }

    // Layer III bitrates
    if (versionID == 3) {
      return [32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320][bitrateIndex - 1];
    }
    // MPEG2 / MPEG2.5 Layer III
    return [8, 16, 24, 32, 40, 48, 56, 64, 80, 96, 112, 128, 144, 160][bitrateIndex - 1];
  }

  /// Scan [data] starting at [startOffset] for a valid MPEG sync word.
  /// Returns the offset of the sync word (first 0xFF byte) or -1 if not found.
  static int _findMp3Sync(Uint8List data, int startOffset) {
    for (int i = startOffset; i < data.length - 1; i++) {
      if (data[i] == 0xFF && (data[i + 1] & 0xE0) == 0xE0) {
        return i;
      }
    }
    return -1;
  }
}
