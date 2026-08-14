import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import '../utils/file_icon_utils.dart';
import 'analytics_service.dart';
import 'cache_service.dart';
import 'download_conversion_hook.dart';
import 'download_cover_processor.dart';
import 'download_task_persistence.dart';
import 'log_service.dart';
import 'cookie_service.dart';

final _log = LogService.instance;

/// Tracks bytes and time to compute real-time download speed.
class _SpeedTracker {
  int lastBytes;
  int lastTimeMs;
  double speedBytesPerSec;

  _SpeedTracker({required this.lastBytes, required this.lastTimeMs})
      : speedBytesPerSec = 0;

  /// Update with the latest received bytes and compute speed.
  void update(int receivedBytes, int currentTimeMs) {
    final timeDiff = currentTimeMs - lastTimeMs;
    if (timeDiff > 0) {
      final bytesDiff = receivedBytes - lastBytes;
      if (bytesDiff >= 0) {
        speedBytesPerSec = bytesDiff / (timeDiff / 1000.0);
      }
    }
    lastBytes = receivedBytes;
    lastTimeMs = currentTimeMs;
  }
}

/// Orchestrates all download operations.
///
/// Delegates task persistence to [DownloadTaskPersistence], cover processing
/// to [DownloadCoverProcessor], and WAV conversion to [DownloadConversionHook].
/// Owns the download queue (concurrent control, HTTP download via Dio) and
/// local import logic.
class DownloadService {
  static DownloadService? _instance;
  static DownloadService get instance => _instance ??= DownloadService._();

  DownloadService._()
      : persistence = DownloadTaskPersistence(),
        coverProcessor = DownloadCoverProcessor(),
        conversionHook = DownloadConversionHook();

  /// Task data persistence (in-memory list + SharedPreferences + disk sync).
  final DownloadTaskPersistence persistence;

  /// Cover image resizing and processing.
  final DownloadCoverProcessor coverProcessor;

  /// WAV → FLAC/ALAC conversion hook.
  final DownloadConversionHook conversionHook;

  final Map<String, CancelToken> _cancelTokens = {};
  final Map<String, _SpeedTracker> _speedTrackers = {};
  final Dio _dio = Dio();
  final StreamController<String> _resumeEventController =
      StreamController<String>.broadcast();

  int _maxConcurrentDownloads = 1;
  int _activeDownloadCount = 0;
  bool _isProcessingQueue = false;

  /// Stream of task lists.
  Stream<List<DownloadTask>> get tasksStream => persistence.tasksStream;

  /// Stream of conversion events.
  Stream<String> get conversionStream => conversionHook.conversionStream;

  /// Stream of resume events (e.g., when server doesn't support resume).
  Stream<String> get resumeEventStream => _resumeEventController.stream;

  /// Stream of workIds whose covers are being processed.
  Stream<Set<int>> get processingCoversStream =>
      coverProcessor.processingCoversStream;

  /// Current list of tasks.
  List<DownloadTask> get tasks => persistence.tasks;

  /// Number of tasks currently downloading or pending.
  int get activeDownloadCount => persistence.activeDownloadCount;

  /// Whether any tasks are currently downloading.
  bool get hasActiveDownloads => persistence.hasActiveDownloads;

  /// Current max concurrent download limit.
  int get maxConcurrentDownloads => _maxConcurrentDownloads;

  /// Get the real-time download speed (bytes/sec) for a task.
  double getDownloadSpeed(String taskId) =>
      _speedTrackers[taskId]?.speedBytesPerSec ?? 0;

  /// Mark a work's cover as being processed.
  void addProcessingCover(int workId) =>
      coverProcessor.addProcessingCover(workId);

  /// Mark a work's cover processing as complete.
  void removeProcessingCover(int workId) =>
      coverProcessor.removeProcessingCover(workId);

  /// Human-friendly natural sort comparator.
  static int naturalCompare(String a, String b) =>
      DownloadTaskPersistence.naturalCompare(a, b);

