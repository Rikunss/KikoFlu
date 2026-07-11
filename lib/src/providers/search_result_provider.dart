import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart';
import '../providers/works_provider.dart';
import '../models/sort_options.dart';
import 'settings_provider.dart';
import 'subtitle_library_provider.dart';

enum SearchLayoutType {
  list,
  smallGrid,
  bigGrid,
}

extension SearchLayoutTypeExtension on SearchLayoutType {
  LayoutType toWorksLayoutType() {
    switch (this) {
      case SearchLayoutType.list:
        return LayoutType.list;
      case SearchLayoutType.smallGrid:
        return LayoutType.smallGrid;
      case SearchLayoutType.bigGrid:
        return LayoutType.bigGrid;
    }
  }
}

class SearchResultState extends Equatable {
  final List<Work> works;
  final List<Work> rawWorks;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final SearchLayoutType layoutType;
  final SortOrder sortOption;
  final SortDirection sortDirection;
  final int subtitleFilter;
  final int basePageSize;
  final String keyword;
  final Map<String, dynamic>? searchParams;

  int get pageSize => subtitleFilter == 1 ? basePageSize * 2 : basePageSize;

  const SearchResultState({
    this.works = const [],
    this.rawWorks = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.layoutType = SearchLayoutType.bigGrid,
    this.sortOption = SortOrder.release,
    this.sortDirection = SortDirection.desc,
    this.subtitleFilter = 0,
    this.basePageSize = 40,
    this.keyword = '',
    this.searchParams,
  });

  SearchResultState copyWith({
    List<Work>? works,
    List<Work>? rawWorks,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    SearchLayoutType? layoutType,
    SortOrder? sortOption,
    SortDirection? sortDirection,
    int? subtitleFilter,
    int? basePageSize,
    String? keyword,
    Map<String, dynamic>? searchParams,
  }) {
    return SearchResultState(
      works: works ?? this.works,
      rawWorks: rawWorks ?? this.rawWorks,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      layoutType: layoutType ?? this.layoutType,
      sortOption: sortOption ?? this.sortOption,
      sortDirection: sortDirection ?? this.sortDirection,
      subtitleFilter: subtitleFilter ?? this.subtitleFilter,
      basePageSize: basePageSize ?? this.basePageSize,
      keyword: keyword ?? this.keyword,
      searchParams: searchParams ?? this.searchParams,
    );
  }

  @override
  List<Object?> get props => [
        works,
        rawWorks,
        isLoading,
        error,
        currentPage,
        totalCount,
        hasMore,
        layoutType,
        sortOption,
        sortDirection,
        subtitleFilter,
        basePageSize,
        keyword,
        searchParams,
      ];
}

class SearchResultNotifier extends StateNotifier<SearchResultState> {
  final KikoeruApiService _apiService;
  final Ref _ref;

  SearchResultNotifier(this._apiService, this._ref, {int initialPageSize = 20})
      : super(SearchResultState(basePageSize: initialPageSize));

  Future<void> initializeSearch({
    required String keyword,
    Map<String, dynamic>? searchParams,
  }) async {
    state = state.copyWith(
      keyword: keyword,
      searchParams: searchParams,
      currentPage: 1,
      works: [],
    );
    await loadResults();
  }

  void updatePageSize(int newSize) {
    if (state.basePageSize == newSize) return;
    state = state.copyWith(basePageSize: newSize);
    if (state.keyword.isNotEmpty || state.searchParams != null) {
      refresh();
    }
  }

