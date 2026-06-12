import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/download_service.dart';
import '../services/log_service.dart';
import '../models/work.dart';
import '../utils/metadata_utils.dart';
import '../utils/snackbar_util.dart';

import 'offline_work_detail_screen.dart';
import '../../l10n/app_localizations.dart';

final _log = LogService.instance;

/// A simplified Work-like structure returned by the scanner.
class _LocalWorkEntry {
  final int workId;
  final String title;
  final int fileCount;
  final int totalBytes;
  final String? localCoverPath;
  final Map<String, dynamic>? metadata;

  const _LocalWorkEntry({
    required this.workId,
    required this.title,
    required this.fileCount,
    required this.totalBytes,
    this.localCoverPath,
    this.metadata,
  });

  String get rjCode => 'RJ${workId.toString().padLeft(6, '0')}';
}

/// Folder-based local file browser — scans the download directory
/// and presents work folders in a file-explorer style list.
///
/// User taps a work → opens the offline work detail screen which
/// shows the full file tree with expandable folders.
class LocalFileBrowserScreen extends ConsumerStatefulWidget {
  const LocalFileBrowserScreen({super.key});

  @override
  ConsumerState<LocalFileBrowserScreen> createState() =>
      _LocalFileBrowserScreenState();
}

class _LocalFileBrowserScreenState
    extends ConsumerState<LocalFileBrowserScreen> {
  List<_LocalWorkEntry> _entries = [];
  bool _isLoading = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _scanDirectory();
  }

  Future<void> _scanDirectory() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final downloadDir = await DownloadService.instance.getDownloadDirectory();
      if (!await downloadDir.exists()) {
        setState(() {
          _isLoading = false;
          _entries = [];
        });
        return;
      }

      final entries = <_LocalWorkEntry>[];
      await for (final entity in downloadDir.list()) {
        if (entity is! Directory) continue;

        // Only process directories with numeric names (work IDs)
        final folderName =
            entity.path.split(Platform.pathSeparator).last;
        final workId = int.tryParse(folderName);
        if (workId == null) continue;

        // Read metadata
        final metadataFile = File('${entity.path}/work_metadata.json');
        Map<String, dynamic>? metadata;
        String title = 'RJ$workId';
        if (await metadataFile.exists()) {
          try {
            final raw = await metadataFile.readAsString();
            metadata = jsonDecode(raw) as Map<String, dynamic>;
            title = (metadata['title'] as String?) ?? title;
          } catch (e) {
            _log.debug('Failed to read metadata for $folderName: $e',
                tag: 'LocalBrowser');
          }
        }

        // Count files (excluding metadata and cover) — use concurrent counting
        int fileCount = 0;
        int totalBytes = 0;
        try {
          final files = await entity.list(recursive: true).toList();
          final fileFutures = files.whereType<File>().map((f) async {
            final name = f.path.split(Platform.pathSeparator).last;
            if (name == 'work_metadata.json' ||
                name == 'cover.jpg' ||
                name.endsWith('.downloading')) {
              return null;
            }
            try {
              final len = await f.length();
              return {'name': name, 'len': len};
            } catch (_) {
              return null;
            }
          });
          final results = await Future.wait(fileFutures);
          for (final r in results) {
            if (r != null) {
              fileCount++;
              totalBytes += r['len'] as int;
            }
          }
        } catch (_) {
          // If listing fails, skip file counting for this work
        }

        if (metadata == null) {
          _log.debug('Skipping work $folderName — no metadata', tag: 'LocalBrowser');
          continue;
        }

        String? coverPath;
        final coverFile = File('${entity.path}/cover.jpg');
        if (await coverFile.exists()) {
          coverPath = coverFile.path;
        }

        entries.add(_LocalWorkEntry(
          workId: workId,
          title: title,
          fileCount: fileCount,
          totalBytes: totalBytes,
          localCoverPath: coverPath,
          metadata: metadata,
        ));
      }

      // Sort by workId descending (newest first)
      entries.sort((a, b) => b.workId.compareTo(a.workId));

      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    } catch (e) {
      _log.warning('Failed to scan download directory: $e', tag: 'LocalBrowser');
      setState(() {
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _openWork(_LocalWorkEntry entry) async {
    try {
      final sanitized = sanitizeMetadata(entry.metadata!);
      final work = Work.fromJson(sanitized);

      // Extract localImportPath from raw metadata for imported works
      final localImportPath = entry.metadata!['local_import_path'] as String?;

      if (!mounted) return;
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => OfflineWorkDetailScreen(
          work: work,
          isOffline: true,
          localCoverPath: entry.localCoverPath,
          localImportPath: localImportPath,
        ),
      ));
    } catch (e) {
      if (!mounted) return;
      _log.warning('Failed to open work ${entry.workId}: $e', tag: 'LocalBrowser');
      SnackBarUtil.showError(
          context, S.of(context).openWorkDetailFailed(e.toString()));
    }
  }



  String _formatBytes(int bytes) {
    if (bytes <= 0) return '';
    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }
    if (unitIndex == 0) return '$bytes B';
    return '${size.toStringAsFixed(1)} ${units[unitIndex]}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).localFileBrowser),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: S.of(context).refresh,
            onPressed: _scanDirectory,
          ),
        ],
      ),
      body: _buildBody(theme, colorScheme),
    );
  }

  Widget _buildBody(ThemeData theme, ColorScheme colorScheme) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(_errorMessage!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: _scanDirectory,
                icon: const Icon(Icons.refresh),
                label: Text(S.of(context).retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_entries.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.folder_open_rounded,
                    size: 48, color: colorScheme.primary),
              ),
              const SizedBox(height: 20),
              Text(
                S.of(context).noDownloadedWorks,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context).noLocalDownloads,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _scanDirectory,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        itemCount: _entries.length,
        itemBuilder: (context, index) {
          final entry = _entries[index];
          return _WorkFolderTile(
            entry: entry,
            onTap: () => _openWork(entry),
            formatBytes: _formatBytes,
            colorScheme: colorScheme,
          );
        },
      ),
    );
  }
}

/// A single work folder tile in the browser list.
class _WorkFolderTile extends StatelessWidget {
  final _LocalWorkEntry entry;
  final VoidCallback onTap;
  final String Function(int) formatBytes;
  final ColorScheme colorScheme;

  const _WorkFolderTile({
    required this.entry,
    required this.onTap,
    required this.formatBytes,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      clipBehavior: Clip.antiAlias,
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant,
          width: 0.5,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Folder icon or cover thumbnail
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: entry.localCoverPath != null
                      ? Image.file(
                          File(entry.localCoverPath!),
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) =>
                              _buildFolderIcon(colorScheme),
                        )
                      : _buildFolderIcon(colorScheme),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer
                                .withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            entry.rjCode,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Icon(Icons.insert_drive_file_outlined,
                            size: 14,
                            color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          '${entry.fileCount}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (entry.totalBytes > 0) ...[
                          const SizedBox(width: 12),
                          Icon(Icons.storage,
                              size: 14,
                              color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 4),
                          Text(
                            formatBytes(entry.totalBytes),
                            style: TextStyle(
                              fontSize: 12,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFolderIcon(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.secondaryContainer.withValues(alpha: 0.3),
      child: Icon(
        Icons.folder_rounded,
        size: 32,
        color: colorScheme.secondary,
      ),
    );
  }
}
