import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/playlist.dart';
import '../services/kikoeru_api_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

class PlaylistsState extends Equatable {
  final List<Playlist> playlists;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final int pageSize;

  const PlaylistsState({
    this.playlists = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.pageSize = 20,
  });

  PlaylistsState copyWith({
    List<Playlist>? playlists,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    int? pageSize,
  }) {
    return PlaylistsState(
      playlists: playlists ?? this.playlists,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      pageSize: pageSize ?? this.pageSize,
    );
  }

  @override
  List<Object?> get props => [
        playlists,
        isLoading,
        error,
        currentPage,
        totalCount,
        hasMore,
        pageSize,
      ];
}

class PlaylistsNotifier extends StateNotifier<PlaylistsState> {
  final KikoeruApiService _apiService;

  PlaylistsNotifier(this._apiService, {int initialPageSize = 20})
      : super(PlaylistsState(pageSize: initialPageSize));

  void updatePageSize(int newSize) {
    if (state.pageSize == newSize) return;
    state = state.copyWith(pageSize: newSize);
    load(targetPage: 1);
  }

  Future<void> load({bool refresh = false, int? targetPage}) async {
    if (state.isLoading) return;
    final page = targetPage ?? state.currentPage;

    state = state.copyWith(isLoading: true, error: null, currentPage: page);

    try {
      final result = await _apiService.getUserPlaylists(
        page: page,
        pageSize: state.pageSize,
        filterBy: 'all',
      );

      final List<dynamic> rawList = result['playlists'] as List? ?? [];
      final playlists = rawList
          .map((item) => Playlist.fromJson(item as Map<String, dynamic>))
          .toList();

      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalCount = pagination?['totalCount'] ?? 0;
      final pageSize = pagination?['pageSize'] ?? state.pageSize;

      final totalPages = totalCount > 0 ? (totalCount / pageSize).ceil() : 1;
      final hasMore = page < totalPages;

      state = state.copyWith(
        playlists: playlists,
        totalCount: totalCount,
        hasMore: hasMore,
        isLoading: false,
        currentPage: page,
        pageSize: pageSize,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  Future<void> goToPage(int page) async {
    if (page < 1 || state.isLoading) return;
    await load(targetPage: page);
  }

  Future<void> previousPage() async {
    if (state.currentPage > 1) {
      final prevPage = state.currentPage - 1;
      await load(targetPage: prevPage);
    }
  }

  Future<void> nextPage() async {
    if (state.hasMore) {
      final nextPage = state.currentPage + 1;
      await load(targetPage: nextPage);
    }
  }

  /// 删除播放列表
  /// 根据播放列表的所有者和类型自动选择合适的删除API
  Future<void> deletePlaylist(
    Playlist playlist,
    String currentUserName,
  ) async {
    try {
      final isOwner = playlist.userName == currentUserName;

      if (isOwner) {
        if (playlist.isSystemPlaylist) {
          throw Exception('系统播放列表不能删除');
        }
        await _apiService.deletePlaylist(playlist.id);
      } else {
        await _apiService.removeLikePlaylist(playlist.id);
      }

      await load(refresh: true);
    } catch (e) {
      rethrow;
    }
  }

  void refresh() => load();
}

final playlistsProvider =
    StateNotifierProvider<PlaylistsNotifier, PlaylistsState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  final pageSize = ref.read(pageSizeProvider);
  final notifier = PlaylistsNotifier(apiService, initialPageSize: pageSize);

  ref.listen(pageSizeProvider, (previous, next) {
    if (previous != next) {
      notifier.updatePageSize(next);
    }
  });

  ref.listen(currentUserProvider, (previous, next) {
    final prevUser = previous;
    final nextUser = next;
    if (prevUser?.name != nextUser?.name || prevUser?.host != nextUser?.host) {
      LogService.instance.debug('[PlaylistsProvider] User changed, refreshing playlists', tag: 'UI');
      notifier.refresh();
    }
  });

  return notifier;
});