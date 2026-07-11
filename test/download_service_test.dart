import 'package:flutter_test/flutter_test.dart';
import 'package:kikoeru_flutter/src/services/download_service.dart';
import 'package:kikoeru_flutter/src/models/download_task.dart';

void main() {
  group('Natural Sort', () {
    test('sorts single-digit numbers before double-digit', () {
      final items = ['10.mp3', '2.mp3', '1.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['1.mp3', '2.mp3', '10.mp3']);
    });

    test('sorts mixed text and numbers', () {
      final items = ['track_10.mp3', 'track_2.mp3', 'track_1.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['track_1.mp3', 'track_2.mp3', 'track_10.mp3']);
    });

    test('sorts folder names naturally', () {
      final items = ['Folder 10', 'Folder 2', 'Folder 1'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['Folder 1', 'Folder 2', 'Folder 10']);
    });

    test('handles identical strings', () {
      final items = ['same.mp3', 'same.mp3', 'same.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['same.mp3', 'same.mp3', 'same.mp3']);
    });

    test('case insensitive comparison', () {
      final items = ['Z.mp3', 'a.mp3', 'M.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['a.mp3', 'M.mp3', 'Z.mp3']);
    });

    test('handles multiple numeric groups', () {
      final items = ['v2.10.mp3', 'v2.2.mp3', 'v1.5.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['v1.5.mp3', 'v2.2.mp3', 'v2.10.mp3']);
    });

    test('handles files with no numbers', () {
      final items = ['zeta.mp3', 'alpha.mp3', 'beta.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['alpha.mp3', 'beta.mp3', 'zeta.mp3']);
    });

    test('handles empty string', () {
      final items = ['b.mp3', '', 'a.mp3'];
      items.sort(DownloadService.naturalCompare);
      expect(items[0], '');
    });

    test('handles numeric-only filenames', () {
      final items = ['10', '2', '1', '20'];
      items.sort(DownloadService.naturalCompare);
      expect(items, ['1', '2', '10', '20']);
    });
  });

  group('DownloadTask Model', () {
    test('creates default task with pending status', () {
      final task = DownloadTask(
        id: 'task-1',
        workId: 12345,
        workTitle: 'Test Work',
        fileName: 'track.mp3',
        downloadUrl: 'https://example.com/track.mp3',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(task.id, 'task-1');
      expect(task.workId, 12345);
      expect(task.workTitle, 'Test Work');
      expect(task.fileName, 'track.mp3');
      expect(task.status, DownloadStatus.pending);
      expect(task.downloadedBytes, 0);
      expect(task.completedAt, isNull);
      expect(task.error, isNull);
    });

    test('JSON serialization roundtrip', () {
      final original = DownloadTask(
        id: 'hash-abc-123',
        workId: 67890,
        workTitle: 'RJ123456 Test Work',
        fileName: 'subtitles/track_01.flac',
        downloadUrl: '',
        hash: 'hash-abc-123',
        totalBytes: 50000000,
        downloadedBytes: 50000000,
        status: DownloadStatus.completed,
        createdAt: DateTime(2024, 6, 1, 10, 30, 0),
        completedAt: DateTime(2024, 6, 1, 10, 35, 30),
        workMetadata: {'id': 67890, 'title': 'RJ123456 Test Work'},
      );

      final json = original.toJson();
      final restored = DownloadTask.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.workId, original.workId);
      expect(restored.workTitle, original.workTitle);
      expect(restored.fileName, original.fileName);
      expect(restored.hash, original.hash);
      expect(restored.totalBytes, original.totalBytes);
      expect(restored.downloadedBytes, original.downloadedBytes);
      expect(restored.status, original.status);
    });

    test('partial update via copyWith', () {
      final task = DownloadTask(
        id: 'task-2',
        workId: 111,
        workTitle: 'Work Title',
        fileName: 'test.mp3',
        downloadUrl: 'https://example.com/test.mp3',
        createdAt: DateTime(2024, 1, 1),
      );

      final updated = task.copyWith(
        status: DownloadStatus.downloading,
        downloadedBytes: 25000,
        totalBytes: 100000,
      );

      expect(updated.status, DownloadStatus.downloading);
      expect(updated.downloadedBytes, 25000);
      expect(updated.totalBytes, 100000);
      expect(updated.id, task.id);
      expect(updated.workId, task.workId);
      expect(updated.fileName, task.fileName);
    });

    test('completed task has completedAt set', () {
      final now = DateTime(2024, 7, 15, 12, 0, 0);
      final task = DownloadTask(
        id: 'task-3',
        workId: 222,
        workTitle: 'Completed Work',
        fileName: 'done.flac',
        downloadUrl: '',
        status: DownloadStatus.completed,
        completedAt: now,
        createdAt: DateTime(2024, 7, 15, 10, 0, 0),
      );

      expect(task.completedAt, now);
    });

    test('failed task has error message', () {
      final task = DownloadTask(
        id: 'task-4',
        workId: 333,
        workTitle: 'Failed Work',
        fileName: 'broken.flac',
        downloadUrl: 'https://example.com/broken.flac',
        status: DownloadStatus.failed,
        error: 'Connection timeout',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(task.error, 'Connection timeout');
    });

    test('converting task has eta field', () {
      final task = DownloadTask(
        id: 'task-5',
        workId: 444,
        workTitle: 'Converting Work',
        fileName: 'source.wav',
        downloadUrl: '',
        status: DownloadStatus.converting,
        eta: '30 seconds',
        createdAt: DateTime(2024, 1, 1),
      );

      expect(task.status, DownloadStatus.converting);
      expect(task.eta, '30 seconds');
    });

    test('paused task can be resumed', () {
      final task = DownloadTask(
        id: 'task-6',
        workId: 555,
        workTitle: 'Paused Work',
        fileName: 'paused.flac',
        downloadUrl: 'https://example.com/paused.flac',
        status: DownloadStatus.paused,
        downloadedBytes: 5000,
        totalBytes: 10000,
        createdAt: DateTime(2024, 1, 1),
      );

      expect(task.status, DownloadStatus.paused);
      expect(task.progress, 0.5);
    });

    test('progress returns 0 for unknown total', () {
      final task = DownloadTask(
        id: 'task-7',
        workId: 666,
        workTitle: 'No Total',
        fileName: 'unknown.flac',
        downloadUrl: '',
        status: DownloadStatus.downloading,
        downloadedBytes: 100,
        totalBytes: 0,
        createdAt: DateTime(2024, 1, 1),
      );

      expect(task.progress, 0.0);
    });
  });

  group('DownloadStatus', () {
    test('all status values are defined', () {
      expect(DownloadStatus.values, hasLength(6));
      expect(DownloadStatus.values, containsAll([
        DownloadStatus.pending,
        DownloadStatus.downloading,
        DownloadStatus.paused,
        DownloadStatus.converting,
        DownloadStatus.completed,
        DownloadStatus.failed,
      ]));
    });
  });
}