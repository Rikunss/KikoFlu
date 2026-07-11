import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../services/log_service.dart';

import '../providers/works_provider.dart';
import '../providers/auth_provider.dart';
import '../models/user.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/sort_dialog.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/overscroll_next_page_detector.dart';
import '../utils/responsive_grid_helper.dart';
import '../utils/snackbar_util.dart';
import '../widgets/scrollable_appbar.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/download_fab.dart';
import '../models/work.dart';
import '../models/sort_options.dart';
import '../utils/scroll_optimization.dart';
import '../services/blurhash_service.dart';

class WorksScreen extends ConsumerStatefulWidget {
  const WorksScreen({super.key});

  @override
  ConsumerState<WorksScreen> createState() => _WorksScreenState();
}

class _WorksScreenState extends ConsumerState<WorksScreen>
    with AutomaticKeepAliveClientMixin {
  /// Per-mode scroll controllers — prevents conflict during AnimatedSwitcher transitions.
  final Map<DisplayMode, ScrollController> _scrollControllers = {};

  ScrollController _controllerFor(DisplayMode mode) {
    return _scrollControllers.putIfAbsent(mode, () => ScrollController());
  }

  ScrollController get _currentScrollController =>
      _controllerFor(ref.read(worksProvider).displayMode);

  final ScrollThrottler _scrollThrottler = ScrollThrottler(positionThreshold: 10);
  bool _isLoadingMore = false;
  bool _batchTriggered = false;
  Timer? _blurHashDebounce;
  int _slideDirection = 0;
  final Map<DisplayMode, double> _scrollPositions = {
    for (final mode in DisplayMode.values) mode: 0.0,
  };

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    for (final mode in DisplayMode.values) {
      final controller = _controllerFor(mode);
      controller.addListener(() => _onScrollForMode(mode));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final worksState = ref.read(worksProvider);
      if (worksState.works.isEmpty) {
        ref.read(worksProvider.notifier).loadWorks(refresh: true).then((_) {
          _triggerBatchIfNeeded();
        });
      }
    });
  }

  @override
  void dispose() {
    _blurHashDebounce?.cancel();
    _scrollThrottler.dispose();
    for (final controller in _scrollControllers.values) {
      controller.dispose();
    }
    _scrollControllers.clear();
    super.dispose();
  }

  void _onScrollForMode(DisplayMode mode) {
    final controller = _controllerFor(mode);
    _scrollThrottler.throttle(() {
      if (!controller.hasClients) return;

      final currentPosition = controller.position.pixels;
      final maxScrollExtent = controller.position.maxScrollExtent;

      final worksState = ref.read(worksProvider);
      _scrollPositions[worksState.displayMode] = currentPosition;
      final isNearBottom = currentPosition >= maxScrollExtent - 50;

      if (worksState.displayMode != DisplayMode.all) {
        if (isNearBottom &&
            !worksState.isLoading &&
            worksState.hasMore &&
            !_isLoadingMore) {
          LogService.instance.debug(
              '[WorksScreen] Triggering load more - currentPage: ${worksState.currentPage}', tag: 'UI');
          _isLoadingMore = true;

          ref.read(worksProvider.notifier).loadWorks().then((_) {
            if (mounted) {
              setState(() {
                _isLoadingMore = false;
              });
              LogService.instance.debug('[WorksScreen] Load more completed', tag: 'UI');
            }
          }).catchError((error) {
            if (mounted) {
              setState(() {
                _isLoadingMore = false;
              });
              LogService.instance.error('[WorksScreen] Load more error: $error', tag: 'UI');
            }
          });
        }
      }
    }, controller: controller);
  }

  void _saveScrollPosition(DisplayMode mode) {
    final controller = _controllerFor(mode);
    if (controller.hasClients) {
      _scrollPositions[mode] = controller.offset;
    }
  }

  void _restoreScrollPosition(DisplayMode mode) {
    final controller = _controllerFor(mode);
    final targetOffset = _scrollPositions[mode] ?? 0;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!controller.hasClients) return;
      final maxExtent = controller.position.maxScrollExtent;
      final safeMax = maxExtent.isFinite ? maxExtent : targetOffset;
      final clamped = targetOffset.clamp(0.0, safeMax).toDouble();
      controller.jumpTo(clamped);
    });
  }

  void _handleSwipe(DragEndDetails details) {
    if (details.primaryVelocity == null) return;

    final velocity = details.primaryVelocity!;
    final currentMode = ref.read(worksProvider).displayMode;

    if (velocity.abs() < 500) return;

    if (velocity < 0) {
      if (currentMode == DisplayMode.all) {
        _saveScrollPosition(DisplayMode.all);
        ref.read(worksProvider.notifier).setDisplayMode(DisplayMode.popular);
      } else if (currentMode == DisplayMode.popular) {
        _saveScrollPosition(DisplayMode.popular);
        ref.read(worksProvider.notifier).setDisplayMode(DisplayMode.recommended);
      }
    } else {
      if (currentMode == DisplayMode.recommended) {
        _saveScrollPosition(DisplayMode.recommended);
        ref.read(worksProvider.notifier).setDisplayMode(DisplayMode.popular);
      } else if (currentMode == DisplayMode.popular) {
        _saveScrollPosition(DisplayMode.popular);
        ref.read(worksProvider.notifier).setDisplayMode(DisplayMode.all);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    ref.listen<DisplayMode>(
      worksProvider.select((s) => s.displayMode),
      (previous, next) {
        if (!mounted || previous == null || previous == next) return;

        _saveScrollPosition(previous);

        final prevIndex = DisplayMode.values.indexOf(previous);
        final nextIndex = DisplayMode.values.indexOf(next);

        setState(() {
          _slideDirection = nextIndex >= prevIndex ? 1 : -1;
        });

        _restoreScrollPosition(next);
      },
    );
    ref.listen<List<Work>>(
      worksProvider.select((s) => s.works),
      (previous, next) {
        if (!_batchTriggered && next.isNotEmpty) {
          _batchTriggered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _triggerBatchIfNeeded();
          });
        }
      },
    );

    ref.listen<User?>(
      currentUserProvider,
      (previous, next) {
        final prevKey = previous != null
            ? '${previous.name}|${previous.host}'
            : null;
        final nextKey =
            next != null ? '${next.name}|${next.host}' : null;

        if (prevKey != null && nextKey != null && prevKey != nextKey) {
          _batchTriggered = false;
        }
      },
    );

    final worksState = ref.watch(worksProvider);

    return Scaffold(
      floatingActionButton: const DownloadFab(),
      appBar: const ScrollableAppBar(
        toolbarHeight: 56,
        flexibleSpace: SafeArea(
          child: _WorksAppBarControls(),
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: _handleSwipe,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          switchInCurve: Curves.easeOut,
          switchOutCurve: Curves.easeIn,
          transitionBuilder: (child, animation) {
            final direction = _slideDirection == 0
                ? 0.0
                : (_slideDirection > 0 ? 0.12 : -0.12);
            final offsetAnimation = Tween<Offset>(
              begin: Offset(direction, 0),
              end: Offset.zero,
            ).animate(animation);
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: offsetAnimation,
                child: child,
              ),
            );
          },
          child: KeyedSubtree(
            key: ValueKey(worksState.displayMode),
            child: _buildBody(worksState),
          ),
        ),
      ),
    );
  }

  Widget _buildBody(WorksState worksState) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    if (worksState.works.isEmpty) {
      if (worksState.error != null) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.error_outline,
                size: 64,
                color: cs.error,
              ),
              const SizedBox(height: 16),
              Text(
                S.of(context).loadFailed,
                style: tt.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                worksState.error!,
                style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: () => ref.read(worksProvider.notifier).refresh(),
                icon: const Icon(Icons.refresh),
                label: Text(S.of(context).retry),
              ),
            ],
          ),
        );
      }

      if (worksState.isLoading) {
        return Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(S.of(context).loading),
            ],
          ),
        );
      }

      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.audiotrack,
                size: 64, color: cs.outline),
            const SizedBox(height: 16),
            Text(
              S.of(context).noWorks,
              style: tt.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).checkNetworkOrRetry,
              style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => ref.read(worksProvider.notifier).refresh(),
      child: Stack(
        children: [
          _buildLayoutView(worksState),
          if (worksState.isLoading && worksState.works.isNotEmpty)
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SizedBox(
                height: 3,
                child: LinearProgressIndicator(),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildLayoutView(WorksState worksState) {
    final size = MediaQuery.of(context).size;
    final orientation = MediaQuery.orientationOf(context);

    switch (worksState.layoutType) {
      case LayoutType.bigGrid:
        return _buildGridView(
          worksState,
          crossAxisCount:
              ResponsiveGridHelper.getBigGridCrossAxisCountForSize(size, orientation),
        );
      case LayoutType.smallGrid:
        return _buildGridView(
          worksState,
          crossAxisCount:
              ResponsiveGridHelper.getSmallGridCrossAxisCountForOrientation(orientation),
        );
      case LayoutType.list:
        return _buildListView(worksState);
    }
  }

  Widget _buildGridView(WorksState worksState, {required int crossAxisCount}) {
    final cs = Theme.of(context).colorScheme;
    final isAllMode = worksState.displayMode == DisplayMode.all;
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final spacing = isLandscape ? 24.0 : 8.0;
    final padding = isLandscape ? 24.0 : 8.0;

    Widget scrollView = CustomScrollView(
      // ignore: deprecated_member_use
      cacheExtent: ScrollOptimization.cacheExtent, controller: _controllerFor(worksState.displayMode),
      physics: ScrollOptimization.physics,
      slivers: [
        SliverPadding(
          padding: EdgeInsets.all(padding),
          sliver: SliverMasonryGrid.count(
            crossAxisCount: crossAxisCount,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing,
            childCount: worksState.works.length +
                (!isAllMode && worksState.hasMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (!isAllMode && index == worksState.works.length) {
                return const SizedBox(
                  height: 100,
                  child: Center(child: CircularProgressIndicator()),
                );
              }

              final work = worksState.works[index];
              return RepaintBoundary(
                child: EnhancedWorkCard(
                  key: ValueKey(work.id),
                  work: work,
                  crossAxisCount: crossAxisCount,
                ),
              );
            },
          ),
        ),

        if (!isAllMode && worksState.isLastPage)
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        S.of(context).reachedEnd,
                        style: TextStyle(
                          color: cs.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                  if (worksState.rawWorks.length > worksState.works.length) ...[
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).excludedNWorks(worksState.rawWorks.length - worksState.works.length),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

        if (isAllMode)
          SliverPadding(
            padding: EdgeInsets.fromLTRB(padding, spacing, padding, 24),
            sliver: SliverToBoxAdapter(
              child: Column(
                children: [
                  PaginationBar(
                    currentPage: worksState.currentPage,
                    totalCount: worksState.totalCount,
                    pageSize: worksState.pageSize,
                    hasMore: worksState.hasMore,
                    isLoading: worksState.isLoading,
                    onPreviousPage: () {
                      ref.read(worksProvider.notifier).previousPage();
                      _scrollToTop();
                    },
                    onNextPage: () {
                      ref.read(worksProvider.notifier).nextPage();
                      _scrollToTop();
                    },
                    onGoToPage: (page) {
                      ref.read(worksProvider.notifier).goToPage(page);
                      _scrollToTop();
                    },
                  ),
                  if (worksState.rawWorks.length > worksState.works.length) ...[
                    const SizedBox(height: 8),
                    Text(
                      S.of(context).pageExcludedNWorks(worksState.rawWorks.length - worksState.works.length),
                      style: TextStyle(
                        color: cs.onSurfaceVariant,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
      ],
    );

    if (isAllMode) {
      return OverscrollNextPageDetector(
        onNextPage: () async {
          await ref.read(worksProvider.notifier).nextPage();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTop();
          });
        },
        hasNextPage: worksState.hasMore,
        isLoading: worksState.isLoading,
        child: scrollView,
      );
    }

    return scrollView;
  }

  Widget _buildListView(WorksState worksState) {
    final cs = Theme.of(context).colorScheme;
    final isAllMode = worksState.displayMode == DisplayMode.all;

    Widget scrollView = CustomScrollView(
      // ignore: deprecated_member_use
      cacheExtent: ScrollOptimization.cacheExtent, controller: _controllerFor(worksState.displayMode),
      physics: ScrollOptimization.physics,
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.all(8),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) {
                if (!isAllMode &&
                    index == worksState.works.length &&
                    worksState.hasMore) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: CircularProgressIndicator(),
                    ),
                  );
                }

                if (!isAllMode &&
                    index == worksState.works.length &&
                    worksState.isLastPage) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                        vertical: 24, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.check_circle_outline,
                          size: 16,                          color:
                                cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).reachedEnd,
                          style: TextStyle(
                            color:
                                cs.onSurfaceVariant,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                final work = worksState.works[index];
                return RepaintBoundary(
                  child: EnhancedWorkCard(
                    key: ValueKey(work.id),
                    work: work,
                    crossAxisCount: 1,
                  ),
                );
              },
              childCount: worksState.works.length +
                  (!isAllMode && worksState.hasMore ? 1 : 0) +
                  (!isAllMode && worksState.isLastPage ? 1 : 0),
              addRepaintBoundaries: false,
            ),
          ),
        ),

        if (isAllMode)
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
            sliver: SliverToBoxAdapter(
              child: PaginationBar(
                currentPage: worksState.currentPage,
                totalCount: worksState.totalCount,
                pageSize: worksState.pageSize,
                hasMore: worksState.hasMore,
                isLoading: worksState.isLoading,
                onPreviousPage: () {
                  ref.read(worksProvider.notifier).previousPage();
                  _scrollToTop();
                },
                onNextPage: () {
                  ref.read(worksProvider.notifier).nextPage();
                  _scrollToTop();
                },
                onGoToPage: (page) {
                  ref.read(worksProvider.notifier).goToPage(page);
                  _scrollToTop();
                },
              ),
            ),
          ),
      ],
    );

    if (isAllMode) {
      return OverscrollNextPageDetector(
        onNextPage: () async {
          await ref.read(worksProvider.notifier).nextPage();
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _scrollToTop();
          });
        },
        hasNextPage: worksState.hasMore,
        isLoading: worksState.isLoading,
        child: scrollView,
      );
    }

    return scrollView;
  }

  /// Trigger batch blurhash generation for works on the first visible page.
  /// Debounced by 800ms to let the UI settle after initial data load or account switch.
  void _triggerBatchIfNeeded() {
    _blurHashDebounce?.cancel();
    if (_batchTriggered) return;

    _blurHashDebounce = Timer(const Duration(milliseconds: 800), () {
      if (!mounted) return;
      _batchTriggered = true;

      final worksState = ref.read(worksProvider);
      final authState = ref.read(authProvider);
      final host = authState.host ?? '';
      final token = authState.token ?? '';

      if (host.isEmpty || worksState.works.isEmpty) return;

      const batchSize = 20;
      final batch = worksState.works.take(batchSize).toList();

      final items = batch
          .where((w) => w.blurHash == null)
          .map((w) => (
                workId: w.id,
                imageUrl: w.getCoverImageUrl(host, token: token),
              ))
          .toList();

      if (items.isEmpty) return;

      LogService.instance.debug('[WorksScreen] Triggering batch blurhash for ${items.length} works', tag: 'UI');
      BlurHashService.instance.generateBatch(items);
    });
  }

  void _scrollToTop() {
    final controller = _currentScrollController;
    if (controller.hasClients) {
      controller.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }
}

