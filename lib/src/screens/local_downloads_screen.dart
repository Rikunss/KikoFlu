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
import '../utils/responsive_grid_helper.dart';
import 'package:flutter_staggered_grid_view/flutter_staggered_grid_view.dart';

import '../providers/auth_provider.dart';
import '../providers/subtitle_library_provider.dart';
import '../utils/metadata_utils.dart';
import '../widgets/custom_file_picker.dart';
import '../widgets/pagination_bar.dart';
import '../widgets/sort_dialog.dart';
import 'offline_work_detail_screen.dart';
import '../widgets/overscroll_next_page_detector.dart';
import '../widgets/privacy_blur_cover.dart';
import '../utils/scroll_optimization.dart';
import 'local_file_browser_screen.dart';

/// Provider that streams the set of workIds currently processing their cover.
final processingCoversProvider = StreamProvider<Set<int>>((ref) {
  return DownloadService.instance.processingCoversStream;
});

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

  // Source filter
  _SourceFilter _sourceFilter = _SourceFilter.all;

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
        availableOptions: const [SortOrder.downloadDate, SortOrder.workId, SortOrder.title],
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

  /// Check if a work group is from local import.
  bool _isImported(List<DownloadTask> tasks) {
    final meta = tasks.first.workMetadata;
    return meta != null && meta['local_import_path'] != null;
  }

  /// Count works by source type.
  (int, int) _countBySource(Map<int, List<DownloadTask>> grouped) {
    int imported = 0, downloaded = 0;
    for (final entry in grouped.entries) {
      if (_isImported(entry.value)) {
        imported++;
      } else {
        downloaded++;
      }
    }
    return (downloaded, imported);
  }

  /// Apply source + search + metadata filter to the grouped tasks.
  Map<int, List<DownloadTask>> _filterTasks(
      Map<int, List<DownloadTask>> groupedTasks) {
    Map<int, List<DownloadTask>> result = groupedTasks;

    // Apply source filter
    if (_sourceFilter != _SourceFilter.all) {
      final targetImported = _sourceFilter == _SourceFilter.imported;
      result = Map.fromEntries(result.entries.where((e) =>
        _isImported(e.value) == targetImported,
      ));
    }

    // Apply metadata filter
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
        case SortOrder.title:
          final aTitle = groupedTasks[a]!.first.workTitle.toLowerCase();
          final bTitle = groupedTasks[b]!.first.workTitle.toLowerCase();
          // Use natural compare for titles with numbers (e.g. "Work 2" vs "Work 10")
          r = _naturalCompare(aTitle, bTitle);
        default:
          r = 0;
      }
      return _sortDirection == SortDirection.asc ? r : -r;
    });
    return ids;
  }

  void _openWorkDetail(int workId, DownloadTask task) async {
    Map<String, dynamic>? metadata = task.workMetadata;
    if (metadata == null) {
      // Try loading from disk — useful before syncWithDiskAfterInit completes
      try {
        metadata = await DownloadService.instance.getWorkMetadata(workId);
      } catch (_) {}
    }
    if (metadata == null) {
      _showSnackBarSafe(SnackBar(
        content: Text(S.of(context).noWorkMetadataForOffline),
        duration: const Duration(seconds: 2),
      ));
      return;
    }
    try {
      final sanitized = sanitizeMetadata(metadata);
      final work = Work.fromJson(sanitized);
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


  /// Natural sort comparator for work titles (e.g. "Work 2" before "Work 10").
  static int _naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+|[^\d]+)');
    final aParts = pattern
        .allMatches(a.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();
    final bParts = pattern
        .allMatches(b.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();

    final len = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < len; i++) {
      final aNum = int.tryParse(aParts[i]);
      final bNum = int.tryParse(bParts[i]);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aParts[i].compareTo(bParts[i]);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
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

    final (downloadedCount, importedCount) =
        _countBySource(allGrouped);
    final allCount = allGrouped.length;

    // Grid layout — responsive masonry, matching main menu's big-grid style
    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;
    final spacing = isLandscape ? 24.0 : 8.0;
    final crossAxisCount =
        ResponsiveGridHelper.getBigGridCrossAxisCountForSize(size, orientation);

    // For empty states, show contextual message based on active filters
    Widget? emptyWidget;
    if (allGrouped.isEmpty) {
      emptyWidget = _emptyState(context,
        S.of(context).noLocalDownloads, Icons.download_outlined);
    } else if (grouped.isEmpty) {
      // Priority: metadata filter → search query → source filter → default
      if (_filterType != _FilterType.all) {
        final filterLabel = switch (_filterType) {
          _FilterType.circle => 'circle',
          _FilterType.va => 'VA',
          _FilterType.tag => 'tag',
          _FilterType.all => '',
        };
        emptyWidget = _emptyState(context,
          'No matching $filterLabel', Icons.filter_alt_off_rounded,
          actionLabel: 'Clear filter',
          onAction: () => setState(() {
            _filterType = _FilterType.all;
            _filterValue = '';
            _currentPage = 1;
          }),
        );
      } else if (_searchQuery.isNotEmpty) {
        emptyWidget = _emptyState(context,
          'No results for "$_searchQuery"', Icons.search_off,
          actionLabel: 'Clear search',
          onAction: () {
            _searchController.clear();
            setState(() {
              _searchQuery = '';
              _currentPage = 1;
            });
          },
        );
      } else if (_sourceFilter == _SourceFilter.imported) {
        emptyWidget = _emptyState(context,
          'No imported works', Icons.folder_open_rounded,
          actionLabel: 'Import now',
          onAction: () => _importSingleFolder());
      } else if (_sourceFilter == _SourceFilter.downloaded) {
        emptyWidget = _emptyState(context,
          'No downloaded works', Icons.cloud_download_rounded);
      } else {
        emptyWidget = _emptyState(context,
          S.of(context).noResults, Icons.search_off);
      }
    }

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
      _buildSourceTabs(downloadedCount: downloadedCount, importedCount: importedCount),
      _buildInfoBar(allCount, downloadedCount, importedCount),
      _buildFilterBar(allGrouped),
      if (_isSearchVisible) _buildSearchBar(),
      Expanded(
        child: emptyWidget ?? AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (child, animation) {
            return ScaleTransition(
              scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                CurvedAnimation(parent: animation, curve: Curves.easeOutCubic),
              ),
              child: FadeTransition(opacity: animation, child: child),
            );
          },
          child: grouped.isEmpty
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
                          padding: EdgeInsets.all(spacing),
                          sliver: SliverMasonryGrid.count(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: spacing,
                            mainAxisSpacing: spacing,
                            childCount: pageMap.length,
                            itemBuilder: (context, index) {
                              final id = pageIds[index];
                              final workTasks = pageMap[id]!;
                              // Compute actual card width from grid dimensions
                              final cardWidth = (size.width -
                                      2 * spacing -
                                      (crossAxisCount - 1) * spacing) /
                                  crossAxisCount;
                              return RepaintBoundary(
                                key: ValueKey('dl_$id'),
                                child: _DownloadWorkCard(
                                workId: id,
                                workTasks: workTasks,
                                firstTask: workTasks.first,
                                cardWidth: cardWidth,
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
                          ),
                        ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(spacing, spacing, spacing, 24),
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
      ),
    ]);
  }

  /// Source tabs — segmented pill control: All | Downloaded | Imported
  Widget _buildSourceTabs({required int downloadedCount, required int importedCount}) {
    final cs = Theme.of(context).colorScheme;
    final s = S.of(context);
    const tabs = _SourceFilter.values;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: List.generate(tabs.length, (i) {
            final filter = tabs[i];
            final isSel = _sourceFilter == filter;

            return Padding(
              padding: EdgeInsets.only(right: i < tabs.length - 1 ? 6 : 0),
              child: GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  setState(() {
                    _sourceFilter = filter;
                    _currentPage = 1;
                    _workCache.clear();
                  });
                },
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: isSel
                        ? cs.primaryContainer
                        : cs.surfaceContainerHighest.withAlpha(150),
                    borderRadius: BorderRadius.circular(12),
                    border: isSel
                        ? Border.all(color: cs.primary.withAlpha(60), width: 1)
                        : null,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _sourceIcon(filter),
                        size: 16,
                        color: isSel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        _sourceLabel(s, filter),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                          color: isSel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Count badge
                      _SourceCountBadge(
                        count: _countForFilter(filter, downloadedCount, importedCount),
                        isSelected: isSel,
                        colorScheme: cs,
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  IconData _sourceIcon(_SourceFilter filter) {
    switch (filter) {
      case _SourceFilter.all:
        return Icons.all_inclusive_rounded;
      case _SourceFilter.downloaded:
        return Icons.cloud_download_rounded;
      case _SourceFilter.imported:
        return Icons.folder_rounded;
    }
  }

  String _sourceLabel(S l10n, _SourceFilter filter) {
    switch (filter) {
      case _SourceFilter.all:
        return 'All';
      case _SourceFilter.downloaded:
        return 'Downloaded';
      case _SourceFilter.imported:
        return 'Imported';
    }
  }

  int _countForFilter(_SourceFilter filter, int downloadedCount, int importedCount) {
    switch (filter) {
      case _SourceFilter.all:
        return downloadedCount + importedCount;
      case _SourceFilter.downloaded:
        return downloadedCount;
      case _SourceFilter.imported:
        return importedCount;
    }
  }

  /// Info bar — summary counts below source tabs.
  Widget _buildInfoBar(int allCount, int downloadedCount, int importedCount) {
    final cs = Theme.of(context).colorScheme;
    if (allCount == 0) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 12,
            color: cs.onSurfaceVariant.withAlpha(100)),
          const SizedBox(width: 6),
          Text(
            '$allCount works',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
              color: cs.onSurfaceVariant),
          ),
          if (downloadedCount > 0) ...[
            const SizedBox(width: 4),
            Text('·', style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(width: 4),
            Icon(Icons.cloud_download_rounded, size: 11,
              color: cs.primary),
            const SizedBox(width: 3),
            Text('$downloadedCount',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                color: cs.primary)),
          ],
          if (importedCount > 0) ...[
            const SizedBox(width: 4),
            Text('·', style: TextStyle(fontSize: 11, color: cs.outline)),
            const SizedBox(width: 4),
            Icon(Icons.folder_rounded, size: 11,
              color: Colors.orange.shade400),
            const SizedBox(width: 3),
            Text('$importedCount',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w500,
                color: Colors.orange.shade400)),
          ],
        ],
      ),
    );
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

  Widget _emptyState(BuildContext context, String message, IconData icon, {
    String? actionLabel,
    VoidCallback? onAction,
  }) {
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
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 20),
              FilledButton.icon(
                onPressed: onAction,
                icon: const Icon(Icons.add, size: 18),
                label: Text(actionLabel),
              ),
            ],
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

