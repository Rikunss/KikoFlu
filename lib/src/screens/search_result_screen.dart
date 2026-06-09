import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../../src/services/log_service.dart';
import '../models/sort_options.dart';
import '../providers/search_result_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/works_grid_view.dart';
import '../widgets/sort_dialog.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/global_audio_player_wrapper.dart';
import '../widgets/download_fab.dart';
import '../widgets/overscroll_next_page_detector.dart';

class SearchResultScreen extends StatelessWidget {
  final String keyword;
  final String? searchTypeLabel;
  final Map<String, dynamic>? searchParams;

  const SearchResultScreen({
    super.key,
    required this.keyword,
    this.searchTypeLabel,
    this.searchParams,
  });

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      overrides: [
        searchResultProvider.overrideWith((ref) {
          final apiService = ref.watch(kikoeruApiServiceProvider);
          final pageSize = ref.read(pageSizeProvider);
          return SearchResultNotifier(apiService, ref, initialPageSize: pageSize);
        }),
      ],
      child: _SearchResultContent(
        keyword: keyword,
        searchTypeLabel: searchTypeLabel,
        searchParams: searchParams,
      ),
    );
  }
}

class _SearchResultContent extends ConsumerStatefulWidget {
  final String keyword;
  final String? searchTypeLabel;
  final Map<String, dynamic>? searchParams;

  const _SearchResultContent({
    required this.keyword,
    this.searchTypeLabel,
    this.searchParams,
  });

  @override
  ConsumerState<_SearchResultContent> createState() =>
      _SearchResultContentState();
}

