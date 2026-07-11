import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import '../widgets/custom_file_picker.dart';
import 'storage_service.dart';
import 'log_service.dart';

final _log = LogService.instance;

/// 下载路径管理服务
class DownloadPathService {
  static const String _customPathKey = 'custom_download_path';

  /// 获取当前下载路径（自定义路径或默认路径）
  static Future<Directory> getDownloadDirectory() async {
    final customPath = StorageService.getString(_customPathKey);

    if (customPath != null && customPath.isNotEmpty) {
      final dir = Directory(customPath);
      if (await dir.exists()) {
        return dir;
      }
      await clearCustomPath();
    }

    return _getDefaultDownloadDirectory();
  }

  /// 获取默认下载路径
  static Future<Directory> _getDefaultDownloadDirectory() async {
    final appDir = await getApplicationDocumentsDirectory();
    final downloadDir = Directory('${appDir.path}/downloads');
    if (!await downloadDir.exists()) {
      await downloadDir.create(recursive: true);
    }
    return downloadDir;
  }

  /// 获取自定义路径（如果设置了）
  static String? getCustomPath() {
    return StorageService.getString(_customPathKey);
  }

  /// 检查是否设置了自定义路径
  static bool hasCustomPath() {
    final path = StorageService.getString(_customPathKey);
    return path != null && path.isNotEmpty;
  }

  /// 清除自定义路径
  static Future<void> clearCustomPath() async {
    await StorageService.remove(_customPathKey);
  }

