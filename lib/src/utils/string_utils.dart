import '../models/work.dart';

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  } else if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  } else if (bytes < 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  } else {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }
}

String formatDuration(Duration duration) {
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  } else {
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }
}

String formatRJCode(int id) {
  String code = id.toString();
  if (code.length == 5) {
    code = '0$code';
  } else if (code.length == 7) {
    code = '0$code';
  }
  return 'RJ$code';
}

/// Extract unique audio format extensions from a list of AudioFile children.
/// Returns a sorted set like {'FLAC', 'MP3', 'WAV'}.
Set<String> extractAudioFormats(List<AudioFile>? children) {
  if (children == null || children.isEmpty) return {};
  final formats = <String>{};
  void walk(List<AudioFile> files) {
    for (final file in files) {
      if (file.isFolder && file.children != null) {
        walk(file.children!);
      } else if (file.isAudio) {
        final ext = file.title.split('.').last.toUpperCase();
        if (ext.isNotEmpty && ext.length <= 5) {
          formats.add(ext);
        }
      }
    }
  }
  walk(children);
  // Normalize common extensions
  final normalized = <String>{};
  for (final f in formats) {
    if (f == 'M4A' || f == 'M4B') normalized.add('AAC');
    else if (f == 'OGG') normalized.add('OGG');
    else if (f == 'OPUS') normalized.add('Opus');
    else normalized.add(f);
  }
  // Sort: FLAC > WAV > MP3 > AAC > OGG > Opus > rest
  final priority = ['FLAC', 'WAV', 'MP3', 'AAC', 'OGG', 'Opus'];
  final sorted = normalized.toList()..sort((a, b) {
    final ia = priority.indexOf(a);
    final ib = priority.indexOf(b);
    if (ia >= 0 && ib >= 0) return ia.compareTo(ib);
    if (ia >= 0) return -1;
    if (ib >= 0) return 1;
    return a.compareTo(b);
  });
  return sorted.toSet();
}

/// Format a duration in seconds to a human-readable string like "2h 15m".
String formatDurationShort(int totalSeconds) {
  final hours = totalSeconds ~/ 3600;
  final minutes = (totalSeconds % 3600) ~/ 60;
  if (hours > 0) {
    return '${hours}h ${minutes}m';
  }
  return '${minutes}m';
}

/// Compute total duration from a list of Works (in seconds).
int totalDurationFromWorks(List<Work> works) {
  return works.fold<int>(0, (sum, w) => sum + (w.duration ?? 0));
}

