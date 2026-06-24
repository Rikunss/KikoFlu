import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../utils/file_icon_utils.dart';
import 'explorer_file_tree_tile.dart';
import 'explorer_helpers.dart';

/// A recursive file tree widget shared between [FileExplorerWidget]
/// and [OfflineFileExplorerWidget].
///
/// Renders expandable folder/file items with consistent icons, badges,
/// and action buttons. Delegates tap handling to callbacks so each
/// explorer can implement its own URL/path resolution logic.
class ExplorerFileTree extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final Set<String> expandedFolders;
  final String parentPath;
  final int level;
  final Map<String, bool> downloadedFiles;
  final Set<String> audioWithLibrarySubtitles;
  final String Function(String originalName)? displayNameTransform;
  final String Function(Map<String, dynamic> item)? getTitle;

  // Folder toggle
  final void Function(String itemPath)? onToggle;

  // File tap — dispatches to correct action based on type
  final void Function(Map<String, dynamic> item, String parentPath)? onTapFile;

  // Audio playback
  final void Function(Map<String, dynamic> item, String parentPath)? onPlayAudio;
  final void Function(Map<String, dynamic> item, String parentPath)? onPlayVideo;

  // Preview
  final void Function(Map<String, dynamic> item)? onPreviewImage;
  final void Function(Map<String, dynamic> item)? onPreviewText;
  final void Function(Map<String, dynamic> item)? onPreviewPdf;

  // Subtitle
  final void Function(Map<String, dynamic> item)? onLoadSubtitle;

  // Delete (offline only)
  final void Function(Map<String, dynamic> item, String parentPath)? onDelete;

  // Called for each item before rendering — used for on-demand translation
  final void Function(String originalName)? onItemRendered;

  // Duration display
  final String Function(Map<String, dynamic> item)? formatItemDuration;

  // File size display (offline only) — async, returns future
  final Future<int?> Function(Map<String, dynamic> item, String parentPath)? fileSizeFuture;

  const ExplorerFileTree({
    super.key,
    required this.items,
    required this.expandedFolders,
    this.parentPath = '',
    this.level = 0,
    this.downloadedFiles = const {},
    this.audioWithLibrarySubtitles = const {},
    this.displayNameTransform,
    this.getTitle,
    this.onToggle,
    this.onTapFile,
    this.onPlayAudio,
    this.onPlayVideo,
    this.onPreviewImage,
    this.onPreviewText,
    this.onPreviewPdf,
    this.onLoadSubtitle,
    this.onDelete,
    this.onItemRendered,
    this.formatItemDuration,
    this.fileSizeFuture,
  });

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[];
    for (final item in items) {
      tiles.add(_buildTile(context, item));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: tiles,
    );
  }

  Widget _buildTile(BuildContext context, Map<String, dynamic> item) {
    final type = item['type'] as String? ?? '';
    final originalTitle = getTitle?.call(item) ??
        (item['title'] as String? ?? item['name'] as String? ?? S.of(context).unknown);
    final title = displayNameTransform != null
        ? displayNameTransform!(originalTitle)
        : originalTitle;
    final isFolder = type == 'folder';
    final children = (item['children'] as List<dynamic>?)
        ?.cast<Map<String, dynamic>>();
    final itemPath = getItemPath(parentPath, item);
    final isExpanded = expandedFolders.contains(itemPath);
    final hash = item['hash'] as String?;

    // Determine badge states
    final isDownloaded = hash != null && (downloadedFiles[hash] ?? false);
    final hasSubtitle = FileIconUtils.isAudioFile(item) &&
        audioWithLibrarySubtitles.contains(originalTitle);

    // Duration label
    String? durationLabel;
    if (formatItemDuration != null) {
      durationLabel = formatItemDuration!(item);
    } else if ((FileIconUtils.isAudioFile(item) || FileIconUtils.isVideoFile(item)) &&
        item['duration'] != null) {
      durationLabel = formatDuration(item['duration']);
    }

    // Trigger onItemRendered for on-demand translation
    onItemRendered?.call(originalTitle);

    // File size label
    String? fileSizeLabel;
    Future<int?> Function()? tileFileSizeFuture;
    if (fileSizeFuture != null) {
      tileFileSizeFuture = () => fileSizeFuture!(item, parentPath);
    }

    // Children count label
    String? childrenCountLabel;
    if (isFolder && children != null) {
      childrenCountLabel = S.of(context).nItems(children.length);
    }

    // Build tile
    final tile = ExplorerFileTreeTile(
      item: item,
      title: title,
      parentPath: parentPath,
      level: level,
      isExpanded: isExpanded,
      isFolder: isFolder,
      isDownloaded: isDownloaded,
      hasSubtitleMatch: hasSubtitle,
      children: children,
      itemPath: itemPath,
      durationLabel: durationLabel,
      fileSizeFuture: tileFileSizeFuture,
      childrenCountLabel: childrenCountLabel,
      onToggle: () => onToggle?.call(itemPath),
      onTapFile: () => onTapFile?.call(item, parentPath),
      onPlayAudio: () => onPlayAudio?.call(item, parentPath),
      onPlayVideo: () => onPlayVideo?.call(item, parentPath),
      onPreviewImage: () => onPreviewImage?.call(item),
      onPreviewText: () => onPreviewText?.call(item),
      onPreviewPdf: () => onPreviewPdf?.call(item),
      onLoadSubtitle: () => onLoadSubtitle?.call(item),
      onDelete: onDelete != null ? () => onDelete!(item, parentPath) : null,
    );

    // If expanded folder, include children recursively
    if (isFolder && isExpanded && children != null && children.isNotEmpty) {
      final subTree = ExplorerFileTree(
        items: children,
        expandedFolders: expandedFolders,
        parentPath: itemPath,
        level: level + 1,
        downloadedFiles: downloadedFiles,
        audioWithLibrarySubtitles: audioWithLibrarySubtitles,
        displayNameTransform: displayNameTransform,
        getTitle: getTitle,
        onToggle: onToggle,
        onTapFile: onTapFile,
        onPlayAudio: onPlayAudio,
        onPlayVideo: onPlayVideo,
        onPreviewImage: onPreviewImage,
        onPreviewText: onPreviewText,
        onPreviewPdf: onPreviewPdf,
        onLoadSubtitle: onLoadSubtitle,
        onDelete: onDelete,
        formatItemDuration: formatItemDuration,
        fileSizeFuture: fileSizeFuture,
      );
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [tile, subTree],
      );
    }

    return tile;
  }
}
