import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../models/download_task.dart';
import '../services/download_service.dart';
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
          style: FilledButton.styleFrom(
            backgroundColor: Colors.red,
          ),
          child: Text(S.of(context).delete),
        ),
      ],
    ),
  );
}

class DownloadsScreen extends ConsumerStatefulWidget {
  const DownloadsScreen({super.key});

  @override
  ConsumerState<DownloadsScreen> createState() => _DownloadsScreenState();
}

class _DownloadsScreenState extends ConsumerState<DownloadsScreen> {
  int _selectedCount = 0;
  bool _isSelectionMode = false;
  final _listKey = GlobalKey<_DownloadTaskListState>();

  void _onSelectionChanged(bool isSelectionMode, int count) {
    setState(() {
      _isSelectionMode = isSelectionMode;
      _selectedCount = count;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        scrolledUnderElevation: 0,
        title: _isSelectionMode
            ? Text(S.of(context).selectedCount(_selectedCount))
            : Text(
                S.of(context).downloadTasks,
                style: const TextStyle(fontSize: 18),
              ),
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
        onSelectionChanged: _onSelectionChanged,
      ),
    );
  }
}

/// ===================================================================
/// Download task list — owns StreamBuilder + selection state
/// Rebuilds independently of the parent AppBar via StreamBuilder.
/// ===================================================================
class _DownloadTaskList extends StatefulWidget {
  final void Function(bool isSelectionMode, int count)? onSelectionChanged;

  const _DownloadTaskList({
    super.key,
    this.onSelectionChanged,
  });

  @override
  State<_DownloadTaskList> createState() => _DownloadTaskListState();
}

class _DownloadTaskListState extends State<_DownloadTaskList> {
  bool _isSelectionMode = false;
  final Set<String> _selectedTaskIds = {};
  final Set<int> _selectedWorkIds = {};

  void enterSelectionMode() {
    setState(() {
      _isSelectionMode = true;
    });
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
    final tasks = DownloadService.instance.tasks;
    final activeTasks = tasks
        .where((t) =>
            t.status == DownloadStatus.downloading ||
            t.status == DownloadStatus.paused ||
            t.status == DownloadStatus.pending ||
            t.status == DownloadStatus.failed)
        .toList();

    setState(() {
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
      for (final task in activeTasks) {
        _selectedTaskIds.add(task.id);
      }
      // Mark all fully-selected works
      final Map<int, List<DownloadTask>> grouped = {};
      for (final task in activeTasks) {
        grouped.putIfAbsent(task.workId, () => []).add(task);
      }
      for (final entry in grouped.entries) {
        _selectedWorkIds.add(entry.key);
      }
    });
    widget.onSelectionChanged
        ?.call(true, _selectedTaskIds.length);
  }

  void deselectAll() {
    setState(() {
      _selectedTaskIds.clear();
      _selectedWorkIds.clear();
    });
    widget.onSelectionChanged?.call(true, 0);
  }

  void toggleTaskSelection(String taskId) {
    setState(() {
      if (_selectedTaskIds.contains(taskId)) {
        _selectedTaskIds.remove(taskId);
      } else {
        _selectedTaskIds.add(taskId);
      }
    });
    widget.onSelectionChanged
        ?.call(true, _selectedTaskIds.length);
  }

  void toggleWorkSelection(int workId, List<DownloadTask> workTasks) {
    setState(() {
      if (_selectedWorkIds.contains(workId)) {
        _selectedWorkIds.remove(workId);
        for (final task in workTasks) {
          _selectedTaskIds.remove(task.id);
        }
      } else {
        _selectedWorkIds.add(workId);
        for (final task in workTasks) {
          _selectedTaskIds.add(task.id);
        }
      }
    });
    widget.onSelectionChanged
        ?.call(true, _selectedTaskIds.length);
  }

