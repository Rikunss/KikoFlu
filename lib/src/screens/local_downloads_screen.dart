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
import '../services/cookie_service.dart';
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

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  bool _isSearchVisible = false;

  SortOrder _sortOrder = SortOrder.downloadDate;
  SortDirection _sortDirection = SortDirection.desc;

  _FilterType _filterType = _FilterType.all;
  String _filterValue = '';

  _SourceFilter _sourceFilter = _SourceFilter.all;

  /// Cache parsed Work objects by workId to avoid re-parsing metadata.
  final Map<int, Work> _workCache = {};

  StreamSubscription<List<DownloadTask>>? _tasksSub;
  List<DownloadTask> _allTasks = [];

  @override
  void initState() {
    super.initState();
    _allTasks = DownloadService.instance.tasks;
    _tasksSub = DownloadService.instance.tasksStream.listen((tasks) {
      if (!mounted) return;
      _workCache.clear();
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
    } catch (e) {
      LogService.instance.warning('[_LocalDownloadListState] error: $e', tag: 'LocalDownloads');
    }
  }

  Future<void> _deleteSelectedWorks(
      Map<int, List<DownloadTask>> groupedTasks) async {
    if (_selectedWorkIds.isEmpty) return;
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

    final s = S.of(context);
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

    if (_sourceFilter != _SourceFilter.all) {
      final targetImported = _sourceFilter == _SourceFilter.imported;
      result = Map.fromEntries(result.entries.where((e) =>
        _isImported(e.value) == targetImported,
      ));
    }

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
          r = _naturalCompare(aTitle, bTitle);
        default:
          r = 0;
      }
      return _sortDirection == SortDirection.asc ? r : -r;
    });
    return ids;
  }

  void _openWorkDetail(int workId, DownloadTask task) async {
    final s = S.of(context);
    Map<String, dynamic>? metadata = task.workMetadata;
    if (metadata == null) {
      try {
        metadata = await DownloadService.instance.getWorkMetadata(workId);
      } catch (e) {
        LogService.instance.warning('[_LocalDownloadListState] error: $e', tag: 'LocalDownloads');
      }
    }
    if (metadata == null) {
      _showSnackBarSafe(SnackBar(
        content: Text(s.noWorkMetadataForOffline),
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
    if (!mounted) return;
    final s = S.of(context);

    final parentPath = await CustomFilePicker.pickDirectory(
      context: context,
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

    if (!mounted) return;

    final progressNotifier = ValueNotifier<_ImportProgress>(
      _ImportProgress(completed: 0, total: totalSubfolders, currentFolder: ''),
    );

    final dialogFuture = showDialog<void>(
      context: context,
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
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
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
      if (mounted) {
        Navigator.of(context, rootNavigator: true).pop();
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

    final Map<int, List<DownloadTask>> allGrouped = {};
    for (final task in completed) {
      allGrouped.putIfAbsent(task.workId, () => []).add(task);
    }

    final grouped = _filterTasks(allGrouped);
    final sortedIds = _sortWorkIds(grouped);

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

    final size = MediaQuery.sizeOf(context);
    final orientation = MediaQuery.orientationOf(context);
    final isLandscape = orientation == Orientation.landscape;
    final spacing = isLandscape ? 24.0 : 8.0;
    final crossAxisCount =
        ResponsiveGridHelper.getBigGridCrossAxisCountForSize(size, orientation);

    Widget? emptyWidget;
    if (allGrouped.isEmpty) {
      emptyWidget = _emptyState(context,
        S.of(context).noLocalDownloads, Icons.download_outlined);
    } else if (grouped.isEmpty) {
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
      if (_isSelectionMode)
        _DownloadTopBar(
          selectedCount: _selectedWorkIds.length,
          totalWorkCount: allGrouped.length,
          onToggleSelectionMode: _toggleSelectionMode,
          onSelectAll: () => _selectAll(allGrouped),
          onDeselectAll: _deselectAll,
          onDeleteSelected: () => _deleteSelectedWorks(allGrouped),
        ),
      _buildSourceTabs(downloadedCount: downloadedCount, importedCount: importedCount),
      _buildFilterButton(allGrouped),
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
  /// Action buttons (More, Search, Sort) are trailing, always visible.
  Widget _buildSourceTabs({required int downloadedCount, required int importedCount}) {
    final cs = Theme.of(context).colorScheme;
    const tabs = _SourceFilter.values;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Expanded(
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
                              _sourceLabel(S.of(context), filter),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: isSel ? FontWeight.w600 : FontWeight.w500,
                                color: isSel ? cs.onPrimaryContainer : cs.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(width: 6),
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
          ),
          const SizedBox(width: 4),
          _CompactIconButton(
            icon: Icons.more_vert_rounded,
            tooltip: 'More',
            onPressed: () => _showOverflowMenu(context),
          ),
          const SizedBox(width: 2),
          _CompactIconButton(
            icon: _isSearchVisible ? Icons.search_off : Icons.search,
            tooltip: S.of(context).search,
            onPressed: _toggleSearch,
          ),
          _CompactIconButton(
            icon: Icons.sort,
            tooltip: S.of(context).sortOptions,
            onPressed: _showSortDialog,
          ),
        ],
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

  /// Show overflow menu (Select, Reload, Import, Browse, etc.)
  void _showOverflowMenu(BuildContext context) {
    final s = S.of(context);
    HapticFeedback.lightImpact();
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.checklist),
              title: Text(s.select),
              onTap: () {
                Navigator.pop(ctx);
                _toggleSelectionMode();
              },
            ),
            ListTile(
              leading: const Icon(Icons.refresh_rounded),
              title: Text(s.reload),
              onTap: () {
                Navigator.pop(ctx);
                _refreshMetadata();
              },
            ),
            ListTile(
              leading: const Icon(Icons.create_new_folder_rounded),
              title: Text(s.importSingleFolder),
              subtitle: Text(s.importSingleFolderDesc, style: const TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _importSingleFolder();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_copy_rounded),
              title: Text(s.importMultipleFolders),
              subtitle: Text(s.importMultipleFoldersDesc, style: const TextStyle(fontSize: 11)),
              onTap: () {
                Navigator.pop(ctx);
                _importMultipleFolders();
              },
            ),
            ListTile(
              leading: const Icon(Icons.folder_rounded),
              title: Text(s.browseFiles),
              onTap: () {
                Navigator.pop(ctx);
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const LocalFileBrowserScreen(),
                  ),
                );
              },
            ),
            if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
              ListTile(
                leading: const Icon(Icons.folder_open),
                title: Text(s.openFolder),
                onTap: () {
                  Navigator.pop(ctx);
                  _openDownloadFolder();
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Filter button — opens bottom sheet with Circle / VA / Tag filters.
  Widget _buildFilterButton(Map<int, List<DownloadTask>> grouped) {
    final cs = Theme.of(context).colorScheme;
    final options = _extractFilterOptions(grouped);
    final hasActiveFilter = _filterType != _FilterType.all;

    final hasOptions = options.values.any((list) => list.isNotEmpty);
    if (!hasOptions && !hasActiveFilter) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
        ),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
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
      _buildCategoryFilterButton(Theme.of(context).colorScheme, options, hasActiveFilter),
          ],
        ),
      ),
    );
  }

  /// Category filter button — shows active filter badge, opens bottom sheet.
  Widget _buildCategoryFilterButton(
    ColorScheme cs,
    Map<String, List<String>> options,
    bool hasActiveFilter,
  ) {
    final filterCount = hasActiveFilter ? 1 : 0;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => _showAggregatedFilterSheet(options),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: hasActiveFilter
                ? cs.primaryContainer.withAlpha(100)
                : cs.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(20),
            border: hasActiveFilter
                ? Border.all(color: cs.primary.withAlpha(60))
                : null,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.filter_list_rounded, size: 16,
                color: hasActiveFilter ? cs.onPrimaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 4),
              Text('Category', style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600,
                color: hasActiveFilter ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              )),
              if (hasActiveFilter) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: cs.primary.withAlpha(40),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text('$filterCount', style: TextStyle(
                    fontSize: 10, fontWeight: FontWeight.w700, color: cs.primary)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// Bottom sheet with Circle / VA / Tag filter options.
  void _showAggregatedFilterSheet(Map<String, List<String>> options) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                children: [
                  Text(
                    'Filter by Category',
                    style: Theme.of(ctx).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  TextButton.icon(
                    icon: const Icon(Icons.refresh_rounded, size: 16),
                    label: const Text('Reset'),
                    onPressed: () {
                      setState(() {
                        _filterType = _FilterType.all;
                        _filterValue = '';
                        _currentPage = 1;
                      });
                      Navigator.pop(ctx);
                    },
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            const SizedBox(height: 4),

            if (options['circles']!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Circle', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant, letterSpacing: 0.5,
                )),
              ),
              SizedBox(
                height: (options['circles']!.length * 48 + 8).clamp(48, 240).toDouble(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: options['circles']!.length,
                  itemBuilder: (ctx, i) {
                    final value = options['circles']![i];
                    final isSelected = _filterType == _FilterType.circle && _filterValue == value;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                        size: 20,
                      ),
                      title: Text(value, style: const TextStyle(fontSize: 14)),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _filterType = _FilterType.circle;
                          _filterValue = value;
                          _currentPage = 1;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],

            if (options['vas']!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('VA', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant, letterSpacing: 0.5,
                )),
              ),
              SizedBox(
                height: (options['vas']!.length * 48 + 8).clamp(48, 240).toDouble(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: options['vas']!.length,
                  itemBuilder: (ctx, i) {
                    final value = options['vas']![i];
                    final isSelected = _filterType == _FilterType.va && _filterValue == value;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                        size: 20,
                      ),
                      title: Text(value, style: const TextStyle(fontSize: 14)),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _filterType = _FilterType.va;
                          _filterValue = value;
                          _currentPage = 1;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],

            if (options['tags']!.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Tag', style: TextStyle(
                  fontSize: 12, fontWeight: FontWeight.w700,
                  color: Theme.of(ctx).colorScheme.onSurfaceVariant, letterSpacing: 0.5,
                )),
              ),
              SizedBox(
                height: (options['tags']!.length * 48 + 8).clamp(48, 240).toDouble(),
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  itemCount: options['tags']!.length,
                  itemBuilder: (ctx, i) {
                    final value = options['tags']![i];
                    final isSelected = _filterType == _FilterType.tag && _filterValue == value;
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                        color: isSelected ? Theme.of(ctx).colorScheme.primary : null,
                        size: 20,
                      ),
                      title: Text(value, style: const TextStyle(fontSize: 14)),
                      selected: isSelected,
                      onTap: () {
                        setState(() {
                          _filterType = _FilterType.tag;
                          _filterValue = value;
                          _currentPage = 1;
                        });
                        Navigator.pop(ctx);
                      },
                    );
                  },
                ),
              ),
            ],

            const SizedBox(height: 16),
          ],
        ),
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
  final int selectedCount;
  final int totalWorkCount;
  final VoidCallback onToggleSelectionMode;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onDeleteSelected;

  const _DownloadTopBar({
    required this.selectedCount,
    required this.totalWorkCount,
    required this.onToggleSelectionMode,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onDeleteSelected,
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
      child: Row(children: [
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
      ]),
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
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                children: [
                  _WorkCardCover(workId: workId, work: work, firstTask: firstTask, cardWidth: cardWidth, fileCount: workTasks.length),
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
                  if (!isSelectionMode)
                    Positioned(
                      top: 6,
                      right: 6,
                      child: _SourceBadge(isImported: isImported),
                    ),
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
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
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
  final int fileCount;

  const _WorkCardCover({
    required this.workId,
    this.work,
    required this.firstTask,
    required this.cardWidth,
    this.fileCount = 0,
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
    } catch (e) {
      LogService.instance.warning('[_WorkCardCover] error: $e', tag: 'LocalDownloads');
    }
    if (mounted) setState(() => _resolved = true);
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth = (widget.cardWidth * dpr).round();
    final cacheHeight = ((widget.cardWidth / 1.3) * dpr).round();

    final processingIds = ref.watch(processingCoversProvider);
    final isProcessing = processingIds.whenOrNull(
      data: (ids) => ids.contains(widget.workId),
    ) ?? false;

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
      coverWidget = _buildProcessingPlaceholder(context);
    } else if (!_resolved) {
      coverWidget = _buildPlaceholder(context);
    } else {
      final host = ref.watch(authProvider.select((s) => s.host));
      final token = ref.watch(authProvider.select((s) => s.token ?? ''));
      if (widget.work != null && host != null && host.isNotEmpty) {
        coverWidget = Hero(
          tag: 'offline_work_cover_${widget.workId}',
          child: PrivacyBlurCover(
            borderRadius: BorderRadius.circular(8),
            child: RepaintBoundary(
              child: CachedNetworkImage(
                imageUrl: widget.work!.getCoverImageUrl(host, token: token),
                cacheKey: 'work_cover_${widget.work!.id}',
                httpHeaders: CookieService.coverHttpHeaders(token: token),
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

    if (isProcessing) {
      return Stack(
        children: [
          coverWidget,
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

    final work = widget.work;
    final hasLocalSubtitle = ref.watch(
      subtitleLibraryProvider.select((set) =>
          work != null && set.contains(work.id)),
    );

    if (hasLocalSubtitle && coverWidget is! Stack) {
      return Stack(
        children: [
          coverWidget,
          const Positioned(
            bottom: 6,
            left: 6,
            child: _SubtitleTag(isLocal: true),
          ),
        ],
      );
    }

    return coverWidget;
  }

  Widget _buildPlaceholder(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isImported = widget.firstTask.workMetadata?['local_import_path'] != null;
    final fileCount = widget.fileCount;

    if (isImported) {
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              Colors.orange.shade800.withValues(alpha: 0.6),
              Colors.orange.shade600.withValues(alpha: 0.3),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.folder_rounded, size: 36,
              color: Colors.white.withValues(alpha: 0.8)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$fileCount files',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: Colors.white.withValues(alpha: 0.9),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primary.withValues(alpha: 0.3),
            cs.secondary.withValues(alpha: 0.15),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Icon(Icons.audiotrack_rounded, size: 40,
        color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
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