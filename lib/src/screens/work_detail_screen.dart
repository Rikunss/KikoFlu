import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/log_service.dart';
import '../services/cookie_service.dart';
import '../utils/string_utils.dart';
import '../../l10n/app_localizations.dart';

import '../models/work.dart';
import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../widgets/scrollable_appbar.dart';
import '../services/storage_service.dart';
import '../widgets/file_explorer_widget.dart';
import '../widgets/file_selection_dialog.dart';
import '../widgets/global_audio_player_wrapper.dart';
import '../widgets/tag_chip.dart';
import '../widgets/va_chip.dart';
import '../widgets/circle_chip.dart';
import '../widgets/responsive_dialog.dart';
import '../widgets/work_bookmark_manager.dart';
import '../widgets/review_progress_dialog.dart';
import '../widgets/rating_detail_popup.dart';
import '../services/translation_service.dart';
import '../widgets/download_fab.dart';
import '../providers/work_detail_display_provider.dart';
import '../widgets/privacy_blur_cover.dart';
import '../widgets/work_detail/tag_vote_dialog.dart';
import '../widgets/work_detail/add_tag_dialog.dart';
import '../widgets/work_detail/recommendation_section.dart';
import '../widgets/work_detail/series_section.dart';

import '../widgets/image_gallery_screen.dart';

class WorkDetailScreen extends ConsumerStatefulWidget {
  final Work work;
  final String? heroTag;

  const WorkDetailScreen({
    super.key,
    required this.work,
    this.heroTag,
  });

  @override
  ConsumerState<WorkDetailScreen> createState() => _WorkDetailScreenState();
}

class _WorkDetailScreenState extends ConsumerState<WorkDetailScreen> {
  Work? _detailedWork;
  String? _errorMessage;
  bool _showHDImage = false;
  ImageProvider? _hdImageProvider;
  String? _currentProgress;
  int? _currentRating;
  bool _isUpdatingProgress = false;
  bool _isOpeningFileSelection = false;
  bool _isOpeningProgressDialog = false;

  String? _translatedTitle;
  bool _showTranslation = false;
  bool _isTranslating = false;

