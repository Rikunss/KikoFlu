import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';

import '../../l10n/app_localizations.dart';
import '../../src/services/log_service.dart';
import '../models/download_task.dart';
import '../models/sort_options.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../services/storage_service.dart';
import '../utils/string_utils.dart';

import '../providers/auth_provider.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/sort_dialog.dart';
import 'offline_work_detail_screen.dart';
import '../widgets/overscroll_next_page_detector.dart';
import '../widgets/privacy_blur_cover.dart';
import '../utils/scroll_optimization.dart';
import 'local_file_browser_screen.dart';

Map<String, dynamic> _sanitizeMetadata(Map<String, dynamic> metadata) {
  try {
    return _deepSanitize(metadata) as Map<String, dynamic>;
  } catch (e) {
    LogService.instance.error('[LocalDownloads] Error sanitizing metadata: $e', tag: 'Download');
    rethrow;
  }
}

dynamic _deepSanitize(dynamic value) {
  if (value == null) return null;
  if (value is Map) {
    return value.map((key, val) => MapEntry(key.toString(), _deepSanitize(val)));
  }
  if (value is List) {
    return value.map(_deepSanitize).toList();
  }
  // Serialize objects with toJson
  if (const [
    'Va', 'Tag', 'AudioFile', 'RatingDetail', 'OtherLanguageEdition'
  ].contains(value.runtimeType.toString())) {
    try {
      return _deepSanitize((value as dynamic).toJson());
    } catch (e) {
      LogService.instance.warning('[LocalDownloads] Serialization failed ${value.runtimeType}: $e', tag: 'Download');
      return null;
    }
  }
  return value;
}

/// 本地下载屏幕 - 显示已完成的下载内容
class LocalDownloadsScreen extends ConsumerStatefulWidget {
  const LocalDownloadsScreen({super.key});

  @override
  ConsumerState<LocalDownloadsScreen> createState() =>
      _LocalDownloadsScreenState();
}

class _LocalDownloadsScreenState extends ConsumerState<LocalDownloadsScreen>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return const Scaffold(
      backgroundColor: Colors.transparent,
      body: _LocalDownloadList(),
    );
  }
}

/// ===================================================================
/// Download list — owns StreamBuilder + selection/filter/sort/page state
/// ===================================================================
class _LocalDownloadList extends StatefulWidget {
  const _LocalDownloadList();

  @override
  State<_LocalDownloadList> createState() => _LocalDownloadListState();
}

class _LocalDownloadListState extends State<_LocalDownloadList> {
  bool _isSelectionMode = false;
  final Set<int> _selectedWorkIds = {};
  final ScrollController _scrollController = ScrollController();
  int _currentPage = 1;
  static const int _pageSize = 30;

  // Search
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchVisible = false;