  Future<void> confirmDelete(DownloadTask task) async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: S.of(context).deletionConfirmTitle,
      message: S.of(context).deleteFileConfirm(task.fileName),
    );

    if (confirmed == true) {
      await DownloadService.instance.deleteTask(task.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).deleted)),
        );
      }
    }
  }

  Future<void> confirmBatchDelete() async {
    final confirmed = await showDeleteConfirmDialog(
      context,
      title: S.of(context).deletionConfirmTitle,
      message: S.of(context)
          .deleteSelectedFilesConfirm(_selectedTaskIds.length),
    );

    if (confirmed == true) {
      final taskIds = List<String>.from(_selectedTaskIds);
      for (final taskId in taskIds) {
        await DownloadService.instance.deleteTask(taskId);
      }

      setState(() {
        _isSelectionMode = false;
        _selectedTaskIds.clear();
        _selectedWorkIds.clear();
      });
      widget.onSelectionChanged?.call(false, 0);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).deletedNFiles(taskIds.length)),
          ),
        );
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

        final activeTasks = tasks
            .where((t) =>
                t.status == DownloadStatus.downloading ||
                t.status == DownloadStatus.paused ||
                t.status == DownloadStatus.pending ||
                t.status == DownloadStatus.failed)
            .toList();

        return _buildDownloadingList(activeTasks);
      },
    );
  }

  Widget _buildDownloadingList(List<DownloadTask> tasks) {
    if (tasks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.download_outlined,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              S.of(context).noDownloadTasks,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    // Group tasks by work
    final Map<int, List<DownloadTask>> groupedTasks = {};
    for (final task in tasks) {
      groupedTasks.putIfAbsent(task.workId, () => []).add(task);
    }

    return ListView.builder(
      itemCount: groupedTasks.length,
      itemBuilder: (context, index) {
        final workId = groupedTasks.keys.elementAt(index);
        final workTasks = groupedTasks[workId]!;
        final firstTask = workTasks.first;
        final isWorkSelected = _selectedWorkIds.contains(workId);

        return _TaskCard(
          workTitle: firstTask.workTitle,
          fileCount: workTasks.length,
          isSelectionMode: _isSelectionMode,
          isWorkSelected: isWorkSelected,
          onToggleWork: () =>
              toggleWorkSelection(workId, workTasks),
          tasks: workTasks,
          selectedTaskIds: _selectedTaskIds,
          onToggleTask: toggleTaskSelection,
          onDeleteTask: confirmDelete,
        );
      },
    );
  }
}

/// ===================================================================
/// Task card — grouped by work, shows ExpansionTile + children
/// ===================================================================
class _TaskCard extends StatelessWidget {
  final String workTitle;
  final int fileCount;
  final bool isSelectionMode;
  final bool isWorkSelected;
  final VoidCallback onToggleWork;
  final List<DownloadTask> tasks;
  final Set<String> selectedTaskIds;
  final void Function(String) onToggleTask;
  final void Function(DownloadTask) onDeleteTask;

  const _TaskCard({
    required this.workTitle,
    required this.fileCount,
    required this.isSelectionMode,
    required this.isWorkSelected,
    required this.onToggleWork,
    required this.tasks,
    required this.selectedTaskIds,
    required this.onToggleTask,
    required this.onDeleteTask,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: ExpansionTile(
        leading: isSelectionMode
            ? Checkbox(
                value: isWorkSelected,
                onChanged: (_) => onToggleWork(),
              )
            : const Icon(Icons.folder),
        title: Text(
          workTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        subtitle: Text(
          S.of(context).nFiles(fileCount),
          style: const TextStyle(fontSize: 12),
        ),
        trailing: isSelectionMode ? null : const Icon(Icons.expand_more),
        children: tasks
            .map((task) => _TaskTile(
                  task: task,
                  isSelectionMode: isSelectionMode,
                  isSelected: selectedTaskIds.contains(task.id),
                  onToggle: () => onToggleTask(task.id),
                  onDelete: () => onDeleteTask(task),
                ))
            .toList(),
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
    return ListTile(
      leading: isSelectionMode
          ? Checkbox(
              value: isSelected,
              onChanged: (_) => onToggle(),
            )
          : _buildStatusIcon(task.status),
      title: Text(
        task.fileName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: isSelectionMode ? onToggle : null,
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (task.totalBytes != null && task.totalBytes! > 0) ...[
            const SizedBox(height: 4),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: Colors.grey[300],
            ),
            const SizedBox(height: 4),
            Text(
              '${formatBytes(task.downloadedBytes)} / '
              '${formatBytes(task.totalBytes!)} '
              '(${(task.progress * 100).toStringAsFixed(1)}%)',
              style: const TextStyle(fontSize: 11),
            ),
          ],
          if (task.error != null) ...[
            const SizedBox(height: 4),
            Text(
              S.of(context).errorWithMessage(task.error!),
              style: const TextStyle(fontSize: 11, color: Colors.red),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
      trailing: isSelectionMode ? null : _buildTaskActions(context, task),
    );
  }

  Widget _buildStatusIcon(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return const Icon(Icons.schedule, color: Colors.grey);
      case DownloadStatus.downloading:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case DownloadStatus.paused:
        return const Icon(Icons.pause_circle, color: Colors.orange);
      case DownloadStatus.completed:
        return const Icon(Icons.check_circle, color: Colors.green);
      case DownloadStatus.failed:
        return const Icon(Icons.error, color: Colors.red);
    }
  }

  Widget _buildTaskActions(BuildContext context, DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () =>
              DownloadService.instance.pauseTask(task.id),
          tooltip: S.of(context).pause,
        );
      case DownloadStatus.paused:
      case DownloadStatus.failed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(Icons.play_arrow),
              onPressed: () =>
                  DownloadService.instance.resumeTask(task.id),
              tooltip: S.of(context).resume,
            ),
            IconButton(
              icon: const Icon(Icons.delete),
              onPressed: onDelete,
              tooltip: S.of(context).delete,
            ),
          ],
        );
      default:
        return IconButton(
          icon: const Icon(Icons.delete),
          onPressed: onDelete,
          tooltip: S.of(context).delete,
        );
    }
  }
}
