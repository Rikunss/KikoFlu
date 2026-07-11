import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;

import '../models/work.dart';
import '../services/log_service.dart';
import '../services/download_path_service.dart';
import '../services/download_service.dart';
import '../services/translation_service.dart';
import '../services/subtitle_library_service.dart';
import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/settings_provider.dart';
import '../utils/file_icon_utils.dart';
import '../utils/snackbar_util.dart';
import 'responsive_dialog.dart';
import 'image_gallery_screen.dart';
import 'text_preview_screen.dart';
import 'pdf_preview_screen.dart';
import 'explorer/explorer_helpers.dart';
import 'explorer/explorer_file_tree.dart';
import '../../l10n/app_localizations.dart';

/// 离线文件浏览器 - 显示已下载的文件
/// 只显示硬盘上实际存在的文件，不显示未下载的文件
class OfflineFileExplorerWidget extends ConsumerStatefulWidget {
  final Work work;
  final List<dynamic>? fileTree;

  /// For imported local works — absolute path to the original source folder.
  /// When set, file existence checks and path resolution use this instead of
  /// the download directory work folder.
  final String? localImportPath;

  const OfflineFileExplorerWidget({
    super.key,
    required this.work,
    this.fileTree,
    this.localImportPath,
  });

  @override
  ConsumerState<OfflineFileExplorerWidget> createState() =>
      _OfflineFileExplorerWidgetState();
}