  // Sort
  SortOrder _sortOrder = SortOrder.downloadDate;
  SortDirection _sortDirection = SortDirection.desc;

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeInOut,
      );
    }
  }

  void _goToPage(int page) {
    setState(() => _currentPage = page);
    _scrollToTop();
  }

  void _nextPage(int totalPages) {
    if (_currentPage < totalPages) _goToPage(_currentPage + 1);
  }

  void _previousPage() => _goToPage((_currentPage - 1).clamp(1, 9999));

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedWorkIds.clear();
    });
  }

  void _toggleWorkSelection(int workId) {
    setState(() {
      if (_selectedWorkIds.contains(workId)) {
        _selectedWorkIds.remove(workId);
      } else {
        _selectedWorkIds.add(workId);
      }
    });
  }

  void _selectAll(Map<int, List<DownloadTask>> groupedTasks) {
    setState(() {
      _selectedWorkIds.clear();
      _selectedWorkIds.addAll(groupedTasks.keys);
    });
  }

  void _deselectAll() {
    setState(() => _selectedWorkIds.clear());
  }

  Future<void> _openDownloadFolder() async {
    try {
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      final uri = Uri.file(downloadDir.path);
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          return;
        }
      }
      if (mounted) {
        _showSnackBarSafe(SnackBar(
          content: Text(S.of(context).cannotOpenFolder(downloadDir.path)),
          duration: const Duration(seconds: 3),
        ));
      }
    } catch (e) {
      if (mounted) {
        _showSnackBarSafe(SnackBar(
          content: Text(S.of(context).openFolderFailed(e.toString())),
          duration: const Duration(seconds: 3),
        ));
      }
    }
  }

  Future<void> _refreshMetadata() async {
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
        ),
        const SizedBox(width: 12),
        Text(S.of(context).reloadingFromDisk),
      ]),
      duration: const Duration(seconds: 30),
    ));

    try {
      await DownloadService.instance.reloadMetadataFromDisk();
      if (!mounted) return;
      Future.microtask(() {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          _showSnackBarSafe(SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Text(S.of(context).refreshComplete),
            ]),
            duration: const Duration(seconds: 2),
          ));
        }
      });
    } catch (e) {
      if (!mounted) return;
      Future.microtask(() {
        if (mounted) {
          ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
          _showSnackBarSafe(SnackBar(
            content: Text(S.of(context).refreshFailed(e.toString())),
            duration: const Duration(seconds: 3),
          ));
        }
      });
    }
  }

  void _showSnackBarSafe(SnackBar snackBar) {
    if (!mounted) return;
    try {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(snackBar);
    } catch (_) {}
  }

  Future<void> _deleteSelectedWorks(
      Map<int, List<DownloadTask>> groupedTasks) async {
    if (_selectedWorkIds.isEmpty) return;
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).deletionConfirmTitle),
        content: Text(S.of(context).deleteSelectedWorksConfirm(_selectedWorkIds.length)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(context).cancel)),
          TextButton(onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error),
            child: Text(S.of(context).delete)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    int success = 0, total = 0;
    String? errorMsg;
    for (final workId in _selectedWorkIds) {
      for (final task in (groupedTasks[workId] ?? [])) {
        total++;
        try {
          await DownloadService.instance.deleteTask(task.id);
          success++;
        } catch (e) {              errorMsg ??= s.partialDeleteFailed(e.toString());
        }
      }
    }
    if (!mounted) return;
    setState(() {
      _isSelectionMode = false;
      _selectedWorkIds.clear();
    });
    if (mounted) {
      Future.microtask(() {
        if (mounted) {
          _showSnackBarSafe(SnackBar(
            content: Text(errorMsg != null && success > 0
                ? S.of(context).deletedNOfTotal(success, total)
                : errorMsg ?? S.of(context).deleted),
          ));
        }
      });
    }
  }

  void _showSortDialog() {
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (ctx) => CommonSortDialog(
        title: S.of(context).sortOptions,
        currentOption: _sortOrder,
        currentDirection: _sortDirection,
        availableOptions: const [SortOrder.downloadDate, SortOrder.workId],
        onSort: (option, direction) {
          setState(() {
            _sortOrder = option;
            _sortDirection = direction;
            _currentPage = 1;
          });
        },
        autoClose: true,
      ),
    );
  }

  void _toggleSearch() {
    setState(() {
      _isSearchVisible = !_isSearchVisible;
      if (!_isSearchVisible) {
        _searchController.clear();
        _searchQuery = '';
        _currentPage = 1;
      }
    });
  }

  Map<int, List<DownloadTask>> _filterTasks(
      Map<int, List<DownloadTask>> groupedTasks) {
    if (_searchQuery.isEmpty) return groupedTasks;
    final query = _searchQuery.toLowerCase();
    return Map.fromEntries(groupedTasks.entries.where((e) {
      final first = e.value.first;
      if (first.workTitle.toLowerCase().contains(query)) return true;
      final rj = 'RJ${e.key.toString().padLeft(6, '0')}';
      return rj.toLowerCase().contains(query) || e.key.toString().contains(query);
    }));
  }

  List<int> _sortWorkIds(Map<int, List<DownloadTask>> groupedTasks) {
    final ids = groupedTasks.keys.toList();
    ids.sort((a, b) {
      int r;
      switch (_sortOrder) {
        case SortOrder.downloadDate:
          final aD = groupedTasks[a]!
              .map((t) => t.completedAt ?? t.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
          final bD = groupedTasks[b]!
              .map((t) => t.completedAt ?? t.createdAt).reduce((x, y) => x.isAfter(y) ? x : y);
          r = aD.compareTo(bD);
        case SortOrder.workId:
          r = a.compareTo(b);
        default:
          r = 0;
      }
      return _sortDirection == SortDirection.asc ? r : -r;
    });
    return ids;
  }

  void _openWorkDetail(int workId, DownloadTask task) async {
    if (task.workMetadata == null) {
      _showSnackBarSafe(SnackBar(
        content: Text(S.of(context).noWorkMetadataForOffline),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    try {
      final metadata = _sanitizeMetadata(task.workMetadata!);
      final work = Work.fromJson(metadata);
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      final relPath = metadata['localCoverPath'] as String?;
      final localCover = relPath != null ? '${downloadDir.path}/$workId/$relPath' : null;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OfflineWorkDetailScreen(
          work: work, isOffline: true, localCoverPath: localCover),
      ));
    } catch (e) {
      if (mounted) {
        _showSnackBarSafe(SnackBar(
          content: Text(S.of(context).openWorkDetailFailed(e.toString())),
          duration: const Duration(seconds: 2),
        ));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<DownloadTask>>(
      stream: DownloadService.instance.tasksStream,
      initialData: DownloadService.instance.tasks,
      builder: (context, snapshot) {
        final tasks = snapshot.data ?? [];
        final completed = tasks.where((t) => t.status == DownloadStatus.completed).toList();

        // Group by workId
        final Map<int, List<DownloadTask>> allGrouped = {};
        for (final task in completed) {
          allGrouped.putIfAbsent(task.workId, () => []).add(task);
        }

        // Filter + sort
        final grouped = _filterTasks(allGrouped);
        final sortedIds = _sortWorkIds(grouped);

        // Pagination
        final total = sortedIds.length;
        final totalPages = (total / _pageSize).ceil();
        final start = (_currentPage - 1) * _pageSize;
        final end = (start + _pageSize).clamp(0, total);
        final pageIds = sortedIds.sublist(start, end);
        final pageMap = Map<int, List<DownloadTask>>.fromEntries(
          pageIds.map((id) => MapEntry(id, grouped[id]!)),
        );

        return Column(children: [
          _DownloadTopBar(
            isSelectionMode: _isSelectionMode,
            selectedCount: _selectedWorkIds.length,
            totalWorkCount: allGrouped.length,
            isSearchVisible: _isSearchVisible,
            onToggleSelectionMode: _toggleSelectionMode,
            onSelectAll: () => _selectAll(allGrouped),
            onDeselectAll: _deselectAll,
            onDeleteSelected: () => _deleteSelectedWorks(allGrouped),
            onRefresh: _refreshMetadata,
            onOpenFolder: _openDownloadFolder,
            onToggleSearch: _toggleSearch,
            onShowSort: _showSortDialog,
          ),
          if (_isSearchVisible) _buildSearchBar(),
          Expanded(
            child: allGrouped.isEmpty
                ? _emptyState(context, S.of(context).noLocalDownloads, Icons.download_outlined)
                : grouped.isEmpty
                    ? _emptyState(context, S.of(context).noResults, Icons.search_off)
                    : OverscrollNextPageDetector(
                        hasNextPage: _currentPage < totalPages,
                        isLoading: false,
                        onNextPage: () async {
                          _nextPage(totalPages);
                          await Future.delayed(const Duration(milliseconds: 50));
                          WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToTop());
                        },
                        child: CustomScrollView(
                          // ignore: deprecated_member_use
                          cacheExtent: ScrollOptimization.cacheExtent, controller: _scrollController,
                          physics: ScrollOptimization.physics,
                          slivers: [
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                              sliver: SliverGrid(
                                gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: 210,
                                  childAspectRatio: 0.72,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                                delegate: SliverChildBuilderDelegate(
                                  (context, index) {
                                    final id = pageIds[index];
                                    final workTasks = pageMap[id]!;
                                    return RepaintBoundary(
                                      key: ValueKey('dl_$id'),
                                      child: _DownloadWorkCard(
                                      workId: id,
                                      workTasks: workTasks,
                                      firstTask: workTasks.first,
                                      isSelected: _selectedWorkIds.contains(id),
                                      isSelectionMode: _isSelectionMode,
                                      onTap: _isSelectionMode
                                          ? () => _toggleWorkSelection(id)
                                          : () => _openWorkDetail(id, workTasks.first),
                                      onLongPress: !_isSelectionMode
                                          ? () => setState(() {
                                              _isSelectionMode = true;
                                              _toggleWorkSelection(id);
                                            })
                                          : null,
                                      ),
                                    );
                                  },
                                  childCount: pageMap.length,
                                ),
                              ),
                            ),
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                              sliver: SliverToBoxAdapter(
                                child: PaginationBar(
                                  currentPage: _currentPage,
                                  totalCount: total,
                                  pageSize: _pageSize,
                                  hasMore: _currentPage < totalPages,
                                  isLoading: false,
                                  onPreviousPage: _previousPage,
                                  onNextPage: () => _nextPage(totalPages),
                                  onGoToPage: _goToPage,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
          ),
        ]);
      },
    );
  }

  Widget _buildSearchBar() {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        decoration: InputDecoration(
          hintText: S.of(context).searchDownloads,
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 20),
                  onPressed: () {
                    _searchController.clear();
                    setState(() {
                      _searchQuery = '';
                      _currentPage = 1;
                    });
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onChanged: (value) {
          setState(() {
            _searchQuery = value;
            _currentPage = 1;
          });
        },
      ),
    );
  }

  Widget _emptyState(BuildContext context, String message, IconData icon) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
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
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                icon,
                size: 40,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              message,
              style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// Top toolbar — receives all callbacks, no state
/// ===================================================================
class _DownloadTopBar extends StatelessWidget {
  final bool isSelectionMode;
  final int selectedCount;
  final int totalWorkCount;
  final bool isSearchVisible;
  final VoidCallback onToggleSelectionMode;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onDeleteSelected;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;
  final VoidCallback onToggleSearch;
  final VoidCallback onShowSort;

  const _DownloadTopBar({
    required this.isSelectionMode,
    required this.selectedCount,
    required this.totalWorkCount,
    required this.isSearchVisible,
    required this.onToggleSelectionMode,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onDeleteSelected,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onToggleSearch,
    required this.onShowSort,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final cs = Theme.of(context).colorScheme;
    final hPad = isLandscape ? 24.0 : 8.0;

    return Container(
      height: 56,
      padding: const EdgeInsets.symmetric(vertical: 4),
      color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
      child: isSelectionMode ? _buildSelectionBar(context, hPad, cs) : _buildActionBar(context, hPad),
    );
  }

  Widget _buildSelectionBar(BuildContext context, double hPad, ColorScheme cs) {
    return Row(children: [
      Padding(
        padding: EdgeInsets.only(left: hPad - 8),
        child: IconButton(
          icon: const Icon(Icons.close), iconSize: 22,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onToggleSelectionMode,
          tooltip: S.of(context).exitSelection,
        ),
      ),
      Text(S.of(context).selectedCount(selectedCount),
          style: Theme.of(context).textTheme.titleSmall),
      const Spacer(),
      IconButton(
        icon: Icon(selectedCount == totalWorkCount ? Icons.deselect : Icons.select_all),
        iconSize: 22, padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: selectedCount == totalWorkCount ? onDeselectAll : onSelectAll,
        tooltip: selectedCount == totalWorkCount
            ? S.of(context).deselectAll : S.of(context).selectAll,
      ),
      if (selectedCount > 0)
        IconButton(
          icon: const Icon(Icons.delete), iconSize: 22,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onDeleteSelected,
          tooltip: '${S.of(context).delete} ($selectedCount)',
          color: cs.error,
        ),
      SizedBox(width: hPad - 8),
    ]);
  }

  Widget _buildActionBar(BuildContext context, double hPad) {
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: [            Padding(
            padding: const EdgeInsets.only(left: 16, right: 6),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.checklist, size: 18),
              label: Text(S.of(context).select),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                onToggleSelectionMode();
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 6),              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(S.of(context).reload),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onRefresh();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 6),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.folder_open, size: 18),
              label: Text(S.of(context).browseFiles),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LocalFileBrowserScreen(),
                  ),
                );
              },
            ),
          ),
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: FilledButton.tonalIcon(
                icon: const Icon(Icons.folder_open, size: 18),
                label: Text(S.of(context).openFolder),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () {
                  HapticFeedback.lightImpact();
                  onOpenFolder();
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: Icon(isSearchVisible ? Icons.search_off : Icons.search, size: 22),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () {
                HapticFeedback.lightImpact();
                onToggleSearch();
              },
              tooltip: S.of(context).search,
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: IconButton(
              icon: const Icon(Icons.sort, size: 22),
              padding: const EdgeInsets.all(8),
              constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
              onPressed: () {
                HapticFeedback.lightImpact();
                onShowSort();
              },
              tooltip: S.of(context).sortOptions,
            ),
          ),
        ]),
      ),
    );
  }
}

