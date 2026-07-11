import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';
import '../models/sort_options.dart';
import 'subtitle_library_provider.dart';

enum DisplayMode {
  all('all', '全部作品'),
  popular('popular', '热门推荐'),
  recommended('recommended', '推荐');

  const DisplayMode(this.value, this.label);
  final String value;
  final String label;
}

enum LayoutType {
  list,
  smallGrid,
  bigGrid
}

class WorksModeSnapshot extends Equatable {      static const _noValue = Object();

  final List<Work> works;
  final List<Work> rawWorks;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final bool isLastPage;

  const WorksModeSnapshot({
    this.works = const [],
    this.rawWorks = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.isLastPage = false,
  });

  WorksModeSnapshot copyWith({
    List<Work>? works,
    List<Work>? rawWorks,
    bool? isLoading,
    Object? error = _noValue,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    bool? isLastPage,
  }) {
    return WorksModeSnapshot(
      works: works ?? this.works,
      rawWorks: rawWorks ?? this.rawWorks,
      isLoading: isLoading ?? this.isLoading,
      error: error == _noValue ? this.error : error as String?,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      isLastPage: isLastPage ?? this.isLastPage,
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
        isLastPage,
      ];
}

class WorksState extends Equatable {
  final LayoutType layoutType;
  final SortOrder sortOption;
  final SortDirection sortDirection;
  final DisplayMode displayMode;
  final int subtitleFilter;
  final int basePageSize;
  final Map<DisplayMode, WorksModeSnapshot> modeStates;

  int get pageSize => subtitleFilter == 1 ? basePageSize * 2 : basePageSize;

  WorksState({
    this.layoutType = LayoutType.bigGrid,
    this.sortOption = SortOrder.release,
    this.sortDirection = SortDirection.desc,
    this.displayMode = DisplayMode.all,
    this.subtitleFilter = 0,
    this.basePageSize = 40,
    Map<DisplayMode, WorksModeSnapshot>? modeStates,
  }) : modeStates = modeStates ?? _createInitialModeStates();

  WorksState copyWith({
    LayoutType? layoutType,
    SortOrder? sortOption,
    SortDirection? sortDirection,
    DisplayMode? displayMode,
    int? subtitleFilter,
    int? basePageSize,
    Map<DisplayMode, WorksModeSnapshot>? modeStates,
  }) {
    return WorksState(
      layoutType: layoutType ?? this.layoutType,
      sortOption: sortOption ?? this.sortOption,
      sortDirection: sortDirection ?? this.sortDirection,
      displayMode: displayMode ?? this.displayMode,
      subtitleFilter: subtitleFilter ?? this.subtitleFilter,
      basePageSize: basePageSize ?? this.basePageSize,
      modeStates: modeStates ?? this.modeStates,
    );
  }

  WorksModeSnapshot get _currentModeState =>
      modeStates[displayMode] ?? const WorksModeSnapshot();

  List<Work> get works => _currentModeState.works;
  List<Work> get rawWorks => _currentModeState.rawWorks;
  bool get isLoading => _currentModeState.isLoading;
  String? get error => _currentModeState.error;
  int get currentPage => _currentModeState.currentPage;
  int get totalCount => _currentModeState.totalCount;
  bool get hasMore => _currentModeState.hasMore;
  bool get isLastPage => _currentModeState.isLastPage;

  static Map<DisplayMode, WorksModeSnapshot> _createInitialModeStates() {
    return {
      for (final mode in DisplayMode.values) mode: const WorksModeSnapshot(),
    };
  }

  @override
  List<Object?> get props => [
        layoutType,
        sortOption,
        sortDirection,
        displayMode,
        subtitleFilter,
        basePageSize,
        modeStates,
      ];
}

class WorksNotifier extends StateNotifier<WorksState> {
  final KikoeruApiService _apiService;
  final Ref _ref;

  WorksNotifier(
    this._apiService,
    this._ref, {
    int initialPageSize = 40,
    SortOrder initialSortOption = SortOrder.release,
    SortDirection initialSortDirection = SortDirection.desc,
  }) : super(WorksState(
          basePageSize: initialPageSize,
          sortOption: initialSortOption,
          sortDirection: initialSortDirection,
        ));

  WorksModeSnapshot _getModeState(DisplayMode mode) {
    return state.modeStates[mode] ?? const WorksModeSnapshot();
  }

