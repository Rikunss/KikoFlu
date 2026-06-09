import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/work.dart' show AudioFile;
import '../utils/string_utils.dart' show formatBytes;
import '../utils/file_icon_utils.dart' show FileIconUtils;
import '../../l10n/app_localizations.dart';

/// Shared file tree selector widget with checkboxes, folder expand/collapse,
/// and selection state management. Used by both [FileSelectionDialog] and
/// [PlayNextSelectionDialog] to avoid code duplication.
class FileTreeSelector extends StatefulWidget {
  final List<AudioFile> files;
  final Set<String> downloadedHashes;
  final bool preSelectAll;

  /// Called whenever the selection changes, so the parent can rebuild its UI.
  final VoidCallback? onSelectionChanged;

  const FileTreeSelector({
    super.key,
    required this.files,
    this.downloadedHashes = const {},
    this.preSelectAll = false,
    this.onSelectionChanged,
  });

  @override
  FileTreeSelectorState createState() => FileTreeSelectorState();
}

class FileTreeSelectorState extends State<FileTreeSelector> {
  late Map<String, bool> _selectedFiles; // hash -> selected
  final Set<String> _expandedFolders = {};

  @override
  void initState() {
    super.initState();
    _selectedFiles = {};
    _initializeSelection(widget.files, widget.preSelectAll);
  }

  @override
  void didUpdateWidget(FileTreeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-initialize if files changed.
    // Note: uses referential equality — the files list should be stable
    // (e.g., not a new list with same elements) to avoid resetting selection.
    if (oldWidget.files != widget.files) {
      _selectedFiles = {};
      _initializeSelection(widget.files, widget.preSelectAll);
    }
  }

  void _initializeSelection(List<AudioFile> files, bool preSelect) {
    for (final file in files) {
      if (file.type == 'file' && file.hash != null) {
        final isDownloaded = widget.downloadedHashes.contains(file.hash);
        _selectedFiles[file.hash!] = preSelect && !isDownloaded;
      }
      if (file.children != null) {
        _initializeSelection(file.children!, preSelect);
      }
    }
  }

  // ── Public getters ──

  /// Number of currently selected files (excluding downloaded).
  int get selectedCount => _selectedFiles.values.where((v) => v).length;

  /// Map of all file hashes to their selection state.
  Map<String, bool> get selectedFiles => Map.unmodifiable(_selectedFiles);

  /// Collect all [AudioFile]s that are currently selected.
  List<AudioFile> getSelectedFiles() {
    final result = <AudioFile>[];
    _collectSelected(widget.files, result);
    return result;
  }

  void _collectSelected(List<AudioFile> files, List<AudioFile> out) {
    for (final file in files) {
      if (file.type == 'file' && _selectedFiles[file.hash] == true) {
        out.add(file);
      }
      if (file.children != null) {
        _collectSelected(file.children!, out);
      }
    }
  }

  /// Collect selected files with their relative paths (for download).
  Map<AudioFile, String> getSelectedFilesWithPaths() {
    final result = <AudioFile, String>{};
    _collectWithPaths(widget.files, '', result);
    return result;
  }

  void _collectWithPaths(
      List<AudioFile> files, String parentPath, Map<AudioFile, String> out) {
    for (final file in files) {
      if (file.type == 'file' && _selectedFiles[file.hash] == true) {
        out[file] = parentPath;
      }
      if (file.children != null) {
        final folderPath = parentPath.isEmpty
            ? file.title
            : '$parentPath/${file.title}';
        _collectWithPaths(file.children!, folderPath, out);
      }
    }
  }

  /// Select or deselect all files that are not yet downloaded.
  void toggleSelectAll() {
    final availableKeys = _selectedFiles.keys
        .where((h) => !widget.downloadedHashes.contains(h))
        .toList();
    if (availableKeys.isEmpty) return;

    final allSelected =
        availableKeys.every((h) => _selectedFiles[h] ?? false);
    setState(() {
      for (final hash in availableKeys) {
        _selectedFiles[hash] = !allSelected;
      }
    });
    widget.onSelectionChanged?.call();
  }

  // ── Internal helpers ──

  String _itemPath(String parentPath, AudioFile item) {
    return parentPath.isEmpty ? item.title : '$parentPath/${item.title}';
  }

  void _toggleFile(String hash) {
    setState(() {
      _selectedFiles[hash] = !(_selectedFiles[hash] ?? false);
    });
    widget.onSelectionChanged?.call();
  }

