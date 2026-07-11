import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../models/work.dart';
import '../services/download_service.dart';
import '../utils/snackbar_util.dart';
import '../providers/auth_provider.dart';
import 'file_tree_selector.dart';

class FileSelectionDialog extends ConsumerStatefulWidget {
  final Work work;

  const FileSelectionDialog({
    super.key,
    required this.work,
  });

  @override
  ConsumerState<FileSelectionDialog> createState() =>
      _FileSelectionDialogState();
}

class _FileSelectionDialogState extends ConsumerState<FileSelectionDialog> {
  final _treeKey = GlobalKey<FileTreeSelectorState>();
  final Set<String> _downloadedFiles = {};
  bool _isCheckingDownloads = true;

  @override
  void initState() {
    super.initState();
    _checkDownloadedFiles();
  }

  Future<void> _checkDownloadedFiles() async {
    final downloadService = DownloadService.instance;
    final hashesToCheck = <String>[];

    void collectHashes(List<AudioFile> files) {
      for (final file in files) {
        if (file.type == 'file' && file.hash != null) {
          hashesToCheck.add(file.hash!);
        }
        if (file.children != null) collectHashes(file.children!);
      }
    }
    if (widget.work.children != null) {
      collectHashes(widget.work.children!);
    }

    for (final hash in hashesToCheck) {
      final filePath =
          await downloadService.getDownloadedFilePath(widget.work.id, hash);
      if (filePath != null) {
        _downloadedFiles.add(hash);
      }
    }

    if (mounted) {
      setState(() => _isCheckingDownloads = false);
    }
  }

  void _startDownload() async {
    final selectedFilesWithPaths =
        _treeKey.currentState?.getSelectedFilesWithPaths();
    if (selectedFilesWithPaths == null || selectedFilesWithPaths.isEmpty) {
      if (mounted) {
        SnackBarUtil.showWarning(context, S.of(context).selectAtLeastOneFile);
      }
      return;
    }

    final downloadService = DownloadService.instance;
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final coverUrl = widget.work.getCoverImageUrl(host, token: token);

    final workJson = widget.work.toJson();
    final workMetadata = Map<String, dynamic>.from(workJson);

    for (final entry in selectedFilesWithPaths.entries) {
      final file = entry.key;
      final relativePath = entry.value;

      final fullFileName =
          relativePath.isEmpty ? file.title : '$relativePath/${file.title}';

      String downloadUrl = file.mediaDownloadUrl ?? '';
      if (downloadUrl.isNotEmpty) {
        if (downloadUrl.startsWith('/') && host.isNotEmpty) {
          String normalizedHost = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            if (host.contains('localhost') ||
                host.startsWith('127.0.0.1') ||
                host.startsWith('192.168.')) {
              normalizedHost = 'http://$host';
            } else {
              normalizedHost = 'https://$host';
            }
          }
          downloadUrl = '$normalizedHost$downloadUrl';
        }
        if (token.isNotEmpty && !downloadUrl.contains('token=')) {
          downloadUrl += downloadUrl.contains('?')
              ? '&token=$token'
              : '?token=$token';
        }
      } else if (host.isNotEmpty && file.hash != null) {
        String normalizedHost = host;
        if (!host.startsWith('http://') && !host.startsWith('https://')) {
          if (host.contains('localhost') ||
              host.startsWith('127.0.0.1') ||
              host.startsWith('192.168.')) {
            normalizedHost = 'http://$host';
          } else {
            normalizedHost = 'https://$host';
          }
        }
        downloadUrl =
            '$normalizedHost/api/media/download/${file.hash}/${Uri.encodeComponent(file.title)}?token=$token';
      }

      await downloadService.addTask(
        workId: widget.work.id,
        workTitle: widget.work.title,
        fileName: fullFileName,
        downloadUrl: downloadUrl,
        hash: file.hash,
        totalBytes: file.size,
        workMetadata: workMetadata,
        coverUrl: coverUrl,
      );
    }

