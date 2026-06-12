import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../models/download_task.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../utils/metadata_utils.dart';
import '../utils/string_utils.dart';

/// Reusable delete confirmation dialog.
Future<bool?> showDeleteConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(S.of(context).cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: FilledButton.styleFrom(backgroundColor: Colors.red),
          child: Text(S.of(context).delete),
        ),
      ],
    ),
  );
}

/// Relative time helper — "2m ago", "1h ago", "2d ago"
String _relativeTime(DateTime dt) {
  final diff = DateTime.now().difference(dt);
  if (diff.inDays > 0) return '${diff.inDays}d ago';
  if (diff.inHours > 0) return '${diff.inHours}h ago';
  if (diff.inMinutes > 0) return '${diff.inMinutes}m ago';
  return 'just now';
}

/// Format icon & color for a file extension
IconData _fileIcon(String fileName) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.opus')) return Icons.music_note;
  if (lower.endsWith('.flac')) return Icons.audiotrack;
  if (lower.endsWith('.mp3')) return Icons.library_music;
  if (lower.endsWith('.wav')) return Icons.graphic_eq;
  if (lower.endsWith('.aac') || lower.endsWith('.m4a')) return Icons.headphones;
  return Icons.insert_drive_file;
}

Color _fileColor(String fileName, ColorScheme cs) {
  final lower = fileName.toLowerCase();
  if (lower.endsWith('.opus')) return const Color(0xFF0891B2);
  if (lower.endsWith('.flac')) return const Color(0xFF7C3AED);
  if (lower.endsWith('.mp3')) return const Color(0xFFD97706);
  if (lower.endsWith('.wav')) return cs.secondary;
  if (lower.endsWith('.aac') || lower.endsWith('.m4a')) return const Color(0xFF0891B2);
  return cs.onSurfaceVariant;
}

/// Progress bar gradient colors per status
List<Color> _progressColors(DownloadStatus status, ColorScheme cs) {
  switch (status) {
    case DownloadStatus.downloading:
      return [cs.primary, Color.lerp(cs.primary, cs.secondary, 0.4)!];
    case DownloadStatus.converting:
      return [Colors.orange, Colors.deepOrange];
    case DownloadStatus.paused:
      return [cs.tertiary, cs.tertiary.withValues(alpha: 0.6)];
    default:
      return [cs.primary.withValues(alpha: 0.3), cs.primary.withValues(alpha: 0.3)];
  }
}

/// ===================================================================
/// Filter options
/// ===================================================================
enum _DownloadFilter { all, active, failed, completed }

/// Source type filter — where the download came from.
enum _SourceFilter { all, downloaded, imported }

/// Metadata filter type for downloads.
enum _FilterType { all, circle, va, tag }

/// Work group — tasks grouped by workId
class _WorkGroup {
  final int workId;
  final List<DownloadTask> tasks;
  const _WorkGroup(this.workId, this.tasks);
}

// ====================================================================
//  MAIN SCREEN
// ====================================================================

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _selectedCount = 0;
  bool _isSelectionMode = false;
  _DownloadFilter _filter = _DownloadFilter.all;
  _SourceFilter _sourceFilter = _SourceFilter.all;
  _FilterType _filterType = _FilterType.all;
  String _filterValue = '';
  final _listKey = GlobalKey<_DownloadTaskListState>();

  void _onSelectionChanged(bool isSelectionMode, int count) {
    setState(() { _isSelectionMode = isSelectionMode; _selectedCount = count; });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: _isSelectionMode
            ? Text(S.of(context).selectedCount(_selectedCount))
            : Text(S.of(context).downloadTasks, style: const TextStyle(fontSize: 18)),
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => _listKey.currentState?.exitSelectionMode(),
              )
            : null,
        actions: _isSelectionMode
            ? [
                IconButton(
                  icon: const Icon(Icons.select_all),
                  onPressed: () => _listKey.currentState?.selectAll(),
                  tooltip: S.of(context).selectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.deselect),
                  onPressed: () => _listKey.currentState?.deselectAll(),
                  tooltip: S.of(context).deselectAll,
                ),
                IconButton(
                  icon: const Icon(Icons.delete),
                  onPressed: _selectedCount == 0
                      ? null
                      : () => _listKey.currentState?.confirmBatchDelete(),
                  tooltip: S.of(context).delete,
                ),
              ]
            : [
                IconButton(
                  icon: const Icon(Icons.checklist),
                  onPressed: () => _listKey.currentState?.enterSelectionMode(),
                  tooltip: S.of(context).select,
                ),
              ],
      ),
      body: _DownloadTaskList(
        key: _listKey,
        filter: _filter,
        sourceFilter: _sourceFilter,
        filterType: _filterType,
        filterValue: _filterValue,
        onFilterChanged: (f) => setState(() => _filter = f),
        onSourceFilterChanged: (f) => setState(() => _sourceFilter = f),
        onFilterTypeChanged: (t, v) => setState(() { _filterType = t; _filterValue = v; }),
        onSelectionChanged: _onSelectionChanged,
      ),
    );
  }
}

