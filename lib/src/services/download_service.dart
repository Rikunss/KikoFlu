import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/download_task.dart';
import 'dart:typed_data';
import 'package:image/image.dart' as img;
import '../utils/file_icon_utils.dart';
import 'audio_conversion_service.dart';
import 'cache_service.dart';
import 'conversion_notification_service.dart';
import 'storage_service.dart';
import 'kikoeru_api_service.dart';
import 'download_path_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

class DownloadService {
  static DownloadService? _instance;
  static DownloadService get instance => _instance ??= DownloadService._();

  DownloadService._();

  final Map<String, CancelToken> _cancelTokens = {};
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();
  final StreamController<String> _conversionController =
      StreamController<String>.broadcast();
  final List<DownloadTask> _tasks = [];
  final Dio _dio = Dio();

  // 并发下载控制
  static const int _maxConcurrentDownloads = 20;
  int _activeDownloadCount = 0;
  bool _isProcessingQueue = false;

  // 用于延迟保存任务，避免频繁 I/O 操作
  Timer? _saveTimer;
  bool _needsSave = false;

  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;
  Stream<String> get conversionStream => _conversionController.stream;
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  // 获取正在下载或等待下载的任务数量
  int get activeDownloadCount => _tasks
      .where((task) =>
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.pending)
      .length;

  // 检查是否有任务正在下载
  bool get hasActiveDownloads => activeDownloadCount > 0;

  static const String _tasksKey = 'download_tasks';

  /// Lightweight init: only load tasks from SharedPreferences (no disk scan).
  /// Call [syncWithDiskAfterInit] later from a post-frame callback.
  Future<void> initialize() async {
    await _loadTasks();
    // 恢复未完成的下载任务
    for (final task in _tasks) {
      if (task.status == DownloadStatus.downloading) {
        _updateTask(task.copyWith(status: DownloadStatus.paused));
      }
      // Reset tasks stuck in 'converting' (app was killed mid-conversion)
      if (task.status == DownloadStatus.converting) {
        _updateTask(task.copyWith(status: DownloadStatus.completed));
      }
    }
  }

  /// Heavy disk scan: sync tasks with filesystem. Run this fire-and-forget
  /// after the app is fully initialized to avoid blocking startup.
  Future<void> syncWithDiskAfterInit() async {
    try {
      await reloadMetadataFromDisk();
      _log.info('启动后磁盘同步完成', tag: 'Download');
    } catch (e) {
      _log.error('启动后磁盘同步失败: $e', tag: 'Download');
    }
  }

  Future<Directory> _getDownloadDirectory() async {
    // 使用 DownloadPathService 获取下载目录（支持自定义路径）
    return await DownloadPathService.getDownloadDirectory();
  }

  // 公开方法，用于获取下载根目录
  Future<Directory> getDownloadDirectory() async {
    return _getDownloadDirectory();
  }

  Future<String> _getWorkDownloadDirectory(int workId) async {
    final downloadDir = await _getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir.path;
  }

  // 下载封面图片到本地
  Future<String?> _downloadCoverImage(int workId, String coverUrl) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final coverFile = File('$workDir/cover.jpg');

      // 如果已存在则不重复下载
      if (await coverFile.exists()) {
        return coverFile.path;
      }

