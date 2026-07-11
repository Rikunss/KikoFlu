import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../../providers/audio_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/playlists_provider.dart';
import '../../services/cookie_service.dart';
import '../../utils/snackbar_util.dart';
import '../../models/audio_track.dart';
import '../privacy_blur_cover.dart';
import '../../../l10n/app_localizations.dart';

/// 播放列表对话框
class PlaylistDialog extends ConsumerWidget {
  const PlaylistDialog({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queueAsync = ref.watch(queueProvider);
    final currentTrack = ref.watch(currentTrackProvider);
    final (host, token) = ref.watch(authProvider.select(
      (s) => (s.host ?? '', s.token ?? ''),
    ));
    final audioState = ref.watch(audioPlayerControllerProvider);

    // Get current queue synchronously as fallback
    final audioService = ref.read(audioPlayerServiceProvider);
    final currentQueue = audioService.queue;

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    final borderRadius = BorderRadius.circular(18);

    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: borderRadius),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
            maxWidth: MediaQuery.of(context).size.width * 0.9,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 8, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                S.of(context).playlistTitle,
                                style: tt.titleLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${currentQueue.length} ${S.of(context).nFiles(currentQueue.length)}',
                                style: tt.bodySmall?.copyWith(
                                      color: cs.onSurfaceVariant,
                                    ),
                              ),
                            ],
                          ),
                        ),
                        if (audioState.appendMode)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Text(
                              S.of(context).appendMode,
                              style: tt.bodySmall?.copyWith(
                                    color: cs.primary,
                                  ),
                            ),
                          ),
                        IconButton(
                          tooltip: audioState.appendMode ? S.of(context).appendModeStatusOn : S.of(context).appendModeStatusOff,
                          icon: Icon(
                            Icons.playlist_add,
                            color: audioState.appendMode
                                ? cs.primary
                                : null,
                          ),
                          onPressed: () async {
                            final notifier =
                                ref.read(audioPlayerControllerProvider.notifier);
                            final shouldShowHint = notifier.toggleAppendMode();
                            if (shouldShowHint && context.mounted) {
                              await _showAppendHintDialog(context);
                            }
                          },
                        ),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.of(context).pop(),
                        ),
                      ],
                    ),
                    if (currentQueue.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4, bottom: 4),
                        child: Row(
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.playlist_remove, size: 18),
                              label: Text(S.of(context).clearQueue),
                              style: TextButton.styleFrom(
                                foregroundColor: cs.error,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () async {
                                final confirmed = await showDialog<bool>(
                                  context: context,
                                  builder: (ctx) => AlertDialog(
                                    title: Text(S.of(context).clearQueue),
                                    content: Text(S.of(context).clearQueueConfirm),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(false),
                                        child: Text(S.of(context).cancel),
                                      ),
                                      TextButton(
                                        onPressed: () => Navigator.of(ctx).pop(true),
                                        child: Text(S.of(context).delete),
                                      ),
                                    ],
                                  ),
                                );
                                if (confirmed == true && context.mounted) {
                                  await ref
                                      .read(audioPlayerControllerProvider.notifier)
                                      .clearQueue();
                                  if (context.mounted) {
                                    Navigator.of(context).pop();
                                  }
                                }
                              },
                            ),
                            TextButton.icon(
                              icon: const Icon(Icons.save_outlined, size: 18),
                              label: Text(S.of(context).saveAsPlaylist),
                              style: TextButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                visualDensity: VisualDensity.compact,
                              ),
                              onPressed: () => _saveQueueAsPlaylist(context, ref, currentQueue),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Playlist
              Expanded(
                child: Builder(
                  builder: (context) {
                    final tracks = queueAsync.valueOrNull ?? currentQueue;

                    if (tracks.isEmpty) {
                      return Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Text(S.of(context).playlistEmpty),
                        ),
                      );
                    }

                    return ReorderableListView.builder(
                      padding: EdgeInsets.zero,
                      itemCount: tracks.length,
                      buildDefaultDragHandles: false,
                      onReorderItem: (oldIndex, newIndex) {
                        ref
                            .read(audioPlayerControllerProvider.notifier)
                            .moveTrack(oldIndex, newIndex);
                      },
                      itemBuilder: (context, index) {
                        final track = tracks[index];
                        final isCurrentTrack =
                            currentTrack.valueOrNull?.id == track.id;

                        // Build work cover URL（优先使用本地文件）
                        String? workCoverUrl;
                        // 优先使用 track.artworkUrl（可能是本地文件 file://）
                        if (track.artworkUrl != null &&
                            track.artworkUrl!.startsWith('file://')) {
                          workCoverUrl = track.artworkUrl;
                        } else if (track.workId != null) {
                          if (host.isNotEmpty) {
                            var normalizedHost = host;
                            if (!normalizedHost.startsWith('http://') &&
                                !normalizedHost.startsWith('https://')) {
                              normalizedHost = 'https://$normalizedHost';
                            }
                            workCoverUrl = token.isNotEmpty
                                ? '$normalizedHost/api/cover/${track.workId}?token=$token'
                                : '$normalizedHost/api/cover/${track.workId}';
                          }
                        }

                        final resolvedCover = workCoverUrl ?? track.artworkUrl;

                        return LayoutBuilder(
                          key: ValueKey(track.id),
                          builder: (context, constraints) {
                            final isCompact = constraints.maxWidth < 480;
                            final actionButtons = Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isCurrentTrack)
                                  Icon(
                                    Icons.music_note,
                                    color:
                                        cs.primary,
                                    size: 18,
                                  ),
                                IconButton(
                                  tooltip: S.of(context).remove,
                                  icon: const Icon(Icons.delete_outline,
                                      size: 20),
                                  onPressed: () {
                                    ref
                                        .read(audioPlayerControllerProvider
                                            .notifier)
                                        .removeTrackAt(index);
                                  },
                                ),
                                ReorderableDragStartListener(
                                  index: index,
                                  child: const Padding(
                                    padding:
                                        EdgeInsets.symmetric(horizontal: 4),
                                    child: Icon(Icons.drag_handle, size: 20),
                                  ),
                                ),
                              ],
                            );

                            return InkWell(
                              onTap: () async {
                                await ref
                                    .read(
                                        audioPlayerControllerProvider.notifier)
                                    .skipToIndex(index);
                                if (context.mounted) {
                                  Navigator.of(context).pop();
                                }
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  gradient: isCurrentTrack
                                      ? LinearGradient(
                                          colors: [
                                            cs.primaryContainer
                                                .withValues(alpha: 0.4),
                                            cs.primaryContainer
                                                .withValues(alpha: 0.2),
                                          ],
                                          begin: Alignment.topLeft,
                                          end: Alignment.bottomRight,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(6),
                                        color: cs.surfaceContainerHighest,
                                      ),
                                      child: resolvedCover != null
                                          ? PrivacyBlurCover(
                                              borderRadius:
                                                  BorderRadius.circular(6),
                                              child: ClipRRect(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                child: resolvedCover
                                                        .startsWith('file://')
                                                    ? Image.file(
                                                        File(resolvedCover
                                                            .replaceFirst(
                                                                'file://', '')),
                                                        fit: BoxFit.cover,
                                                        cacheWidth: 144,
                                                        cacheHeight: 144,
                                                        errorBuilder: (context,
                                                            error, stackTrace) {
                                                          return const Icon(
                                                              Icons.music_note,
                                                              size: 24);
                                                        },
                                                      )
                                                    : CachedNetworkImage(
                                                        imageUrl: resolvedCover,
                                                        httpHeaders: CookieService.coverHttpHeaders(token: token),
                                                        cacheKey: track.workId != null
                                                            ? 'work_cover_${track.workId}'
                                                            : null,
                                                        fit: BoxFit.cover,
                                                        errorWidget: (context,
                                                            url, error) {
                                                          return const Icon(
                                                              Icons.music_note,
                                                              size: 24);
                                                        },
                                                        placeholder:
                                                            (context, url) =>
                                                                const Center(
                                                          child:
                                                              CircularProgressIndicator(),
                                                        ),
                                                      ),
                                              ),
                                            )
                                          : const Icon(Icons.music_note,
                                              size: 24),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Row(
                                            crossAxisAlignment:
                                                CrossAxisAlignment.start,
                                            children: [
                                              Expanded(
                                                child: Text(
                                                  track.title,
                                                  style: TextStyle(
                                                    fontWeight: isCurrentTrack
                                                        ? FontWeight.bold
                                                        : FontWeight.normal,
                                                    color: isCurrentTrack
                                                        ? cs.primary
                                                        : null,
                                                  ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                              ),
                                              if (!isCompact)
                                                Padding(
                                                  padding:
                                                      const EdgeInsets.only(
                                                          bottom: 4),
                                                  child: actionButtons,
                                                ),
                                            ],
                                          ),
                                          if (track.artist != null)
                                            Padding(
                                              padding:
                                                  const EdgeInsets.only(top: 2),
                                              child: Text(
                                                track.artist!,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  color: isCurrentTrack
                                                      ? cs.primary
                                                      : tt.bodySmall?.color,
                                                ),
                                              ),
                                            ),
                                          if (isCompact)
                                            Align(
                                              alignment: Alignment.centerRight,
                                              child: Padding(
                                                padding: const EdgeInsets.only(
                                                    top: 2),
                                                child: actionButtons,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 显示播放列表对话框
  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => const PlaylistDialog(),
    );
  }

  Future<void> _showAppendHintDialog(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).appendModeEnabled),
        content: Text(
          S.of(context).appendModeHint,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).gotIt),
          ),
        ],
      ),
    );
  }

  Future<void> _saveQueueAsPlaylist(
      BuildContext context, WidgetRef ref, List<AudioTrack> tracks) async {
    if (tracks.isEmpty) {
      if (context.mounted) {
        SnackBarUtil.showError(context, S.of(context).noWorks);
      }
      return;
    }

    final nameController = TextEditingController();

    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).saveAsPlaylist),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: S.of(context).newPlaylistNameHint,
            labelText: S.of(context).playlistName,
          ),
          onSubmitted: (value) => Navigator.of(ctx).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              final text = nameController.text.trim();
              if (text.isNotEmpty) {
                Navigator.of(ctx).pop(text);
              }
            },
            child: Text(S.of(context).create),
          ),
        ],
      ),
    );

    nameController.dispose();

    if (name == null || name.isEmpty || !context.mounted) return;

    try {
      await ref
          .read(audioPlayerControllerProvider.notifier)
          .saveQueueAsPlaylist(name: name);
      if (context.mounted) {
        ref.invalidate(playlistsProvider);
        SnackBarUtil.showSuccess(
          context,
          S.of(context).playlistCreatedSuccess(name),
        );
      }
    } catch (e) {
      if (context.mounted) {
        SnackBarUtil.showError(
          context,
          S.of(context).createFailedWithError(e.toString()),
        );
      }
    }
  }
}
