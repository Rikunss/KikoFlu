import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';
import '../providers/my_reviews_provider.dart';
import '../providers/my_tabs_display_provider.dart';
import '../utils/scroll_optimization.dart';
import '../providers/auth_provider.dart';
import '../utils/server_utils.dart';
import '../utils/l10n_extensions.dart';
import '../widgets/enhanced_work_card.dart';
import '../widgets/pagination_bar.dart';
import '../utils/responsive_grid_helper.dart';
import '../widgets/download_fab.dart';
import '../services/download_service.dart';
import '../models/download_task.dart';
import 'downloads_screen.dart';
import 'local_downloads_screen.dart';
import 'subtitle_library_screen.dart';
import 'playlists_screen.dart';
import 'history_screen.dart';
import '../widgets/sort_dialog.dart';
import '../models/sort_options.dart';
export '../providers/my_reviews_provider.dart' show MyReviewLayoutType;

import '../widgets/overscroll_next_page_detector.dart';
import '../../l10n/app_localizations.dart';

/// Tab data for the premium segmented pill control.
class _MyTabPill {
  final String label;
  final IconData outlined;
  final IconData filled;
  final WidgetBuilder builder;
  final bool showFab;
  final WidgetBuilder? fabBuilder;

  const _MyTabPill({
    required this.label,
    required this.outlined,
    required this.filled,
    required this.builder,
    this.showFab = false,
    this.fabBuilder,
  });
}

class MyScreen extends ConsumerStatefulWidget {
  const MyScreen({super.key});

  @override
  ConsumerState<MyScreen> createState() => _MyScreenState();
}

