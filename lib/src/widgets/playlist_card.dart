import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/playlist.dart';
import '../../l10n/app_localizations.dart';
import '../providers/auth_provider.dart';
import '../services/cookie_service.dart';
import 'privacy_blur_cover.dart';

class PlaylistCard extends ConsumerWidget {
  final Playlist playlist;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;

  const PlaylistCard({
    super.key,
    required this.playlist,
    this.onTap,
    this.onDelete,
  });

  String _relativeTime(BuildContext context, String dateStr) {
    if (dateStr.isEmpty) return '';
    try {
      final date = DateTime.parse(dateStr);
      final diff = DateTime.now().difference(date);
      final s = S.of(context);
      if (diff.inMinutes < 1) return s.justNow;
      if (diff.inHours < 1) return s.minutesAgo(diff.inMinutes);
      if (diff.inDays < 1) return s.hoursAgo(diff.inHours);
      if (diff.inDays < 30) return s.daysAgo(diff.inDays);
      return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
    } catch (_) {
      return dateStr;
    }
  }

  IconData _privacyIcon(int privacy) {
    switch (privacy) {
      case 0: return Icons.lock;
      case 1: return Icons.link;
      case 2: return Icons.public;
      default: return Icons.lock;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final host = ref.watch(authProvider.select((s) => s.host ?? ''));
    final token = ref.watch(authProvider.select((s) => s.token ?? ''));
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    final httpHeaders = CookieService.coverHttpHeaders(token: token);
    final isSystem = playlist.isSystemPlaylist;
    final relativeTime = _relativeTime(context, playlist.updatedAt.isNotEmpty ? playlist.updatedAt : playlist.createdAt);
    final privacyIcon = _privacyIcon(playlist.privacy);

    return Card(
      elevation: 1,
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: InkWell(
        onTap: onTap,
        child: SizedBox(
          height: 96,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 96,
                height: 96,
                clipBehavior: Clip.antiAlias,
                decoration: const BoxDecoration(
                  borderRadius: BorderRadius.only(
                    topLeft: Radius.circular(12),
                    bottomLeft: Radius.circular(12),
                  ),
                ),
                child: PrivacyBlurCover(
                  borderRadius: BorderRadius.circular(0),
                  child: CachedNetworkImage(
                    imageUrl: playlist.getFullCoverUrl(host, token: token),
                    httpHeaders: httpHeaders,
                    cacheKey: 'playlist_cover_${playlist.id}',
                    memCacheWidth: (96 * MediaQuery.devicePixelRatioOf(context)).round(),
                    fit: BoxFit.cover,
                    placeholder: (context, url) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Center(
                        child: Icon(
                          Icons.playlist_play,
                          size: 32,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    errorWidget: (context, url, error) => Container(
                      color: colorScheme.surfaceContainerHighest,
                      child: Icon(
                        Icons.playlist_play,
                        size: 32,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),

              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              isSystem ? playlist.displayName : playlist.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w600,
                                height: 1.2,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Icon(
                              privacyIcon,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 6),

                      Row(
                        children: [
                          Icon(
                            Icons.person_outline,
                            size: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                          Flexible(
                            child: Text(
                              playlist.userName,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                fontSize: 11,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                            child: Text(
                              '•',
                              style: TextStyle(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                                fontSize: 11,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.audiotrack,
                            size: 12,
                            color: colorScheme.primary.withValues(alpha: 0.7),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${playlist.worksCount}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),

                      Row(
                        children: [
                          if (playlist.playbackCount > 0) ...[
                            Icon(
                              Icons.play_circle_outline,
                              size: 12,
                              color: colorScheme.primary.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 3),
                            Text(
                              s.nPlaysCount(playlist.playbackCount),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                                fontSize: 10,
                              ),
                            ),
                            const SizedBox(width: 8),
                          ],
                          Icon(
                            Icons.schedule,
                            size: 12,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            relativeTime,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),

                      if (playlist.description.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          playlist.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                            fontSize: 10,
                            height: 1.2,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: onDelete != null
                    ? IconButton(
                        icon: Icon(
                          Icons.delete_outline,
                          size: 20,
                          color: colorScheme.error.withValues(alpha: 0.7),
                        ),
                        onPressed: onDelete,
                        tooltip: s.delete,
                      )
                    : Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Icon(
                          Icons.chevron_right,
                          size: 20,
                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}