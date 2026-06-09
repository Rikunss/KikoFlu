import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/smart_playlist.dart';
import '../models/work.dart';
import '../services/kikoeru_api_service.dart' hide kikoeruApiServiceProvider;
import 'auth_provider.dart' show kikoeruApiServiceProvider;

/// State for a smart playlist evaluation.
class SmartPlaylistEvalState {
  final List<Work> works;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final bool hasMore;
  final int totalCount;

  const SmartPlaylistEvalState({
    this.works = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.hasMore = false,
    this.totalCount = 0,
  });

  SmartPlaylistEvalState copyWith({
    List<Work>? works,
    bool? isLoading,
    String? error,
    int? currentPage,
    bool? hasMore,
    int? totalCount,
  }) {
    return SmartPlaylistEvalState(
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      totalCount: totalCount ?? this.totalCount,
    );
  }
}

/// Evaluates a smart playlist by building a search query from its rules
/// and fetching matching works from the API.
class SmartPlaylistEvaluatorNotifier
    extends StateNotifier<SmartPlaylistEvalState> {
  final KikoeruApiService _api;
  final SmartPlaylist _playlist;

  SmartPlaylistEvaluatorNotifier(this._api, this._playlist)
      : super(const SmartPlaylistEvalState()) {
    load();
  }

  /// Build a search keyword string from the playlist's rules.
  /// Uses the custom search syntax: `$tag:name$`, `$va:name$`, `$circle:name$`, `$age:general$`
  String _buildKeyword() {
    final parts = <String>[];
    for (final rule in _playlist.rules) {
      switch (rule.type) {
        case SmartPlaylistRuleType.tag:
          final prefix = rule.isExclude ? '-\$tag:' : '\$tag:';
          parts.add('$prefix${rule.value}\$');
        case SmartPlaylistRuleType.va:
          parts.add('\$va:${rule.value}\$');
        case SmartPlaylistRuleType.circle:
          parts.add('\$circle:${rule.value}\$');
        case SmartPlaylistRuleType.age:
          parts.add('\$age:${rule.value}\$');
        case SmartPlaylistRuleType.rating:
        case SmartPlaylistRuleType.subtitle:
          // These are handled as client-side filters
          break;
      }
    }
    return parts.join(' ');
  }

  /// Check if a work passes client-side filters (rating, subtitle).
  bool _passesClientFilters(Work work) {
    for (final rule in _playlist.rules) {
      switch (rule.type) {
        case SmartPlaylistRuleType.rating:
          final minRating = int.tryParse(rule.value) ?? 0;
          final workRating = work.rateAverage ?? 0;
          if (workRating < minRating) return false;
        case SmartPlaylistRuleType.subtitle:
          final wantsSubtitle = rule.value == 'true';
          if (wantsSubtitle && work.hasSubtitle != true) return false;
          if (!wantsSubtitle && work.hasSubtitle == true) return false;
        default:
          break;
      }
    }
    return true;
  }

  /// Load the first page of results.
  Future<void> load({bool refresh = false}) async {
    if (state.isLoading && !refresh) return;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final keyword = _buildKeyword();
      const pageSize = 40;

      final result = await _api.searchWorks(
        keyword: keyword.isNotEmpty ? keyword : ' ', // space = default search
        page: 1,
        pageSize: pageSize * 2, // Fetch more for client-side filtering
        order: _playlist.sortField.value,
        sort: _playlist.sortDirection,
      );

      // Parse works
      final List<dynamic> rawWorks = result['works'] as List? ?? [];
      List<Work> allWorks = rawWorks
          .map((json) => Work.fromJson(json as Map<String, dynamic>))
          .toList();

      // Apply client-side filters
      final filtered = allWorks.where(_passesClientFilters).toList();

      // Get pagination info
      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalRaw = pagination?['totalCount'] ?? filtered.length;
      // Rough estimate: we fetched 2x pageSize, so cap total
      final estimatedTotal =
          (totalRaw is int) ? totalRaw : filtered.length;

      state = state.copyWith(
        works: filtered,
        isLoading: false,
        currentPage: 1,
        hasMore: filtered.length >= pageSize,
        totalCount: estimatedTotal,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// Load the next page.
  Future<void> loadNextPage() async {
    if (state.isLoading || !state.hasMore) return;
    final nextPage = state.currentPage + 1;

    state = state.copyWith(isLoading: true, error: null);

    try {
      final keyword = _buildKeyword();
      const pageSize = 40;

      final result = await _api.searchWorks(
        keyword: keyword.isNotEmpty ? keyword : ' ',
        page: nextPage,
        pageSize: pageSize * 2,
        order: _playlist.sortField.value,
        sort: _playlist.sortDirection,
      );

      final List<dynamic> rawWorks = result['works'] as List? ?? [];
      List<Work> newWorks = rawWorks
          .map((json) => Work.fromJson(json as Map<String, dynamic>))
          .toList();

      // Apply client-side filters
      final filtered = newWorks.where(_passesClientFilters).toList();

      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalRaw = pagination?['totalCount'] ?? 0;

      state = state.copyWith(
        works: [...state.works, ...filtered],
        isLoading: false,
        currentPage: nextPage,
        hasMore: filtered.length >= pageSize,
        totalCount: (totalRaw is int) ? totalRaw : state.totalCount,
      );
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  void refresh() => load(refresh: true);
}

/// Family provider that creates an evaluator for each smart playlist.
final smartPlaylistEvaluatorProvider = StateNotifierProvider.family<
    SmartPlaylistEvaluatorNotifier,
    SmartPlaylistEvalState,
    SmartPlaylist>((ref, playlist) {
  final api = ref.watch(kikoeruApiServiceProvider);
  return SmartPlaylistEvaluatorNotifier(api, playlist);
});
