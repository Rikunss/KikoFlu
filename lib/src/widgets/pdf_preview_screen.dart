import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:flutter_pdfview/flutter_pdfview.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/log_service.dart';
import '../services/cache_service.dart';
import '../services/storage_service.dart';
import '../services/cookie_service.dart';
import '../../l10n/app_localizations.dart';
import 'scrollable_appbar.dart';

/// PDF预览屏幕
class PdfPreviewScreen extends StatefulWidget {
  final String title;
  final String pdfUrl;
  final int? workId;
  final String? hash;

  const PdfPreviewScreen({
    super.key,
    required this.title,
    required this.pdfUrl,
    this.workId,
    this.hash,
  });

  @override
  State<PdfPreviewScreen> createState() => _PdfPreviewScreenState();
}

class _PdfPreviewScreenState extends State<PdfPreviewScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  String? _localFilePath;
  int _currentPage = 0;
  int _totalPages = 0;
  PDFViewController? _pdfViewController;

  @override
  void initState() {
    super.initState();
    _loadPdf();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _loadPdf() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final s = S.of(context);

    try {
      if (widget.pdfUrl.startsWith('file://')) {
        final localPath = widget.pdfUrl.substring(7);
        final localFile = File(localPath);

        if (await localFile.exists()) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final uri = Uri.file(localPath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
              if (mounted) {
                Navigator.of(context).pop();
              }
              return;
            }
          }

          if (!mounted) return;
          setState(() {
            _localFilePath = localPath;
            _isLoading = false;
          });
          return;
        } else {
          if (!mounted) return;
          setState(() {
            _errorMessage = s.localPdfNotExist;
            _isLoading = false;
          });
          return;
        }
      }

      if (widget.workId != null &&
          widget.hash != null &&
          widget.hash!.isNotEmpty) {
        final cachedPath = await CacheService.getCachedFileResource(
          workId: widget.workId!,
          hash: widget.hash!,
          fileType: 'pdf',
        );

        if (cachedPath != null) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final uri = Uri.file(cachedPath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
              if (mounted) {
                Navigator.of(context).pop();
              }
              return;
            }
          }

          setState(() {
            _localFilePath = cachedPath;
            _isLoading = false;
          });
          return;
        }

        final dio = Dio();
        dio.options.headers.addAll(CookieService.serverCookieHeaders);

        final newCachedPath = await CacheService.cacheFileResource(
          workId: widget.workId!,
          hash: widget.hash!,
          fileType: 'pdf',
          url: widget.pdfUrl,
          dio: dio,
        );

        if (newCachedPath != null) {
          if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
            final uri = Uri.file(newCachedPath);
            if (await canLaunchUrl(uri)) {
              await launchUrl(uri);
              if (mounted) {
                Navigator.of(context).pop();
              }
              return;
            }
          }

          setState(() {
            _localFilePath = newCachedPath;
            _isLoading = false;
          });
          return;
        }
      }

      final dio = Dio();
      final tempDir = await getTemporaryDirectory();
      final fileName = 'temp_pdf_${DateTime.now().millisecondsSinceEpoch}.pdf';
      final filePath = '${tempDir.path}/$fileName';

      await dio.download(
        widget.pdfUrl,
        filePath,
        options: Options(
          receiveTimeout: const Duration(seconds: 60),
          headers: CookieService.serverCookieHeaders,
        ),
        onReceiveProgress: (received, total) {
          if (total != -1) {
            LogService.instance.debug('PDF下载进度: ${(received / total * 100).toStringAsFixed(0)}%', tag: 'Download');
          }
        },
      );

      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        final uri = Uri.file(filePath);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri);
          if (mounted) {
            Navigator.of(context).pop();
          }
          return;
        } else {              throw Exception(s.cannotOpenPdf);
        }
      }

      setState(() {
        _localFilePath = filePath;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = S.of(context).loadPdfFailed(e.toString());
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScrollableAppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.title,
              style: const TextStyle(fontSize: 16),
            ),
            if (_totalPages > 0)
              Text(
                S.of(context).pdfPageOfTotal(_currentPage + 1, _totalPages),
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
        actions: [
          if (_localFilePath != null && _totalPages > 1) ...[
            IconButton(
              icon: const Icon(Icons.arrow_back_ios),
              onPressed: _currentPage > 0
                  ? () => _pdfViewController?.setPage(_currentPage - 1)
                  : null,
              tooltip: S.of(context).previousPage,
            ),
            IconButton(
              icon: const Icon(Icons.arrow_forward_ios),
              onPressed: _currentPage < _totalPages - 1
                  ? () => _pdfViewController?.setPage(_currentPage + 1)
                  : null,
              tooltip: S.of(context).nextPage,
            ),
          ],
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(S.of(context).loadingPdf),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(
                Icons.error_outline,
                size: 64,
                color: Colors.red,
              ),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadPdf,
                child: Text(S.of(context).retry),
              ),
            ],
          ),
        ),
      );
    }

    if (_localFilePath == null) {
      return Center(child: Text(S.of(context).pdfPathInvalid));
    }

    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.desktop_access_disabled,
                size: 64, color: Colors.grey),
            const SizedBox(height: 16),
            Text(S.of(context).desktopPdfPreviewNotSupported),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () async {
                final Uri uri = Uri.file(_localFilePath!);
                if (await canLaunchUrl(uri)) {
                  await launchUrl(uri);
                } else {
                  if (Platform.isWindows) {
                    await Process.run('explorer', [_localFilePath!]);
                  } else if (Platform.isLinux) {
                    await Process.run('xdg-open', [_localFilePath!]);
                  }
                }
              },
              icon: const Icon(Icons.open_in_new),
              label: Text(S.of(context).openWithSystemApp),
            ),
          ],
        ),
      );
    }

    return PDFView(
      filePath: _localFilePath!,
      enableSwipe: true,
      swipeHorizontal: false,
      autoSpacing: true,
      pageFling: true,
      pageSnap: true,
      fitPolicy: FitPolicy.BOTH,
      onRender: (pages) {
        setState(() => _totalPages = pages ?? 0);
      },
      onViewCreated: (PDFViewController controller) {
        _pdfViewController = controller;
      },
      onPageChanged: (page, total) {
        setState(() {
          _currentPage = page ?? 0;
          _totalPages = total ?? 0;
        });
      },
      onError: (error) {
        setState(() =>
            _errorMessage = S.of(context).renderPdfFailed(error.toString()));
      },
    );
  }
}