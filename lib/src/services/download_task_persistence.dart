import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:dio/dio.dart';

import '../models/download_task.dart';
import '../utils/file_icon_utils.dart';
import 'download_path_service.dart';
import 'kikoeru_api_service.dart';
import 'log_service.dart';
import 'storage_service.dart';
import 'cookie_service.dart';

final _log = LogService.instance;

/// Manages all download task data: in-memory task list, persistence to
/// SharedPreferences, disk metadata (work_metadata.json), disk sync,
/// file tree management, and natural sort utilities.
///
/// Owns the [_tasks] list and [_tasksController] stream. Other modules
/// (QueueManager, Service facade) read/write tasks through this class.
class DownloadTaskPersistence {
  final List<DownloadTask> _tasks = [];
  final StreamController<List<DownloadTask>> _tasksController =
      StreamController<List<DownloadTask>>.broadcast();

  Timer? _saveTimer;
  bool _needsSave = false;

  static const String _tasksKey = 'download_tasks';

  /// Dio instance used for downloading cover images.
  final Dio _dio = Dio();

  /// Stream of task lists — emitted whenever tasks change.
  Stream<List<DownloadTask>> get tasksStream => _tasksController.stream;

  /// Unmodifiable snapshot of current tasks.
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);

  /// Number of tasks currently downloading or pending.
  int get activeDownloadCount => _tasks
      .where((task) =>
          task.status == DownloadStatus.downloading ||
          task.status == DownloadStatus.pending)
      .length;

  /// Whether any tasks are currently downloading.
  bool get hasActiveDownloads => activeDownloadCount > 0;

  /// Find a task by id, or return a sentinel empty task.
  DownloadTask findTaskById(String taskId) {
    return _tasks.firstWhere(
      (t) => t.id == taskId,
      orElse: () => DownloadTask(
        id: '',
        workId: 0,
        workTitle: '',
        fileName: '',
        downloadUrl: '',
        createdAt: DateTime.now(),
      ),
    );
  }

  /// Find the index of a task by id, or -1.
  int indexOf(String taskId) => _tasks.indexWhere((t) => t.id == taskId);

  /// Find tasks for a given work.
  List<DownloadTask> tasksForWork(int workId) {
    return _tasks.where((t) => t.workId == workId).toList();
  }

  /// Remove tasks matching a predicate.
  void removeWhere(bool Function(DownloadTask) predicate) {
    _tasks.removeWhere(predicate);
  }

  /// Add multiple tasks.
  void addAll(Iterable<DownloadTask> tasks) {
    _tasks.addAll(tasks);
  }

  /// Get a task by index.
  DownloadTask operator [](int index) => _tasks[index];

  /// Set a task at index.
  void operator []=(int index, DownloadTask task) {
    _tasks[index] = task;
  }

  /// Length of the task list.
  int get length => _tasks.length;

  /// Iterate over tasks.
  void forEach(void Function(DownloadTask) action) => _tasks.forEach(action);

  /// Update a task in the list and notify listeners.
  /// If [immediate] is true, saves to SharedPreferences immediately.
  /// Otherwise schedules a delayed save.
  void updateTask(DownloadTask updatedTask, {bool immediate = false}) {
    final index = _tasks.indexWhere((t) => t.id == updatedTask.id);
    if (index != -1) {
      _tasks[index] = updatedTask;
      _tasksController.add(List.from(_tasks));
      if (immediate) {
        _saveTasks();
      } else {
        _scheduleDelayedSave();
      }
    }
  }

  /// Notify listeners that tasks changed (without modifying any task).
  void notifyChanged() {
    _tasksController.add(List.from(_tasks));
  }

  /// Immediately save tasks to SharedPreferences.
  Future<void> flush() => _saveTasks();

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

  Future<void> _saveTasks() async {
    try {
      final prefs = await StorageService.getPrefs();
      final tasksJson = jsonEncode(_tasks.map((t) => t.toJson()).toList());
      await prefs.setString(_tasksKey, tasksJson);
    } catch (e) {
      _log.error('保存下载任务失败: $e', tag: 'Download');
    }
  }

  /// Load tasks from SharedPreferences.
  Future<void> loadTasks() async {
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

  /// Get the download root directory.
  Future<Directory> getDownloadDirectory() async {
    return await DownloadPathService.getDownloadDirectory();
  }

  /// Get the work-specific download directory path.
  Future<String> getWorkDownloadDirectory(int workId) async {
    final downloadDir = await getDownloadDirectory();
    final workDir = Directory('${downloadDir.path}/$workId');
    if (!await workDir.exists()) {
      await workDir.create(recursive: true);
    }
    return workDir.path;
  }

  /// Download a cover image for a work.
  Future<String?> downloadCoverImage(int workId, String coverUrl) async {
    try {
      final workDir = await getWorkDownloadDirectory(workId);
      final coverFile = File('$workDir/cover.jpg');
      if (await coverFile.exists()) {
        return coverFile.path;
      }
      _dio.options.headers.addAll(CookieService.serverCookieHeaders);
      await _dio.download(coverUrl, coverFile.path);
      return coverFile.path;
    } catch (e) {
      _log.error('下载封面图片失败: $e', tag: 'Download');
      return null;
    }
  }

  /// Save work metadata to disk (including cover download).
  Future<void> saveWorkMetadata(
      int workId, Map<String, dynamic> metadata, String? coverUrl) async {
    try {
      if (coverUrl != null && coverUrl.isNotEmpty) {
        final localCoverPath = await downloadCoverImage(workId, coverUrl);
        if (localCoverPath != null) {
          metadata['localCoverPath'] = 'cover.jpg';
        }
      }
      final workDir = await getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');
      final jsonStr = jsonEncode(metadata);
      await metadataFile.writeAsString(jsonStr);
    } catch (e) {
      _log.error('保存作品元数据失败: $e', tag: 'Download');
    }
  }

  /// Load work metadata from disk.
  Future<Map<String, dynamic>?> loadWorkMetadata(int workId) async {
    try {
      final workDir = await getWorkDownloadDirectory(workId);
      final metadataFile = File('$workDir/work_metadata.json');
      if (await metadataFile.exists()) {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;
        if (metadata.containsKey('localCoverPath')) {
          final coverPath = metadata['localCoverPath'] as String?;
          if (coverPath != null && coverPath.contains(Platform.pathSeparator)) {
            metadata['localCoverPath'] = 'cover.jpg';
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

  /// Get work metadata (from memory first, then disk).
  Future<Map<String, dynamic>?> getWorkMetadata(int workId) async {
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
    return await loadWorkMetadata(workId);
  }

  /// Get the file path for a downloaded track.
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
    final workDir = await getWorkDownloadDirectory(workId);
    final file = File('$workDir/${task.fileName}');
    if (await file.exists()) {
      return file.path;
    }
    return null;
  }

  /// Fully sync tasks with disk. Scans the filesystem, removes tasks for
  /// missing files, adds new files as completed tasks.
  ///
  /// The heavy file I/O is offloaded to a background Isolate to prevent
  /// UI freezes during the scan.
  Future<void> reloadMetadataFromDisk() async {
    try {
      _log.info('开始从硬盘同步任务 (background)...', tag: 'Download');
      final downloadDir = await getDownloadDirectory();
      if (!await downloadDir.exists()) {
        _log.warning('下载目录不存在，清空所有已完成任务', tag: 'Download');
        _tasks.removeWhere((t) => t.status == DownloadStatus.completed);
        _tasksController.add(List.from(_tasks));
        await _saveTasks();
        return;
      }

      // Prepare current tasks as JSON for Isolate transfer
      final currentTasksJson = _tasks.map((t) => t.toJson()).toList();

      // Run heavy I/O in background Isolate
      final result = await Isolate.run(
        () => _scanDownloadDirectoryInBackground(
          downloadDir.path,
          currentTasksJson,
        ),
      );

      _log.info('发现 ${result.scannedFolders} 个作品文件夹', tag: 'Download');

      // Apply results from Isolate
      if (result.tasksToRemove.isNotEmpty) {
        _tasks.removeWhere((t) => result.tasksToRemove.contains(t.id));
        _log.info(
            '删除了 ${result.tasksToRemove.length} 个不存在的任务', tag: 'Download');
      }

      // Convert new tasks from JSON
      if (result.newTasks.isNotEmpty) {
        for (final taskJson in result.newTasks) {
          final workId = taskJson['workId'] as int;
          Map<String, dynamic>? metadata;
          final metadataJson = taskJson['workMetadataJson'] as String?;
          if (metadataJson != null) {
            metadata = jsonDecode(metadataJson) as Map<String, dynamic>;
          }
          final newTask = DownloadTask(
            id: taskJson['id'] as String,
            workId: workId,
            workTitle: taskJson['workTitle'] as String,
            fileName: taskJson['fileName'] as String,
            downloadUrl: taskJson['downloadUrl'] as String,
            status: DownloadStatus.completed,
            totalBytes: taskJson['totalBytes'] as int?,
            downloadedBytes: (taskJson['downloadedBytes'] as int?) ?? 0,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
                taskJson['createdAt'] as int),
            completedAt: taskJson['completedAt'] != null
                ? DateTime.fromMillisecondsSinceEpoch(
                    taskJson['completedAt'] as int)
                : null,
            workMetadata: metadata,
          );
          _tasks.add(newTask);
        }
        _log.info('添加了 ${result.newTasks.length} 个新任务', tag: 'Download');
      }

      // Update metadata for existing tasks
      for (var i = 0; i < _tasks.length; i++) {
        final task = _tasks[i];
        if (task.status == DownloadStatus.completed) {
          final metadata = result.workMetadata[task.workId];
          if (metadata != null) {
            _tasks[i] = task.copyWith(workMetadata: metadata);
          }
        }
      }

      _tasksController.add(List.from(_tasks));
      await _saveTasks();
      _log.info(
          '同步完成：删除 ${result.tasksToRemove.length} 个，新增 ${result.newTasks.length} 个',
          tag: 'Download');
    } catch (e) {
      _log.error('从硬盘同步任务失败: $e', tag: 'Download');
      rethrow;
    }
  }

  /// Sync disk files into work_metadata.json's children tree.
  Future<void> syncFileTreeWithDisk(int workId, Directory workDir) async {
    final diskFiles = <String, File>{};

    Future<void> collectFiles(Directory dir, String relativePath) async {
      final entities = await dir.list(followLinks: false).toList();
      entities.sort((a, b) {
        final aName = a.path.split(Platform.pathSeparator).last;
        final bName = b.path.split(Platform.pathSeparator).last;
        return naturalCompare(aName, bName);
      });
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
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

    final metadataFile = File('${workDir.path}/work_metadata.json');
    Map<String, dynamic>? metadata;
    if (await metadataFile.exists()) {
      try {
        metadata =
            jsonDecode(await metadataFile.readAsString()) as Map<String, dynamic>;
      } catch (e) {
        _log.error('读取元数据失败: RJ$workId, $e', tag: 'Download');
      }
    }
    metadata ??= {
      'id': workId,
      'title': 'RJ$workId',
      'children': <dynamic>[],
    };

    if (diskFiles.isNotEmpty) {
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
            if (children != null) collectKnownPaths(children, folderPath);
          } else {
            knownPaths.add(parentPath.isEmpty ? title : '$parentPath/$title');
          }
        }
      }
      collectKnownPaths(existingChildren, '');

      final newFiles = <String, File>{};
      for (final entry in diskFiles.entries) {
        if (!knownPaths.contains(entry.key)) newFiles[entry.key] = entry.value;
      }

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
        } catch (e) {
          LogService.instance.warning('[DownloadTaskPersistence] Failed to get file size: $e', tag: 'Download');
        }
        final fileEntry = <String, dynamic>{
          'type': fileType,
          'title': parts.last,
          'hash': syntheticHash,
          if (fileSize != null) 'size': fileSize,
        };
        if (parts.length == 1) {
          mutableChildren.add(fileEntry);
        } else {
          var currentLevel = mutableChildren;
          for (var i = 0; i < parts.length - 1; i++) {
            final folderName = parts[i];
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
        _log.info('添加手动文件到文件树: $relativePath (RJ$workId)',
            tag: 'Download');
      }
      sortChildrenTree(mutableChildren);
      metadata['children'] = mutableChildren;
      await metadataFile.writeAsString(jsonEncode(metadata));
      _log.info(
          '已更新作品文件树: RJ$workId, 新增 ${newFiles.length} 个文件',
          tag: 'Download');
    } else {
      final existingChildren = (metadata['children'] as List<dynamic>?) ?? [];
      sortChildrenTree(existingChildren);
      metadata['children'] = existingChildren;
      await metadataFile.writeAsString(jsonEncode(metadata));
      _log.info('已排序作品文件树: RJ$workId (no new files)', tag: 'Download');
    }
  }

  Future<void> _upgradeOldWorkFolders(Map<int, Directory> workFolders) async {
    for (final entry in workFolders.entries) {
      final workId = entry.key;
      final workDir = entry.value;
      final metadataFile = File('${workDir.path}/work_metadata.json');
      if (await metadataFile.exists()) continue;

      _log.info('发现旧版本作品文件夹，尝试升级: RJ$workId', tag: 'Download');
      try {
        final apiService = KikoeruApiService();
        final workData = await apiService.getWork(workId);
        final tracks = await apiService.getWorkTracks(workId);
        workData['children'] = tracks;
        workData['localCoverPath'] = 'cover.jpg';
        await metadataFile.writeAsString(jsonEncode(workData));
        _log.info('已保存作品元数据: RJ$workId', tag: 'Download');

        final host = StorageService.getString('server_host') ?? '';
        final token = await StorageService.getStringAsync('auth_token') ?? '';
        if (host.isNotEmpty) {
          String normalizedHost = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedHost = 'https://$host';
          }
          final coverUrl = token.isNotEmpty
              ? '$normalizedHost/api/cover/$workId?token=$token'
              : '$normalizedHost/api/cover/$workId';
          await downloadCoverImage(workId, coverUrl);
          _log.info('已下载作品封面: RJ$workId', tag: 'Download');
        }
        await _organizeFilesIntoTree(workId, workDir, tracks);
        _log.info('作品升级成功: RJ$workId', tag: 'Download');
      } catch (e) {
        _log.error('升级作品失败 RJ$workId: $e', tag: 'Download');
      }
    }
  }

  Future<void> _organizeFilesIntoTree(
      int workId, Directory workDir, List<dynamic> tracks) async {
    try {
      final Map<String, String> hashToPath = {};
      void buildPathMap(List<dynamic> items, String parentPath) {
        for (final item in items) {
          final type = item['type'] as String?;
          final title =
              item['title'] as String? ?? item['name'] as String? ?? '';
          final hash = item['hash'] as String?;
          if (type == 'folder') {
            final folderPath =
                parentPath.isEmpty ? title : '$parentPath/$title';
            final children = item['children'] as List<dynamic>?;
            if (children != null) buildPathMap(children, folderPath);
          } else if (hash != null) {
            hashToPath[hash] =
                parentPath.isEmpty ? title : '$parentPath/$title';
          }
        }
      }
      buildPathMap(tracks, '');

      final workEntities = await workDir.list(followLinks: false).toList();
      workEntities.sort((a, b) {
        final aName = a.path.split(Platform.pathSeparator).last;
        final bName = b.path.split(Platform.pathSeparator).last;
        return naturalCompare(aName, bName);
      });
      for (final entity in workEntities) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName == 'work_metadata.json' || fileName == 'cover.jpg') {
            continue;
          }
          String? targetPath;
          for (final entry in hashToPath.entries) {
            final expectedFileName = entry.value.split('/').last;
            if (expectedFileName == fileName) {
              targetPath = entry.value;
              break;
            }
          }
          if (targetPath != null && targetPath.contains('/')) {
            final targetFile = File('${workDir.path}/$targetPath');
            await targetFile.parent.create(recursive: true);
            try {
              await entity.rename(targetFile.path);
              _log.info(
                  '文件已重新组织: $fileName -> $targetPath', tag: 'Download');
            } catch (e) {
              await entity.copy(targetFile.path);
              await entity.delete();
              _log.info(
                  '文件已复制并重新组织: $fileName -> $targetPath',
                  tag: 'Download');
            }
          }
        }
      }
      _log.info('文件树结构组织完成: RJ$workId', tag: 'Download');
    } catch (e) {
      _log.error('组织文件树失败 RJ$workId: $e', tag: 'Download');
    }
  }

  /// Human-friendly natural sort comparator — sorts "2.mp3" before "10.mp3".
  static int naturalCompare(String a, String b) {
    final pattern = RegExp(r'(\d+|[^\d]+)');
    final aParts = pattern
        .allMatches(a.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();
    final bParts = pattern
        .allMatches(b.toLowerCase())
        .map((m) => m.group(1)!)
        .toList();
    final len = aParts.length < bParts.length ? aParts.length : bParts.length;
    for (int i = 0; i < len; i++) {
      final aNum = int.tryParse(aParts[i]);
      final bNum = int.tryParse(bParts[i]);
      if (aNum != null && bNum != null) {
        if (aNum != bNum) return aNum.compareTo(bNum);
      } else {
        final cmp = aParts[i].compareTo(bParts[i]);
        if (cmp != 0) return cmp;
      }
    }
    return aParts.length.compareTo(bParts.length);
  }

  /// Recursively sort a children tree in natural filename order.
  static void sortChildrenTree(List<dynamic> children) {
    children.sort((a, b) {
      final aIsFolder = a is Map && a['type'] == 'folder';
      final bIsFolder = b is Map && b['type'] == 'folder';
      if (aIsFolder && !bIsFolder) return -1;
      if (!aIsFolder && bIsFolder) return 1;
      final aName =
          (a is Map ? (a['title'] as String? ?? '') : '').toLowerCase();
      final bName =
          (b is Map ? (b['title'] as String? ?? '') : '').toLowerCase();
      return naturalCompare(aName, bName);
    });
    for (final item in children) {
      if (item is Map && item['type'] == 'folder') {
        final subChildren = item['children'] as List<dynamic>?;
        if (subChildren != null && subChildren.isNotEmpty) {
          sortChildrenTree(subChildren);
        }
      }
    }
  }

  /// Ensure tasks are saved and close stream.
  Future<void> dispose() async {
    _saveTimer?.cancel();
    _saveTimer = null;
    if (_needsSave) {
      await _saveTasks();
    }
    await _tasksController.close();
  }
}

