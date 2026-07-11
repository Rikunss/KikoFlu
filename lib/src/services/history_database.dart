import 'dart:io';
import 'package:sqflite/sqflite.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import '../models/history_record.dart';
import 'log_service.dart';

final _log = LogService.instance;

class HistoryDatabase {
  static final HistoryDatabase instance = HistoryDatabase._init();
  static Database? _database;

  HistoryDatabase._init();

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDB('history.db');
    return _database!;
  }

  Future<Database> _initDB(String filePath) async {
    final String dbPath;
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      final appDocDir = await getApplicationDocumentsDirectory();
      dbPath = join(appDocDir.path, 'KikoFlu');
      await Directory(dbPath).create(recursive: true);
    } else {
      dbPath = await getDatabasesPath();
    }
    final path = join(dbPath, filePath);

    return await openDatabase(
      path,
      version: 3,
      onCreate: _createDB,
      onUpgrade: _onUpgrade,
    );
  }

  Future<void> _createDB(Database db, int version) async {
    await db.execute('''
      CREATE TABLE history (
        work_id INTEGER PRIMARY KEY,
        work_json TEXT NOT NULL,
        last_played_time INTEGER NOT NULL,
        last_track_json TEXT,
        last_position_ms INTEGER DEFAULT 0,
        playlist_index INTEGER DEFAULT 0,
        playlist_total INTEGER DEFAULT 0,
        total_listened_ms INTEGER DEFAULT 0
      )
    ''');
  }

  Future<void> _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      try {
        await db.execute(
            'ALTER TABLE history ADD COLUMN playlist_index INTEGER DEFAULT 0');
        await db.execute(
            'ALTER TABLE history ADD COLUMN playlist_total INTEGER DEFAULT 0');
      } catch (e) {
        _log.warning('Migration v2 error (ignored): $e');
      }
    }
    if (oldVersion < 3) {
      try {
        await db.execute(
            'ALTER TABLE history ADD COLUMN total_listened_ms INTEGER DEFAULT 0');
      } catch (e) {
        _log.warning('Migration v3 error (ignored): $e');
      }
    }
  }

  Future<void> addOrUpdate(HistoryRecord record) async {
    final db = await instance.database;
    await db.insert(
      'history',
      record.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<List<HistoryRecord>> getAllHistory({
    int? limit,
    int? offset,
  }) async {
    final db = await instance.database;
    final result = await db.query(
      'history',
      orderBy: 'last_played_time DESC',
      limit: limit,
      offset: offset,
    );
    return result.map((json) => HistoryRecord.fromMap(json)).toList();
  }

  Future<HistoryRecord?> getHistoryByWorkId(int workId) async {
    final db = await instance.database;
    final result = await db.query(
      'history',
      where: 'work_id = ?',
      whereArgs: [workId],
      limit: 1,
    );
    if (result.isEmpty) return null;
    return HistoryRecord.fromMap(result.first);
  }
  
  Future<int> getHistoryCount() async {
    final db = await instance.database;
    final result = await db.rawQuery('SELECT COUNT(*) as count FROM history');
    return Sqflite.firstIntValue(result) ?? 0;
  }

  Future<void> delete(int workId) async {
    final db = await instance.database;
    await db.delete(
      'history',
      where: 'work_id = ?',
      whereArgs: [workId],
    );
  }

  /// Close the database connection. After closing, the database will
  /// be re-opened lazily on the next access.
  Future<void> close() async {
    await _database?.close();
    _database = null;
  }

  Future<void> clear() async {
    final db = await instance.database;
    await db.delete('history');
  }
}