  Future<void> loadResults({int? targetPage}) async {
    if (state.isLoading) return;

    final page = targetPage ?? state.currentPage;

    state = state.copyWith(
      isLoading: true,
      error: null,
    );

    try {
      Map<String, dynamic> result;

      const serverSubtitleParam = 0;

      if (state.searchParams?.containsKey('vaId') == true) {
        result = await _apiService.getWorksByVa(
          vaId: state.searchParams!['vaId'],
          page: page,
          pageSize: state.pageSize,
          order: state.sortOption.value,
          sort: state.sortDirection.value,
          subtitle: serverSubtitleParam,
        );
      } else if (state.searchParams?.containsKey('tagId') == true) {
        result = await _apiService.getWorksByTag(
          tagId: state.searchParams!['tagId'],
          page: page,
          pageSize: state.pageSize,
          order: state.sortOption.value,
          sort: state.sortDirection.value,
          subtitle: serverSubtitleParam,
        );
      } else {
        result = await _apiService.searchWorks(
          keyword: state.keyword,
          page: page,
          pageSize: state.pageSize,
          order: state.sortOption.value,
          sort: state.sortDirection.value,
          subtitle: serverSubtitleParam,
        );
      }

      final works =
          (result['works'] as List).map((json) => Work.fromJson(json)).toList();

      final blockedItems = _ref.read(blockedItemsProvider);
      final filteredWorks = _filterWorks(works, blockedItems);

      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalCount = pagination?['totalCount'] ?? works.length;

      final totalPages =
          totalCount > 0 ? (totalCount / state.pageSize).ceil() : 1;
      final hasMorePages = page < totalPages;

      state = state.copyWith(
        works: filteredWorks,
        rawWorks: works,
        currentPage: page,
        totalCount: totalCount,
        hasMore: hasMorePages,
        isLoading: false,
      );
    } catch (e) {
      state = state.copyWith(
        isLoading: false,
        error: e.toString(),
      );
    }
  }

  void reapplyFilters() {
    final blockedItems = _ref.read(blockedItemsProvider);
    final filteredWorks = _filterWorks(state.rawWorks, blockedItems);
    state = state.copyWith(works: filteredWorks);
  }

  List<Work> _filterWorks(List<Work> works, BlockedItemsState blockedItems) {
    final localSubtitleIds = _ref.read(subtitleLibraryProvider);
    final subtitleFilter = state.subtitleFilter;

    return works.where((work) {
      if (subtitleFilter == 1) {
        final hasServerSubtitle = work.hasSubtitle == true;
        final hasLocalSubtitle = localSubtitleIds.contains(work.id);
        if (!hasServerSubtitle && !hasLocalSubtitle) {
          return false;
        }
      }

      if (work.tags != null) {
        for (final tag in work.tags!) {
          if (blockedItems.tags.contains(tag.name)) return false;
        }
      }
      if (work.vas != null) {
        for (final va in work.vas!) {
          if (blockedItems.cvs.contains(va.name)) return false;
        }
      }
      if (work.name != null && blockedItems.circles.contains(work.name)) {
        return false;
      }
      return true;
    }).toList();
  }

  Future<void> goToPage(int page) async {
    await loadResults(targetPage: page);
  }

  Future<void> refresh() async {
    await loadResults(targetPage: state.currentPage);
  }

  void toggleLayoutType() {
    final nextLayout = switch (state.layoutType) {
      SearchLayoutType.bigGrid => SearchLayoutType.smallGrid,
      SearchLayoutType.smallGrid => SearchLayoutType.list,
      SearchLayoutType.list => SearchLayoutType.bigGrid,
    };
    state = state.copyWith(layoutType: nextLayout);
  }

  bool get isSubtitleFilterActive => state.subtitleFilter == 1;

  void toggleSubtitleFilter() {
    final currentPage = state.currentPage;
    final oldFilter = state.subtitleFilter;
    final newFilter = oldFilter == 0 ? 1 : 0;

    int newPage;
    if (newFilter == 1) {
      newPage = ((currentPage + 1) / 2).ceil();
    } else {
      newPage = (currentPage * 2) - 1;
    }
    newPage = newPage.clamp(1, 9999);

    state = state.copyWith(
      subtitleFilter: newFilter,
      currentPage: newPage,
      works: [],
    );
    loadResults(targetPage: newPage);
  }

  void updateSort(SortOrder option, SortDirection direction) {
    state = state.copyWith(
      sortOption: option,
      sortDirection: direction,
      currentPage: 1,
      works: [],
    );
    loadResults();
  }
}

final searchResultProvider =
    StateNotifierProvider<SearchResultNotifier, SearchResultState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  final pageSize = ref.read(pageSizeProvider);
  final notifier =
      SearchResultNotifier(apiService, ref, initialPageSize: pageSize);

  ref.listen(pageSizeProvider, (previous, next) {
    if (previous != next) {
      notifier.updatePageSize(next);
    }
  });

  ref.listen(blockedItemsProvider, (previous, next) {
    if (previous != next) {
      notifier.reapplyFilters();
    }
  });

  ref.listen(subtitleLibraryProvider, (previous, next) {
    if (previous != next && notifier.isSubtitleFilterActive) {
      notifier.reapplyFilters();
    }
  });

  return notifier;
});