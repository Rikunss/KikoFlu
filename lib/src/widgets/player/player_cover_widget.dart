import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../models/audio_track.dart';
import '../privacy_blur_cover.dart';

/// 播放器封面组件
class PlayerCoverWidget extends StatelessWidget {
  final AudioTrack track;
  final String? workCoverUrl;
  final bool isLandscape;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeLeft;
  final VoidCallback? onSwipeRight;

  const PlayerCoverWidget({
    super.key,
    required this.track,
    this.workCoverUrl,
    this.isLandscape = false,
    this.onTap,
    this.onSwipeLeft,
    this.onSwipeRight,
  });

  // 判断是否为本地文件路径
  bool _isLocalFile(String? url) {
    if (url == null) return false;
    return url.startsWith('file://');
  }

  // 从 file:// URL 获取本地文件路径
  String _getLocalPath(String fileUrl) {
    return fileUrl.replaceFirst('file://', '');
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onHorizontalDragEnd: (details) {
        // Swipe left/right detection with velocity threshold
        const threshold = 400.0; // pixels/sec minimum velocity
        if (details.primaryVelocity == null) return;
        if (details.primaryVelocity! < -threshold) {
          HapticFeedback.lightImpact();
          onSwipeLeft?.call();
        } else if (details.primaryVelocity! > threshold) {
          HapticFeedback.lightImpact();
          onSwipeRight?.call();
        }
      },
      child: Center(
        child: Hero(
          tag: 'audio_player_artwork_${track.id}',              child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: isLandscape
                  ? MediaQuery.of(context).size.width * 0.35
                  : MediaQuery.of(context).size.width - 48,
            ),
            child: AspectRatio(
              aspectRatio: 1,
              child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: (workCoverUrl ?? track.artworkUrl) != null
                  ? PrivacyBlurCover(
                      borderRadius: BorderRadius.circular(16),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // Cover image
                            _isLocalFile(workCoverUrl ?? track.artworkUrl)
                                ? Image.file(
                                    File(_getLocalPath(
                                        (workCoverUrl ?? track.artworkUrl)!)),
                                    fit: BoxFit.cover,
                                    cacheWidth: 1080,
                                    errorBuilder: (context, error, stackTrace) {
                                      return Padding(
                                        padding: const EdgeInsets.all(40),
                                        child: Icon(
                                          Icons.album,
                                          size: isLandscape ? 80 : 120,
                                        ),
                                      );
                                    },
                                  )
                                : CachedNetworkImage(
                                    imageUrl: (workCoverUrl ?? track.artworkUrl)!,
                                    // 使用workId作为cacheKey，与作品详情页保持一致，避免token变化导致重新下载
                                    cacheKey: track.workId != null
                                        ? 'work_cover_${track.workId}'
                                        : null,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) {
                                      return Padding(
                                        padding: const EdgeInsets.all(40),
                                        child: Icon(
                                          Icons.album,
                                          size: isLandscape ? 80 : 120,
                                        ),
                                      );
                                    },
                                    placeholder: (context, url) {
                                      return Padding(
                                        padding: const EdgeInsets.all(40),
                                        child: Icon(
                                          Icons.album,
                                          size: isLandscape ? 80 : 120,
                                        ),
                                      );
                                    },
                                  ),
                            // Gradient overlay at bottom for immersive blend
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 0,
                              height: 80,
                              child: Container(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.topCenter,
                                    end: Alignment.bottomCenter,
                                    colors: [
                                      Colors.transparent,
                                      Colors.black.withValues(alpha: 0.6),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    )
                  : Padding(
                      padding: const EdgeInsets.all(40),
                      child: Icon(
                        Icons.album,
                        size: isLandscape ? 80 : 120,
                      ),
                    ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