/// Source type filter for the downloads screen.
enum _SourceFilter { all, downloaded, imported }

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
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerLeft,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // Select (primary action — keep prominent)
          Padding(
            padding: const EdgeInsets.only(left: 16, right: 4),
            child: FilledButton.tonalIcon(
              icon: const Icon(Icons.checklist, size: 18),
              label: Text(s.select),
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              ),
              onPressed: () {
                HapticFeedback.lightImpact();
                onToggleSelectionMode();
              },
            ),
          ),
          // Reload — icon only
          _CompactIconButton(
            icon: Icons.refresh_rounded,
            tooltip: s.reload,
            onPressed: onRefresh,
          ),
          // Browse Files — icon only
          _CompactIconButton(
            icon: Icons.folder_rounded,
            tooltip: s.browseFiles,
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const LocalFileBrowserScreen(),
                ),
              );
            },
          ),
          // Open Folder — icon only (desktop only)
          if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
            _CompactIconButton(
              icon: Icons.folder_open,
              tooltip: s.openFolder,
              onPressed: onOpenFolder,
            ),
          // Separator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Icon(Icons.more_horiz, size: 16, color: cs.outlineVariant),
          ),
          // Search
          _CompactIconButton(
            icon: isSearchVisible ? Icons.search_off : Icons.search,
            tooltip: s.search,
            onPressed: onToggleSearch,
          ),
          // Sort
          _CompactIconButton(
            icon: Icons.sort,
            tooltip: s.sortOptions,
            onPressed: onShowSort,
          ),
        ]),
      ),
    );
  }
}