  @override
  void initState() {
    super.initState();
    _currentProgress = widget.work.progress;
    _currentRating = widget.work.userRating;
    _loadWorkDetail();
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _preloadHDImage();
      }
    });
  }

  Future<void> _preloadHDImage() async {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    if (host.isEmpty) return;

    final imageUrl = widget.work.getCoverImageUrl(host, token: token);
    final imageProvider = NetworkImage(imageUrl);

    try {
      await precacheImage(imageProvider, context);
      if (mounted) {
        setState(() {
          _hdImageProvider = imageProvider;
          _showHDImage = true;
        });
      }
    } catch (e) {
      LogService.instance.warning('HD image preload failed: $e', tag: 'UI');
    }
  }

  Future<void> _translateTitle() async {
    if (_isTranslating) return;

    final work = _detailedWork ?? widget.work;

    if (_translatedTitle != null) {
      setState(() {
        _showTranslation = !_showTranslation;
      });
      return;
    }

    setState(() {
      _isTranslating = true;
    });

    try {
      final translationService = TranslationService();
      final translated =
          await translationService.translate(work.title, sourceLang: 'ja');

      if (mounted) {
        setState(() {
          _translatedTitle = translated;
          _showTranslation = true;
          _isTranslating = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).translationFailed(e.toString())),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Future<void> _copyToClipboard(String text, String label) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(S.of(context).copiedToClipboard(label, text)),
          duration: const Duration(seconds: 2),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showTagInfo(Tag tag) {
    showDialog(
      context: context,
      builder: (context) => TagVoteDialog(
        tag: tag,
        workId: widget.work.id,
        onVoteChanged: (updatedTag) {
          if (mounted) {
            setState(() {
              if (_detailedWork != null && _detailedWork!.tags != null) {
                final tagIndex = _detailedWork!.tags!
                    .indexWhere((t) => t.id == updatedTag.id);
                if (tagIndex != -1) {
                  final updatedTags = List<Tag>.from(_detailedWork!.tags!);
                  updatedTags[tagIndex] = updatedTag;
                  _detailedWork = _detailedWork!.copyWith(tags: updatedTags);
                }
              }
            });
          }
        },
        onCopyTag: () => _copyToClipboard(tag.name, S.of(context).tagLabel),
      ),
    );
  }

  void _showAddTagDialog() {
    showDialog(
      context: context,
      builder: (context) => AddTagDialog(
        workId: widget.work.id,
        existingTags: _detailedWork?.tags ?? widget.work.tags ?? [],
        onTagsAdded: () {
          _loadWorkDetail();
        },
      ),
    );
  }

  Future<void> _openSourceUrl(String url) async {
    try {
      final uri = Uri.parse(url);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );

      if (!launched && mounted) {
        final fallbackLaunched = await launchUrl(
          uri,
          mode: LaunchMode.platformDefault,
        );

        if (!fallbackLaunched && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).cannotOpenLink),
              duration: const Duration(seconds: 2),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).openLinkFailed(e.toString())),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showFileSelectionDialog() async {
    if (_isOpeningFileSelection) return;
    _isOpeningFileSelection = true;

    final preparedWorkFuture = _prepareWorkForFileSelection();

    try {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return FutureBuilder<Work>(
            future: preparedWorkFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return ResponsiveAlertDialog(
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 16),
                      Text(S.of(context).loadingFileList),
                    ],
                  ),
                );
              }

              if (snapshot.hasError) {
                return ResponsiveAlertDialog(
                  title: Text(S.of(context).loadFailed),
                  content: Text(S.of(context).loadFileListFailed(snapshot.error.toString())),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(S.of(context).close),
                    ),
                  ],
                );
              }

              final work = snapshot.data!;
              return FileSelectionDialog(work: work);
            },
          );
        },
      );
    } finally {
      _isOpeningFileSelection = false;
    }
  }

  Future<Work> _prepareWorkForFileSelection() async {
    final apiService = ref.read(kikoeruApiServiceProvider);
    final files = await apiService.getWorkTracks(widget.work.id);
    final audioFiles = _convertToAudioFiles(files);
    final baseWork = _detailedWork ?? widget.work;
    return _cloneWorkWithChildren(baseWork, audioFiles);
  }

  Work _cloneWorkWithChildren(Work baseWork, List<AudioFile> audioFiles) {
    return Work(
      id: baseWork.id,
      title: baseWork.title,
      circleId: baseWork.circleId,
      name: baseWork.name,
      vas: baseWork.vas,
      tags: baseWork.tags,
      age: baseWork.age,
      release: baseWork.release,
      dlCount: baseWork.dlCount,
      price: baseWork.price,
      reviewCount: baseWork.reviewCount,
      rateCount: baseWork.rateCount,
      rateAverage: baseWork.rateAverage,
      hasSubtitle: baseWork.hasSubtitle,
      duration: baseWork.duration,
      progress: baseWork.progress,
      images: baseWork.images,
      description: baseWork.description,
      children: audioFiles,
      otherLanguageEditions: baseWork.otherLanguageEditions,
    );
  }

  List<AudioFile> _convertToAudioFiles(List<dynamic> files) {
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';

    String normalizedHost = host;
    if (host.isNotEmpty &&
        !host.startsWith('http://') &&
        !host.startsWith('https://')) {
      normalizedHost = 'https://$host';
    }

    return files.map((file) {
      final type = file['type'] as String?;
      final title = file['title'] as String? ?? file['name'] as String? ?? '';
      final hash = file['hash'] as String?;
      final size = file['size'] as int?;

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
        children = _convertToAudioFiles(file['children'] as List<dynamic>);
      }

      return AudioFile(
        title: title,
        hash: hash,
        type: type == 'folder' ? 'folder' : 'file',
        children: children,
        size: size,
        mediaDownloadUrl: downloadUrl,
      );
    }).toList();
  }

  Future<void> _loadWorkDetail() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final apiService = ref.read(kikoeruApiServiceProvider);
      final response = await apiService.getWork(widget.work.id);
      final detailedWork = Work.fromJson(response);

      if (mounted) {
        setState(() {
          _detailedWork = detailedWork;
          _currentProgress = detailedWork.progress;
          _currentRating = detailedWork.userRating;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = S.of(context).loadFailedWithError(e.toString());
        });
      }
    }
  }

  Future<void> _refreshWorkDetail() async {
    try {
      setState(() {
        _errorMessage = null;
      });

      final apiService = ref.read(kikoeruApiServiceProvider);

      final prefs = await StorageService.getPrefs();
      await prefs.remove('work_detail_${widget.work.id}');
      await prefs.remove('work_detail_time_${widget.work.id}');

      final response = await apiService.getWork(widget.work.id);
      final detailedWork = Work.fromJson(response);

      if (mounted) {
        setState(() {
          _detailedWork = detailedWork;
          _currentProgress = detailedWork.progress;
          _currentRating = detailedWork.userRating;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).refreshComplete),
            duration: const Duration(seconds: 1),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = S.of(context).refreshFailed(e.toString());
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).refreshFailed(e.toString())),
            duration: const Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showProgressDialog() async {
    if (_isOpeningProgressDialog) return;
    _isOpeningProgressDialog = true;

    final manager = WorkBookmarkManager(ref: ref, context: context);

    await manager.showMarkDialog(
      workId: widget.work.id,
      currentProgress: _currentProgress,
      currentRating: _currentRating,
      workTitle: widget.work.title,
      onChanged: (newProgress, newRating) {
        if (mounted) {
          setState(() {
            _currentProgress = newProgress;
            _currentRating = newRating;
            _isUpdatingProgress = false;
          });
        }
      },
    );

    _isOpeningProgressDialog = false;
  }

  Future<void> _showRatingDetailDialog(Work work) async {
    if (work.rateCountDetail == null || work.rateCountDetail!.isEmpty) return;
    if (work.rateAverage == null || work.rateCount == null) return;

    await showDialog(
      context: context,
      builder: (context) => Dialog(
        backgroundColor: Colors.transparent,
        child: RatingDetailPopup(
          ratingDetails: work.rateCountDetail!,
          averageRating: work.rateAverage!,
          totalCount: work.rateCount!,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final mediaQuerySize = MediaQuery.of(context).size;
    final orientation = MediaQuery.orientationOf(context);

    final brightness = theme.brightness;
    final systemOverlayStyle = SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: brightness == Brightness.light
          ? Brightness.dark
          : Brightness.light,
      systemNavigationBarColor: Colors.transparent,
    );

    return GlobalAudioPlayerWrapper(
      child: Scaffold(
        floatingActionButton: const DownloadFab(),
        appBar: ScrollableAppBar(
          systemOverlayStyle: systemOverlayStyle,
          title: GestureDetector(
            onLongPress: () =>
                _copyToClipboard(formatRJCode(widget.work.id), S.of(context).rjNumberLabel),
            child: Text(
              formatRJCode(widget.work.id),
              style: textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
            ),
          ),
          backgroundColor: Colors.transparent,
          elevation: 0,
          actions: [
            IconButton(
              icon: const Icon(Icons.download),
              onPressed: () {
                HapticFeedback.lightImpact();
                _showFileSelectionDialog();
              },
              tooltip: S.of(context).download,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                switchInCurve: Curves.easeOut,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(
                      scale: animation,
                      child: child,
                    ),
                  );
                },
                child: _isUpdatingProgress
                    ? Padding(
                        key: const ValueKey('progress_loading'),
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Center(                            child: SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colorScheme.primary,
                              ),
                            ),
                        ),
                      )
                    : TextButton(
                        key: ValueKey('progress_${_currentProgress ?? 'none'}'),
                        onPressed: () {
                          HapticFeedback.lightImpact();
                          _showProgressDialog();
                        },
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              ReviewProgressDialog.getProgressLabel(
                                  _currentProgress, context),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: _currentProgress != null
                                    ? colorScheme.primary
                                    : colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(width: 4),
                            Icon(
                              ReviewProgressDialog.getProgressIcon(
                                  _currentProgress),
                              size: 22,
                              color: _currentProgress != null
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ],
                        ),
                      ),
              ),
            ),
          ],
        ),
        body: _buildBody(
          theme: theme,
          colorScheme: colorScheme,
          textTheme: textTheme,
          mediaQuerySize: mediaQuerySize,
          orientation: orientation,
        ),
      ),
    );
  }

  Widget _buildBody({
    required ThemeData theme,
    required ColorScheme colorScheme,
    required TextTheme textTheme,
    required Size mediaQuerySize,
    required Orientation orientation,
  }) {
    final (host, token) = ref.watch(authProvider.select(
      (s) => (s.host ?? '', s.token ?? ''),
    ));
    final isLandscape =
        orientation == Orientation.landscape;

    final work = _detailedWork ?? widget.work;

    final effectiveHeroTag = widget.heroTag ?? 'work_cover_${widget.work.id}';
    final coverWidget = GestureDetector(
      onLongPress: () {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => ImageGalleryScreen(
              images: [
                {
                  'url': work.getCoverImageUrl(host, token: token),
                  'title': work.title,
                  'hash': '',
                },
              ],
              initialIndex: 0,
            ),
          ),
        );
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: Hero(
          tag: effectiveHeroTag,
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            clipBehavior: Clip.antiAlias,
            child: Container(
              width: isLandscape ? null : double.infinity,
              constraints: BoxConstraints(
                maxHeight: isLandscape
                    ? mediaQuerySize.height * 0.8
                    : 500,
                maxWidth: isLandscape
                    ? mediaQuerySize.width * 0.45
                    : double.infinity,
              ),
              child: PrivacyBlurCover(
                borderRadius: BorderRadius.circular(12),
                child: Stack(
                  fit: StackFit.passthrough,
                  children: [
                    CachedNetworkImage(
                      imageUrl: work.getCoverImageUrl(host, token: token),
                      cacheKey: 'work_cover_${widget.work.id}',
                      httpHeaders: CookieService.coverHttpHeaders(token: token),
                      fit: BoxFit.contain,
                      placeholder: (context, url) => Container(
                        height: 300,
                        color: Colors.grey[300],
                        child: const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
                      errorWidget: (context, url, error) => Container(
                        height: 300,
                        color: Colors.grey[300],
                        child: const Icon(
                          Icons.image_not_supported,
                          size: 64,
                          color: Colors.grey,
                        ),
                      ),
                    ),
                    if (_showHDImage && _hdImageProvider != null)
                      Image(
                        image: _hdImageProvider!,
                        fit: BoxFit.contain,
                        errorBuilder: (context, error, stackTrace) {
                          return const SizedBox.shrink();
                        },
                      ),
                    if (ref.watch(workDetailDisplayProvider).showSubtitleTag &&
                        work.hasSubtitle == true)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        height: 52,
                        child: Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.bottomCenter,
                              end: Alignment.topCenter,
                              colors: [
                                Colors.black.withValues(alpha: 0.35),
                                Colors.transparent,
                              ],
                            ),
                          ),
                        ),
                      ),
                    if (ref.watch(workDetailDisplayProvider).showSubtitleTag &&
                        work.hasSubtitle == true)
                      Positioned(
                        right: 12,
                        bottom: 12,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            borderRadius: BorderRadius.circular(6),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.3),
                                blurRadius: 4,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            S.of(context).subtitleBadge,
                            style: TextStyle(
                              color: colorScheme.onPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.1,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final infoWidget = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Consumer(
            builder: (context, ref, _) {
              final displaySettings = ref.watch(workDetailDisplayProvider);
              return GestureDetector(
                onLongPress: () => _copyToClipboard(
                  _showTranslation && _translatedTitle != null
                      ? _translatedTitle!
                      : work.title,
                  S.of(context).titleLabel,
                ),
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: _showTranslation && _translatedTitle != null
                            ? _translatedTitle
                            : work.title,
                      ),
                      if (displaySettings.showExternalLinks &&
                          work.sourceUrl != null)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: () => _openSourceUrl(work.sourceUrl!),
                                child: Icon(
                                  Icons.open_in_new,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (displaySettings.showTranslateButton)
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: MouseRegion(
                              cursor: _isTranslating
                                  ? SystemMouseCursors.basic
                                  : SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _isTranslating ? null : _translateTitle,
                                child: _isTranslating
                                    ? SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: colorScheme.primary,
                                        ),
                                      )
                                    : Icon(
                                        Icons.g_translate,
                                        size: 18,
                                        color: _showTranslation
                                            ? colorScheme.primary
                                            :colorScheme.onSurface
                                                .withValues(alpha: 0.6),
                                      ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                  style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                  textAlign: TextAlign.start,
                  softWrap: true,
                ),
              );
            },
          ),
          const SizedBox(height: 8),

          if (_errorMessage != null)
            Card(
              elevation: 0,
              color:colorScheme.errorContainer
                  .withValues(alpha: 0.25),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer
                            .withValues(alpha: 0.6),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.error_outline_rounded,
                        size: 20,
                        color: colorScheme.error,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _errorMessage!,
                        style: TextStyle(
                          color:colorScheme.onErrorContainer,
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: _loadWorkDetail,
                      style: TextButton.styleFrom(
                        foregroundColor:
                            colorScheme.error,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                      ),
                      child: Text(
                        S.of(context).retry,
                        style: const TextStyle(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

          Consumer(
            builder: (context, ref, _) {
              final displaySettings = ref.watch(workDetailDisplayProvider);
              final showPrice = displaySettings.showPrice && work.price != null;
              final showDuration = displaySettings.showDuration &&
                  work.duration != null &&
                  work.duration! > 0;
              final showSales = displaySettings.showSales &&
                  work.dlCount != null &&
                  work.dlCount! > 0;
              final hasAnyItem = displaySettings.showRating ||
                  _currentRating != null ||
                  showPrice ||
                  showDuration ||
                  showSales;
              if (!hasAnyItem) return const SizedBox.shrink();
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (displaySettings.showRating)
                        MouseRegion(
                          cursor: work.rateCountDetail != null &&
                                  work.rateCountDetail!.isNotEmpty
                              ? SystemMouseCursors.click
                              : SystemMouseCursors.basic,
                          child: GestureDetector(
                            onTap: () {
                              if (work.rateCountDetail != null &&
                                  work.rateCountDetail!.isNotEmpty) {
                                _showRatingDetailDialog(work);
                              }
                            },
                            child: Tooltip(
                              message: work.rateCountDetail != null &&
                                      work.rateCountDetail!.isNotEmpty
                                  ? S.of(context).tapToViewRatingDetail
                                  : '',
                              preferBelow: false,
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star,
                                      color: Colors.amber, size: 20),
                                  const SizedBox(width: 4),
                                  Text(
                                    (work.rateAverage != null &&
                                            work.rateCount != null &&
                                            (work.rateCount! > 0 ||
                                                work.rateAverage! != 0))
                                        ? work.rateAverage!.toStringAsFixed(1)
                                        : '-',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        '(',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                      Text(
                                        '${work.rateCount ?? 0}',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                      if (work.rateCountDetail != null &&
                                          work.rateCountDetail!.isNotEmpty)
                                        Icon(
                                          Icons.info_outline,
                                          size: 14,
                                          color: Colors.grey[600],
                                        ),
                                      Text(
                                        ')',
                                        style: TextStyle(
                                          color: Colors.grey[600],
                                          fontSize: 12,
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                      if (_currentRating != null)
                        InkWell(
                          onTap: _showProgressDialog,
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.person,
                                  color:colorScheme.onPrimaryContainer,
                                  size: 14,
                                ),
                                const SizedBox(width: 4),
                                const Icon(
                                  Icons.star,
                                  color: Colors.amber,
                                  size: 14,
                                ),
                                const SizedBox(width: 2),
                                Text(
                                  '$_currentRating',
                                  style: TextStyle(
                                    color: colorScheme.onPrimaryContainer,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      if (showPrice)
                        Text(
                          S.of(context).priceInYen(work.price!),
                          style: textTheme.bodyMedium?.copyWith(
                                color: Colors.red[700],
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                        ),

                      if (showDuration)
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.access_time,
                                color: Colors.blue, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              _formatDuration(work.duration!),
                              style: textTheme.bodyMedium?.copyWith(
                                    color: Colors.blue[700],
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),

                      if (showSales)
                        Text(
                          S.of(context).soldCount(
                              _formatNumber(context, work.dlCount!)),
                          style: textTheme.bodyMedium?.copyWith(
                                color: Colors.grey[600],
                                fontSize: 12,
                              ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),

          const SizedBox(height: 16),

          if ((work.name != null && work.name!.isNotEmpty) ||
              (work.vas != null && work.vas!.isNotEmpty))
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.groups, size: 18,
                            color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          S.of(context).circleAndVaSection,
                          style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),

            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                if (work.name != null &&
                    work.name!.isNotEmpty &&
                    work.circleId != null)
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: CircleChip(
                      circleId: work.circleId!,
                      circleName: work.name!,
                      fontSize: 12,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      borderRadius: 6,
                      fontWeight: FontWeight.w500,
                      onLongPress: () => _copyToClipboard(work.name!, S.of(context).circleLabel),
                    ),
                  ),

                if (work.vas != null && work.vas!.isNotEmpty)
                  ...work.vas!.map((va) {
                    return MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: VaChip(
                        va: va,
                        fontSize: 12,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        borderRadius: 6,
                        fontWeight: FontWeight.w500,
                        onLongPress: () => _copyToClipboard(va.name, S.of(context).vaLabel),
                      ),
                    );
                  }),
              ],
            ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

          if (work.tags != null && work.tags!.isNotEmpty)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.label, size: 18,
                            color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          S.of(context).tagLabel,
                          style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                ...work.tags!
                    .map((tag) => MouseRegion(
                          cursor: SystemMouseCursors.click,
                          child: GestureDetector(
                            onSecondaryTapDown: (details) {
                              _showTagInfo(tag);
                            },
                            child: TagChip(
                              tag: tag,
                              fontSize: 12,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 4),
                              borderRadius: 6,
                              fontWeight: FontWeight.w500,
                              onLongPress: () => _showTagInfo(tag),
                            ),
                          ),
                        )),
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: _showAddTagDialog,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color:colorScheme.primaryContainer
                            .withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Icon(
                        Icons.add,
                        size: 16,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ) else ...[
            GestureDetector(
              onTap: _showAddTagDialog,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer
                      .withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      S.of(context).addTag,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.primary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],

          const SizedBox(height: 8),

          Consumer(
            builder: (context, ref, _) {
              final displaySettings = ref.watch(workDetailDisplayProvider);
              if (!displaySettings.showReleaseDate || work.release == null) {
                return const SizedBox.shrink();
              }
              return Card(
                elevation: 0,
                color: colorScheme.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                margin: const EdgeInsets.only(bottom: 8),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.calendar_today, size: 18,
                              color: colorScheme.primary),
                          const SizedBox(width: 6),
                          Text(
                            S.of(context).releaseDate,
                            style: textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.primary,
                                ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        work.release!.split('T')[0],
                        style: textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                            ),
                      ),
                      const SizedBox(height: 4),
                    ],
                  ),
                ),
              );
            },
          ),

          if (work.otherLanguageEditions != null &&
              work.otherLanguageEditions!.isNotEmpty)
            Card(
              elevation: 0,
              color: colorScheme.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.translate, size: 18,
                            color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          S.of(context).otherEditions,
                          style: textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w600,
                                color: colorScheme.primary,
                              ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 4,
                      runSpacing: 4,
                      children: work.otherLanguageEditions!.map((edition) {
                        return InkWell(
                          onTap: () {
                            Navigator.of(context).push(
                              MaterialPageRoute(
                                builder: (context) => WorkDetailScreen(
                                  work: Work(
                                    id: edition.id,
                                    title: edition.title,
                                  ),
                                ),
                              ),
                            );
                          },
                          borderRadius: BorderRadius.circular(6),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color:colorScheme.secondaryContainer
                                  .withValues(alpha: 0.7),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.translate,
                                  size: 14,
                                  color:colorScheme.onSecondaryContainer,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '「${edition.lang}」',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colorScheme.onSecondaryContainer,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 4),
                  ],
                ),
              ),
            ),

          FileExplorerWidget(work: work),

          const SizedBox(height: 4),
          SeriesSection(work: work),
          RecommendationSection(work: work),
        ],
      ),
    );

    if (isLandscape) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Center(
              child: coverWidget,
            ),
          ),
          Expanded(
            flex: 3,
            child: RefreshIndicator(
              onRefresh: _refreshWorkDetail,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(0),
                physics: const AlwaysScrollableScrollPhysics(),
                child: infoWidget,
              ),
            ),
          ),
        ],
      );
    } else {
      return RefreshIndicator(
        onRefresh: _refreshWorkDetail,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(0),
          physics: const AlwaysScrollableScrollPhysics(),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              coverWidget,
              infoWidget,
            ],
          ),
        ),
      );
    }
  }

  String _formatNumber(BuildContext context, int number) {
    if (number >= 10000) {
      return S.of(context).tenThousandSuffix((number / 10000).toStringAsFixed(1));
    } else if (number >= 1000) {
      return '${(number / 1000).toStringAsFixed(1)}k';
    } else {
      return number.toString();
    }
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }
}