import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../models/work.dart';
import '../../models/audio_track.dart';
import '../../providers/auth_provider.dart';
import '../../providers/audio_provider.dart';
import '../../services/download_service.dart';
import '../../services/cache_service.dart';
import '../../services/log_service.dart';
import '../../utils/file_icon_utils.dart';
import '../va_chip.dart';
import '../tag_chip.dart';
import '../../../l10n/app_localizations.dart';

/// Shows a slide-up work info panel with track list picker.
/// Call this from the fullscreen player to let users browse work details
/// and pick individual audio tracks.
Future<void> showWorkInfoPanel(
  BuildContext context,
  WidgetRef ref,
  AudioTrack currentTrack,
) async {
  // Fetch the full work data
  final Work? work = await _fetchWork(ref, currentTrack.workId);
  if (!context.mounted || work == null) return;

  // Fetch tracks (file tree)
  final List<dynamic> workTracks = await _fetchWorkTracks(ref, currentTrack.workId);
  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (context) => _WorkInfoPanel(
      work: work,
      currentTrack: currentTrack,
      workTracks: workTracks,
    ),
  );
}

Future<Work?> _fetchWork(WidgetRef ref, int? workId) async {
  if (workId == null) return null;
  try {
    final api = ref.read(kikoeruApiServiceProvider);
    final data = await api.getWork(workId);
    return Work.fromJson(data);
  } catch (e) {
    LogService.instance.warning('[WorkInfoPanel] Failed to fetch work $workId: $e', tag: 'UI');
    return null;
  }
}

Future<List<dynamic>> _fetchWorkTracks(WidgetRef ref, int? workId) async {
  if (workId == null) return [];
  try {
    final api = ref.read(kikoeruApiServiceProvider);
    return await api.getWorkTracks(workId);
  } catch (e) {
    LogService.instance.warning('[WorkInfoPanel] Failed to fetch tracks $workId: $e', tag: 'UI');
    return [];
  }
}

/// Flatten audio files from a nested file tree into a single list.
List<Map<String, dynamic>> _flattenAudioFiles(List<dynamic> items) {
  final result = <Map<String, dynamic>>[];
  void walk(List<dynamic> list) {
    for (final item in list) {
      final type = item is Map ? (item['type'] ?? '') : '';
      final children = item is Map ? (item['children'] as List<dynamic>?) : null;
      if (type == 'folder' && children != null) {
        walk(children);
      } else if (FileIconUtils.isAudioFile(item)) {
        result.add(Map<String, dynamic>.from(item as Map));
      }
    }
  }
  walk(items);
  return result;
}

/// Builds a playable [AudioTrack] from a raw API file map.
Future<AudioTrack> _buildTrack(
  Map<String, dynamic> file,
  Work work,
  String host,
  String token,
  String? coverUrl,
  DownloadService downloadService,
) async {
  final hash = file['hash'] as String?;
  final title = file['title'] as String? ?? file['name'] as String? ?? 'Unknown';
  final vaNames = work.vas?.map((v) => v.name).toList() ?? [];
  final artist = vaNames.isNotEmpty ? vaNames.join(', ') : null;

  String audioUrl = '';

  // 1. Local download
  if (hash != null) {
    final localPath = await downloadService.getDownloadedFilePath(work.id, hash);
    if (localPath != null) {
      audioUrl = 'file://$localPath';
    }
  }

  // 2. Cache
  if (audioUrl.isEmpty && hash != null) {
    final cachedPath = await CacheService.getCachedAudioFile(hash);
    if (cachedPath != null) {
      audioUrl = 'file://$cachedPath';
    }
  }

  // 3. Network
  if (audioUrl.isEmpty) {
    var mediaUrl = file['mediaDownloadUrl'] as String? ?? '';
    if (mediaUrl.isEmpty) {
      mediaUrl = file['mediaStreamUrl'] as String? ?? '';
    }
    if (mediaUrl.isNotEmpty) {
      audioUrl = mediaUrl;
      if (audioUrl.startsWith('/') && host.isNotEmpty) {
        final normalized = _normalizeHost(host);
        audioUrl = '$normalized$audioUrl';
      }
      if (token.isNotEmpty && !audioUrl.contains('token=')) {
        audioUrl += audioUrl.contains('?') ? '&token=$token' : '?token=$token';
      }
    } else if (host.isNotEmpty && hash != null) {
      final normalized = _normalizeHost(host);
      audioUrl = '$normalized/api/media/stream/$hash?token=$token';
    }
  }

  return AudioTrack(
    id: hash ?? title,
    url: audioUrl,
    title: title,
    artist: artist,
    album: work.title,
    artworkUrl: coverUrl,
    duration: file['duration'] != null
        ? Duration(milliseconds: (file['duration'] * 1000).round())
        : null,
    workId: work.id,
    hash: hash,
  );
}

