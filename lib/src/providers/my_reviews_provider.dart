import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/work.dart';
import '../models/sort_options.dart';
import '../services/kikoeru_api_service.dart';
import '../services/log_service.dart';
import 'auth_provider.dart';
import 'settings_provider.dart';

/// 用户 Review/收藏状态的过滤枚举
enum MyReviewFilter {
  all(null, '全部'),
  marked('marked', '想听'),
  listening('listening', '在听'),
  listened('listened', '听过'),
  replay('replay', '重听'),
  postponed('postponed', '搁置');

  final String? value;
  final String label;
  const MyReviewFilter(this.value, this.label);
}

/// 布局类型枚举
enum MyReviewLayoutType {
  bigGrid,
  smallGrid,
  list,
}

class MyReviewsState extends Equatable {
  final List<Work> works;
  final bool isLoading;
  final String? error;
  final int currentPage;
  final int totalCount;
  final bool hasMore;
  final MyReviewFilter filter;
  final int pageSize;
  final MyReviewLayoutType layoutType;
  final SortOrder sortType;
  final SortDirection sortOrder;

  const MyReviewsState({
    this.works = const [],
    this.isLoading = false,
    this.error,
    this.currentPage = 1,
    this.totalCount = 0,
    this.hasMore = true,
    this.filter = MyReviewFilter.all,
    this.pageSize = 20,
    this.layoutType = MyReviewLayoutType.bigGrid,
    this.sortType = SortOrder.updatedAt,
    this.sortOrder = SortDirection.desc,
  });

  MyReviewsState copyWith({
    List<Work>? works,
    bool? isLoading,
    String? error,
    int? currentPage,
    int? totalCount,
    bool? hasMore,
    MyReviewFilter? filter,
    int? pageSize,
    MyReviewLayoutType? layoutType,
    SortOrder? sortType,
    SortDirection? sortOrder,
  }) {
    return MyReviewsState(
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      currentPage: currentPage ?? this.currentPage,
      totalCount: totalCount ?? this.totalCount,
      hasMore: hasMore ?? this.hasMore,
      filter: filter ?? this.filter,
      pageSize: pageSize ?? this.pageSize,
      layoutType: layoutType ?? this.layoutType,
      sortType: sortType ?? this.sortType,
      sortOrder: sortOrder ?? this.sortOrder,
    );
  }

  @override
  List<Object?> get props => [
        works,
        isLoading,
        error,
        currentPage,
        totalCount,
        hasMore,
        filter,
        pageSize,
        layoutType,
        sortType,
        sortOrder,
      ];
}

class MyReviewsNotifier extends StateNotifier<MyReviewsState> {
  final KikoeruApiService _apiService;
  MyReviewsNotifier(this._apiService, {int initialPageSize = 20})
      : super(MyReviewsState(pageSize: initialPageSize));

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
      final result = await _apiService.getMyReviews(
        page: page,
        pageSize: state.pageSize,
        filter: state.filter.value,
        order: state.sortType.value,
        sort: state.sortOrder.value,
      );

      final List<dynamic> rawList =
          (result['works'] as List?) ??
              (result['reviews'] as List?) ??
              (result['data'] as List?) ??
              [];

      final works = rawList.map((item) {
        if (item is Map<String, dynamic>) {
          if (item.containsKey('work')) {
            final workJson = item['work'] as Map<String, dynamic>;
            return Work.fromJson(workJson);
          } else {
            return Work.fromJson(item);
          }
        }
        throw Exception('Unexpected review item format');
      }).toList();

      final pagination = result['pagination'] as Map<String, dynamic>?;
      final totalCount = pagination?['totalCount'] ?? 0;

      final totalPages =
          totalCount > 0 ? (totalCount / state.pageSize).ceil() : 1;
      final hasMore = page < totalPages;

      state = state.copyWith(
        works: works,
        totalCount: totalCount,
        hasMore: hasMore,
        isLoading: false,
        currentPage: page,
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

  void changeFilter(MyReviewFilter filter) {
    state = state.copyWith(filter: filter, currentPage: 1, totalCount: 0);
    load(targetPage: 1);
  }

  void changeSort(SortOrder sortType, SortDirection sortOrder) {
    if (state.sortType == sortType && state.sortOrder == sortOrder) return;
    state = state.copyWith(
      sortType: sortType,
      sortOrder: sortOrder,
      currentPage: 1,
      totalCount: 0,
    );
    load(targetPage: 1);
  }

  void toggleLayoutType() {
    final nextLayout = switch (state.layoutType) {
      MyReviewLayoutType.bigGrid => MyReviewLayoutType.smallGrid,
      MyReviewLayoutType.smallGrid => MyReviewLayoutType.list,
      MyReviewLayoutType.list => MyReviewLayoutType.bigGrid,
    };
    state = state.copyWith(layoutType: nextLayout);
  }

  void refresh() => load();
}

final myReviewsProvider =
    StateNotifierProvider<MyReviewsNotifier, MyReviewsState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  final pageSize = ref.read(pageSizeProvider);
  final notifier = MyReviewsNotifier(apiService, initialPageSize: pageSize);

  ref.listen(pageSizeProvider, (previous, next) {
    if (previous != next) {
      notifier.updatePageSize(next);
    }
  });

  ref.listen(currentUserProvider, (previous, next) {
    final prevUser = previous;
    final nextUser = next;
    if (prevUser?.name != nextUser?.name || prevUser?.host != nextUser?.host) {
      LogService.instance.debug('[MyReviewsProvider] User changed, refreshing my reviews', tag: 'UI');
      notifier.refresh();
    }
  });

  return notifier;
});