/// ===================================================================
/// Download task list
/// ===================================================================
class _DownloadTaskList extends StatefulWidget {
  final _DownloadFilter filter;
  final _SourceFilter sourceFilter;
  final _FilterType filterType;
  final String filterValue;
  final ValueChanged<_DownloadFilter> onFilterChanged;
  final ValueChanged<_SourceFilter> onSourceFilterChanged;
  final void Function(_FilterType type, String value) onFilterTypeChanged;
  final void Function(bool isSelectionMode, int count)? onSelectionChanged;

  const _DownloadTaskList({
    super.key,
    required this.filter,
    required this.sourceFilter,
    required this.filterType,
    required this.filterValue,
    required this.onFilterChanged,
    required this.onSourceFilterChanged,
    required this.onFilterTypeChanged,
    this.onSelectionChanged,
  });

  @override
  State<_DownloadTaskList> createState() => _DownloadTaskListState();
}

class _DownloadTaskListState extends State<_DownloadTaskList> {
  final _listKey = GlobalKey<AnimatedListState>();
  List<_WorkGroup> _groups = [];
  bool _isSelectionMode = false;
  bool _isLoading = true;
  final Set<String> _selectedTaskIds = {};
  final Set<int> _selectedWorkIds = {};
  StreamSubscription<String>? _conversionSub;
  StreamSubscription<List<DownloadTask>>? _tasksSub;