/// ===================================================================
/// Search bar — shown when _isSearchVisible
/// ===================================================================
// (Search bar is built inline in _DownloadTopBar parent as a separate container)

/// ===================================================================
/// Work card — receives auth props instead of ref.watch per card
/// ===================================================================
class _DownloadWorkCard extends StatelessWidget {
  final int workId;
  final List<DownloadTask> workTasks;
  final DownloadTask firstTask;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DownloadWorkCard({
    required this.workId,
    required this.workTasks,
    required this.firstTask,
    required this.isSelected,
    required this.isSelectionMode,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final totalSize = workTasks.fold<int>(
      0, (sum, t) => sum + (t.totalBytes ?? 0),
    );
    final cs = Theme.of(context).colorScheme;

    Work? work;
    if (firstTask.workMetadata != null) {
      try {
        final sanitized = _sanitizeMetadata(firstTask.workMetadata!);
        work = Work.fromJson(sanitized);
      } catch (e) {
        LogService.instance.warning('[LocalDownloads] Failed to parse work metadata for offline card: $e', tag: 'Download');
      }
    }

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: isSelected ? 8 : 2,
      shadowColor: isSelected
          ? cs.primary.withValues(alpha: 0.4)
          : null,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: isSelected
            ? BorderSide(color: cs.primary, width: 2)
            : BorderSide.none,
      ),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Stack(children: [
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // Cover
            Expanded(
              child: Stack(fit: StackFit.expand, children: [
                _WorkCardCover(workId: workId, work: work, firstTask: firstTask),
                Positioned(
                  left: 0, right: 0, bottom: 0,
                  child: Container(
                    height: 60,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter, end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.7)],
                      ),
                    ),
                  ),
                ),
              ]),
            ),
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(
                  work?.title ?? firstTask.workTitle,
                  maxLines: 2, overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                    height: 1.3, color: cs.onSurface),
                ),
                const SizedBox(height: 8),
                if (work?.vas != null && work!.vas!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(children: [
                      Icon(Icons.mic, size: 12,
                        color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Expanded(child: Text(work.vas!.first.name,
                        maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11,
                          color: cs.onSurfaceVariant))),
                    ]),
                  ),
                Row(children: [
                  Icon(Icons.folder_outlined, size: 12,
                    color: cs.primary),
                  const SizedBox(width: 4),
                  Text('${workTasks.length}', style: TextStyle(fontSize: 11,
                    fontWeight: FontWeight.w500,
                    color: cs.primary)),
                  const SizedBox(width: 8),
                  Icon(Icons.storage, size: 12,
                    color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Flexible(child: Text(formatBytes(totalSize),
                    style: TextStyle(fontSize: 11,
                      color: cs.onSurfaceVariant),
                    overflow: TextOverflow.ellipsis)),
                ]),
              ]),
            ),
          ]),
          if (isSelectionMode)
            Positioned(
              top: 8, right: 8,
              child: Container(
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary
                      : Colors.white.withValues(alpha: 0.95),
                  shape: BoxShape.circle,
                  boxShadow: [BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 8, offset: const Offset(0, 2))],
                ),
                padding: const EdgeInsets.all(6),
                child: Icon(
                  isSelected ? Icons.check : Icons.circle_outlined,
                  color: isSelected ? Colors.white
                      : cs.outline,
                  size: 20,
                ),
              ),
            ),
        ]),
      ),
    );
  }
}

