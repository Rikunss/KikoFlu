import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../models/download_task.dart';
import '../../providers/settings_provider.dart';
import '../../services/download_service.dart';
import '../../services/subtitle_library_service.dart';
import '../../utils/file_icon_utils.dart';

/// Direction to pass to explorer actions.
enum ExplorerAction { playAudio, playVideo, previewImage, previewText, previewPdf, loadSubtitle, delete }

/// Callbacks that each explorer widget must provide.
typedef ExplorerActionCallback = void Function(ExplorerAction action, Map<String, dynamic> item, String parentPath);
typedef ExplorerAsyncActionCallback = Future<void> Function(ExplorerAction action, Map<String, dynamic> item, String parentPath);
typedef ExplorerItemAccessor = String? Function(Map<String, dynamic> item, String key);

/// Safe property accessor for file tree items.
String? getItemProperty(Map<String, dynamic> item, String key, {String? defaultValue}) {
  return (item[key] as String?) ?? defaultValue;
}

/// Get a dynamic property from a file tree item.
dynamic getItemPropertyDynamic(Map<String, dynamic> item, String key, {dynamic defaultValue}) {
  return item[key] ?? defaultValue;
}

/// Generate a unique path for a file/folder item.
String getItemPath(String parentPath, Map<String, dynamic> item) {
  final title = item['title'] as String? ?? item['name'] as String? ?? 'unknown';
  return parentPath.isEmpty ? title : '$parentPath/$title';
}

/// Format duration (seconds -> H:MM:SS or M:SS).
String formatDuration(dynamic durationValue) {
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
  }
  return '$minutes:${seconds.toString().padLeft(2, '0')}';
}

/// Format file size in human-readable format.
String formatFileSize(int? bytes) {
  if (bytes == null || bytes <= 0) return '';
  const units = ['B', 'KB', 'MB', 'GB'];
  int unitIndex = 0;
  double size = bytes.toDouble();
  while (size >= 1024 && unitIndex < units.length - 1) {
    size /= 1024;
    unitIndex++;
  }
  if (unitIndex == 0) return '$bytes B';
  return '${size.toStringAsFixed(2)} ${units[unitIndex]}';
}

/// Expand all parent folders along the path to [targetPath].
void expandPathToFolder(Set<String> expandedFolders, String targetPath) {
  final segments = targetPath.split('/');
  String currentPath = '';
  for (int i = 0; i < segments.length; i++) {
    currentPath = i == 0 ? segments[i] : '$currentPath/${segments[i]}';
    expandedFolders.add(currentPath);
  }
}

/// Toggle a folder's expanded state.
void toggleFolder(Set<String> expandedFolders, String path) {
  if (expandedFolders.contains(path)) {
    expandedFolders.remove(path);
  } else {
    expandedFolders.add(path);
  }
}

/// Find a folder's children by path.
List<Map<String, dynamic>>? findFolderChildren(
    List<Map<String, dynamic>> items, String targetPath) {
  final segments = targetPath.split('/');
  List<Map<String, dynamic>> currentItems = items;

  for (final segment in segments) {
    bool found = false;
    for (final item in currentItems) {
      final title = item['title'] as String? ?? item['name'] as String? ?? '';
      if (title == segment && item['type'] == 'folder') {
        currentItems = (item['children'] as List<dynamic>?)
                ?.cast<Map<String, dynamic>>() ??
            [];
        found = true;
        break;
      }
    }
    if (!found) return [];
  }
  return currentItems;
}