  /// Load max concurrent download count from SharedPreferences.
  Future<void> _loadConcurrentSetting() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedValue = prefs.getInt('concurrent_downloads');
      if (savedValue != null && savedValue >= 1 && savedValue <= 10) {
        _maxConcurrentDownloads = savedValue;
      }
    } catch (_) {
      _maxConcurrentDownloads = 1;
    }
  }

  /// Update max concurrent downloads (called from settings UI).
  void setMaxConcurrentDownloads(int count) {
    if (count >= 1 && count <= 10) {
      _maxConcurrentDownloads = count;
    }
  }

  /// Lightweight init: only load tasks from SharedPreferences.
  Future<void> initialize() async {
    await _loadConcurrentSetting();
    await persistence.loadTasks();
    for (final task in persistence.tasks) {
      if (task.status == DownloadStatus.downloading) {
        persistence.updateTask(task.copyWith(status: DownloadStatus.paused),
            immediate: true);
      }
      if (task.status == DownloadStatus.converting) {
        persistence.updateTask(task.copyWith(status: DownloadStatus.completed),
            immediate: true);
      }
    }
  }

  /// Heavy disk scan: sync tasks with filesystem.
  Future<void> syncWithDiskAfterInit() async {
    try {
      await persistence.reloadMetadataFromDisk();
      _log.info('启动后磁盘同步完成', tag: 'Download');
    } catch (e) {
      _log.error('启动后磁盘同步失败: $e', tag: 'Download');
    }
  }

  /// Get the download root directory.
  Future<Directory> getDownloadDirectory() =>
      persistence.getDownloadDirectory();

  /// Get work metadata (from memory first, then disk).
  Future<Map<String, dynamic>?> getWorkMetadata(int workId) =>
      persistence.getWorkMetadata(workId);

  /// Get tasks for a given work.
  Future<List<DownloadTask>> getWorkTasks(int workId) async =>
      persistence.tasksForWork(workId);

  /// Get the file path for a downloaded track.
  Future<String?> getDownloadedFilePath(int workId, String? hash) =>
      persistence.getDownloadedFilePath(workId, hash);

  /// Fully sync tasks with disk.
  Future<void> reloadMetadataFromDisk() =>
      persistence.reloadMetadataFromDisk();

  /// Add a download task. If the file is already cached, imports it
  /// immediately. Otherwise enqueues for download.
  Future<DownloadTask> addTask({
    required int workId,
    required String workTitle,
    required String fileName,
    required String downloadUrl,
    required String? hash,
    int? totalBytes,
    Map<String, dynamic>? workMetadata,
    String? coverUrl,
    String? relativePath,
  }) async {
    final existing = persistence.tasks.firstWhere(
      (t) => t.hash == hash && t.workId == workId,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );
    if (existing.id.isNotEmpty) {
      if (existing.status == DownloadStatus.completed) {
        if (existing.workMetadata == null && workMetadata != null) {
          final updated = existing.copyWith(workMetadata: workMetadata);
          persistence.updateTask(updated, immediate: true);
          unawaited(
              persistence.saveWorkMetadata(workId, workMetadata, coverUrl));
          return updated;
        }
        return existing;
      }
      return existing;
    }

    if (hash != null && hash.isNotEmpty) {
      final cachedFile = await CacheService.getCachedAudioFile(hash);
      if (cachedFile != null) {
        final workDir = await persistence.getWorkDownloadDirectory(workId);
        final targetPath = relativePath != null && relativePath.isNotEmpty
            ? '$workDir/$relativePath/$fileName'
            : '$workDir/$fileName';
        final targetFile = File(targetPath);
        await targetFile.parent.create(recursive: true);
        if (!await targetFile.exists()) {
          await File(cachedFile).copy(targetPath);
        }
        final fullFileName = relativePath != null && relativePath.isNotEmpty
            ? '$relativePath/$fileName'
            : fileName;
        final task = DownloadTask(
          id: hash,
          workId: workId,
          workTitle: workTitle,
          fileName: fullFileName,
          downloadUrl: downloadUrl,
          hash: hash,
          totalBytes: totalBytes ?? await targetFile.length(),
          downloadedBytes: totalBytes ?? await targetFile.length(),
          status: DownloadStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
          workMetadata: workMetadata,
        );
        persistence.addAll([task]);
        await persistence.flush();
        persistence.notifyChanged();
        if (workMetadata != null) {
          unawaited(
              persistence.saveWorkMetadata(workId, workMetadata, coverUrl));
        }
        return task;
      }
    }

    final task = DownloadTask(
      id: hash ?? '${workId}_${DateTime.now().millisecondsSinceEpoch}',
      workId: workId,
      workTitle: workTitle,
      fileName: fileName,
      downloadUrl: downloadUrl,
      hash: hash,
      totalBytes: totalBytes,
      createdAt: DateTime.now(),
      workMetadata: workMetadata,
    );
    persistence.addAll([task]);
    persistence.notifyChanged();
    await persistence.flush();
    if (workMetadata != null) {
      unawaited(persistence.saveWorkMetadata(workId, workMetadata, coverUrl));
    }
    unawaited(_processQueue());
    return task;
  }

  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      final pendingTasks =
          persistence.tasks.where((t) => t.status == DownloadStatus.pending).toList();
      if (pendingTasks.isNotEmpty) {
        _log.debug(
            '调度下载队列: ${pendingTasks.length} 个等待中, $_activeDownloadCount/$_maxConcurrentDownloads 个进行中',
            tag: 'Download');
      }
      for (final task in pendingTasks) {
        if (_activeDownloadCount >= _maxConcurrentDownloads) break;
        _activeDownloadCount++;
        unawaited(_startDownload(task).whenComplete(() {
          _activeDownloadCount--;
          _processQueue();
        }));
      }
    } finally {
      _isProcessingQueue = false;
    }
  }

  Future<void> _startDownload(DownloadTask task) async {
    if (task.status == DownloadStatus.downloading ||
        task.status == DownloadStatus.completed) {
      return;
    }

    _log.info('开始下载: ${task.fileName} (workId: ${task.workId})',
        tag: 'Download');
    persistence.updateTask(task.copyWith(status: DownloadStatus.downloading),
        immediate: true);

    final workDir = await persistence.getWorkDownloadDirectory(task.workId);
    final filePath = '$workDir/${task.fileName}';
    final tempFilePath = '$filePath.downloading';
    final file = File(filePath);
    final tempFile = File(tempFilePath);

    _log.debug('下载路径: filePath=$filePath, tempFile=$tempFilePath',
        tag: 'Download');
    await file.parent.create(recursive: true);

    // Check for existing partial download (resume support)
    int resumeOffset = 0;
    if (await tempFile.exists()) {
      resumeOffset = await tempFile.length();
      if (resumeOffset > 0) {
        _log.info('发现未完成的下载: $resumeOffset bytes, 尝试断点续传',
            tag: 'Download');
      }
    }

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      if (task.hash != null && task.hash!.isNotEmpty) {
        final fileType = task.fileName.split('.').last.toLowerCase();
        final cachedPath = await CacheService.getCachedFileResource(
          workId: task.workId,
          hash: task.hash!,
          fileType: fileType,
        );
        if (cachedPath != null) {
          _log.info('从缓存复制文件: $cachedPath -> $filePath', tag: 'Download');
          final cachedFile = File(cachedPath);
          if (await cachedFile.exists()) {
            await cachedFile.copy(filePath);
            final completedTask = task.copyWith(
              status: DownloadStatus.completed,
              completedAt: DateTime.now(),
              downloadedBytes: await file.length(),
              totalBytes: await file.length(),
            );
            persistence.updateTask(completedTask, immediate: true);
            _cancelTokens.remove(task.id);
            _speedTrackers.remove(task.id);
            return;
          }
        }
      }

      int lastUpdateTime = 0;
      const updateInterval = 500;
      int? firstReportedTotal;

      // Initialize speed tracker for this task
      _speedTrackers[task.id] = _SpeedTracker(
        lastBytes: resumeOffset,
        lastTimeMs: DateTime.now().millisecondsSinceEpoch,
      );

      // Set cookies for all subsequent requests
      _dio.options.headers.addAll(CookieService.serverCookieHeaders);
      _log.info('开始网络下载: ${task.fileName}, url=${task.downloadUrl}',
          tag: 'Download');

      bool resumed = false;
      if (resumeOffset > 0) {
        try {
          final Response<ResponseBody> rs = await _dio.get<ResponseBody>(
            task.downloadUrl,
            options: Options(
              responseType: ResponseType.stream,
              headers: {'Range': 'bytes=$resumeOffset-'},
            ),
            cancelToken: cancelToken,
          );

          if (rs.statusCode == 206) {
            final body = rs.data!;
            final raf = await tempFile.open(mode: FileMode.append);
            try {
              int totalReceived = resumeOffset;
              int? totalSize;
              final contentRange = rs.headers.value('content-range');
              if (contentRange != null) {
                final match =
                    RegExp(r'/(\d+)$').firstMatch(contentRange);
                if (match != null) {
                  totalSize = int.tryParse(match.group(1)!);
                }
              }

              await for (final chunk in body.stream) {
                if (cancelToken.isCancelled) break;
                await raf.writeFrom(chunk);
                totalReceived += chunk.length;

                final now = DateTime.now().millisecondsSinceEpoch;
                _speedTrackers[task.id]?.update(totalReceived, now);

                if (now - lastUpdateTime > updateInterval) {
                  lastUpdateTime = now;
                  persistence.updateTask(task.copyWith(
                    status: DownloadStatus.downloading,
                    downloadedBytes: totalReceived,
                    totalBytes: totalSize ?? totalReceived,
                  ));
                }
              }
              resumed = true;
              _log.info('断点续传完成: ${task.fileName}', tag: 'Download');
            } finally {
              await raf.close();
            }
          } else {
            _log.info(
                '服务器不支持断点续传(status ${rs.statusCode}), 重新下载',
                tag: 'Download');
            _resumeEventController.add(
                'fail:${task.fileName}:Server returned ${rs.statusCode}, not 206');
          }
        } catch (e) {
          if (e is DioException && e.type == DioExceptionType.cancel) {
            rethrow;
          }
          _log.warning('断点续传失败: $e, 重新下载', tag: 'Download');
          _resumeEventController.add(
              'fail:${task.fileName}:$e');
        }

        // If resume didn't work, clean up and fall through to full download
        if (!resumed) {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
          resumeOffset = 0;
        }
      }

      if (!resumed) {
        await _dio.download(
          task.downloadUrl,
          tempFilePath,
          cancelToken: cancelToken,
          onReceiveProgress: (received, total) {
            if (total != -1) {
              if (firstReportedTotal == null) {
                firstReportedTotal = total;
                if (task.totalBytes != null &&
                    task.totalBytes! > 0 &&
                    task.totalBytes != total) {
                  _log.warning(
                    '服务器报告的文件大小($total)与任务记录的大小(${task.totalBytes})不一致: ${task.fileName}',
                    tag: 'Download',
                  );
                }
              } else if (firstReportedTotal != total) {
                _log.warning(
                  '下载过程中文件总大小发生变化: $firstReportedTotal -> $total (${task.fileName})',
                  tag: 'Download',
                );
                firstReportedTotal = total;
              }
              final now = DateTime.now().millisecondsSinceEpoch;

              // Update download speed
              _speedTrackers[task.id]?.update(received, now);

              if (now - lastUpdateTime > updateInterval ||
                  received == total) {
                lastUpdateTime = now;
                persistence.updateTask(task.copyWith(
                  status: DownloadStatus.downloading,
                  downloadedBytes: received,
                  totalBytes: total,
                ));
              }
            }
          },
        );
      }

      await tempFile.rename(filePath);
      _log.info('下载完成: ${task.fileName}', tag: 'Download');

      String? convertedPath;
      if (filePath.toLowerCase().endsWith('.wav')) {
        final result = await conversionHook.convertIfWav(
          filePath: filePath,
          task: task,
          findTask: (id) => persistence.findTaskById(id),
          onUpdate: (t) => persistence.updateTask(t, immediate: true),
        );
        convertedPath = result.convertedPath;
      }

      final currentTask = persistence.findTaskById(task.id);
      var updatedTask = currentTask.copyWith(
        status: DownloadStatus.completed,
        completedAt: DateTime.now(),
      );
      if (convertedPath != null) {
        final convertedFile = File(convertedPath);
        final originalStem = task.fileName.replaceAll(
          RegExp(r'\.wav$', caseSensitive: false), '');
        final newExt = convertedPath.split('.').last;
        final newFileName = '$originalStem.$newExt';
        updatedTask = updatedTask.copyWith(
          fileName: newFileName,
          totalBytes: await convertedFile.length(),
          downloadedBytes: await convertedFile.length(),
        );
      }
      persistence.updateTask(updatedTask, immediate: true);
      unawaited(AnalyticsService.instance.logEvent('download_completed',
          parameters: {
        'work_id': task.workId,
        if (convertedPath != null) 'format': convertedPath.split('.').last,
      }));
      _cancelTokens.remove(task.id);
      _speedTrackers.remove(task.id);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _log.info('下载已取消: ${task.fileName}', tag: 'Download');
        persistence.updateTask(task.copyWith(status: DownloadStatus.paused),
            immediate: true);
      } else if (e is PathNotFoundException) {
        _log.error('路径不存在: ${task.fileName}, filePath=$filePath, error=$e',
            tag: 'Download');
        persistence.updateTask(
            task.copyWith(status: DownloadStatus.failed, error: e.toString()),
            immediate: true);
      } else if (e is FileSystemException) {
        _log.error('文件系统错误: ${task.fileName}, filePath=$filePath, error=$e',
            tag: 'Download');
        persistence.updateTask(
            task.copyWith(status: DownloadStatus.failed, error: e.toString()),
            immediate: true);
      } else if (e is DioException) {
        _log.error(
            '网络错误: ${task.fileName}, type=${e.type}, message=${e.message}, url=${task.downloadUrl}',
            tag: 'Download');
        persistence.updateTask(
            task.copyWith(status: DownloadStatus.failed, error: e.toString()),
            immediate: true);
      } else {
        _log.error('下载失败: ${task.fileName}, error=$e', tag: 'Download');
        persistence.updateTask(
            task.copyWith(status: DownloadStatus.failed, error: e.toString()),
            immediate: true);
      }
      _cancelTokens.remove(task.id);
      _speedTrackers.remove(task.id);
    }
  }

  /// Pause a download task.
  Future<void> pauseTask(String taskId) async {
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
    }
  }

  /// Resume a paused or failed task.
  Future<void> resumeTask(String taskId) async {
    final index = persistence.indexOf(taskId);
    if (index == -1) {
      _log.warning('resumeTask: task not found: $taskId', tag: 'Download');
      return;
    }
    final task = persistence[index];
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      persistence.updateTask(task.copyWith(status: DownloadStatus.pending),
          immediate: true);
      unawaited(_processQueue());
    }
  }

  /// Delete a download task and its file.
  Future<void> deleteTask(String taskId) async {
    final taskIdx = persistence.indexOf(taskId);
    if (taskIdx == -1) {
      _log.warning('deleteTask: task not found: $taskId', tag: 'Download');
      return;
    }
    final task = persistence[taskIdx];
    final workId = task.workId;

    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
      _cancelTokens.remove(taskId);
    }

    if (task.status == DownloadStatus.completed) {
      final workDir = await persistence.getWorkDownloadDirectory(workId);
      final file = File('$workDir/${task.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    persistence.removeWhere((t) => t.id == taskId);

    final remainingTasks = persistence.tasksForWork(workId);
    if (remainingTasks.isEmpty) {
      try {
        final workDir = await persistence.getWorkDownloadDirectory(workId);
        final dir = Directory(workDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          _log.info('已删除作品文件夹: $workDir', tag: 'Download');
        }
      } catch (e) {
        _log.error('删除作品文件夹失败: $e', tag: 'Download');
      }
    }

    persistence.notifyChanged();
    await persistence.flush();
  }

  /// Delete a single file from a work (used in offline detail page).
  Future<void> deleteFile(int workId, String relativePath) async {
    try {
      final workDir = await persistence.getWorkDownloadDirectory(workId);
      final file = File('$workDir/$relativePath');
      if (!await file.exists()) {
        throw Exception('文件不存在');
      }
      await file.delete();
      _log.info('已删除文件: $relativePath', tag: 'Download');

      await _cleanEmptyDirectories(file.parent, workDir);

      persistence.removeWhere((t) =>
          t.workId == workId &&
          t.fileName == relativePath &&
          t.status == DownloadStatus.completed);

      final workDirObj = Directory(workDir);
      if (await workDirObj.exists()) {
        final contents = await workDirObj.list().toList();
        final hasOtherFiles = contents.any((entity) {
          final name = entity.path.split(Platform.pathSeparator).last;
          return name != 'work_metadata.json' && name != 'cover.jpg';
        });
        if (!hasOtherFiles) {
          await workDirObj.delete(recursive: true);
          _log.info('作品文件夹已空，已删除: $workDir', tag: 'Download');
          persistence.removeWhere((t) => t.workId == workId);
        }
      }

      persistence.notifyChanged();
      await persistence.flush();
    } catch (e) {
      _log.error('删除文件失败: $e', tag: 'Download');
      rethrow;
    }
  }

  Future<void> _cleanEmptyDirectories(Directory dir, String workDir) async {
    try {
      if (dir.path == workDir) return;
      final contents = await dir.list().toList();
      if (contents.isEmpty) {
        _log.debug('清理空文件夹: ${dir.path}', tag: 'Download');
        await dir.delete();
        await _cleanEmptyDirectories(dir.parent, workDir);
      }
    } catch (e) {
      _log.error('清理空文件夹失败: $e', tag: 'Download');
    }
  }

  /// Import a local folder as a new work (reference only — no file copy).
  Future<int> importLocalWork({
    required String folderPath,
    required String title,
  }) async {
    final importDir = Directory(folderPath);
    if (!await importDir.exists()) {
      throw Exception('Folder not found: $folderPath');
    }

    int? existingWorkId;
    for (final task in persistence.tasks) {
      final importPath = task.workMetadata?['local_import_path'] as String?;
      if (importPath != null &&
          importPath.replaceAll(Platform.pathSeparator, '/') ==
              folderPath.replaceAll(Platform.pathSeparator, '/')) {
        existingWorkId = task.workId;
        _log.info(
            'Found existing import for same folder, reusing workId=$existingWorkId: $folderPath',
            tag: 'Download');
        break;
      }
    }

    final workId = existingWorkId ?? -DateTime.now().millisecondsSinceEpoch;

    if (existingWorkId != null) {
      persistence.removeWhere((t) => t.workId == existingWorkId);
      persistence.notifyChanged();

      final downloadDir = await persistence.getDownloadDirectory();
      final oldWorkDir = Directory('${downloadDir.path}/$existingWorkId');
      if (await oldWorkDir.exists()) {
        try {
          await oldWorkDir.delete(recursive: true);
          _log.info('Deleted old work directory for re-import: $existingWorkId',
              tag: 'Download');
        } catch (e) {
          _log.warning('Failed to delete old work directory: $e',
              tag: 'Download');
        }
      }
    }

    final downloadDir = await persistence.getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    await workDir.create(recursive: true);

    final List<dynamic> children = [];
    int totalFiles = 0;

    Future<void> scanDir(
        Directory dir, List<dynamic> parentList, String relativePath) async {
      final entities = await dir.list(followLinks: false).toList();
      entities.sort((a, b) {
        final aName = a.path.split(Platform.pathSeparator).last;
        final bName = b.path.split(Platform.pathSeparator).last;
        return naturalCompare(aName, bName);
      });
      for (final entity in entities) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        if (entity is Directory) {
          final subDirChildren = <dynamic>[];
          final subPath = relativePath.isEmpty ? name : '$relativePath/$name';
          await scanDir(entity, subDirChildren, subPath);
          if (subDirChildren.isNotEmpty) {
            parentList.add({
              'type': 'folder',
              'title': name,
              'children': subDirChildren,
            });
          }
        } else if (entity is File) {
          final fileType = FileIconUtils.inferFileType(name);
          if (fileType == 'audio' || fileType == 'image' ||
              fileType == 'text' || fileType == 'pdf') {
            int? fileSize;
            try {
              fileSize = await entity.length();
            } catch (e) {
              LogService.instance.warning('[DownloadService] error: $e', tag: 'Download');
            }
            parentList.add({
              'type': fileType,
              'title': name,
              'hash': 'local_${workId}_$name',
              'size': fileSize,
            });
            totalFiles++;
          }
        }
      }
    }

    await scanDir(importDir, children, '');

    if (children.isEmpty) {
      await workDir.delete(recursive: true);
      throw Exception(
          'No supported audio/image/text files found in the selected folder.');
    }

    final metadata = <String, dynamic>{
      'id': workId,
      'title': title,
      'children': children,
      'local_import_path': folderPath,
    };
    final metadataFile = File('${workDir.path}/work_metadata.json');
    await metadataFile.writeAsString(jsonEncode(metadata));

    _log.info(
        'Imported local work: $title (ID: $workId, $totalFiles files)',
        tag: 'Download');

    int fileIndex = 0;
    void addTaskForFile(dynamic item, String parentPath) {
      final itemType = item['type'] ?? '';
      final fileTitle = item['title'] ?? 'unknown';
      final hash = item['hash'];
      if (itemType == 'folder') {
        final subChildren = item['children'] as List<dynamic>?;
        if (subChildren != null) {
          for (final child in subChildren) {
            addTaskForFile(
                child,
                parentPath.isEmpty
                    ? fileTitle
                    : '$parentPath/$fileTitle');
          }
        }
      } else {
        final fileName = parentPath.isEmpty
            ? fileTitle
            : '$parentPath/$fileTitle';
        persistence.addAll([
          DownloadTask(
            id: hash ?? 'import_${workId}_${fileIndex++}',
            workId: workId,
            workTitle: title,
            fileName: fileName,
            downloadUrl: '',
            hash: hash,
            totalBytes: item['size'] as int?,
            downloadedBytes: item['size'] as int? ?? 0,
            status: DownloadStatus.completed,
            createdAt: DateTime.now(),
            completedAt: DateTime.now(),
            workMetadata: metadata,
          )
        ]);
      }
    }

    for (final child in children) {
      addTaskForFile(child, '');
    }

    await persistence.flush();
    persistence.notifyChanged();

    addProcessingCover(workId);
    coverProcessor.processCoverForImport(
      workId: workId,
      workDirPath: workDir.path,
      importDir: importDir,
      onMetadataUpdated: (meta) {
        for (var i = 0; i < persistence.length; i++) {
          if (persistence[i].workId == workId) {
            persistence[i] = persistence[i].copyWith(workMetadata: meta);
          }
        }
        persistence.notifyChanged();
      },
    );

    return workId;
  }

  /// Import multiple folders (each subfolder becomes one work).
  Future<List<int>> importMultipleLocalWorks({
    required String parentFolderPath,
    void Function(int current, int total, String folderName)? onProgress,
  }) async {
    final parentDir = Directory(parentFolderPath);
    if (!await parentDir.exists()) {
      throw Exception('Folder not found: $parentFolderPath');
    }

    final subDirs = <Directory>[];
    await for (final entity in parentDir.list(followLinks: false)) {
      if (entity is Directory) {
        final name = entity.path.split(Platform.pathSeparator).last;
        if (name.startsWith('.')) continue;
        subDirs.add(entity);
      }
    }

    if (subDirs.isEmpty) {
      throw Exception('No subfolders found in the selected folder.');
    }

    subDirs.sort((a, b) {
      final aName = a.path.split(Platform.pathSeparator).last;
      final bName = b.path.split(Platform.pathSeparator).last;
      return naturalCompare(aName, bName);
    });

    final total = subDirs.length;
    final createdIds = <int>[];
    final errors = <String>[];

    for (int i = 0; i < total; i++) {
      final subDir = subDirs[i];
      final folderName = subDir.path.split(Platform.pathSeparator).last;
      try {
        final workId = await importLocalWork(
          folderPath: subDir.path,
          title: folderName,
        );
        createdIds.add(workId);
      } catch (e) {
        errors.add('$folderName: $e');
      }
      onProgress?.call(i + 1, total, folderName);
    }

    if (errors.isNotEmpty) {
      _log.warning(
        'Import multiple works completed with errors: ${errors.join("; ")}',
        tag: 'Download',
      );
    }

    await persistence.reloadMetadataFromDisk();
    return createdIds;
  }

  /// Dispose all resources.
  Future<void> dispose() async {
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();
    await _resumeEventController.close();
    await persistence.dispose();
    conversionHook.dispose();
    coverProcessor.dispose();
  }
}