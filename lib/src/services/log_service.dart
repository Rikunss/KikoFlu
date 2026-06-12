import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

enum LogLevel { debug, info, warning, error }

/// Predefined log tag categories for filtering.
class LogTag {
  final String name;
  final String label;

  const LogTag(this.name, this.label);

  static const all = LogTag('', 'All');
  static const playback = LogTag('Playback', 'Playback');
  static const usbDac = LogTag('USB', 'USB DAC');
  static const database = LogTag('Database', 'Database');
  static const network = LogTag('Network', 'Network');
  static const ui = LogTag('UI', 'UI');
  static const download = LogTag('Download', 'Download');
  static const audio = LogTag('Audio', 'Audio');

  static const List<LogTag> predefined = [
    all,
    playback,
    usbDac,
    database,
    network,
    ui,
    download,
    audio,
  ];

  /// Check if a log entry's tag matches this category.
  bool matches(String? entryTag) {
    if (name.isEmpty) return true; // 'All' matches everything
    if (entryTag == null) return false;
    return entryTag.toUpperCase() == name.toUpperCase();
  }
}

class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String message;
  final String? tag;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.message,
    this.tag,
  });

  String get levelLabel {
    switch (level) {
      case LogLevel.debug:
        return 'D';
      case LogLevel.info:
        return 'I';
      case LogLevel.warning:
        return 'W';
      case LogLevel.error:
        return 'E';
    }
  }

  String format() {
    final time =
        '${timestamp.hour.toString().padLeft(2, '0')}:'
        '${timestamp.minute.toString().padLeft(2, '0')}:'
        '${timestamp.second.toString().padLeft(2, '0')}.'
        '${timestamp.millisecond.toString().padLeft(3, '0')}';
    final tagStr = tag != null ? '[$tag] ' : '';
    return '$time [$levelLabel] $tagStr$message';
  }
}

class LogService {
  static final LogService _instance = LogService._();
  static LogService get instance => _instance;

  LogService._();

  final List<LogEntry> _logs = [];
  static const int _maxLogs = 1000;
  static const int _maxMessageLength = 500;
  static const int _maxFileSize = 5 * 1024 * 1024; // 5MB
  final _controller = StreamController<LogEntry>.broadcast();

  Stream<LogEntry> get logStream => _controller.stream;
  List<LogEntry> get logs => List.unmodifiable(_logs);

  bool _initialized = false;
  File? _logFile;

  /// Initialize log system, start file logging.
  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    // Set up log file for persistent storage
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logDir = Directory(p.join(dir.path, 'logs'));
      if (!await logDir.exists()) {
        await logDir.create(recursive: true);
      }
      _logFile = File(p.join(logDir.path, 'app.log'));

      // Rotate if file is too large
      if (await _logFile!.exists()) {
        final length = await _logFile!.length();
        if (length > _maxFileSize) {
          final rotated = File(p.join(logDir.path, 'app_old.log'));
          await _logFile!.rename(rotated.path);
          _logFile = File(p.join(logDir.path, 'app.log'));
        }
      }
    } catch (e) {
      // Intentionally not using LogService here to avoid recursion;
      // any failures during log initialization are non-critical.
      debugPrint('[LogService] Init error: $e');
    }
  }

  void _addEntry(LogEntry entry) {
    // Truncate long messages
    final truncated = entry.message.length > _maxMessageLength
        ? LogEntry(
            timestamp: entry.timestamp,
            level: entry.level,
            message: '${entry.message.substring(0, _maxMessageLength)}... (truncated, original ${entry.message.length})',
            tag: entry.tag,
          )
        : entry;

    _logs.add(truncated);
    if (_logs.length > _maxLogs) {
      _logs.removeAt(0);
    }

    // Write to file
    _appendToFile(truncated);

    _controller.add(truncated);
  }

  Future<void> _appendToFile(LogEntry entry) async {
    try {
      final file = _logFile;
      if (file == null) return;
      // Rotate if file is too large (check before writing)
      if (await file.exists()) {
        final length = await file.length();
        if (length > _maxFileSize) {
          final dir = file.parent;
          final rotated = File(p.join(dir.path, 'app_old.log'));
          await file.rename(rotated.path);
          _logFile = File(p.join(dir.path, 'app.log'));
        }
      }
      await file.writeAsString('${entry.format()}\n', mode: FileMode.append);
    } catch (e) {
      // Avoid LogService recursion — use debugPrint for internal failures.
      debugPrint('[LogService] File write error: $e');
    }
  }

  void debug(String message, {String? tag}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.debug,
      message: message,
      tag: tag,
    );
    _addEntry(entry);
  }

  void info(String message, {String? tag}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.info,
      message: message,
      tag: tag,
    );
    _addEntry(entry);
  }

  void warning(String message, {String? tag}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.warning,
      message: message,
      tag: tag,
    );
    _addEntry(entry);
  }

  void error(String message, {String? tag}) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      level: LogLevel.error,
      message: message,
      tag: tag,
    );
    _addEntry(entry);
  }

  /// Capture print output and log it.
  void captureOutput(String line) {
    String? tag;
    String message = line;
    final tagMatch = RegExp(r'^\[([^\]]+)\]\s*(.*)$').firstMatch(line);
    if (tagMatch != null) {
      tag = tagMatch.group(1);
      message = tagMatch.group(2) ?? line;
    }

    LogLevel level = LogLevel.debug;
    final lower = line.toLowerCase();
    if (lower.contains('error') || lower.contains('exception') || lower.contains('failed')) {
      level = LogLevel.error;
    } else if (lower.contains('warning') || lower.contains('warn')) {
      level = LogLevel.warning;
    }

    _addEntry(LogEntry(
      timestamp: DateTime.now(),
      level: level,
      message: message,
      tag: tag,
    ));
  }

  void clear() {
    _logs.clear();
  }

  /// Get logs filtered by optional tag and level.
  List<LogEntry> getFilteredLogs({LogTag? tag, LogLevel? level, String? search}) {
    return _logs.where((entry) {
      if (tag != null && !tag.matches(entry.tag)) return false;
      if (level != null && entry.level != level) return false;
      if (search != null && search.isNotEmpty) {
        if (!entry.format().toLowerCase().contains(search.toLowerCase())) {
          return false;
        }
      }
      return true;
    }).toList();
  }

  String exportAsText() {
    final buffer = StringBuffer();
    buffer.writeln('=== KikoFlu Logs ===');
    buffer.writeln('Exported: ${DateTime.now().toIso8601String()}');
    buffer.writeln('Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}');
    buffer.writeln('Entries: ${_logs.length}');
    buffer.writeln('');
    for (final entry in _logs) {
      buffer.writeln(entry.format());
    }
    return buffer.toString();
  }

  Future<String> exportToFile([String? outputPath]) async {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    final fileName = 'kikoflu_log_$timestamp.txt';

    if (outputPath != null) {
      final file = File(outputPath);
      await file.writeAsString(exportAsText());
      return file.path;
    }

    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, fileName));
    await file.writeAsString(exportAsText());
    return file.path;
  }

  String get exportFileName {
    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-').split('.').first;
    return 'kikoflu_log_$timestamp.txt';
  }

  int get logCount => _logs.length;
}

/// Initialize the log system.
void setupLogCapture() {
  LogService.instance.initialize();
}
