import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';
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
import '../utils/metadata_utils.dart';
import '../widgets/custom_file_picker.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/sort_dialog.dart';
import 'offline_work_detail_screen.dart';
import '../widgets/overscroll_next_page_detector.dart';
import '../widgets/privacy_blur_cover.dart';
import '../utils/scroll_optimization.dart';
import 'local_file_browser_screen.dart';

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

  // Filter by circle / VA / tag
  _FilterType _filterType = _FilterType.all;
  String _filterValue = '';

  /// Cache parsed Work objects by workId to avoid re-parsing metadata.
  final Map<int, Work> _workCache = {};

  // ── Reactive subscriptions ──
  StreamSubscription<List<DownloadTask>>? _tasksSub;
  List<DownloadTask> _allTasks = [];

  @override
  void initState() {
    super.initState();
    _allTasks = DownloadService.instance.tasks;
    _tasksSub = DownloadService.instance.tasksStream.listen((tasks) {
      if (!mounted) return;
      _workCache.clear(); // invalidate cache on data change
      setState(() => _allTasks = tasks);
    });
  }

  @override
  void dispose() {
    _tasksSub?.cancel();
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
    // Clear work cache so filter options are rebuilt
    _workCache.clear();
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

  /// ── Filter helpers ──

  /// Lazily parse and cache a [Work] from the first task's metadata.
  Work? _getWork(int workId, List<DownloadTask> tasks) {
    if (_workCache.containsKey(workId)) return _workCache[workId];
    final meta = tasks.first.workMetadata;
    if (meta == null) return null;
    try {
      final sanitized = sanitizeMetadata(meta);
      final work = Work.fromJson(sanitized);
      _workCache[workId] = work;
      return work;
    } catch (_) {
      return null;
    }
  }

  /// Extract unique circles, VAs, and tags from all completed tasks.
  Map<String, List<String>> _extractFilterOptions(
      Map<int, List<DownloadTask>> grouped) {
    final circles = <String>{};
    final vas = <String>{};
    final tags = <String>{};

    for (final entry in grouped.entries) {
      final work = _getWork(entry.key, entry.value);
      if (work == null) continue;

      if (work.name != null && work.name!.isNotEmpty) circles.add(work.name!);
      if (work.vas != null) {
        for (final va in work.vas!) {
          if (va.name.isNotEmpty) vas.add(va.name);
        }
      }
      if (work.tags != null) {
        for (final tag in work.tags!) {
          if (tag.name.isNotEmpty) tags.add(tag.name);
        }
      }
    }

    return {
      'circles': circles.toList()..sort(),
      'vas': vas.toList()..sort(),
      'tags': tags.toList()..sort(),
    };
  }

  /// Apply search + metadata filter to the grouped tasks.
  Map<int, List<DownloadTask>> _filterTasks(
      Map<int, List<DownloadTask>> groupedTasks) {
    // Apply metadata filter first
    Map<int, List<DownloadTask>> result = groupedTasks;
    if (_filterType != _FilterType.all && _filterValue.isNotEmpty) {
      result = Map.fromEntries(groupedTasks.entries.where((e) {
        final work = _getWork(e.key, e.value);
        if (work == null) return false;
        switch (_filterType) {
          case _FilterType.all:
            return true;
          case _FilterType.circle:
            return work.name == _filterValue;
          case _FilterType.va:
            return work.vas?.any((va) => va.name == _filterValue) ?? false;
          case _FilterType.tag:
            return work.tags?.any((tag) => tag.name == _filterValue) ?? false;
        }
      }));
    }

    // Then apply search query
    if (_searchQuery.isEmpty) return result;
    final query = _searchQuery.toLowerCase();
    return Map.fromEntries(result.entries.where((e) {
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
      final metadata = sanitizeMetadata(task.workMetadata!);
      final work = Work.fromJson(metadata);
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      final relPath = metadata['localCoverPath'] as String?;
      final localCover = relPath != null ? '${downloadDir.path}/$workId/$relPath' : null;
      final localImportPath = metadata['local_import_path'] as String?;
      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OfflineWorkDetailScreen(
          work: work, isOffline: true, localCoverPath: localCover,
          localImportPath: localImportPath),
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


  /// Import a single folder as one work.
  Future<void> _importSingleFolder() async {
    final s = S.of(context);

    final folderPath = await CustomFilePicker.pickDirectory(
      context: context,
      title: s.selectImportFolderSingle,
    );
    if (folderPath == null || !mounted) return;
    final displayPath = folderPath.split(Platform.pathSeparator).last;
    final titleCtrl = TextEditingController(text: displayPath);
    final title = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.importDialogTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(s.importDialogMessage(displayPath)),
            const SizedBox(height: 16),
            TextField(
              controller: titleCtrl,
              decoration: InputDecoration(
                labelText: s.workNameTitle,
                border: const OutlineInputBorder(),
                hintText: s.enterWorkName,
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              final name = titleCtrl.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx, name);
              }
            },
            child: Text(s.importAction),
          ),
        ],
      ),
    );

    if (title == null || !mounted) return;

    _showSnackBarSafe(SnackBar(
      content: Row(children: [
        const SizedBox(width: 16, height: 16,
          child: CircularProgressIndicator(strokeWidth: 2,
            valueColor: AlwaysStoppedAnimation<Color>(Colors.white)),
        ),
        const SizedBox(width: 12),
        Text(s.importingWork),
      ]),
      duration: const Duration(seconds: 30),
    ));

    try {
      await DownloadService.instance.importLocalWork(
        folderPath: folderPath,
        title: title,
      );
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      // Reset to page 1 so the newly imported work is visible
      setState(() => _currentPage = 1);
      _scrollToTop();
      _showSnackBarSafe(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(s.importComplete)),
        ]),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.clearSnackBars();
      _showSnackBarSafe(SnackBar(
        content: Text(s.importFailed(e.toString())),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  /// Import multiple subfolders — each becomes one work.
  Future<void> _importMultipleFolders() async {
    final dialogContext = context;
    final s = S.of(dialogContext);

    final parentPath = await CustomFilePicker.pickDirectory(
      context: dialogContext,
      title: s.selectImportFolderMultiple,
    );
    if (parentPath == null || !mounted) return;

    final parentDir = Directory(parentPath);
    int totalSubfolders = 0;
    if (await parentDir.exists()) {
      await for (final e in parentDir.list(followLinks: false)) {
        if (e is Directory && !e.path.split(Platform.pathSeparator).last.startsWith('.')) {
          totalSubfolders++;
        }
      }
    }

    if (totalSubfolders == 0) {
      _showSnackBarSafe(SnackBar(
        content: Text(s.importFailed('No subfolders found')),
        duration: const Duration(seconds: 3),
      ));
      return;
    }

    if (!dialogContext.mounted) return;

    final progressNotifier = ValueNotifier<_ImportProgress>(
      _ImportProgress(completed: 0, total: totalSubfolders, currentFolder: ''),
    );

    final dialogFuture = showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Row(children: [
          const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(width: 12),
          Text(s.importingMultipleWorks),
        ]),
        content: ValueListenableBuilder<_ImportProgress>(
          valueListenable: progressNotifier,
          builder: (ctx, progress, _) {
            final foldername = progress.currentFolder;
            final ratio = progress.total > 0 ? progress.completed / progress.total : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: ratio,
                    minHeight: 8,
                    backgroundColor: Theme.of(ctx).colorScheme.surfaceContainerHighest,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  '${progress.completed} / ${progress.total}',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (foldername.isNotEmpty) ...[const SizedBox(height: 4),
                  Text(
                    foldername,
                    style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                      color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            );
          },
        ),
      ),
    );

    try {
      final createdIds = await DownloadService.instance.importMultipleLocalWorks(
        parentFolderPath: parentPath,
        onProgress: (current, total, folderName) {
          progressNotifier.value = _ImportProgress(
            completed: current, total: total, currentFolder: folderName,
          );
        },
      );

      if (!mounted) return;
      if (dialogContext.mounted) {
        // ignore: use_build_context_synchronously
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
      await dialogFuture;

      setState(() => _currentPage = 1);
      _scrollToTop();

      _showSnackBarSafe(SnackBar(
        content: Row(children: [
          const Icon(Icons.check_circle, color: Colors.white),
          const SizedBox(width: 12),
          Expanded(child: Text(
            createdIds.length < totalSubfolders
                ? s.importPartialComplete(createdIds.length, totalSubfolders)
                : s.importMultipleComplete(createdIds.length),
          )),
        ]),
        duration: const Duration(seconds: 3),
      ));
    } catch (e) {
      if (!mounted) return;
      if (dialogContext.mounted) {
        // ignore: use_build_context_synchronously
        Navigator.of(dialogContext, rootNavigator: true).pop();
      }
      await dialogFuture;
      _showSnackBarSafe(SnackBar(
        content: Text(s.importFailed(e.toString())),
        duration: const Duration(seconds: 4),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _allTasks;
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
      _buildImportBar(),
      _buildFilterBar(allGrouped),
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
  }

  /// Import bar — sits between the top toolbar and the filter bar.
  Widget _buildImportBar() {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.folder_rounded, size: 16, color: cs.onSurfaceVariant.withAlpha(120)),
          const SizedBox(width: 8),
          Text(
            s.importWork,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant,
            ),
          ),
          const Spacer(),
          PopupMenuButton<_ImportAction>(
            tooltip: s.importWork,
            icon: Icon(Icons.add_circle_outline_rounded, size: 22, color: cs.primary),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
            onSelected: (action) {
              HapticFeedback.lightImpact();
              switch (action) {
                case _ImportAction.singleFolder:
                  _importSingleFolder();
                case _ImportAction.multipleFolders:
                  _importMultipleFolders();
              }
            },
            itemBuilder: (ctx) => [
              PopupMenuItem(
                value: _ImportAction.singleFolder,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.create_new_folder_rounded, size: 20),
                  title: Text(s.importSingleFolder),
                  subtitle: Text(s.importSingleFolderDesc, style: const TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: _ImportAction.multipleFolders,
                child: ListTile(
                  dense: true,
                  leading: const Icon(Icons.folder_copy_rounded, size: 20),
                  title: Text(s.importMultipleFolders),
                  subtitle: Text(s.importMultipleFoldersDesc, style: const TextStyle(fontSize: 11)),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Filter bar — chips for Circle / VA / Tag filtering.
  Widget _buildFilterBar(Map<int, List<DownloadTask>> grouped) {
    final cs = Theme.of(context).colorScheme;
    final options = _extractFilterOptions(grouped);
    final hasActiveFilter = _filterType != _FilterType.all;

    // Only show if there are filterable options or an active filter
    final hasOptions = options.values.any((list) => list.isNotEmpty);
    if (!hasOptions && !hasActiveFilter) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            // "All" chip (always visible to clear filter)
            _FilterChip(
              label: 'All',
              icon: Icons.filter_alt_off_rounded,
              isSelected: !hasActiveFilter,
              onTap: () => setState(() {
                _filterType = _FilterType.all;
                _filterValue = '';
                _currentPage = 1;
              }),
              cs: cs,
            ),
            const SizedBox(width: 6),

            // Circle filter chip
            if (options['circles']!.isNotEmpty)
              _buildFilterChip(
                label: 'Circle',
                icon: Icons.business_rounded,
                type: _FilterType.circle,
                options: options['circles']!,
                cs: cs,
              ),

            // VA filter chip
            if (options['vas']!.isNotEmpty)
              _buildFilterChip(
                label: 'VA',
                icon: Icons.mic_rounded,
                type: _FilterType.va,
                options: options['vas']!,
                cs: cs,
              ),

            // Tag filter chip
            if (options['tags']!.isNotEmpty)
              _buildFilterChip(
                label: 'Tag',
                icon: Icons.label_rounded,
                type: _FilterType.tag,
                options: options['tags']!,
                cs: cs,
              ),

            // Active filter badge
            if (hasActiveFilter) ...[
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: cs.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _filterValue,
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: cs.onPrimaryContainer),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Build a single filter chip group (Circle / VA / Tag).
  /// Tapping the chip opens a bottom sheet to pick a value.
  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required _FilterType type,
    required List<String> options,
    required ColorScheme cs,
  }) {
    final isActive = _filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 14,
          color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        label: Text(
          isActive ? _filterValue : label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
            color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant,
          ),
        ),
        side: isActive
            ? BorderSide(color: cs.primary, width: 1)
            : BorderSide(color: cs.outlineVariant.withAlpha(80)),
        backgroundColor: isActive ? cs.primaryContainer : cs.surfaceContainerHighest.withAlpha(120),
        onPressed: () => _showFilterPicker(type, options, label),
      ),
    );
  }

  /// Show a bottom sheet to pick a filter value.
  void _showFilterPicker(_FilterType type, List<String> options, String label) {
    final s = S.of(context);
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(children: [
                Text('Filter by $label',
                  style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600)),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: Text(s.cancel),
                ),
              ]),
            ),
            const Divider(height: 1),
            // Options list
            SizedBox(
              height: (options.length * 52 + 16).clamp(100, 360).toDouble(),
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final value = options[i];
                  final isSelected = _filterType == type && _filterValue == value;
                  return ListTile(
                    dense: true,
                    leading: Icon(
                      isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                      size: 20,
                    ),
                    title: Text(value, style: const TextStyle(fontSize: 14)),
                    trailing: isSelected
                        ? Icon(Icons.check_circle, color: Theme.of(ctx).colorScheme.primary, size: 20)
                        : null,
                    selected: isSelected,
                    onTap: () {
                      Navigator.pop(ctx);
                      setState(() {
                        _filterType = type;
                        _filterValue = value;
                        _currentPage = 1;
                      });
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
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
/// Progress state for the import multiple dialog.
class _ImportProgress {
  final int completed;
  final int total;
  final String currentFolder;
  const _ImportProgress({
    required this.completed,
    required this.total,
    this.currentFolder = '',
  });
}

enum _ImportAction { singleFolder, multipleFolders }

/// Filter type for the downloads filter bar.
enum _FilterType { all, circle, va, tag }

/// Small reusable filter chip widget.
class _FilterChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _FilterChip({
    required this.label,
    required this.icon,
    required this.isSelected,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return ActionChip(
      avatar: Icon(icon, size: 14,
        color: isSelected ? cs.primary : cs.onSurfaceVariant),
      label: Text(label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          color: isSelected ? cs.primary : cs.onSurfaceVariant,
        ),
      ),
      backgroundColor: isSelected
          ? cs.primaryContainer.withValues(alpha: 0.4)
          : cs.surfaceContainerHighest.withValues(alpha: 0.6),
      side: BorderSide(color: cs.outlineVariant.withAlpha(80)),
      onPressed: onTap,
    );
  }
}

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
              icon: const Icon(Icons.folder_rounded, size: 18),
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
        final sanitized = sanitizeMetadata(firstTask.workMetadata!);
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
                // Colored avatar with work title initial
                Positioned(
                  top: 8, left: 8,
                  child: _WorkAvatar(
                    workId: workId,
                    title: work?.title ?? firstTask.workTitle,
                    size: 34,
                  ),
                ),
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
/// Generate a consistent color from a workId using the golden angle.
/// Each work gets a distinct hue that stays the same across sessions.
Color _workColor(int id) {
  final hue = (id * 137.508) % 360;
  return HSLColor.fromAHSL(0.85, hue, 0.55, 0.5).toColor();
}

/// Small circle avatar with the first character of the work title.
/// Placed as an overlay on the cover image to help distinguish works.
class _WorkAvatar extends StatelessWidget {
  final int workId;
  final String? title;
  final double size;

  const _WorkAvatar({
    required this.workId,
    this.title,
    this.size = 32,
  });

  @override
  Widget build(BuildContext context) {
    final color = _workColor(workId);
    final initial = (title ?? '').isNotEmpty ? title![0].toUpperCase() : '?';

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.35),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.5),
          width: 1.5,
        ),
      ),
      child: Center(
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: size * 0.48,
            letterSpacing: 0,
          ),
        ),
      ),
    );
  }
}