      // 下载图片
      _dio.options.headers.addAll(StorageService.serverCookieHeaders);
      await _dio.download(coverUrl, coverFile.path);
      return coverFile.path;
    } catch (e) {
      _log.error('下载封面图片失败: $e', tag: 'Download');
      return null;
    }
  }

  // 保存作品元数据到硬盘（包括下载封面图片）
  Future<void> _saveWorkMetadata(
      int workId, Map<String, dynamic> metadata, String? coverUrl) async {
    try {
      // 先下载封面图片
      if (coverUrl != null && coverUrl.isNotEmpty) {
        final localCoverPath = await _downloadCoverImage(workId, coverUrl);
        if (localCoverPath != null) {
          // 在元数据中只保存相对路径，便于迁移
          metadata['localCoverPath'] = 'cover.jpg';
        }
      }

      final workDir = await _getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');
      final jsonStr = jsonEncode(metadata);
      await metadataFile.writeAsString(jsonStr);
    } catch (e) {
      _log.error('保存作品元数据失败: $e', tag: 'Download');
    }
  }

  // 从硬盘读取作品元数据
  Future<Map<String, dynamic>?> _loadWorkMetadata(int workId) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');

      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;

        // 迁移旧的绝对路径为相对路径
        if (metadata.containsKey('localCoverPath')) {
          final coverPath = metadata['localCoverPath'] as String?;
          if (coverPath != null && coverPath.contains(Platform.pathSeparator)) {
            // 如果包含路径分隔符，说明是绝对路径，转换为相对路径
            metadata['localCoverPath'] = 'cover.jpg';
            // 保存更新后的元数据
            await metadataFile.writeAsString(jsonEncode(metadata));
            _log.info('已迁移作品 $workId 的封面路径为相对路径', tag: 'Download');
          }
        }

        return metadata;
      }
    } catch (e) {
      _log.error('读取作品元数据失败: $e', tag: 'Download');
    }
    return null;
  }

  // 获取作品元数据（公共方法，优先从内存读取，否则从硬盘读取）
  Future<Map<String, dynamic>?> getWorkMetadata(int workId) async {
    // 先尝试从任务中获取
    final task = _tasks.firstWhere(
      (t) => t.workId == workId && t.workMetadata != null,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    if (task.id.isNotEmpty && task.workMetadata != null) {
      return task.workMetadata;
    }

    // 如果内存中没有，从硬盘读取
    return await _loadWorkMetadata(workId);
  }

  // 添加下载任务
  Future<DownloadTask> addTask({
    required int workId,
    required String workTitle,
    required String fileName,
    required String downloadUrl,
    required String? hash,
    int? totalBytes,
    Map<String, dynamic>? workMetadata,
    String? coverUrl,
    String? relativePath, // 相对路径，用于按文件树组织
  }) async {
    // 检查是否已存在
    final existingTask = _tasks.firstWhere(
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

    if (existingTask.id.isNotEmpty) {
      if (existingTask.status == DownloadStatus.completed) {
        // 如果任务已完成但没有元数据，更新元数据
        if (existingTask.workMetadata == null && workMetadata != null) {
          final updatedTask = existingTask.copyWith(workMetadata: workMetadata);
          _updateTask(updatedTask, immediate: true);
          // 保存元数据到硬盘
          unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
          return updatedTask;
        }
        return existingTask;
      }
      // 如果任务存在但未完成，返回现有任务
      return existingTask;
    }

    // 检查缓存中是否已有此文件
    if (hash != null && hash.isNotEmpty) {
      final cachedFile = await CacheService.getCachedAudioFile(hash);
      if (cachedFile != null) {
        // 从缓存移动到下载目录
        final workDir = await _getWorkDownloadDirectory(workId);
        final targetPath = relativePath != null && relativePath.isNotEmpty
            ? '$workDir/$relativePath/$fileName'
            : '$workDir/$fileName';
        final targetFile = File(targetPath);

        // 确保目录存在
        await targetFile.parent.create(recursive: true);

        if (!await targetFile.exists()) {
          await File(cachedFile).copy(targetPath);
        }

        // 使用完整的文件名（包含相对路径），以便后续检测
        final fullFileName = relativePath != null && relativePath.isNotEmpty
            ? '$relativePath/$fileName'
            : fileName;

        final task = DownloadTask(
          id: hash,
          workId: workId,
          workTitle: workTitle,
          fileName: fullFileName, // 使用包含路径的完整文件名
          downloadUrl: downloadUrl,
          hash: hash,
          totalBytes: totalBytes ?? await targetFile.length(),
          downloadedBytes: totalBytes ?? await targetFile.length(),
          status: DownloadStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
          workMetadata: workMetadata,
        );

        _tasks.add(task);
        await _saveTasks();
        _tasksController.add(List.from(_tasks));

        // 保存作品元数据到硬盘
        if (workMetadata != null) {
          unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
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

    _tasks.add(task);
    _tasksController.add(List.from(_tasks));

    // 添加任务后立即保存
    await _saveTasks();

    // 保存作品元数据到硬盘
    if (workMetadata != null) {
      unawaited(_saveWorkMetadata(workId, workMetadata, coverUrl));
    }

    // 自动开始下载（通过队列调度）
    unawaited(_processQueue());

    return task;
  }

  /// 处理下载队列：确保活跃下载数不超过上限
  Future<void> _processQueue() async {
    if (_isProcessingQueue) return;
    _isProcessingQueue = true;
    try {
      // 获取所有等待中的任务
      final pendingTasks =
          _tasks.where((t) => t.status == DownloadStatus.pending).toList();

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
          _processQueue(); // 完成后继续调度
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

    _updateTask(task.copyWith(status: DownloadStatus.downloading),
        immediate: true);

    final workDir = await _getWorkDownloadDirectory(task.workId);
    // 使用fileName中的路径信息（如果包含/）
    final filePath = '$workDir/${task.fileName}';
    final tempFilePath = '$filePath.downloading'; // 临时文件路径
    final file = File(filePath);
    final tempFile = File(tempFilePath);

    _log.debug('下载路径: filePath=$filePath, tempFile=$tempFilePath',
        tag: 'Download');

    // 确保父目录存在
    await file.parent.create(recursive: true);

    final cancelToken = CancelToken();
    _cancelTokens[task.id] = cancelToken;

    try {
      // 先检查缓存中是否已有此文件
      if (task.hash != null && task.hash!.isNotEmpty) {
        final fileType = task.fileName.split('.').last.toLowerCase();
        final cachedPath = await CacheService.getCachedFileResource(
          workId: task.workId,
          hash: task.hash!,
          fileType: fileType,
        );

        if (cachedPath != null) {
          // 缓存存在,直接复制文件
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
            _updateTask(completedTask, immediate: true);
            _cancelTokens.remove(task.id);
            return;
          }
        }
      }

      // 缓存不存在,从网络下载
      // 节流：限制进度更新频率
      int lastUpdateTime = 0;
      const updateInterval = 500; // 500ms 更新一次
      int? firstReportedTotal; // 记录首次收到的total，用于诊断进度跳变

      _dio.options.headers.addAll(StorageService.serverCookieHeaders);

      _log.info('开始网络下载: ${task.fileName}, url=${task.downloadUrl}',
          tag: 'Download');

      // 下载到临时文件，完成后再重命名
      await _dio.download(
        task.downloadUrl,
        tempFilePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total != -1) {
            // 诊断：检测服务器报告的总大小是否变化（可能导致进度条跳变）
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
            // 只在间隔足够时才更新，避免过于频繁的更新
            if (now - lastUpdateTime > updateInterval || received == total) {
              lastUpdateTime = now;
              _updateTask(task.copyWith(
                status: DownloadStatus.downloading,
                downloadedBytes: received,
                totalBytes: total,
              )); // 不立即保存，使用延迟保存
            }
          }
        },
      );

      // 下载完成，重命名临时文件为最终文件
      await tempFile.rename(filePath);

      _log.info('下载完成: ${task.fileName}', tag: 'Download');

      // ── WAV → FLAC/ALAC conversion hook ──
      final isWav = filePath.toLowerCase().endsWith('.wav');
      String? convertedPath;
      if (isWav) {
        try {
          final prefs = await SharedPreferences.getInstance();
          final formatStr = prefs.getString('wav_conversion_format') ?? 'none';
          final format = WavConversionFormat.values.firstWhere(
            (f) => f.value == formatStr,
            orElse: () => WavConversionFormat.none,
          );
          if (format != WavConversionFormat.none) {
            // Update task status to show "Converting..." in the UI
            final currentTask =
                _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);
            _updateTask(currentTask.copyWith(status: DownloadStatus.converting), immediate: true);

            _log.info('开始转换: $filePath → ${format.displayName}', tag: 'Download');
            _conversionController.add('start:${task.fileName}');
            unawaited(ConversionNotificationService.instance.showProgress(
              fileName: task.fileName, progress: 0.0,
            ));
            var lastProgressMs = 0;
            const progressThrottleMs = 200;
            String? currentEta;
            convertedPath = await AudioConversionService.instance.convert(
              filePath, format,
              onProgress: (progress, {eta}) {
                final now = DateTime.now().millisecondsSinceEpoch;
                if (eta != null) currentEta = eta;
                if (now - lastProgressMs > progressThrottleMs || progress >= 1.0) {
                  lastProgressMs = now;
                  final t = _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);
                  _updateTask(t.copyWith(
                    status: DownloadStatus.converting,
                    downloadedBytes: (progress * 100).round(),
                    totalBytes: 100,
                    eta: currentEta,
                  ));
                  unawaited(ConversionNotificationService.instance.showProgress(
                    fileName: task.fileName, progress: progress, eta: currentEta,
                  ));
                }
              },
            );
            if (convertedPath != null) {
              _log.info('转换成功: $convertedPath', tag: 'Download');
              _conversionController.add('success:${format.displayName}:${task.fileName}');
              unawaited(ConversionNotificationService.instance.showCompleted(
                fileName: task.fileName,
                formatName: format.displayName,
              ));
            } else {
              _log.warning('转换失败，保留原始WAV: $filePath', tag: 'Download');
              _conversionController.add('fail:${format.displayName}:${task.fileName}');
              unawaited(ConversionNotificationService.instance.showFailed(
                fileName: task.fileName,
                formatName: format.displayName,
              ));
            }
          }
        } catch (e) {
          _log.error('转换异常: $e', tag: 'Download');
          _conversionController.add('fail:${task.fileName}');
          unawaited(ConversionNotificationService.instance.showFailed(
            fileName: task.fileName,
          ));
          // Reset task status so it doesn't stay stuck in "converting"
          try {
            final stuckTask = _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);
            _updateTask(stuckTask.copyWith(status: DownloadStatus.completed), immediate: true);
          } catch (_) {}
        }
      }

      // 从 _tasks 获取当前版本以保留进度数据
      final currentTask =
          _tasks.firstWhere((t) => t.id == task.id, orElse: () => task);

      // Update task info if conversion changed the file
      var updatedTask = currentTask.copyWith(
        status: DownloadStatus.completed,
        completedAt: DateTime.now(),
      );
      if (convertedPath != null) {
        final convertedFile = File(convertedPath);
        final physicalName = convertedPath.split('/').last;
        _log.info('[Download] Conversion success: $physicalName', tag: 'Download');

        // Preserve relative path from original fileName, just replace extension
        final originalStem = task.fileName.replaceAll(
          RegExp(r'\.wav$', caseSensitive: false), '');
        final newExt = convertedPath.split('.').last;
        final newFileName = '$originalStem.$newExt';
        _log.info('[Download] newFileName=$newFileName', tag: 'Download');
        // Update fileName and totalBytes to reflect converted file
        updatedTask = updatedTask.copyWith(
          fileName: newFileName,
          totalBytes: await convertedFile.length(),
          downloadedBytes: await convertedFile.length(),
        );
      }
      _updateTask(updatedTask, immediate: true); // 完成时立即保存
      _cancelTokens.remove(task.id);
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        _log.info('下载已取消: ${task.fileName}', tag: 'Download');
        _updateTask(task.copyWith(status: DownloadStatus.paused),
            immediate: true);
      } else if (e is PathNotFoundException) {
        _log.error('路径不存在: ${task.fileName}, filePath=$filePath, error=$e',
            tag: 'Download');
        _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: e.toString(),
            ),
            immediate: true);
      } else if (e is FileSystemException) {
        _log.error('文件系统错误: ${task.fileName}, filePath=$filePath, error=$e',
            tag: 'Download');
        _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: e.toString(),
            ),
            immediate: true);
      } else if (e is DioException) {
        _log.error(
            '网络错误: ${task.fileName}, type=${e.type}, message=${e.message}, url=${task.downloadUrl}',
            tag: 'Download');
        _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: e.toString(),
            ),
            immediate: true);
      } else {
        _log.error('下载失败: ${task.fileName}, error=$e', tag: 'Download');
        _updateTask(
            task.copyWith(
              status: DownloadStatus.failed,
              error: e.toString(),
            ),
            immediate: true);
      }
      _cancelTokens.remove(task.id);
    }
  }

  Future<void> pauseTask(String taskId) async {
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
    }
  }

  Future<void> resumeTask(String taskId) async {
    final index = _tasks.indexWhere((t) => t.id == taskId);
    if (index == -1) {
      _log.warning('resumeTask: task not found: $taskId', tag: 'Download');
      return;
    }
    final task = _tasks[index];
    if (task.status == DownloadStatus.paused ||
        task.status == DownloadStatus.failed) {
      _updateTask(task.copyWith(status: DownloadStatus.pending),
          immediate: true);
      unawaited(_processQueue());
    }
  }

  Future<void> deleteTask(String taskId) async {
    final taskIdx = _tasks.indexWhere((t) => t.id == taskId);
    if (taskIdx == -1) {
      _log.warning('deleteTask: task not found: $taskId', tag: 'Download');
      return;
    }
    final task = _tasks[taskIdx];
    final workId = task.workId;

    // 取消下载
    final token = _cancelTokens[taskId];
    if (token != null) {
      token.cancel();
      _cancelTokens.remove(taskId);
    }

    // 删除文件
    if (task.status == DownloadStatus.completed) {
      final workDir = await _getWorkDownloadDirectory(workId);
      final file = File('$workDir/${task.fileName}');
      if (await file.exists()) {
        await file.delete();
      }
    }

    // 从任务列表中移除
    _tasks.removeWhere((t) => t.id == taskId);

    // 检查该作品是否还有其他任务
    final remainingTasks = _tasks.where((t) => t.workId == workId).toList();
    if (remainingTasks.isEmpty) {
      // 如果没有其他任务了，删除整个作品文件夹
      try {
        final workDir = await _getWorkDownloadDirectory(workId);
        final dir = Directory(workDir);
        if (await dir.exists()) {
          await dir.delete(recursive: true);
          _log.info('已删除作品文件夹: $workDir', tag: 'Download');
        }
      } catch (e) {
        _log.error('删除作品文件夹失败: $e', tag: 'Download');
      }
    }

    await _saveTasks();
    _tasksController.add(List.from(_tasks));
  }

  /// 删除单个文件（用于离线详情页）
  /// 删除后会清理空文件夹并同步任务列表
  Future<void> deleteFile(int workId, String relativePath) async {
    try {
      final workDir = await _getWorkDownloadDirectory(workId);
      final file = File('$workDir/$relativePath');

      if (!await file.exists()) {
        throw Exception('文件不存在');
      }

      // 删除文件
      await file.delete();
      _log.info('已删除文件: $relativePath', tag: 'Download');

      // 清理空文件夹
      await _cleanEmptyDirectories(file.parent, workDir);

      // 从任务列表中移除对应的任务
      _tasks.removeWhere((t) =>
          t.workId == workId &&
          t.fileName == relativePath &&
          t.status == DownloadStatus.completed);

      // 检查该作品是否还有其他文件
      final workDirObj = Directory(workDir);
      if (await workDirObj.exists()) {
        final contents = await workDirObj.list().toList();
        // 只剩下 metadata 和 cover 文件时，删除整个作品文件夹
        final hasOtherFiles = contents.any((entity) {
          final name = entity.path.split(Platform.pathSeparator).last;
          return name != 'work_metadata.json' && name != 'cover.jpg';
        });

        if (!hasOtherFiles) {
          await workDirObj.delete(recursive: true);
          _log.info('作品文件夹已空，已删除: $workDir', tag: 'Download');
          // 删除所有相关任务
          _tasks.removeWhere((t) => t.workId == workId);
        }
      }

      await _saveTasks();
      _tasksController.add(List.from(_tasks));
    } catch (e) {
      _log.error('删除文件失败: $e', tag: 'Download');
      rethrow;
    }
  }

  /// 递归清理空文件夹
  Future<void> _cleanEmptyDirectories(Directory dir, String workDir) async {
    try {
      // 不要删除作品根目录
      if (dir.path == workDir) {
        return;
      }

      // 检查目录是否为空
      final contents = await dir.list().toList();
      if (contents.isEmpty) {
        _log.debug('清理空文件夹: ${dir.path}', tag: 'Download');
        await dir.delete();

        // 递归检查父目录
        await _cleanEmptyDirectories(dir.parent, workDir);
      }
    } catch (e) {
      _log.error('清理空文件夹失败: $e', tag: 'Download');
    }
  }

  Future<List<DownloadTask>> getWorkTasks(int workId) async {
    return _tasks.where((t) => t.workId == workId).toList();
  }

  Future<String?> getDownloadedFilePath(int workId, String? hash) async {
    if (hash == null) return null;

    final task = _tasks.firstWhere(
      (t) =>
          t.workId == workId &&
          t.hash == hash &&
          t.status == DownloadStatus.completed,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );

    if (task.id.isEmpty) return null;

    final workDir = await _getWorkDownloadDirectory(workId);
    final file = File('$workDir/${task.fileName}');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  void _updateTask(DownloadTask updatedTask, {bool immediate = false}) {
    final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _tasksController.add(List.from(_tasks));

      // 对于下载进度更新，使用延迟保存避免频繁 I/O
      if (immediate) {
        _saveTasks();
      } else {
        _scheduleDelayedSave();
      }
    }
  }

  // 延迟保存，避免频繁的 I/O 操作
  void _scheduleDelayedSave() {
    _needsSave = true;
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(seconds: 2), () {
      if (_needsSave) {
        _saveTasks();
        _needsSave = false;
      }
    });
  }

  // 升级旧版本的作品文件夹（尝试从 API 获取元数据）
  Future<void> _upgradeOldWorkFolders(Map<int, Directory> workFolders) async {
    for (final entry in workFolders.entries) {
      final workId = entry.key;
      final workDir = entry.value;

      // 检查是否已有元数据文件
      final metadataFile = File('${workDir.path}/work_metadata.json');
      if (await metadataFile.exists()) {
        continue; // 已有元数据，跳过
      }

      _log.info('发现旧版本作品文件夹，尝试升级: RJ$workId', tag: 'Download');

      try {
        // 创建 API 服务实例尝试获取元数据
        final apiService = KikoeruApiService();

        // 获取作品详情
        final workData = await apiService.getWork(workId);

        // 获取文件树
        final tracks = await apiService.getWorkTracks(workId);

        // 将 tracks 转换为 children 格式并添加到 workData
        workData['children'] = tracks;

        // 保存元数据（使用相对路径）
        workData['localCoverPath'] = 'cover.jpg';
        await metadataFile.writeAsString(jsonEncode(workData));
        _log.info('已保存作品元数据: RJ$workId', tag: 'Download');

        // 下载封面（使用高清封面 URL）
        final host = StorageService.getString('server_host') ?? '';
        final token = StorageService.getString('auth_token') ?? '';

        if (host.isNotEmpty) {
          String normalizedHost = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedHost = 'https://$host';
          }

          final coverUrl = token.isNotEmpty
              ? '$normalizedHost/api/cover/$workId?token=$token'
              : '$normalizedHost/api/cover/$workId';

          await _downloadCoverImage(workId, coverUrl);
          _log.info('已下载作品封面: RJ$workId', tag: 'Download');
        }

        // 尝试组织文件树结构
        await _organizeFilesIntoTree(workId, workDir, tracks);

        _log.info('作品升级成功: RJ$workId', tag: 'Download');
      } catch (e) {
        _log.error('升级作品失败 RJ$workId: $e', tag: 'Download');
        // 升级失败不影响继续运行，保持原有文件不变
      }
    }
  }

  // 将扁平的文件结构组织成树形结构
  Future<void> _organizeFilesIntoTree(
      int workId, Directory workDir, List<dynamic> tracks) async {
    try {
      // 构建文件树映射：hash -> 相对路径
      final Map<String, String> hashToPath = {};

      void buildPathMap(List<dynamic> items, String parentPath) {
        for (final item in items) {
          final type = item['type'] as String?;
          final title =
              item['title'] as String? ?? item['name'] as String? ?? '';
          final hash = item['hash'] as String?;

          if (type == 'folder') {
            // 文件夹，递归处理子项
            final folderPath =
                parentPath.isEmpty ? title : '$parentPath/$title';
            final children = item['children'] as List<dynamic>?;
            if (children != null) {
              buildPathMap(children, folderPath);
            }
          } else if (hash != null) {
            // 文件，记录路径映射
            final filePath = parentPath.isEmpty ? title : '$parentPath/$title';
            hashToPath[hash] = filePath;
          }
        }
      }

      buildPathMap(tracks, '');

      // 扫描工作目录中的所有文件
      await for (final entity in workDir.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;

          // 跳过元数据和封面文件
          if (fileName == 'work_metadata.json' || fileName == 'cover.jpg') {
            continue;
          }

          // 尝试从文件树中找到对应的路径
          String? targetPath;
          for (final entry in hashToPath.entries) {
            final expectedFileName = entry.value.split('/').last;
            if (expectedFileName == fileName) {
              targetPath = entry.value;
              break;
            }
          }

          // 如果找到了对应路径且包含目录，则移动文件
          if (targetPath != null && targetPath.contains('/')) {
            final targetFile = File('${workDir.path}/$targetPath');

            // 创建目标目录
            await targetFile.parent.create(recursive: true);

            // 移动文件
            try {
              await entity.rename(targetFile.path);
              _log.info('文件已重新组织: $fileName -> $targetPath', tag: 'Download');
            } catch (e) {
              // 如果 rename 失败（跨文件系统），尝试复制后删除
              await entity.copy(targetFile.path);
              await entity.delete();
              _log.info('文件已复制并重新组织: $fileName -> $targetPath',
                  tag: 'Download');
            }
          }
        }
      }

      _log.info('文件树结构组织完成: RJ$workId', tag: 'Download');
    } catch (e) {
      _log.error('组织文件树失败 RJ$workId: $e', tag: 'Download');
      // 失败不影响继续运行
    }
  }

  /// 同步磁盘文件到 work_metadata.json 的 children 文件树
  /// 确保手动添加的文件也能在离线浏览器中正确显示
  Future<void> _syncFileTreeWithDisk(int workId, Directory workDir) async {
    // 1. 收集磁盘上所有实际文件的相对路径
    final diskFiles = <String, File>{};

    Future<void> collectFiles(Directory dir, String relativePath) async {
      await for (final entity in dir.list()) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          // 跳过元数据、封面和临时下载文件
          if (fileName == 'work_metadata.json' ||
              fileName == 'cover.jpg' ||
              fileName.endsWith('.downloading')) {
            continue;
          }
          final fullName =
              relativePath.isEmpty ? fileName : '$relativePath/$fileName';
          diskFiles[fullName] = entity;
        } else if (entity is Directory) {
          final dirName = entity.path.split(Platform.pathSeparator).last;
          final subPath =
              relativePath.isEmpty ? dirName : '$relativePath/$dirName';
          await collectFiles(entity, subPath);
        }
      }
    }

    await collectFiles(workDir, '');
    if (diskFiles.isEmpty) return;

    // 2. 加载现有元数据
    final metadataFile = File('${workDir.path}/work_metadata.json');
    Map<String, dynamic>? metadata;

    if (await metadataFile.exists()) {
      try {
        metadata = jsonDecode(await metadataFile.readAsString())
            as Map<String, dynamic>;
      } catch (e) {
        _log.error('读取元数据失败: RJ$workId, $e', tag: 'Download');
      }
    }

    bool metadataCreated = false;
    if (metadata == null) {
      // 没有任何元数据，创建基础元数据
      metadata = {
        'id': workId,
        'title': 'RJ$workId',
        'children': <dynamic>[],
      };
      metadataCreated = true;
    }

    // 3. 收集已有文件树中所有文件的相对路径
    final existingChildren = (metadata['children'] as List<dynamic>?) ?? [];
    final knownPaths = <String>{};

    void collectKnownPaths(List<dynamic> items, String parentPath) {
      for (final item in items) {
        if (item is! Map<String, dynamic>) continue;
        final type = item['type'] as String? ?? '';
        final title = item['title'] as String? ?? '';
        if (type == 'folder') {
          final folderPath = parentPath.isEmpty ? title : '$parentPath/$title';
          final children = item['children'] as List<dynamic>?;
          if (children != null) {
            collectKnownPaths(children, folderPath);
          }
        } else {
          final filePath = parentPath.isEmpty ? title : '$parentPath/$title';
          knownPaths.add(filePath);
        }
      }
    }

    collectKnownPaths(existingChildren, '');

    // 4. 找出磁盘上有但文件树中没有的文件
    final newFiles = <String, File>{};
    for (final entry in diskFiles.entries) {
      if (!knownPaths.contains(entry.key)) {
        newFiles[entry.key] = entry.value;
      }
    }

    if (newFiles.isEmpty && !metadataCreated) return;

    // 5. 将新文件添加到 children 树中的正确位置
    final mutableChildren = List<dynamic>.from(existingChildren);

    for (final entry in newFiles.entries) {
      final relativePath = entry.key;
      final file = entry.value;
      final parts = relativePath.split('/');

      final fileType = FileIconUtils.inferFileType(parts.last);
      final syntheticHash = 'local_${workId}_$relativePath';

      int? fileSize;
      try {
        fileSize = await file.length();
      } catch (_) {}

      final fileEntry = <String, dynamic>{
        'type': fileType,
        'title': parts.last,
        'hash': syntheticHash,
        if (fileSize != null) 'size': fileSize,
      };

      if (parts.length == 1) {
        // 根级别文件
        mutableChildren.add(fileEntry);
      } else {
        // 嵌套文件，确保父文件夹存在
        var currentLevel = mutableChildren;
        for (var i = 0; i < parts.length - 1; i++) {
          final folderName = parts[i];
          // 查找或创建文件夹
          Map<String, dynamic>? folder;
          for (final item in currentLevel) {
            if (item is Map<String, dynamic> &&
                item['type'] == 'folder' &&
                item['title'] == folderName) {
              folder = item;
              break;
            }
          }

          if (folder == null) {
            folder = <String, dynamic>{
              'type': 'folder',
              'title': folderName,
              'children': <dynamic>[],
            };
            currentLevel.add(folder);
          } else if (folder['children'] == null) {
            folder['children'] = <dynamic>[];
          }
          currentLevel = folder['children'] as List<dynamic>;
        }
        currentLevel.add(fileEntry);
      }

      _log.info('添加手动文件到文件树: $relativePath (RJ$workId)', tag: 'Download');
    }

    if (newFiles.isNotEmpty || metadataCreated) {
      metadata['children'] = mutableChildren;
      await metadataFile.writeAsString(jsonEncode(metadata));
      _log.info('已更新作品文件树: RJ$workId, 新增 ${newFiles.length} 个文件',
          tag: 'Download');
    }
  }

  Future<void> _loadTasks() async {
    try {
      final prefs = await StorageService.getPrefs();
      final tasksJson = prefs.getString(_tasksKey);
      if (tasksJson != null) {
        final List<dynamic> tasksList = jsonDecode(tasksJson);
        _tasks.clear();
        _tasks.addAll(
          tasksList.map((json) => DownloadTask.fromJson(json)).toList(),
        );
      }
    } catch (e) {
      _log.error('加载下载任务失败: $e', tag: 'Download');
    }
  }

  // 从硬盘加载元数据并补充到任务中
  /// 公开方法：从硬盘完全同步下载任务
  /// 扫描硬盘文件系统，删除不存在的任务，添加新发现的文件
  /// 用于手动刷新，确保下载完成界面与硬盘文件完全一致
  Future<void> reloadMetadataFromDisk() async {
    try {
      _log.info('开始从硬盘同步任务...', tag: 'Download');

      // 获取下载目录
      final downloadDir = await _getDownloadDirectory();
      if (!await downloadDir.exists()) {
        _log.warning('下载目录不存在，清空所有已完成任务', tag: 'Download');
        _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
        _tasksController.add(List.from(_tasks));
        await _saveTasks();
        return;
      }

      // 扫描硬盘上所有的作品文件夹
      final workFolders = <int, Directory>{};
      await for (final entity in downloadDir.list()) {
        if (entity is Directory) {
          final workIdStr = entity.path.split(Platform.pathSeparator).last;
          final workId = int.tryParse(workIdStr);
          if (workId != null) {
            workFolders[workId] = entity;
          }
        }
      }

      _log.info('发现 ${workFolders.length} 个作品文件夹', tag: 'Download');

      // 第一步：删除硬盘上不存在的已完成任务
      final tasksToRemove = <String>[];
      for (final task in _tasks) {
        if (task.status == DownloadStatus.completed) {
          final workDir = workFolders[task.workId];
          if (workDir == null) {
            // 作品文件夹不存在，删除任务
            tasksToRemove.add(task.id);
            _log.warning('作品文件夹不存在，删除任务: ${task.workTitle}', tag: 'Download');
          } else {
            // Check file existence in the work directory first.
            final file = File('${workDir.path}/${task.fileName}');
            bool fileExists = await file.exists();

            // If not found, try loading metadata from disk — imported works
            // (local_import_path) keep their files in the original source
            // folder, not the work directory. task.workMetadata is null on
            // startup because it's not serialized to SharedPreferences.
            if (!fileExists) {
              final meta = await _loadWorkMetadata(task.workId);
              final importPath = meta?['local_import_path'] as String?;
              if (importPath != null && importPath.isNotEmpty) {
                final sourceFile = File('$importPath/${task.fileName}');
                fileExists = await sourceFile.exists();
              }
            }

            if (!fileExists) {
              tasksToRemove.add(task.id);
              _log.warning('文件不存在，删除任务: ${task.fileName}', tag: 'Download');
            }
          }
        }
      }

      // 执行删除
      if (tasksToRemove.isNotEmpty) {
        _tasks.removeWhere((t) => tasksToRemove.contains(t.id));
        _log.info('删除了 ${tasksToRemove.length} 个不存在的任务', tag: 'Download');
      }

      // 第二步：检查并升级旧版本文件（没有元数据的文件）
      await _upgradeOldWorkFolders(workFolders);

      // 第三步：同步磁盘文件到文件树（确保手动添加的文件能正确显示）
      for (final entry in workFolders.entries) {
        try {
          await _syncFileTreeWithDisk(entry.key, entry.value);
        } catch (e) {
          _log.error('同步文件树失败 RJ${entry.key}: $e', tag: 'Download');
        }
      }

      // 第四步：扫描硬盘上的所有文件，添加新发现的任务
      final newTasks = <DownloadTask>[];
      for (final entry in workFolders.entries) {
        final workId = entry.key;
        final workDir = entry.value;

        // 加载元数据（现在可能已经通过升级创建了）
        final metadata = await _loadWorkMetadata(workId);
        final workTitle = metadata?['title'] as String? ?? 'RJ$workId';

        // 递归扫描文件夹中的所有文件
        Future<void> scanDirectory(Directory dir, String relativePath) async {
          await for (final entity in dir.list()) {
            if (entity is File) {
              final fileName = entity.path.split(Platform.pathSeparator).last;

              // 跳过元数据、封面和临时下载文件
              if (fileName == 'work_metadata.json' ||
                  fileName == 'cover.jpg' ||
                  fileName.endsWith('.downloading')) {
                continue;
              }

              // 构建相对路径下的文件名
              final fullFileName =
                  relativePath.isEmpty ? fileName : '$relativePath/$fileName';

              // 检查该文件是否已有对应的任务
              final existingTask = _tasks.firstWhere(
                (t) => t.workId == workId && t.fileName == fullFileName,
                orElse: () => DownloadTask(
                  id: '',
                  workId: 0,
                  workTitle: '',
                  fileName: '',
                  downloadUrl: '',
                  createdAt: DateTime.now(),
                ),
              );

              if (existingTask.id.isEmpty) {
                // 发现新文件，创建任务
                final newTask = DownloadTask(
                  id: '${workId}_${fullFileName}_${DateTime.now().millisecondsSinceEpoch}',
                  workId: workId,
                  workTitle: workTitle,
                  fileName: fullFileName,
                  downloadUrl: '', // 硬盘扫描的任务没有下载URL
                  status: DownloadStatus.completed,
                  totalBytes: await entity.length(),
                  downloadedBytes: await entity.length(),
                  createdAt: entity.statSync().modified,
                  completedAt: entity.statSync().modified,
                  workMetadata: metadata,
                );
                newTasks.add(newTask);
                _log.info('发现新文件: $fullFileName ($workTitle)', tag: 'Download');
              }
            } else if (entity is Directory) {
              // 递归扫描子目录
              final dirName = entity.path.split(Platform.pathSeparator).last;
              final subPath =
                  relativePath.isEmpty ? dirName : '$relativePath/$dirName';
              await scanDirectory(entity, subPath);
            }
          }
        }

        await scanDirectory(workDir, '');
      }

      // 添加新任务
      if (newTasks.isNotEmpty) {
        _tasks.addAll(newTasks);
        _log.info('添加了 ${newTasks.length} 个新任务', tag: 'Download');
      }

      // 第五步：为所有已完成任务更新元数据（包含新同步的文件树）
      for (var i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.status == DownloadStatus.completed) {
          final metadata = await _loadWorkMetadata(task.workId);
          if (metadata != null) {
            _tasks[i] = task.copyWith(workMetadata: metadata);
          }
        }
      }

      // 通知更新并保存
      _tasksController.add(List.from(_tasks));
      await _saveTasks();

      _log.info('同步完成：删除 ${tasksToRemove.length} 个，新增 ${newTasks.length} 个',
          tag: 'Download');
    } catch (e) {
      _log.error('从硬盘同步任务失败: $e', tag: 'Download');
      rethrow;
    }
  }

  Future<void> _saveTasks() async {
    try {
      final prefs = await StorageService.getPrefs();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_tasksKey, tasksJson);
    } catch (e) {
      _log.error('保存下载任务失败: $e', tag: 'Download');
    }
  }

  /// Import a local folder as a new work (reference only — no file copy).
  /// Creates a synthetic work entry with a negative ID so it appears
  /// alongside downloaded works in the local downloads screen.
  ///
  /// Returns the synthetic workId on success, or throws on error.
  Future<int> importLocalWork({
    required String folderPath,
    required String title,
  }) async {
    final importDir = Directory(folderPath);
    if (!await importDir.exists()) {
      throw Exception('Folder not found: $folderPath');
    }

    // Generate a unique negative workId
    final workId = -DateTime.now().millisecondsSinceEpoch;

    // Create work directory in download folder
    final downloadDir = await _getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    await workDir.create(recursive: true);

    // Scan the original folder for files and build a file tree
    final List<dynamic> children = [];
    int totalFiles = 0;

    Future<void> scanDir(Directory dir, List<dynamic> parentList,
        String relativePath) async {
      await for (final entity in dir.list(followLinks: false)) {
        final name = entity.path.split(Platform.pathSeparator).last;
        // Skip hidden files
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
            } catch (_) {}
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
      // Clean up empty directory
      await workDir.delete(recursive: true);
      throw Exception('No supported audio/image/text files found in the selected folder.');
    }

    // Look for a cover image in the imported folder, resize to a reasonable
    // max dimension (720px), and save as JPEG quality 85.
    // This prevents large/resolution covers (>1MB) from failing to display in
    // the fullscreen player and avoids unnecessary memory pressure during
    // image decoding (Image.file with cacheWidth).
    String? coverPath;
    try {
      await for (final entity in importDir.list(followLinks: false)) {
        if (entity is File) {
          final fName = entity.path.split(Platform.pathSeparator).last.toLowerCase();
          if (fName.endsWith('.jpg') || fName.endsWith('.jpeg') ||
              fName.endsWith('.png') || fName.endsWith('.webp') ||
              fName.endsWith('.bmp')) {
            await _resizeAndSaveCover(
              sourcePath: entity.path,
              destPath: '${workDir.path}/cover.jpg',
              maxDimension: 720,
            );
            coverPath = 'cover.jpg';
            _log.info('Cover image resized and saved as JPEG: $fName (max ${720}px)', tag: 'Download');
            break; // use the first image found
          }
        }
      }
    } catch (e) {
      _log.warning('Failed to process cover image: $e', tag: 'Download');
    }

    // Create work metadata
    final metadata = <String, dynamic>{
      'id': workId,
      'title': title,
      'children': children,
      'local_import_path': folderPath,
    };
    if (coverPath != null) {
      metadata['localCoverPath'] = coverPath;
    }

    final metadataFile = File('${workDir.path}/work_metadata.json');
    await metadataFile.writeAsString(jsonEncode(metadata));

    _log.info('Imported local work: $title (ID: $workId, $totalFiles files)',
        tag: 'Download');

    // Create DownloadTask entries for each file
    int fileIndex = 0;
    void addTaskForFile(dynamic item, String parentPath) {
      final itemType = item['type'] ?? '';
      final fileTitle = item['title'] ?? 'unknown';
      final hash = item['hash'];

      if (itemType == 'folder') {
        final subChildren = item['children'] as List<dynamic>?;
        if (subChildren != null) {
          for (final child in subChildren) {
            final childPath = parentPath.isEmpty ? fileTitle : '$parentPath/$fileTitle';
            addTaskForFile(child, childPath);
          }
        }
      } else {
        final fileName = parentPath.isEmpty ? fileTitle : '$parentPath/$fileTitle';
        _tasks.add(DownloadTask(
          id: hash ?? 'import_${workId}_${fileIndex++}',
          workId: workId,
          workTitle: title, // use the work title (outer param), not file name
          fileName: fileName,
          downloadUrl: '',
          hash: hash,
          totalBytes: item['size'] as int?,
          downloadedBytes: item['size'] as int? ?? 0,
          status: DownloadStatus.completed,
          createdAt: DateTime.now(),
          completedAt: DateTime.now(),
          workMetadata: metadata,
        ));
      }
    }

    for (final child in children) {
      addTaskForFile(child, '');
    }

    await _saveTasks();
    _tasksController.add(List.from(_tasks));

    return workId;
  }

  /// Resize a cover image to [maxDimension] pixels on the longest edge and
  /// save as JPEG quality 85. This prevents large images (>1MB) from causing
  /// silent decode failures in Image.file() on Android with Impeller/Vulkan.
  Future<void> _resizeAndSaveCover({
    required String sourcePath,
    required String destPath,
    int maxDimension = 720,
  }) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) return;

    // Read the source file bytes
    final Uint8List bytes = await sourceFile.readAsBytes();

    // Decode the image using the pure-Dart image package
    final original = img.decodeImage(bytes);
    if (original == null) {
      // Fallback: copy the file as-is if decoding fails (better than nothing)
      _log.warning('Failed to decode cover image, copying as-is: $sourcePath',
          tag: 'Download');
      await sourceFile.copy(destPath);
      return;
    }

    // Determine if resize is needed
    final isOversized =
        original.width > maxDimension || original.height > maxDimension;

    img.Image result;
    if (isOversized) {
      // Resize maintaining aspect ratio
      result = img.copyResize(original,
          width: original.width > original.height ? maxDimension : null,
          height: original.height >= original.width ? maxDimension : null);
    } else {
      result = original;
    }

    // Encode as JPEG quality 85 (good visual quality, small file size)
    final jpegBytes = img.encodeJpg(result, quality: 85);
    await File(destPath).writeAsBytes(jpegBytes);

    _log.info(
      'Cover resized: ${original.width}x${original.height} -> ${result.width}x${result.height} '
      '(${(bytes.length / 1024).toStringAsFixed(1)}KB -> '
      '${(jpegBytes.length / 1024).toStringAsFixed(1)}KB)',
      tag: 'Download',
    );
  }

  /// Import multiple folders (each subfolder becomes one work).
  /// [parentFolderPath] is the parent directory; each direct subfolder will
  /// become an imported work using the folder name as its title.
  /// [onProgress] is called with (currentIndex, totalCount, folderName) after
  /// each subfolder is processed (whether it succeeds or fails).
  /// Returns the list of synthetic workIds created.
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

    return createdIds;
  }

  void dispose() {
    _saveTimer?.cancel();
    _saveTimer = null;
    _tasksController.close();
    _conversionController.close();
    for (final token in _cancelTokens.values) {
      token.cancel();
    }
    _cancelTokens.clear();

    // 确保最后保存一次
    if (_needsSave) {
      _saveTasks();
    }
  }
}
