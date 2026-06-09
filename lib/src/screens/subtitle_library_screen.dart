import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_filex/open_filex.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subtitle_library_service.dart';
import '../providers/settings_provider.dart';
import '../widgets/text_preview_screen.dart';
import '../providers/audio_provider.dart';
import '../providers/lyric_provider.dart';
import '../widgets/responsive_dialog.dart';
import '../utils/file_icon_utils.dart';
import '../utils/snackbar_util.dart';
import '../../l10n/app_localizations.dart';

/// Maps disk folder names to localized display names.
String _localizedFolderTitle(BuildContext context, String diskName) {
  final s = S.of(context);
  switch (diskName) {
    case SubtitleLibraryService.parsedFolderName:
      return s.subtitleFolderParsed;
    case SubtitleLibraryService.savedFolderName:
      return s.subtitleFolderSaved;
    case SubtitleLibraryService.unknownFolderName:
      return s.subtitleFolderUnknown;
    default:
      return diskName;
  }
}

/// Format file size to human-readable string.
String _formatSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

class SubtitleLibraryScreen extends ConsumerStatefulWidget {
  const SubtitleLibraryScreen({super.key});

  @override
  ConsumerState<SubtitleLibraryScreen> createState() =>
      _SubtitleLibraryScreenState();
}

class _SubtitleLibraryScreenState extends ConsumerState<SubtitleLibraryScreen> {
  List<Map<String, dynamic>> _files = [];
  bool _isLoading = true;
  String? _errorMessage;
  LibraryStats? _stats;
  bool _isSelectionMode = false;
  final Set<String> _selectedPaths = {};
  bool _isSearching = false;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  String _currentPath = '';
  String? _rootPath;

  @override
  void initState() {
    super.initState();
    _initRootPath();
  }

