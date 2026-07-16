import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path/path.dart' as p;
import '../services/log_service.dart';

import '../../l10n/app_localizations.dart';
import '../models/work.dart';
import '../models/audio_track.dart';
import '../models/download_task.dart';
import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/settings_provider.dart';
import '../services/download_service.dart';
import '../services/cache_service.dart';
import '../services/translation_service.dart';
import '../utils/file_icon_utils.dart';
import '../utils/snackbar_util.dart';
import 'responsive_dialog.dart';
import 'image_gallery_screen.dart';
import 'text_preview_screen.dart';
import 'pdf_preview_screen.dart';
import 'explorer/explorer_helpers.dart';
import 'explorer/explorer_file_tree.dart';

class FileExplorerWidget extends ConsumerStatefulWidget {
  final Work work;

  const FileExplorerWidget({
    super.key,
    required this.work,
  });

  @override
  ConsumerState<FileExplorerWidget> createState() => _FileExplorerWidgetState();
}

class _FileExplorerWidgetState extends ConsumerState<FileExplorerWidget> {
  List<dynamic> _rootFiles = [];
  final Set<String> _expandedFolders = {};
  final Map<String, bool> _downloadedFiles = {};
  final Map<String, String> _fileRelativePaths = {};
  final Set<String> _audioWithLibrarySubtitles = {};
  bool _isLoading = false;
  String? _errorMessage;
  String? _mainFolderPath;
  ScaffoldMessengerState? _scaffoldMessenger;
  StreamSubscription<List<DownloadTask>>? _downloadTasksSubscription;

  bool _isTranslating = false;
  bool _showTranslation = false;
  String _translationProgress = '';
  final Map<String, String> _translationCache = {};

  @override
  void initState() {
    super.initState();
    _loadWorkTree();
    _listenToDownloadTasks();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _scaffoldMessenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    _downloadTasksSubscription?.cancel();
    _scaffoldMessenger = null;
    super.dispose();
  }

  void _listenToDownloadTasks() {
    final downloadService = DownloadService.instance;
    _downloadTasksSubscription = downloadService.tasksStream.listen((tasks) {
      final workTasks = tasks.where((t) => t.workId == widget.work.id).toList();

      if (workTasks.isNotEmpty) {
        _checkDownloadedFiles();
      }
    });
  }

  Future<void> _loadWorkTree() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final files = await apiService.getWorkTracks(widget.work.id);

      setState(() {
        _rootFiles = files;
        _isLoading = false;
      });

      _checkDownloadedFiles();

      await _checkLibrarySubtitles();

