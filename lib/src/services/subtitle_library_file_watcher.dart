import 'dart:async';
import 'dart:io';

import 'log_service.dart';
import 'subtitle_library_service.dart';
import '../utils/file_icon_utils.dart';

final _log = LogService.instance;

/// Watches the subtitle library directory for file system changes (create,
/// modify, delete) and automatically refreshes the database index via
/// [SubtitleLibraryService.clearCache].
///
/// Uses [Directory.watch()] which is cross-platform (Windows, macOS, Linux,
/// Android). Events are debounced with a 2-second delay to avoid excessive
/// rebuilds when copying/moving many files at once (e.g. importing a ZIP).
///
/// Usage:
/// ```dart
/// SubtitleLibraryFileWatcher.instance.start();
/// // ... later ...
/// SubtitleLibraryFileWatcher.instance.stop();
/// ```
class SubtitleLibraryFileWatcher {
  SubtitleLibraryFileWatcher._();
  static final SubtitleLibraryFileWatcher instance =
      SubtitleLibraryFileWatcher._();

  StreamSubscription<FileSystemEvent>? _sub;
  Timer? _debounceTimer;
  Timer? _periodicScanTimer;
  bool _watching = false;
  bool _resourceLimitReached = false;
  bool _periodicScanActive = false;

  /// Whether the watcher was stopped due to a file system resource limit
  /// (e.g., `inotify.max_user_watches` on Android/Linux).
  /// When `true`, the watcher will NOT auto-restart — use [restart()] manually
  /// or switch to a periodic scan approach for large subtitle libraries.
  bool get stoppedDueToResourceLimit => _resourceLimitReached;

  /// Whether the watcher has fallen back to periodic polling (30s interval)
  /// because the native recursive watch hit a resource limit.
  /// This only happens on Android where [Directory.watch(recursive: true)]
  /// registers one `inotify` watch per subdirectory.
  bool get isPeriodicScanActive => _periodicScanActive;

  /// Start watching the subtitle library directory.
  /// Safe to call multiple times — subsequent calls are no-ops.
  void start() {
    if (_watching) return;
    _watching = true;
    _setupWatch();
  }

  /// Stop watching and clean up all resources.
  void stop() {
    _watching = false;
    _stopPeriodicScan();
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _sub?.cancel();
    _sub = null;
    _log.info('[SubtitleWatcher] Stopped', tag: 'SubtitleWatcher');
  }

  /// Restart the watcher (stop + start).
  void restart() {
    stop();
    start();
  }

  // ==================================================================
  // Internal
  // ==================================================================

  Future<void> _setupWatch() async {
    try {
      if (!_watching) return;

      final dir = await SubtitleLibraryService.getSubtitleLibraryDirectory();
      if (!await dir.exists()) {
        // Directory doesn't exist yet — retry after a short delay
        _log.info(
          '[SubtitleWatcher] Directory not ready, retrying in 5s',
          tag: 'SubtitleWatcher',
        );
        Future.delayed(const Duration(seconds: 5), _setupWatch);
        return;
      }

      _log.info(
        '[SubtitleWatcher] Watching: ${dir.path}',
        tag: 'SubtitleWatcher',
      );

      _sub = dir.watch(recursive: true).listen(
        _onFileEvent,
        onError: (Object error, StackTrace stack) {
          if (_isResourceLimitError(error)) {
            _handleResourceLimit();
          } else {
            _log.warning(
              '[SubtitleWatcher] Stream error: $error',
              tag: 'SubtitleWatcher',
            );
            _scheduleRestart();
          }
        },
        onDone: () {
          _log.info(
            '[SubtitleWatcher] Stream done — restarting',
            tag: 'SubtitleWatcher',
          );
          _scheduleRestart();
        },
      );
    } catch (e) {
      if (_isResourceLimitError(e)) {
        _handleResourceLimit();
      } else {
        _log.warning(
          '[SubtitleWatcher] Setup failed: $e — retrying in 10s',
          tag: 'SubtitleWatcher',
        );
        _scheduleRestart(delay: const Duration(seconds: 10));
      }
    }
  }