  Future<void> _initRootPath() async {
    final dir = await SubtitleLibraryService.getSubtitleLibraryDirectory();
    if (!mounted) return;
    setState(() {
      _rootPath = dir.path;
      _currentPath = dir.path;
    });
    _loadFiles();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSelectionMode() {
    setState(() {
      _isSelectionMode = !_isSelectionMode;
      if (!_isSelectionMode) _selectedPaths.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedPaths.clear();
      _collectAllPaths(_files, _selectedPaths);
    });
  }

  void _collectAllPaths(List<Map<String, dynamic>> items, Set<String> paths) {
    for (final item in items) {
      paths.add(item['path'] as String);
      if (item['type'] == 'folder' && item['children'] != null) {
        _collectAllPaths(item['children'], paths);
      }
    }
  }

  void _deselectAll() => setState(() => _selectedPaths.clear());

  Future<void> _openSubtitleLibraryFolder() async {
    try {
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();
      if (Platform.isWindows || Platform.isMacOS || Platform.isLinux) {
        await launchUrl(Uri.file(libraryDir.path));
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).openFolderFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _deleteSelectedItems() async {
    if (_selectedPaths.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).confirmDelete),
        content: Text(S.of(context).deleteSelectedConfirm(_selectedPaths.length)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    int successCount = 0;
    for (final path in _selectedPaths) {
      if (await SubtitleLibraryService.delete(path)) successCount++;
    }

    if (!mounted) return;

    setState(() {
      _isSelectionMode = false;
      _selectedPaths.clear();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(S.of(context).deletedNOfTotalItems(successCount, _selectedPaths.length)),
        backgroundColor: successCount > 0 ? Colors.green : Colors.red,
      ),
    );

    _loadFiles();
  }

  Future<void> _loadFiles({bool forceRefresh = false}) async {
    setState(() { _isLoading = true; _errorMessage = null; });

    try {
      final files = await SubtitleLibraryService.getSubtitleFiles(
        forceRefresh: forceRefresh,
      );
      final stats = await SubtitleLibraryService.getStats(
        forceRefresh: forceRefresh,
      );
      setState(() { _files = files; _stats = stats; _isLoading = false; });
    } catch (e) {
      setState(() { _errorMessage = S.of(context).loadFailed; _isLoading = false; });
    }
  }

  Future<void> _importFile() async {
    _showSimpleLoadingDialog(S.of(context).importingSubtitleFile);
    final result = await SubtitleLibraryService.importSubtitleFile();
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result.success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) SnackBarUtil.showSuccess(context, result.message);
        });
      }
    } else {
      if (mounted) SnackBarUtil.showError(context, result.message);
    }
  }

  void _showSimpleLoadingDialog(String message) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              Text(message),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _importFolder() async {
    final updateProgress = _showProgressDialog(S.of(context).preparingImport);
    final result = await SubtitleLibraryService.importFolder(
      onProgress: updateProgress,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result.success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) SnackBarUtil.showSuccess(context, result.message);
        });
      }
    } else {
      if (mounted) SnackBarUtil.showError(context, result.message);
    }
  }

  Future<void> _importArchive() async {
    final updateProgress = _showProgressDialog(S.of(context).preparingExtract);
    final result = await SubtitleLibraryService.importArchive(
      onProgress: updateProgress,
    );
    if (!mounted) return;
    Navigator.of(context).pop();
    if (result.success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) SnackBarUtil.showSuccess(context, result.message);
        });
      }
    } else {
      if (mounted) SnackBarUtil.showError(context, result.message);
    }
  }

  void Function(String)? _showProgressDialog(String initialMessage) {
    final progressNotifier = ValueNotifier<String>(initialMessage);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: progressNotifier,
            builder: (context, message, child) => Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(message, textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
      ),
    );

    return (String message) {
      if (mounted) progressNotifier.value = message;
    };
  }

  void _showImportOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.insert_drive_file),
              title: Text(S.of(context).importSubtitleFile),
              subtitle: Text(S.of(context).supportedSubtitleFormats),
              onTap: () { Navigator.pop(context); _importFile(); },
            ),
            if (!Platform.isIOS)
              ListTile(
                leading: const Icon(Icons.folder),
                title: Text(S.of(context).importFolder),
                subtitle: Text(S.of(context).importFolderDesc),
                onTap: () { Navigator.pop(context); _importFolder(); },
              ),
            ListTile(
              leading: const Icon(Icons.archive),
              title: Text(S.of(context).importArchive),
              subtitle: Text(S.of(context).importArchiveDesc),
              onTap: () { Navigator.pop(context); _importArchive(); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _stepCircle(BuildContext context, String number) {
    return Container(
      width: 28, height: 28,
      margin: const EdgeInsets.only(right: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(
        child: Text(number, style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Theme.of(context).colorScheme.onPrimaryContainer,
        )),
      ),
    );
  }

  Widget _bulletPoint(BuildContext context, Widget child) {
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('• ', style: Theme.of(context).textTheme.bodyMedium),
          Expanded(child: child),
        ],
      ),
    );
  }

  void _showLibraryInfoDialog() {
    showDialog(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: Text(S.of(context).subtitleLibraryGuide, style: const TextStyle(fontSize: 18)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Step 1
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stepCircle(context, '1'),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.of(context).subtitleLibraryFunction,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(S.of(context).subtitleLibraryFunctionDesc,
                    style: Theme.of(context).textTheme.bodyMedium),
                ])),
              ]),
              const SizedBox(height: 16),
              // Step 2
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stepCircle(context, '2'),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.of(context).subtitleAutoLoad,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  Text(S.of(context).subtitleAutoLoadDesc,
                    style: Theme.of(context).textTheme.bodyMedium),
                  const SizedBox(height: 8),
                  _bulletPoint(context, Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [
                    TextSpan(text: S.of(context).guideInPrefix),
                    TextSpan(text: S.of(context).guideParsedFolder, style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: S.of(context).guideFindWorkDesc),
                  ]))),
                  const SizedBox(height: 6),
                  _bulletPoint(context, Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [
                    TextSpan(text: S.of(context).guideInPrefix),
                    TextSpan(text: S.of(context).guideSavedFolder, style: const TextStyle(fontWeight: FontWeight.bold)),
                    TextSpan(text: S.of(context).guideFindSubtitleDesc),
                  ]))),
                  const SizedBox(height: 6),
                  _bulletPoint(context, Text(S.of(context).guideMatchRule,
                    style: Theme.of(context).textTheme.bodyMedium)),
                ])),
              ]),
              const SizedBox(height: 16),
              // Step 3
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                _stepCircle(context, '3'),
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(S.of(context).smartCategoryAndMark,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
                  const SizedBox(height: 4),
                  _bulletPoint(context, Text.rich(TextSpan(style: Theme.of(context).textTheme.bodyMedium, children: [
                    TextSpan(text: S.of(context).guideRecognizedWorkPrefix),
                    WidgetSpan(alignment: PlaceholderAlignment.middle,
                      child: Container(padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.9), borderRadius: BorderRadius.circular(4)),
                        child: const Icon(Icons.closed_caption, color: Colors.green, size: 18))),
                    TextSpan(text: S.of(context).guideTagSuffix),
                    WidgetSpan(alignment: PlaceholderAlignment.middle,
                      child: SizedBox(width: 24, height: 24, child: Stack(children: [
                        const Icon(Icons.audiotrack, color: Colors.green, size: 24),
                        Positioned(left: 0, top: 0,
                          child: Container(decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                            child: Icon(Icons.subtitles, color: Colors.blue[600], size: 13))),
                      ]))),
                    TextSpan(text: S.of(context).guideSubtitleMatchSuffix),
                  ]))),
                  const SizedBox(height: 6),
                  _bulletPoint(context, Text(S.of(context).guideAutoRecognizeRJ,
                    style: Theme.of(context).textTheme.bodyMedium)),
                  const SizedBox(height: 6),
                  _bulletPoint(context, Text(S.of(context).guideAutoAddRJPrefix,
                    style: Theme.of(context).textTheme.bodyMedium)),
                ])),
              ]),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(S.of(context).gotIt)),
        ],
      ),
    );
  }
  void _showFileOptions(Map<String, dynamic> item, String path) {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (item['type'] == 'text' &&
                FileIconUtils.isLyricFile(item['title'] ?? ''))
              ListTile(
                leading: const Icon(Icons.subtitles, color: Colors.orange),
                title: Text(S.of(context).loadAsSubtitle),
                onTap: () { Navigator.pop(context); _loadLyricManually(item); },
              ),
            if (item['type'] == 'text')
              ListTile(
                leading: const Icon(Icons.visibility),
                title: Text(S.of(context).preview),
                onTap: () { Navigator.pop(context); _previewFile(path); },
              ),
            ListTile(
              leading: const Icon(Icons.open_in_new),
              title: Text(S.of(context).open),
              onTap: () { Navigator.pop(context); _openFile(path); },
            ),
            ListTile(
              leading: const Icon(Icons.drive_file_move),
              title: Text(S.of(context).moveTo),
              onTap: () { Navigator.pop(context); _moveItem(item); },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text(S.of(context).rename),
              onTap: () { Navigator.pop(context); _renameItem(item); },
            ),
            ListTile(
              leading: const Icon(Icons.delete, color: Colors.red),
              title: Text(S.of(context).delete, style: const TextStyle(color: Colors.red)),
              onTap: () { Navigator.pop(context); _deleteItem(item); },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _previewFile(String path) async {
    try {
      if (!mounted) return;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => TextPreviewScreen(
            title: path.split(Platform.pathSeparator).last,
            textUrl: 'file://$path',
            workId: null,
            onSavedToLibrary: _loadFiles,
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).previewFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _openFile(String path) async {
    try {
      await OpenFilex.open(path);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).openFailed(e.toString())),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _renameItem(Map<String, dynamic> item) async {
    final controller = TextEditingController(text: item['title']);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).rename),
        content: TextField(
          controller: controller,
          decoration: InputDecoration(
            labelText: S.of(context).newName,
            border: const OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text),
            child: Text(S.of(context).confirm),
          ),
        ],
      ),
    );
    if (newName == null || newName.isEmpty || newName == item['title']) return;
    final success = await SubtitleLibraryService.rename(item['path'], newName);
    if (!mounted) return;
    if (success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context).renameSuccess), backgroundColor: Colors.green),
            );
          }
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).renameFailed), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _deleteItem(Map<String, dynamic> item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).confirmDelete),
        content: Text(
            '${S.of(context).deleteItemConfirm(item['type'] == 'folder' ? _localizedFolderTitle(context, item['title']) : item['title'])}'
            '${item['type'] == 'folder' ? '\n\n${S.of(context).deleteFolderContentsWarning}' : ''}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final success = await SubtitleLibraryService.delete(item['path']);
    if (!mounted) return;
    if (success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context).deleteSuccess), backgroundColor: Colors.green),
            );
          }
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).deleteFailed), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _loadLyricManually(Map<String, dynamic> item) async {
    final title = item['title'] ?? S.of(context).unknownFile;
    final path = item['path'] as String;
    final currentTrack = ref.read(currentTrackProvider).value;
    if (currentTrack == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).noAudioCannotLoadSubtitle),
            backgroundColor: Colors.orange,
            duration: const Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => ResponsiveAlertDialog(
        title: Row(children: [
          Icon(Icons.subtitles, color: Theme.of(context).colorScheme.primary, size: 24),
          const SizedBox(width: 12),
          Text(S.of(context).loadSubtitle),
        ]),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(S.of(context).loadSubtitleConfirm,
                style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.closed_caption, size: 16,
                      color: Theme.of(context).colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(S.of(context).subtitleFile,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.primary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 16),
                  Row(children: [
                    Icon(Icons.music_note, size: 16,
                      color: Theme.of(context).colorScheme.secondary),
                    const SizedBox(width: 8),
                    Text(S.of(context).currentAudio,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                        color: Theme.of(context).colorScheme.secondary)),
                  ]),
                  const SizedBox(height: 8),
                  Text(currentTrack.title,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                ]),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.secondaryContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(children: [
                  Icon(Icons.info_outline, size: 16,
                    color: Theme.of(context).colorScheme.onSecondaryContainer),
                  const SizedBox(width: 8),
                  Expanded(child: Text(S.of(context).subtitleAutoRestoreNote,
                    style: TextStyle(fontSize: 12,
                      color: Theme.of(context).colorScheme.onSecondaryContainer))),
                ]),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false),
            child: Text(S.of(context).cancel)),
          ElevatedButton(onPressed: () => Navigator.pop(context, true),
            child: Text(S.of(context).confirmLoad)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(children: [
          const SizedBox(width: 16, height: 16,
            child: CircularProgressIndicator(strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white))),
          const SizedBox(width: 12),
          Text(S.of(context).loadingSubtitle),
        ]),
        duration: const Duration(seconds: 2),
      ),
    );
    try {
      await ref.read(lyricControllerProvider.notifier).loadLyricFromLocalFile(path);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(children: [
              const Icon(Icons.check_circle, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(child: Text(S.of(context).subtitleLoadSuccess(title))),
            ]),
            backgroundColor: Colors.green,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).subtitleLoadFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Future<void> _moveItem(Map<String, dynamic> item) async {
    final libraryDir = await SubtitleLibraryService.getSubtitleLibraryDirectory();
    final itemPath = item['path'] as String;
    if (!mounted) return;
    final selectedFolder = await showDialog<String>(
      context: context,
      builder: (context) => _FolderBrowserDialog(
        rootPath: libraryDir.path,
        excludePath: item['type'] == 'folder' ? itemPath : null,
      ),
    );
    if (selectedFolder == null) return;
    final success = await SubtitleLibraryService.move(itemPath, selectedFolder);
    if (!mounted) return;
    if (success) {
      await _loadFiles();
      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(S.of(context).moveSuccess), backgroundColor: Colors.green),
            );
          }
        });
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).moveFailed), backgroundColor: Colors.red),
        );
      }
    }
  }

  List<Map<String, dynamic>> _filterFiles(
      List<Map<String, dynamic>> files, String query) {
    if (query.isEmpty) return files;
    final List<Map<String, dynamic>> filtered = [];
    for (final file in files) {
      final isFolder = file['type'] == 'folder';
      final title = file['title'] ?? '';
      final matches = title.toLowerCase().contains(query.toLowerCase());
      if (isFolder) {
        final children = (file['children'] as List?)?.cast<Map<String, dynamic>>() ?? [];
        final fc = _filterFiles(children, query);
        if (matches || fc.isNotEmpty) {
          final nf = Map<String, dynamic>.from(file);
          nf['children'] = fc;
          filtered.add(nf);
        }
      } else if (matches) {
        filtered.add(file);
      }
    }
    return filtered;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<int>(subtitleLibraryRefreshTriggerProvider, (previous, next) {
      if (previous != next && _files.isNotEmpty) _loadFiles();
    });

    final displayFiles = _isSearching ? _filterFiles(_files, _searchQuery) : _getCurrentFiles();

    return PopScope(
      canPop: _currentPath == _rootPath || _currentPath.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _navigateUp();
      },
      child: Scaffold(
        floatingActionButton: FloatingActionButton(
          onPressed: _showImportOptions,
          tooltip: S.of(context).importSubtitle,
          child: const Icon(Icons.add),
        ),
        body: Column(children: [
          _SubtitleToolbar(
            rootPath: _rootPath,
            currentPath: _currentPath,
            isSelectionMode: _isSelectionMode,
            selectedCount: _selectedPaths.length,
            isSearching: _isSearching,
            searchQuery: _searchQuery,
            searchController: _searchController,
            stats: _stats,
            onToggleSelectionMode: _toggleSelectionMode,
            onSelectAll: _selectAll,
            onDeselectAll: _deselectAll,
            onDeleteSelected: _deleteSelectedItems,
            onRefresh: () => _loadFiles(forceRefresh: true),
            onOpenFolder: _openSubtitleLibraryFolder,
            onSearchChanged: (q) => setState(() { _searchQuery = q; }),
            onExitSearch: () => setState(() { _isSearching = false; _searchQuery = ''; _searchController.clear(); }),
            onEnterSearch: () => setState(() => _isSearching = true),
            onClearSearch: () => setState(() { _searchQuery = ''; _searchController.clear(); }),
            onNavigateTo: _navigateTo,
            onShowInfo: _showLibraryInfoDialog,
          ),
          if (_currentPath != _rootPath && _currentPath.isNotEmpty && !_isSearching)
            Material(
              color: Theme.of(context).colorScheme.surface,
              child: InkWell(
                onTap: _navigateUp,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    border: Border(bottom: BorderSide(
                      color: Theme.of(context).dividerColor.withValues(alpha: 0.5))),
                  ),
                  child: Row(children: [
                    const Icon(Icons.arrow_back, size: 20),
                    const SizedBox(width: 16),
                    Text(S.of(context).back, style: Theme.of(context).textTheme.bodyLarge),
                  ]),
                ),
              ),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        const Icon(Icons.error_outline, size: 48, color: Colors.red),
                        const SizedBox(height: 16),
                        Text(_errorMessage!),
                        const SizedBox(height: 16),
                        ElevatedButton(onPressed: _loadFiles, child: Text(S.of(context).retry)),
                      ]))
                    : _files.isEmpty
                        ? Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                            Icon(Icons.library_books_outlined, size: 64,
                              color: Theme.of(context).colorScheme.onSurfaceVariant),
                            const SizedBox(height: 16),
                            Text(S.of(context).subtitleLibraryEmpty,
                              style: TextStyle(fontSize: 18,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 8),
                            Text(S.of(context).tapToImportSubtitle,
                              style: TextStyle(fontSize: 14,
                                color: Theme.of(context).colorScheme.onSurfaceVariant)),
                          ]))
                        : RefreshIndicator(
                            onRefresh: () => _loadFiles(forceRefresh: true),
                            child: ListView(padding: const EdgeInsets.only(bottom: 80), children: [
                              _SubtitleFileTree(
                                items: displayFiles,
                                isSelectionMode: _isSelectionMode,
                                selectedPaths: _selectedPaths,
                                isRecursive: _isSearching,
                                onTap: (item, path) {
                                  final isFolder = item['type'] == 'folder';
                                  if (_isSelectionMode) {
                                    _toggleItemSelection(path, isFolder, item);
                                  } else if (isFolder) {
                                    _navigateTo(path);
                                  } else {
                                    _previewFile(path);
                                  }
                                },
                                onMoreOptions: _showFileOptions,
                                onLoadLyric: _loadLyricManually,
                                onPreview: _previewFile,
                              ),
                            ]),
                          ),
          ),
        ]),
      ),
    );
  }

  void _toggleItemSelection(String path, bool isFolder, Map<String, dynamic> item) {
    setState(() {
      if (_selectedPaths.contains(path)) {
        _selectedPaths.remove(path);
        if (isFolder) _removeChildrenFromSelection(item);
      } else {
        _selectedPaths.add(path);
        if (isFolder) _addChildrenToSelection(item);
      }
    });
  }

  void _addChildrenToSelection(Map<String, dynamic> folder) {
    if (folder['children'] != null) {
      for (final child in folder['children']) {
        _selectedPaths.add(child['path']);
        if (child['type'] == 'folder') _addChildrenToSelection(child);
      }
    }
  }

  void _removeChildrenFromSelection(Map<String, dynamic> folder) {
    if (folder['children'] != null) {
      for (final child in folder['children']) {
        _selectedPaths.remove(child['path']);
        if (child['type'] == 'folder') _removeChildrenFromSelection(child);
      }
    }
  }

  void _navigateTo(String path) {
    setState(() {
      _currentPath = path; _isSearching = false; _searchQuery = ''; _searchController.clear();
      _selectedPaths.clear(); _isSelectionMode = false;
    });
  }

  void _navigateUp() {
    if (_rootPath == null || _currentPath == _rootPath) return;
    final parent = Directory(_currentPath).parent;
    if (parent.path.length < _rootPath!.length) return;
    setState(() { _currentPath = parent.path; _selectedPaths.clear(); _isSelectionMode = false; });
  }

  List<Map<String, dynamic>> _getCurrentFiles() {
    if (_files.isEmpty) return [];
    if (_currentPath == _rootPath || _currentPath.isEmpty) return _files;
    return _findChildren(_files, _currentPath) ?? [];
  }

  List<Map<String, dynamic>>? _findChildren(List<Map<String, dynamic>> nodes, String target) {
    for (final node in nodes) {
      if (node['path'] == target) {
        return (node['children'] as List?)?.cast<Map<String, dynamic>>();
      }
      if (node['type'] == 'folder' && node['children'] != null) {
        if ((node['path'] as String).startsWith(target)) {
          final r = _findChildren(
            (node['children'] as List).cast<Map<String, dynamic>>(), target);
          if (r != null) return r;
        }
      }
    }
    return null;
  }
}

