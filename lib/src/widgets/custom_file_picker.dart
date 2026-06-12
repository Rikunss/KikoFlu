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
// Internal dialog widget — redesigned with Material 3
// ═══════════════════════════════════════════════════════════════════

class _BreadcrumbInfo {
  final String label;
  final String path;
  const _BreadcrumbInfo({required this.label, required this.path});
}

class _QuickAccessLocation {
  final String label;
  final IconData icon;
  final String path;
  const _QuickAccessLocation({
    required this.label,
    required this.icon,
    required this.path,
  });
}

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
  String _searchQuery = '';
  final _searchController = TextEditingController();
  bool _showSearch = false;
  bool _showHiddenFiles = false;

  // Path history for back navigation
  final List<String> _pathHistory = [];

  // Pre-cached modified dates for list items
  final Map<String, DateTime> _modifiedDates = {};

  @override
  void initState() {
    super.initState();
    _currentPath = widget.initialPath;
    _loadDirectory(_currentPath);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // ── Directory loading ──
  Future<void> _loadDirectory(String path) async {
    setState(() {
      _isLoading = true;
      _error = null;
      _showSearch = false;
      _searchQuery = '';
      _searchController.clear();
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

      // Cache modified dates
      _modifiedDates.clear();

      // Sort: folders first, then alphabetically
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
      CustomFilePicker._log.warning(
          '[CustomFilePicker] Failed to list $path: $e', tag: 'FilePicker');
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _isLoading = false;
        _entries = [];
      });
    }
  }

  // ── Navigation ──
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

  bool get _canGoBack => _pathHistory.isNotEmpty;

  // ── Helpers ──
  String _getDisplayName(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    return name.isEmpty ? '/' : name;
  }

  bool _isHidden(FileSystemEntity entity) {
    final name = p.basename(entity.path);
    // Skip hidden dotfiles unless user toggled show hidden
    if (name.startsWith('.') && !_showHiddenFiles) return true;
    // These system dirs are locked on Android 11+ and can't be browsed anyway
    if (name == 'data' && entity.path.contains('/Android/')) return true;
    if (name == 'obb' && entity.path.contains('/Android/')) return true;
    return false;
  }

  /// Build breadcrumb segments from the current path.
  List<_BreadcrumbInfo> _getBreadcrumbs() {
    final segments = _currentPath
        .split(Platform.pathSeparator)
        .where((s) => s.isNotEmpty)
        .toList();
    final crumbs = <_BreadcrumbInfo>[];
    String accumulated = '';
    for (int i = 0; i < segments.length; i++) {
      accumulated += (i == 0 ? '' : '/') + segments[i];
      // On Android, fix the leading slash
      String label = segments[i];
      if (Platform.isAndroid && i == 0) {
        if (segments[i] == 'storage') label = 'Storage';
        else if (segments[i] == 'sdcard') label = 'SD Card';
        else if (segments[i] == 'emulated') label = 'Internal';
      }
      crumbs.add(_BreadcrumbInfo(
        label: label,
        path: i == 0 ? '/${segments[0]}' : '/${segments.sublist(0, i + 1).join('/')}',
      ));
    }
    return crumbs;
  }

  /// Quick-access locations for Android.
  List<_QuickAccessLocation> _getQuickAccess() {
    final storageRoot = '/storage/emulated/0';
    if (!Directory(storageRoot).existsSync()) return [];
    return [
      _QuickAccessLocation(
        label: 'Internal Storage',
        icon: Icons.phone_android_rounded,
        path: storageRoot,
      ),
      _QuickAccessLocation(
        label: 'Downloads',
        icon: Icons.download_rounded,
        path: '$storageRoot/Download',
      ),
      _QuickAccessLocation(
        label: 'DCIM',
        icon: Icons.camera_alt_rounded,
        path: '$storageRoot/DCIM',
      ),
      _QuickAccessLocation(
        label: 'Documents',
        icon: Icons.description_rounded,
        path: '$storageRoot/Documents',
      ),
      _QuickAccessLocation(
        label: 'Music',
        icon: Icons.music_note_rounded,
        path: '$storageRoot/Music',
      ),
    ];
  }

  // ── Actions ──
  Future<void> _createNewFolder() async {
    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Create Folder'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Folder name',
            border: OutlineInputBorder(),
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
      await Directory('$_currentPath/$name').create();
      _loadDirectory(_currentPath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text('Failed to create folder: $e')),
      );
    }
  }

  // ── Filtered entries for search ──
  List<FileSystemEntity> get _filteredEntries {
    if (_searchQuery.isEmpty) return _entries;
    final q = _searchQuery.toLowerCase();
    return _entries.where((e) {
      if (_isHidden(e)) return false;
      return _getDisplayName(e).toLowerCase().contains(q);
    }).toList();
  }

  // ── Count items in subdirectories (non-recursive, synchronous) ──
  int _countItems(String dirPath) {
    try {
      final dir = Directory(dirPath);
      if (!dir.existsSync()) return 0;
      return dir.listSync().length;
    } catch (_) {
      return 0;
    }
  }

  // ── Build ──
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final isRoot = _currentPath == '/storage/emulated/0' ||
        _currentPath == '/' ||
        _currentPath.endsWith('/0');

    return PopScope(
      canPop: !_canGoBack,
      onPopInvoked: (didPop) {
        if (!didPop && _canGoBack) {
          _goBack();
        }
      },
      child: Dialog(
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header with breadcrumb ──
            _buildHeader(cs, tt),

            // ── Quick access (only visible near root) ──
            if (isRoot && _entries.isNotEmpty && !_isLoading && _error == null)
              _buildQuickAccess(cs, tt),

            // ── Search bar ──
            if (_showSearch) _buildSearchBar(cs, tt),

            // ── Content ──
            SizedBox(
              height: 380,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                child: _isLoading
                    ? _buildSkeleton(cs)
                    : _error != null
                        ? _buildError(cs, tt)
                        : _filteredEntries.isEmpty
                            ? _buildEmpty(cs, tt)
                            : _buildList(cs, tt),
              ),
            ),

            // ── Footer ──
            _buildFooter(cs, tt),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(ColorScheme cs, TextTheme tt) {
    final crumbs = _getBreadcrumbs();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: title + action buttons
          Row(
            children: [
              // Back button
              if (_canGoBack)
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: _IconButtonSmall(
                    icon: Icons.arrow_back_rounded,
                    onPressed: _goBack,
                    tooltip: 'Back',
                    cs: cs,
                  ),
                ),
              // Title
              Expanded(
                child: widget.dialogTitle.isNotEmpty
                    ? Text(
                        widget.dialogTitle,
                        style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600),
                      )
                    : const SizedBox.shrink(),
              ),
              // Show/hide hidden files
              _IconButtonSmall(
                icon: _showHiddenFiles
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                onPressed: () => setState(() => _showHiddenFiles = !_showHiddenFiles),
                tooltip: _showHiddenFiles ? 'Hide hidden files' : 'Show hidden files',
                cs: cs,
                activeColor: _showHiddenFiles ? cs.primary : null,
              ),
              // Refresh
              _IconButtonSmall(
                icon: Icons.refresh_rounded,
                onPressed: () => _loadDirectory(_currentPath),
                tooltip: 'Refresh',
                cs: cs,
              ),
              // Search toggle
              _IconButtonSmall(
                icon: _showSearch ? Icons.search_off_rounded : Icons.search_rounded,
                onPressed: () => setState(() => _showSearch = !_showSearch),
                tooltip: 'Search',
                cs: cs,
              ),
              // Close
              _IconButtonSmall(
                icon: Icons.close_rounded,
                onPressed: () => Navigator.pop(context),
                tooltip: 'Close',
                cs: cs,
              ),
            ],
          ),
          // Breadcrumb row
          const SizedBox(height: 6),
          SizedBox(
            height: 28,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: crumbs.length,
              separatorBuilder: (_, __) => Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Icon(Icons.chevron_right, size: 14, color: cs.onSurfaceVariant.withAlpha(120)),
              ),
              itemBuilder: (_, i) {
                final isLast = i == crumbs.length - 1;
                return GestureDetector(
                  onTap: isLast ? null : () {
                    _pathHistory.add(_currentPath);
                    _currentPath = crumbs[i].path;
                    _loadDirectory(_currentPath);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: isLast
                          ? cs.primaryContainer.withValues(alpha: 0.5)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      crumbs[i].label,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: isLast ? FontWeight.w600 : FontWeight.w400,
                        color: isLast
                            ? cs.onPrimaryContainer
                            : cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickAccess(ColorScheme cs, TextTheme tt) {
    final locations = _getQuickAccess();
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('Quick Access',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant.withAlpha(150)),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 56,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: locations.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (_, i) {
                final loc = locations[i];
                final exists = Directory(loc.path).existsSync();
                if (!exists) return const SizedBox.shrink();
                return _QuickAccessChip(
                  label: loc.label,
                  icon: loc.icon,
                  onTap: () {
                    _pathHistory.add(_currentPath);
                    _currentPath = loc.path;
                    _loadDirectory(loc.path);
                  },
                  cs: cs,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchBar(ColorScheme cs, TextTheme tt) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: cs.outlineVariant, width: 0.5)),
        color: cs.surfaceContainerLow.withValues(alpha: 0.5),
      ),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Filter folders...',
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
        ),
        onChanged: (v) => setState(() => _searchQuery = v),
      ),
    );
  }

  Widget _buildFooter(ColorScheme cs, TextTheme tt) {
    final showing = _searchQuery.isEmpty ? _entries.length : _filteredEntries.length;
    final filtered = _searchQuery.isEmpty ? 0 : _entries.length - _filteredEntries.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: cs.outlineVariant, width: 0.5)),
      ),
      child: Row(
        children: [
          // Create folder
          _IconButtonSmall(
            icon: Icons.create_new_folder_rounded,
            onPressed: _createNewFolder,
            tooltip: 'New Folder',
            cs: cs,
          ),
          const SizedBox(width: 8),
          // Count badge
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              filtered > 0 ? '$showing/$filtered' : '$showing',
              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
            ),
          ),
          const Spacer(),
          // Select button
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, _currentPath),
            icon: const Icon(Icons.check_rounded, size: 18),
            label: const Text('Select'),
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Loading skeleton ──
  Widget _buildSkeleton(ColorScheme cs) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: List.generate(6, (i) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Container(
                  height: 14,
                  decoration: BoxDecoration(
                    color: cs.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
            ],
          ),
        )),
      ),
    );
  }

  // ── Error state ──
  Widget _buildError(ColorScheme cs, TextTheme tt) {
    return Center(key: const ValueKey('error'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded, size: 32, color: cs.error),
            ),
            const SizedBox(height: 16),
            Text('Cannot access this folder',
              style: tt.titleSmall?.copyWith(color: cs.error),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(_error!,
              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () => _loadDirectory(_currentPath),
              icon: const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Empty state ──
  Widget _buildEmpty(ColorScheme cs, TextTheme tt) {
    return Center(key: const ValueKey('empty'),
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64, height: 64,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.folder_open_rounded, size: 32, color: cs.onSurfaceVariant.withAlpha(100)),
            ),
            const SizedBox(height: 16),
            Text(
              _searchQuery.isNotEmpty ? 'No matches' : 'This folder is empty',
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
            if (_searchQuery.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  '"$_searchQuery" not found in this folder',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant.withAlpha(150)),
                ),
              ),
            const SizedBox(height: 20),
            if (_searchQuery.isNotEmpty)
              FilledButton.tonalIcon(
                onPressed: () {
                  _searchController.clear();
                  setState(() => _searchQuery = '');
                },
                icon: const Icon(Icons.clear_rounded, size: 18),
                label: const Text('Clear filter'),
              ),
          ],
        ),
      ),
    );
  }

  // ── File list ──
  Widget _buildList(ColorScheme cs, TextTheme tt) {
    final items = _filteredEntries;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: items.length,
      itemBuilder: (context, index) {
        final entity = items[index];
        if (_isHidden(entity)) return const SizedBox.shrink();

        final isDir = entity is Directory;
        final name = _getDisplayName(entity);
        final isSelected = entity.path == _currentPath;

        // Count sub-items for folders
        int subCount = 0;
        if (isDir) {
          subCount = _countItems(entity.path);
        }

        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          child: Material(
            color: isSelected
                ? cs.primaryContainer.withValues(alpha: 0.3)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
            child: InkWell(
              borderRadius: BorderRadius.circular(10),
              onTap: isDir ? () => _navigateTo(entity.path) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                child: Row(
                  children: [
                    // Icon with container
                    Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: isDir
                            ? cs.primaryContainer.withValues(alpha: 0.5)
                            : cs.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(
                        isDir
                            ? (_isDownloads(name)
                                ? Icons.download_rounded
                                : Icons.folder_rounded)
                            : Icons.insert_drive_file_outlined,
                        size: 20,
                        color: isDir ? cs.primary : cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Name + info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            name,
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: isDir ? FontWeight.w500 : FontWeight.normal,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (isDir && subCount > 0)
                            Text(
                              '$subCount ${subCount == 1 ? 'item' : 'items'}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant.withAlpha(150),
                              ),
                            ),
                        ],
                      ),
                    ),
                    // Chevron for folders
                    if (isDir)
                      Container(
                        width: 24, height: 24,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Icon(
                          Icons.chevron_right_rounded,
                          size: 18,
                          color: cs.onSurface.withAlpha(120),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  bool _isDownloads(String name) {
    return name.toLowerCase() == 'download' || name.toLowerCase() == 'downloads';
  }
}

// ═══════════════════════════════════════════════════════════════════
// Reusable small icon button
// ═══════════════════════════════════════════════════════════════════

class _IconButtonSmall extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final String tooltip;
  final ColorScheme cs;
  final Color? activeColor;
  const _IconButtonSmall({
    required this.icon,
    this.onPressed,
    required this.tooltip,
    required this.cs,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onPressed,
        child: Container(
          width: 32, height: 32,
          decoration: activeColor != null
              ? BoxDecoration(
                  color: activeColor!.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                )
              : null,
          alignment: Alignment.center,
          child: Icon(icon, size: 20,
            color: activeColor ?? (onPressed != null
                ? cs.onSurfaceVariant
                : cs.onSurfaceVariant.withAlpha(80))),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════
// Quick access chip
// ═══════════════════════════════════════════════════════════════════

class _QuickAccessChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme cs;

  const _QuickAccessChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: cs.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: cs.outlineVariant, width: 0.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: cs.primary),
              const SizedBox(width: 6),
              Text(label,
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                  color: cs.onSurface),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
