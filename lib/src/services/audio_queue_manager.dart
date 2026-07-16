import 'dart:async';
import 'package:just_audio/just_audio.dart';
import '../models/audio_track.dart';

/// Manages the playback queue for [AudioPlayerService].
///
/// Responsible for track ordering, index tracking, and all queue
/// mutation operations. Does NOT hold any audio player reference —
/// the caller (AudioPlayerService) provides callbacks for loading
/// tracks and controlling playback.
class AudioQueueManager {
  final List<AudioTrack> _queue = [];
  int _currentIndex = 0;
  LoopMode _appLoopMode = LoopMode.off;

  final StreamController<List<AudioTrack>> _queueController =
      StreamController<List<AudioTrack>>.broadcast();
  final StreamController<AudioTrack?> _currentTrackController =
      StreamController<AudioTrack?>.broadcast();

  /// Callbacks for the parent to respond to queue actions.
  final Future<void> Function(AudioTrack track, {int startPositionMs})
      onLoadTrack;
  final Future<void> Function() onPlay;

  AudioQueueManager({
    required this.onLoadTrack,
    required this.onPlay,
  });

  // ── Getters ──

  LoopMode get appLoopMode => _appLoopMode;
  List<AudioTrack> get queue => List.unmodifiable(_queue);
  int get currentIndex => _currentIndex;
  AudioTrack? get currentTrack =>
      _queue.isNotEmpty && _currentIndex < _queue.length
          ? _queue[_currentIndex]
          : null;
  bool get hasNext => _currentIndex < _queue.length - 1;
  bool get hasPrevious => _currentIndex > 0;
  Stream<List<AudioTrack>> get queueStream => _queueController.stream;
  Stream<AudioTrack?> get currentTrackStream =>
      _currentTrackController.stream;

  // ── Queue Mutations ──

  Future<void> updateQueue(List<AudioTrack> tracks,
      {int startIndex = 0}) async {
    _queue.clear();
    _queue.addAll(tracks);
    _currentIndex = startIndex.clamp(0, tracks.length - 1);
    _queueController.add(List.from(_queue));

    if (tracks.isNotEmpty && _currentIndex < tracks.length) {
      _currentTrackController.add(tracks[_currentIndex]);
      await onLoadTrack(tracks[_currentIndex]);
    }
  }