// ═══════════════════════════════════════════════════════════════════
// Top-level functions for background Isolate operations
// ═══════════════════════════════════════════════════════════════════

/// Data transfer object for Isolate communication.
class _ScanResult {
  final List<Map<String, dynamic>> existingTasks;
  final List<Map<String, dynamic>> newTasks;
  final List<String> tasksToRemove;
  final Map<int, Map<String, dynamic>?> workMetadata;
  final int scannedFolders;

  const _ScanResult({
    required this.existingTasks,
    required this.newTasks,
    required this.tasksToRemove,
    required this.workMetadata,
    required this.scannedFolders,
  });
}

/// Top-level function that runs in a background Isolate.
/// Scans the download directory and returns results.
Future<_ScanResult> _scanDownloadDirectoryInBackground(
  String downloadDirPath,
  List<Map<String, dynamic>> currentTasksJson,
) async {
  final downloadDir = Directory(downloadDirPath);
  if (!await downloadDir.exists()) {
    return _ScanResult(
      existingTasks: currentTasksJson,
      newTasks: [],
      tasksToRemove: [],
      workMetadata: {},
      scannedFolders: 0,
    );
  }

  // 1. Collect work folders
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

  // 2. Load metadata for all work folders
  final workMetadata = <int, Map<String, dynamic>?>{};
  for (final entry in workFolders.entries) {
    final metadataFile = File('${entry.value.path}/work_metadata.json');
    if (await metadataFile.exists()) {
      try {
        final content = await metadataFile.readAsString();
        final metadata = jsonDecode(content) as Map<String, dynamic>;
        // Migrate cover path if needed
        if (metadata.containsKey('localCoverPath')) {
          final coverPath = metadata['localCoverPath'] as String?;
          if (coverPath != null && coverPath.contains(Platform.pathSeparator)) {
            metadata['localCoverPath'] = 'cover.jpg';
            await metadataFile.writeAsString(jsonEncode(metadata));
          }
        }
        workMetadata[entry.key] = metadata;
      } catch (e) {
        workMetadata[entry.key] = null;
      }
    } else {
      workMetadata[entry.key] = null;
    }
  }

  // 3. Check which existing tasks still have files on disk
  final tasksToRemove = <String>[];
  final existingTasks = <Map<String, dynamic>>[];
  for (final taskJson in currentTasksJson) {
    final status = taskJson['status'] as String? ?? '';
    final workId = taskJson['workId'] as int? ?? 0;
    final fileName = taskJson['fileName'] as String? ?? '';
    if (status == 'completed') {
      final workDir = workFolders[workId];
      if (workDir == null) {
        tasksToRemove.add(taskJson['id'] as String? ?? '');
      } else {
        final file = File('${workDir.path}/$fileName');
        bool fileExists = await file.exists();
        if (!fileExists) {
          // Check local import path
          final meta = workMetadata[workId];
          final importPath = meta?['local_import_path'] as String?;
          if (importPath != null && importPath.isNotEmpty) {
            final sourceFile = File('$importPath/$fileName');
            fileExists = await sourceFile.exists();
          }
        }
        if (!fileExists) {
          tasksToRemove.add(taskJson['id'] as String? ?? '');
        }
      }
    }
    existingTasks.add(taskJson);
  }

  // 4. Scan for new files on disk
  final newTasks = <Map<String, dynamic>>[];
  for (final entry in workFolders.entries) {
    final workId = entry.key;
    final workDir = entry.value;
    final metadata = workMetadata[workId];
    final workTitle = metadata?['title'] as String? ?? 'RJ$workId';

    Future<void> scanDirectory(Directory dir, String relativePath) async {
      final entities = await dir.list(followLinks: false).toList();
      entities.sort((a, b) {
        final aName = a.path.split(Platform.pathSeparator).last;
        final bName = b.path.split(Platform.pathSeparator).last;
        return _naturalCompare(aName, bName);
      });
      for (final entity in entities) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          if (fileName == 'work_metadata.json' ||
              fileName == 'cover.jpg' ||
              fileName.endsWith('.downloading')) {
            continue;
          }
          final fullFileName = relativePath.isEmpty
              ? fileName
              : '$relativePath/$fileName';
          // Check if this file already has a task
          final hasTask = existingTasks.any((t) =>
              t['workId'] == workId && t['fileName'] == fullFileName);
          if (!hasTask) {
            final stat = await entity.stat();
            final length = await entity.length();
            newTasks.add({
              'id': '${workId}_${fullFileName}_${DateTime.now().millisecondsSinceEpoch}',
              'workId': workId,
              'workTitle': workTitle,
              'fileName': fullFileName,
              'downloadUrl': '',
              'status': 'completed',
              'totalBytes': length,
              'downloadedBytes': length,
              'createdAt': stat.modified.millisecondsSinceEpoch,
              'completedAt': stat.modified.millisecondsSinceEpoch,
              'workMetadataJson': metadata != null ? jsonEncode(metadata) : null,
            });
          }
        } else if (entity is Directory) {
          final dirName = entity.path.split(Platform.pathSeparator).last;
          final subPath = relativePath.isEmpty ? dirName : '$relativePath/$dirName';
          await scanDirectory(entity, subPath);
        }
      }
    }
    await scanDirectory(workDir, '');
  }

  return _ScanResult(
    existingTasks: existingTasks,
    newTasks: newTasks,
    tasksToRemove: tasksToRemove,
    workMetadata: workMetadata,
    scannedFolders: workFolders.length,
  );
}

/// Natural sort comparator for file names.
int _naturalCompare(String a, String b) {
  final pattern = RegExp(r'(\d+|[^\d]+)');
  final aParts = pattern
      .allMatches(a.toLowerCase())
      .map((m) => m.group(1)!)
      .toList();
  final bParts = pattern
      .allMatches(b.toLowerCase())
      .map((m) => m.group(1)!)
      .toList();
  final len = aParts.length < bParts.length ? aParts.length : bParts.length;
  for (int i = 0; i < len; i++) {
    final aNum = int.tryParse(aParts[i]);
    final bNum = int.tryParse(bParts[i]);
    if (aNum != null && bNum != null) {
      if (aNum != bNum) return aNum.compareTo(bNum);
    } else {
      final cmp = aParts[i].compareTo(bParts[i]);
      if (cmp != 0) return cmp;
    }
  }
  return aParts.length.compareTo(bParts.length);
}