  /// 选择自定义下载目录
  /// 返回 null 表示用户取消选择
  /// 返回路径字符串表示成功
  ///
  /// [context] is required on Android to show the custom file picker dialog.
  static Future<String?> pickCustomDirectory({BuildContext? context}) async {
    if (Platform.isAndroid) {
      return await _pickDirectoryAndroid(context: context);
    } else if (Platform.isIOS) {
      return await _pickDirectoryIOS();
    } else if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
      return await _pickDirectoryDesktop();
    }
    return null;
  }

  /// Android 平台选择目录
  ///
  /// Uses the in-app custom file browser ([CustomFilePicker]) instead of SAF
  /// (Storage Access Framework), because SAF's `ACTION_OPEN_DOCUMENT_TREE`
  /// is broken on MIUI/HyperOS (shows empty folder).
  ///
  /// On Android 11+, requests [Permission.manageExternalStorage] first.
  /// If granted, [CustomFilePicker] uses [dart:io] to browse the filesystem.
  static Future<String?> _pickDirectoryAndroid({BuildContext? context}) async {
    if (context == null) {
      _log.error('Context required for Android custom file picker',
          tag: 'DownloadPath');
      return null;
    }
    return CustomFilePicker.pickDirectory(context: context);
  }

  /// iOS 平台选择目录
  static Future<String?> _pickDirectoryIOS() async {
    final result = await FilePicker.getDirectoryPath();
    return result;
  }

  /// 桌面平台（Windows/macOS/Linux）选择目录
  static Future<String?> _pickDirectoryDesktop() async {
    final result = await FilePicker.getDirectoryPath();
    return result;
  }

  /// 设置自定义下载路径并迁移文件
  /// 返回迁移结果消息
  static Future<MigrationResult> setCustomPath(String newPath) async {
    final newDir = Directory(newPath);

    if (!await newDir.exists()) {
      try {
        await newDir.create(recursive: true);
      } catch (e) {
        return MigrationResult(
          success: false,
          message: '无法创建目录: $e',
        );
      }
    }

    final oldDir = await getDownloadDirectory();

    if (oldDir.path == newPath) {
      return MigrationResult(
        success: true,
        message: '目录未改变，无需迁移',
      );
    }

    final migrationResult = await _migrateFiles(oldDir, newDir);

    if (migrationResult.success) {
      await StorageService.setString(_customPathKey, newPath);
    }

    return migrationResult;
  }

  /// 将下载目录迁移回默认路径
  static Future<MigrationResult> migrateToDefaultPath() async {
    final currentDir = await getDownloadDirectory();
    final defaultDir = await _getDefaultDownloadDirectory();

    if (currentDir.path == defaultDir.path) {
      await clearCustomPath();
      return MigrationResult(
        success: true,
        message: '当前已使用默认路径',
      );
    }

    final result = await _migrateFiles(currentDir, defaultDir);

    if (result.success) {
      await clearCustomPath();
    }

    return result;
  }

  /// 迁移文件从旧目录到新目录
  /// 只迁移符合下载结构的文件（以数字命名的 workId 文件夹）
  /// 保护用户可能存放在下载目录中的其他文件
  static Future<MigrationResult> _migrateFiles(
    Directory oldDir,
    Directory newDir,
  ) async {
    try {
      if (!await oldDir.exists()) {
        return MigrationResult(
          success: true,
          message: '原目录不存在，无需迁移',
        );
      }

      int fileCount = 0;
      int workFolderCount = 0;
      int skippedCount = 0;
      int errorCount = 0;
      final List<String> skippedItems = [];

      await for (final entity in oldDir.list(followLinks: false)) {
        if (entity is Directory) {
          final folderName = entity.path.split(Platform.pathSeparator).last;
          final workId = int.tryParse(folderName);

          if (workId != null || folderName == 'subtitle_library') {
            try {
              final newWorkDir = Directory('${newDir.path}/$folderName');
              await newWorkDir.create(recursive: true);

              int folderFileCount = 0;
              await for (final fileEntity
                  in entity.list(recursive: true, followLinks: false)) {
                try {
                  final relativePath =
                      fileEntity.path.substring(entity.path.length + 1);
                  final newPath = '${newWorkDir.path}/$relativePath';

                  if (fileEntity is File) {
                    final newFile = File(newPath);
                    await newFile.parent.create(recursive: true);
                    await fileEntity.copy(newPath);
                    folderFileCount++;
                  } else if (fileEntity is Directory) {
                    await Directory(newPath).create(recursive: true);
                  }
                } catch (e) {
                  _log.error('复制文件失败: ${fileEntity.path}, 错误: $e', tag: 'DownloadPath');
                  errorCount++;
                }
              }

              fileCount += folderFileCount;
              workFolderCount++;
              if (folderName == 'subtitle_library') {
                _log.info('已迁移字幕库: $folderFileCount 个文件', tag: 'DownloadPath');
              } else {
                _log.info('已迁移作品文件夹 $folderName: $folderFileCount 个文件', tag: 'DownloadPath');
              }

              try {
                await entity.delete(recursive: true);
              } catch (e) {
                _log.error('删除原文件夹失败: $folderName, 错误: $e', tag: 'DownloadPath');
                errorCount++;
              }
            } catch (e) {
              _log.error('迁移文件夹失败: $folderName, 错误: $e', tag: 'DownloadPath');
              errorCount++;
            }
          } else {
            skippedCount++;
            skippedItems.add(folderName);
            _log.debug('跳过文件夹: $folderName', tag: 'DownloadPath');
          }
        } else if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          skippedCount++;
          skippedItems.add(fileName);
          _log.debug('跳过根目录文件: $fileName', tag: 'DownloadPath');
        }
      }

      bool isOldDirEmpty = true;
      try {
        final remainingEntities = await oldDir.list().toList();
        isOldDirEmpty = remainingEntities.isEmpty;

        if (isOldDirEmpty) {
          try {
            await oldDir.delete(recursive: false);
            _log.info('已删除空的旧目录', tag: 'DownloadPath');
          } catch (e) {
            _log.error('删除空目录失败: $e', tag: 'DownloadPath');
          }
        } else {
          _log.info('旧目录中还有 ${remainingEntities.length} 个项目，保留目录', tag: 'DownloadPath');
        }
      } catch (e) {
        _log.error('检查旧目录是否为空时出错: $e', tag: 'DownloadPath');
      }

      String resultMessage = '迁移完成: $workFolderCount 个作品文件夹, $fileCount 个文件';
      if (skippedCount > 0) {
        resultMessage += '\n跳过 $skippedCount 个非下载项目（已保留）';
        if (skippedItems.length <= 5) {
          resultMessage += ': ${skippedItems.join(", ")}';
        }
      }
      if (errorCount > 0) {
        resultMessage += '\n$errorCount 个错误';
      }
      if (!isOldDirEmpty) {
        resultMessage += '\n原目录保留（包含其他文件）';
      }

      return MigrationResult(
        success: true,
        message: resultMessage,
        fileCount: fileCount,
        errorCount: errorCount,
      );
    } catch (e) {
      return MigrationResult(
        success: false,
        message: '迁移失败: $e',
      );
    }
  }

  /// 检查平台是否支持自定义路径
  static bool isPlatformSupported() {
    return Platform.isWindows ||
        Platform.isMacOS ||
        Platform.isAndroid ||
        Platform.isLinux;
  }

  /// 获取平台友好的提示信息
  static String getPlatformHint() {
    if (Platform.isAndroid) {
      return 'Android: 将使用系统文件选择器，可能需要存储权限';
    } else if (Platform.isIOS) {
      return 'iOS: 受系统限制，使用默认路径，可使用系统默认文件浏览器查看';
    } else if (Platform.isWindows) {
      return 'Windows: 可选择任意可访问的目录';
    } else if (Platform.isMacOS) {
      return 'macOS: 可选择任意可访问的目录';
    }
    return '选择一个用于保存下载文件的目录';
  }
}

/// 迁移结果
class MigrationResult {
  final bool success;
  final String message;
  final int fileCount;
  final int errorCount;

  MigrationResult({
    required this.success,
    required this.message,
    this.fileCount = 0,
    this.errorCount = 0,
  });
}