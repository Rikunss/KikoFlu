import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../services/log_service.dart';
import 'blur_hash_widget.dart';
import '../models/history_record.dart';
import '../models/audio_track.dart';
import '../models/download_task.dart';
import '../providers/auth_provider.dart';
import '../providers/history_provider.dart';
import '../services/audio_player_service.dart';
import '../services/download_service.dart';
import '../services/cache_service.dart';
import '../screens/work_detail_screen.dart';
import '../services/storage_service.dart';
import '../services/blurhash_service.dart';
import '../utils/string_utils.dart';
import '../providers/lyric_provider.dart';
import '../utils/snackbar_util.dart';
import '../../l10n/app_localizations.dart';
import 'add_to_playlist_dialog.dart';
import 'privacy_blur_cover.dart';

/// Helper untuk membangun cover placeholder dengan dukungan BlurHash
Widget _buildCoverPlaceholder(BuildContext context, String? blurHash) {
  if (blurHash != null && blurHash.isNotEmpty) {
    return BlurHashWidget(
      hash: blurHash,
      imageFit: BoxFit.cover,
    );
  }
  return Container(
    color: Colors.grey[200],
    child: const Center(
      child: Icon(Icons.image, color: Colors.grey),
    ),
  );
}

class HistoryWorkCard extends ConsumerWidget {
  final HistoryRecord record;
  final VoidCallback? onTap;

