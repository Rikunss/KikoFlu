import 'dart:io';
import 'dart:convert';
import 'dart:isolate';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'log_service.dart';
import 'storage_service.dart';
import 'cookie_service.dart';
import 'download_service.dart';
import '../models/download_task.dart';
import '../utils/encoding_utils.dart';

class CacheService {
  static const Duration workDetailCacheDuration =
      Duration(hours: 24);
  static const Duration workTracksCacheDuration =
      Duration(hours: 24);
  static const Duration fileCacheDuration =
      Duration(days: 30);
  static const Duration audioCacheDuration =
      Duration(days: 30);

  static String _safeAudioHash(String hash) => hash.replaceAll('/', '_');

  static Future<File> _audioFinalFile(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final cacheDir = await _getAudioCacheDirectory();
    return File('${cacheDir.path}/$safeHash.audio');
  }

  static Future<File> _audioTempFile(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final cacheDir = await _getAudioCacheDirectory();
    return File('${cacheDir.path}/$safeHash.audio.part');
  }

  static Future<void> _writeAudioCacheMeta(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final prefs = await StorageService.getPrefs();
    await prefs.setInt(
        'audio_cache_meta_$safeHash', DateTime.now().millisecondsSinceEpoch);
  }

  static Future<void> _removeAudioCacheMeta(String hash) async {
    final safeHash = _safeAudioHash(hash);
    final prefs = await StorageService.getPrefs();
    await prefs.remove('audio_cache_meta_$safeHash');
  }

  static Future<void> resetAudioCachePartial(String hash) async {
    final tempFile = await _audioTempFile(hash);
    if (await tempFile.exists()) {
      await tempFile.delete();
    }
    await _removeAudioCacheMeta(hash);
  }

  static Future<File> prepareAudioCacheTempFile(String hash) async {
    final tempFile = await _audioTempFile(hash);
    if (!await tempFile.exists()) {
      await tempFile.create(recursive: true);
    }
    return tempFile;
  }

  static Future<void> finalizeAudioCacheFile(String hash,
      {required int expectedSize}) async {
    final tempFile = await _audioTempFile(hash);
    if (!await tempFile.exists()) {
      return;
    }

    final currentSize = await tempFile.length();
    if (currentSize < expectedSize) {
      return;
    }

    final finalFile = await _audioFinalFile(hash);

    if (await finalFile.exists()) {
      await finalFile.delete();
    }

    await tempFile.rename(finalFile.path);
    await _writeAudioCacheMeta(hash);
  }

  static const String cacheSizeLimitKey = 'cache_size_limit_mb';
  static const int defaultCacheSizeLimitMB = 1000;

  static const Duration autoCleanCheckInterval = Duration(minutes: 5);
  static const String lastCleanCheckTimeKey = 'last_clean_check_time';

  static Future<void> cacheWorkDetail(
      int workId, Map<String, dynamic> workData) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    await prefs.setString(cacheKey, jsonEncode(workData));
    await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<Map<String, dynamic>?> getCachedWorkDetail(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    final cachedData = prefs.getString(cacheKey);
    final cacheTime = prefs.getInt(cacheTimeKey);

    if (cachedData == null || cacheTime == null) {
      return null;
    }

    final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
    if (DateTime.now().difference(cacheDateTime) > workDetailCacheDuration) {
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }

    try {
      return jsonDecode(cachedData) as Map<String, dynamic>;
    } catch (e) {
      LogService.instance.error('[Cache] 解码作品详情缓存失败: $e');
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }
  }

  static Future<void> invalidateWorkDetailCache(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_detail_$workId';
    final cacheTimeKey = 'work_detail_time_$workId';

    await prefs.remove(cacheKey);
    await prefs.remove(cacheTimeKey);
    LogService.instance.info('[Cache] 已清除作品详情缓存: $workId');
  }

  static Future<void> cacheWorkTracks(int workId, String tracksJson) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_tracks_$workId';
    final cacheTimeKey = 'work_tracks_time_$workId';

