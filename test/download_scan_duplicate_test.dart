import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:kikoeru_flutter/src/models/download_task.dart';
import 'package:kikoeru_flutter/src/services/download_path_service.dart';
import 'package:kikoeru_flutter/src/services/download_service.dart';
import 'package:kikoeru_flutter/src/services/download_task_persistence.dart';
import 'package:kikoeru_flutter/src/services/storage_service.dart';

const int _workId = 12345;

/// Writes a work folder + matching completed tasks to a fake download dir.
Future<void> _seed(
  Directory downloadDir, {
  required List<String> fileNames,
  int bytesPerFile = 100,
}) async {
  // keep the parameter meaningful for the size assertions below
  final unit = 'x' * bytesPerFile;
  final workDir = Directory('${downloadDir.path}/$_workId');
  await workDir.create(recursive: true);
  for (final name in fileNames) {
    final file = File('${workDir.path}/$name');
    await file.parent.create(recursive: true);
    await file.writeAsString(unit);
  }
  await File('${workDir.path}/work_metadata.json').writeAsString(jsonEncode({
    'id': _workId,
    'title': 'RJ012345 asmr',
    'children': <dynamic>[],
  }));

  final tasks = <DownloadTask>[];
  for (var i = 0; i < fileNames.length; i++) {
    tasks.add(DownloadTask(
      id: 'hash_$i',
      workId: _workId,
      workTitle: 'RJ012345 asmr',
      fileName: fileNames[i],
      downloadUrl: '',
      hash: 'hash_$i',
      totalBytes: bytesPerFile,
      downloadedBytes: bytesPerFile,
      status: DownloadStatus.completed,
      createdAt: DateTime(2026, 1, 1),
      completedAt: DateTime(2026, 1, 1),
    ));
  }
  final prefs = await StorageService.getPrefs();
  await prefs.setString(
      'download_tasks', jsonEncode(tasks.map((t) => t.toJson()).toList()));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late Directory downloadDir;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('kikoflu_dup');
    downloadDir = Directory('${tmp.path}/custom_dl')..createSync(recursive: true);

    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => tmp.path,
    );

    Hive.init(tmp.path);
    SharedPreferences.setMockInitialValues({});
    await StorageService.init();

    // Reset the singleton's in-memory task list.
    DownloadService.instance.persistence.removeWhere((_) => true);
    await DownloadService.instance.persistence.flush();

    await (await StorageService.getPrefs())
        .setString('custom_download_path', downloadDir.path);
  });

  tearDown(() async {
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  test('startup order: loadTasks() then disk sync keeps one task per file',
      () async {
    await _seed(downloadDir, fileNames: ['a1.mp3', 'a2.mp3', 'a3.mp3']);

    await DownloadService.instance.initialize(); // loadTasks()
    expect(DownloadService.instance.tasks.length, 3);

    await DownloadService.instance.reloadMetadataFromDisk();

    expect(DownloadService.instance.tasks.map((t) => t.fileName).toList(),
        ['a1.mp3', 'a2.mp3', 'a3.mp3']);
  });

  test('startup race: disk sync started before loadTasks() finishes', () async {
    // A slow scan (many files) makes the race resolve the way it does in the
    // app: the saved tasks finish loading before the scan result is applied.
    await _seed(downloadDir,
        fileNames: [for (var i = 0; i < 400; i++) 'track_$i.mp3']);

    // Mirrors main.dart: MainScreen's post-frame callback runs the disk sync
    // while AppBootstrap.initialize() is still loading the saved tasks.
    final sync = DownloadService.instance.reloadMetadataFromDisk();
    await DownloadService.instance.initialize(); // races the scan
    await sync;

    expect(DownloadService.instance.tasks.length, 400);
  });

  test('startup race: slow scan finishing after loadTasks() duplicates tasks',
      () async {
    // A large work folder makes the background scan slower than the splash
    // screen's loadTasks(), which is what happens on slow (external) storage.
    await _seed(downloadDir,
        fileNames: [for (var i = 0; i < 3000; i++) 'track_$i.mp3']);

    final sync = DownloadService.instance.syncWithDiskAfterInit();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await DownloadService.instance.initialize();
    await sync;

    expect(DownloadService.instance.tasks.length, 3000);
  }, timeout: const Timeout(Duration(minutes: 2)));

  test('migration to a custom path does not duplicate tasks', () async {
    // Start on the default path (mocked documents dir + /downloads).
    await (await StorageService.getPrefs()).remove('custom_download_path');
    final defaultDir = Directory('${tmp.path}/downloads');
    await _seed(defaultDir,
        fileNames: ['a1.mp3', 'sub/a2.mp3', 'sub/deep/a3.mp3']);

    await DownloadService.instance.initialize();
    expect(DownloadService.instance.tasks.length, 3);

    final newDir = '${tmp.path}/Music/asmr';
    final result = await DownloadPathService.setCustomPath(newDir);
    expect(result.success, isTrue);

    await DownloadService.instance.reloadMetadataFromDisk();

    expect(DownloadService.instance.tasks.map((t) => t.fileName).toList(),
        ['a1.mp3', 'sub/a2.mp3', 'sub/deep/a3.mp3']);
  });

  test('reopening the app after a path migration does not duplicate tasks',
      () async {
    await (await StorageService.getPrefs()).remove('custom_download_path');
    final defaultDir = Directory('${tmp.path}/downloads');
    await _seed(defaultDir,
        fileNames: ['a1.mp3', 'sub/a2.mp3', 'sub/deep/a3.mp3']);

    await DownloadService.instance.initialize();
    final newDir = '${tmp.path}/Music/asmr';
    expect((await DownloadPathService.setCustomPath(newDir)).success, isTrue);
    await DownloadService.instance.reloadMetadataFromDisk();
    expect(DownloadService.instance.tasks.length, 3);

    // Simulate the next app start: fresh persistence, tasks loaded from prefs.
    final reopened = DownloadTaskPersistence();
    await reopened.loadTasks();
    expect(reopened.tasks.length, 3);

    await reopened.reloadMetadataFromDisk();

    expect(reopened.tasks.map((t) => t.fileName).toList(),
        ['a1.mp3', 'sub/a2.mp3', 'sub/deep/a3.mp3']);
  });

  test('an already doubled list is healed back to one entry per file',
      () async {
    // What the app saved before the fix: the original download plus the extra
    // "completed" record the disk sync invented for the same file.
    const fileNames = [
      'a1.mp3', 'a2.mp3', 'a3.mp3', 'a4.mp3', 'a5.mp3', 'a6.mp3', 'a7.mp3',
    ];
    await _seed(downloadDir, fileNames: fileNames, bytesPerFile: 100);

    final prefs = await StorageService.getPrefs();
    final saved = jsonDecode(prefs.getString('download_tasks')!) as List<dynamic>;
    for (var i = 0; i < fileNames.length; i++) {
      saved.add({
        ...(saved[i] as Map<String, dynamic>),
        'id': '${_workId}_${fileNames[i]}_9$i',
        'hash': null,
        'downloadUrl': '',
      });
    }
    await prefs.setString('download_tasks', jsonEncode(saved));

    await DownloadService.instance.initialize();
    expect(DownloadService.instance.tasks.length, 7);

    await DownloadService.instance.reloadMetadataFromDisk();

    final tasks = DownloadService.instance.tasks;
    expect(tasks.length, 7);
    expect(
      tasks.fold<int>(0, (sum, t) => sum + (t.totalBytes ?? 0)),
      700,
    );
  });

  test('scan does not duplicate when a task file name only differs in case',
      () async {
    await _seed(downloadDir, fileNames: ['Track One.mp3']);

    final tasks = DownloadService.instance.persistence;
    tasks.addAll([
      DownloadTask(
        id: 'hash_0',
        workId: _workId,
        workTitle: 'RJ012345 asmr',
        fileName: 'track one.MP3',
        downloadUrl: '',
        hash: 'hash_0',
        totalBytes: 100,
        downloadedBytes: 100,
        status: DownloadStatus.completed,
        createdAt: DateTime(2026, 1, 1),
        completedAt: DateTime(2026, 1, 1),
      ),
    ]);
    await tasks.flush();

    await DownloadService.instance.reloadMetadataFromDisk();

    expect(DownloadService.instance.tasks.length, 1);
  });
}
