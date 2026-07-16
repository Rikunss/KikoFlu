import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';

import 'account_database.dart';
import 'history_database.dart';
import 'log_service.dart';
import 'storage_service.dart';
import 'subtitle_database.dart';

final _log = LogService.instance;

/// Error thrown during backup/restore with a user-friendly message.
class BackupException implements Exception {
  final String message;
  const BackupException(this.message);

  @override
  String toString() => 'BackupException: $message';
}

/// Backup & Restore service for KikoFlu.
///
/// Exports all app data (SQLite databases, Hive boxes, SharedPreferences)
/// into a single .zip file, and restores from it.
class BackupService {
  BackupService._();

  /// Export all app data to [destinationPath] as a .zip file.
  ///
  /// Returns the final path of the created backup file.
  static Future<String> exportBackup(String destinationPath) async {
    final archive = Archive();
    final tmpDir = await _createTempDir();
    try {
      final dbDir = await _getDatabaseDirectory();
      final hiveDir = await _getHiveDirectory();

      await _closeAll();

      final prefsJson = await _exportPreferencesJson();
      final prefsFile = File(p.join(tmpDir.path, 'preferences.json'));
      await prefsFile.writeAsString(prefsJson);
      await _addFileToArchive(archive, 'preferences.json', prefsFile);

      for (final dbName in _kDatabaseFiles) {
        final src = File(p.join(dbDir.path, dbName));
        if (await src.exists()) {
          final dest = File(p.join(tmpDir.path, 'databases', dbName));
          await dest.parent.create(recursive: true);
          await src.copy(dest.path);
          await _addFileToArchive(
              archive, 'databases/$dbName', dest);
        } else {
          _log.warning('[Backup] Database file not found: $dbName');
        }
      }

      for (final hiveName in _kHiveFiles) {
        final src = File(p.join(hiveDir.path, hiveName));
        if (await src.exists()) {
          final dest = File(p.join(tmpDir.path, 'hive', hiveName));
          await dest.parent.create(recursive: true);
          await src.copy(dest.path);
          await _addFileToArchive(archive, 'hive/$hiveName', dest);
        } else {
          _log.warning('[Backup] Hive file not found: $hiveName');
        }
      }

      final pkgInfo = await _getPackageInfo();
      final manifest = {
        'app_name': pkgInfo['app_name'],
        'version': pkgInfo['version'],
        'backup_time': DateTime.now().toIso8601String(),
        'data_summary': {
          'databases': _kDatabaseFiles,
          'hive_boxes': _kHiveFiles,
          'preferences_exported': true,
        },
      };
      final manifestJson = const JsonEncoder.withIndent('  ').convert(manifest);
      archive.addFile(ArchiveFile(
        'manifest.json',
        manifestJson.length,
        utf8.encode(manifestJson),
      ));

      final zipBytes = ZipEncoder().encode(archive);
      if (zipBytes == null) {
        throw const BackupException('Failed to create zip archive');
      }
      final backupFile = File(destinationPath);
      await backupFile.writeAsBytes(zipBytes);

      _log.info('[Backup] Backup saved to: $destinationPath');
      return destinationPath;
    } finally {
      await _reopenAll();
      await tmpDir.delete(recursive: true);
    }
  }

  /// Restore app data from [backupFilePath] (.zip).
  ///
  /// On success, returns a list of warning messages (e.g. missing files).
  /// The app should be restarted after a successful restore.
  static Future<List<String>> importBackup(String backupFilePath) async {
    final warnings = <String>[];
    final tmpDir = await _createTempDir();
    try {
      final zipBytes = await File(backupFilePath).readAsBytes();
      final archive = ZipDecoder().decodeBytes(zipBytes);
      if (archive.isEmpty) {
        throw const BackupException('Invalid backup file: not a valid zip archive');
      }

      for (final file in archive) {
        if (file.isFile) {
          final destPath = p.join(tmpDir.path, file.name);
          final destFile = File(destPath);
          await destFile.parent.create(recursive: true);
          await destFile.writeAsBytes(file.content as List<int>);
        }
      }

      final manifestFile = File(p.join(tmpDir.path, 'manifest.json'));
      if (!await manifestFile.exists()) {
        throw const BackupException(
            'Invalid backup file: manifest.json not found');
      }
      final manifestJson = await manifestFile.readAsString();
      final manifest =
          jsonDecode(manifestJson) as Map<String, dynamic>;
      final version = '${manifest['version'] ?? 'unknown'}';
      _log.info('[Backup] Restoring from backup created by v$version');

      await _closeAll();

      final prefsFile = File(p.join(tmpDir.path, 'preferences.json'));
      if (await prefsFile.exists()) {
        await _importPreferencesJson(await prefsFile.readAsString());
      } else {
        warnings.add('preferences.json not found in backup');
      }

      final dbDir = await _getDatabaseDirectory();
      for (final dbName in _kDatabaseFiles) {
        final src = File(p.join(tmpDir.path, 'databases', dbName));
        if (await src.exists()) {
          final dest = File(p.join(dbDir.path, dbName));
          await src.copy(dest.path);
        } else {
          warnings.add('Database file not found in backup: $dbName');
        }
      }

      final hiveDir = await _getHiveDirectory();
      for (final hiveName in _kHiveFiles) {
        final src = File(p.join(tmpDir.path, 'hive', hiveName));
        if (await src.exists()) {
          final dest = File(p.join(hiveDir.path, hiveName));
          await src.copy(dest.path);
        } else {
          warnings.add('Hive file not found in backup: $hiveName');
        }
      }

      _log.info('[Backup] Restore completed successfully');
      return warnings;
    } finally {
      await _reopenAll();
      await tmpDir.delete(recursive: true);
    }
  }