    if (mounted) {
      Navigator.of(context).pop();
      SnackBarUtil.showSuccess(
          context,
          S.of(context)
              .addedNFilesToDownloadQueue(selectedFilesWithPaths.length));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final mq = MediaQuery.of(context);
    final s = S.of(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    final files = widget.work.children;
    final hasFiles = files != null && files.isNotEmpty;
    final selectedCount = _treeKey.currentState?.selectedCount ?? 0;

    if (isLandscape) {
      return Dialog(
        child: Container(
          constraints: BoxConstraints(
            maxHeight: mq.size.height * 0.85,
            maxWidth: mq.size.width * 0.75,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildHeaderLandscape(theme, s, selectedCount),
              const Divider(height: 1),
              Flexible(
                child: _isCheckingDownloads
                    ? _buildLoadingIndicator(context)
                    : !hasFiles
                        ? _buildEmptyState(context)
                        : FileTreeSelector(
                            key: _treeKey,
                            files: files,
                            downloadedHashes: _downloadedFiles,
                            onSelectionChanged: () => setState(() {}),
                          ),
              ),
            ],
          ),
        ),
      );
    }

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: mq.size.height * 0.8,
          maxWidth: 800,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildHeader(theme, s),
            _buildToolbar(theme, s, selectedCount),
            Flexible(
              child: _isCheckingDownloads
                  ? _buildLoadingIndicator(context)
                  : !hasFiles
                      ? _buildEmptyState(context)
                      : FileTreeSelector(
                          key: _treeKey,
                          files: files,
                          downloadedHashes: _downloadedFiles,
                          onSelectionChanged: () => setState(() {}),
                        ),
            ),
            const Divider(height: 1),
            _buildActions(theme, s, selectedCount),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderLandscape(
      ThemeData theme, S s, int selectedCount) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Icon(Icons.download, color: cs.onPrimaryContainer, size: 20),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.work.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onPrimaryContainer,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!_isCheckingDownloads) ...[
                  const SizedBox(height: 2),
                  Text(
                    s.downloadedAndSelected(
                      _downloadedFiles.length,
                      selectedCount,
                    ),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onPrimaryContainer.withAlpha(179),
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton.icon(
            icon: Icon(Icons.select_all,
                size: 16, color: cs.onPrimaryContainer),
            label: Text(s.selectAll,
                style: TextStyle(color: cs.onPrimaryContainer)),
            onPressed: () => _treeKey.currentState?.toggleSelectAll(),
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: _startDownload,
            icon: const Icon(Icons.download, size: 16),
            label: Text(s.downloadN(selectedCount)),
            style: FilledButton.styleFrom(
              backgroundColor: cs.onPrimaryContainer,
              foregroundColor: cs.primaryContainer,
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.close, size: 20),
            onPressed: () => Navigator.of(context).pop(),
            color: cs.onPrimaryContainer,
            padding: const EdgeInsets.all(8),
            constraints: const BoxConstraints(),
            tooltip: s.close,
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeData theme, S s) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Row(
        children: [
          Icon(Icons.download, color: cs.onPrimaryContainer),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.selectFilesToDownload,
                  style: theme.textTheme.titleLarge?.copyWith(
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.work.title,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onPrimaryContainer.withAlpha(179),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
            color: cs.onPrimaryContainer,
          ),
        ],
      ),
    );
  }

  Widget _buildToolbar(
      ThemeData theme, S s, int selectedCount) {
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.dividerColor)),
      ),
      child: Row(
        children: [
          TextButton.icon(
            icon: const Icon(Icons.select_all, size: 18),
            label: Text(s.selectAll),
            onPressed: () {
              HapticFeedback.lightImpact();
              _treeKey.currentState?.toggleSelectAll();
            },
          ),
          const Spacer(),
          if (!_isCheckingDownloads) ...[
            Text(
              s.downloadedNCount(_downloadedFiles.length),
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.primary),
            ),
            const SizedBox(width: 12),
            Container(
              width: 1,
              height: 12,
              color: theme.dividerColor,
            ),
            const SizedBox(width: 12),
            Text(
              s.selectedNCount(selectedCount),
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurface.withAlpha(153),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActions(
      ThemeData theme, S s, int selectedCount) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              Navigator.of(context).pop();
            },
            child: Text(s.cancel),
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            onPressed: selectedCount > 0 ? _startDownload : null,
            icon: const Icon(Icons.download),
            label: Text(s.downloadN(selectedCount)),
          ),
        ],
      ),
    );
  }

  Widget _buildLoadingIndicator(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: cs.primaryContainer.withValues(alpha: 0.3),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            S.of(context).checkingDownloadedFiles,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.folder_off_rounded,
                size: 32,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).noDownloadableFiles,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}