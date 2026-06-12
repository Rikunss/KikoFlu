import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:saver_gallery/saver_gallery.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../utils/snackbar_util.dart';
import '../services/storage_service.dart';
import '../../l10n/app_localizations.dart';

/// 封面预览对话框，支持放大查看和保存图片
class CoverPreviewDialog extends StatefulWidget {
  /// 网络图片URL
  final String? imageUrl;

  /// 本地图片路径
  final String? localPath;

  /// 用于生成保存文件名的标识
  final String? identifier;

  /// Hero标签（用于动画过渡）
  final String? heroTag;

  const CoverPreviewDialog({
    super.key,
    this.imageUrl,
    this.localPath,
    this.identifier,
    this.heroTag,
  }) : assert(imageUrl != null || localPath != null,
            'Either imageUrl or localPath must be provided');

  /// 显示封面预览对话框
  static Future<void> show(
    BuildContext context, {
    String? imageUrl,
    String? localPath,
    String? identifier,
    String? heroTag,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        barrierColor: Colors.black87,
        pageBuilder: (context, animation, secondaryAnimation) {
          return CoverPreviewDialog(
            imageUrl: imageUrl,
            localPath: localPath,
            identifier: identifier,
            heroTag: heroTag,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<CoverPreviewDialog> createState() => _CoverPreviewDialogState();
}

class _CoverPreviewDialogState extends State<CoverPreviewDialog> {
  final TransformationController _transformController =
      TransformationController();
  bool _isSaving = false;
  bool _showControls = true;

  @override
  void dispose() {
    _transformController.dispose();
    super.dispose();
  }

  void _handleDoubleTap() {
    final currentScale = _transformController.value.getMaxScaleOnAxis();

    if (currentScale > 1.0) {
      _transformController.value = Matrix4.identity();
    } else {
      const newScale = 2.5;
      _transformController.value = Matrix4.diagonal3Values(newScale, newScale, 1.0);
    }
  }

  Future<void> _saveImage() async {
    if (_isSaving) return;

    setState(() => _isSaving = true);

    try {
      Uint8List? imageBytes;
      String fileName;

      if (widget.localPath != null && File(widget.localPath!).existsSync()) {
        // 本地图片
        imageBytes = await File(widget.localPath!).readAsBytes();
        fileName =
            'cover_${widget.identifier ?? DateTime.now().millisecondsSinceEpoch}.jpg';
      } else if (widget.imageUrl != null) {
        // 网络图片
        final response = await Dio().get<List<int>>(
          widget.imageUrl!,
          options: Options(
            responseType: ResponseType.bytes,
            headers: StorageService.serverCookieHeaders,
          ),
        );
        imageBytes = Uint8List.fromList(response.data!);
        fileName =
            'cover_${widget.identifier ?? DateTime.now().millisecondsSinceEpoch}.jpg';
      } else {
        throw Exception(S.of(context).noImageAvailable);
      }

      // 根据平台选择保存方式
      if (Platform.isAndroid || Platform.isIOS) {
        await _saveToGallery(imageBytes, fileName);
      } else {
        await _saveToFile(imageBytes, fileName);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context, S.of(context).saveFailedWithError(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _saveToGallery(Uint8List bytes, String fileName) async {
    // 请求权限
    if (Platform.isAndroid) {
      final status = await Permission.photos.request();
      if (!status.isGranted) {
        final storageStatus = await Permission.storage.request();
        if (!storageStatus.isGranted) {
          if (mounted) {
            SnackBarUtil.showError(
                context, S.of(context).storagePermissionRequiredForImage);
          }
          return;
        }
      }
    }

    final result = await SaverGallery.saveImage(
      bytes,
      fileName: fileName,
      androidRelativePath: 'Pictures/KikoFlu',
      skipIfExists: false,
    );

    if (mounted) {
      if (result.isSuccess) {
        SnackBarUtil.showSuccess(context, S.of(context).savedToGallery);
      } else {
        SnackBarUtil.showError(context, S.of(context).saveImageFailed);
      }
    }
  }

  Future<void> _saveToFile(Uint8List bytes, String fileName) async {
    // 桌面端：让用户选择保存位置
    final result = await FilePicker.saveFile(
      dialogTitle: S.of(context).saveCoverImage,
      fileName: fileName,
      type: FileType.image,
      allowedExtensions: ['jpg', 'jpeg', 'png'],
    );

    if (result != null) {
      final file = File(result);
      await file.writeAsBytes(bytes);
      if (mounted) {
        SnackBarUtil.showSuccess(context, S.of(context).savedToPath(result));
      }
    }
  }

  Widget _buildImage() {
    Widget imageWidget;

    if (widget.localPath != null && File(widget.localPath!).existsSync()) {
      imageWidget = Image.file(
        File(widget.localPath!),
        fit: BoxFit.contain,
        cacheWidth: 2160,
        errorBuilder: (context, error, stackTrace) {
          if (widget.imageUrl != null) {              return CachedNetworkImage(
              imageUrl: widget.imageUrl!,
              cacheKey: 'cover_${widget.imageUrl!.hashCode}',
              fit: BoxFit.contain,
              placeholder: (context, url) => const Center(
                child: CircularProgressIndicator(),
              ),
              errorWidget: (context, url, error) => const Icon(
                Icons.error,
                color: Colors.white,
                size: 48,
              ),
            );
          }
          return const Icon(
            Icons.error,
            color: Colors.white,
            size: 48,
          );
        },
      );
    } else if (widget.imageUrl != null) {
      imageWidget = CachedNetworkImage(
        imageUrl: widget.imageUrl!,
        cacheKey: 'cover_${widget.imageUrl!.hashCode}',
        fit: BoxFit.contain,
        placeholder: (context, url) => const Center(
          child: CircularProgressIndicator(),
        ),
        errorWidget: (context, url, error) => const Icon(
          Icons.error,
          color: Colors.white,
          size: 48,
        ),
      );
    } else {
      imageWidget = const Icon(
        Icons.image_not_supported,
        color: Colors.white,
        size: 48,
      );
    }

    if (widget.heroTag != null) {
      imageWidget = Hero(
        tag: widget.heroTag!,
        child: imageWidget,
      );
    }

    return imageWidget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () {
          setState(() => _showControls = !_showControls);
        },
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 图片区域
            Center(
              child: GestureDetector(
                onDoubleTap: _handleDoubleTap,
                child: InteractiveViewer(
                  transformationController: _transformController,
                  minScale: 0.5,
                  maxScale: 5.0,
                  child: _buildImage(),
                ),
              ),
            ),

            // 顶部工具栏              if (_showControls)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 4, vertical: 4),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          // 关闭按钮
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: () {
                              HapticFeedback.lightImpact();
                              Navigator.of(context).pop();
                            },
                          ),
                          // 保存按钮
                          IconButton(
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.save_alt,
                                    color: Colors.white),
                            onPressed: _isSaving
                                ? null
                                : () {
                                    HapticFeedback.lightImpact();
                                    _saveImage();
                                  },
                            tooltip: S.of(context).saveImage,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

            // 底部提示
            if (_showControls)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.5),
                        Colors.transparent,
                      ],
                    ),
                  ),
                  child: SafeArea(
                    child: Center(
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          S.of(context).doubleTapToZoom,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 12,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
