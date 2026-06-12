import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// 字幕文件数据库记录
///
/// 数据库只存储相对路径（相对于字幕库根目录），绝对路径在运行时动态拼接。
/// 这样即使 iOS 重装后沙盒 UUID 变化，或其他平台迁移下载目录，数据库无需更新。
class SubtitleFileRecord {
  final String fileName;
  final String relativePath;
  final String category;
  final int? workId;
  final int fileSize;
  final String? modifiedAt;
  final String? normalizedName;

  SubtitleFileRecord({
    required this.fileName,
    required this.relativePath,
    required this.category,
    this.workId,
    this.fileSize = 0,
    this.modifiedAt,
    this.normalizedName,
  });

  /// 根据字幕库根目录拼接出绝对路径
  String absolutePath(String libraryRootPath) {
    return p.joinAll([libraryRootPath, ...relativePath.split('/')]);
  }

  Map<String, dynamic> toMap() => {
        'file_name': fileName,
        'relative_path': relativePath,
        'category': category,
        'work_id': workId,
        'file_size': fileSize,
        'modified_at': modifiedAt,
        'normalized_name': normalizedName,
      };

  factory SubtitleFileRecord.fromMap(Map<String, dynamic> map) {
    return SubtitleFileRecord(
      fileName: map['file_name'] as String,
      relativePath: map['relative_path'] as String,
      category: map['category'] as String,
      workId: map['work_id'] as int?,
      fileSize: (map['file_size'] as int?) ?? 0,
      modifiedAt: map['modified_at'] as String?,
      normalizedName: map['normalized_name'] as String?,
    );
  }
}

/// 字幕库数据库
class SubtitleDatabase {
  static final SubtitleDatabase instance = SubtitleDatabase._init();
  static Database? _database;

  SubtitleDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('subtitle_library.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      dbPath = p.join(appDocDir.path, 'KikoFlu');
      await Directory(dbPath).create(recursive: true);
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = p.join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 2,
      onCreate: _createDB,
      onUpgrade: _upgradeDB,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE subtitle_files (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        file_name TEXT NOT NULL,
        relative_path TEXT NOT NULL UNIQUE,
        category TEXT NOT NULL,
        work_id INTEGER,
        file_size INTEGER DEFAULT 0,
        modified_at TEXT,
        normalized_name TEXT,
        created_at TEXT DEFAULT (datetime('now'))
      )
    ''');

    await db.execute(
        'CREATE INDEX idx_files_work_id ON subtitle_files(work_id)');
    await db.execute(
        'CREATE INDEX idx_files_category ON subtitle_files(category)');

    await db.execute('''
      CREATE TABLE library_meta (
        key TEXT PRIMARY KEY,
        value TEXT
      )
    ''');
  }

  Future<void> _upgradeDB(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      // v2: 移除 file_path 列，改用 relative_path 作为唯一键
      // SQLite 不支持直接 DROP COLUMN，需要重建表
      await db.execute(
          'ALTER TABLE subtitle_files RENAME TO subtitle_files_old');
      await db.execute('''
        CREATE TABLE subtitle_files (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          file_name TEXT NOT NULL,
          relative_path TEXT NOT NULL UNIQUE,
          category TEXT NOT NULL,
          work_id INTEGER,
          file_size INTEGER DEFAULT 0,
          modified_at TEXT,
          normalized_name TEXT,
          created_at TEXT DEFAULT (datetime('now'))
        )
      ''');
      await db.execute('''
        INSERT OR REPLACE INTO subtitle_files
          (file_name, relative_path, category, work_id, file_size,
           modified_at, normalized_name, created_at)
        SELECT file_name, relative_path, category, work_id, file_size,
               modified_at, normalized_name, created_at
        FROM subtitle_files_old
      ''');
      await db.execute('DROP TABLE subtitle_files_old');
      await db.execute(
          'CREATE INDEX idx_files_work_id ON subtitle_files(work_id)');
      await db.execute(
          'CREATE INDEX idx_files_category ON subtitle_files(category)');
    }
  }

  // ==================== CRUD ====================

  /// 插入单条记录
  Future<void> insertFile(SubtitleFileRecord record) async {
    final db = await database;
    await db.insert('subtitle_files', record.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  /// 批量插入（事务）
  Future<void> insertFiles(List<SubtitleFileRecord> records) async {
    if (records.isEmpty) return;
    final db = await database;
    final batch = db.batch();
    for (final record in records) {
      batch.insert('subtitle_files', record.toMap(),
          conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
  }

  /// 按相对路径删除
  Future<int> deleteByRelativePath(String relativePath) async {
    final db = await database;
    return await db.delete('subtitle_files',
        where: 'relative_path = ?', whereArgs: [relativePath]);
  }

  /// 按相对路径前缀删除（用于删除目录下所有文件）
  Future<int> deleteByRelativePathPrefix(String relativePrefix) async {
    final db = await database;
    // 确保路径以 / 结尾，避免误删同前缀的其他目录
    final prefix =
        relativePrefix.endsWith('/') ? relativePrefix : '$relativePrefix/';
    return await db.delete('subtitle_files',
        where: 'relative_path LIKE ?', whereArgs: ['$prefix%']);
  }

  /// 更新单个文件的路径（重命名）
  Future<void> updateRelativePath(
    String oldRelativePath,
    String newRelativePath,
    String newFileName,
  ) async {
    final db = await database;
    final newCategory = _extractCategoryFromRelativePath(newRelativePath);
    final newWorkId = _extractWorkIdFromRelativePath(newRelativePath);
    await db.update(
      'subtitle_files',
      {
        'relative_path': newRelativePath,
        'file_name': newFileName,
        'category': newCategory,
        'work_id': newWorkId,
      },
      where: 'relative_path = ?',
      whereArgs: [oldRelativePath],
    );
  }

  /// 批量更新目录路径（目录重命名/移动）
  Future<void> updateDirectoryRelativePaths(
    String oldRelativePrefix,
    String newRelativePrefix,
  ) async {
    final db = await database;
    final oldPrefix =
        oldRelativePrefix.endsWith('/') ? oldRelativePrefix : '$oldRelativePrefix/';
    final files = await db.query('subtitle_files',
        where: 'relative_path LIKE ?', whereArgs: ['$oldPrefix%']);

    if (files.isEmpty) return;

    final batch = db.batch();
    for (final file in files) {
      final oldRelativePath = file['relative_path'] as String;
      final newRelativePath =
          oldRelativePath.replaceFirst(oldRelativePrefix, newRelativePrefix);
      final parts = newRelativePath.split('/');
      final newCategory = parts.isNotEmpty ? parts.first : '';
      final newWorkId = _extractWorkIdFromRelativePath(newRelativePath);

      batch.update(
        'subtitle_files',
        {
          'relative_path': newRelativePath,
          'category': newCategory,
          'work_id': newWorkId,
        },
        where: 'id = ?',
        whereArgs: [file['id']],
      );
    }
    await batch.commit(noResult: true);
  }

  // ==================== 查询 ====================

  /// 获取所有文件记录
  Future<List<Map<String, dynamic>>> getAllFiles() async {
    final db = await database;
    return await db.query('subtitle_files', orderBy: 'relative_path');
  }

  /// 按 workId 查询
  Future<List<SubtitleFileRecord>> getFilesByWorkId(int workId) async {
    final db = await database;
    final results = await db.query('subtitle_files',
        where: 'work_id = ?', whereArgs: [workId]);
    return results.map((m) => SubtitleFileRecord.fromMap(m)).toList();
  }

  /// 按分类查询
  Future<List<SubtitleFileRecord>> getFilesByCategory(
      String category) async {
    final db = await database;
    final results = await db.query('subtitle_files',
        where: 'category = ?', whereArgs: [category]);
    return results.map((m) => SubtitleFileRecord.fromMap(m)).toList();
  }

  /// 获取所有不重复的 workId
  Future<Set<int>> getDistinctWorkIds() async {
    final db = await database;
    final results = await db.rawQuery(
        'SELECT DISTINCT work_id FROM subtitle_files WHERE work_id IS NOT NULL');
    return results
        .map((r) => r['work_id'] as int)
        .toSet();
  }

  /// 获取已解析目录下的文件夹名列表
  Future<List<String>> getParsedFolderNames(String parsedCategory) async {
    final db = await database;
    final results = await db.rawQuery('''
      SELECT DISTINCT 
        CASE 
          WHEN INSTR(SUBSTR(relative_path, LENGTH(?) + 2), '/') > 0
          THEN SUBSTR(SUBSTR(relative_path, LENGTH(?) + 2), 1, 
               INSTR(SUBSTR(relative_path, LENGTH(?) + 2), '/') - 1)
          ELSE SUBSTR(relative_path, LENGTH(?) + 2)
        END as folder_name
      FROM subtitle_files 
      WHERE category = ?
    ''', [parsedCategory, parsedCategory, parsedCategory, parsedCategory, parsedCategory]);
    return results
        .map((r) => r['folder_name'] as String)
        .where((name) => name.isNotEmpty && name.contains('.') == false)
        .toList();
  }

  /// 获取统计信息（文件数 + 总大小）
  Future<Map<String, int>> getStatsRaw() async {
    final db = await database;
    final result = await db.rawQuery(
        'SELECT COUNT(*) as total_files, COALESCE(SUM(file_size), 0) as total_size FROM subtitle_files');
    return {
      'totalFiles': (result.first['total_files'] as int?) ?? 0,
      'totalSize': (result.first['total_size'] as int?) ?? 0,
    };
  }

  /// 获取文件记录数量
  Future<int> getFileCount() async {
    final db = await database;
    return Sqflite.firstIntValue(
            await db.rawQuery('SELECT COUNT(*) FROM subtitle_files')) ??
        0;
  }

  /// 获取不重复的文件夹数量（从 relative_path 推算）
  Future<int> getFolderCount() async {
    final db = await database;
    // 提取 relative_path 中所有目录层级，去重计数
    // 例如 "已解析/RJ123/sub/a.vtt" → "已解析", "已解析/RJ123", "已解析/RJ123/sub"
    final results = await db.query('subtitle_files', columns: ['relative_path']);
    final folderPaths = <String>{};
    for (final row in results) {
      final relativePath = row['relative_path'] as String;
      final parts = relativePath.split('/');
      for (int i = 1; i < parts.length; i++) {
        folderPaths.add(parts.sublist(0, i).join('/'));
      }
    }
    return folderPaths.length;
  }

  // ==================== 元数据 ====================

  Future<String?> getMeta(String key) async {
    final db = await database;
    final results = await db.query('library_meta',
        where: 'key = ?', whereArgs: [key], limit: 1);
    if (results.isEmpty) return null;
    return results.first['value'] as String?;
  }

  Future<void> setMeta(String key, String value) async {
    final db = await database;
    await db.insert('library_meta', {'key': key, 'value': value},
        conflictAlgorithm: ConflictAlgorithm.replace);
  }

  // ==================== 维护 ====================

  /// 清空所有记录
  Future<void> clear() async {
    final db = await database;
    await db.delete('subtitle_files');
  }

  /// Close the database connection. After closing, the database will
  /// be re-opened lazily on the next access.
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  // ==================== 工具方法 ====================

  static final _workIdRegex = RegExp(r'[RrBbVv][Jj]0*(\d+)');

  /// 从相对路径提取分类（第一级目录）
  static String _extractCategoryFromRelativePath(String relativePath) {
    final firstSlash = relativePath.indexOf('/');
    if (firstSlash > 0) {
      return relativePath.substring(0, firstSlash);
    }
    return '';
  }

  /// 从相对路径提取 workId
  static int? _extractWorkIdFromRelativePath(String relativePath) {
    // 相对路径格式: "已解析/RJ1003058/track.vtt"
    final parts = relativePath.split('/');
    if (parts.length < 2) return null;
    // 检查第二级目录名
    final match = _workIdRegex.firstMatch(parts[1]);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }
}
