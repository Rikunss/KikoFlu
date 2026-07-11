import 'dart:convert';
import 'package:equatable/equatable.dart';
import 'work.dart';
import 'audio_track.dart';

class HistoryRecord extends Equatable {
  final Work work;
  final DateTime lastPlayedTime;
  final AudioTrack? lastTrack;
  final int lastPositionMs;
  final int playlistIndex;
  final int playlistTotal;

  /// Approximate total time (ms) spent listening to this work across ALL
  /// sessions. Accumulated by [PlaybackHistoryService] on each checkpoint
  /// tick by measuring wall-clock time between ticks when playing.
  final int totalListenedMs;

  const HistoryRecord({
    required this.work,
    required this.lastPlayedTime,
    this.lastTrack,
    this.lastPositionMs = 0,
    this.playlistIndex = 0,
    this.playlistTotal = 0,
    this.totalListenedMs = 0,
  });

  HistoryRecord copyWith({
    Work? work,
    DateTime? lastPlayedTime,
    AudioTrack? lastTrack,
    int? lastPositionMs,
    int? playlistIndex,
    int? playlistTotal,
    int? totalListenedMs,
  }) {
    return HistoryRecord(
      work: work ?? this.work,
      lastPlayedTime: lastPlayedTime ?? this.lastPlayedTime,
      lastTrack: lastTrack ?? this.lastTrack,
      lastPositionMs: lastPositionMs ?? this.lastPositionMs,
      playlistIndex: playlistIndex ?? this.playlistIndex,
      playlistTotal: playlistTotal ?? this.playlistTotal,
      totalListenedMs: totalListenedMs ?? this.totalListenedMs,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'work_id': work.id,
      'work_json': jsonEncode(work.toJson()),
      'last_played_time': lastPlayedTime.millisecondsSinceEpoch,
      'last_track_json':
          lastTrack != null ? jsonEncode(lastTrack!.toJson()) : null,
      'last_position_ms': lastPositionMs,
      'playlist_index': playlistIndex,
      'playlist_total': playlistTotal,
      'total_listened_ms': totalListenedMs,
    };
  }

  factory HistoryRecord.fromMap(Map<String, dynamic> map) {
    return HistoryRecord(
      work: Work.fromJson(jsonDecode(map['work_json'])),
      lastPlayedTime:
          DateTime.fromMillisecondsSinceEpoch(map['last_played_time']),
      lastTrack: map['last_track_json'] != null
          ? AudioTrack.fromJson(jsonDecode(map['last_track_json']))
          : null,
      lastPositionMs: map['last_position_ms'] ?? 0,
      playlistIndex: map['playlist_index'] ?? 0,
      playlistTotal: map['playlist_total'] ?? 0,
      totalListenedMs: map['total_listened_ms'] ?? 0,
    );
  }

  @override
  List<Object?> get props => [
        work,
        lastPlayedTime,
        lastTrack,
        lastPositionMs,
        playlistIndex,
        playlistTotal,
        totalListenedMs,
      ];
}