  void _toggleFolderExpand(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  void _toggleFolderSelection(String path, bool selected) {
    void selectInChildren(List<AudioFile> items, String parentPath) {
      for (final item in items) {
        final childPath = _itemPath(parentPath, item);
        if (item.type == 'file' && item.hash != null) {
          if (!widget.downloadedHashes.contains(item.hash)) {
            _selectedFiles[item.hash!] = selected;
          }
        } else if (item.type == 'folder' && item.children != null) {
          selectInChildren(item.children!, childPath);
        }
      }
    }

    void findAndSelect(List<AudioFile> items, String currentPath) {
      for (final item in items) {
        final childPath = _itemPath(currentPath, item);
        if (childPath == path && item.children != null) {
          selectInChildren(item.children!, childPath);
          return;
        }
        if (item.type == 'folder' && item.children != null) {
          findAndSelect(item.children!, childPath);
        }
      }
    }

    setState(() {
      findAndSelect(widget.files, '');
    });
    widget.onSelectionChanged?.call();
  }

  bool? _folderSelectionState(AudioFile folder) {
    if (folder.children == null || folder.children!.isEmpty) return false;

    int selectedCount = 0;
    int totalCount = 0;

    void countSelection(List<AudioFile> items) {
      for (final item in items) {
        if (item.type == 'file' && item.hash != null) {
          final isDownloaded = widget.downloadedHashes.contains(item.hash);
          if (!isDownloaded) {
            totalCount++;
            if (_selectedFiles[item.hash!] ?? false) selectedCount++;
          }
        }
        if (item.children != null) countSelection(item.children!);
      }
    }

    countSelection(folder.children!);
    if (totalCount == 0) return false;
    if (selectedCount == 0) return false;
    if (selectedCount == totalCount) return true;
    return null;
  }

  // ── Build ──

  @override
  Widget build(BuildContext context) {
    if (widget.files.isEmpty) {
      return _buildEmptyState(context);
    }
    return ListView(
      shrinkWrap: true,
      children: _buildTree(widget.files, 0, ''),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_off_rounded, size: 32, color: Theme.of(context).colorScheme.primary),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).noDownloadableFiles,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildTree(
      List<AudioFile> files, int level, String parentPath) {
    final widgets = <Widget>[];

    for (final file in files) {
      final path = _itemPath(parentPath, file);

      if (file.type == 'folder' && file.children != null) {
        final isExpanded = _expandedFolders.contains(path);
        final selState = _folderSelectionState(file);

        widgets.add(_FolderRow(
          file: file,
          level: level,
          isExpanded: isExpanded,
          selectionState: selState,
          onTap: () {
            HapticFeedback.lightImpact();
            _toggleFolderExpand(path);
          },
          onCheckboxChanged: (v) => _toggleFolderSelection(path, v ?? false),
        ));

        if (isExpanded) {
          widgets.addAll(_buildTree(file.children!, level + 1, path));
        }
      } else if (file.type == 'file') {
        final hash = file.hash ?? '';
        final isDownloaded = widget.downloadedHashes.contains(hash);
        final isSelected = _selectedFiles[hash] ?? false;

        widgets.add(_FileRow(
          file: file,
          level: level,
          isDownloaded: isDownloaded,
          isSelected: isSelected,
          onTap: isDownloaded
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  _toggleFile(hash);
                },
          onCheckboxChanged: isDownloaded ? null : (_) {
            HapticFeedback.lightImpact();
            _toggleFile(hash);
          },
        ));
      }
    }

    return widgets;
  }
}

// ── Helper widgets ──

class _FolderRow extends StatelessWidget {
  final AudioFile file;
  final int level;
  final bool isExpanded;
  final bool? selectionState;
  final VoidCallback onTap;
  final ValueChanged<bool?> onCheckboxChanged;

  const _FolderRow({
    required this.file,
    required this.level,
    required this.isExpanded,
    required this.selectionState,
    required this.onTap,
    required this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 4.0 + (level * 16.0), right: 4.0),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 40,
              child: Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                color: cs.onSurface.withAlpha(153),
                size: 20,
              ),
            ),
            SizedBox(
              width: 32,
              height: 40,
              child: Checkbox(
                value: selectionState,
                tristate: true,
                onChanged: onCheckboxChanged,
              ),
            ),
            const SizedBox(width: 4),
            Icon(
              FileIconUtils.getFileIcon(file),
              color: FileIconUtils.getFileIconColor(file),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.title,
                style: Theme.of(context).textTheme.bodyMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FileRow extends StatelessWidget {
  final AudioFile file;
  final int level;
  final bool isDownloaded;
  final bool isSelected;
  final VoidCallback? onTap;
  final ValueChanged<bool?>? onCheckboxChanged;

  const _FileRow({
    required this.file,
    required this.level,
    required this.isDownloaded,
    required this.isSelected,
    this.onTap,
    this.onCheckboxChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.only(left: 4.0 + (level * 16.0), right: 4.0),
        child: Row(
          children: [
            const SizedBox(width: 32, height: 40),
            SizedBox(
              width: 32,
              height: 40,
              child: isDownloaded
                  ? Icon(Icons.check_circle, color: cs.primary, size: 20)
                  : Checkbox(
                      value: isSelected,
                      onChanged: onCheckboxChanged,
                    ),
            ),
            const SizedBox(width: 4),
            Icon(
              FileIconUtils.getFileIcon(file),
              color: FileIconUtils.getFileIconColor(file),
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          file.title,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: isDownloaded
                                ? cs.onSurface.withAlpha(153)
                                : null,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (isDownloaded) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primaryContainer.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            'Downloaded',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.primary,
                              fontSize: 11,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  if (file.size != null) ...[
                    const SizedBox(height: 2),
                    Text(
                      formatBytes(file.size!),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurface.withAlpha(153),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
