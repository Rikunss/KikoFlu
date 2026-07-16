import 'dart:convert';
import 'dart:math';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/smart_playlist.dart';
import '../services/storage_service.dart';
import '../services/log_service.dart';
import 'works_provider.dart';

/// Provider for the layout type of smart playlist detail screens.
final smartPlaylistLayoutProvider =
    StateProvider<LayoutType>((ref) => LayoutType.bigGrid);

/// Key used to persist the list of smart playlists in SharedPreferences.
const String _storageKey = 'smart_playlists';

/// Provider that watches the list of all smart playlists.
///
/// Smart playlists are stored locally in SharedPreferences and are
/// not synced to the server.
final smartPlaylistsProvider =
    StateNotifierProvider<SmartPlaylistsNotifier, List<SmartPlaylist>>((ref) {
  return SmartPlaylistsNotifier();
});

class SmartPlaylistsNotifier extends StateNotifier<List<SmartPlaylist>> {
  /// Generate a unique ID for smart playlists.
  String _generateId() {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final random = Random().nextInt(99999);
    return 'sp_${timestamp}_$random';
  }

  SmartPlaylistsNotifier() : super([]) {
    _loadFromStorage();
  }

  /// Load smart playlists from SharedPreferences.
  Future<void> _loadFromStorage() async {
    try {
      final jsonString = StorageService.getString(_storageKey);
      if (jsonString != null && jsonString.isNotEmpty) {
        final List<dynamic> decoded = jsonDecode(jsonString);
        final playlists = decoded
            .map((e) => SmartPlaylist.fromJson(e as Map<String, dynamic>))
            .toList()
          ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        state = playlists;
      }
    } catch (e) {
      state = [];
    }
  }

  /// Save smart playlists to SharedPreferences.
  Future<void> _saveToStorage() async {
    try {
      final jsonString = jsonEncode(state.map((p) => p.toJson()).toList());
      await StorageService.setString(_storageKey, jsonString);
    } catch (e) {
      LogService.instance.warning('[SmartPlaylists] Failed to save: $e', tag: 'Settings');
    }
  }

  /// Create a new smart playlist.
  Future<SmartPlaylist> create({
    required String name,
    String description = '',
    List<SmartPlaylistRule> rules = const [],
    SmartPlaylistSortField sortField = SmartPlaylistSortField.release,
    String sortDirection = 'desc',
  }) async {
    final now = DateTime.now();
    final playlist = SmartPlaylist(
      id: _generateId(),
      name: name,
      description: description,
      rules: rules,
      sortField: sortField,
      sortDirection: sortDirection,
      createdAt: now,
      updatedAt: now,
    );
    state = [playlist, ...state];
    await _saveToStorage();
    return playlist;
  }

  /// Update an existing smart playlist.
  Future<void> update(SmartPlaylist updated) async {
    state = [
      updated.copyWith(updatedAt: DateTime.now()),
      ...state.where((p) => p.id != updated.id),
    ];
    await _saveToStorage();
  }

  /// Delete a smart playlist.
  Future<void> delete(String id) async {
    state = state.where((p) => p.id != id).toList();
    await _saveToStorage();
  }

  /// Update the cached works count for a smart playlist.
  Future<void> updateCachedCount(String id, int count) async {
    state = state.map((p) {
      if (p.id == id) {
        return p.copyWith(cachedWorksCount: count);
      }
      return p;
    }).toList();
    await _saveToStorage();
  }
}