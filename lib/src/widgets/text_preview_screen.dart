import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../services/log_service.dart';
import '../services/cache_service.dart';
import '../services/translation_service.dart';
import '../services/subtitle_library_service.dart';
import '../services/cookie_service.dart';
import '../utils/snackbar_util.dart';
import '../utils/encoding_utils.dart';
import '../utils/scroll_optimization.dart';
import '../../l10n/app_localizations.dart';
import 'scrollable_appbar.dart';

/// 文本预览屏幕
class TextPreviewScreen extends StatefulWidget {
  final String textUrl;
  final String title;
  final int? workId;
  final String? hash;
  final VoidCallback? onSavedToLibrary;

  const TextPreviewScreen({
    super.key,
    required this.textUrl,
    required this.title,
    this.workId,
    this.hash,
    this.onSavedToLibrary,
  });

  @override
  State<TextPreviewScreen> createState() => _TextPreviewScreenState();
}

class _TextPreviewScreenState extends State<TextPreviewScreen> {
  bool _isLoading = true;
  String? _content;
  String? _translatedContent;
  String? _errorMessage;
  final ScrollController _scrollController = ScrollController();
  final ScrollThrottler _scrollThrottler = ScrollThrottler();
  double _scrollProgress = 0.0;
  bool _showTranslation = false;
  bool _isTranslating = false;
  String _translationProgress = '';
  bool _isEditMode = false;
  late TextEditingController _textController;
  late TextEditingController _translatedTextController;
  String _detectedEncoding = 'UTF-8';