class _MyScreenState extends ConsumerState<MyScreen>
    with AutomaticKeepAliveClientMixin, TickerProviderStateMixin {
  int _currentTabIndex = 0;
  late TabController _tabController;
  List<_MyTabPill> _cachedTabs = [];
  MyTabsDisplaySettings? _lastTabSettings;

  @override
  bool get wantKeepAlive => true;

  List<_MyTabPill> _buildTabList(MyTabsDisplaySettings settings) {
    final s = S.of(context);
    final tabs = <_MyTabPill>[];
    final authState = ref.read(authProvider);
    final isOfficialServer = ServerUtils.isOfficialServer(authState.host);

    if (settings.showOnlineMarks) {
      tabs.add(_MyTabPill(
        label: s.onlineMarks,
        outlined: Icons.bookmark_outline,
        filled: Icons.bookmark,
        builder: (_) => _buildOnlineBookmarksTab(),
        showFab: true,
        fabBuilder: (_) => const DownloadFab(),
      ));
    }

    tabs.add(_MyTabPill(
      label: s.historyRecord,
      outlined: Icons.history,
      filled: Icons.history,
      builder: (_) => const HistoryScreen(),
    ));

    if (settings.showPlaylists && isOfficialServer) {
      tabs.add(_MyTabPill(
        label: s.playlists,
        outlined: Icons.queue_music_outlined,
        filled: Icons.queue_music,
        builder: (_) => const PlaylistsScreen(),
      ));
    }

    tabs.add(_MyTabPill(
      label: s.downloaded,
      outlined: Icons.download_outlined,
      filled: Icons.download,
      builder: (_) => const LocalDownloadsScreen(),
      showFab: true,
      fabBuilder: (_) => StreamBuilder<List<DownloadTask>>(
        key: const ValueKey('downloads_badge'),
        stream: DownloadService.instance.tasksStream,
        builder: (context, snapshot) {
          // Compute active count from stream data reactively.
          final tasks = snapshot.data ?? [];
          final activeCount = tasks.where((t) =>
              t.status == DownloadStatus.downloading ||
              t.status == DownloadStatus.pending).length;
          return Badge(
            isLabelVisible: activeCount > 0,
            label: Text('$activeCount'),
            child: FloatingActionButton(
              onPressed: _navigateToDownloads,
              tooltip: S.of(context).downloadTasks,
              child: const Icon(Icons.download),
            ),
          );
        },
      ),
    ));

    if (settings.showSubtitleLibrary) {
      tabs.add(_MyTabPill(
        label: s.subtitleLibrary,
        outlined: Icons.subtitles_outlined,
        filled: Icons.subtitles,
        builder: (_) => const SubtitleLibraryScreen(),
      ));
    }

    return tabs;
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _tabController.addListener(() {
      if (!_tabController.indexIsChanging) {
        setState(() => _currentTabIndex = _tabController.index);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final myState = ref.read(myReviewsProvider);
      if (myState.works.isEmpty) {
        ref.read(myReviewsProvider.notifier).load(refresh: true);
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _navigateToDownloads() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => const DownloadsScreen(),
      ),
    );
  }

  void _selectTab(int index) {
    if (_currentTabIndex == index) return;
    HapticFeedback.lightImpact();
    _tabController.animateTo(index);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final tabsSettings = ref.watch(myTabsDisplayProvider);

    if (_lastTabSettings != tabsSettings) {
      _cachedTabs = _buildTabList(tabsSettings);
      _lastTabSettings = tabsSettings;
    }
    final tabs = _cachedTabs;

    if (_tabController.length != tabs.length) {
      final oldIndex = _currentTabIndex;
      _tabController.dispose();
      _tabController = TabController(length: tabs.length, vsync: this);
      _tabController.addListener(() {
        if (!_tabController.indexIsChanging) {
          setState(() => _currentTabIndex = _tabController.index);
        }
      });
      if (oldIndex < tabs.length) {
        _tabController.index = oldIndex;
        _currentTabIndex = oldIndex;
      }
    }

    final colorScheme = Theme.of(context).colorScheme;
    const Duration animDur = Duration(milliseconds: 300);

    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(48),
        child: Container(
          color: colorScheme.surface,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Row(
                children: List.generate(tabs.length, (i) {
                  final tab = tabs[i];
                  final isSel = i == _currentTabIndex;

                  return Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(
                        right: i < tabs.length - 1 ? 6 : 0,
                      ),
                      child: GestureDetector(
                        onTap: () => _selectTab(i),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: animDur,
                          curve: Curves.easeOutCubic,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSel
                                ? colorScheme.primaryContainer
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedSwitcher(
                                duration: animDur,
                                switchInCurve: Curves.easeOutBack,
                                switchOutCurve: Curves.easeIn,
                                transitionBuilder: (child, anim) =>
                                    ScaleTransition(
                                      scale: anim,
                                      child: FadeTransition(
                                          opacity: anim, child: child),
                                    ),
                                child: Icon(
                                  isSel ? tab.filled : tab.outlined,
                                  key: ValueKey(
                                      'my_tab_${i}_${isSel ? 'on' : 'off'}'),
                                  size: 16,
                                  color: isSel
                                      ? colorScheme.onPrimaryContainer
                                      : colorScheme.onSurfaceVariant,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(
                                  tab.label,
                                  overflow: TextOverflow.ellipsis,
                                  maxLines: 1,
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: isSel
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    color: isSel
                                        ? colorScheme.onPrimaryContainer
                                        : colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                }),
              ),
            ),
          ),
        ),
      ),
      floatingActionButton: _buildFab(tabs),
      body: TabBarView(
        controller: _tabController,
        children: tabs.map((tab) => tab.builder(context)).toList(),
      ),
    );
  }

  Widget _buildFab(List<_MyTabPill> tabs) {
    final idx = _currentTabIndex;
    if (idx >= 0 && idx < tabs.length) {
      final currentTab = tabs[idx];
      if (currentTab.showFab && currentTab.fabBuilder != null) {
        return currentTab.fabBuilder!(context);
      }
    }
    return const SizedBox.shrink();
  }

  Widget _buildOnlineBookmarksTab() {
    return const Column(
      children: [
        _ProfileHeaderCard(),
        _FilterToolbar(),
        Expanded(child: _ContentArea()),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════
// Profile Header Card
// ═══════════════════════════════════════════════════

class _ProfileHeaderCard extends ConsumerWidget {
  const _ProfileHeaderCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(currentUserProvider);
    final host = ref.watch(serverHostProvider) ?? '';
    final isLoggedIn = ref.watch(isLoggedInProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (user == null) return const SizedBox.shrink();

    final displayName = user.name.isNotEmpty ? user.name : 'User';
    final shortHost = _shortenHost(host);

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
      child: Card(
        elevation: 0,
        color: colorScheme.surfaceContainerLow,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(14)),
        ),
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 22,
                backgroundColor: colorScheme.primaryContainer,
                child: Text(
                  displayName.isNotEmpty
                      ? displayName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      displayName,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(Icons.link, size: 12,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Flexible(
                          child: Text(
                            shortHost,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: isLoggedIn
                                ? Colors.green.shade400
                                : Colors.orange.shade400,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          isLoggedIn ? 'Online' : 'Offline',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: isLoggedIn
                                ? Colors.green.shade400
                                : Colors.orange.shade400,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortenHost(String host) {
    final cleaned = host
        .replaceAll('https://', '')
        .replaceAll('http://', '');
    if (cleaned.length > 28) {
      return '${cleaned.substring(0, 26)}...';
    }
    return cleaned;
  }
}

// ═══════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.icon,
    required this.title,
    this.subtitle,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 48, color: colorScheme.primary),
            ),
            const SizedBox(height: 20),
            Text(
              title,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              OutlinedButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.explore_outlined, size: 18),
                label: Text(actionLabel!),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 20, vertical: 10),
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.all(Radius.circular(12)),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Filter Toolbar — Animated Pill Chips
// ═══════════════════════════════════════════════════

class _FilterToolbar extends ConsumerWidget {
  const _FilterToolbar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myReviewsProvider.select((s) => s.filter));
    final layoutType =
        ref.watch(myReviewsProvider.select((s) => s.layoutType));
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final horizontalPadding = isLandscape ? 24.0 : 8.0;
    final colorScheme = Theme.of(context).colorScheme;
    const Duration animDur = Duration(milliseconds: 300);

    return Container(
      height: 52,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Row(
        children: [
          Expanded(
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.symmetric(
                  horizontal: horizontalPadding, vertical: 4),
              itemCount: MyReviewFilter.values.length,
              itemBuilder: (context, i) {
                final filter = MyReviewFilter.values[i];
                final isSel = state == filter;

                return Padding(
                  padding: EdgeInsets.only(
                      right: i < MyReviewFilter.values.length - 1 ? 6 : 0),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(myReviewsProvider.notifier)
                          .changeFilter(filter);
                    },
                    behavior: HitTestBehavior.opaque,
                    child: AnimatedContainer(
                      duration: animDur,
                      curve: Curves.easeOutCubic,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: isSel
                            ? colorScheme.primaryContainer
                            : colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _filterIcon(filter),
                            size: 16,
                            color: isSel
                                ? colorScheme.primary
                                : colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            filter.localizedLabel(context),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight:
                                  isSel ? FontWeight.w600 : FontWeight.w500,
                              color: isSel
                                  ? colorScheme.primary
                                  : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          Padding(
            padding: EdgeInsets.only(right: horizontalPadding - 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: const Icon(Icons.sort),
                  iconSize: 22,
                  padding: const EdgeInsets.all(8),
                  constraints:
                      const BoxConstraints(minWidth: 40, minHeight: 40),
                  onPressed: () => _showSortDialog(context, ref),
                  tooltip: S.of(context).sort,
                ),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (child, anim) =>
                      RotationTransition(
                        turns: anim,
                        child: FadeTransition(opacity: anim, child: child),
                      ),
                  child: IconButton(
                    key: ValueKey('layout_$layoutType'),
                    icon: _getLayoutIcon(layoutType),
                    iconSize: 22,
                    padding: const EdgeInsets.all(8),
                    constraints:
                        const BoxConstraints(minWidth: 40, minHeight: 40),
                    onPressed: () {
                      HapticFeedback.selectionClick();
                      ref
                          .read(myReviewsProvider.notifier)
                          .toggleLayoutType();
                    },
                    tooltip: _getLayoutTooltip(context, layoutType),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  IconData _filterIcon(MyReviewFilter filter) {
    switch (filter) {
      case MyReviewFilter.all:
        return Icons.all_inclusive;
      case MyReviewFilter.marked:
        return Icons.bookmark;
      case MyReviewFilter.listening:
        return Icons.headphones;
      case MyReviewFilter.listened:
        return Icons.check_circle;
      case MyReviewFilter.replay:
        return Icons.replay;
      case MyReviewFilter.postponed:
        return Icons.schedule;
    }
  }

  Icon _getLayoutIcon(MyReviewLayoutType layoutType) {
    switch (layoutType) {
      case MyReviewLayoutType.bigGrid:
        return const Icon(Icons.grid_view);
      case MyReviewLayoutType.smallGrid:
        return const Icon(Icons.grid_4x4);
      case MyReviewLayoutType.list:
        return const Icon(Icons.view_agenda_outlined);
    }
  }

  String _getLayoutTooltip(BuildContext context, MyReviewLayoutType layoutType) {
    switch (layoutType) {
      case MyReviewLayoutType.bigGrid:
        return S.of(context).switchToSmallGrid;
      case MyReviewLayoutType.smallGrid:
        return S.of(context).switchToList;
      case MyReviewLayoutType.list:
        return S.of(context).switchToLargeGrid;
    }
  }

  static void _showSortDialog(BuildContext context, WidgetRef ref) {
    final state = ref.read(myReviewsProvider);
    showDialog(
      context: context,
      builder: (context) => CommonSortDialog(
        title: S.of(context).sortOptions,
        currentOption: state.sortType,
        currentDirection: state.sortOrder,
        availableOptions: const [
          SortOrder.updatedAt,
          SortOrder.release,
          SortOrder.review,
          SortOrder.dlCount,
        ],
        onSort: (option, direction) {
          ref.read(myReviewsProvider.notifier).changeSort(option, direction);
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Content Area
// ═══════════════════════════════════════════════════

class _ContentArea extends ConsumerWidget {
  const _ContentArea();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final state = ref.watch(myReviewsProvider);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    if (state.error != null) {
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
              state.error!,
              style: tt.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: () =>
                  ref.read(myReviewsProvider.notifier).refresh(),
              icon: const Icon(Icons.refresh),
              label: Text(S.of(context).retry),
            ),
          ],
        ),
      );
    }

    // Initial loading
    if (state.isLoading && state.works.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    // Empty state
    if (state.works.isEmpty && !state.isLoading) {
      return _EmptyState(
        icon: Icons.bookmark_border,
        title: S.of(context).noReviews,
        subtitle: 'Your marked works will appear here',
        actionLabel: S.of(context).search,
        onAction: () {
          // Navigate to search — exploring content
        },
      );
    }

    return Stack(
      children: [
        _buildBody(context, ref, state, isLandscape),
        if (state.isLoading && state.works.isNotEmpty)
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
    );
  }

  Widget _buildBody(BuildContext context, WidgetRef ref,
      MyReviewsState state, bool isLandscape) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      transitionBuilder: (child, anim) =>
          FadeTransition(opacity: anim, child: child),
      child: _buildLayout(context, ref, state, isLandscape),
    );
  }

  Widget _buildLayout(BuildContext context, WidgetRef ref,
      MyReviewsState state, bool isLandscape) {
    final orientation =
        isLandscape ? Orientation.landscape : Orientation.portrait;
    final size = MediaQuery.of(context).size;

    switch (state.layoutType) {
      case MyReviewLayoutType.bigGrid:
        return _buildGridView(
          context,
          ref,
          state,
          crossAxisCount:
              ResponsiveGridHelper.getBigGridCrossAxisCountForSize(size, orientation),
          isLandscape: isLandscape,
        );
      case MyReviewLayoutType.smallGrid:
        return _buildGridView(
          context,
          ref,
          state,
          crossAxisCount:
              ResponsiveGridHelper.getSmallGridCrossAxisCountForOrientation(orientation),
          isLandscape: isLandscape,
        );
      case MyReviewLayoutType.list:
        return _buildListView(context, ref, state);
    }
  }

  Widget _buildGridView(BuildContext context, WidgetRef ref,
      MyReviewsState state, {required int crossAxisCount, bool isLandscape = false}) {
    final spacing = isLandscape ? 24.0 : 8.0;
    final padding = isLandscape ? 24.0 : 8.0;

    return RefreshIndicator(
      onRefresh: () async => ref.read(myReviewsProvider.notifier).refresh(),
      child: OverscrollNextPageDetector(
        hasNextPage: state.hasMore,
        isLoading: state.isLoading,
        onNextPage: () async {
          await ref.read(myReviewsProvider.notifier).nextPage();
        },
        child: CustomScrollView(
          // ignore: deprecated_member_use
          cacheExtent: ScrollOptimization.cacheExtent, physics: ScrollOptimization.physics,
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding, 8, padding, padding),
              sliver: SliverMasonryGrid.count(
                crossAxisCount: crossAxisCount,
                mainAxisSpacing: spacing,
                crossAxisSpacing: spacing,
                childCount: state.works.length,
                itemBuilder: (context, index) {
                  final work = state.works[index];
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
            SliverPadding(
              padding: EdgeInsets.fromLTRB(padding, spacing, padding, 24),
              sliver: SliverToBoxAdapter(
                child: PaginationBar(
                  currentPage: state.currentPage,
                  totalCount: state.totalCount,
                  pageSize: state.pageSize,
                  hasMore: state.hasMore,
                  isLoading: state.isLoading,
                  onPreviousPage: () {
                    ref.read(myReviewsProvider.notifier).previousPage();
                  },
                  onNextPage: () {
                    ref.read(myReviewsProvider.notifier).nextPage();
                  },
                  onGoToPage: (page) {
                    ref.read(myReviewsProvider.notifier).goToPage(page);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildListView(
      BuildContext context, WidgetRef ref, MyReviewsState state) {
    return RefreshIndicator(
      onRefresh: () async => ref.read(myReviewsProvider.notifier).refresh(),
      child: OverscrollNextPageDetector(
        hasNextPage: state.hasMore,
        isLoading: state.isLoading,
        onNextPage: () async {
          await ref.read(myReviewsProvider.notifier).nextPage();
        },
        child: CustomScrollView(
          // ignore: deprecated_member_use
          cacheExtent: ScrollOptimization.cacheExtent, physics: ScrollOptimization.physics,
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.all(8),
              sliver: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    final work = state.works[index];
                    return RepaintBoundary(
                      child: EnhancedWorkCard(
                        key: ValueKey(work.id),
                        work: work,
                        crossAxisCount: 1,
                      ),
                    );
                  },
                  childCount: state.works.length,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 24),
              sliver: SliverToBoxAdapter(
                child: PaginationBar(
                  currentPage: state.currentPage,
                  totalCount: state.totalCount,
                  pageSize: state.pageSize,
                  hasMore: state.hasMore,
                  isLoading: state.isLoading,
                  onPreviousPage: () {
                    ref.read(myReviewsProvider.notifier).previousPage();
                  },
                  onNextPage: () {
                    ref.read(myReviewsProvider.notifier).nextPage();
                  },
                  onGoToPage: (page) {
                    ref.read(myReviewsProvider.notifier).goToPage(page);
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
