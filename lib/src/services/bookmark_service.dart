import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/audio_bookmark.dart';
import 'storage_service.dart';

/// Provider that exposes the [BookmarkService] singleton.
final bookmarkServiceProvider = Provider<BookmarkService>((ref) {
  return BookmarkService.instance;
});

/// Provider that watches all bookmarks and rebuilds when they change.
final allBookmarksProvider = StreamProvider<List<AudioBookmark>>((ref) {
  final service = ref.watch(bookmarkServiceProvider);
  return service.bookmarkStream;
});

/// Provider that filters bookmarks for a specific track.
final trackBookmarksProvider =
    StreamProvider.family<List<AudioBookmark>, String>((ref, trackId) {
  final service = ref.watch(bookmarkServiceProvider);
  return service.bookmarkStream.map(
    (bookmarks) => bookmarks.where((b) => b.trackId == trackId).toList(),
  );
});

/// Service for managing audio bookmarks (timestamp markers).
///
/// Bookmarks are persisted in Hive's settings box under the key 'audio_bookmarks'
/// as a JSON-encoded list. This keeps them included in Backup & Restore
/// automatically (Hive settings box is already backed up).
class BookmarkService {
  BookmarkService._();
  static final BookmarkService instance = BookmarkService._();

  static const _storageKey = 'audio_bookmarks';

  final List<AudioBookmark> _bookmarks = [];
  final _controller = StreamController<List<AudioBookmark>>.broadcast();

  /// Stream that emits the full bookmark list whenever it changes.
  Stream<List<AudioBookmark>> get bookmarkStream => _controller.stream;

  /// Load bookmarks from storage. Called once at app startup.
  Future<void> initialize() async {
    final jsonStr = StorageService.getSetting<String>(_storageKey);
    if (jsonStr == null || jsonStr.isEmpty) return;

    try {
      final list = jsonDecode(jsonStr) as List;
      _bookmarks.clear();
      for (final item in list) {
        _bookmarks.add(AudioBookmark.fromJson(item as Map<String, dynamic>));
      }
    } catch (e) {
      // Corrupted data — start fresh
      _bookmarks.clear();
    }
    _emit();
  }

  /// Add a new bookmark at [position] for the given [trackId].
  /// Returns the created bookmark.
  AudioBookmark add({
    required String trackId,
    int? workId,
    required Duration position,
    String? note,
    String? trackTitle,
  }) {
    // Avoid duplicates at the exact same position (within 1s tolerance)
    final existingIndex = _bookmarks.indexWhere((b) =>
        b.trackId == trackId &&
        (b.position - position).abs().inMilliseconds < 1000);
    if (existingIndex >= 0) {
      // Update existing bookmark's note
      _bookmarks[existingIndex] = _bookmarks[existingIndex].copyWith(
        note: note ?? _bookmarks[existingIndex].note,
        createdAt: DateTime.now(),
      );
      _persist();
      _emit();
      return _bookmarks[existingIndex];
    }

    final bookmark = AudioBookmark(
      id: 'bm_${DateTime.now().millisecondsSinceEpoch}_${_bookmarks.length}',
      trackId: trackId,
      workId: workId,
      position: position,
      note: note,
      trackTitle: trackTitle,
      createdAt: DateTime.now(),
    );
    _bookmarks.add(bookmark);
    _persist();
    _emit();
    return bookmark;
  }

  /// Remove a bookmark by its [id].
  void remove(String id) {
    _bookmarks.removeWhere((b) => b.id == id);
    _persist();
    _emit();
  }

  /// Update the note for a bookmark.
  void updateNote(String id, String note) {
    final index = _bookmarks.indexWhere((b) => b.id == id);
    if (index < 0) return;
    _bookmarks[index] = _bookmarks[index].copyWith(note: note);
    _persist();
    _emit();
  }

  /// Get all bookmarks for a specific track, sorted by position.
  List<AudioBookmark> getForTrack(String trackId) {
    return _bookmarks
        .where((b) => b.trackId == trackId)
        .toList()
      ..sort((a, b) => a.position.compareTo(b.position));
  }

  /// Get all bookmarks, sorted by creation time (newest first).
  List<AudioBookmark> getAll() => List.unmodifiable(_bookmarks)
    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));

  /// Get bookmark count for a track.
  int countForTrack(String trackId) {
    return _bookmarks.where((b) => b.trackId == trackId).length;
  }

  void _persist() {
    final jsonStr = jsonEncode(_bookmarks.map((b) => b.toJson()).toList());
    StorageService.setSetting(_storageKey, jsonStr);
  }

  void _emit() {
    final sorted = List<AudioBookmark>.from(_bookmarks)
      ..sort((a, b) => a.position.compareTo(b.position));
    _controller.add(sorted);
  }

  /// Remove all bookmarks for a specific track.
  void clearForTrack(String trackId) {
    _bookmarks.removeWhere((b) => b.trackId == trackId);
    _persist();
    _emit();
  }

  /// Dispose the stream controller. Call when the service is no longer needed.
  void dispose() {
    _controller.close();
  }
}