  /// Check if an error from [Directory.watch] indicates a file system
  /// resource limit has been reached (e.g., `inotify.max_user_watches`).
  ///
  /// Common error patterns:
  /// - "inotify" — Linux inotify API
  /// - "max_user_watches" — the kernel-imposed watch count limit
  /// - "Too many open files" / "EMFILE" — file descriptor exhaustion
  /// - "ENOSPC" — inotify watch queue full
  static bool _isResourceLimitError(Object error) {
    final msg = error.toString().toLowerCase();
    return msg.contains('inotify') ||
        msg.contains('max_user_watches') ||
        msg.contains('too many open files') ||
        msg.contains('emfile') ||
        msg.contains('enospc') ||
        msg.contains('no space left');
  }

  /// Called when a resource limit error is detected.
  /// Stops the watcher gracefully and logs a detailed warning with
  /// actionable advice for the user.
  void _handleResourceLimit() {
    _resourceLimitReached = true;

    // On Android, fall back to periodic scan instead of going dark.
    // Directoy.watch(recursive: true) on Android uses inotify which
    // registers one watch per subdirectory — large libraries hit the
    // kernel's fs.inotify.max_user_watches limit (~8K by default).
    if (Platform.isAndroid) {
      _log.warning(
        '[SubtitleWatcher] inotify limit reached — falling back to periodic scan (30s). '
        'Subtitle changes may take up to 30 seconds to appear.',
        tag: 'SubtitleWatcher',
      );
      _sub?.cancel();
      _sub = null;
      _watching = false;
      _startPeriodicScan();
    } else {
      _log.warning(
        '[SubtitleWatcher] File system resource limit reached — stopping watcher. '
        'Your subtitle library has too many folders for recursive watching.',
        tag: 'SubtitleWatcher',
      );
      stop();
    }
  }

  /// Fallback: poll the subtitle library directory every 30 seconds and
  /// rebuild the index. Used on Android when the native recursive watch
  /// fails due to inotify resource limits.
  void _startPeriodicScan() {
    _stopPeriodicScan();
    _periodicScanActive = true;
    _log.info(
      '[SubtitleWatcher] Periodic scan started (30s interval)',
      tag: 'SubtitleWatcher',
    );

    // Run an initial scan immediately
    _runPeriodicScan();

    _periodicScanTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) => _runPeriodicScan(),
    );
  }

  void _stopPeriodicScan() {
    _periodicScanActive = false;
    _periodicScanTimer?.cancel();
    _periodicScanTimer = null;
  }

  Future<void> _runPeriodicScan() async {
    if (!_periodicScanActive) return;
    try {
      _log.info(
        '[SubtitleWatcher] Periodic scan — refreshing index',
        tag: 'SubtitleWatcher',
      );
      await SubtitleLibraryService.clearCache();
    } catch (e) {
      _log.warning(
        '[SubtitleWatcher] Periodic scan failed: $e',
        tag: 'SubtitleWatcher',
      );
    }
  }

  void _scheduleRestart({Duration delay = const Duration(seconds: 5)}) {
    _sub?.cancel();
    _sub = null;
    if (_watching && !_resourceLimitReached) {
      Future.delayed(delay, _setupWatch);
    }
  }

  void _onFileEvent(FileSystemEvent event) {
    // Skip move events — they're redundant with create+delete pairs
    if (event.type == FileSystemEvent.move) return;

    final path = event.path;
    final fileName = path.split(Platform.pathSeparator).last;

    // Skip hidden files, temp download files, and non-subtitle files
    if (fileName.startsWith('.') || fileName.endsWith('.downloading')) return;
    if (!FileIconUtils.isLyricFile(fileName)) return;

    // Debounce: reset timer on each event, wait 2s of silence before
    // triggering a refresh. This avoids excessive rebuilds during bulk
    // import operations (ZIP extraction, folder copy, etc.).
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(seconds: 2), () {
      if (!_watching) return;
      _log.info(
        '[SubtitleWatcher] Changes detected — refreshing index',
        tag: 'SubtitleWatcher',
      );
      unawaited(SubtitleLibraryService.clearCache().catchError((e) {
        _log.warning(
          '[SubtitleWatcher] Refresh failed: $e',
          tag: 'SubtitleWatcher',
        );
      }));
    });
  }
}