  @override
  void initState() {
    super.initState();
    _textController = TextEditingController();
    _translatedTextController = TextEditingController();
    _loadTextContent();
    _scrollController.addListener(_updateScrollProgress);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateScrollProgress);
    _scrollController.dispose();
    _scrollThrottler.dispose();
    _textController.dispose();
    _translatedTextController.dispose();
    super.dispose();
  }

  void _updateScrollProgress() {
    _scrollThrottler.throttle(() {
      if (_scrollController.hasClients) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.position.pixels;
        setState(() {
          _scrollProgress = maxScroll > 0 ? currentScroll / maxScroll : 0.0;
        });
      }
    });
  }

  /// 智能检测文件编码并读取内容
  /// 支持 UTF-8、GBK、Shift-JIS 等常见编码
  Future<String> _readFileWithEncoding(File file) async {
    try {
      final (content, encoding) =
          await EncodingUtils.readFileWithEncoding(file);
      _detectedEncoding = encoding;
      LogService.instance.debug('[TextPreview] 检测到文件编码: $encoding', tag: 'UI');
      return content;
    } catch (e) {
      LogService.instance.error('[TextPreview] 读取文件失败: $e', tag: 'UI');
      rethrow;
    }
  }

  /// 智能解码字节数组
  /// 尝试多种编码格式：UTF-16LE/BE -> UTF-8 -> GBK -> Shift-JIS -> Latin1
  String _decodeBytes(List<int> bytes) {
    final (content, encoding) = EncodingUtils.decodeBytes(bytes);
    _detectedEncoding = encoding;
    LogService.instance.debug('[TextPreview] 检测到编码: $encoding', tag: 'UI');
    return content;
  }

  /// 将字符串编码为字节数组
  /// 使用检测到的原始编码，保持文件编码一致性
  List<int> _encodeString(String content) {
    LogService.instance.debug('[TextPreview] 使用 $_detectedEncoding 编码保存', tag: 'UI');
    return EncodingUtils.encodeString(content, _detectedEncoding);
  }

  void _showSaveOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.folder_open),
              title: Text(S.of(context).saveToLocal),
              subtitle: Text(S.of(context).selectDirectoryToSaveFile),
              onTap: () {
                Navigator.pop(context);
                _saveToLocal();
              },
            ),
            ListTile(
              leading: const Icon(Icons.library_books),
              title: Text(S.of(context).saveToSubtitleLibrary),
              subtitle: Text(S.of(context).saveToSubtitleLibraryDesc),
              onTap: () {
                Navigator.pop(context);
                _saveToSubtitleLibrary();
              },
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _saveToLocal() async {
    final contentToSave = _getCurrentContent();
    final s = S.of(context);
    if (contentToSave == null || contentToSave.isEmpty) {
      if (mounted) {
        SnackBarUtil.showWarning(context, s.noContentToSave);
      }
      return;
    }

    try {
      String fileName = widget.title;
      if (!fileName.contains('.')) {
        fileName = '$fileName.txt';
      }

      if (Platform.isIOS) {
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$fileName');
        final bytes = _encodeString(contentToSave);
        await tempFile.writeAsBytes(bytes);
        try {
          if (!mounted) return;
          final box = context.findRenderObject() as RenderBox?;
          final mediaQuerySize = MediaQuery.of(context).size;
          await Share.shareXFiles(
            [XFile(tempFile.path)],
            sharePositionOrigin: box != null
                ? box.localToGlobal(Offset.zero) & box.size
                : Rect.fromLTWH(0, 0, mediaQuerySize.width, 80),
          );
        } finally {
          if (await tempFile.exists()) {
            await tempFile.delete();
          }
        }
      } else {
        final directoryPath = await FilePicker.getDirectoryPath();
        if (directoryPath == null) return;
        if (!mounted) return;

        String finalPath = path.join(directoryPath, fileName);
        int counter = 1;
        while (await File(finalPath).exists()) {
          final nameWithoutExt = path.basenameWithoutExtension(fileName);
          final ext = path.extension(fileName);
          finalPath =
              path.join(directoryPath, '${nameWithoutExt}_$counter$ext');
          counter++;
        }

        final file = File(finalPath);
        final bytes = _encodeString(contentToSave);
        await file.writeAsBytes(bytes);

        if (!mounted) return;
        SnackBarUtil.showSuccess(
            context, s.fileSavedToPath(finalPath));
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context, s.saveFailedWithError(e.toString()));
      }
    }
  }

  Future<void> _saveToSubtitleLibrary() async {
    final contentToSave = _getCurrentContent();
    final s2 = S.of(context);
    if (contentToSave == null || contentToSave.isEmpty) {
      if (mounted) {
        SnackBarUtil.showWarning(context, s2.noContentToSave);
      }
      return;
    }

    try {
      final libraryDir =
          await SubtitleLibraryService.getSubtitleLibraryDirectory();

      final savedDir = Directory(
          path.join(libraryDir.path, SubtitleLibraryService.savedFolderName));
      if (!await savedDir.exists()) {
        await savedDir.create();
      }

      String fileName = widget.title;
      if (!fileName.contains('.')) {
        fileName = '$fileName.txt';
      }

      String finalPath = path.join(savedDir.path, fileName);
      int counter = 1;
      while (await File(finalPath).exists()) {
        final nameWithoutExt = path.basenameWithoutExtension(fileName);
        final ext = path.extension(fileName);
        finalPath = path.join(savedDir.path, '${nameWithoutExt}_$counter$ext');
        counter++;
      }

      final file = File(finalPath);
      final bytes = _encodeString(contentToSave);
      await file.writeAsBytes(bytes);

      await SubtitleLibraryService.refreshDirectoryCache(savedDir.path);

      widget.onSavedToLibrary?.call();

      if (mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            SnackBarUtil.showSuccess(
                context, s2.savedToSubtitleLibrary);
          }
        });
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context, s2.saveFailedWithError(e.toString()));
      }
    }
  }

  String? _getCurrentContent() {
    if (_showTranslation && _translatedContent != null) {
      return _isEditMode ? _translatedTextController.text : _translatedContent;
    } else {
      return _isEditMode ? _textController.text : _content;
    }
  }

  Future<void> _loadTextContent() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.textUrl.startsWith('file://')) {
        final localPath = widget.textUrl.substring(7);
        final localFile = File(localPath);

        if (await localFile.exists()) {
          final content = await _readFileWithEncoding(localFile);
          setState(() {
            _content = content;
            _textController.text = content;
            _isLoading = false;
          });
          return;
        } else {
          setState(() {
            _errorMessage = S.of(context).localFileNotExist;
            _isLoading = false;
          });
          return;
        }
      }

      if (widget.workId != null &&
          widget.hash != null &&
          widget.hash!.isNotEmpty) {
        final cachedContent = await CacheService.getCachedTextContent(
          workId: widget.workId!,
          hash: widget.hash!,
          fileName: null,
        );

        if (cachedContent != null) {
          setState(() {
            _content = cachedContent;
            _textController.text = cachedContent;
            _isLoading = false;
          });
          return;
        }
      }

      final dio = Dio();
      final response = await dio.get(
        widget.textUrl,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: const Duration(seconds: 30),
          headers: CookieService.serverCookieHeaders,
        ),
      );

      if (response.statusCode == 200) {
        final bytes = response.data as List<int>;
        final content = _decodeBytes(bytes);

        if (widget.workId != null &&
            widget.hash != null &&
            widget.hash!.isNotEmpty) {
          await CacheService.cacheTextContent(
            workId: widget.workId!,
            hash: widget.hash!,
            content: content,
          );
        }

        setState(() {
          _content = content;
          _textController.text = content;
          _isLoading = false;
        });
      } else {
        throw Exception(
            'HTTP ${response.statusCode}: ${response.statusMessage}');
      }
    } catch (e) {
      setState(() {
        _errorMessage = S.of(context).loadTextFailed(e.toString());
        _isLoading = false;
      });
    }
  }

  Future<void> _translateContent() async {
    if (_content == null || _content!.isEmpty) return;

    setState(() {
      _isTranslating = true;
      _translationProgress = S.of(context).preparingTranslation;
    });

    try {
      final translationService = TranslationService();
      final translated = await translationService.translateLongText(
        _content!,
        onProgress: (current, total) {
          setState(() {
            _translationProgress =
                S.of(context).translatingProgress(current, total);
          });
        },
      );

      setState(() {
        _translatedContent = translated;
        _translatedTextController.text = translated;
        _showTranslation = true;
        _isTranslating = false;
        _translationProgress = '';
      });
    } catch (e) {
      setState(() {
        _isTranslating = false;
        _translationProgress = '';
      });
      if (mounted) {
        SnackBarUtil.showError(
            context, S.of(context).translationFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(widget.title),
        actions: [
          if (_content != null && _content!.isNotEmpty)
            IconButton(
              icon: Icon(
                _isEditMode ? Icons.visibility : Icons.edit,
                color:
                    _isEditMode ? Theme.of(context).colorScheme.primary : null,
              ),
              onPressed: () {
                setState(() {
                  _isEditMode = !_isEditMode;
                });
              },
              tooltip: _isEditMode
                  ? S.of(context).previewMode
                  : S.of(context).editMode,
            ),
          if (_content != null && _content!.isNotEmpty)
            IconButton(
              icon: _isTranslating
                  ? SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                    )
                  : Icon(
                      Icons.g_translate,
                      color: _showTranslation
                          ? Theme.of(context).colorScheme.primary
                          : null,
                    ),
              onPressed: _isTranslating
                  ? null
                  : () {
                      if (_translatedContent != null) {
                        setState(() {
                          _showTranslation = !_showTranslation;
                        });
                      } else {
                        _translateContent();
                      }
                    },
              tooltip: _showTranslation
                  ? S.of(context).showOriginal
                  : S.of(context).translateContent,
            ),
          IconButton(
            icon: const Icon(Icons.download),
            onPressed: _showSaveOptions,
            tooltip: S.of(context).save,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_errorMessage != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error, size: 64, color: Colors.red),
            const SizedBox(height: 16),
            Text(
              _errorMessage!,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _loadTextContent,
              child: Text(S.of(context).retry),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        LinearProgressIndicator(
          value: _scrollProgress,
          backgroundColor: Colors.grey[300],
          valueColor: AlwaysStoppedAnimation<Color>(
            Theme.of(context).colorScheme.primary,
          ),
          minHeight: 3,
        ),
        if (_isTranslating)
          Container(
            padding: const EdgeInsets.all(8),
            color: Theme.of(context).colorScheme.primaryContainer,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(_translationProgress),
              ],
            ),
          ),
        Expanded(
          child: Scrollbar(
            controller: _scrollController,
            thumbVisibility: true,
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              child: _isEditMode
                  ? TextField(
                      controller: _showTranslation && _translatedContent != null
                          ? _translatedTextController
                          : _textController,
                      maxLines: null,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                      decoration: InputDecoration(
                        border: const OutlineInputBorder(),
                        hintText: S.of(context).editTextContentHint,
                      ),
                    )
                  : SelectableText(
                      _showTranslation && _translatedContent != null
                          ? _translatedContent!
                          : _content ?? '',
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 14,
                      ),
                    ),
            ),
          ),
        ),
      ],
    );
  }
}

class TimeoutException implements Exception {
  final String message;
  TimeoutException(this.message);

  @override
  String toString() => message;
}