/// Compact icon button with consistent sizing.
class _CompactIconButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  const _CompactIconButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 2),
      child: IconButton(
        icon: Icon(icon, size: 20),
        padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        onPressed: () {
          HapticFeedback.lightImpact();
          onPressed();
        },
        tooltip: tooltip,
      ),
    );
  }
}

/// ===================================================================
/// Work card — redesigned to match EnhancedWorkCard medium card style
/// ===================================================================
class _DownloadWorkCard extends StatelessWidget {
  final int workId;
  final List<DownloadTask> workTasks;
  final DownloadTask firstTask;
  final double cardWidth;
  final bool isSelected;
  final bool isSelectionMode;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const _DownloadWorkCard({
    required this.workId,
    required this.workTasks,
    required this.firstTask,
    required this.cardWidth,
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
    final tt = Theme.of(context).textTheme;

    Work? work;
    if (firstTask.workMetadata != null) {
      try {
        final sanitized = sanitizeMetadata(firstTask.workMetadata!);
        work = Work.fromJson(sanitized);
      } catch (e) {
        LogService.instance.warning('[LocalDownloads] Failed to parse work metadata for offline card: $e', tag: 'Download');
      }
    }

    final workTitle = work?.title ?? firstTask.workTitle;
    final isImported = firstTask.workMetadata?['local_import_path'] != null;

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
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cover — AspectRatio 1.3 (matching EnhancedWorkCard medium)
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                children: [
                  _WorkCardCover(workId: workId, work: work, firstTask: firstTask, cardWidth: cardWidth),
                  // RJ tag (top-left) — matches EnhancedWorkCard style
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.7),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        formatRJCode(workId),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  // Source badge (top-right) — only show when NOT in selection mode
                  if (!isSelectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _SourceBadge(isImported: isImported),
                    ),
                  // Selection check (top-right) — overlaps source badge in selection mode
                  if (isSelectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
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
                          color: isSelected ? Colors.white : cs.outline,
                          size: 20,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info area — matching EnhancedWorkCard medium card padding & font sizes
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Title
                  Text(
                    workTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      height: 1.1,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(height: 4),
                  // VA (if available)
                  if (work?.vas != null && work!.vas!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Row(
                        children: [
                          Icon(Icons.mic, size: 12,
                            color: cs.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Expanded(
                            child: Text(
                              work.vas!.first.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: tt.bodySmall?.copyWith(
                                fontSize: 10,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  // File count + size row
                  Row(
                    children: [
                      Icon(Icons.folder_outlined, size: 12,
                        color: cs.primary),
                      const SizedBox(width: 3),
                      Text('${workTasks.length}',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w500,
                          color: cs.primary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(Icons.storage, size: 12,
                        color: cs.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Flexible(
                        child: Text(
                          formatBytes(totalSize),
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
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
    );
  }
}

/// ===================================================================
/// Work card cover — fetches auth only when needed (not per-card)
/// ===================================================================

/// Small count badge shown inside source tab pills.
class _SourceCountBadge extends StatelessWidget {
  final int count;
  final bool isSelected;
  final ColorScheme colorScheme;

  const _SourceCountBadge({
    required this.count,
    required this.isSelected,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: isSelected
            ? colorScheme.primary.withAlpha(30)
            : colorScheme.surfaceContainerHighest.withAlpha(180),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        '$count',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: isSelected
              ? colorScheme.onPrimaryContainer
              : colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// Small badge indicating whether a work was downloaded from server or imported.
class _SourceBadge extends StatelessWidget {
  final bool isImported;

  const _SourceBadge({required this.isImported});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Icon(
        isImported ? Icons.folder_rounded : Icons.cloud_download_rounded,
        size: 14,
        color: isImported ? Colors.orange.shade300 : Colors.white.withAlpha(220),
      ),
    );
  }
}

/// Small subtitle tag overlay shown on the cover when the work has local subtitles.
/// Matches the style of EnhancedWorkCard's subtitle tag.
class _SubtitleTag extends StatelessWidget {
  final bool isLocal;

  const _SubtitleTag({this.isLocal = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLocal
            ? Colors.green.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.closed_caption,
        color: Colors.white,
        size: 14,
      ),
    );
  }
}

class _WorkCardCover extends ConsumerStatefulWidget {
  final int workId;
  final Work? work;
  final DownloadTask firstTask;
  final double cardWidth;

  const _WorkCardCover({
    required this.workId,
    this.work,
    required this.firstTask,
    required this.cardWidth,
  });

  @override
  ConsumerState<_WorkCardCover> createState() => _WorkCardCoverState();
}

class _WorkCardCoverState extends ConsumerState<_WorkCardCover>
    with SingleTickerProviderStateMixin {
  /// Cached local cover file path
  String? _coverPath;

  /// Whether we've finished trying to resolve the local cover
  bool _resolved = false;

  /// Shimmer animation controller — pulses when cover is being processed.
  late final AnimationController _shimmerCtrl;
  late final Animation<double> _shimmerAnim;

  @override
  void initState() {
    super.initState();
    _shimmerCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _shimmerAnim = Tween<double>(begin: 0.3, end: 0.8).animate(
      CurvedAnimation(parent: _shimmerCtrl, curve: Curves.easeInOutSine),
    );
    _resolveCover();
  }

  @override
  void dispose() {
    _shimmerCtrl.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant _WorkCardCover oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-resolve cover when workMetadata changes (e.g. after cover resize)
    if (widget.firstTask.workMetadata != oldWidget.firstTask.workMetadata) {
      _resolved = false;
      _coverPath = null;
      _resolveCover();
    }
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
    // Use actual card width from masonry grid, scaled by aspect ratio 1.3
    final cacheWidth = (widget.cardWidth * dpr).round();
    final cacheHeight = ((widget.cardWidth / 1.3) * dpr).round();

    // Check if this work's cover is being processed
    final processingIds = ref.watch(processingCoversProvider);
    final isProcessing = processingIds.whenOrNull(
      data: (ids) => ids.contains(widget.workId),
    ) ?? false;

    // Start/stop shimmer animation based on processing state
    if (isProcessing && !_shimmerCtrl.isAnimating) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && isProcessing) _shimmerCtrl.repeat(reverse: true);
      });
    } else if (!isProcessing && _shimmerCtrl.isAnimating) {
      _shimmerCtrl.stop();
    }

    Widget coverWidget;

    if (_coverPath != null) {
      coverWidget = Hero(
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
    } else if (isProcessing) {
      // Show shimmer placeholder while cover is being processed
      coverWidget = _buildProcessingPlaceholder(context);
    } else if (!_resolved) {
      coverWidget = _buildPlaceholder(context);
    } else {
      final host = ref.watch(authProvider.select((s) => s.host));
      if (widget.work != null && host != null && host.isNotEmpty) {
        coverWidget = Hero(
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
      } else {
        coverWidget = _buildPlaceholder(context);
      }
    }

    // Wrap in a Stack to overlay the processing indicator
    if (isProcessing) {
      return Stack(
        children: [
          coverWidget,
          // Processing indicator overlay (bottom-right)
          Positioned(
            bottom: 8,
            right: 8,
            child: AnimatedBuilder(
              animation: _shimmerAnim,
              builder: (context, child) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.65),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.5,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            Colors.white.withValues(alpha: _shimmerAnim.value),
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Cover',
                        style: TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.w600,
                          color: Colors.white.withValues(alpha: _shimmerAnim.value),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      );
    }

    // Check if work has local subtitle — use .select() to avoid unnecessary rebuilds
    final work = widget.work;
    final hasLocalSubtitle = ref.watch(
      subtitleLibraryProvider.select((set) =>
          work != null && set.contains(work.id)),
    );

    // Wrap in Stack to add subtitle tag overlay when applicable
    if (hasLocalSubtitle && coverWidget is! Stack) {
      return Stack(
        children: [
          coverWidget,
          // Subtitle tag (bottom-left) — matching EnhancedWorkCard style
          Positioned(
            bottom: 6,
            left: 6,
            child: const _SubtitleTag(isLocal: true),
          ),
        ],
      );
    }

    return coverWidget;
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

  /// Shimmer-style placeholder shown while the cover image is being resized.
  Widget _buildProcessingPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _shimmerAnim,
      builder: (context, child) {
        return Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: Color.lerp(
              cs.surfaceContainerHighest,
              cs.primaryContainer.withValues(alpha: 0.4),
              _shimmerAnim.value,
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.sync_rounded, size: 28,
                color: cs.primary.withValues(alpha: 0.5)),
              const SizedBox(height: 4),
              SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: cs.primary.withValues(alpha: 0.4),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
