import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import '../services/log_service.dart';
import '../utils/snackbar_util.dart';

/// Enhanced log viewer with tag filtering, live updates, and export/share.
class LogScreen extends StatefulWidget {
  const LogScreen({super.key});

  @override
  State<LogScreen> createState() => _LogScreenState();
}

class _LogScreenState extends State<LogScreen> {
  final ScrollController _scrollController = ScrollController();
  StreamSubscription<LogEntry>? _subscription;
  List<LogEntry> _filteredLogs = [];
  LogLevel? _filterLevel;
  LogTag _filterTag = LogTag.all;
  String _searchQuery = '';
  bool _autoScroll = true;
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  static const int _maxDisplayLogs = 2000;

  @override
  void initState() {
    super.initState();
    _updateFilteredLogs();
    _subscription = LogService.instance.logStream.listen((_) {
      _updateFilteredLogs();
      if (_autoScroll) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (_scrollController.hasClients) {
            _scrollController.jumpTo(
              _scrollController.position.maxScrollExtent,
            );
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _updateFilteredLogs() {
    setState(() {
      _filteredLogs = LogService.instance.getFilteredLogs(
        tag: _filterTag,
        level: _filterLevel,
        search: _searchQuery.isNotEmpty ? _searchQuery : null,
      );
      if (_filteredLogs.length > _maxDisplayLogs) {
        _filteredLogs =
            _filteredLogs.sublist(_filteredLogs.length - _maxDisplayLogs);
      }
    });
  }

  Color _levelColor(LogLevel level) {
    switch (level) {
      case LogLevel.debug:
        return Theme.of(context).colorScheme.onSurfaceVariant;
      case LogLevel.info:
        return Theme.of(context).colorScheme.primary;
      case LogLevel.warning:
        return Colors.orange;
      case LogLevel.error:
        return Theme.of(context).colorScheme.error;
    }
  }

  Future<void> _exportLogs() async {
    try {
      final logService = LogService.instance;
      final content = logService.exportAsText();
      final fileName = logService.exportFileName;

      if (Platform.isIOS) {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Logs',
          fileName: fileName,
          bytes: Uint8List.fromList(content.codeUnits),
        );
        if (result != null && mounted) {
          SnackBarUtil.showSuccess(context, 'Logs exported to $result');
        }
      } else {
        final result = await FilePicker.platform.saveFile(
          dialogTitle: 'Export Logs',
          fileName: fileName,
        );
        if (result != null) {
          await File(result).writeAsString(content);
          if (mounted) {
            SnackBarUtil.showSuccess(context, 'Logs exported to $result');
          }
        }
      }
    } catch (e) {
      if (mounted) SnackBarUtil.showError(context, e.toString());
    }
  }

  Future<void> _shareLogs() async {
    try {
      final content = LogService.instance.exportAsText();
      await Share.share(content, subject: 'KikoFlu Logs');
    } catch (e) {
      if (mounted) SnackBarUtil.showError(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: _isSearching
            ? TextField(
                controller: _searchController,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Search logs...',
                  border: InputBorder.none,
                ),
                onChanged: (value) {
                  _searchQuery = value;
                  _updateFilteredLogs();
                },
              )
            : const Text('Log Viewer'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search),
            onPressed: () {
              setState(() {
                if (_isSearching) {
                  _isSearching = false;
                  _searchQuery = '';
                  _searchController.clear();
                  _updateFilteredLogs();
                } else {
                  _isSearching = true;
                }
              });
            },
          ),
          PopupMenuButton<LogLevel?>(
            icon: Icon(
              Icons.filter_alt_outlined,
              color: _filterLevel != null ? colorScheme.primary : null,
            ),
            onSelected: (level) {
              _filterLevel = level;
              _updateFilteredLogs();
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: null,
                child: Text('All Levels'),
              ),
              ...LogLevel.values.map((level) => PopupMenuItem(
                    value: level,
                    child: Text(level.name.toUpperCase()),
                  )),
            ],
          ),
          PopupMenuButton<String>(
            onSelected: (action) async {
              switch (action) {
                case 'copy':
                  await Clipboard.setData(
                    ClipboardData(text: LogService.instance.exportAsText()),
                  );
                  if (!context.mounted) return;
                  SnackBarUtil.showSuccess(context, 'Logs copied to clipboard');
                  break;
                case 'export':
                  await _exportLogs();
                  break;
                case 'share':
                  await _shareLogs();
                  break;
                case 'clear':
                  LogService.instance.clear();
                  _updateFilteredLogs();
                  break;
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'copy',
                child: ListTile(
                  leading: Icon(Icons.copy),
                  title: Text('Copy All'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.save_alt),
                  title: Text('Export'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: ListTile(
                  leading: Icon(Icons.share_outlined),
                  title: Text('Share'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem(
                value: 'clear',
                child: ListTile(
                  leading: Icon(Icons.delete_outline),
                  title: Text('Clear'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Tag Filter Chips ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            color: colorScheme.surfaceContainerHighest,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: LogTag.predefined.map((tag) {
                  final isSelected = _filterTag.name == tag.name;
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      label: Text(
                        tag.label,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      selected: isSelected,
                      onSelected: (_) {
                        setState(() {
                          _filterTag = tag;
                          _updateFilteredLogs();
                        });
                      },
                      visualDensity: VisualDensity.compact,
                      selectedColor: colorScheme.primaryContainer,
                      checkmarkColor: colorScheme.onPrimaryContainer,
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          // ── Status Bar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            color: colorScheme.surface,
            child: Row(
              children: [
                Text(
                  '${_filteredLogs.length} entries',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                if (_filterTag.name.isNotEmpty || _filterLevel != null) ...[
                  const SizedBox(width: 8),
                  Icon(Icons.filter_alt, size: 12,
                      color: colorScheme.primary),
                ],
                const Spacer(),
                InkWell(
                  onTap: () {
                    setState(() {
                      _autoScroll = !_autoScroll;
                    });
                    if (_autoScroll && _scrollController.hasClients) {
                      _scrollController.jumpTo(
                        _scrollController.position.maxScrollExtent,
                      );
                    }
                  },
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoScroll
                            ? Icons.vertical_align_bottom
                            : Icons.pause,
                        size: 14,
                        color: _autoScroll
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'Auto-scroll',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: _autoScroll
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          // ── Log List ──
          Expanded(
            child: _filteredLogs.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.article_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.3)),
                        const SizedBox(height: 12),
                        Text(
                          'No logs match filter',
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        const SizedBox(height: 4),
                        TextButton(
                          onPressed: () {
                            setState(() {
                              _filterTag = LogTag.all;
                              _filterLevel = null;
                              _searchQuery = '';
                              _searchController.clear();
                              _updateFilteredLogs();
                            });
                          },
                          child: const Text('Clear filters'),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    itemCount: _filteredLogs.length,
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    itemBuilder: (context, index) {
                      final entry = _filteredLogs[index];
                      return _LogEntryTile(
                        entry: entry,
                        levelColor: _levelColor(entry.level),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _LogEntryTile extends StatelessWidget {
  final LogEntry entry;
  final Color levelColor;

  const _LogEntryTile({
    required this.entry,
    required this.levelColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final time =
        '${entry.timestamp.hour.toString().padLeft(2, '0')}:' //
        '${entry.timestamp.minute.toString().padLeft(2, '0')}:' //
        '${entry.timestamp.second.toString().padLeft(2, '0')}';

    return InkWell(
      onLongPress: () {
        Clipboard.setData(ClipboardData(text: entry.format()));
        SnackBarUtil.showSuccess(context, 'Copied to clipboard');
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Time
            Text(
              time,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'monospace',
                color: colorScheme.onSurfaceVariant,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 6),
            // Level badge
            Container(
              width: 16,
              alignment: Alignment.center,
              child: Text(
                entry.levelLabel,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: levelColor,
                ),
              ),
            ),
            const SizedBox(width: 6),
            // Tag + Message
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    if (entry.tag != null)
                      TextSpan(
                        text: '[${entry.tag}] ',
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: 12,
                          color: colorScheme.primary,
                        ),
                      ),
                    TextSpan(
                      text: entry.message,
                      style: TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 12,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
