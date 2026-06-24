import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../l10n/app_localizations.dart';
import '../../utils/file_icon_utils.dart';
import '../../utils/snackbar_util.dart';
import 'explorer_helpers.dart';

/// A single row in the file explorer tree, representing a file or folder.
///
/// Shared between [FileExplorerWidget] and [OfflineFileExplorerWidget].
/// Customizes icons, badges, and action buttons through callbacks.
class ExplorerFileTreeTile extends StatelessWidget {
  final Map<String, dynamic> item;
  final String title;
  final String parentPath;
  final int level;
  final bool isExpanded;
  final bool isFolder;
  final bool isDownloaded;
  final bool hasSubtitleMatch;
  final List<Map<String, dynamic>>? children;
  final String? itemPath;

  // Callbacks
  final VoidCallback? onToggle; // Folder toggle; for files, use the specific action callbacks
  final VoidCallback? onTapFile; // Called when tapping a non-folder item
  final VoidCallback? onPlayAudio;
  final VoidCallback? onPlayVideo;
  final VoidCallback? onPreviewImage;
  final VoidCallback? onPreviewText;
  final VoidCallback? onPreviewPdf;
  final VoidCallback? onLoadSubtitle;
  final VoidCallback? onDelete;
  final String? durationLabel;
  final String? fileSizeLabel;
  final Future<int?> Function()? fileSizeFuture;
  final String? childrenCountLabel;

  const ExplorerFileTreeTile({
    super.key,
    required this.item,
    required this.title,
    required this.parentPath,
    required this.level,
    required this.isExpanded,
    required this.isFolder,
    this.isDownloaded = false,
    this.hasSubtitleMatch = false,
    this.children,
    this.itemPath,
    this.onToggle,
    this.onTapFile,
    this.onPlayAudio,
    this.onPlayVideo,
    this.onPreviewImage,
    this.onPreviewText,
    this.onPreviewPdf,
    this.onLoadSubtitle,
    this.onDelete,
    this.durationLabel,
    this.fileSizeLabel,
    this.fileSizeFuture,
    this.childrenCountLabel,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        if (isFolder) {
          onToggle?.call();
        } else {
          onTapFile?.call();
        }
      },
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: title));
        SnackBarUtil.showSuccess(context, S.of(context).copiedName(title));
      },
      child: Padding(
        padding: EdgeInsets.only(
          left: 8.0 + (level * 20.0),
          right: 8.0,
          top: 8.0,
          bottom: 8.0,
        ),
        child: Row(
          children: [
            // Expand/collapse icon
            if (isFolder)
              Icon(
                isExpanded
                    ? Icons.keyboard_arrow_down
                    : Icons.keyboard_arrow_right,
                size: 20,
              )
            else
              const SizedBox(width: 20),
            const SizedBox(width: 8),
            // File icon with badges
            SizedBox(
              width: 24,
              height: 24,
              child: Stack(
                children: [
                  Icon(
                    FileIconUtils.getFileIconFromMap(item),
                    color: FileIconUtils.getFileIconColorFromMap(item),
                    size: 24,
                  ),
                  // Downloaded badge
                  if (!isFolder && isDownloaded)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_circle,
                          color: Colors.green[600],
                          size: 13,
                        ),
                      ),
                    ),
                  // Subtitle match badge
                  if (hasSubtitleMatch)
                    Positioned(
                      left: 0,
                      top: 0,
                      child: Container(
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.subtitles,
                          color: Colors.blue[600],
                          size: 13,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // File name + metadata
            Expanded(
              child: Opacity(
                opacity: (!isFolder && isDownloaded) ? 0.5 : 1.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w400,
                      ),
                    ),
                    if (durationLabel != null && durationLabel!.isNotEmpty)
                      Text(
                        durationLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (fileSizeLabel != null && fileSizeLabel!.isNotEmpty)
                      Text(
                        fileSizeLabel!,
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (fileSizeFuture != null)
                      FutureBuilder<int?>(
                        future: fileSizeFuture!(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData || snapshot.data == null || snapshot.data! <= 0) {
                            return const SizedBox.shrink();
                          }
                          return Text(
                            formatFileSize(snapshot.data),
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey[600],
                            ),
                          );
                        },
                      ),
                  ],
                ),
              ),
            ),
            // Action buttons
            _buildActions(context),
          ],
        ),
      ),
    );
  }

  Widget _buildActions(BuildContext context) {
    final isAudio = FileIconUtils.isAudioFile(item);
    final isVideo = FileIconUtils.isVideoFile(item);
    final isImage = FileIconUtils.isImageFile(item);
    final isText = FileIconUtils.isTextFile(item);
    final isPdf = FileIconUtils.isPdfFile(item);
    final originalFileName = (item['title'] as String? ?? item['name'] as String? ?? '');
    final isLyric = isText && FileIconUtils.isLyricFile(originalFileName);

    if (isAudio || isVideo) {
      return IconButton(
        onPressed: isVideo ? onPlayVideo : onPlayAudio,
        icon: Icon(
          isVideo ? Icons.video_library : Icons.play_arrow,
          color: isVideo ? Colors.blue : Colors.green,
        ),
        iconSize: 20,
      );
    }

    if (isImage || isText || isPdf) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLyric)
            IconButton(
              onPressed: onLoadSubtitle,
              icon: const Icon(Icons.subtitles),
              color: Colors.orange,
              tooltip: S.of(context).loadAsSubtitle,
              iconSize: 20,
            ),
          IconButton(
            onPressed: () {
              if (isImage) onPreviewImage?.call();
              else if (isPdf) onPreviewPdf?.call();
              else onPreviewText?.call();
            },
            icon: const Icon(Icons.visibility),
            color: Colors.blue,
            tooltip: S.of(context).preview,
            iconSize: 20,
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              icon: const Icon(Icons.delete_outline),
              color: Colors.red.shade400,
              tooltip: S.of(context).delete,
              iconSize: 20,
            ),
        ],
      );
    }

    // For non-file items that might have other actions...
    if (onDelete != null) {
      return IconButton(
        onPressed: onDelete,
        icon: const Icon(Icons.delete_outline),
        color: Colors.red.shade400,
        tooltip: S.of(context).delete,
        iconSize: 20,
      );
    }

    // Folder: show children count
    if (isFolder && children != null) {
      return Text(
        childrenCountLabel ?? S.of(context).nItems(children!.length),
        style: TextStyle(fontSize: 12, color: Colors.grey[600]),
      );
    }

    return const SizedBox.shrink();
  }
}