/// ===================================================================
/// Toolbar (selection/search/action modes + breadcrumbs)
/// ===================================================================
class _SubtitleToolbar extends StatelessWidget {
  final String? rootPath;
  final String currentPath;
  final bool isSelectionMode;
  final int selectedCount;
  final bool isSearching;
  final String searchQuery;
  final TextEditingController searchController;
  final LibraryStats? stats;
  final VoidCallback onToggleSelectionMode;
  final VoidCallback onSelectAll;
  final VoidCallback onDeselectAll;
  final VoidCallback onDeleteSelected;
  final VoidCallback onRefresh;
  final VoidCallback onOpenFolder;
  final void Function(String) onSearchChanged;
  final VoidCallback onExitSearch;
  final VoidCallback onEnterSearch;
  final VoidCallback onClearSearch;
  final void Function(String) onNavigateTo;
  final VoidCallback onShowInfo;

  const _SubtitleToolbar({
    this.rootPath,
    required this.currentPath,
    required this.isSelectionMode,
    required this.selectedCount,
    required this.isSearching,
    required this.searchQuery,
    required this.searchController,
    this.stats,
    required this.onToggleSelectionMode,
    required this.onSelectAll,
    required this.onDeselectAll,
    required this.onDeleteSelected,
    required this.onRefresh,
    required this.onOpenFolder,
    required this.onSearchChanged,
    required this.onExitSearch,
    required this.onEnterSearch,
    required this.onClearSearch,
    required this.onNavigateTo,
    required this.onShowInfo,
  });