class _WorkCardCover extends ConsumerStatefulWidget {
  final int workId;
  final Work? work;
  final DownloadTask firstTask;

  const _WorkCardCover({
    required this.workId,
    this.work,
    required this.firstTask,
  });

  @override
  ConsumerState<_WorkCardCover> createState() => _WorkCardCoverState();
}

class _WorkCardCoverState extends ConsumerState<_WorkCardCover> {
  /// Cached local cover file path (resolved once in initState)
  String? _coverPath;

  /// Whether we've finished trying to resolve the local cover
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _resolveCover();
  }

  Future<void> _resolveCover() async {
    final meta = widget.firstTask.workMetadata;
    if (meta == null) {
      if (mounted) setState(() => _resolved = true);
      return;
    }
    final relPath = meta['localCoverPath'] as String?;
    if (relPath == null) {
      if (mounted) setState(() => _resolved = true);
      return;
    }
    try {
      final dir = await DownloadService.instance.getDownloadDirectory();
      final path = '${dir.path}/${widget.workId}/$relPath';
      final file = File(path);
      if (await file.exists()) {
        if (mounted) setState(() => _coverPath = path);
        return;
      }
    } catch (_) {}
    if (mounted) setState(() => _resolved = true);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (210 * dpr).round();
    final cacheHeight = ((210 / 0.72 - 94.0) * dpr).round();

    if (_coverPath != null) {
      return Hero(
        tag: 'offline_work_cover_${widget.workId}',
        child: PrivacyBlurCover(
          borderRadius: BorderRadius.circular(8),
          child: RepaintBoundary(
            child: Image.file(
              File(_coverPath!),
              fit: BoxFit.cover,
              width: double.infinity,
              cacheWidth: cacheWidth,
              cacheHeight: cacheHeight,
              filterQuality: FilterQuality.low,
            ),
          ),
        ),
      );
    }

    if (!_resolved) return _buildPlaceholder(context);

    final host = ref.watch(authProvider.select((s) => s.host));
    if (widget.work != null && host != null && host.isNotEmpty) {
      return Hero(
        tag: 'offline_work_cover_${widget.workId}',
        child: PrivacyBlurCover(
          borderRadius: BorderRadius.circular(8),
          child: RepaintBoundary(
            child: CachedNetworkImage(
              imageUrl: widget.work!.getCoverImageUrl(host),
              cacheKey: 'work_cover_${widget.work!.id}',
              httpHeaders: StorageService.serverCookieHeaders,
              fit: BoxFit.cover,
              memCacheWidth: cacheWidth,
              errorWidget: (_, __, ___) => _buildPlaceholder(context),
            ),
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
