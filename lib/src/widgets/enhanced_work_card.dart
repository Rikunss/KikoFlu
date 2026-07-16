import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'blur_hash_widget.dart';
import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../providers/work_card_display_provider.dart';
import '../providers/subtitle_library_provider.dart';

import '../services/log_service.dart';
import '../services/cookie_service.dart';
import '../services/blurhash_service.dart';
import '../screens/work_detail_screen.dart';
import '../utils/snackbar_util.dart';
import '../utils/string_utils.dart';
import '../../l10n/app_localizations.dart';
import 'add_to_playlist_dialog.dart';
import 'file_selection_dialog.dart';
import 'play_next_selection_dialog.dart';
import 'tag_chip.dart';
import 'va_chip.dart';
import 'work_bookmark_manager.dart';
import 'privacy_blur_cover.dart';

class EnhancedWorkCard extends ConsumerStatefulWidget {
  final Work work;
  final VoidCallback? onTap;
  final int crossAxisCount;

  const EnhancedWorkCard({
    super.key,
    required this.work,
    this.onTap,
    this.crossAxisCount = 2,
  });

  @override
  ConsumerState<EnhancedWorkCard> createState() => _EnhancedWorkCardState();
}

class _EnhancedWorkCardState extends ConsumerState<EnhancedWorkCard> {
  String? _progress;
  int? _rating;
  bool _updating = false;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _progress = widget.work.progress;
    _rating = widget.work.userRating;
  }

  Future<void> _onLongPress() async {
    HapticFeedback.mediumImpact();
    final s = S.of(context);

    final result = await showModalBottomSheet<Map<String, String>>(
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
                widget.work.title,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(height: 16),
            _MenuListTile(
              icon: Icons.playlist_play,
              label: s.playNext,
              value: 'play_next',
            ),
            _MenuListTile(
              icon: Icons.playlist_add,
              label: s.addToPlaylist,
              value: 'add_to_playlist',
            ),
            _MenuListTile(
              icon: Icons.download,
              label: s.download,
              value: 'download',
            ),
            _MenuListTile(
              icon: Icons.bookmark,
              label: s.markWork,
              value: 'mark_progress',
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );

    if (result == null || !mounted) return;

    switch (result['action']) {
      case 'play_next':
        await _handlePlayNext();
        break;
      case 'add_to_playlist':
        await _handleAddToPlaylist();
        break;
      case 'download':
        await _handleDownload();
        break;
      case 'mark_progress':
        await _handleMarkProgress();
        break;
    }
  }

  Future<void> _handlePlayNext() async {
    final s = S.of(context);
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    try {
      final api = ref.read(kikoeruApiServiceProvider);
      final allFiles = await api.getWorkTracks(widget.work.id);

      if (allFiles.isEmpty) {
        if (mounted) {
          SnackBarUtil.showWarning(context, s.noAudioTracks);
        }
        return;
      }

      final audioFiles = _convertApiFilesToAudioFiles(allFiles, host, token);
      if (audioFiles.isEmpty) {
        if (mounted) {
          SnackBarUtil.showWarning(context, s.noAudioTracks);
        }
        return;
      }

      if (!mounted) return;

      await PlayNextSelectionDialog.show(
        context: context,
        work: widget.work,
        audioFiles: audioFiles,
        host: host,
        token: token,
      );
    } catch (e) {
      LogService.instance.error('Play Next failed: $e', tag: 'Playback');
      if (mounted) {
        SnackBarUtil.showError(context, s.playbackFailed(e.toString()));
      }
    }
  }

  Future<void> _handleAddToPlaylist() async {
    await AddToPlaylistDialog.show(
      context: context,
      workId: widget.work.id,
      workTitle: widget.work.title,
    );
  }

  Future<void> _handleDownload() async {
    try {
      final api = ref.read(kikoeruApiServiceProvider);
      final authState = ref.read(authProvider);
      final host = authState.host ?? '';
      final token = authState.token ?? '';

      final allFiles = await api.getWorkTracks(widget.work.id);
      final audioFiles = _convertApiFilesToAudioFiles(allFiles, host, token);

      if (!mounted) return;

      final workWithChildren = widget.work.copyWith(children: audioFiles);

      await showDialog(
        context: context,
        builder: (ctx) => FileSelectionDialog(work: workWithChildren),
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context, S.of(context).loadFileListFailed(e.toString()));
      }
    }
  }

  Future<void> _handleMarkProgress() async {
    if (_updating) return;
    setState(() => _updating = true);

    try {
      final api = ref.read(kikoeruApiServiceProvider);
      final json = await api.getWork(widget.work.id);
      final detailed = Work.fromJson(json);

      if (!mounted) return;

      setState(() {
        _progress = detailed.progress;
        _rating = detailed.userRating;
      });

      final manager = WorkBookmarkManager(ref: ref, context: context);
      await manager.showMarkDialog(
        workId: widget.work.id,
        currentProgress: _progress,
        currentRating: _rating,
        workTitle: widget.work.title,
        onChanged: (newProgress, newRating) {
          if (mounted) {
            setState(() {
              _progress = newProgress;
              _rating = newRating;
            });
          }
        },
      );
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context, S.of(context).getStatusFailed(e.toString()));
      }
    } finally {
      if (mounted) {
        setState(() => _updating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;

    final host = ref.watch(authProvider.select((s) => s.host ?? ''));
    final token = ref.watch(authProvider.select((s) => s.token ?? ''));
    final displaySettings = ref.watch(workCardDisplayProvider.select((s) => (
      s.showRating,
      s.showPrice,
      s.showSales,
      s.showReleaseDate,
      s.showCircle,
      s.showDuration,
      s.showSubtitleTag,
    )));

    final hasLocalSubtitle = ref.watch(
      subtitleLibraryProvider.select((set) => set.contains(widget.work.id)),
    );
    final hasSubtitle = widget.work.hasSubtitle == true || hasLocalSubtitle;

    final cardOnTap = widget.onTap ??
        () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => WorkDetailScreen(work: widget.work),
            ),
          );
        };

    if (widget.crossAxisCount >= 5 ||
        (widget.crossAxisCount == 3 && !isLandscape)) {
      return _buildCompactCard(context, theme, isLandscape, devicePixelRatio,
          screenWidth, host, token, cardOnTap, displaySettings,
          hasSubtitle, hasLocalSubtitle);
    } else if (widget.crossAxisCount >= 2) {
      return _buildMediumCard(context, theme, isLandscape, devicePixelRatio,
          screenWidth, host, token, cardOnTap, displaySettings,
          hasSubtitle, hasLocalSubtitle);
    } else {
      return _buildFullCard(context, theme, isLandscape, devicePixelRatio,
          screenWidth, host, token, cardOnTap, displaySettings,
          hasSubtitle, hasLocalSubtitle);
    }
  }

  Widget _buildCompactCard(BuildContext context, ThemeData theme,
      bool isLandscape, double devicePixelRatio, double screenWidth,
      String host, String token,
      VoidCallback cardOnTap, (bool,bool,bool,bool,bool,bool,bool) displaySettings,
      bool hasSubtitle, bool hasLocalSubtitle) {
    final (
      showRating,
      showPrice,
      showSales,
      showReleaseDate,
      showCircle,
      showDuration,
      showSubtitleTag,
    ) = displaySettings;
    final titleFontSize = isLandscape ? 13.5 : 11.0;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(0),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: cardOnTap,
          onLongPress: _onLongPress,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.0,
              child: Stack(
                children: [
                  _buildCoverImage(context, host, token, theme, isLandscape, devicePixelRatio, screenWidth),
                  Positioned(
                    top: 4,
                    left: 4,
                    child: _buildRjTag(isLandscape),
                  ),
                  if (showSubtitleTag && (hasSubtitle))
                    Positioned(
                      bottom: 4,
                      left: 4,
                      child: _buildSubtitleTag(
                        context, isLandscape,
                        isLocal: hasLocalSubtitle,
                      ),
                    ),
                  if (showReleaseDate &&
                            widget.work.release != null)
                    Positioned(
                      bottom: 4,
                      right: 4,
                      child: _buildDateTag(isLandscape),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.work.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          fontSize: titleFontSize,
                        ),
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

  Widget _buildMediumCard(BuildContext context, ThemeData theme,
      bool isLandscape, double devicePixelRatio, double screenWidth,
      String host, String token,
      VoidCallback cardOnTap, (bool,bool,bool,bool,bool,bool,bool) displaySettings,
      bool hasSubtitle, bool hasLocalSubtitle) {
    final (
      showRating,
      showPrice,
      showSales,
      showReleaseDate,
      showCircle,
      showDuration,
      showSubtitleTag,
    ) = displaySettings;
    final titleFontSize = isLandscape ? 14.5 : 12.0;
    final bodyFontSize = isLandscape ? 13.5 : 10.0;
    final priceFontSize = isLandscape ? 13.5 : 10.0;
    final ratingFontSize = isLandscape ? 13.0 : 9.0;
    final iconSize = isLandscape ? 14.0 : 12.0;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        clipBehavior: Clip.antiAlias,
        margin: const EdgeInsets.all(0),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: cardOnTap,
          onLongPress: _onLongPress,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            AspectRatio(
              aspectRatio: 1.3,
              child: Stack(
                children: [
                  _buildCoverImage(context, host, token, theme, isLandscape, devicePixelRatio, screenWidth),
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _buildRjTag(isLandscape),
                  ),
                  if (showSubtitleTag && (hasSubtitle))
                    Positioned(
                      bottom: 6,
                      left: 6,
                      child: _buildSubtitleTag(
                        context, isLandscape,
                        isLocal: hasLocalSubtitle,
                      ),
                    ),
                  if (showReleaseDate &&
                      widget.work.release != null)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: _buildDateTag(isLandscape),
                    ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.work.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          height: 1.1,
                          fontSize: titleFontSize,
                        ),
                  ),
                  const SizedBox(height: 3),
                  if (showCircle)
                    Text(
                      widget.work.name ?? '',
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.grey[600],
                            fontSize: bodyFontSize,
                          ),
                    ),
                  if (showCircle) const SizedBox(height: 3),
                  if (showPrice && widget.work.price != null)
                    Text(
                      S.of(context).priceInYen(widget.work.price!),
                      style: theme.textTheme.bodySmall?.copyWith(
                            color: Colors.red[700],
                            fontWeight: FontWeight.w600,
                            fontSize: priceFontSize,
                          ),
                    ),
                  if (showRating &&
                      widget.work.rateAverage != null &&
                      widget.work.rateCount != null &&
                      (widget.work.rateCount! > 0 ||
                          widget.work.rateAverage! != 0)) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.star,
                          color: Colors.amber[700],
                          size: iconSize,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.work.rateAverage!.toStringAsFixed(1)} (${widget.work.rateCount})',
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber[700],
                                    fontWeight: FontWeight.w500,
                                    fontSize: ratingFontSize,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  if (showDuration &&
                      widget.work.duration != null &&
                      widget.work.duration! > 0) ...[
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time,
                          color: Colors.blue,
                          size: iconSize,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatDuration(
                              Duration(seconds: widget.work.duration!)),
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.blue[700],
                                    fontSize: bodyFontSize,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 4),
                  if (widget.work.vas != null && widget.work.vas!.isNotEmpty)
                    _buildVoiceActorsRow(context, isLandscape),
                  const SizedBox(height: 2),
                  if (widget.work.tags != null && widget.work.tags!.isNotEmpty)
                    _buildTagsRow(context, isLandscape),
                  const SizedBox(height: 2),
                ],
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildFullCard(BuildContext context, ThemeData theme,
      bool isLandscape, double devicePixelRatio, double screenWidth,
      String host, String token,
      VoidCallback cardOnTap, (bool,bool,bool,bool,bool,bool,bool) displaySettings,
      bool hasSubtitle, bool hasLocalSubtitle) {
    final (
      showRating,
      showPrice,
      showSales,
      showReleaseDate,
      showCircle,
      showDuration,
      showSubtitleTag,
    ) = displaySettings;
    final rjFontSize = isLandscape ? 11.0 : 10.0;
    final titleFontSize = isLandscape ? 16.0 : 14.0;

    return AnimatedScale(
      scale: _isPressed ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 120),
      curve: Curves.easeOut,
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        child: InkWell(
          onTap: cardOnTap,
          onLongPress: _onLongPress,
          onTapDown: (_) => setState(() => _isPressed = true),
          onTapUp: (_) => setState(() => _isPressed = false),
          onTapCancel: () => setState(() => _isPressed = false),
          child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 80,
                    height: 80,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: _buildCoverImage(context, host, token, theme, isLandscape, devicePixelRatio, screenWidth),
                        ),
                        Positioned(
                          top: 2,
                          left: 2,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              formatRJCode(widget.work.id),
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: rjFontSize,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                        if (showSubtitleTag && (hasSubtitle))
                          Positioned(
                            bottom: 2,
                            left: 2,
                            child: _buildSubtitleTag(
                              context, isLandscape,
                              isLocal: hasLocalSubtitle,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      widget.work.title,
                      style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            height: 1.3,
                            fontSize: titleFontSize,
                          ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (showCircle)
                        Expanded(
                          child: Text(
                            widget.work.name ?? '',
                            style: theme.textTheme.bodyMedium?.copyWith(
                                  color: Colors.grey[600],
                                ),
                          ),
                        ),
                      if (showPrice &&
                          widget.work.price != null)
                        Text(
                          S.of(context).priceInYen(widget.work.price!),
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.red[700],
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      if (showReleaseDate &&
                          widget.work.release != null)
                        Text(
                          widget.work.release!,
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                        ),
                      if (showRating &&
                          widget.work.rateAverage != null &&
                          widget.work.rateCount != null &&
                          widget.work.rateCount! > 0) ...[
                        if (showReleaseDate &&
                            widget.work.release != null)
                          const SizedBox(width: 8),
                        Icon(
                          Icons.star,
                          color: Colors.amber[700],
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          '${widget.work.rateAverage!.toStringAsFixed(1)} (${widget.work.rateCount})',
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.amber[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                      if (showDuration &&
                          widget.work.duration != null &&
                          widget.work.duration! > 0) ...[
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.access_time,
                          color: Colors.blue,
                          size: 14,
                        ),
                        const SizedBox(width: 2),
                        Text(
                          formatDuration(
                              Duration(seconds: widget.work.duration!)),
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.blue[700],
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                      const Spacer(),
                      if (showSales &&
                          widget.work.dlCount != null)
                        Text(
                          S.of(context).soldCount('${widget.work.dlCount}'),
                          style:
                              theme.textTheme.bodySmall?.copyWith(
                                    color: Colors.grey[500],
                                  ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (widget.work.vas != null && widget.work.vas!.isNotEmpty)
                    _buildVoiceActorsWrap(context, isLandscape),
                  const SizedBox(height: 6),
                  if (widget.work.tags != null && widget.work.tags!.isNotEmpty)
                    _buildTagsWrap(context, isLandscape),
                ],
              ),
            ],
          ),
        ),
      ),
      ),
    );
  }

  Widget _buildCoverImage(BuildContext context, String host, String token,
      ThemeData theme, bool isLandscape, double devicePixelRatio, double screenWidth) {
    if (host.isEmpty) {
      return _buildPlaceholder(context);
    }

    final url = widget.work.getCoverImageUrl(host, token: token);
    int targetWidth;
    if (widget.crossAxisCount >= 2) {
      final padding = isLandscape ? 24.0 : 8.0;
      final spacing = isLandscape ? 24.0 : 8.0;
      final availableWidth =
          screenWidth - 2 * padding - (widget.crossAxisCount - 1) * spacing;
      targetWidth =
          (availableWidth / widget.crossAxisCount * devicePixelRatio).round();
    } else {
      targetWidth = (80 * devicePixelRatio).round();
    }

    final httpHeaders = CookieService.coverHttpHeaders(token: token);

    final blurHash = widget.work.blurHash ??
        BlurHashService.instance.getBlurHash(widget.work.id);

    return Hero(
      tag: 'work_cover_${widget.work.id}',
      child: PrivacyBlurCover(
        borderRadius: BorderRadius.circular(4),
        child: RepaintBoundary(
          child: CachedNetworkImage(
            imageUrl: url,
            httpHeaders: httpHeaders,
            cacheKey: 'work_cover_${widget.work.id}',
            memCacheWidth: targetWidth,
            fadeInDuration: const Duration(milliseconds: 120),
            fadeOutDuration: const Duration(milliseconds: 90),
            placeholderFadeInDuration: const Duration(milliseconds: 80),
            placeholder: (context, _) => _buildPlaceholder(context, blurHash: blurHash),
            errorWidget: (context, _, __) => _buildPlaceholder(context, blurHash: blurHash),
            imageBuilder: (context, imageProvider) {
              if (widget.work.blurHash == null &&
                  !BlurHashService.instance.hasBlurHash(widget.work.id)) {
                BlurHashService.instance
                    .generateIfNeeded(widget.work.id, url);
              }
              return Container(
                decoration: BoxDecoration(
                  image: DecorationImage(
                    image: imageProvider,
                    fit: BoxFit.cover,
                    filterQuality: FilterQuality.low,
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholder(BuildContext context, {String? blurHash}) {
    if (blurHash != null && blurHash.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: BlurHashWidget(
          hash: blurHash,
          imageFit: BoxFit.cover,
        ),
      );
    }
    return Container(
      width: double.infinity,
      height: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(
        Icons.audiotrack,
        color: Colors.grey,
        size: 32,
      ),
    );
  }

  Widget _buildRjTag(bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 11.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        formatRJCode(widget.work.id),
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildDateTag(bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 10.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        widget.work.release!,
        style: TextStyle(
          color: Colors.white,
          fontSize: fontSize,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildSubtitleTag(BuildContext context, bool isLandscape, {bool isLocal = false}) {
    final iconSize = isLandscape ? 16.0 : 14.0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: isLocal
            ? Colors.green.withValues(alpha: 0.9)
            : Colors.black.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Icon(
        Icons.closed_caption,
        color: Colors.white,
        size: iconSize,
      ),
    );
  }

  Widget _buildTagsRow(BuildContext context, bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 10.0;

    return Container(
      constraints: const BoxConstraints(minHeight: 14),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: widget.work.tags!.map((tag) {
          return TagChip(
            tag: tag,
            fontSize: fontSize,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            borderRadius: 6,
            fontWeight: FontWeight.w500,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildVoiceActorsRow(BuildContext context, bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 10.0;

    return Container(
      constraints: const BoxConstraints(minHeight: 14),
      child: Wrap(
        spacing: 3,
        runSpacing: 2,
        children: widget.work.vas!.map((va) {
          return VaChip(
            va: va,
            fontSize: fontSize,
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            borderRadius: 6,
            fontWeight: FontWeight.w500,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildTagsWrap(BuildContext context, bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 11.0;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: widget.work.tags!.map((tag) {
        return TagChip(
          tag: tag,
          fontSize: fontSize,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          borderRadius: 12,
          fontWeight: FontWeight.w500,
        );
      }).toList(),
    );
  }

  Widget _buildVoiceActorsWrap(BuildContext context, bool isLandscape) {
    final fontSize = isLandscape ? 13.0 : 11.0;

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: widget.work.vas!.map((va) {
        return VaChip(
          va: va,
          fontSize: fontSize,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          borderRadius: 12,
          fontWeight: FontWeight.w500,
        );
      }).toList(),
    );
  }
}

/// Menu item widget for the long-press context menu bottom sheet.
class _MenuListTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _MenuListTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: Theme.of(context).colorScheme.primary),
      title: Text(label),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.pop(context, {'action': value}),
    );
  }
}

/// Convert raw API file list to [AudioFile] list with proper type normalization.
/// The API returns `type: 'audio'` for audio files, but FileSelectionDialog
/// and PlayNextSelectionDialog expect `type: 'file'`.
List<AudioFile> _convertApiFilesToAudioFiles(
    List<dynamic> files, String host, String token) {
  String normalizedHost = host;
  if (host.isNotEmpty &&
      !host.startsWith('http://') &&
      !host.startsWith('https://')) {
    if (host.contains('localhost') ||
        host.startsWith('127.0.0.1') ||
        host.startsWith('192.168.')) {
      normalizedHost = 'http://$host';
    } else {
      normalizedHost = 'https://$host';
    }
  }

  return files.map((file) {
    final type = file['type'] as String?;
    final title = file['title'] as String? ?? file['name'] as String? ?? '';
    final hash = file['hash'] as String?;
    final size = file['size'] as int?;
    final duration = file['duration'];

    String? downloadUrl;
    if (file['mediaDownloadUrl'] != null &&
        file['mediaDownloadUrl'].toString().isNotEmpty) {
      downloadUrl = file['mediaDownloadUrl'];
    } else if (file['mediaStreamUrl'] != null &&
        file['mediaStreamUrl'].toString().isNotEmpty) {
      downloadUrl = file['mediaStreamUrl'];
    } else if (normalizedHost.isNotEmpty &&
        hash != null &&
        type != 'folder') {
      downloadUrl = '$normalizedHost/api/media/stream/$hash?token=$token';
    }

    List<AudioFile>? children;
    if (file['children'] != null && file['children'] is List) {
      children = _convertApiFilesToAudioFiles(
          file['children'] as List<dynamic>, host, token);
    }

    return AudioFile(
      title: title,
      hash: hash,
      type: type == 'folder' ? 'folder' : 'file',
      children: children,
      size: size,
      mediaDownloadUrl: downloadUrl,
      duration: duration,
    );
  }).toList();
}