  @override
  void initState() {
    super.initState();
    _groups = _computeGroups(DownloadService.instance.tasks);
    _tasksSub = DownloadService.instance.tasksStream.listen(_onTasksChanged);
    _conversionSub = DownloadService.instance.conversionStream.listen((event) {
      if (!mounted) return;
      final parts = event.split(':');
      final type = parts.isNotEmpty ? parts[0] : event;
      final s = S.of(context);

      switch (type) {
        case 'start':
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const SizedBox(
                    width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Text(s.convertingAudio)),
                ],
              ),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          break;
        case 'success':
          final formatName = parts.length > 2 ? parts[1] : 'FLAC';
          final fileName = parts.sublist(2).join(':');
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle_outline, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${fileName.split('/').last} → $formatName ✓')),
                ],
              ),
              backgroundColor: Colors.green.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 3),
            ),
          );
          break;
        case 'fail':
          final fileName = parts.sublist(1).join(':');
          ScaffoldMessenger.of(context).clearSnackBars();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 20),
                  const SizedBox(width: 12),
                  Expanded(child: Text('${fileName.split('/').last} — Conversion failed')),
                ],
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 4),
            ),
          );
          break;
      }
    });
  }

  @override
  void dispose() {
    _conversionSub?.cancel();
    _tasksSub?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(_DownloadTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.filter != widget.filter ||
        oldWidget.sourceFilter != widget.sourceFilter ||
        oldWidget.filterType != widget.filterType ||
        oldWidget.filterValue != widget.filterValue) {
      _workCache.clear();
      _onTasksChanged(DownloadService.instance.tasks);
    }
  }

  void enterSelectionMode() {
    setState(() { _isSelectionMode = true; });
    widget.onSelectionChanged?.call(true, 0);
  }

  void exitSelectionMode() {
    setState(() {
      _isSelectionMode = false;
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
    });
    widget.onSelectionChanged?.call(false, 0);
  }

  void selectAll() {
    final tasks = _filteredTasks(DownloadService.instance.tasks);
    setState(() {
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
      for (final task in tasks) { _selectedTaskIds.add(task.id); }
      for (final entry in _groupByWork(tasks).entries) { _selectedWorkIds.add(entry.key); }
    });
    widget.onSelectionChanged?.call(true, _selectedTaskIds.length);
  }

  void deselectAll() {
    setState(() { _selectedTaskIds.clear(); _selectedWorkIds.clear(); });
    widget.onSelectionChanged?.call(true, 0);
  }

  void toggleTaskSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) { _selectedTaskIds.remove(taskId); }
      else { _selectedTaskIds.add(taskId); }
    });
    widget.onSelectionChanged?.call(true, _selectedTaskIds.length);
  }

  void toggleWorkSelection(int workId, List<DownloadTask> workTasks) {
    setState(() {
      if (_selectedWorkIds.contains(workId)) {
        _selectedWorkIds.remove(workId);
        for (final t in workTasks) {
          _selectedTaskIds.remove(t.id);
        }
      } else {
        _selectedWorkIds.add(workId);
        for (final t in workTasks) {
          _selectedTaskIds.add(t.id);
        }
      }
    });
    widget.onSelectionChanged?.call(true, _selectedTaskIds.length);
  }

  Future<void> confirmDelete(DownloadTask task) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: S.of(context).deletionConfirmTitle,
      message: S.of(context).deleteFileConfirm(task.fileName),
    );
    if (confirmed == true) {
      await DownloadService.instance.deleteTask(task.id);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).deleted)));
    }
  }

  /// Delete immediately without confirmation dialog (for swipe-to-delete).
  void swipeDelete(DownloadTask task) async {
    await DownloadService.instance.deleteTask(task.id);
    if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).deleted)));
  }

  Future<void> confirmBatchDelete() async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: S.of(context).deletionConfirmTitle,
      message: S.of(context).deleteSelectedFilesConfirm(_selectedTaskIds.length),
    );
    if (confirmed == true) {
      final ids = List<String>.from(_selectedTaskIds);
      for (final id in ids) {
        await DownloadService.instance.deleteTask(id);
      }
      setState(() { _isSelectionMode = false; _selectedTaskIds.clear(); _selectedWorkIds.clear(); });
      widget.onSelectionChanged?.call(false, 0);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.of(context).deletedNFiles(ids.length))));
    }
  }

  /// Check if a task's work is from local import.
  bool _isImported(DownloadTask task) {
    return task.workMetadata?['local_import_path'] != null;
  }

  // ── Helpers ──

  List<DownloadTask> _filteredTasks(List<DownloadTask> all) {
    // First apply status filter
    List<DownloadTask> byStatus;
    switch (widget.filter) {
      case _DownloadFilter.active:
        byStatus = all.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.converting || t.status == DownloadStatus.paused || t.status == DownloadStatus.pending).toList();
      case _DownloadFilter.failed:
        byStatus = all.where((t) => t.status == DownloadStatus.failed).toList();
      case _DownloadFilter.completed:
        byStatus = all.where((t) => t.status == DownloadStatus.completed).toList();
      case _DownloadFilter.all:
        byStatus = all;
    }

    // Then apply source filter
    if (widget.sourceFilter != _SourceFilter.all) {
      final targetImported = widget.sourceFilter == _SourceFilter.imported;
      byStatus = byStatus.where((t) => _isImported(t) == targetImported).toList();
    }

    return byStatus;
  }

  Map<int, List<DownloadTask>> _groupByWork(List<DownloadTask> tasks) {
    final map = <int, List<DownloadTask>>{};
    for (final t in tasks) {
      map.putIfAbsent(t.workId, () => []).add(t);
    }
    return map;
  }

  /// Lazily parse and cache a [Work] from the first task's metadata.
  final Map<int, Work> _workCache = {};

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

  /// Extract unique circles, VAs, and tags from work groups.
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

  /// Apply metadata filter (circle/VA/tag) to already-grouped works.
  List<_WorkGroup> _applyMetadataFilter(List<_WorkGroup> groups) {
    if (widget.filterType == _FilterType.all || widget.filterValue.isEmpty) {
      return groups;
    }
    return groups.where((g) {
      final work = _getWork(g.workId, g.tasks);
      if (work == null) return false;
      switch (widget.filterType) {
        case _FilterType.all:
          return true;
        case _FilterType.circle:
          return work.name == widget.filterValue;
        case _FilterType.va:
          return work.vas?.any((va) => va.name == widget.filterValue) ?? false;
        case _FilterType.tag:
          return work.tags?.any((tag) => tag.name == widget.filterValue) ?? false;
      }
    }).toList();
  }

  // ── AnimatedList diff helpers ──

  List<_WorkGroup> _computeGroups(List<DownloadTask> allTasks) {
    final filtered = _filteredTasks(allTasks);
    final groups = _groupByWork(filtered)
        .entries
        .map((e) => _WorkGroup(e.key, e.value))
        .toList();
    return _applyMetadataFilter(groups);
  }

  void _onTasksChanged(List<DownloadTask> tasks) {
    _isLoading = false;
    final newGroups = _computeGroups(tasks);
    _syncGroups(newGroups);
  }

  void _syncGroups(List<_WorkGroup> newGroups) {
    final listState = _listKey.currentState;
    if (listState == null) {
      _groups = newGroups;
      if (mounted) setState(() {});
      return;
    }

    final oldIds = _groups.map((g) => g.workId).toSet();
    final newIds = newGroups.map((g) => g.workId).toSet();

    // Remove groups that are no longer in the filtered list
    for (int i = _groups.length - 1; i >= 0; i--) {          if (!newIds.contains(_groups[i].workId)) {
        final removed = _groups[i];
        _groups.removeAt(i);
        listState.removeItem(
          i,
          (context, animation) => _AnimatedRemoveWrapper(
            animation: animation,
            child: _buildWorkGroupCard(removed),
          ),
          duration: const Duration(milliseconds: 350),
        );
      }
    }

    // Insert new groups in the correct positions
    for (int i = 0; i < newGroups.length; i++) {
      if (!oldIds.contains(newGroups[i].workId)) {
        _groups.insert(i, newGroups[i]);
        listState.insertItem(i, duration: const Duration(milliseconds: 350));
      }
    }

    // 🔥 CRITICAL FIX: Update task data for existing groups (progress/status changes)
    // Without this, progress updates from downloads and conversions are never
    // reflected in the UI until the user navigates away and back.
    for (int i = 0; i < _groups.length; i++) {
      final match = newGroups.where((g) => g.workId == _groups[i].workId);
      if (match.isNotEmpty) {
        _groups[i] = match.first;
      }
    }

    // Ensure the list is fully rebuilt with latest data
    setState(() {});
  }

  Widget _buildWorkGroupCard(_WorkGroup group) {
    final firstTask = group.tasks.first;
    final isWorkSelected = _selectedWorkIds.contains(group.workId);
    final isImported = _isImported(firstTask);
    return _WorkCard(
      workTitle: firstTask.workTitle,
      fileCount: group.tasks.length,
      isSelectionMode: _isSelectionMode,
      isWorkSelected: isWorkSelected,
      isImported: isImported,
      onToggleWork: () => toggleWorkSelection(group.workId, group.tasks),
      tasks: group.tasks,
      selectedTaskIds: _selectedTaskIds,
      onToggleTask: toggleTaskSelection,
      onDeleteTask: confirmDelete,
      onSwipeDeleteTask: swipeDelete,
    );
  }

  /// Filter bar — chips for Circle / VA / Tag filtering.
  Widget _buildFilterBar(Map<int, List<DownloadTask>> grouped) {
    final cs = Theme.of(context).colorScheme;
    final options = _extractFilterOptions(grouped);
    final hasActiveFilter = widget.filterType != _FilterType.all;

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
            _buildFilterChip(
              label: 'All',
              icon: Icons.filter_alt_off_rounded,
              isSelected: !hasActiveFilter,
              onTap: () => widget.onFilterTypeChanged(_FilterType.all, ''),
              cs: cs,
            ),
            const SizedBox(width: 6),

            // Circle filter chip
            if (options['circles']!.isNotEmpty)
              _buildFilterDropdownChip(
                label: 'Circle',
                icon: Icons.business_rounded,
                type: _FilterType.circle,
                options: options['circles']!,
                cs: cs,
              ),

            // VA filter chip
            if (options['vas']!.isNotEmpty)
              _buildFilterDropdownChip(
                label: 'VA',
                icon: Icons.mic_rounded,
                type: _FilterType.va,
                options: options['vas']!,
                cs: cs,
              ),

            // Tag filter chip
            if (options['tags']!.isNotEmpty)
              _buildFilterDropdownChip(
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
                  widget.filterValue,
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

  /// Simple filter chip (for "All").
  Widget _buildFilterChip({
    required String label,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme cs,
  }) {
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

  /// Dropdown filter chip (Circle / VA / Tag) — opens bottom sheet on tap.
  Widget _buildFilterDropdownChip({
    required String label,
    required IconData icon,
    required _FilterType type,
    required List<String> options,
    required ColorScheme cs,
  }) {
    final isActive = widget.filterType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: ActionChip(
        avatar: Icon(icon, size: 14,
          color: isActive ? cs.onPrimaryContainer : cs.onSurfaceVariant),
        label: Text(
          isActive ? widget.filterValue : label,
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
            SizedBox(
              height: (options.length * 52 + 16).clamp(100, 360).toDouble(),
              child: ListView.builder(
                itemCount: options.length,
                itemBuilder: (ctx, i) {
                  final value = options[i];
                  final isSelected = widget.filterType == type && widget.filterValue == value;
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
                      widget.onFilterTypeChanged(type, value);
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

  /// Build source filter tabs — similar to local_downloads_screen.
  Widget _buildSourceTabs({
    required ColorScheme cs,
    required int importedCount,
    required int downloadedCount,
  }) {
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
            _SourceTabChip(
              icon: Icons.all_inclusive_rounded,
              label: 'All',
              count: downloadedCount + importedCount,
              isSelected: widget.sourceFilter == _SourceFilter.all,
              onTap: () => widget.onSourceFilterChanged(_SourceFilter.all),
              cs: cs,
            ),
            const SizedBox(width: 6),
            _SourceTabChip(
              icon: Icons.cloud_download_rounded,
              label: 'Downloaded',
              count: downloadedCount,
              isSelected: widget.sourceFilter == _SourceFilter.downloaded,
              onTap: () => widget.onSourceFilterChanged(_SourceFilter.downloaded),
              cs: cs,
            ),
            const SizedBox(width: 6),
            _SourceTabChip(
              icon: Icons.folder_rounded,
              label: 'Imported',
              count: importedCount,
              isSelected: widget.sourceFilter == _SourceFilter.imported,
              onTap: () => widget.onSourceFilterChanged(_SourceFilter.imported),
              cs: cs,
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final allTasks = DownloadService.instance.tasks;

    // Compute stats
    final totalCount = allTasks.length;
    final doneCount = allTasks.where((t) => t.status == DownloadStatus.completed).length;
    final activeCount = allTasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.converting || t.status == DownloadStatus.pending).length;
    final failedCount = allTasks.where((t) => t.status == DownloadStatus.failed).length;

    // Source counts
    final importedCount = allTasks.where((t) => _isImported(t)).length;
    final downloadedCount = allTasks.length - importedCount;

    return Column(
      children: [
        // ── Summary Stats Card ──
        _SummaryStats(
          activeCount: activeCount,
          doneCount: doneCount,
          failedCount: failedCount,
          totalCount: totalCount,
        ),

        // ── Filter Chips ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(label: 'All ($totalCount)', selected: widget.filter == _DownloadFilter.all, onTap: () => widget.onFilterChanged(_DownloadFilter.all)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Active ($activeCount)', selected: widget.filter == _DownloadFilter.active, color: cs.primary, onTap: () => widget.onFilterChanged(_DownloadFilter.active)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Failed ($failedCount)', selected: widget.filter == _DownloadFilter.failed, color: Colors.red, onTap: () => widget.onFilterChanged(_DownloadFilter.failed)),
                const SizedBox(width: 8),
                _FilterChip(label: 'Done ($doneCount)', selected: widget.filter == _DownloadFilter.completed, color: Colors.green, onTap: () => widget.onFilterChanged(_DownloadFilter.completed)),
              ],
            ),
          ),
        ),

        // ── Source Tabs ──
        _buildSourceTabs(cs: cs, importedCount: importedCount, downloadedCount: downloadedCount),

        // ── Filter Bar (Circle / VA / Tag) ──
        _buildFilterBar(Map<int, List<DownloadTask>>.fromEntries(
          _groups.map((g) => MapEntry(g.workId, g.tasks)),
        )),

        // ── Animated Task List ──
        Expanded(
          child: _isLoading && allTasks.isEmpty
              ? _ShimmerSkeleton()
              : _groups.isEmpty
                  ? AnimatedSwitcher(
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
                      child: _buildEmptyState(cs, context),
                    )
                  : AnimatedList(
                  key: _listKey,
                  initialItemCount: _groups.length,
                  padding: const EdgeInsets.only(bottom: 24),
                  itemBuilder: (context, index, animation) {
                    if (index >= _groups.length) return const SizedBox.shrink();
                    return _AnimatedInsertWrapper(
                      animation: animation,
                      child: _buildWorkGroupCard(_groups[index]),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(ColorScheme cs, BuildContext context) {
    // Build contextual empty state based on active filters
    final hasMetaFilter = widget.filterType != _FilterType.all;
    final hasSourceFilter = widget.sourceFilter != _SourceFilter.all;
    final hasStatusFilter = widget.filter != _DownloadFilter.all;

    String title;
    IconData icon;
    Color iconColor;
    String? message;

    // Priority: metadata filter → source filter → status filter → default
    if (hasMetaFilter) {
      final filterLabel = switch (widget.filterType) {
        _FilterType.circle => 'circle',
        _FilterType.va => 'VA',
        _FilterType.tag => 'tag',
        _FilterType.all => '',
      };
      title = 'No matching $filterLabel';
      icon = Icons.filter_alt_off_rounded;
      iconColor = cs.primary;
      message = widget.filterValue;
    } else if (hasSourceFilter) {
      switch (widget.sourceFilter) {
        case _SourceFilter.imported:
          title = 'No imported works';
          icon = Icons.folder_open_rounded;
          iconColor = Colors.orange;
          break;
        case _SourceFilter.downloaded:
          title = 'No downloaded works';
          icon = Icons.cloud_off_rounded;
          iconColor = cs.primary;
          break;
        case _SourceFilter.all:
          title = 'No downloads yet';
          icon = Icons.download_for_offline_outlined;
          iconColor = cs.primary.withValues(alpha: 0.4);
      }
    } else if (hasStatusFilter) {
      switch (widget.filter) {
        case _DownloadFilter.failed:
          title = 'No failed downloads';
          icon = Icons.check_circle_outline;
          iconColor = cs.primary.withValues(alpha: 0.4);
          break;
        case _DownloadFilter.completed:
          title = 'No completed downloads';
          icon = Icons.download_for_offline_outlined;
          iconColor = cs.primary.withValues(alpha: 0.4);
          break;
        case _DownloadFilter.active:
          title = 'All downloads are complete';
          icon = Icons.check_circle_outline;
          iconColor = cs.primary.withValues(alpha: 0.4);
          message = 'Browse and download your favorite works.';
          break;
        case _DownloadFilter.all:
          title = 'No downloads yet';
          icon = Icons.download_for_offline_outlined;
          iconColor = cs.primary.withValues(alpha: 0.4);
      }
    } else {
      title = 'No downloads yet';
      icon = Icons.download_for_offline_outlined;
      iconColor = cs.primary.withValues(alpha: 0.4);
      message = 'Start browsing and download\nyour favorite audio works.';
    }

    // Compute a unique key so AnimatedSwitcher detects changes
    final emptyKey = ValueKey('dl_${widget.filter.name}_${widget.sourceFilter.name}_${widget.filterType.name}_${widget.filterValue}_${message ?? ''}');

    return Center(
      key: emptyKey,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 40, color: iconColor),
            ),
            const SizedBox(height: 24),
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            if (message != null && message.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: cs.onSurfaceVariant.withValues(alpha: 0.7),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// Animated wrapper for items entering the list (SizeTransition + FadeTransition)
/// ===================================================================
class _AnimatedInsertWrapper extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AnimatedInsertWrapper({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizeTransition(        sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      ),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeOut,
        ),
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, -0.1),
            end: Offset.zero,
          ).animate(CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          )),
          child: child,
        ),
      ),
    );
  }
}

/// ===================================================================
/// Animated wrapper for items leaving the list (shrink + fade out)
/// ===================================================================
class _AnimatedRemoveWrapper extends StatelessWidget {
  final Animation<double> animation;
  final Widget child;

  const _AnimatedRemoveWrapper({
    required this.animation,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizeTransition(
      sizeFactor: CurvedAnimation(
        parent: animation,
        curve: Curves.easeInCubic,
      ),
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: Curves.easeIn,
        ),
        child: child,
      ),
    );
  }
}

/// ===================================================================
/// Shimmer skeleton — animated placeholder while data loads
/// ===================================================================
class _ShimmerSkeleton extends StatefulWidget {
  @override
  State<_ShimmerSkeleton> createState() => _ShimmerSkeletonState();
}

class _ShimmerSkeletonState extends State<_ShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final baseColor = cs.surfaceContainerHighest.withValues(alpha: 0.6);
    final shimmerHighlight = Colors.white.withValues(alpha: 0.12);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final offset = _controller.value;
        return Stack(
          children: [
            // Skeleton content
            child!,
            // Shimmer sweep overlay
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        Colors.transparent,
                        Colors.transparent,
                        shimmerHighlight,
                        Colors.transparent,
                        Colors.transparent,
                      ],
                      stops: [0.0, (offset - 0.15).clamp(0.0, 1.0), offset.clamp(0.0, 1.0), (offset + 0.15).clamp(0.0, 1.0), 1.0],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _ShimmerCard(baseColor: baseColor, cs: cs, showTasks: true),
          const SizedBox(height: 10),
          _ShimmerCard(baseColor: baseColor, cs: cs, showTasks: false),
          const SizedBox(height: 10),
          _ShimmerCard(baseColor: baseColor, cs: cs, showTasks: true),
        ],
      ),
    );
  }
}

/// Single skeleton card placeholder used by _ShimmerSkeleton
class _ShimmerCard extends StatelessWidget {
  final Color baseColor;
  final ColorScheme cs;
  final bool showTasks;

  const _ShimmerCard({
    required this.baseColor,
    required this.cs,
    required this.showTasks,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row: icon + title
            Row(
              children: [
                Container(
                  width: 24, height: 24,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 14,
                    decoration: BoxDecoration(
                      color: baseColor,
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Subtitle chips row
            Row(
              children: [
                _chip(baseColor: baseColor, width: 56),
                const SizedBox(width: 6),
                if (showTasks) _chip(baseColor: baseColor, width: 48),
                const SizedBox(width: 6),
                _chip(baseColor: baseColor, width: 64),
              ],
            ),

            // Task tile placeholders
            if (showTasks) ...[
            buildTaskSkeleton(),
            const SizedBox(height: 2),
            buildTaskSkeleton(),
          ],
          if (!showTasks) buildTaskSkeleton(),
          ],
        ),
      ),
    );
  }

  Widget _chip({required Color baseColor, required double width}) {
    return Container(
      width: width,
      height: 14,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(7),
      ),
    );
  }

  Widget buildTaskSkeleton() {
    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Row(
        children: [
          // File icon placeholder
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: baseColor,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          const SizedBox(width: 10),
          // Text lines
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 12,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      height: 10,
                      width: 80,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      height: 10,
                      width: 50,
                      decoration: BoxDecoration(
                        color: baseColor,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  height: 4,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: baseColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// ===================================================================
/// Summary Stats Card
/// ===================================================================
class _SummaryStats extends StatelessWidget {
  final int activeCount, doneCount, failedCount, totalCount;

  const _SummaryStats({required this.activeCount, required this.doneCount, required this.failedCount, required this.totalCount});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (totalCount == 0) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Card(
        margin: EdgeInsets.zero,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              _StatItem(icon: Icons.downloading, value: '$activeCount', label: 'Active', color: cs.primary),
              _StatItem(icon: Icons.check_circle, value: '$doneCount', label: 'Done', color: Colors.green),
              _StatItem(icon: Icons.error_outline, value: '$failedCount', label: 'Failed', color: Colors.red),
              _StatItem(icon: Icons.inbox, value: '$totalCount', label: 'Total', color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatItem extends StatelessWidget {
  final IconData icon;
  final String value, label;
  final Color color;

  const _StatItem({required this.icon, required this.value, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(height: 2),
          Text(value, style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16, color: color)),
          Text(label, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// ===================================================================
/// Source Tab Chip
/// ===================================================================
class _SourceTabChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _SourceTabChip({
    required this.icon,
    required this.label,
    required this.count,
    required this.isSelected,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        decoration: BoxDecoration(
          color: isSelected
              ? cs.primaryContainer
              : cs.surfaceContainerHighest.withAlpha(150),
          borderRadius: BorderRadius.circular(12),
          border: isSelected
              ? Border.all(color: cs.primary.withAlpha(60), width: 1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                color: isSelected ? cs.onPrimaryContainer : cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(width: 6),
            // Count badge
            if (count > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? cs.primary.withAlpha(30)
                      : cs.surfaceContainerHighest.withAlpha(180),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSelected
                        ? cs.onPrimaryContainer
                        : cs.onSurfaceVariant,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// Filter Chip
/// ===================================================================
class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? color;
  final VoidCallback onTap;

  const _FilterChip({required this.label, required this.selected, this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final bg = selected ? (color ?? cs.primary).withValues(alpha: 0.15) : cs.surfaceContainerHighest.withValues(alpha: 0.5);
    final fg = selected ? (color ?? cs.primary) : cs.onSurfaceVariant;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(20),
            border: selected ? Border.all(color: (color ?? cs.primary).withValues(alpha: 0.3)) : null,
          ),
          child: Text(label, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: fg)),
        ),
      ),
    );
  }
}

/// ===================================================================
/// Work Card — grouped by work, shows ExpansionTile + children
/// ===================================================================
class _WorkCard extends StatelessWidget {
  final String workTitle;
  final int fileCount;
  final bool isSelectionMode;
  final bool isWorkSelected;
  final bool isImported;
  final VoidCallback onToggleWork;
  final List<DownloadTask> tasks;
  final Set<String> selectedTaskIds;
  final void Function(String) onToggleTask;
  final void Function(DownloadTask) onDeleteTask;
  final void Function(DownloadTask) onSwipeDeleteTask;

  const _WorkCard({
    required this.workTitle,
    required this.fileCount,
    required this.isSelectionMode,
    required this.isWorkSelected,
    required this.isImported,
    required this.onToggleWork,
    required this.tasks,
    required this.selectedTaskIds,
    required this.onToggleTask,
    required this.onDeleteTask,
    required this.onSwipeDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    // Compute overall progress
    final totalProgress = tasks.fold(0.0, (sum, t) => sum + t.progress) / tasks.length;
    final activeCount = tasks.where((t) => t.status == DownloadStatus.downloading || t.status == DownloadStatus.converting).length;
    final failedCount = tasks.where((t) => t.status == DownloadStatus.failed).length;
    final doneCount = tasks.where((t) => t.status == DownloadStatus.completed).length;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
      child: Card(
        margin: EdgeInsets.zero,
        clipBehavior: Clip.antiAlias,
        child: ExpansionTile(
          initiallyExpanded: activeCount > 0,
          leading: isSelectionMode
              ? Checkbox(value: isWorkSelected, onChanged: (_) => onToggleWork())
              : Icon(
                  isImported ? Icons.folder_rounded : Icons.cloud_download_rounded,
                  color: isImported ? Colors.orange.shade400 : cs.primary,
                ),
          title: Text(
            workTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 2),
              Row(
                children: [
                  // Source badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: isImported
                          ? Colors.orange.withValues(alpha: 0.15)
                          : cs.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isImported ? Icons.folder_rounded : Icons.cloud_download_rounded,
                          size: 10,
                          color: isImported ? Colors.orange.shade400 : cs.primary,
                        ),
                        const SizedBox(width: 3),
                        Text(
                          isImported ? 'Imported' : 'Downloaded',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w600,
                            color: isImported ? Colors.orange.shade600 : cs.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                  if (activeCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: cs.primary.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('$activeCount active', style: TextStyle(fontSize: 10, color: cs.primary, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (failedCount > 0) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                      decoration: BoxDecoration(color: Colors.red.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                      child: Text('$failedCount failed', style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text('$doneCount done', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 8),
                  Text('$fileCount files', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                ],
              ),
              if (totalProgress < 1.0 && totalProgress > 0) ...[
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: totalProgress.clamp(0.0, 1.0),
                    minHeight: 4,
                    backgroundColor: cs.surfaceContainerHighest,
                    valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                  ),
                ),
              ],
            ],
          ),
          trailing: isSelectionMode ? null : Icon(Icons.expand_more, color: cs.onSurfaceVariant),
          children: [
            for (final task in tasks)
              Dismissible(
                key: ValueKey(task.id),
                direction: DismissDirection.endToStart,
                dismissThresholds: const {DismissDirection.endToStart: 0.35},
                confirmDismiss: (_) async {
                  if (isSelectionMode) return false;
                  return showDeleteConfirmDialog(
                    context,
                    title: S.of(context).deletionConfirmTitle,
                    message: S.of(context).deleteFileConfirm(task.fileName),
                  );
                },
                onDismissed: (_) => onSwipeDeleteTask(task),
                background: Container(
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.shade500,
                    borderRadius: const BorderRadius.only(
                      topRight: Radius.circular(12),
                      bottomRight: Radius.circular(12),
                    ),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.delete_outline, color: Colors.white, size: 20),
                      SizedBox(width: 6),
                      Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13)),
                    ],
                  ),
                ),
                child: _TaskTile(
                  task: task,
                  isSelectionMode: isSelectionMode,
                  isSelected: selectedTaskIds.contains(task.id),
                  onToggle: () => onToggleTask(task.id),
                  onDelete: () => onDeleteTask(task),
                ),
              ),
            const SizedBox(height: 4),
          ],
        ),
      ),
    );
  }
}

/// ===================================================================
/// Task tile — individual download item
/// ===================================================================
class _TaskTile extends StatelessWidget {
  final DownloadTask task;
  final bool isSelectionMode;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onDelete;

  const _TaskTile({
    required this.task,
    required this.isSelectionMode,
    required this.isSelected,
    required this.onToggle,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    if (isSelectionMode) {
      return ListTile(
        leading: Checkbox(value: isSelected, onChanged: (_) => onToggle()),
        title: Text(task.fileName.split('/').last, maxLines: 1, overflow: TextOverflow.ellipsis),
        onTap: onToggle,
      );
    }

    final isConverting = task.status == DownloadStatus.converting;
    final isDownloading = task.status == DownloadStatus.downloading;
    final isFailed = task.status == DownloadStatus.failed;
    final isPaused = task.status == DownloadStatus.paused;
    final isPending = task.status == DownloadStatus.pending;
    final isCompleted = task.status == DownloadStatus.completed;

    final ext = task.fileName.split('.').last.toUpperCase();
    final icon = _fileIcon(task.fileName);
    final iconColor = _fileColor(task.fileName, cs);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Container(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: cs.surfaceContainerHighest.withValues(alpha: 0.5), width: 0.5)),
        ),
        child: InkWell(
          onTap: isPending || isFailed || isPaused ? () => DownloadService.instance.resumeTask(task.id) : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // File type icon container
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: iconColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(child: Icon(icon, size: 18, color: iconColor)),
                ),
                const SizedBox(width: 10),

                // Middle content
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Filename row
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.fileName.split('/').last,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: isFailed ? FontWeight.w600 : FontWeight.w500,
                                color: isFailed ? Colors.red : (isCompleted ? cs.onSurface.withValues(alpha: 0.8) : cs.onSurface),
                              ),
                            ),
                          ),
                          // Format badge
                          if (ext.isNotEmpty && !isPending)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: iconColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                ext,
                                style: TextStyle(fontSize: 9, fontWeight: FontWeight.w700, color: iconColor, letterSpacing: 0.5),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 4),

                      // Status row
                      if (isCompleted) ...[
                        Row(
                          children: [
                            const Icon(Icons.check_circle, size: 12, color: Colors.green),
                            const SizedBox(width: 4),
                            Text('Completed', style: TextStyle(fontSize: 11, color: Colors.green.shade700)),
                            if (task.completedAt != null) ...[
                              const SizedBox(width: 8),
                              Text(_relativeTime(task.completedAt!), style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant.withValues(alpha: 0.6))),
                            ],
                          ],
                        ),
                      ] else if (isFailed) ...[
                        Row(
                          children: [
                            const Icon(Icons.error_outline, size: 12, color: Colors.red),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                task.error ?? 'Download failed',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.red),
                              ),
                            ),
                          ],
                        ),
                      ] else if (isPaused) ...[
                        Row(
                          children: [
                            const Icon(Icons.pause_circle, size: 12, color: Colors.orange),
                            const SizedBox(width: 4),
                            Text('Paused', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                          ],
                        ),
                      ] else if (isPending) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary.withValues(alpha: 0.5)),
                            ),
                            const SizedBox(width: 4),
                            Text('Waiting...', style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ] else if (isConverting) ...[
                        Row(
                          children: [
                            const SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.orange),
                            ),
                            const SizedBox(width: 4),
                            Text('Converting...', style: TextStyle(fontSize: 11, color: Colors.orange.shade700)),
                            if (task.eta != null) ...[
                              const SizedBox(width: 6),
                              Text('ETA ${task.eta}', style: TextStyle(fontSize: 10, color: Colors.orange.shade400)),
                            ],
                          ],
                        ),
                      ] else if (isDownloading) ...[
                        Row(
                          children: [
                            SizedBox(
                              width: 12, height: 12,
                              child: CircularProgressIndicator(strokeWidth: 1.5, color: cs.primary),
                            ),
                            const SizedBox(width: 4),
                            Text(
                              task.totalBytes != null && task.totalBytes! > 0
                                  ? '${formatBytes(task.downloadedBytes)} / ${formatBytes(task.totalBytes!)}'
                                  : 'Downloading...',
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                            ),
                          ],
                        ),
                      ],

                      // Progress bar
                      if ((isDownloading || isConverting || isPaused) && task.progress > 0)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: SizedBox(
                                    height: 6,
                                    child: Stack(
                                      children: [
                                        Container(
                                          height: 6,
                                          decoration: BoxDecoration(
                                            color: cs.surfaceContainerHighest,
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                        FractionallySizedBox(
                                          widthFactor: task.progress.clamp(0.0, 1.0),
                                          child: Container(
                                            height: 6,
                                            decoration: BoxDecoration(
                                              borderRadius: BorderRadius.circular(4),
                                              gradient: LinearGradient(
                                                colors: _progressColors(task.status, cs),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (isConverting ? Colors.orange : cs.primary).withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${(task.progress * 100).round()}%',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: isConverting ? Colors.orange : cs.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),

                // Trailing actions
                if (isDownloading)
                  IconButton(
                    icon: Icon(Icons.pause, size: 18, color: cs.onSurfaceVariant),
                    onPressed: () => DownloadService.instance.pauseTask(task.id),
                    tooltip: 'Pause',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
                if (isPaused || isFailed)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.play_arrow, size: 18, color: cs.primary),
                        onPressed: () => DownloadService.instance.resumeTask(task.id),
                        tooltip: 'Resume',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      IconButton(
                        icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant),
                        onPressed: onDelete,
                        tooltip: 'Delete',
                        visualDensity: VisualDensity.compact,
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                if (isCompleted || isPending)
                  IconButton(
                    icon: Icon(Icons.delete_outline, size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                    onPressed: onDelete,
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