class _SearchResultContentState extends ConsumerState<_SearchResultContent> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    LogService.instance.debug(
        '[SearchResult] Screen initialized with keyword: ${widget.keyword}, type: ${widget.searchTypeLabel}');
    // Load initial data
    WidgetsBinding.instance.addPostFrameCallback((_) {
      LogService.instance.debug(
          '[SearchResult] Starting search with params: ${widget.searchParams}');
      ref.read(searchResultProvider.notifier).initializeSearch(
            keyword: widget.keyword,
            searchParams: widget.searchParams,
          );
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  void _showSortDialog(BuildContext context) {
    final state = ref.read(searchResultProvider);
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS, // iOS 上防止点击外部区域意外关闭
      builder: (context) => CommonSortDialog(
        currentOption: state.sortOption,
        currentDirection: state.sortDirection,
        availableOptions: SortOrder.values
            .where((option) =>
                option != SortOrder.nsfw && option != SortOrder.updatedAt)
            .toList(),
        onSort: (option, direction) {
          ref.read(searchResultProvider.notifier).updateSort(option, direction);
        },
        autoClose: true,
      ),
    );
  }

  Icon _getLayoutIcon(SearchLayoutType layoutType) {
    switch (layoutType) {
      case SearchLayoutType.bigGrid:
        return const Icon(Icons.grid_3x3);
      case SearchLayoutType.smallGrid:
        return const Icon(Icons.view_list);
      case SearchLayoutType.list:
        return const Icon(Icons.view_agenda);
    }
  }

  String _getLayoutTooltip(SearchLayoutType layoutType) {
    switch (layoutType) {
      case SearchLayoutType.bigGrid:
        return S.of(context).switchToSmallGrid;
      case SearchLayoutType.smallGrid:
        return S.of(context).switchToList;
      case SearchLayoutType.list:
        return S.of(context).switchToLargeGrid;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Listen to pageSize changes to update search page size
    ref.listen(pageSizeProvider, (previous, next) {
      if (previous != next) {
        ref.read(searchResultProvider.notifier).updatePageSize(next);
      }
    });

    final searchState = ref.watch(searchResultProvider);

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 0.0;

    return GlobalAudioPlayerWrapper(
      child: Scaffold(
        floatingActionButton: const DownloadFab(),
        appBar: AppBar(
          scrolledUnderElevation: 0,
          elevation: 0,
          titleSpacing: 0,
          actions: [
            if (horizontalPadding > 0) SizedBox(width: horizontalPadding - 8),
            IconButton(
              icon: _getLayoutIcon(searchState.layoutType),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () =>
                  ref.read(searchResultProvider.notifier).toggleLayoutType(),
              tooltip: _getLayoutTooltip(searchState.layoutType),
            ),
            IconButton(
              icon: Icon(
                searchState.subtitleFilter == 1
                    ? Icons.closed_caption
                    : Icons.closed_caption_disabled,
                color: searchState.subtitleFilter == 1
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              iconSize: 22,
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () => ref
                  .read(searchResultProvider.notifier)
                  .toggleSubtitleFilter(),
              tooltip: searchState.subtitleFilter == 1 ? S.of(context).showAllWorks : S.of(context).showOnlySubtitled,
            ),
            Padding(
              padding: EdgeInsets.only(
                  right: horizontalPadding > 0 ? horizontalPadding - 8 : 0),
              child: IconButton(
                icon: const Icon(Icons.sort),
                iconSize: 22,
                padding: const EdgeInsets.all(8),
                constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
                onPressed: () => _showSortDialog(context),
                tooltip: S.of(context).sort,
              ),
            ),
          ],
        ),
        body: Column(
          children: [
            // 搜索信息行
            Container(
              width: double.infinity,
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 24.0 : 8.0,
                vertical: 8,
              ),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                border: Border(
                  bottom: BorderSide(
                    color: Theme.of(context).dividerColor,
                    width: 1,
                  ),
                ),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: _buildSearchInfo(context, searchState),
              ),
            ),
            // 搜索结果内容
            Expanded(
              child: _buildBody(searchState),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchInfo(BuildContext context, SearchResultState searchState) {
    // 检查是否有详细的搜索条件
    final conditions = widget.searchParams?['conditions'] as List?;
    final minRate = widget.searchParams?['minRate'] as num?;
    final ageRating = widget.searchParams?['ageRating'] as String?;
    final salesRange = widget.searchParams?['salesRange'] as String?;

    // 如果有详细条件，显示为芯片
    if (conditions != null && conditions.isNotEmpty) {
      return Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          // 搜索条件芯片
          ...conditions.map((condition) {
            final type = condition['type'] as String;
            final value = condition['value'] as String;
            final isExclude = condition['isExclude'] as bool? ?? false;
            // RJ号需要添加RJ前缀显示
            final isRjNumber = RegExp(r'^\d+$').hasMatch(value);
            final displayValue = isRjNumber ? 'RJ$value' : value;

            return Chip(
              avatar: Icon(
                isExclude
                    ? Icons.remove_circle_outline
                    : _getConditionIcon(type),
                size: 16,
              ),
              label: Text(
                '$type: $displayValue',
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: isExclude
                  ? Theme.of(context).colorScheme.errorContainer
                  : Theme.of(context).colorScheme.secondaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            );
          }),

          // 高级筛选条件芯片
          if (minRate != null && minRate > 0)
            Chip(
              avatar: const Icon(Icons.star, size: 16),
              label: Text(
                '${S.of(context).ratingLabel} ≥ ${minRate.toStringAsFixed(2)}',
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
          if (ageRating != null)
            Chip(
              avatar: const Icon(Icons.shield, size: 16),
              label: Text(
                ageRating,
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),
          if (salesRange != null)
            Chip(
              avatar: const Icon(Icons.trending_up, size: 16),
              label: Text(
                salesRange,
                style: const TextStyle(fontSize: 13),
              ),
              backgroundColor: Theme.of(context).colorScheme.tertiaryContainer,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              side: BorderSide.none,
            ),

          // 结果统计
          if (searchState.totalCount > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                S.of(context).totalNWorks(searchState.totalCount),
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
            ),
        ],
      );
    }

    // 原有的简单显示方式（兼容旧逻辑）
    String searchInfo = widget.keyword;
    if (widget.searchTypeLabel != null) {
      searchInfo = '${widget.searchTypeLabel}: $searchInfo';
    }

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(6),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.search,
                size: 18,
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
              const SizedBox(width: 6),
              Text(
                searchInfo,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onSecondaryContainer,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
        if (searchState.totalCount > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.numbers,
                  size: 18,
                  color: Theme.of(context).colorScheme.onPrimaryContainer,
                ),
                const SizedBox(width: 4),
                Text(
                  S.of(context).totalNWorks(searchState.totalCount),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBody(SearchResultState searchState) {
    if (searchState.error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .errorContainer
                      .withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                S.of(context).loadFailed,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                searchState.error!,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: () =>
                    ref.read(searchResultProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(S.of(context).retry),
              ),
            ],
          ),
        ),
      );
    }

    if (searchState.works.isEmpty && searchState.isLoading) {
      return _buildSkeletonGrid();
    }

    if (searchState.works.isEmpty && !searchState.isLoading) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .primaryContainer
                      .withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.search_off_rounded,
                  size: 40,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                S.of(context).noResults,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context).noData,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return OverscrollNextPageDetector(
      hasNextPage: searchState.hasMore,
      isLoading: searchState.isLoading,
      onNextPage: () async {
        await ref
            .read(searchResultProvider.notifier)
            .goToPage(searchState.currentPage + 1);
        // 等待一帧后滚动到顶部，确保内容已加载
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToTop();
        });
      },
      child: WorksGridView(
        works: searchState.works,
        layoutType: searchState.layoutType.toWorksLayoutType(),
        scrollController: _scrollController,
        isLoading: searchState.isLoading,
        paginationWidget: _buildPaginationBar(searchState),
      ),
    );
  }

  Widget _buildPaginationBar(SearchResultState searchState) {
    return Column(
      children: [
        PaginationBar(
          currentPage: searchState.currentPage,
          pageSize: searchState.pageSize,
          totalCount: searchState.totalCount,
          hasMore: searchState.hasMore,
          isLoading: searchState.isLoading,
          onPreviousPage: () {
            ref
                .read(searchResultProvider.notifier)
                .goToPage(searchState.currentPage - 1);
            _scrollToTop();
          },
          onNextPage: () {
            ref
                .read(searchResultProvider.notifier)
                .goToPage(searchState.currentPage + 1);
            _scrollToTop();
          },
          onGoToPage: (page) {
            ref.read(searchResultProvider.notifier).goToPage(page);
          },
          onScrollToTop: _scrollToTop,
          endMessage: S.of(context).reachedEnd,
        ),
        if (searchState.rawWorks.length > searchState.works.length) ...[
          const SizedBox(height: 8),
          Text(
            '${searchState.rawWorks.length - searchState.works.length} filtered',
            style: TextStyle(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontSize: 12,
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildSkeletonGrid() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverGrid(
            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 210,
              childAspectRatio: 0.72,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            delegate: SliverChildBuilderDelegate(
              (context, index) => _SkeletonWorkCard(),
              childCount: 6,
            ),
          ),
        ],
      ),
    );
  }

  IconData _getConditionIcon(String type) {
    return Icons.search;
  }
}

/// A container that rebuilds every animation frame to produce shimmer effect.
class _SkeletonShimmerContainer extends AnimatedWidget {
  final Color baseColor;

  const _SkeletonShimmerContainer({
    required super.listenable,
    required this.baseColor,
  }) : super();

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        color: baseColor.withValues(alpha: _animation.value),
      ),
    );
  }
}

/// A shimmer line that only rebuilds the animated Container, not the parent.
class _SkeletonShimmerLine extends AnimatedWidget {
  final Color baseColor;
  final double width;
  final double height;
  final double alphaMultiplier;

  const _SkeletonShimmerLine({
    required super.listenable,
    required this.baseColor,
    required this.width,
    required this.height,
    required this.alphaMultiplier,
  }) : super();

  Animation<double> get _animation => listenable as Animation<double>;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: baseColor.withValues(alpha: _animation.value * alphaMultiplier),
        borderRadius: BorderRadius.circular(4),
      ),
    );
  }
}

class _SkeletonWorkCard extends StatefulWidget {
  @override
  State<_SkeletonWorkCard> createState() => _SkeletonWorkCardState();
}

class _SkeletonWorkCardState extends State<_SkeletonWorkCard>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _animation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final baseColor = colorScheme.surfaceContainerHighest;
    final cardColor = colorScheme.surfaceContainerLow;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      color: cardColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Cover placeholder — AnimatedWidget, only this rebuilds per frame
          _SkeletonShimmerContainer(
            listenable: _animation,
            baseColor: baseColor,
          ),
          // Info placeholder
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SkeletonShimmerLine(
                  listenable: _animation,
                  baseColor: baseColor,
                  width: double.infinity,
                  height: 12,
                  alphaMultiplier: 1.0,
                ),
                const SizedBox(height: 8),
                _SkeletonShimmerLine(
                  listenable: _animation,
                  baseColor: baseColor,
                  width: 100,
                  height: 10,
                  alphaMultiplier: 0.7,
                ),
                const SizedBox(height: 6),
                _SkeletonShimmerLine(
                  listenable: _animation,
                  baseColor: baseColor,
                  width: 80,
                  height: 10,
                  alphaMultiplier: 0.5,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