/// ===================================================================
/// AppBar controls — hanya watch layoutType, subtitleFilter, displayMode
/// Tidak rebuild saat works (data) berubah.
/// ===================================================================
class _WorksAppBarControls extends ConsumerWidget {
  const _WorksAppBarControls();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final (layoutType, subtitleFilter, displayMode) = ref.watch(
      worksProvider.select((s) => (s.layoutType, s.subtitleFilter, s.displayMode)),
    );

    final isRecommendMode =
        displayMode == DisplayMode.popular ||
        displayMode == DisplayMode.recommended;

    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 8.0;

    return Row(
      children: [
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 8),
            child: _buildModeButtons(context, ref, displayMode),
          ),
        ),
        Container(
          height: 28,
          width: 1,
          color: cs.outlineVariant.withValues(alpha: 0.5),
          margin: const EdgeInsets.symmetric(horizontal: 2),
        ),
        IconButton(
          icon: _getLayoutIcon(layoutType),
          iconSize: 22,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => ref.read(worksProvider.notifier).toggleLayoutType(),
          tooltip: _getLayoutTooltip(context, layoutType),
        ),
        IconButton(
          icon: Icon(
            subtitleFilter == 1
                ? Icons.closed_caption
                : Icons.closed_caption_disabled,
            color: subtitleFilter == 1
                ? cs.primary
                : null,
          ),
          iconSize: 22,
          padding: const EdgeInsets.all(6),
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          onPressed: () => ref.read(worksProvider.notifier).toggleSubtitleFilter(),
          tooltip: subtitleFilter == 1
              ? S.of(context).showAllWorks
              : S.of(context).showOnlySubtitled,
        ),
        Padding(
          padding: EdgeInsets.only(right: horizontalPadding - 6),
          child: IconButton(
            icon: Icon(
              Icons.sort,
              color: isRecommendMode ? Colors.grey : null,
            ),
            iconSize: 22,
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onPressed:
                isRecommendMode ? null : () => _showSortDialog(context, ref),
            tooltip: isRecommendMode
                ? S.of(context).recommendedNoSort
                : S.of(context).sort,
          ),
        ),
      ],
    );
  }

  Widget _buildModeButtons(
    BuildContext context,
    WidgetRef ref,
    DisplayMode displayMode,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildModeButton(
          context: context,
          icon: Icons.grid_view,
          label: S.of(context).displayModeAll,
          isSelected: displayMode == DisplayMode.all,
          index: 0,
          total: 3,
          onTap: () => ref
              .read(worksProvider.notifier)
              .setDisplayMode(DisplayMode.all),
        ),
        _buildModeButton(
          context: context,
          icon: Icons.local_fire_department,
          label: S.of(context).displayModePopular,
          isSelected: displayMode == DisplayMode.popular,
          index: 1,
          total: 3,
          onTap: () => ref
              .read(worksProvider.notifier)
              .setDisplayMode(DisplayMode.popular),
        ),
        _buildModeButton(
          context: context,
          icon: Icons.auto_awesome,
          label: S.of(context).displayModeRecommended,
          isSelected: displayMode == DisplayMode.recommended,
          index: 2,
          total: 3,
          onTap: () => ref
              .read(worksProvider.notifier)
              .setDisplayMode(DisplayMode.recommended),
        ),
      ],
    );
  }

  Widget _buildModeButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
    required int index,
    required int total,
  }) {
    final theme = Theme.of(context);

    BorderRadius buttonBorderRadius;
    if (index == 0) {
      buttonBorderRadius = const BorderRadius.only(
        topLeft: Radius.circular(16),
        bottomLeft: Radius.circular(16),
      );
    } else if (index == total - 1) {
      buttonBorderRadius = const BorderRadius.only(
        topRight: Radius.circular(16),
        bottomRight: Radius.circular(16),
      );
    } else {
      buttonBorderRadius = BorderRadius.zero;
    }

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: buttonBorderRadius,
          onTap: onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: isSelected
                  ? theme.colorScheme.primaryContainer
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: buttonBorderRadius,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 16,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Text(
                  label,
                  style: TextStyle(
                    color: isSelected
                        ? theme.colorScheme.primary
                        : theme.colorScheme.onSurfaceVariant,
                    fontSize: 12,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _showSortDialog(BuildContext context, WidgetRef ref) {
    final displayMode = ref.read(worksProvider).displayMode;
    final isRecommendMode = displayMode == DisplayMode.popular ||
        displayMode == DisplayMode.recommended;

    if (isRecommendMode) {
      SnackBarUtil.showInfo(
        context,
        displayMode == DisplayMode.popular
            ? S.of(context).popularNoSort
            : S.of(context).recommendedNoSort,
      );
      return;
    }

    final state = ref.read(worksProvider);
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => CommonSortDialog(
        currentOption: state.sortOption,
        currentDirection: state.sortDirection,
        availableOptions: SortOrder.values
            .where((option) => option != SortOrder.updatedAt)
            .toList(),
        onSort: (option, direction) {
          ref.read(worksProvider.notifier).setSortOption(option);
          ref.read(worksProvider.notifier).setSortDirection(direction);
        },
        autoClose: true,
      ),
    );
  }

  Icon _getLayoutIcon(LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.bigGrid:
        return const Icon(Icons.grid_3x3);
      case LayoutType.smallGrid:
        return const Icon(Icons.view_list);
      case LayoutType.list:
        return const Icon(Icons.view_agenda);
    }
  }

  String _getLayoutTooltip(BuildContext context, LayoutType layoutType) {
    switch (layoutType) {
      case LayoutType.bigGrid:
        return S.of(context).switchToSmallGrid;
      case LayoutType.smallGrid:
        return S.of(context).switchToList;
      case LayoutType.list:
        return S.of(context).switchToLargeGrid;
    }
  }
}