  const HistoryWorkCard({
    super.key,
    required this.record,
    this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Gunakan select() agar kartu tidak rebuild saat field auth lain berubah
    final host = ref.watch(authProvider.select((s) => s.host ?? ''));
    final token = ref.watch(authProvider.select((s) => s.token ?? ''));
    final work = record.work;

    final cs = Theme.of(context).colorScheme;

    final httpHeaders = StorageService.serverCookieHeaders;

    return Card(
      clipBehavior: Clip.antiAlias,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(work: work),
            ),
          );
        },
        onLongPress: () => _showContextMenu(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Cover
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: 'work_cover_${work.id}',
                    child: Material(
                      color: Colors.transparent,
                      child: PrivacyBlurCover(
                        child: CachedNetworkImage(
                          imageUrl: work.getCoverImageUrl(host, token: token),
                          httpHeaders: httpHeaders,
                          cacheKey: 'work_cover_${work.id}',
                          memCacheWidth: (210 * MediaQuery.devicePixelRatioOf(context)).round(),
                          fit: BoxFit.cover,
                          placeholder: (context, url) => _buildCoverPlaceholder(
                            context,
                            work.blurHash ??
                                BlurHashService.instance.getBlurHash(work.id),
                          ),
                          errorWidget: (context, url, error) => _buildCoverPlaceholder(
                            context,
                            work.blurHash ??
                                BlurHashService.instance.getBlurHash(work.id),
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Gradient
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      height: 60,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.transparent,
                            Colors.black.withValues(alpha: 0.7),
                          ],
                        ),
                      ),
                    ),
                  ),
                  // Play Button
                  if (record.lastTrack != null)
                    Positioned(
                      right: 8,
                      bottom: 8,
                      child: Material(
                        color: cs.primary,
                        shape: const CircleBorder(),
                        elevation: 4,
                        child: InkWell(
                          customBorder: const CircleBorder(),
                          onTap: () => _resumePlayback(context, ref),
                          child: Padding(
                            padding: const EdgeInsets.all(10.0),
                            child: Icon(
                              Icons.play_arrow,
                              size: 24,
                              color: cs.onPrimary,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            // Info
            Container(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    work.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (record.lastTrack != null)
                    Builder(
                      builder: (context) {
                        final lastTrack = record.lastTrack!;
                        final int? trackDurationMs =
                            lastTrack.duration?.inMilliseconds;
                        final double progressValue =
                            trackDurationMs != null && trackDurationMs > 0
                                ? (record.lastPositionMs / trackDurationMs)
                                    .clamp(0.0, 1.0)
                                : 0.0;

                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              lastTrack.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.secondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  '${formatDuration(Duration(milliseconds: record.lastPositionMs))} / ${formatDuration(lastTrack.duration ?? Duration.zero)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w500,
                                    color:
                                        cs.primary,
                                  ),
                                ),
                                if (record.playlistTotal > 0)
                                  Text(
                                    '${record.playlistIndex + 1} / ${record.playlistTotal}',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color:
                                          cs.outline,
                                    ),
                                  ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            LinearProgressIndicator(
                              value: progressValue,
                              backgroundColor: cs.surfaceContainerHighest,
                              color: cs.primary,
                              minHeight: 3,
                              borderRadius: BorderRadius.circular(1.5),
                            ),
                          ],
                        );
                      },
                    )
                  else
                    Text(
                      S.of(context).notPlayedYet,
                      style: TextStyle(
                        fontSize: 11,
                        color: cs.outline,
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build AudioTrack list for the work. Returns null on failure.
  static Future<List<AudioTrack>?> _buildTracks({
    required HistoryRecord record,
    required BuildContext context,
    required WidgetRef ref,
  }) async {
    final work = record.work;
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final s = S.of(context);

    final apiService = ref.read(kikoeruApiServiceProvider);
    List<dynamic> allFiles = [];
    try {
      allFiles = await apiService.getWorkTracks(work.id);
      ref.read(fileListControllerProvider.notifier).updateFiles(allFiles);
    } catch (e) {
      LogService.instance.warning('Failed to update file list: $e', tag: 'Playback');
      try {
        final tasks = await DownloadService.instance.getWorkTasks(work.id);
        if (tasks.isNotEmpty) {
          final downloadedFiles = tasks
              .where((t) => t.status == DownloadStatus.completed)
              .map((t) => ({
                    'title': t.fileName,
                    'name': t.fileName,
                    'hash': t.hash,
                    'type': 'file',
                  }))
              .toList();
          if (downloadedFiles.isNotEmpty) {
            allFiles = downloadedFiles;
            ref.read(fileListControllerProvider.notifier).updateFiles(allFiles);
          }
        }
      } catch (e2) {
        LogService.instance.warning('Failed to load downloaded files: $e2', tag: 'Playback');
      }
    }

    if (allFiles.isEmpty) return null;

    // Helper: check if a file matches the last track
    bool isTargetFile(dynamic file, HistoryRecord rec) {
      if (file['type'] == 'folder') return false;
      final fileHash = file['hash'];
      final fileName = file['title'] ?? file['name'];
      if (rec.lastTrack?.hash != null && fileHash == rec.lastTrack!.hash) return true;
      return fileName == rec.lastTrack?.title;
    }

    // Helper: extract audio files from a list
    List<dynamic> extractAudioFiles(List<dynamic> list) {
      return list.where((file) {
        if (file['type'] == 'folder') return false;
        final name = file['title'] ?? file['name'] ?? '';
        final ext = name.split('.').last.toLowerCase();
        return ['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].contains(ext);
      }).toList();
    }

    // Find sibling audio files of the last track
    List<dynamic> findSiblingAudioFiles(List<dynamic> files, HistoryRecord rec) {
      for (final file in files) {
        if (file['type'] == 'folder') {
          if (file['children'] != null) {
            final children = file['children'] as List<dynamic>;
            if (children.any((f) => isTargetFile(f, rec))) {
              return extractAudioFiles(children);
            }
            final result = findSiblingAudioFiles(children, rec);
            if (result.isNotEmpty) return result;
          }
        } else {
          if (isTargetFile(file, rec)) {
            return extractAudioFiles(files);
          }
        }
      }
      return [];
    }

    List<dynamic> audioFiles = findSiblingAudioFiles(allFiles, record);

    // Fallback: flatten all audio files
    if (audioFiles.isEmpty) {
      List<dynamic> flatten(List<dynamic> files) {
        final result = <dynamic>[];
        for (final file in files) {
          if (file['type'] == 'folder' && file['children'] != null) {
            result.addAll(flatten(file['children']));
          } else {
            final name = file['title'] ?? file['name'] ?? '';
            final ext = name.split('.').last.toLowerCase();
            if (['mp3', 'wav', 'flac', 'm4a', 'aac', 'ogg'].contains(ext)) {
              result.add(file);
            }
          }
        }
        return result;
      }
      audioFiles = flatten(allFiles);
    }

    // Build AudioTracks
    final List<AudioTrack> tracks = [];
    final downloadService = DownloadService.instance;

    String? coverUrl;
    if (host.isNotEmpty) {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        normalizedUrl = 'https://$host';
      }
      coverUrl = token.isNotEmpty
          ? '$normalizedUrl/api/cover/${work.id}?token=$token'
          : '$normalizedUrl/api/cover/${work.id}';
    }

    for (final file in audioFiles) {
      final fileHash = file['hash'];
      final fileTitle = file['title'] ?? file['name'] ?? s.unknown;
      String audioUrl = '';

      if (fileHash != null) {
        final localPath = await downloadService.getDownloadedFilePath(work.id, fileHash);
        if (localPath != null) {
          audioUrl = 'file://$localPath';
        } else {
          final cachedPath = await CacheService.getCachedAudioFile(fileHash);
          if (cachedPath != null) {
            audioUrl = 'file://$cachedPath';
          }
        }
      }

      if (audioUrl.isEmpty) {
        if (file['mediaDownloadUrl'] != null &&
            file['mediaDownloadUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaDownloadUrl'];
        } else if (file['mediaStreamUrl'] != null &&
            file['mediaStreamUrl'].toString().isNotEmpty) {
          audioUrl = file['mediaStreamUrl'];
        } else if (host.isNotEmpty && fileHash != null) {
          String normalizedUrl = host;
          if (!host.startsWith('http://') && !host.startsWith('https://')) {
            normalizedUrl = 'https://$host';
          }
          audioUrl = '$normalizedUrl/api/media/stream/$fileHash?token=$token';
        }
      }

      if (audioUrl.isNotEmpty) {
        final vaNames = work.vas?.map((va) => va.name).toList() ?? [];
        final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;
        tracks.add(AudioTrack(
          id: fileHash ?? fileTitle,
          url: audioUrl,
          title: fileTitle,
          artist: artistInfo,
          album: work.title,
          artworkUrl: coverUrl,
          duration: file['duration'] != null
              ? Duration(milliseconds: (file['duration'] * 1000).round())
              : null,
          workId: work.id,
          hash: fileHash,
        ));
      }
    }

    if (tracks.isEmpty && record.lastTrack != null) {
      tracks.add(record.lastTrack!);
    }

    return tracks.isNotEmpty ? tracks : null;
  }

  /// Resume playback from where the user left off.
  Future<void> _resumePlayback(BuildContext context, WidgetRef ref) async {
    final work = record.work;
    final s = S.of(context);

    final tracks = await _buildTracks(record: record, context: context, ref: ref);

    if (tracks == null) {
      // Fallback to single track
      if (record.lastTrack != null) {
        try {
          await AudioPlayerService.instance.updateQueue([record.lastTrack!]);
          await AudioPlayerService.instance
              .seek(Duration(milliseconds: record.lastPositionMs));
          await AudioPlayerService.instance.play();
          ref.read(historyProvider.notifier).addOrUpdate(work);
        } catch (e) {
          LogService.instance.error('Failed to resume playback: $e', tag: 'Playback');
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(S.of(context).playbackFailed(e.toString()))),
          );
        }
      }
      return;
    }

    // Find index
    final lastTrackId = record.lastTrack?.id;
    int index = 0;
    if (lastTrackId != null) {
      index = tracks.indexWhere((t) => t.id == lastTrackId);
      if (index == -1) {
        index = tracks.indexWhere((t) => t.title == record.lastTrack!.title);
      }
      if (index == -1) index = 0;
    }

    if (tracks.isNotEmpty) {
      try {
        await AudioPlayerService.instance.updateQueue(tracks, startIndex: index);
        await AudioPlayerService.instance
            .seek(Duration(milliseconds: record.lastPositionMs));
        await AudioPlayerService.instance.play();
        ref.read(historyProvider.notifier).addOrUpdate(work);
      } catch (e) {
        LogService.instance.error('Failed to resume playback: $e', tag: 'Playback');
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).playbackFailed(e.toString()))),
        );
      }
    }
  }

  /// Show context menu on long press.
  void _showContextMenu(BuildContext context, WidgetRef ref) {
    HapticFeedback.mediumImpact();
    final s = S.of(context);
    final work = record.work;

    showModalBottomSheet<Map<String, String>>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                work.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              leading: Icon(Icons.playlist_play, color: Theme.of(context).colorScheme.primary),
              title: Text(s.playNext),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, {'action': 'play_next'}),
            ),
            ListTile(
              leading: Icon(Icons.playlist_add, color: Theme.of(context).colorScheme.primary),
              title: Text(s.addToPlaylist),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.pop(ctx, {'action': 'add_to_playlist'}),
            ),
            ListTile(
              leading: Icon(Icons.delete_outline, color: Theme.of(context).colorScheme.error),
              title: Text(s.deleteRecord, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              trailing: Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.error),
              onTap: () => Navigator.pop(ctx, {'action': 'delete_record'}),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    ).then((result) {
      if (result == null || !context.mounted) return;

      switch (result['action']) {
        case 'play_next':
          _handlePlayNext(context, ref);
          break;
        case 'add_to_playlist':
          AddToPlaylistDialog.show(
            context: context,
            workId: work.id,
            workTitle: work.title,
          );
          break;
        case 'delete_record':
          _showDeleteConfirm(context, ref);
          break;
      }
    });
  }

  /// Handle "Play Next" from context menu.
  Future<void> _handlePlayNext(BuildContext context, WidgetRef ref) async {
    final s = S.of(context);

    final tracks = await _buildTracks(record: record, context: context, ref: ref);

    if (tracks == null) {
      if (context.mounted) {
        SnackBarUtil.showWarning(context, s.noAudioTracks);
      }
      return;
    }

    try {
      await AudioPlayerService.instance.insertTracksAfterCurrent(tracks);
      if (context.mounted) {
        SnackBarUtil.showSuccess(context, s.playingNextTracks(tracks.length));
      }
    } catch (e) {
      LogService.instance.error('Play Next failed: $e', tag: 'Playback');
      if (context.mounted) {
        SnackBarUtil.showError(context, s.playbackFailed(e.toString()));
      }
    }
  }

  /// Show delete confirmation dialog.
  void _showDeleteConfirm(BuildContext context, WidgetRef ref) {
    final work = record.work;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).deleteRecord),
        content: Text(S.of(context).deletePlayRecordConfirm(work.title)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).cancel),
          ),
          TextButton(
            onPressed: () {
              ref.read(historyProvider.notifier).remove(work.id);
              Navigator.pop(ctx);
            },
            child: Text(S.of(context).delete),
          ),
        ],
      ),
    );
  }
}