/// Check which audio files have matching subtitles in the subtitle library.
Future<Set<String>> checkLibrarySubtitles({
  required int workId,
  required List<Map<String, dynamic>> items,
  required String Function(Map<String, dynamic> item) getTitle,
}) async {
  final subtitledAudioFiles = <String>{};
  try {
    final libraryDir = await SubtitleLibraryService.getSubtitleLibraryDirectory();
    if (!await libraryDir.exists()) return subtitledAudioFiles;

    final parsedFolderPath =
        '${libraryDir.path}/${SubtitleLibraryService.parsedFolderName}';
    final possibleFolderNames = [
      'RJ$workId', 'RJ0$workId', 'BJ$workId', 'BJ0$workId', 'VJ$workId', 'VJ0$workId',
    ];

    final audioFiles = <String>[];
    void collectAudioFiles(List<Map<String, dynamic>> fileItems) {
      for (final item in fileItems) {
        final title = getTitle(item);
        if (FileIconUtils.isAudioFile(item) && title.isNotEmpty) {
          audioFiles.add(title);
        }
        final children = (item['children'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>();
        if (children != null) collectAudioFiles(children);
      }
    }
    collectAudioFiles(items);

    for (final folderName in possibleFolderNames) {
      final folderPath = '$parsedFolderPath/$folderName';
      final folder = Directory(folderPath);
      if (!await folder.exists()) continue;
      await for (final entity in folder.list(recursive: true)) {
        if (entity is File) {
          final fileName = entity.path.split(Platform.pathSeparator).last;
          for (final audioFile in audioFiles) {
            if (SubtitleLibraryService.isSubtitleForAudio(fileName, audioFile)) {
              subtitledAudioFiles.add(audioFile);
            }
          }
        }
      }
    }
  } catch (e) {
  }
  return subtitledAudioFiles;
}

/// Statistics for a folder.
class FolderStats {
  final int audioCount;
  final int textCount;
  FolderStats(this.audioCount, this.textCount);
}

/// Count audio and text files in a folder (non-recursive).
FolderStats countFilesInFolder(
  List<Map<String, dynamic>> items,
  Set<String> subtitledAudioFiles,
  String Function(Map<String, dynamic>) getTitle,
) {
  int audioCount = 0;
  int textCount = 0;
  for (final child in items) {
    if (FileIconUtils.isAudioFile(child)) {
      audioCount++;
      final title = getTitle(child);
      if (subtitledAudioFiles.contains(title)) textCount++;
    } else if (FileIconUtils.isTextFile(child)) {
      textCount++;
    }
  }
  return FolderStats(audioCount, textCount);
}

/// Select the best folder by audio format preference.
String? selectByAudioFormatPreference(
  List<String> candidates,
  List<AudioFormat> priorityOrder,
  List<Map<String, dynamic>> items,
) {
  Map<String, int> folderPriorities = {};
  for (final folderPath in candidates) {
    final folderChildren = findFolderChildren(items, folderPath) ?? [];
    int highestPriority = priorityOrder.length;
    for (final child in folderChildren) {
      if (FileIconUtils.isAudioFile(child)) {
        final fileName =
            ((child['title'] as String?) ?? (child['name'] as String?) ?? '').toLowerCase();
        for (int i = 0; i < priorityOrder.length; i++) {
          final format = priorityOrder[i];
          if (fileName.endsWith('.${format.extension}')) {
            if (i < highestPriority) highestPriority = i;
            break;
          }
        }
      }
    }
    folderPriorities[folderPath] = highestPriority;
  }

  String selected = candidates.first;
  int best = folderPriorities[selected] ?? priorityOrder.length;
  for (final path in candidates) {
    final p = folderPriorities[path] ?? priorityOrder.length;
    if (p < best) {
      best = p;
      selected = path;
    }
  }
  return selected;
}

/// Identify the main folder (most audio files, tie-break by text count, then format).
String? identifyMainFolder(
  List<Map<String, dynamic>> items,
  Set<String> expandedFolders,
  Set<String> subtitledAudioFiles,
  String Function(Map<String, dynamic>) getTitle,
  List<AudioFormat> priorityOrder,
) {
  if (items.isEmpty) return null;
  if (items.any((item) => FileIconUtils.isAudioFile(item))) return '';

  final folderStats = <String, FolderStats>{};
  void analyzeFolders(List<Map<String, dynamic>> fileItems, String parentPath) {
    for (final item in fileItems) {
      if (item['type'] == 'folder') {
        final children = (item['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
        if (children != null && children.isNotEmpty) {
          final path = getItemPath(parentPath, item);
          folderStats[path] = countFilesInFolder(children, subtitledAudioFiles, getTitle);
          analyzeFolders(children, path);
        }
      }
    }
  }
  analyzeFolders(items, '');
  if (folderStats.isEmpty) return null;

  int maxAudio = 0;
  for (final s in folderStats.values) {
    if (s.audioCount > maxAudio) maxAudio = s.audioCount;
  }

  int maxText = -1;
  List<String> candidates = [];
  for (final entry in folderStats.entries) {
    if (entry.value.audioCount == maxAudio && entry.value.textCount > maxText) {
      maxText = entry.value.textCount;
      candidates = [entry.key];
    } else if (entry.value.audioCount == maxAudio && entry.value.textCount == maxText) {
      candidates.add(entry.key);
    }
  }

  String? mainFolder;
  if (candidates.length > 1) {
    mainFolder = selectByAudioFormatPreference(candidates, priorityOrder, items);
  } else if (candidates.isNotEmpty) {
    mainFolder = candidates.first;
  }

  if (mainFolder != null) {
    expandPathToFolder(expandedFolders, mainFolder);
  }
  return mainFolder;
}

/// Get all audio files from the same directory (non-recursive).
List<Map<String, dynamic>> getAudioFilesFromSameDirectory(
  List<Map<String, dynamic>> items,
  String targetPath,
) {
  final audioFiles = <Map<String, dynamic>>[];
  if (targetPath.isEmpty) {
    for (final item in items) {
      if (FileIconUtils.isAudioFile(item)) audioFiles.add(item);
    }
    return audioFiles;
  }
  List<Map<String, dynamic>>? findFolder(
      List<Map<String, dynamic>> fileItems, String currentPath) {
    for (final item in fileItems) {
      if (item['type'] == 'folder') {
        final itemPath = getItemPath(currentPath, item);
        if (itemPath == targetPath) {
          return (item['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
        }
        final children = (item['children'] as List<dynamic>?)?.cast<Map<String, dynamic>>();
        if (children != null) {
          final result = findFolder(children, itemPath);
          if (result != null) return result;
        }
      }
    }
    return null;
  }
  final folderContents = findFolder(items, '');
  if (folderContents != null) {
    for (final item in folderContents) {
      if (FileIconUtils.isAudioFile(item)) audioFiles.add(item);
    }
  }
  return audioFiles;
}