/// ===================================================================
/// Work card cover — fetches auth only when needed (not per-card)
/// ===================================================================
class _WorkCardCover extends ConsumerWidget {
  final int workId;
  final Work? work;
  final DownloadTask firstTask;

  const _WorkCardCover({
    required this.workId,
    this.work,
    required this.firstTask,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Prefer local cover
    if (firstTask.workMetadata != null) {
      final relPath = firstTask.workMetadata!['localCoverPath'] as String?;
      if (relPath != null) {
        return FutureBuilder<Directory>(
          future: DownloadService.instance.getDownloadDirectory(),
          builder: (context, snap) {
            if (snap.hasData) {
              final path = '${snap.data!.path}/$workId/$relPath';
              final file = File(path);
              if (file.existsSync()) {
                final dpr = MediaQuery.devicePixelRatioOf(context);
                return Hero(
                  tag: 'offline_work_cover_$workId',
                  child: PrivacyBlurCover(
                    borderRadius: BorderRadius.circular(8),
                    child: Image.file(file,
                      fit: BoxFit.cover,
                      width: double.infinity,
                      cacheWidth: (210 * dpr).round(),
                    ),
                  ),
                );
              }
            }
            return _buildPlaceholder(context);
          },
        );
      }
    }

    // Fallback to network cover — narrow auth watch with select()
    final host = ref.watch(authProvider.select((s) => s.host));
    if (work != null && host != null && host.isNotEmpty) {
      return Hero(
        tag: 'offline_work_cover_$workId',
        child: PrivacyBlurCover(
          borderRadius: BorderRadius.circular(8),                          child: CachedNetworkImage(
                            imageUrl: work!.getCoverImageUrl(host),
                            cacheKey: 'work_cover_${work!.id}',
                            httpHeaders: StorageService.serverCookieHeaders,
                            fit: BoxFit.cover,
                            errorWidget: (_, __, ___) => _buildPlaceholder(context),
          ),
        ),
      );
    }
    return _buildPlaceholder(context);
  }

  Widget _buildPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.image_not_supported, size: 48,
        color: cs.outline),
    );
  }
}