String _normalizeHost(String host) {
  if (host.startsWith('http://') || host.startsWith('https://')) return host;
  if (host.contains('localhost') || host.startsWith('127.0.0.1') || host.startsWith('192.168.')) {
    return 'http://$host';
  }
  return 'https://$host';
}

/// Build cover URL for a work.
String? _buildCoverUrl(String host, String token, int? workId) {
  if (host.isEmpty || workId == null) return null;
  final normalized = _normalizeHost(host);
  return token.isNotEmpty
      ? '$normalized/api/cover/$workId?token=$token'
      : '$normalized/api/cover/$workId';
}

// ======================================================================
// Work Info Panel StatefulWidget
// ======================================================================

class _WorkInfoPanel extends ConsumerStatefulWidget {
  final Work work;
  final AudioTrack currentTrack;
  final List<dynamic> workTracks;

  const _WorkInfoPanel({
    required this.work,
    required this.currentTrack,
    required this.workTracks,
  });

  @override
  ConsumerState<_WorkInfoPanel> createState() => _WorkInfoPanelState();
}

class _WorkInfoPanelState extends ConsumerState<_WorkInfoPanel> {
  late Future<List<AudioTrack>> _tracksFuture;
  List<AudioTrack>? _cachedTracks;
  bool _showFullDescription = false;

  @override
  void initState() {
    super.initState();
    _tracksFuture = _buildTrackList().then((t) { _cachedTracks = t; return t; });
  }

  Future<List<AudioTrack>> _buildTrackList() async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final downloadService = DownloadService.instance;
    final coverUrl = _buildCoverUrl(host, token, widget.work.id);