  static const _kDatabaseFiles = [
    'accounts.db',
    'history.db',
    'subtitle_library.db',
  ];

  static const _kHiveFiles = [
    'settings.hive',
    'settings.lock',
    'users.hive',
    'users.lock',
  ];

  static Future<Directory> _getDatabaseDirectory() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      return Directory(p.join(appDocDir.path, 'KikoFlu'));
    } else {
      return Directory(await getDatabasesPath());
    }
  }

  static Future<Directory> _getHiveDirectory() async {
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      return Directory(p.join(appDocDir.path, 'KikoFlu'));
    } else {
      return Directory((await getApplicationDocumentsDirectory()).path);
    }
  }

  static Future<Directory> _createTempDir() async {
    final tmp = await Directory.systemTemp.createTemp('kikoflu_backup_');
    return tmp;
  }

  static Future<void> _addFileToArchive(
      Archive archive, String archivePath, File file) async {
    final bytes = await file.readAsBytes();
    archive.addFile(ArchiveFile(archivePath, bytes.length, bytes));
  }

  /// Export all SharedPreferences key-value pairs as a JSON string.
  /// Uses try-each-type approach since SharedPreferences has no generic getter.
  static Future<String> _exportPreferencesJson() async {
    final prefs = await SharedPreferences.getInstance();
    final keys = prefs.getKeys();
    final data = <String, dynamic>{};

    for (final key in keys) {
      try {
        final stringVal = prefs.getString(key);
        if (stringVal != null) {
          data[key] = {'t': 's', 'v': stringVal};
          continue;
        }
      } catch (_) {
        _log.warning('[Backup] getString failed for key: $key');
      }
      try {
        final intVal = prefs.getInt(key);
        if (intVal != null) {
          data[key] = {'t': 'i', 'v': intVal};
          continue;
        }
      } catch (_) {
        _log.warning('[Backup] getInt failed for key: $key');
      }
      try {
        final boolVal = prefs.getBool(key);
        if (boolVal != null) {
          data[key] = {'t': 'b', 'v': boolVal};
          continue;
        }
      } catch (_) {
        _log.warning('[Backup] getBool failed for key: $key');
      }
      try {
        final doubleVal = prefs.getDouble(key);
        if (doubleVal != null) {
          data[key] = {'t': 'd', 'v': doubleVal};
          continue;
        }
      } catch (_) {
        _log.warning('[Backup] getDouble failed for key: $key');
      }
      try {
        final listVal = prefs.getStringList(key);
        if (listVal != null) {
          data[key] = {'t': 'l', 'v': listVal};
          continue;
        }
      } catch (_) {
        _log.warning('[Backup] getStringList failed for key: $key');
      }
    }

    return const JsonEncoder.withIndent('  ').convert(data);
  }

  /// Import SharedPreferences key-value pairs from a JSON string.
  static Future<void> _importPreferencesJson(String jsonStr) async {
    final prefs = await SharedPreferences.getInstance();
    final data =
        jsonDecode(jsonStr) as Map<String, dynamic>;

    await prefs.clear();

    for (final entry in data.entries) {
      final key = entry.key;
      final typedValue = entry.value as Map<String, dynamic>;
      final type = typedValue['t'] as String;
      final value = typedValue['v'];

      try {
        switch (type) {
          case 's':
            await prefs.setString(key, value as String);
          case 'i':
            await prefs.setInt(key, (value as num).toInt());
          case 'b':
            await prefs.setBool(key, value as bool);
          case 'd':
            await prefs.setDouble(key, (value as num).toDouble());
          case 'l':
            await prefs.setStringList(
                key, (value as List).cast<String>());
        }
      } catch (e) {
        _log.warning('[Backup] Failed to restore preference "$key": $e');
      }
    }
  }

  /// Close all database connections and Hive boxes so file I/O is safe.
  static Future<void> _closeAll() async {
    await AccountDatabase.instance.close();
    await HistoryDatabase.instance.close();
    await SubtitleDatabase.instance.close();

    await StorageService.closeBoxes();
  }

  /// Reopen all database connections and Hive boxes.
  static Future<void> _reopenAll() async {
    await StorageService.init();

    await AccountDatabase.instance.database;
    await HistoryDatabase.instance.database;
    await SubtitleDatabase.instance.database;
  }

  static Future<Map<String, String>> _getPackageInfo() async {
    return {
      'app_name': 'KikoFlu Edge',
      'version': '3.2.0',
    };
  }
}