  Future<void> skipToNext() async {
    if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
      _currentIndex++;
      _currentTrackController.add(_queue[_currentIndex]);
      await onLoadTrack(_queue[_currentIndex]);
      await onPlay();
    } else {
      throw Exception('没有下一首可播放');
    }
  }

  Future<void> skipToPrevious() async {
    if (_queue.isNotEmpty && _currentIndex > 0) {
      _currentIndex--;
      _currentTrackController.add(_queue[_currentIndex]);
      await onLoadTrack(_queue[_currentIndex]);
      await onPlay();
    } else {
      throw Exception('没有上一首可播放');
    }
  }

  Future<void> skipToIndex(int index) async {
    if (index >= 0 && index < _queue.length) {
      _currentIndex = index;
      _currentTrackController.add(_queue[_currentIndex]);
      await onLoadTrack(_queue[_currentIndex]);
      await onPlay();
    }
  }

  Future<void> removeTrackAt(int index) async {
    if (index < 0 || index >= _queue.length) return;

    final wasCurrent = index == _currentIndex;
    final currentTrackId =
        (_queue.isNotEmpty && _currentIndex < _queue.length)
            ? _queue[_currentIndex].id
            : null;

    _queue.removeAt(index);
    _queueController.add(List.from(_queue));

    if (_queue.isEmpty) {
      _currentIndex = 0;
      _currentTrackController.add(null);
      return;
    }

    if (wasCurrent) {
      if (_currentIndex >= _queue.length) {
        _currentIndex = _queue.length - 1;
      }
      _currentTrackController.add(_queue[_currentIndex]);
      await onLoadTrack(_queue[_currentIndex]);
      await onPlay();
      return;
    }

    if (currentTrackId != null) {
      final updatedIndex =
          _queue.indexWhere((track) => track.id == currentTrackId);
      if (updatedIndex != -1) _currentIndex = updatedIndex;
    }
  }

  Future<void> clearQueue() async {
    _queue.clear();
    _currentIndex = 0;
    _queueController.add(List.from(_queue));
    _currentTrackController.add(null);
  }

  Future<void> moveTrack(int oldIndex, int newIndex) async {
    if (oldIndex < 0 || oldIndex >= _queue.length) return;
    if (newIndex < 0) {
      newIndex = 0;
    } else if (newIndex > _queue.length) {
      newIndex = _queue.length;
    }
    if (newIndex > oldIndex) newIndex -= 1;
    if (oldIndex == newIndex) return;

    final currentTrackId =
        (_queue.isNotEmpty && _currentIndex < _queue.length)
            ? _queue[_currentIndex].id
            : null;

    final track = _queue.removeAt(oldIndex);
    _queue.insert(newIndex, track);

    if (currentTrackId != null) {
      final updatedIndex =
          _queue.indexWhere((element) => element.id == currentTrackId);
      if (updatedIndex != -1) _currentIndex = updatedIndex;
    }
    _queueController.add(List.from(_queue));
  }

  Future<void> insertTracksAfterCurrent(List<AudioTrack> tracks) async {
    if (tracks.isEmpty) return;

    final existingIds = _queue.map((t) => t.id).toSet();
    final newTracks =
        tracks.where((t) => !existingIds.contains(t.id)).toList();

    if (newTracks.isEmpty) {
      if (_queue.isNotEmpty && _currentIndex < _queue.length - 1) {
        _currentIndex++;
        _currentTrackController.add(_queue[_currentIndex]);
        await onLoadTrack(_queue[_currentIndex]);
        await onPlay();
      }
      return;
    }

    if (_queue.isEmpty) {
      await updateQueue(newTracks, startIndex: 0);
      await onPlay();
      return;
    }

    if (_currentIndex >= _queue.length - 1) {
      final indexMap = await appendTracks(newTracks);
      final firstNew = newTracks.first;
      final targetIdx = indexMap[firstNew.id];
      if (targetIdx != null) {
        _currentIndex = targetIdx;
        _currentTrackController.add(_queue[_currentIndex]);
        await onLoadTrack(_queue[_currentIndex]);
        await onPlay();
      }
      return;
    }

    final insertPos = _currentIndex + 1;
    _queue.insertAll(insertPos, newTracks);
    _queueController.add(List.from(_queue));
    _currentIndex = insertPos;
    _currentTrackController.add(_queue[_currentIndex]);
    await onLoadTrack(_queue[_currentIndex]);
    await onPlay();
  }

  Future<Map<String, int>> appendTracks(List<AudioTrack> tracks) async {
    final indexMap = <String, int>{};
    if (tracks.isEmpty) return indexMap;

    if (_queue.isEmpty) {
      await updateQueue(tracks);
      for (var i = 0; i < _queue.length; i++) {
        indexMap[_queue[i].id] = i;
      }
      return indexMap;
    }

    final existingIdx = <String, int>{};
    for (var i = 0; i < _queue.length; i++) {
      existingIdx[_queue[i].id] = i;
    }

    bool appended = false;
    for (final track in tracks) {
      final existing = existingIdx[track.id];
      if (existing != null) {
        indexMap[track.id] = existing;
        continue;
      }
      _queue.add(track);
      indexMap[track.id] = _queue.length - 1;
      appended = true;
    }

    if (appended) _queueController.add(List.from(_queue));

    for (final track in tracks) {
      indexMap[track.id] ??= existingIdx[track.id] ??
          _queue.indexWhere((e) => e.id == track.id);
    }
    return indexMap;
  }

  /// Advance to the next track after completion.
  /// Returns false when queue is exhausted (caller should pause).
  Future<bool> handleCompletion() async {
    if (_appLoopMode == LoopMode.one) {
      // LoopMode.one is handled by the caller (seek to 0 and play)
      return true;
    }

    if (_currentIndex < _queue.length - 1) {
      _currentIndex++;
      _currentTrackController.add(_queue[_currentIndex]);
      await onLoadTrack(_queue[_currentIndex]);
      await onPlay();
      return true;
    }

    if (_appLoopMode == LoopMode.all && _queue.isNotEmpty) {
      _currentIndex = 0;
      _currentTrackController.add(_queue[0]);
      await onLoadTrack(_queue[0]);
      await onPlay();
      return true;
    }

    return false; // queue exhausted
  }

  Future<void> setRepeatMode(LoopMode mode) async {
    _appLoopMode = mode;
  }

  void dispose() {
    _queueController.close();
    _currentTrackController.close();
  }
}