  @override
  Widget build(BuildContext context) {
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    final hPad = isLandscape ? 24.0 : 8.0;

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (isSelectionMode)
          _buildSelectionBar(context, hPad)
        else if (isSearching)
          _buildSearchBar(context, hPad)
        else
          _buildActionBar(context, hPad),
        if (!isSearching && !isSelectionMode) _buildBreadcrumbs(context, hPad),
      ]),
    );
  }

  Widget _buildSelectionBar(BuildContext context, double hPad) {
    return Row(children: [
      Padding(
        padding: EdgeInsets.only(left: hPad - 8),
        child: IconButton(
          icon: const Icon(Icons.close), iconSize: 22,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onToggleSelectionMode,
          tooltip: S.of(context).exitSelection,
        ),
      ),
      Text(S.of(context).selectedCount(selectedCount), style: Theme.of(context).textTheme.titleSmall),
      const Spacer(),
      IconButton(
        icon: Icon(selectedCount == 0 ? Icons.select_all : Icons.deselect),
        iconSize: 22, padding: const EdgeInsets.all(8),
        constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
        onPressed: selectedCount == 0 ? onSelectAll : onDeselectAll,
        tooltip: selectedCount == 0 ? S.of(context).selectAll : S.of(context).deselectAll,
      ),
      if (selectedCount > 0)
        IconButton(
          icon: const Icon(Icons.delete), iconSize: 22,
          padding: const EdgeInsets.all(8),
          constraints: const BoxConstraints(minWidth: 40, minHeight: 40),
          onPressed: onDeleteSelected,
          tooltip: S.of(context).deleteWithCount(selectedCount),
          color: Theme.of(context).colorScheme.error,
        ),
      SizedBox(width: hPad - 8),
    ]);
  }

  Widget _buildSearchBar(BuildContext context, double hPad) {
    return Row(children: [
      Padding(
        padding: EdgeInsets.only(left: hPad - 8),
        child: IconButton(icon: const Icon(Icons.arrow_back), onPressed: onExitSearch),
      ),
      Expanded(child: TextField(
        controller: searchController, autofocus: true,
        decoration: InputDecoration(hintText: S.of(context).searchSubtitles, border: InputBorder.none),
        onChanged: onSearchChanged,
      )),
      if (searchQuery.isNotEmpty)
        IconButton(icon: const Icon(Icons.clear), onPressed: onClearSearch),
      SizedBox(width: hPad - 8),
    ]);
  }

  Widget _buildActionBar(BuildContext context, double hPad) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: hPad),
      child: Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
        TextButton.icon(
          icon: const Icon(Icons.refresh, size: 20),
          label: Text(S.of(context).reload),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
          ),
          onPressed: onRefresh,
        ),
        if (Platform.isWindows || Platform.isMacOS || Platform.isLinux)
          TextButton.icon(
            icon: const Icon(Icons.folder_open, size: 20),
            label: Text(S.of(context).openFolder),
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              backgroundColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.5),
            ),
            onPressed: onOpenFolder,
          ),
        IconButton(
          icon: const Icon(Icons.search), onPressed: onEnterSearch,
          tooltip: S.of(context).search,
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          icon: const Icon(Icons.checklist), onPressed: onToggleSelectionMode,
          tooltip: S.of(context).select,
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        ),
        IconButton(
          icon: Icon(Icons.info_outline, size: 20, color: Theme.of(context).colorScheme.primary),
          padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          tooltip: S.of(context).subtitleLibraryGuide, onPressed: onShowInfo,
        ),
        if (stats != null)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(4),
            ),
            child: Text(S.of(context).nFilesWithSize(stats!.totalFiles, stats!.sizeFormatted),
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ),
      ]),
    );
  }

  Widget _buildBreadcrumbs(BuildContext context, double hPad) {
    if (rootPath == null) return const SizedBox.shrink();
    final crumbs = <Widget>[];
    crumbs.add(InkWell(
      onTap: () => onNavigateTo(rootPath!),
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
        child: Text(S.of(context).subtitleLibrary,
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary,
            fontWeight: FontWeight.w500)),
      ),
    ));

    if (currentPath.isNotEmpty && currentPath != rootPath) {
      var relative = currentPath.substring(rootPath!.length);
      if (relative.startsWith(Platform.pathSeparator)) relative = relative.substring(1);
      final parts = relative.split(Platform.pathSeparator);
      String buildPath = rootPath!;
      for (var i = 0; i < parts.length; i++) {
        buildPath = '$buildPath${Platform.pathSeparator}${parts[i]}';
        final target = buildPath;
        crumbs.add(Text(' > ',
          style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurfaceVariant)));
        if (i == parts.length - 1) {
          crumbs.add(Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Text(parts[i],
              style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.onSurface,
                fontWeight: FontWeight.bold)),
          ));
        } else {
          crumbs.add(InkWell(
            onTap: () => onNavigateTo(target),
            borderRadius: BorderRadius.circular(4),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(parts[i],
                style: TextStyle(fontSize: 13, color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.w500)),
            ),
          ));
        }
      }
    }

    return Padding(
      padding: EdgeInsets.only(left: hPad, right: hPad, top: 8),
      child: Row(children: [
        Icon(Icons.folder_open, size: 16, color: Theme.of(context).colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: crumbs),
        )),
      ]),
    );
  }
}

