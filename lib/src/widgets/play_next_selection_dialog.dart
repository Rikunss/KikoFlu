import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../models/audio_track.dart';
import '../models/work.dart' show AudioFile, Work;
import '../services/audio_player_service.dart' show AudioPlayerService;
import '../services/cache_service.dart' show CacheService;
import '../services/download_service.dart' show DownloadService;
import '../services/log_service.dart' show LogService;
import '../utils/snackbar_util.dart' show SnackBarUtil;
import 'file_tree_selector.dart';

/// Dialog for selecting which audio files to play next from a work.
/// Shows a file tree with checkboxes, similar to [FileSelectionDialog].
class PlayNextSelectionDialog extends StatefulWidget {
  final String workTitle;
  final List<AudioFile> audioFiles;
  final String? coverUrl;
  final String? artistInfo;
  final int workId;
  final String host;
  final String token;

  const PlayNextSelectionDialog({
    super.key,
    required this.workTitle,
    required this.audioFiles,
    this.coverUrl,
    this.artistInfo,
    required this.workId,
    required this.host,
    required this.token,
  });

  /// Show the dialog and let user select tracks. Returns selected [AudioFile]s,
  /// which the caller should then convert to [AudioTrack]s and queue.
  static Future<List<AudioFile>?> show({
    required BuildContext context,
    required Work work,
    required List<AudioFile> audioFiles,
    required String host,
    required String token,
  }) {
    String? coverUrl;
    if (host.isNotEmpty) {
      String normalizedUrl = host;
      if (!host.startsWith('http://') && !host.startsWith('https://')) {
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedUrl = 'http://$host';
        } else {
          normalizedUrl = 'https://$host';
        }
      }
      coverUrl = token.isNotEmpty
          ? '$normalizedUrl/api/cover/${work.id}?token=$token'
          : '$normalizedUrl/api/cover/${work.id}';
    }

    final vaNames = work.vas?.map((va) => va.name).toList() ?? [];
    final artistInfo = vaNames.isNotEmpty ? vaNames.join(', ') : null;

    return showDialog<List<AudioFile>>(
      context: context,
      builder: (ctx) => PlayNextSelectionDialog(
        workTitle: work.title,
        audioFiles: audioFiles,
        coverUrl: coverUrl,
        artistInfo: artistInfo,
        workId: work.id,
        host: host,
        token: token,
      ),
    );
  }

  @override
  State<PlayNextSelectionDialog> createState() =>
      _PlayNextSelectionDialogState();
}

class _PlayNextSelectionDialogState extends State<PlayNextSelectionDialog> {
  final _treeKey = GlobalKey<FileTreeSelectorState>();

  Future<void> _playSelected() async {
    final selected = _treeKey.currentState?.getSelectedFiles();
    if (selected == null || selected.isEmpty) return;

    final downloadService = DownloadService.instance;
    final tracks = <AudioTrack>[];

    for (final file in selected) {
      final fileHash = file.hash;
      final fileTitle = file.title;

      String audioUrl = '';
      if (fileHash != null) {
        final localPath =
            await downloadService.getDownloadedFilePath(widget.workId, fileHash);
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
        if (file.mediaDownloadUrl != null &&
            file.mediaDownloadUrl!.isNotEmpty) {
          audioUrl = file.mediaDownloadUrl!;
        } else if (widget.host.isNotEmpty && fileHash != null) {
          String normalizedUrl = widget.host;
          if (!widget.host.startsWith('http://') &&
              !widget.host.startsWith('https://')) {
            if (widget.host.contains('localhost') ||
                widget.host.startsWith('127.0.0.1') ||
                widget.host.startsWith('192.168.')) {
              normalizedUrl = 'http://${widget.host}';
            } else {
              normalizedUrl = 'https://${widget.host}';
            }
          }
          audioUrl =
              '$normalizedUrl/api/media/stream/$fileHash?token=${widget.token}';
        }
      }

      if (audioUrl.isNotEmpty) {
        tracks.add(AudioTrack(
          id: fileHash ?? fileTitle,
          url: audioUrl,
          title: fileTitle,
          artist: widget.artistInfo,
          album: widget.workTitle,
          artworkUrl: widget.coverUrl,
          duration: file.duration != null
              ? Duration(milliseconds: (file.duration! * 1000).round())
              : null,
          workId: widget.workId,
          hash: fileHash,
        ));
      }
    }

    if (tracks.isEmpty) return;

    try {
      await AudioPlayerService.instance.insertTracksAfterCurrent(tracks);
      if (mounted) {
        SnackBarUtil.showSuccess(
            context, S.of(context).playingNextTracks(tracks.length));
        Navigator.of(context).pop();
      }
    } catch (e) {
      LogService.instance.error('Play Next failed: $e', tag: 'Playback');
      if (mounted) {
        SnackBarUtil.showError(
            context, S.of(context).playbackFailed(e.toString()));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = S.of(context);
    final cs = theme.colorScheme;
    final selectedCount = _treeKey.currentState?.selectedCount ?? widget.audioFiles.length;

    return Dialog(
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.8,
          maxWidth: 500,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.secondaryContainer,
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Row(
                children: [
                  Icon(Icons.playlist_play, color: cs.onSecondaryContainer),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          s.playNext,
                          style: theme.textTheme.titleLarge?.copyWith(
                            color: cs.onSecondaryContainer,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          widget.workTitle,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer.withAlpha(179),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                    color: cs.onSecondaryContainer,
                  ),
                ],
              ),
            ),

            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: theme.dividerColor)),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.select_all, size: 18),
                    label: Text(s.selectAll),
                    onPressed: () {
                      HapticFeedback.lightImpact();
                      _treeKey.currentState?.toggleSelectAll();
                    },
                  ),
                  const Spacer(),
                  Text(
                    s.selectedNCount(selectedCount),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurface.withAlpha(153),
                    ),
                  ),
                ],
              ),
            ),

            Flexible(
              child: widget.audioFiles.isEmpty
                  ? _buildEmptyState(context)
                  : FileTreeSelector(
                      key: _treeKey,
                      files: widget.audioFiles,
                      preSelectAll: true,
                      onSelectionChanged: () => setState(() {}),
                    ),
            ),

            const Divider(height: 1),

            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: Text(s.cancel),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: selectedCount > 0
                        ? () {
                            HapticFeedback.lightImpact();
                            _playSelected();
                          }
                        : null,
                    icon: const Icon(Icons.playlist_play),
                    label: Text('${s.playNext} ($selectedCount)'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.audiotrack, size: 32, color: cs.primary),
            ),
            const SizedBox(height: 16),
            Text(
              S.of(context).noPlayableAudioFiles,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
            ),
          ],
        ),
      ),
    );
  }
}