    final flatFiles = _flattenAudioFiles(widget.workTracks);
    final tracks = <AudioTrack>[];
    for (final file in flatFiles) {
      final track = await _buildTrack(file, widget.work, host, token, coverUrl, downloadService);
      if (track.url.isNotEmpty) {
        tracks.add(track);
      }
    }
    return tracks;
  }

  Future<void> _playTrack(AudioTrack track) async {
    final tracks = _cachedTracks ?? await _buildTrackList();
    final startIndex = tracks.indexWhere((t) => t.id == track.id);
    if (startIndex >= 0) {
      if (mounted) {
        Navigator.pop(context); // close the panel
      }
      ref.read(audioPlayerControllerProvider.notifier).playTracks(
        tracks,
        startIndex: startIndex,
        work: widget.work,
      );
    }
  }

  String _formatDuration(int? seconds) {
    if (seconds == null || seconds <= 0) return '';
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    if (h > 0) return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  IconData _formatFileIcon(String title) {
    return Icons.audiotrack;
  }

  Color _formatColor(String title) {
    final lower = title.toLowerCase();
    if (lower.endsWith('.flac')) return const Color(0xFF7C3AED);
    if (lower.endsWith('.wav')) return const Color(0xFF2563EB);
    if (lower.endsWith('.mp3')) return const Color(0xFFEA580C);
    if (lower.endsWith('.m4a') || lower.endsWith('.aac')) return const Color(0xFF0D9488);
    return Colors.grey;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cs = Theme.of(context).colorScheme;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    return DraggableScrollableSheet(
      initialChildSize: isLandscape ? 0.85 : 0.65,
      maxChildSize: isLandscape ? 0.92 : 0.85,
      minChildSize: 0.3,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: cs.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.2),
                blurRadius: 20,
                offset: const Offset(0, -4),
              ),
            ],
          ),
          child: Column(
            children: [
              // Drag handle
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Row(
                  children: [
                    Icon(Icons.analytics_outlined, size: 20, color: cs.primary),
                    const SizedBox(width: 8),
                    Expanded(                        child: Text(
                          widget.work.title,
                          style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              // Scrollable content
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.only(top: 8, bottom: 24),
                  children: [
                    // ── Work Info Card ──
                    _buildWorkInfoCard(cs, s),
                    const SizedBox(height: 12),

                    // ── Voice Actors ──
                    if (widget.work.vas != null && widget.work.vas!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.mic, size: 16, color: cs.tertiary),
                            const SizedBox(width: 6),
                            Text(s.vaLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: widget.work.vas!.map((va) => VaChip(
                            va: va,
                            fontSize: 11,
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            borderRadius: 8,
                            fontWeight: FontWeight.w500,
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Tags ──
                    if (widget.work.tags != null && widget.work.tags!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.label_outline, size: 16, color: cs.secondary),
                            const SizedBox(width: 6),
                            Text(s.tagLabel, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Wrap(
                          spacing: 6,
                          runSpacing: 4,
                          children: widget.work.tags!.take(20).map((tag) => TagChip(
                            tag: tag,
                            fontSize: 10,
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            borderRadius: 6,
                            fontWeight: FontWeight.w400,
                          )).toList(),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],

                    // ── Description ──
                    if (widget.work.description != null && widget.work.description!.isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          children: [
                            Icon(Icons.description_outlined, size: 16, color: cs.primary),
                            const SizedBox(width: 6),
                            Text(s.description, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 6),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: GestureDetector(
                          onTap: () => setState(() => _showFullDescription = !_showFullDescription),
                          child: Text(
                            widget.work.description!,
                            style: TextStyle(fontSize: 12, color: cs.onSurface, height: 1.5),
                            maxLines: _showFullDescription ? null : 4,
                            overflow: _showFullDescription ? null : TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],

                    // ── Divider ──
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Icon(Icons.queue_music, size: 16, color: cs.primary),
                          const SizedBox(width: 6),
                          Text(s.fileList, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                          const Spacer(),                            Text(
                              s.nFiles(widget.work.children?.length ?? 0),
                              style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),

                    // ── Track List ──
                    FutureBuilder<List<AudioTrack>>(
                      future: _tracksFuture,
                      builder: (context, snapshot) {
                        if (snapshot.connectionState == ConnectionState.waiting) {
                          return const Padding(
                            padding: EdgeInsets.all(24),
                            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                          );
                        }
                        if (snapshot.hasError) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(
                                s.loadFailed,
                                style: TextStyle(fontSize: 13, color: cs.error),
                              ),
                            ),
                          );
                        }
                        final tracks = snapshot.data ?? [];
                        if (tracks.isEmpty) {
                          return Padding(
                            padding: const EdgeInsets.all(24),
                            child: Center(
                              child: Text(s.noAudioPlaying, style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
                            ),
                          );
                        }

                        return Column(
                          children: List.generate(tracks.length, (index) {
                            final track = tracks[index];
                            final isCurrent = track.id == widget.currentTrack.id;
                            final ext = track.title.contains('.')
                                ? track.title.split('.').last.toUpperCase()
                                : '';
                            return InkWell(
                              onTap: isCurrent ? null : () => _playTrack(track),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isCurrent ? cs.primaryContainer.withValues(alpha: 0.3) : null,
                                  border: Border(
                                    bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.3), width: 0.5),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    // Track number
                                    SizedBox(
                                      width: 24,
                                      child: isCurrent
                                          ? Icon(Icons.play_arrow, size: 18, color: cs.primary)
                                          : Text(
                                              '${index + 1}',
                                              style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant, fontWeight: FontWeight.w600),
                                            ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Format icon
                                    Icon(_formatFileIcon(track.title), size: 18, color: _formatColor(track.title)),
                                    const SizedBox(width: 8),
                                    // Title + codec
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            track.title,
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                                              color: isCurrent ? cs.primary : cs.onSurface,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          if (ext.isNotEmpty)
                                            Text(
                                              ext,
                                              style: TextStyle(fontSize: 9, color: cs.onSurfaceVariant, fontWeight: FontWeight.w500),
                                            ),
                                        ],
                                      ),
                                    ),
                                    // Duration
                                    if (track.duration != null)
                                      Text(
                                        '${track.duration!.inMinutes}:${(track.duration!.inSeconds % 60).toString().padLeft(2, '0')}',
                                        style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                                      ),
                                    const SizedBox(width: 4),
                                    // Play button
                                    if (!isCurrent)
                                      Icon(Icons.play_circle_outline, size: 20, color: cs.primary)
                                    else
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: cs.primary.withValues(alpha: 0.1),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text('NOW', style: TextStyle(fontSize: 9, color: cs.primary, fontWeight: FontWeight.bold)),
                                      ),
                                  ],
                                ),
                              ),
                            );
                          }),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildWorkInfoCard(ColorScheme cs, S s) {
    final work = widget.work;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              // Mini cover
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 56,
                  height: 56,
                  child: _buildMiniCover(cs),
                ),
              ),
              const SizedBox(width: 12),
              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      work.title,
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: cs.onSurface),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    if (work.name != null)
                      Text(
                        work.name!,
                        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        // Rating
                        if (work.rateAverage != null && work.rateAverage! > 0) ...[
                          const Icon(Icons.star, size: 14, color: Colors.amber),
                          const SizedBox(width: 2),
                          Text(
                            work.rateAverage!.toStringAsFixed(1),
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.amber),
                          ),
                          if (work.rateCount != null) ...[
                            const SizedBox(width: 2),
                            Text(
                              '(${work.rateCount})',
                              style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                            ),
                          ],
                          const SizedBox(width: 8),
                        ],
                        // Duration
                        if (work.duration != null && work.duration! > 0) ...[
                          Icon(Icons.access_time, size: 12, color: cs.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Text(
                            _formatDuration(work.duration),
                            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMiniCover(ColorScheme cs) {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    final coverUrl = _buildCoverUrl(host, token, widget.work.id);

    if (coverUrl != null) {
      return CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        placeholder: (_, __) => Container(color: cs.surfaceContainerHighest),
        errorWidget: (_, __, ___) => Container(
          color: cs.surfaceContainerHighest,
          child: Icon(Icons.music_note, size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
        ),
      );
    }
    return Container(
      color: cs.surfaceContainerHighest,
      child: Icon(Icons.music_note, size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
    );
  }
}