/// ===================================================================
/// File tree - recursive rendering
/// ===================================================================
class _SubtitleFileTree extends StatelessWidget {
  final List<Map<String, dynamic>> items;
  final bool isSelectionMode;
  final Set<String> selectedPaths;
  final bool isRecursive;
  final void Function(Map<String, dynamic> item, String path) onTap;
  final void Function(Map<String, dynamic> item, String path) onMoreOptions;
  final void Function(Map<String, dynamic> item) onLoadLyric;
  final void Function(String path) onPreview;

  const _SubtitleFileTree({
    required this.items,
    required this.isSelectionMode,
    required this.selectedPaths,
    this.isRecursive = false,
    required this.onTap,
    required this.onMoreOptions,
    required this.onLoadLyric,
    required this.onPreview,
  });

  @override
  Widget build(BuildContext context) {
    return Column(children: _buildNodes(context, items, level: 0));
  }

  List<Widget> _buildNodes(BuildContext context, List<Map<String, dynamic>> nodes, {int level = 0}) {
    final result = <Widget>[];
    for (final item in nodes) {
      final isFolder = item['type'] == 'folder';
      final path = item['path'] as String;
      final isSelected = selectedPaths.contains(path);

      result.add(InkWell(
        onTap: () => onTap(item, path),
        child: Padding(
          padding: EdgeInsets.only(left: 16.0 + (level * 20.0), right: 16.0, top: 8.0, bottom: 8.0),
          child: Row(children: [
            SizedBox(width: 24, child: Icon(
              isFolder ? Icons.folder : Icons.text_snippet,
              color: isFolder ? Colors.amber : Colors.grey, size: 20)),
            const SizedBox(width: 8),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min,
              children: [
                Text(isFolder ? _localizedFolderTitle(context, item['title']) : item['title'],
                  style: const TextStyle(fontSize: 14), overflow: TextOverflow.ellipsis),
                if (!isFolder && item['size'] != null)
                  Text(_formatSize(item['size']),
                    style: TextStyle(fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant)),
              ],
            )),
            if (!isFolder && FileIconUtils.isLyricFile(item['title'] ?? ''))
              Row(mainAxisSize: MainAxisSize.min, children: [
                IconButton(onPressed: () => onLoadLyric(item),
                  icon: const Icon(Icons.subtitles), color: Colors.orange,
                  tooltip: S.of(context).loadAsSubtitle, iconSize: 20,
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
                IconButton(onPressed: () => onPreview(path),
                  icon: const Icon(Icons.visibility), color: Colors.blue,
                  tooltip: S.of(context).preview, iconSize: 20,
                  padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
              ])
            else if (isFolder)
              Text(S.of(context).nItems((item['children'] as List?)?.length ?? 0),
                style: TextStyle(fontSize: 12, color: Colors.grey[600])),
            IconButton(icon: const Icon(Icons.more_vert, size: 18),
              onPressed: () => onMoreOptions(item, path),
              padding: EdgeInsets.zero, constraints: const BoxConstraints(minWidth: 32, minHeight: 32)),
            if (isSelectionMode)
              Padding(padding: const EdgeInsets.only(left: 8),
                child: Icon(isSelected ? Icons.check_circle : Icons.radio_button_unchecked,
                  color: isSelected ? Theme.of(context).colorScheme.primary : Colors.grey, size: 20)),
          ]),
        ),
      ));

      if (isRecursive && isFolder && item['children'] != null) {
        result.addAll(_buildNodes(context,
          (item['children'] as List).cast<Map<String, dynamic>>(),
          level: level + 1));
      }
    }
    return result;
  }
}

