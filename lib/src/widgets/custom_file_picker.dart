import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../services/log_service.dart';

/// A custom in-app file/directory browser that uses [dart:io] directly
/// instead of SAF (Storage Access Framework), which is broken on MIUI.
///
/// On Android 11+, requests [Permission.manageExternalStorage] first.
/// If granted, scans the filesystem with [Directory.list].
/// If denied, shows an error with a link to Settings.
class CustomFilePicker {
  static final _log = LogService.instance;

  /// Request full filesystem access permission on Android 11+.
  /// Returns `true` if permission is granted or not needed.
  static Future<bool> requestStoragePermission() async {
    if (!Platform.isAndroid) return true;

    // Try requesting MANAGE_EXTERNAL_STORAGE even on Android 13+
    // Many devices (especially MIUI) still honor this.
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
    }
    return status.isGranted;
  }

  /// Open the custom directory picker dialog.
  ///
  /// Returns the selected directory path, or `null` if cancelled.
  /// On error, shows a snackbar and returns `null`.
  static Future<String?> pickDirectory({
    required BuildContext context,
    String title = '',
    String? initialPath,
  }) async {
    // Request permission first
    final hasPermission = await requestStoragePermission();
    if (!hasPermission) {
      if (!context.mounted) return null;
      _showPermissionDeniedDialog(context);
      return null;
    }

    // Determine initial path
    String rootPath = initialPath ?? _getDefaultRoot();
    final dir = Directory(rootPath);
    if (!await dir.exists()) {
      rootPath = _getDefaultRoot();
    }

    if (!context.mounted) return null;
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _CustomFilePickerDialog(
        initialPath: rootPath,
        dialogTitle: title,
      ),
    );
  }

  /// Get the default root directory for browsing.
  static String _getDefaultRoot() {
    if (!Platform.isAndroid) return '/';
    // Common internal storage paths on Android
    const candidates = [
      '/storage/emulated/0',
      '/sdcard',
      '/storage',
    ];
    for (final path in candidates) {
      if (Directory(path).existsSync()) return path;
    }
    return '/';
  }

  static void _showPermissionDeniedDialog(BuildContext context) {
    final s = S.of(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.folder_off_rounded, color: Theme.of(ctx).colorScheme.error),
            const SizedBox(width: 12),
            Text(s.permissionRequired('Storage Access')),
          ],
        ),
        content: Text(s.storagePermissionRequired),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: Text(s.openSettings),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Internal dialog widget
// ═══════════════════════════════════════════════════════════════════

class _CustomFilePickerDialog extends StatefulWidget {
  final String initialPath;
  final String dialogTitle;

  const _CustomFilePickerDialog({
    required this.initialPath,
    this.dialogTitle = '',
  });

  @override
  State<_CustomFilePickerDialog> createState() =>
      _CustomFilePickerDialogState();
}

class _CustomFilePickerDialogState extends State<_CustomFilePickerDialog> {
  late List<FileSystemEntity> _entries;
  late String _currentPath;
  bool _isLoading = true;
  String? _error;

  // Breadcrumb — stack of ancestor paths for back navigation
  final List<String> _pathHistory = [];

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory(_currentPath);
  }

  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final dir = Directory(path);
      if (!await dir.exists()) {
        setState(() {
          _error = 'Directory not found: $path';
          _isLoading = false;
          _entries = [];
        });
        return;
      }

      final entities = await dir.list(followLinks: false).toList();

      // Sort: folders first, then by name
      entities.sort((a, b) {
        final aIsDir = a is Directory;
        final bIsDir = b is Directory;
        if (aIsDir && !bIsDir) return -1;
        if (!aIsDir && bIsDir) return 1;
        return p.basename(a.path)
            .toLowerCase()
            .compareTo(p.basename(b.path).toLowerCase());
      });

      if (!mounted) return;
      setState(() {
        _entries = entities;
        _isLoading = false;
      });
    } catch (e) {
      CustomFilePicker._log.warning('[CustomFilePicker] Failed to list $path: $e',
          tag: 'FilePicker');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _entries = [];
      });
    }
  }

  void _navigateTo(String path) {
    _pathHistory.add(_currentPath);
    _currentPath = path;
    _loadDirectory(path);
  }

  void _goBack() {
    if (_pathHistory.isNotEmpty) {
      _currentPath = _pathHistory.removeLast();
      _loadDirectory(_currentPath);
    }
  }

  /// Get the display name for an entity
  String _getDisplayName(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    if (name.isEmpty) return '/';
    return name;
  }

  /// Check if an item should be hidden (hidden files, special dirs)
  bool _isHidden(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    // Skip hidden files/folders
    if (name.startsWith('.')) { return true; }
    // Skip Android/data and Android/obb which are locked on newer Android
    if (name == 'data' && entity.path.contains('/Android/')) { return true; }
    if (name == 'obb' && entity.path.contains('/Android/')) { return true; }
    return false;
  }

  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Folder name',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () {
              final v = controller.text.trim();
              if (v.isNotEmpty) Navigator.pop(ctx, v);
            },
            child: const Text('Create'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty) return;

    try {
      final newDir = Directory('$_currentPath/$name');
      await newDir.create();
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to create folder: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Dialog(
      insetPadding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Back button
                if (_pathHistory.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.arrow_back, size: 20),
                    onPressed: _goBack,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  ),
                if (_pathHistory.isNotEmpty) const SizedBox(width: 4),
                // Path display
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (widget.dialogTitle.isNotEmpty)
                        Text(
                          widget.dialogTitle,
                          style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Text(
                        _currentPath,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                // Close button
                IconButton(
                  icon: const Icon(Icons.close, size: 20),
                  onPressed: () => Navigator.pop(context),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
              ],
            ),
          ),

          // ── Content ──
          SizedBox(
            height: 400,
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _error != null
                    ? _buildError(cs, tt)
                    : _entries.isEmpty
                        ? _buildEmpty(cs, tt)
                        : _buildList(cs, tt),
          ),

          // ── Footer ──
          Container(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(color: cs.outlineVariant, width: 0.5),
              ),
            ),
            child: Row(
              children: [
                // Create folder button
                IconButton(
                  icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                  onPressed: _createNewFolder,
                  tooltip: 'Create folder',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                ),
                const Spacer(),
                // Select this folder button
                FilledButton.tonalIcon(
                  onPressed: () => Navigator.pop(context, _currentPath),
                  icon: const Icon(Icons.check, size: 18),
                  label: const Text('Select'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildError(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, size: 48, color: cs.error),
            const SizedBox(height: 12),
            Text(
              'Cannot access this folder',
              style: tt.titleSmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _error!,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: () => _loadDirectory(_currentPath),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmpty(ColorScheme cs, TextTheme tt) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.folder_open_rounded, size: 48, color: cs.outline),
          const SizedBox(height: 12),
          Text(
            'This folder is empty',
            style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  Widget _buildList(ColorScheme cs, TextTheme tt) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _entries.length,
      itemBuilder: (context, index) {
        final entity = _entries[index];
        if (_isHidden(entity)) return const SizedBox.shrink();

        final isDir = entity is Directory;
        final name = _getDisplayName(entity);

        return Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: isDir ? () => _navigateTo(entity.path) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              child: Row(
                children: [
                  Icon(
                    isDir ? Icons.folder_rounded : Icons.insert_drive_file_outlined,
                    size: 22,
                    color: isDir ? cs.primary : cs.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      name,
                      style: tt.bodyMedium?.copyWith(
                        fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isDir)
                    Icon(
                      Icons.chevron_right,
                      size: 18,
                      color: cs.onSurface.withAlpha(100),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
