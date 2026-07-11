/// A bookmark marking a specific timestamp within an audio track.
///
/// Users can add bookmarks during playback to mark favorite moments,
/// scenes, or sections (e.g., ear-cleaning ASMR triggers, whisper parts).
/// Bookmarks are stored persistently and survive app restarts.
class AudioBookmark {
  final String id;
  final String trackId;
  final int? workId;
  final Duration position;
  final String? note;
  final String? trackTitle;
  final DateTime createdAt;

  const AudioBookmark({
    required this.id,
    required this.trackId,
    this.workId,
    required this.position,
    this.note,
    this.trackTitle,
    required this.createdAt,
  });

  /// Format position as HH:MM:SS or MM:SS.
  String get formattedPosition {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = position.inHours;
    final minutes = position.inMinutes.remainder(60);
    final seconds = position.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'trackId': trackId,
        'workId': workId,
        'positionMs': position.inMilliseconds,
        'note': note,
        'trackTitle': trackTitle,
        'createdAt': createdAt.toIso8601String(),
      };

  factory AudioBookmark.fromJson(Map<String, dynamic> json) {
    return AudioBookmark(
      id: json['id'] as String,
      trackId: json['trackId'] as String,
      workId: json['workId'] as int?,
      position: Duration(milliseconds: json['positionMs'] as int),
      note: json['note'] as String?,
      trackTitle: json['trackTitle'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  AudioBookmark copyWith({
    String? id,
    String? trackId,
    int? workId,
    Duration? position,
    String? note,
    String? trackTitle,
    DateTime? createdAt,
  }) {
    return AudioBookmark(
      id: id ?? this.id,
      trackId: trackId ?? this.trackId,
      workId: workId ?? this.workId,
      position: position ?? this.position,
      note: note ?? this.note,
      trackTitle: trackTitle ?? this.trackTitle,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}