/// Folder browser dialog (lazy-loaded)
class _FolderBrowserDialog extends StatefulWidget {
  final String rootPath;
  final String? excludePath;
  const _FolderBrowserDialog({required this.rootPath, this.excludePath});

  @override
  State<_FolderBrowserDialog> createState() => _FolderBrowserDialogState();
}

class _FolderBrowserDialogState extends State<_FolderBrowserDialog> {
  final List<String> _pathStack = [];
  List<Map<String, dynamic>> _currentFolders = [];
  bool _loading = false;

  @override
  void initState() { super.initState(); _loadFolders(); }

  String get _currentPath => _pathStack.isEmpty ? widget.rootPath : _pathStack.last;

  String _currentDisplayName(BuildContext context) {
    if (_pathStack.isEmpty) return S.of(context).rootDirectory;
    final name = _pathStack.last.split(Platform.pathSeparator).last;
    final dn = _localizedFolderTitle(context, name);
    return dn.length > 10 ? '${dn.substring(0, 10)}...' : dn;
  }

  Future<void> _loadFolders() async {
    setState(() => _loading = true);
    try {
      var folders = await SubtitleLibraryService.getSubFolders(_currentPath);
      if (widget.excludePath != null) {
        folders = folders.where((f) {
          final fp = f['path'] as String;
          return fp != widget.excludePath &&
              !fp.startsWith('${widget.excludePath}${Platform.pathSeparator}');
        }).toList();
      }
      setState(() { _currentFolders = folders; _loading = false; });
    } catch (_) { setState(() => _loading = false); }
  }