      setState(() {
        _identifyAndExpandMainFolder();
      });
    } catch (e) {
      setState(() {
        _errorMessage = S.of(context).loadFilesFailed(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _checkDownloadedFiles() async {
    final downloadService = DownloadService.instance;
    _downloadedFiles.clear();
    _fileRelativePaths.clear();

    void collectHashes(List<dynamic> items, String parentPath) {
      for (final item in items) {
        final type = item['type'] ?? '';
        if (type != 'folder' && item['hash'] != null) {
          _downloadedFiles[item['hash']] = false;
          final title = item['title'] ?? item['name'] ?? 'unknown';
          final relativePath =
              parentPath.isEmpty ? title : '$parentPath/$title';
          _fileRelativePaths[item['hash']] = relativePath;
        }
        final children = item['children'] as List<dynamic>?;
        if (children != null && type == 'folder') {
          final folderName = item['title'] ?? item['name'] ?? '';
          final nextPath =
              parentPath.isEmpty ? folderName : '$parentPath/$folderName';
          collectHashes(children, nextPath);
        } else if (children != null) {
          collectHashes(children, parentPath);
        }
      }
    }

    collectHashes(_rootFiles, '');

    final hashesToCheck = List<String>.from(_downloadedFiles.keys);

    for (final hash in hashesToCheck) {
      final filePath =
          await downloadService.getDownloadedFilePath(widget.work.id, hash);
      if (filePath != null) {
        _downloadedFiles[hash] = true;
        continue;
      }

      final relativePath = _fileRelativePaths[hash];
      if (relativePath != null) {
        final downloadDir = await downloadService.getDownloadDirectory();
        final localFile = File(
            p.join(downloadDir.path, widget.work.id.toString(), relativePath));
        if (await localFile.exists()) {
          _downloadedFiles[hash] = true;
        }
      }
    }

    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _checkLibrarySubtitles() async {
    final items = _rootFiles.whereType<Map<String, dynamic>>().toList();
    _audioWithLibrarySubtitles.addAll(await checkLibrarySubtitles(
      workId: widget.work.id,
      items: items,
      getTitle: (item) => item['title'] as String? ?? item['name'] as String? ?? '',
    ));
    if (mounted) setState(() {});
  }

  void _identifyAndExpandMainFolder() {
    if (_rootFiles.isEmpty) return;

    final rootHasAudio =
        _rootFiles.any((item) => FileIconUtils.isAudioFile(item));
    if (rootHasAudio) {
      _mainFolderPath = '';
      return;
    }

    final Map<String, Map<String, dynamic>> folderStats = {};

    void analyzeFolders(List<dynamic> items, String parentPath) {
      for (final item in items) {
        if (item['type'] == 'folder') {
          final children = item['children'] as List<dynamic>?;
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

    analyzeFolders(_rootFiles, '');

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
          '[FileExplorer] 识别到主文件夹 $_mainFolderPath (音频:$maxAudioCount, 文本:$maxTextCount)', tag: 'UI');
    }
  }

  Map<String, int> _countFilesInFolder(List<dynamic> items) {
    int audioCount = 0;
    int textCount = 0;

    for (final child in items) {
      if (FileIconUtils.isAudioFile(child)) {
        audioCount++;

        final audioTitle = child['title'] ?? child['name'] ?? '';
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
        if (FileIconUtils.isAudioFile(child)) {
          final fileName =
              (child['title'] ?? child['name'] ?? '').toLowerCase();
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
    List<dynamic> currentItems = _rootFiles;

    for (final segment in segments) {
      bool found = false;
      for (final item in currentItems) {
        final title = item['title'] ?? item['name'] ?? '';
        if (title == segment && item['type'] == 'folder') {
          currentItems = item['children'] ?? [];
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

  void _toggleFolder(String path) {
    setState(() {
      if (_expandedFolders.contains(path)) {
        _expandedFolders.remove(path);
      } else {
        _expandedFolders.add(path);
      }
    });
  }

  String _getItemPath(String parentPath, dynamic item) {
    final title = item['title'] ?? item['name'] ?? 'unknown';
    return parentPath.isEmpty ? title : '$parentPath/$title';
  }

  String _formatDuration(dynamic durationValue) {
    if (durationValue == null) return '';

    final totalSeconds = durationValue is int
        ? durationValue
        : (durationValue is double ? durationValue.toInt() : 0);

    if (totalSeconds <= 0) return '';

    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }

  void _showSnackBar(SnackBar snackBar) {
    if (!mounted) return;

    final content = snackBar.content;
    String message = '';

    if (content is Text) {
      message = content.data ?? '';
    } else if (content is Row) {
      final children = content.children;
      for (final child in children) {
        if (child is Text) {
          message = child.data ?? '';
          break;
        } else if (child is Expanded) {
          final expandedChild = child.child;
          if (expandedChild is Text) {
            message = expandedChild.data ?? '';
            break;
          }
        }
      }
    }

    if (message.isEmpty) {
      final messenger =
          _scaffoldMessenger ?? ScaffoldMessenger.maybeOf(context);
      messenger?.showSnackBar(snackBar);
      return;
    }

    final backgroundColor = snackBar.backgroundColor;
    final duration = snackBar.duration;

    if (backgroundColor == Colors.red) {
      SnackBarUtil.showError(context, message, duration: duration);
    } else if (backgroundColor == Colors.green) {
      SnackBarUtil.showSuccess(context, message, duration: duration);
    } else if (backgroundColor == Colors.orange) {
      SnackBarUtil.showWarning(context, message, duration: duration);
    } else {
      SnackBarUtil.showInfo(context, message, duration: duration);
    }
  }

  void _playAudioFile(dynamic audioFile, String parentPath) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    String? coverUrl;
    if (host.isNotEmpty) {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      coverUrl = token.isNotEmpty
          ? '$normalizedUrl/api/cover/${widget.work.id}?token=$token'
          : '$normalizedUrl/api/cover/${widget.work.id}';
    }

    final hash = audioFile['hash'];
    final title = audioFile['title'] ?? audioFile['name'] ?? S.of(context).unknown;

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final allFiles = await apiService.getWorkTracks(widget.work.id);
      if (!mounted) return;

      ref.read(fileListControllerProvider.notifier).updateFiles(allFiles);
    } catch (e) {
      LogService.instance.warning('获取完整文件树失败 $e', tag: 'UI');
    }

    final audioFiles = _getAudioFilesFromSameDirectory(parentPath);
    final currentIndex = audioFiles.indexWhere((file) => file['hash'] == hash);

    if (currentIndex == -1) {
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).cannotFindAudioFile(title)),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    final downloadService = DownloadService.instance;
    final List<AudioTrack> audioTracks = [];
    final unknownLabel = S.of(context).unknown;

    for (final file in audioFiles) {
      final fileHash = file['hash'];
      final fileTitle = file['title'] ?? file['name'] ?? unknownLabel;

      String audioUrl = '';
      if (fileHash != null) {
        final localPath = await downloadService.getDownloadedFilePath(
          widget.work.id,
          fileHash,
        );

        if (localPath != null) {
          audioUrl = 'file://$localPath';
          LogService.instance.debug('[FileExplorer] 使用本地下载的音频: $fileHash', tag: 'Playback');
        } else if (_downloadedFiles[fileHash] == true) {
          final relativePath = _fileRelativePaths[fileHash];
          if (relativePath != null) {
            final downloadDir = await downloadService.getDownloadDirectory();
            final localFile = File(p.join(
                downloadDir.path, widget.work.id.toString(), relativePath));
            if (await localFile.exists()) {
              audioUrl = 'file://${localFile.path}';
              LogService.instance.debug('[FileExplorer] 使用手动复制的音频: $fileHash', tag: 'Playback');
            }
          }
        }

        if (audioUrl.isEmpty) {
          final cachedPath = await CacheService.getCachedAudioFile(fileHash);
          if (cachedPath != null) {
            audioUrl = 'file://$cachedPath';
            LogService.instance.debug('[FileExplorer] 使用缓存的音频: $fileHash', tag: 'Playback');
          }
        }
      }

      if (audioUrl.isEmpty) {
        if (file['mediaDownloadUrl'] != null &&
            file['mediaDownloadUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaDownloadUrl'];

          if (audioUrl.startsWith('/') && host.isNotEmpty) {
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
            audioUrl = '$normalizedHost$audioUrl';
          }

          if (token.isNotEmpty && !audioUrl.contains('token=')) {
            if (audioUrl.contains('?')) {
              audioUrl = '$audioUrl&token=$token';
            } else {
              audioUrl = '$audioUrl?token=$token';
            }
          }
        } else if (file['mediaStreamUrl'] != null &&
            file['mediaStreamUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaStreamUrl'];

          if (audioUrl.startsWith('/') && host.isNotEmpty) {
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
            audioUrl = '$normalizedHost$audioUrl';
          }

          if (token.isNotEmpty && !audioUrl.contains('token=')) {
            if (audioUrl.contains('?')) {
              audioUrl = '$audioUrl&token=$token';
            } else {
              audioUrl = '$audioUrl?token=$token';
            }
          }
        } else if (host.isNotEmpty && fileHash != null) {
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          audioUrl = '$normalizedUrl/api/media/stream/$fileHash?token=$token';
        }
      }

      if (audioUrl.isNotEmpty) {
        final vaNames = widget.work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

        audioTracks.add(AudioTrack(
          id: fileHash ?? fileTitle,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: widget.work.title,
          artworkUrl: coverUrl,
          duration: file['duration'] != null
              ? Duration(milliseconds: (file['duration'] * 1000).round())
              : null,
          workId: widget.work.id,
          hash: fileHash,
        ));
      }
    }

    if (audioTracks.isEmpty) {
      if (!mounted) return;
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).noPlayableAudioFiles),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 3),
        ),
      );
      return;
    }

    LogService.instance.debug('播放音频: $title', tag: 'Playback');
    LogService.instance.debug('播放队列包含 ${audioTracks.length} 个文件', tag: 'Playback');

    final adjustedIndex =
        audioTracks.indexWhere((track) => track.id == (hash ?? title));
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
      for (final item in _rootFiles) {
        if (FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
      return audioFiles;
    }

    List<dynamic>? findFolderByPath(List<dynamic> items, String currentPath) {
      for (final item in items) {
        if (item['type'] == 'folder') {
          final itemPath = _getItemPath(currentPath, item);

          if (itemPath == targetPath) {
            return item['children'] as List<dynamic>?;
          }

          if (item['children'] != null) {
            final result = findFolderByPath(item['children'], itemPath);
            if (result != null) return result;
          }
        }
      }
      return null;
    }

    final folderContents = findFolderByPath(_rootFiles, '');
    if (folderContents != null) {
      for (final item in folderContents) {
        if (FileIconUtils.isAudioFile(item)) {
          audioFiles.add(item);
        }
      }
    }

    return audioFiles;
  }

  Future<void> _loadLyricManually(dynamic file) async {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final title = file['title'] ?? file['name'] ?? S.of(context).unknown;

    final currentTrackAsync = ref.read(currentTrackProvider);
    final currentTrack = currentTrackAsync.value;

    if (currentTrack == null) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).noAudioCannotLoadSubtitle),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
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

    _showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Text(S.of(context).loadingSubtitle),
          ],
        ),
        duration: const Duration(seconds: 2),
      ),
    );

    try {
      await ref.read(lyricControllerProvider.notifier).loadLyricManually(
            file,
            workId: widget.work.id,
          );

      if (!mounted) return;
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(S.of(context).subtitleLoadSuccess(title)),
                ),
              ],
            ),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 3),
          ),
        );
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.error, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(S.of(context).subtitleLoadFailed(e.toString())),
                ),
              ],
            ),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    }
  }

  Future<void> _previewImageFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    if (host.isEmpty) {
      _showSnackBar(
              SnackBar(
          content: Text(S.of(context).cannotPreviewImageMissingInfo),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String normalizedUrl = host;
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      normalizedUrl = 'https://$host';
    }

    final imageFiles = _getImageFilesFromCurrentDirectory();
    final currentIndex =
        imageFiles.indexWhere((f) => f['hash'] == file['hash']);

    if (currentIndex == -1) {
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).cannotFindImageFile),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final imageItems = <Map<String, String>>[];

    final unknownLabel2 = S.of(context).unknown;
    for (final f in imageFiles) {
      final hash = f['hash'] ?? '';
      final title = f['title'] ?? f['name'] ?? unknownLabel2;
      String imageUrl;

      final relativePath = _fileRelativePaths[hash];
      if (relativePath != null && _downloadedFiles[hash] == true) {
        try {
          final downloadService = DownloadService.instance;
          final downloadDir = await downloadService.getDownloadDirectory();
          final localPath =
              p.join(downloadDir.path, widget.work.id.toString(), relativePath);
          final localFile = File(localPath);

          if (await localFile.exists()) {
            imageUrl = 'file://$localPath';
          } else {
            imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
          }
        } catch (e) {
          LogService.instance.warning('[FileExplorer] 检查本地图片文件失败: $e', tag: 'UI');
          imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        }
      } else {
        imageUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      }

      imageItems.add({
        'url': imageUrl,
        'title': title,
        'hash': hash,
      });
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ImageGalleryScreen(
          images: imageItems,
          initialIndex: currentIndex,
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
        } else if (item['type'] == 'folder' && item['children'] != null) {
          extractImageFiles(item['children']);
        }
      }
    }

    if (_rootFiles.isNotEmpty) {
      extractImageFiles(_rootFiles);
    }

    return imageFiles;
  }

  Future<void> _previewTextFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = file['hash'];
    final title = file['title'] ?? file['name'] ?? S.of(context).unknown;

    if (hash == null || host.isEmpty) {
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).cannotPreviewTextMissingInfo),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    String textUrl;

    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath = '${downloadDir.path}/${widget.work.id}/$relativePath';
        final localFile = File(localPath);

        if (await localFile.exists()) {
          textUrl = 'file://$localPath';
        } else {
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        }
      } catch (e) {
        LogService.instance.warning('[FileExplorer] 检查本地文本文件失败: $e', tag: 'UI');
        String normalizedUrl = host;
        if (!host.startsWith('http://') && !host.startsWith('https://')) {
          normalizedUrl = 'https://$host';
        }
        textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      }
    } else {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      textUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
    }

    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => TextPreviewScreen(
          textUrl: textUrl,
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  Future<void> _previewPdfFile(dynamic file) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = file['hash'];
    final title = file['title'] ?? file['name'] ?? S.of(context).unknown;

    if (hash == null || host.isEmpty) {
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).cannotPreviewPdfMissingInfo),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath =
            p.join(downloadDir.path, widget.work.id.toString(), relativePath);
        final localFile = File(localPath);

        if (await localFile.exists()) {
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
          return;
        }
      } catch (e) {
        LogService.instance.warning('[FileExplorer] 检查本地PDF文件失败: $e', tag: 'UI');
      }
    }

    String normalizedUrl = host;
    if (!host.startsWith('http://') && !host.startsWith('https://')) {
      normalizedUrl = 'https://$host';
    }
    final pdfUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';

    if (!mounted) return;
    if (!mounted) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PdfPreviewScreen(
          pdfUrl: pdfUrl,
          title: title,
          workId: widget.work.id,
          hash: hash,
        ),
      ),
    );
  }

  Future<void> _playVideoWithSystemPlayer(dynamic videoFile) async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final hash = videoFile['hash'] ?? '';

    if (hash.isEmpty) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).cannotPlayVideoMissingId),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    Uri uri;
    String uriString;

    final relativePath = _fileRelativePaths[hash];
    if (relativePath != null && _downloadedFiles[hash] == true) {
      try {
        final downloadService = DownloadService.instance;
        final downloadDir = await downloadService.getDownloadDirectory();
        final localPath =
            p.join(downloadDir.path, widget.work.id.toString(), relativePath);
        final localFile = File(localPath);

        if (await localFile.exists()) {
          uriString = localPath;
          LogService.instance.debug('[FileExplorer] 使用本地视频文件: $localPath', tag: 'Playback');

          try {
            final result = await OpenFilex.open(localPath);
            if (result.type != ResultType.done) {
              if (mounted) {
                _showSnackBar(
                  SnackBar(
                    content: Text(S.of(context).cannotOpenVideoFile(result.message)),
                    backgroundColor: Colors.orange,
                  ),
                );
              }
            }
          } catch (e) {
            if (mounted) {
              _showSnackBar(
                SnackBar(
                  content: Text(S.of(context).openVideoFileError(e.toString())),
                  backgroundColor: Colors.red,
                ),
              );
            }
          }
          return;
        } else {
          if (host.isEmpty || token.isEmpty) {
            if (mounted) {
              _showSnackBar(
                SnackBar(
                  content: Text(S.of(context).cannotPlayVideoMissingParams),
                  backgroundColor: Colors.red,
                ),
              );
            }
            return;
          }
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
          uri = Uri.parse(videoUrl);
          uriString = videoUrl;
        }
      } catch (e) {
        LogService.instance.warning('[FileExplorer] 检查本地视频文件失败: $e', tag: 'UI');
        if (host.isEmpty || token.isEmpty) {
          if (mounted) {
            _showSnackBar(
              SnackBar(
                content: Text(S.of(context).cannotPlayVideoMissingParams),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        String normalizedUrl = host;
        if (!host.startsWith('http://') && !host.startsWith('https://')) {
          normalizedUrl = 'https://$host';
        }
        final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
        uri = Uri.parse(videoUrl);
        uriString = videoUrl;
      }
    } else {
      if (host.isEmpty || token.isEmpty) {
        if (mounted) {
          _showSnackBar(
            SnackBar(
              content: Text(S.of(context).cannotPlayVideoMissingParams),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      final videoUrl = '$normalizedUrl/api/media/stream/$hash?token=$token';
      uri = Uri.parse(videoUrl);
      uriString = videoUrl;
    }

    try {
      final canLaunch = await canLaunchUrl(uri);

      if (canLaunch) {
        final launched = await launchUrl(
          uri,
          mode: LaunchMode.externalApplication,
        );
        if (!launched && mounted) {
          await launchUrl(
            uri,
            mode: LaunchMode.externalNonBrowserApplication,
          );
        }
      } else {

        if (mounted) {
          showDialog(
            context: context,
            builder: (context) => ResponsiveAlertDialog(
              title: Text(S.of(context).cannotPlayDirectly),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(S.of(context).noVideoPlayerFound),
                    const SizedBox(height: 12),
                    Text(S.of(context).youCan),
                    Text(S.of(context).copyLinkToExternalPlayer),
                    Text(S.of(context).openInBrowserOption),
                    const SizedBox(height: 12),
                    SelectableText(
                      uriString,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(S.of(context).close),
                ),
                TextButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    await launchUrl(uri, mode: LaunchMode.platformDefault);
                  },
                  child: Text(S.of(context).openInBrowserOption),
                ),
              ],
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).playVideoError(e.toString())),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    return _buildFileList(colorScheme, textTheme);
  }

  Widget _buildFileList(ColorScheme colorScheme, TextTheme textTheme) {
    if (_isLoading) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildSkeletonRow(colorScheme, width: 140, height: 16, bottomPadding: 16),
            const Divider(height: 1),
            const SizedBox(height: 12),
            _buildSkeletonRow(colorScheme, width: double.infinity, height: 20, bottomPadding: 12),
            _buildSkeletonRow(colorScheme, width: 200, height: 18, bottomPadding: 12),
            _buildSkeletonRow(colorScheme, width: double.infinity, height: 20, bottomPadding: 12),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _buildSkeletonRow(colorScheme, width: 180, height: 18, bottomPadding: 12),
            ),
            Padding(
              padding: const EdgeInsets.only(left: 24),
              child: _buildSkeletonRow(colorScheme, width: 160, height: 18, bottomPadding: 12),
            ),
            _buildSkeletonRow(colorScheme, width: double.infinity, height: 20, bottomPadding: 12),
            _buildSkeletonRow(colorScheme, width: 120, height: 18, bottomPadding: 0),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                S.of(context).loadFailed,
                style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                style: textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 24),
              FilledButton.tonalIcon(
                onPressed: _loadWorkTree,
                icon: const Icon(Icons.refresh, size: 18),
                label: Text(S.of(context).retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_rootFiles.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.folder_open_rounded,
                  size: 40,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(height: 24),
              Text(
                S.of(context).noFiles,
                style: textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    final rootItems = _rootFiles.whereType<Map<String, dynamic>>().toList();
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  Icons.folder_outlined,
                  size: 20,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _showTranslation
                        ? S.of(context).resourceFilesTranslated(_translationCache.length)
                        : S.of(context).resourceFiles,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                  ),
                ),
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isTranslating ? null : _translateAllNames,
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
                          _isTranslating
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.primary,
                                  ),
                                )
                              : Icon(
                                  Icons.g_translate,
                                  size: 16,
                                  color: _showTranslation
                                      ? colorScheme.primary
                                      : colorScheme.onSurface.withValues(alpha: 0.7),
                                ),
                          if (!_isTranslating) ...[
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
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          const SizedBox(height: 4),
          if (_isTranslating)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    _translationProgress,
                    style: textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ExplorerFileTree(
            items: rootItems,
            expandedFolders: _expandedFolders,
            downloadedFiles: _downloadedFiles,
            audioWithLibrarySubtitles: _audioWithLibrarySubtitles,
            displayNameTransform: (name) => _getDisplayName(name),
            getTitle: (item) => item['title'] as String? ?? item['name'] as String? ?? S.of(context).unknown,
            onToggle: (path) => setState(() => toggleFolder(_expandedFolders, path)),
            onTapFile: (item, parentPath) => _handleFileTap(item, _getDisplayName(item['title'] as String? ?? item['name'] as String? ?? ''), parentPath),
            onPlayAudio: (item, parentPath) => _playAudioFile(item, parentPath),
            onPlayVideo: (item, _) => _playVideoWithSystemPlayer(item),
            onPreviewImage: (item) => _previewImageFile(item),
            onPreviewText: (item) => _previewTextFile(item),
            onPreviewPdf: (item) => _previewPdfFile(item),
            onLoadSubtitle: (item) => _loadLyricManually(item),
          ),
        ],
      ),
    );
  }

  List<String> _collectAllNames(List<dynamic> items) {
    final List<String> names = [];

    void collect(List<dynamic> items) {
      for (final item in items) {
        final title = item['title'] ?? item['name'] ?? '';
        if (title.isNotEmpty && !names.contains(title)) {
          names.add(title);
        }

        if (item['type'] == 'folder' && item['children'] != null) {
          collect(item['children'] as List<dynamic>);
        }
      }
    }

    collect(items);
    return names;
  }

  Future<void> _translateAllNames() async {
    if (_isTranslating) return;

    if (_translationCache.isNotEmpty) {
      setState(() {
        _showTranslation = !_showTranslation;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
      _translationProgress = S.of(context).preparingTranslation;
    });

    try {
      final allNames = _collectAllNames(_rootFiles);

      if (allNames.isEmpty) {
        setState(() {
          _isTranslating = false;
        });
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).noContentToTranslate),
            duration: const Duration(seconds: 2),
          ),
        );
        return;
      }

      const maxChunkSize = 500;
      final List<String> chunks = [];
      String currentChunk = '';

      for (final name in allNames) {
        final separator = currentChunk.isEmpty ? '' : '\n';
        final estimatedLength =
            currentChunk.length + separator.length + name.length;

        if (estimatedLength > maxChunkSize && currentChunk.isNotEmpty) {
          chunks.add(currentChunk);
          currentChunk = name;
        } else {
          currentChunk += separator + name;
        }
      }

      if (currentChunk.isNotEmpty) {
        chunks.add(currentChunk);
      }

      final translationService = TranslationService();
      final List<String> translatedChunks = [];

      for (int i = 0; i < chunks.length; i++) {
        setState(() {
          _translationProgress = S.of(context).translatingProgress(i + 1, chunks.length);
        });

        try {
          final translated = await translationService.translate(
            chunks[i],
            sourceLang: 'ja',
          );
          translatedChunks.add(translated);
        } catch (e) {
          LogService.instance.warning('[FileExplorer] 翻译块 $i 失败: $e', tag: 'UI');
          translatedChunks.add(chunks[i]);
        }

        if (i < chunks.length - 1) {
          await Future.delayed(const Duration(milliseconds: 300));
        }
      }

      final allTranslatedNames = translatedChunks.join('\n').split('\n');

      for (int i = 0;
          i < allNames.length && i < allTranslatedNames.length;
          i++) {
        _translationCache[allNames[i]] = allTranslatedNames[i];
      }

      setState(() {
        _showTranslation = true;
        _isTranslating = false;
        _translationProgress = '';
      });

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).translationComplete(_translationCache.length)),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translationProgress = '';
      });

      if (mounted) {
        _showSnackBar(
          SnackBar(
            content: Text(S.of(context).translationFailed(e.toString())),
          backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  String _getDisplayName(String originalName) {
    if (_showTranslation && _translationCache.containsKey(originalName)) {
      return _translationCache[originalName]!;
    }
    return originalName;
  }

  Widget _buildSkeletonRow(ColorScheme colorScheme, {
    required double width,
    required double height,
    double bottomPadding = 0,
  }) {
    return Padding(
      padding: EdgeInsets.only(bottom: bottomPadding),
      child: TweenAnimationBuilder<double>(
        tween: Tween<double>(begin: 0.3, end: 0.7),
        duration: const Duration(milliseconds: 1000),
        builder: (context, value, child) {
          return Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: value),
              borderRadius: BorderRadius.circular(4),
            ),
          );
        },
      ),
    );
  }

  void _handleFileTap(dynamic file, String title, String parentPath) {
    if (FileIconUtils.isVideoFile(file)) {
      _playVideoWithSystemPlayer(file);
    } else if (FileIconUtils.isAudioFile(file)) {
      _playAudioFile(file, parentPath);
    } else if (FileIconUtils.isImageFile(file)) {
      _previewImageFile(file);
    } else if (FileIconUtils.isPdfFile(file)) {
      _previewPdfFile(file);
    } else if (FileIconUtils.isTextFile(file)) {
      _previewTextFile(file);
    } else {
      _showSnackBar(
        SnackBar(
          content: Text(S.of(context).unsupportedFileTypeWithTitle(title)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }
}