    await prefs.setString(cacheKey, tracksJson);
    await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
  }

  static Future<String?> getCachedWorkTracks(int workId) async {
    final prefs = await StorageService.getPrefs();
    final cacheKey = 'work_tracks_$workId';
    final cacheTimeKey = 'work_tracks_time_$workId';

    final cachedData = prefs.getString(cacheKey);
    final cacheTime = prefs.getInt(cacheTimeKey);

    if (cachedData == null || cacheTime == null) {
      return null;
    }

    final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
    if (DateTime.now().difference(cacheDateTime) > workTracksCacheDuration) {
      await prefs.remove(cacheKey);
      await prefs.remove(cacheTimeKey);
      return null;
    }

    return cachedData;
  }

  static Future<String?> cacheAudioFile({
    required String hash,
    required String url,
    required Dio dio,
  }) async {
    try {
      final finalFile = await _audioFinalFile(hash);
      final file = finalFile;
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        if (DateTime.now().difference(lastModified) < audioCacheDuration) {
          LogService.instance.info('[Cache] 音频缓存命中: $hash');
          return file.path;
        }
        LogService.instance.info('[Cache] 音频缓存过期，重新下载: $hash');
        await file.delete();
        await _removeAudioCacheMeta(hash);
      }

      await resetAudioCachePartial(hash);
      final tempFile = await prepareAudioCacheTempFile(hash);

      LogService.instance.info('[Cache] 下载音频文件: $hash');

      dio.options.headers.addAll(CookieService.serverCookieHeaders);
      await dio.download(url, tempFile.path);

      await finalizeAudioCacheFile(hash, expectedSize: await tempFile.length());

      await checkAndCleanCache();
      return (await _audioFinalFile(hash)).path;
    } catch (e) {
      LogService.instance.error('[Cache] 缓存音频文件失败: $e');
      return null;
    }
  }

  static Future<String?> getCachedAudioFile(String hash) async {
    try {
      final downloadedFile = await _getDownloadedAudioFile(hash);
      if (downloadedFile != null) {
        LogService.instance.info('[Cache] 使用已下载的音频文件: $hash');
        return downloadedFile;
      }

      final finalFile = await _audioFinalFile(hash);
      final tempFile = await _audioTempFile(hash);

      if (!await finalFile.exists()) {
        if (await tempFile.exists()) {
          final lastModified = await tempFile.lastModified();
          if (DateTime.now().difference(lastModified) > audioCacheDuration) {
            await tempFile.delete();
          }
        }
        return null;
      }

      final file = finalFile;
      if (await file.exists()) {
        final prefs = await StorageService.getPrefs();
        final metaKey = 'audio_cache_meta_${_safeAudioHash(hash)}';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < audioCacheDuration) {
            LogService.instance.info('[Cache] 使用缓存的音频文件: $hash');
            return file.path;
          }
        }

        LogService.instance.info('[Cache] 音频缓存过期: $hash');
        await file.delete();
        await prefs.remove(metaKey);
        if (await tempFile.exists()) {
          await tempFile.delete();
        }
      }

      return null;
    } catch (e) {
      LogService.instance.error('[Cache] 获取缓存音频文件失败: $e');
      return null;
    }
  }

  static Future<String?> cacheFileResource({
    required int workId,
    required String hash,
    required String fileType,
    required String url,
    required Dio dio,
  }) async {
    try {
      final downloadedFile = await _getDownloadedFile(workId, hash, null);
      if (downloadedFile != null) {
        LogService.instance.info('[Cache] 使用已下载的文件: $hash');
        return downloadedFile;
      }

      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_$fileType';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        final lastModified = await file.lastModified();
        if (DateTime.now().difference(lastModified) < fileCacheDuration) {
          return filePath;
        }
        await file.delete();
      }

      dio.options.headers.addAll(CookieService.serverCookieHeaders);

      await dio.download(url, filePath);

      final prefs = await StorageService.getPrefs();
      final metaKey = 'file_cache_meta_${workId}_$safeHash';
      await prefs.setInt(metaKey, DateTime.now().millisecondsSinceEpoch);

      await checkAndCleanCache();

      return filePath;
    } catch (e) {
      LogService.instance.error('[Cache] 缓存文件失败: $e');
      return null;
    }
  }

  static Future<String?> getCachedFileResource({
    required int workId,
    required String hash,
    required String fileType,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_$fileType';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      if (await file.exists()) {
        final prefs = await StorageService.getPrefs();
        final metaKey = 'file_cache_meta_${workId}_$safeHash';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < fileCacheDuration) {
            return filePath;
          }
        }

        await file.delete();
        await prefs.remove(metaKey);
      }

      return null;
    } catch (e) {
      LogService.instance.error('[Cache] 获取缓存文件失败: $e');
      return null;
    }
  }

  static Future<void> cacheTextContent({
    required int workId,
    required String hash,
    required String content,
  }) async {
    try {
      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final fileName = '${workId}_${safeHash}_text.txt';
      final filePath = '${cacheDir.path}/$fileName';

      final file = File(filePath);
      await file.writeAsString(content);

      final prefs = await StorageService.getPrefs();
      final metaKey = 'text_cache_meta_${workId}_$safeHash';
      await prefs.setInt(metaKey, DateTime.now().millisecondsSinceEpoch);

      await checkAndCleanCache();
    } catch (e) {
      LogService.instance.error('[Cache] 缓存文本失败: $e');
    }
  }

  static Future<String?> getCachedTextContent({
    required int workId,
    required String hash,
    String? fileName,
  }) async {
    try {
      final downloadedFile = await _getDownloadedFile(workId, hash, fileName);
      if (downloadedFile != null) {
        final file = File(downloadedFile);
        if (await file.exists()) {
          LogService.instance.info('[Cache] 从已下载的文件读取文本内容: $hash');
          return await EncodingUtils.readFileAsString(file);
        }
      }

      final cacheDir = await _getCacheDirectory();
      final safeHash = hash.replaceAll('/', '_');
      final cacheFileName = '${workId}_${safeHash}_text.txt';
      final filePath = '${cacheDir.path}/$cacheFileName';

      final file = File(filePath);
      if (await file.exists()) {
        final prefs = await StorageService.getPrefs();
        final metaKey = 'text_cache_meta_${workId}_$safeHash';
        final cacheTime = prefs.getInt(metaKey);

        if (cacheTime != null) {
          final cacheDateTime = DateTime.fromMillisecondsSinceEpoch(cacheTime);
          if (DateTime.now().difference(cacheDateTime) < fileCacheDuration) {
            return await EncodingUtils.readFileAsString(file);
          }
        }

        await file.delete();
        await prefs.remove(metaKey);
      }

      return null;
    } catch (e) {
      LogService.instance.error('[Cache] 获取缓存文本失败: $e');
      return null;
    }
  }

  static Future<void> clearAllCache() async {
    try {
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        await cacheDir.delete(recursive: true);
      }

      await clearAudioCache();

      await clearImageCache();

      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('work_detail_') ||
            key.startsWith('work_tracks_') ||
            key.startsWith('file_cache_meta_') ||
            key.startsWith('text_cache_meta_') ||
            key.startsWith('audio_cache_meta_')) {
          await prefs.remove(key);
        }
      }

      LogService.instance.info('[Cache] 所有缓存已清除');
    } catch (e) {
      LogService.instance.error('[Cache] 清除缓存失败: $e');
      rethrow;
    }
  }

  static Future<void> clearAudioCache() async {
    try {
      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await customAudioCacheDir.delete(recursive: true);
        LogService.instance.info('[Cache] 自定义音频缓存已清除');
      }

      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      for (final key in keys) {
        if (key.startsWith('audio_cache_meta_')) {
          await prefs.remove(key);
        }
      }

      final appCacheDir = await getApplicationCacheDirectory();
      final justAudioCacheDir =
          Directory('${appCacheDir.path}/just_audio_cache');
      if (await justAudioCacheDir.exists()) {
        await justAudioCacheDir.delete(recursive: true);
        LogService.instance.info('[Cache] just_audio 缓存已清除');
      }
    } catch (e) {
      LogService.instance.error('[Cache] 清除音频缓存失败: $e');
    }
  }

  static Future<void> clearImageCache() async {
    try {
      final appCacheDir = await getApplicationCacheDirectory();
      final imageCacheDir = Directory('${appCacheDir.path}/libCachedImageData');

      if (await imageCacheDir.exists()) {
        await imageCacheDir.delete(recursive: true);
        LogService.instance.info('[Cache] 图片缓存已清除');
      }
    } catch (e) {
      LogService.instance.error('[Cache] 清除图片缓存失败: $e');
    }
  }

  static Future<int> getCacheSize() async {
    try {
      LogService.instance.info('[Cache] Getting cache size via isolate');

      final result = await _runCacheIoInIsolate(cleanExpired: false);
      final fileSize = result?.totalSize ?? 0;

      final prefsSize = await _getSharedPreferencesCacheSize();

      final total = fileSize + prefsSize;
      LogService.instance.info('[Cache] Cache size: ${_formatBytes(total)}');
      return total;
    } catch (e) {
      LogService.instance.error('[Cache] Failed to get cache size: $e');
      return 0;
    }
  }

  static Future<int> _getAudioCacheSize() async {
    try {
      int totalSize = 0;

      final customAudioCacheDir = await _getAudioCacheDirectory();
      if (await customAudioCacheDir.exists()) {
        await for (final entity in customAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      final appCacheDir = await getApplicationCacheDirectory();
      final justAudioCacheDir =
          Directory('${appCacheDir.path}/just_audio_cache');
      if (await justAudioCacheDir.exists()) {
        await for (final entity in justAudioCacheDir.list(recursive: true)) {
          if (entity is File) {
            totalSize += await entity.length();
          }
        }
      }

      return totalSize;
    } catch (e) {
      LogService.instance.error('[Cache] 获取音频缓存大小失败: $e');
      return 0;
    }
  }

  static Future<int> _getImageCacheSize() async {
    try {
      final appCacheDir = await getApplicationCacheDirectory();
      final imageCacheDir = Directory('${appCacheDir.path}/libCachedImageData');

      if (!await imageCacheDir.exists()) {
        return 0;
      }

      int totalSize = 0;
      await for (final entity in imageCacheDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return totalSize;
    } catch (e) {
      LogService.instance.error('[Cache] 获取图片缓存大小失败: $e');
      return 0;
    }
  }

  static Future<int> _getSharedPreferencesCacheSize() async {
    try {
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      int estimatedSize = 0;

      for (final key in keys) {
        if (key.startsWith('work_detail_') ||
            key.startsWith('work_tracks_') ||
            key.startsWith('file_cache_meta_') ||
            key.startsWith('text_cache_meta_') ||
            key.startsWith('audio_cache_meta_')) {
          estimatedSize += key.length;

          final value = prefs.get(key);
          if (value is String) {
            estimatedSize += value.length;
          } else if (value is int) {
            estimatedSize += 8;
          }
        }
      }

      return estimatedSize;
    } catch (e) {
      LogService.instance.error('[Cache] 获取 SharedPreferences 缓存大小失败: $e');
      return 0;
    }
  }

  static Future<Directory> _getCacheDirectory() async {
    final appCacheDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appCacheDir.path}/kikoeru_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  static Future<Directory> _getAudioCacheDirectory() async {
    final appCacheDir = await getApplicationCacheDirectory();
    final cacheDir = Directory('${appCacheDir.path}/kikoeru_audio_cache');

    if (!await cacheDir.exists()) {
      await cacheDir.create(recursive: true);
    }

    return cacheDir;
  }

  static Future<void> setCacheSizeLimit(int limitMB) async {
    final prefs = await StorageService.getPrefs();
    await prefs.setInt(cacheSizeLimitKey, limitMB);
  }

  static Future<int> getCacheSizeLimit() async {
    final prefs = await StorageService.getPrefs();
    return prefs.getInt(cacheSizeLimitKey) ?? defaultCacheSizeLimitMB;
  }

  static Future<void> checkAndCleanCache({bool force = false}) async {
    try {
      if (!force) {
        final prefs = await StorageService.getPrefs();
        final lastCheckTime = prefs.getInt(lastCleanCheckTimeKey);

        if (lastCheckTime != null) {
          final lastCheck = DateTime.fromMillisecondsSinceEpoch(lastCheckTime);
          final timeSinceLastCheck = DateTime.now().difference(lastCheck);

          if (timeSinceLastCheck < autoCleanCheckInterval) {
            return;
          }
        }

        await prefs.setInt(
            lastCleanCheckTimeKey, DateTime.now().millisecondsSinceEpoch);
      }

      final result = await _runCacheIoInIsolate(cleanExpired: true);
      if (result == null) return;

      final prefs = await StorageService.getPrefs();

      for (final fileName in result.deletedKikoeruFiles) {
        final parts = fileName.split('_');
        if (parts.length >= 2) {
          final workId = parts[0];
          final safeHash = parts[1];
          await prefs.remove('file_cache_meta_${workId}_$safeHash');
          await prefs.remove('text_cache_meta_${workId}_$safeHash');
        }
      }

      for (final hash in result.deletedAudioHashes) {
        await prefs.remove('audio_cache_meta_$hash');
      }

      await _cleanExpiredSharedPreferences();

      if (result.expiredFileCount > 0) {
        LogService.instance.info('[Cache] Isolate cleaned ${result.expiredFileCount} files, size: ${_formatBytes(result.totalSize)}');
      }
    } catch (e) {
      LogService.instance.error('[Cache] Auto cleanup failed: $e');
    }
  }

  static Future<int> _cleanExpiredSharedPreferences() async {
    try {
      final prefs = await StorageService.getPrefs();
      final keys = prefs.getKeys();
      final now = DateTime.now();
      int deletedCount = 0;

      for (final key in keys) {
        if (key.startsWith('work_detail_time_')) {
          final cacheTime = prefs.getInt(key);
          if (cacheTime != null) {
            final cacheDateTime =
                DateTime.fromMillisecondsSinceEpoch(cacheTime);
            if (now.difference(cacheDateTime) > workDetailCacheDuration) {
              final workId = key.replaceFirst('work_detail_time_', '');
              await prefs.remove('work_detail_$workId');
              await prefs.remove(key);
              deletedCount += 2;
            }
          }
        }
        else if (key.startsWith('work_tracks_time_')) {
          final cacheTime = prefs.getInt(key);
          if (cacheTime != null) {
            final cacheDateTime =
                DateTime.fromMillisecondsSinceEpoch(cacheTime);
            if (now.difference(cacheDateTime) > workTracksCacheDuration) {
              final workId = key.replaceFirst('work_tracks_time_', '');
              await prefs.remove('work_tracks_$workId');
              await prefs.remove(key);
              deletedCount += 2;
            }
          }
        }
      }

      return deletedCount;
    } catch (e) {
      LogService.instance.error('[Cache] 清理过期 SharedPreferences 失败: $e');
      return 0;
    }
  }

  static Future<String?> _getDownloadedAudioFile(String hash) async {
    try {
      final downloadService = DownloadService.instance;
      final tasks = downloadService.tasks;

      for (final task in tasks) {
        if (task.hash == hash && task.status == DownloadStatus.completed) {
          final filePath = await downloadService.getDownloadedFilePath(
            task.workId,
            hash,
          );
          if (filePath != null) {
            final file = File(filePath);
            if (await file.exists()) {
              return filePath;
            }
          }
        }
      }

      return null;
    } catch (e) {
      LogService.instance.error('[Cache] 获取下载文件失败: $e');
      return null;
    }
  }

  static Future<String?> _getDownloadedFile(
    int workId,
    String hash,
    String? fileName,
  ) async {
    try {
      final downloadService = DownloadService.instance;

      String actualHash = hash;
      if (hash.contains('/')) {
        final parts = hash.split('/');
        if (parts.length == 2) {
          actualHash = parts[1];
        }
      }

      final filePath =
          await downloadService.getDownloadedFilePath(workId, actualHash);
      if (filePath != null) {
        final file = File(filePath);
        if (await file.exists()) {
          return filePath;
        }
      }

      if (fileName != null && fileName.isNotEmpty) {
        try {
          final downloadDir = await downloadService.getDownloadDirectory();
          final workDir =
              Directory(p.join(downloadDir.path, workId.toString()));

          if (await workDir.exists()) {
            await for (final entity in workDir.list(recursive: true)) {
              if (entity is File) {
                final entityFileName =
                    entity.path.split(Platform.pathSeparator).last;
                if (entityFileName == fileName) {
                  LogService.instance.info('[Cache] 找到手动复制的文件: ${entity.path}');
                  return entity.path;
                }
              }
            }
          }
        } catch (e) {
          LogService.instance.error('[Cache] 检查手动复制文件失败: $e');
        }
      }

      return null;
    } catch (e) {
      LogService.instance.error('[Cache] 获取下载文件失败: $e');
      return null;
    }
  }

  static String _formatBytes(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    } else if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else {
      return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
    }
  }

  static Future<String> getFormattedCacheSize() async {
    final size = await getCacheSize();
    return _formatBytes(size);
  }

  /// Returns a breakdown of cache sizes by category in bytes.
  /// Keys: 'audio', 'image', 'other', 'total'
  static Future<Map<String, int>> getCacheBreakdown() async {
    try {
      final audioSize = await _getAudioCacheSize();
      final imageSize = await _getImageCacheSize();
      final prefsSize = await _getSharedPreferencesCacheSize();

      int otherSize = 0;
      final cacheDir = await _getCacheDirectory();
      if (await cacheDir.exists()) {
        int mainSize = 0;
        await for (final entity in cacheDir.list(recursive: true)) {
          if (entity is File) {
            mainSize += await entity.length();
          }
        }
        otherSize = mainSize;
      }

      final total = audioSize + imageSize + otherSize + prefsSize;

      return {
        'audio': audioSize,
        'image': imageSize,
        'other': otherSize + prefsSize,
        'total': total,
      };
    } catch (e) {
      LogService.instance.error('[Cache] 获取缓存分解失败: $e');
      return {'audio': 0, 'image': 0, 'other': 0, 'total': 0};
    }
  }

  /// Format bytes to human-readable string (public version)
  static String formatBytes(int bytes) {
    return _formatBytes(bytes);
  }

  /// Runs heavy file I/O operations (cache size scanning, expired file cleanup)
  /// in a separate isolate to avoid blocking the main thread.
  static Future<_IsolateCacheResult?> _runCacheIoInIsolate({bool cleanExpired = true}) async {
    try {
      final cacheDirPath = (await _getCacheDirectory()).path;
      final audioCacheDirPath = (await _getAudioCacheDirectory()).path;
      final appCacheDirPath = (await getApplicationCacheDirectory()).path;
      final limitBytes = (await getCacheSizeLimit()) * 1024 * 1024;

      return Isolate.run(() {
        return _doCacheFileIo(
          cacheDirPath: cacheDirPath,
          audioCacheDirPath: audioCacheDirPath,
          appCacheDirPath: appCacheDirPath,
          limitBytes: limitBytes,
          cleanExpired: cleanExpired,
        );
      });
    } catch (e) {
      LogService.instance.error('[Cache] Isolate I/O failed: $e');
      return null;
    }
  }
}

/// Result from [CacheService._runCacheIoInIsolate].
class _IsolateCacheResult {
  final int totalSize;
  final int expiredFileCount;
  final List<String> deletedKikoeruFiles;
  final List<String> deletedAudioHashes;

  const _IsolateCacheResult({
    required this.totalSize,
    this.expiredFileCount = 0,
    this.deletedKikoeruFiles = const [],
    this.deletedAudioHashes = const [],
  });
}

/// Top-level function that runs in [Isolate.run].
/// Does ONLY pure dart:io file operations — NO SharedPreferences.
_IsolateCacheResult _doCacheFileIo({
  required String cacheDirPath,
  required String audioCacheDirPath,
  required String appCacheDirPath,
  required int limitBytes,
  required bool cleanExpired,
}) {
  final now = DateTime.now();
  const fileCacheDuration = CacheService.fileCacheDuration;
  const audioCacheDuration = CacheService.audioCacheDuration;

  final deletedKikoeruFiles = <String>[];
  final deletedAudioHashes = <String>[];
  int expiredFileCount = 0;
  int totalSize = 0;

  final cacheDir = Directory(cacheDirPath);
  if (cacheDir.existsSync()) {
    for (final entity in cacheDir.listSync(recursive: true)) {
      if (entity is File) {
        totalSize += entity.lengthSync();
        if (cleanExpired) {
          final modified = entity.lastModifiedSync();
          if (now.difference(modified) > fileCacheDuration) {
            final name = entity.path.split(Platform.pathSeparator).last;
            entity.deleteSync();
            deletedKikoeruFiles.add(name);
            expiredFileCount++;
          }
        }
      }
    }
  }

  final audioCacheDir = Directory(audioCacheDirPath);
  if (audioCacheDir.existsSync()) {
    for (final entity in audioCacheDir.listSync(recursive: true)) {
      if (entity is File) {
        totalSize += entity.lengthSync();
        if (cleanExpired) {
          final modified = entity.lastModifiedSync();
          if (now.difference(modified) > audioCacheDuration) {
            final name = entity.path.split(Platform.pathSeparator).last;
            entity.deleteSync();
            expiredFileCount++;
            if (name.endsWith('.audio')) {
              deletedAudioHashes.add(name.replaceAll('.audio', ''));
            }
          }
        }
      }
    }
  }

  final justAudioDir = Directory('$appCacheDirPath/just_audio_cache');
  if (justAudioDir.existsSync()) {
    for (final entity in justAudioDir.listSync(recursive: true)) {
      if (entity is File) {
        totalSize += entity.lengthSync();
        if (cleanExpired) {
          final modified = entity.lastModifiedSync();
          if (now.difference(modified) > audioCacheDuration) {
            entity.deleteSync();
            expiredFileCount++;
          }
        }
      }
    }
  }

  final imageCacheDir = Directory('$appCacheDirPath/libCachedImageData');
  if (imageCacheDir.existsSync()) {
    for (final entity in imageCacheDir.listSync(recursive: true)) {
      if (entity is File) {
        totalSize += entity.lengthSync();
      }
    }
  }

  if (cleanExpired && totalSize > limitBytes) {
    final allEntries = <_FileEntry>[];

    void collectDir(String dirPath) {
      final dir = Directory(dirPath);
      if (dir.existsSync()) {
        for (final entity in dir.listSync(recursive: true)) {
          if (entity is File) {
            allEntries.add(_FileEntry(
              path: entity.path,
              size: entity.lengthSync(),
              modified: entity.lastModifiedSync(),
            ));
          }
        }
      }
    }

    collectDir(cacheDirPath);
    collectDir(audioCacheDirPath);

    allEntries.sort((a, b) => a.modified.compareTo(b.modified));

    final targetSize = (limitBytes * 0.8).toInt();
    int currentSize = totalSize;

    for (final entry in allEntries) {
      if (currentSize <= targetSize) break;
      File(entry.path).deleteSync();
      currentSize -= entry.size;
      expiredFileCount++;

      final name = entry.path.split(Platform.pathSeparator).last;
      if (entry.path.contains('kikoeru_cache')) {
        deletedKikoeruFiles.add(name);
      } else if (entry.path.contains('kikoeru_audio_cache') && name.endsWith('.audio')) {
        deletedAudioHashes.add(name.replaceAll('.audio', ''));
      }
    }
    totalSize = currentSize;
  }

  return _IsolateCacheResult(
    totalSize: totalSize,
    expiredFileCount: expiredFileCount,
    deletedKikoeruFiles: deletedKikoeruFiles,
    deletedAudioHashes: deletedAudioHashes,
  );
}

/// Helper for file entries used in the isolate function.
class _FileEntry {
  final String path;
  final int size;
  final DateTime modified;

  const _FileEntry({
    required this.path,
    required this.size,
    required this.modified,
  });
}