  void _updateModeState(
    DisplayMode mode,
    WorksModeSnapshot Function(WorksModeSnapshot current) updater,
  ) {
    final updatedStates =
        Map<DisplayMode, WorksModeSnapshot>.from(state.modeStates);
    final currentSnapshot = _getModeState(mode);
    updatedStates[mode] = updater(currentSnapshot);
    state = state.copyWith(modeStates: updatedStates);
  }

  void _updateActiveModeState(
    WorksModeSnapshot Function(WorksModeSnapshot current) updater,
  ) {
    _updateModeState(state.displayMode, updater);
  }

  void updatePageSize(int newSize) {
    if (state.basePageSize == newSize) return;
    state = state.copyWith(basePageSize: newSize);
    loadWorks(targetPage: 1);
  }

  Future<void> loadWorks({bool refresh = false, int? targetPage}) async {
    final mode = state.displayMode;
    final modeState = _getModeState(mode);

    if (modeState.isLoading) {
      LogService.instance.debug('[WorksProvider] Already loading, skipping', tag: 'UI');
      return;
    }

    final isAllMode = mode == DisplayMode.all;
    final previousPage = modeState.currentPage;

    final page = targetPage ??
        (isAllMode ? previousPage : (refresh ? 1 : (previousPage + 1)));

    LogService.instance.debug(
        '[WorksProvider] Loading works - mode: $mode, page: $page, refresh: $refresh, currentPage: $previousPage, targetPage: $targetPage', tag: 'UI');

    _updateModeState(
      mode,
      (snapshot) => snapshot.copyWith(isLoading: true, error: null),
    );

    try {
      Map<String, dynamic> response;

      final pageSize = state.pageSize;
      final sortOption = state.sortOption;
      final sortDirection = state.sortDirection;

      const serverSubtitleParam = 0;

      if (mode == DisplayMode.popular) {
        response = await _apiService.getPopularWorks(
          page: page,
          pageSize: pageSize,
          subtitle: serverSubtitleParam,
        );
      } else if (mode == DisplayMode.recommended) {
        final currentUser = _ref.read(authProvider).currentUser;
        final recommenderUuid = currentUser?.recommenderUuid ??
            '766cc58d-7f1e-4958-9a93-913400f378dc';

        response = await _apiService.getRecommendedWorks(
          recommenderUuid: recommenderUuid,
          page: page,
          pageSize: pageSize,
          subtitle: serverSubtitleParam,
        );
      } else {
        response = await _apiService.getWorks(
          page: page,
          order: sortOption.value,
          sort: sortOption == SortOrder.nsfw ? 'asc' : sortDirection.value,
          subtitle: serverSubtitleParam,
          pageSize: pageSize,
        );
      }

      final worksData = response['works'] as List<dynamic>?;
      final pagination = response['pagination'] as Map<String, dynamic>?;

      if (worksData == null) {
        throw Exception('No works data in response');
      }

      final works = worksData
          .map((workJson) => Work.fromJson(workJson as Map<String, dynamic>))
          .toList();

      final shouldReplace = isAllMode || page == 1;
      final newRawWorks =
          shouldReplace ? works : [...modeState.rawWorks, ...works];

      final blockedItems = _ref.read(blockedItemsProvider);
      final filteredWorks = _filterWorks(newRawWorks, blockedItems);

      final totalCount = pagination?['totalCount'] as int? ?? 0;
      final currentPage = pagination?['currentPage'] as int? ?? page;

      bool hasMore;
      bool isLastPage = false;

      if (mode == DisplayMode.popular || mode == DisplayMode.recommended) {
        final currentTotal = filteredWorks.length;
        hasMore = works.length >= pageSize &&
            currentTotal < 100 &&
            currentTotal < totalCount;
        isLastPage = !hasMore && filteredWorks.isNotEmpty;
      } else {
        hasMore = (currentPage * pageSize) < totalCount;
        isLastPage = !hasMore && filteredWorks.isNotEmpty;
      }

      LogService.instance.debug(
          '[WorksProvider] Loaded ${filteredWorks.length} works (filtered from ${newRawWorks.length}), total: ${filteredWorks.length}, hasMore: $hasMore, currentPage: $currentPage', tag: 'UI');

      _updateModeState(
        mode,
        (snapshot) => snapshot.copyWith(
          works: filteredWorks,
          rawWorks: newRawWorks,
          isLoading: false,
          currentPage: currentPage,
          totalCount: totalCount,
          hasMore: hasMore,
          isLastPage: isLastPage,
          error: null,
        ),
      );
    } catch (e) {
      LogService.instance.error('Failed to load works: $e', tag: 'UI');

      _updateModeState(
        mode,
        (snapshot) => snapshot.copyWith(
          isLoading: false,
          error: '加载失败: ${e.toString()}',
        ),
      );
    }
  }