  void _navigateToFolder(String path) { setState(() => _pathStack.add(path)); _loadFolders(); }
  void _navigateBack() { if (_pathStack.isNotEmpty) { setState(() => _pathStack.removeLast()); _loadFolders(); } }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(children: [
        if (_pathStack.isNotEmpty)
          IconButton(icon: const Icon(Icons.arrow_back), onPressed: _navigateBack,
            tooltip: S.of(context).goToParent),
        Expanded(child: Text(S.of(context).moveToTarget(_currentDisplayName(context)),
          style: const TextStyle(fontSize: 16))),
      ]),
      content: SizedBox(
        width: double.maxFinite, height: 400,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : Column(children: [
                Expanded(child: _currentFolders.isEmpty
                  ? Center(child: Text(S.of(context).noSubfoldersHere,
                      style: const TextStyle(color: Colors.grey)))
                  : ListView.builder(
                      itemCount: _currentFolders.length,
                      itemBuilder: (ctx, i) {
                        final f = _currentFolders[i];
                        return ListTile(
                          leading: const Icon(Icons.folder, color: Colors.amber),
                          title: Text(_localizedFolderTitle(ctx, f['name'])),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => _navigateToFolder(f['path']),
                        );
                      },
                    )),
              ]),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text(S.of(context).cancel)),
        Flexible(child: ElevatedButton.icon(
          icon: const Icon(Icons.check_circle, size: 18),
          label: Text(_currentDisplayName(context), overflow: TextOverflow.ellipsis, maxLines: 1),
          style: ElevatedButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
            foregroundColor: Theme.of(context).colorScheme.onPrimary,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          onPressed: () => Navigator.pop(context, _currentPath),
        )),
      ],
    );
  }
}