class _OfflineFileExplorerWidgetState
    extends ConsumerState<OfflineFileExplorerWidget> {
  List<dynamic> _localFiles = [];
  final Set<String> _expandedFolders = {};
  final Map<String, bool> _fileExists = {};
  final Set<String> _audioWithLibrarySubtitles = {};
  bool _isLoading = true;
  String? _errorMessage;
  String? _mainFolderPath;
  late final FileListController _fileListController;

  bool _showTranslation = false;
  final Map<String, String> _translationCache = {};
  final Set<String> _translatingItems = {};

  @override
  void initState() {
    super.initState();
    _fileListController = ref.read(fileListControllerProvider.notifier);
    _loadLocalFiles();
  }

  @override
  void dispose() {
    Future.microtask(() => _fileListController.clear());
    super.dispose();
  }

  /// Returns the base directory path for file operations.
  /// For imported works, this is the original source folder.
  /// For downloaded works, this is the work folder in the download directory.
  Future<String> _getWorkBasePath() async {
    if (widget.localImportPath != null &&
        await Directory(widget.localImportPath!).exists()) {
      return widget.localImportPath!;
    }
    final downloadDir = await DownloadPathService.getDownloadDirectory();
    return p.join(downloadDir.path, widget.work.id.toString());
  }

  Future<void> _loadLocalFiles() async {
    if (widget.fileTree == null) {
      setState(() {
        _isLoading = false;
        _errorMessage = S.of(context).noFileTreeInfo;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final basePath = await _getWorkBasePath();
      final workDir = Directory(basePath);

      if (!await workDir.exists()) {
        setState(() {
          _isLoading = false;
          _errorMessage = S.of(context).workFolderNotExist;
        });
        return;
      }

      _localFiles = await _filterLocalFiles(widget.fileTree!, workDir.path, '');
      _fileListController.updateFiles(List<dynamic>.from(_localFiles));

      await _checkLibrarySubtitles();

      _identifyAndExpandMainFolder();

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _errorMessage = S.of(context).loadFilesFailed(e.toString());
      });
    }
  }

  Future<List<dynamic>> _filterLocalFiles(
      List<dynamic> items, String workDirPath, String parentPath) async {
    final List<dynamic> filteredItems = [];

    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final title = _getProperty(item, 'title', defaultValue: 'unknown');
      final hash = _getProperty(item, 'hash');

      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;

        if (children != null && children.isNotEmpty) {
          final folderPath = parentPath.isEmpty ? title : '$parentPath/$title';
          final filteredChildren =
              await _filterLocalFiles(children, workDirPath, folderPath);

          if (filteredChildren.isNotEmpty) {
            if (item is Map<String, dynamic>) {
              final folderCopy = Map<String, dynamic>.from(item);
              folderCopy['children'] = filteredChildren;
              filteredItems.add(folderCopy);
            } else {
              final folderMap = <String, dynamic>{
                'type': 'folder',
                'title': title,
                'children': filteredChildren,
              };
              filteredItems.add(folderMap);
            }
          }
        }
      } else if (hash != null) {
        final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';
        final filePath = '$workDirPath/$relativePath';
        final file = File(filePath);
        final downloadingFile = File('$filePath.downloading');

        if (await file.exists() && !await downloadingFile.exists()) {
          _fileExists[hash] = true;

          String fileType = type;

          if (type == 'file' || type == null || type.isEmpty) {
            fileType = FileIconUtils.inferFileType(title);
          }

          if (item is Map<String, dynamic>) {
            if (item['type'] != fileType) {
              final correctedMap = Map<String, dynamic>.from(item);
              correctedMap['type'] = fileType;
              filteredItems.add(correctedMap);
            } else {
              filteredItems.add(item);
            }
          } else {
            final fileMap = <String, dynamic>{
              'type': fileType,
              'title': title,
              'hash': hash,
              'duration': _getProperty(item, 'duration'),
              'size': _getProperty(item, 'size'),
            };
            filteredItems.add(fileMap);
          }
        }
      }
    }

    return filteredItems;
  }

  dynamic _getProperty(dynamic item, String key, {dynamic defaultValue}) {
    if (item == null) return defaultValue;

    if (item is Map) {
      return item[key] ?? defaultValue;
    } else {
      try {
        switch (key) {
          case 'type':
            return (item as dynamic).type ?? defaultValue;
          case 'title':
            return (item as dynamic).title ?? defaultValue;
          case 'name':
            return (item as dynamic).title ?? defaultValue;
          case 'hash':
            return (item as dynamic).hash ?? defaultValue;
          case 'children':
            return (item as dynamic).children ?? defaultValue;
          case 'size':
            return (item as dynamic).size ?? defaultValue;
          case 'mediaType':
            return (item as dynamic).type ?? defaultValue;
          case 'duration':
            return (item as dynamic).duration ?? defaultValue;
          default:
            return defaultValue;
        }
      } catch (e) {
        return defaultValue;
      }
    }
  }

  Future<void> _checkLibrarySubtitles() async {
    final items = _localFiles.whereType<Map<String, dynamic>>().toList();
    _audioWithLibrarySubtitles.addAll(await checkLibrarySubtitles(
      workId: widget.work.id,
      items: items,
      getTitle: (item) => item['title'] as String? ?? item['name'] as String? ?? '',
    ));
    if (mounted) setState(() {});
  }

  void _identifyAndExpandMainFolder() {
    if (_localFiles.isEmpty) return;

    final rootHasAudio = _localFiles.any((item) =>
        item is Map<String, dynamic> && FileIconUtils.isAudioFile(item));
    if (rootHasAudio) {
      _mainFolderPath = '';
      return;
    }

    final Map<String, Map<String, dynamic>> folderStats = {};

    void analyzeFolders(List<dynamic> items, String parentPath) {
      for (final item in items) {
        if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null && children.isNotEmpty) {
            final itemPath = _getItemPath(parentPath, item);

            final stats = _countFilesInFolder(children);
            folderStats[itemPath] = {
              'audioCount': stats['audioCount'],
              'textCount': stats['textCount'],
              'item': item,
            };

            analyzeFolders(children, itemPath);
          }
        }
      }
    }

    analyzeFolders(_localFiles, '');

    if (folderStats.isEmpty) {
      _mainFolderPath = null;
      return;
    }

    int maxAudioCount = 0;
    for (final stats in folderStats.values) {
      if (stats['audioCount'] > maxAudioCount) {
        maxAudioCount = stats['audioCount'];
      }
    }

    String? mainFolder;
    int maxTextCount = -1;
    List<String> candidateFolders = [];

    for (final entry in folderStats.entries) {
      if (entry.value['audioCount'] == maxAudioCount) {
        final textCount = entry.value['textCount'] as int;
        if (textCount > maxTextCount) {
          maxTextCount = textCount;
          candidateFolders = [entry.key];
        } else if (textCount == maxTextCount) {
          candidateFolders.add(entry.key);
        }
      }
    }

    if (candidateFolders.length > 1) {
      final formatPreference = ref.read(audioFormatPreferenceProvider);
      mainFolder = _selectByAudioFormatPreference(
          candidateFolders, formatPreference.priority);
    } else if (candidateFolders.isNotEmpty) {
      mainFolder = candidateFolders.first;
    }

    if (mainFolder != null) {
      _mainFolderPath = mainFolder;
      _expandPathToFolder(mainFolder);
      LogService.instance.debug(
          '[OfflineFileExplorer] 识别到主文件夹 $_mainFolderPath (音频:$maxAudioCount, 文本:$maxTextCount)', tag: 'UI');
    }
  }

  Map<String, int> _countFilesInFolder(List<dynamic> items) {
    int audioCount = 0;
    int textCount = 0;

    for (final child in items) {
      if (child is Map<String, dynamic> && FileIconUtils.isAudioFile(child)) {
        audioCount++;

        final audioTitle = _getProperty(child, 'title', defaultValue: '');
        if (_audioWithLibrarySubtitles.contains(audioTitle)) {
          textCount++;
        }
      } else if (FileIconUtils.isTextFile(child)) {
        textCount++;
      }
    }

    return {'audioCount': audioCount, 'textCount': textCount};
  }

  String _selectByAudioFormatPreference(
      List<String> folderPaths, List<AudioFormat> priorityOrder) {
    Map<String, int> folderPriorities = {};

    for (final folderPath in folderPaths) {
      final folderChildren = _findFolderChildren(folderPath);
      int highestPriority = priorityOrder.length;

      for (final child in folderChildren) {
        if (child is Map<String, dynamic> && FileIconUtils.isAudioFile(child)) {
          final fileName =
              _getProperty(child, 'title', defaultValue: '').toLowerCase();
          for (int i = 0; i < priorityOrder.length; i++) {
            final format = priorityOrder[i];
            if (fileName.endsWith('.${format.extension}')) {
              if (i < highestPriority) {
                highestPriority = i;
              }
              break;
            }
          }
        }
      }

      folderPriorities[folderPath] = highestPriority;
    }

    String selectedFolder = folderPaths.first;
    int bestPriority = folderPriorities[selectedFolder]!;

    for (final folderPath in folderPaths) {
      final priority = folderPriorities[folderPath]!;
      if (priority < bestPriority) {
        bestPriority = priority;
        selectedFolder = folderPath;
      }
    }

    return selectedFolder;
  }

  List<dynamic> _findFolderChildren(String targetPath) {
    final segments = targetPath.split('/');
    List<dynamic> currentItems = _localFiles;

    for (final segment in segments) {
      bool found = false;
      for (final item in currentItems) {
        final title = _getProperty(item, 'title', defaultValue: '');
        if (title == segment &&
            _getProperty(item, 'type', defaultValue: '') == 'folder') {
          currentItems = _getProperty(item, 'children') as List<dynamic>? ?? [];
          found = true;
          break;
        }
      }
      if (!found) {
        return [];
      }
    }

    return currentItems;
  }

  void _expandPathToFolder(String targetPath) {
    final segments = targetPath.split('/');
    String currentPath = '';

    for (int i = 0; i < segments.length; i++) {
      if (i == 0) {
        currentPath = segments[i];
      } else {
        currentPath = '$currentPath/${segments[i]}';
      }

      if (!_expandedFolders.contains(currentPath)) {
        _expandedFolders.add(currentPath);
      }
    }
  }

  String _getItemPath(String parentPath, dynamic item) {
    final title = _getProperty(item, 'title', defaultValue: 'unknown');
    return parentPath.isEmpty ? title : '$parentPath/$title';
  }

  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  String _formatFileSize(int? bytes) {
    if (bytes == null || bytes <= 0) return '';

    const units = ['B', 'KB', 'MB', 'GB'];
    int unitIndex = 0;
    double size = bytes.toDouble();

    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex++;
    }

    if (unitIndex == 0) {
      return '$bytes B';
    } else {
      return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
    }
  }

  Future<int?> _getFileSize(dynamic item, String parentPath) async {
    final metaSize = _getProperty(item, 'size');
    if (metaSize != null && metaSize is int && metaSize > 0) {
      return metaSize;
    }

    final title = _getProperty(item, 'title', defaultValue: '');

    try {
      final basePath = await _getWorkBasePath();
      final filePath = parentPath.isEmpty
          ? p.join(basePath, title)
          : p.join(basePath, parentPath, title);
      final file = File(filePath);

      if (await file.exists()) {
        return await file.length();
      }
    } catch (e) {
    }

    return null;
  }

  Future<void> _playAudioFile(dynamic audioFile, String parentPath) async {
    final hash = _getProperty(audioFile, 'hash');
    final unknownLabel = S.of(context).unknown;
    final title = _getProperty(audioFile, 'title', defaultValue: unknownLabel);

    if (hash == null) {
      SnackBarUtil.showError(context, S.of(context).cannotPlayAudioMissingId);
      return;
    }

    final basePath = await _getWorkBasePath();
    final localPath = parentPath.isEmpty
        ? p.join(basePath, title)
        : p.join(basePath, parentPath, title);
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).audioFileNotExist);
      return;
    }

    String? coverUrl;
    try {
      final metadataFile = File(p.join(basePath, 'work_metadata.json'));
      if (await metadataFile.exists()) {
        try {
          final content = await metadataFile.readAsString();
          // ignore: avoid_dynamic_calls
          final json = (jsonDecode(content) as Map<String, dynamic>);
          final relPath = json['localCoverPath'] as String?;
          if (relPath != null && relPath.isNotEmpty) {
            final coverFile = File(p.join(basePath, relPath));
            if (await coverFile.exists()) {
              coverUrl = 'file://${coverFile.path}';
            }
          }
        } catch (e) {
          LogService.instance.warning('[OfflineFileExplorer] Failed to find cover image: $e', tag: 'OfflineFileExplorer');
        }
      }

      if (coverUrl == null) {
        final coverFile = File(p.join(basePath, 'cover.jpg'));
        if (await coverFile.exists()) {
          coverUrl = 'file://${coverFile.path}';
        }
      }

      if (coverUrl == null) {
        final dir = Directory(basePath);
        if (await dir.exists()) {
          final entries = await dir.list(recursive: true).toList();
          entries.sort((a, b) {
            final aN = a.path.split(Platform.pathSeparator).last;
            final bN = b.path.split(Platform.pathSeparator).last;
            return aN.toLowerCase().compareTo(bN.toLowerCase());
          });
          for (final entry in entries) {
            if (entry is! File) continue;
            final lower = entry.path.toLowerCase();
            if (lower.endsWith('.downloading') ||
                lower.endsWith('work_metadata.json')) {
              continue;
            }
            if (lower.endsWith('.jpg') || lower.endsWith('.jpeg') ||
                lower.endsWith('.png') || lower.endsWith('.webp') ||
                lower.endsWith('.bmp')) {
              coverUrl = 'file://${entry.path}';
              break;
            }
          }
        }
      }
    } catch (e) {
    }

    final audioFiles = _getAudioFilesFromSameDirectory(parentPath);

    final currentIndex =
        audioFiles.indexWhere((file) => _getProperty(file, 'hash') == hash);

    if (currentIndex == -1) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotFindAudioFile(title));
      return;
    }

    final List<AudioTrack> audioTracks = [];
    for (final file in audioFiles) {
      final fileHash = _getProperty(file, 'hash');
      final fileTitle = _getProperty(file, 'title', defaultValue: unknownLabel);

      if (fileHash == null) continue;

      final filePath = parentPath.isEmpty
          ? p.join(basePath, fileTitle)
          : p.join(basePath, parentPath, fileTitle);
      final file2 = File(filePath);

      if (await file2.exists()) {
        final audioUrl = 'file://$filePath';

        final vaNames = widget.work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

        audioTracks.add(AudioTrack(
          id: fileHash,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: widget.work.title,
          artworkUrl: coverUrl,
          duration: _getProperty(file, 'duration') != null
              ? Duration(
                  milliseconds: (_getProperty(file, 'duration') * 1000).round())
              : null,
          workId: widget.work.id,
          hash: fileHash,
        ));
      }
    }

    if (audioTracks.isEmpty) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).noPlayableAudioFiles);
      return;
    }

    final adjustedIndex = audioTracks.indexWhere((track) => track.hash == hash);
    final startIndex = adjustedIndex != -1 ? adjustedIndex : 0;

    ref.read(audioPlayerControllerProvider.notifier).playTracks(
          audioTracks,
          startIndex: startIndex,
          work: widget.work,
        );
  }

  List<dynamic> _getAudioFilesFromSameDirectory(String targetPath) {
    final List<dynamic> audioFiles = [];

    if (targetPath.isEmpty) {
      for (final item in _localFiles) {
        if (item is Map<String, dynamic> && FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
      return audioFiles;
    }

    List<dynamic>? findFolderByPath(List<dynamic> items, String currentPath) {
      for (final item in items) {
        if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final itemPath = _getItemPath(currentPath, item);

          if (itemPath == targetPath) {
            final children = _getProperty(item, 'children') as List<dynamic>?;
            return children;
          }

          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null) {
            final result = findFolderByPath(children, itemPath);
            if (result != null) return result;
          }
        }
      }
      return null;
    }

    final folderContents = findFolderByPath(_localFiles, '');

    if (folderContents != null) {
      for (final item in folderContents) {
        if (item is Map<String, dynamic> && FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
    }

    return audioFiles;
  }

  Future<void> _loadLyricManually(dynamic file) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = _getProperty(file, 'title', defaultValue: S.of(context).unknown);

    final currentTrackAsync = ref.read(currentTrackProvider);
    final currentTrack = currentTrackAsync.value;

    if (currentTrack == null) {
      SnackBarUtil.showError(context, S.of(context).noAudioCannotLoadSubtitle);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: Row(
          children: [
            Icon(
              Icons.subtitles,
              color: cs.primary,
              size: 24,
            ),
            const SizedBox(width: 12),
            Text(S.of(context).loadSubtitle),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                S.of(context).loadSubtitleConfirm,
                style: tt.bodyMedium,
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: cs.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: cs.outlineVariant,
                    width: 1,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.closed_caption,
                          size: 16,
                          color: cs.primary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).subtitleFile,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Icon(
                          Icons.music_note,
                          size: 16,
                          color: cs.secondary,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          S.of(context).currentAudio,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: cs.secondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      currentTrack.title,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: cs.secondaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 16,
                      color: cs.onSecondaryContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        S.of(context).subtitleAutoRestoreNote,
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(S.of(context).confirmLoad),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      await ref.read(lyricControllerProvider.notifier).loadLyricManually(
            file,
            workId: widget.work.id,
          );
      if (!mounted) return;
      SnackBarUtil.showSuccess(context, S.of(context).subtitleLoadSuccess(title));
    } catch (e) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).subtitleLoadFailed(e.toString()));
    }
  }

  Future<void> _previewImageFile(dynamic file) async {
    final unknownLabel = S.of(context).unknown;
    final basePath = await _getWorkBasePath();

    final imageFiles = _getImageFilesFromCurrentDirectory();
    final currentIndex = imageFiles.indexWhere(
        (f) => _getProperty(f, 'hash') == _getProperty(file, 'hash'));

    if (currentIndex == -1) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotFindImageFile);
      return;
    }

    final List<Map<String, String>> imageItems = [];
    for (final f in imageFiles) {
      final hash = _getProperty(f, 'hash', defaultValue: '');
      final title = _getProperty(f, 'title', defaultValue: unknownLabel);

      final filePath = await _findFileFullPath(f, _localFiles, '');
      if (filePath != null) {
        final localPath = p.join(basePath, filePath);
        final localFile = File(localPath);
        if (await localFile.exists()) {
          imageItems
              .add({'url': 'file://$localPath', 'title': title, 'hash': hash});
        }
      }
    }

    if (imageItems.isEmpty) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).noPreviewableImages);
      return;
    }

    final adjustedIndex = imageItems
        .indexWhere((item) => item['hash'] == _getProperty(file, 'hash'));

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageGalleryScreen(
          images: imageItems,
          initialIndex: adjustedIndex != -1 ? adjustedIndex : 0,
          workId: widget.work.id,
        ),
      ),
    );
  }

  List<dynamic> _getImageFilesFromCurrentDirectory() {
    final List<dynamic> imageFiles = [];

    void extractImageFiles(List<dynamic> items) {
      for (final item in items) {
        if (FileIconUtils.isImageFile(item)) {
          imageFiles.add(item);
        } else if (_getProperty(item, 'type', defaultValue: '') == 'folder') {
          final children = _getProperty(item, 'children') as List<dynamic>?;
          if (children != null) {
            extractImageFiles(children);
          }
        }
      }
    }

    if (_localFiles.isNotEmpty) {
      extractImageFiles(_localFiles);
    }

    return imageFiles;
  }

  Future<String?> _findFileFullPath(
      dynamic targetFile, List<dynamic> items, String parentPath) async {
    for (final item in items) {
      final type = _getProperty(item, 'type', defaultValue: '');
      final title = _getProperty(item, 'title', defaultValue: 'unknown');

      if (type == 'folder') {
        final children = _getProperty(item, 'children') as List<dynamic>?;
        if (children != null) {
          final folderPath = parentPath.isEmpty ? title : '$parentPath/$title';
          final result =
              await _findFileFullPath(targetFile, children, folderPath);
          if (result != null) return result;
        }
      } else {
        if (_getProperty(item, 'hash') == _getProperty(targetFile, 'hash')) {
          return parentPath.isEmpty ? title : '$parentPath/$title';
        }
      }
    }
    return null;
  }

  Future<void> _previewTextFile(dynamic file) async {
    final hash = _getProperty(file, 'hash');
    final title = _getProperty(file, 'title', defaultValue: S.of(context).unknown);

    if (hash == null) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotPreviewTextMissingId);
      return;
    }

    final filePath = await _findFileFullPath(file, _localFiles, '');
    if (filePath == null) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotFindFilePath);
      return;
    }

    final basePath = await _getWorkBasePath();
    final localPath = p.join(basePath, filePath);
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).fileNotExist(title));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TextPreviewScreen(
          textUrl: 'file://$localPath',
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  Future<void> _previewPdfFile(dynamic file) async {
    final hash = _getProperty(file, 'hash');
    final title = _getProperty(file, 'title', defaultValue: S.of(context).unknown);

    if (hash == null) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotPreviewPdfMissingId);
      return;
    }

    final filePath = await _findFileFullPath(file, _localFiles, '');
    if (filePath == null) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotFindFilePath);
      return;
    }

    final basePath = await _getWorkBasePath();
    final localPath = p.join(basePath, filePath);
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).fileNotExist(title));
      return;
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          pdfUrl: 'file://$localPath',
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  Future<void> _playVideoWithSystemPlayer(dynamic videoFile) async {
    final hash = _getProperty(videoFile, 'hash');

    if (hash == null) {
      SnackBarUtil.showError(context, S.of(context).cannotPlayVideoMissingId);
      return;
    }

    final filePath = await _findFileFullPath(videoFile, _localFiles, '');
    if (filePath == null) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).cannotFindFilePath);
      return;
    }

    final basePath = await _getWorkBasePath();
    final localPath = p.join(basePath, filePath);
    final localFile = File(localPath);

    if (!await localFile.exists()) {
      if (!mounted) return;
      SnackBarUtil.showError(context, S.of(context).videoFileNotExist);
      return;
    }

    try {
      final result = await OpenFilex.open(localPath);

      if (result.type != ResultType.done) {
        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => ResponsiveAlertDialog(
              title: Text(S.of(context).cannotOpenVideo),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.of(context).errorInfo(result.message)),
                    const SizedBox(height: 12),
                    Text(S.of(context).noVideoPlayerFound),
                    const SizedBox(height: 8),
                    Text(S.of(context).installVideoPlayerApp),
                    const SizedBox(height: 12),
                    Text(S.of(context).filePathLabel),
                    SelectableText(localPath,
                        style: const TextStyle(fontSize: 12)),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.of(context).close),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, S.of(context).openVideoFileError(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return _buildFileList();
  }

  Widget _buildFileList() {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              style: const TextStyle(color: Colors.red),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadLocalFiles,
              child: Text(S.of(context).retry),
            ),
          ],
        ),
      );
    }

    if (_localFiles.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.folder_open, size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(
              S.of(context).noDownloadedFiles,
              style: const TextStyle(color: Colors.grey),
            ),
          ],
        ),
      );
    }

    final rootItems = _localFiles.whereType<Map<String, dynamic>>().toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: theme.dividerColor,
                  width: 1,
                ),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    S.of(context).offlineFiles,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: () {
                      setState(() {
                        _showTranslation = !_showTranslation;
                      });
                    },
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: _showTranslation
                              ? colorScheme.primary.withValues(alpha: 0.3)
                              : colorScheme.onSurface.withValues(alpha: 0.2),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.g_translate,
                            size: 16,
                            color: _showTranslation
                                ? colorScheme.primary
                                : colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _showTranslation ? S.of(context).translationOriginal : S.of(context).translationTranslated,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: _showTranslation
                                  ? colorScheme.primary
                                  : colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          ExplorerFileTree(
            items: rootItems,
            expandedFolders: _expandedFolders,
            audioWithLibrarySubtitles: _audioWithLibrarySubtitles,
            displayNameTransform: (name) => _getDisplayName(name),
            getTitle: (item) => _getProperty(item, 'title', defaultValue: S.of(context).unknown)!,
            onToggle: (path) => setState(() => toggleFolder(_expandedFolders, path)),
            onTapFile: (item, parentPath) => _handleFileTap(item, _getDisplayName(item['title'] as String? ?? item['name'] as String? ?? S.of(context).unknown), parentPath),
            onPlayAudio: (item, parentPath) => _playAudioFile(item, parentPath),
            onPlayVideo: (item, parentPath) => _playVideoWithSystemPlayer(item),
            onPreviewImage: (item) => _previewImageFile(item),
            onPreviewText: (item) => _previewTextFile(item),
            onPreviewPdf: (item) => _previewPdfFile(item),
            onLoadSubtitle: (item) => _loadLyricManually(item),
            onDelete: (item, parentPath) => _deleteFile(item, parentPath),
            onItemRendered: (name) {
              if (_showTranslation &&
                  !_translationCache.containsKey(name) &&
                  !_translatingItems.contains(name)) {
                _translateItem(name);
              }
            },
            fileSizeFuture: (item, parentPath) => _getFileSize(item, parentPath),
          ),
        ],
      ),
    );
  }

  String _getDisplayName(String originalName) {
    if (_showTranslation && _translationCache.containsKey(originalName)) {
      return _translationCache[originalName]!;
    }
    return originalName;
  }

  Future<void> _translateItem(String originalName) async {
    if (_translationCache.containsKey(originalName) ||
        _translatingItems.contains(originalName)) {
      return;
    }

    setState(() {
      _translatingItems.add(originalName);
    });

    try {
      final translationService = TranslationService();
      final translated = await translationService.translate(
        originalName,
        sourceLang: 'ja',
      );

      setState(() {
        _translationCache[originalName] = translated;
        _translatingItems.remove(originalName);
      });
    } catch (e) {
      LogService.instance.warning('[OfflineFileExplorer] 翻译失败: $e', tag: 'UI');
      setState(() {
        _translatingItems.remove(originalName);
      });
    }
  }

  void _handleFileTap(dynamic file, String title, String parentPath) {
    if (FileIconUtils.isAudioFile(file)) {
      _playAudioFile(file, parentPath);
    } else if (FileIconUtils.isVideoFile(file)) {
      _playVideoWithSystemPlayer(file);
    } else if (FileIconUtils.isImageFile(file)) {
      _previewImageFile(file);
    } else if (FileIconUtils.isPdfFile(file)) {
      _previewPdfFile(file);
    } else if (FileIconUtils.isTextFile(file)) {
      _previewTextFile(file);
    } else {
      SnackBarUtil.showInfo(context, S.of(context).unsupportedFileType(title));
    }
  }

  Future<void> _deleteFile(dynamic file, String parentPath) async {
    if (widget.localImportPath != null) {
      if (!mounted) return;
      SnackBarUtil.showInfo(
        context,
        S.of(context).importedWorkDeleteNotSupported,
      );
      return;
    }

    final title = _getProperty(file, 'title', defaultValue: S.of(context).unknown);
    final relativePath = parentPath.isEmpty ? title : '$parentPath/$title';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: Text(S.of(context).deletionConfirmTitle),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(S.of(context).deleteFilePrompt),
            const SizedBox(height: 12),
            Text(
              relativePath,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: Colors.red,
            ),
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      if (mounted) {
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (context) => const Center(
            child: CircularProgressIndicator(),
          ),
        );
      }

      await DownloadService.instance.deleteFile(widget.work.id, relativePath);

      if (mounted) {
        Navigator.of(context).pop();
      }

      await _loadLocalFiles();

      if (mounted) {
        SnackBarUtil.showSuccess(context, S.of(context).deletedItem(title));
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
      }

      if (mounted) {
        SnackBarUtil.showError(context, S.of(context).deleteFailedWithError(e.toString()));
      }
    }
  }
}