  Future<void> refresh({bool resetPage = false}) async {
    if (resetPage) {
      await loadWorks(targetPage: 1);
    } else {
      await loadWorks(targetPage: state.currentPage);
    }
  }

  Future<void> goToPage(int page) async {
    if (state.displayMode != DisplayMode.all) return;
    if (page < 1) return;

    final maxPage = (state.totalCount / state.pageSize).ceil();
    if (page > maxPage && maxPage > 0) return;

    await loadWorks(targetPage: page);
  }

  Future<void> nextPage() async {
    if (state.displayMode != DisplayMode.all) return;
    if (!state.hasMore || state.isLoading) return;
    await loadWorks(targetPage: state.currentPage + 1);
  }

  Future<void> previousPage() async {
    if (state.displayMode != DisplayMode.all) return;
    if (state.currentPage <= 1 || state.isLoading) return;
    await loadWorks(targetPage: state.currentPage - 1);
  }

  void setSortOption(SortOrder option) {
    if (state.sortOption != option) {
      state = state.copyWith(sortOption: option);
      refresh(resetPage: true);
    }
  }

  void setSortDirection(SortDirection direction) {
    if (state.sortDirection != direction) {
      state = state.copyWith(sortDirection: direction);
      refresh(resetPage: true);
    }
  }

  void toggleSortDirection() {
    final newDirection = state.sortDirection == SortDirection.asc
        ? SortDirection.desc
        : SortDirection.asc;
    setSortDirection(newDirection);
  }

  void setLayoutType(LayoutType layoutType) {
    state = state.copyWith(layoutType: layoutType);
  }

  void toggleLayoutType() {
    late LayoutType newLayoutType;
    switch (state.layoutType) {
      case LayoutType.bigGrid:
        newLayoutType = LayoutType.smallGrid;
        break;
      case LayoutType.smallGrid:
        newLayoutType = LayoutType.list;
        break;
      case LayoutType.list:
        newLayoutType = LayoutType.bigGrid;
        break;
    }
    setLayoutType(newLayoutType);
  }

  void clearError() {
    _updateActiveModeState((modeState) => modeState.copyWith(error: null));
  }

  void setDisplayMode(DisplayMode mode) {
    if (state.displayMode == mode) return;

    state = state.copyWith(displayMode: mode);

    final targetState = _getModeState(mode);
    final shouldLoadInitial =
        targetState.works.isEmpty && !targetState.isLoading;

    if (shouldLoadInitial) {
      refresh(resetPage: true);
    }
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

    state = state.copyWith(subtitleFilter: newFilter);
    loadWorks(targetPage: newPage);
  }

  void reapplyFilters() {
    final blockedItems = _ref.read(blockedItemsProvider);
    final updatedStates = state.modeStates.map((mode, snapshot) {
      final filteredWorks = _filterWorks(snapshot.rawWorks, blockedItems);
      return MapEntry(mode, snapshot.copyWith(works: filteredWorks));
    });
    state = state.copyWith(modeStates: updatedStates);
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
}

final worksProvider = StateNotifierProvider<WorksNotifier, WorksState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  final pageSize = ref.read(pageSizeProvider);
  final defaultSort = ref.read(defaultSortProvider);

  final notifier = WorksNotifier(
    apiService,
    ref,
    initialPageSize: pageSize,
    initialSortOption: defaultSort.order,
    initialSortDirection: defaultSort.direction,
  );

  ref.listen(pageSizeProvider, (previous, next) {
    if (previous != next) {
      notifier.updatePageSize(next);
    }
  });

  ref.listen(defaultSortProvider, (previous, next) {
    if (previous != next) {
      notifier.setSortOption(next.order);
      notifier.setSortDirection(next.direction);
    }
  });

  ref.listen(currentUserProvider, (previous, next) {
    final prevUser = previous;
    final nextUser = next;
    if (prevUser?.name != nextUser?.name || prevUser?.host != nextUser?.host) {
      LogService.instance.debug('[WorksProvider] User changed, refreshing works list', tag: 'UI');
      notifier.refresh();
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