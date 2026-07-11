import 'dart:async';
import 'dart:io';
import 'dart:math' show max;
import 'dart:ui' show ImageFilter;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../services/log_service.dart';

import '../models/work.dart';
import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/locale_provider.dart';
import '../providers/lyric_provider.dart';
import '../widgets/player/player_cover_widget.dart';
import '../widgets/player/player_controls_widget.dart';
import '../widgets/player/lyric_display_widget.dart';
import '../widgets/player/playlist_dialog.dart';
import '../widgets/work_bookmark_manager.dart';
import '../widgets/player/audio_info_sheet.dart' show showAudioInfoSheet;
import '../providers/exclusive_audio_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../utils/audio_format_parser.dart' show AudioFormatInfo;
import '../widgets/player/work_info_panel.dart' show showWorkInfoPanel;
import '../utils/artwork_color_extractor.dart';
import 'work_detail_screen.dart';
import '../../l10n/app_localizations.dart';
import '../services/ai_model_service.dart';
import '../services/streaming_speed_tracker.dart';
import '../providers/ai_settings_provider.dart';
import '../widgets/ai_model_picker_dialog.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

/// 音频播放器主屏幕
class AudioPlayerScreen extends ConsumerStatefulWidget {
  const AudioPlayerScreen({super.key});

  @override
  ConsumerState<AudioPlayerScreen> createState() => _AudioPlayerScreenState();
}

/// ===================================================================
/// Extracted widget: translate button — watches lyricControllerProvider
/// ===================================================================
class _TranslateButton extends ConsumerWidget {
  const _TranslateButton();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(lyricControllerProvider);
    final cs = Theme.of(context).colorScheme;
    if (lyricState.lyrics.isEmpty) return const SizedBox.shrink();

    final appLocale =
        ref.watch(localeProvider) ?? Localizations.localeOf(context);
    if (!lyricState.needsTranslation(appLocale) && !lyricState.isTranslated) {
      return const SizedBox.shrink();
    }

    final isTranslating = lyricState.isTranslating;
    final isTranslated = lyricState.isTranslated;
    final showTranslated = lyricState.showTranslated;

    String tooltip;
    if (isTranslating) {
      tooltip = S.of(context).translatingLyrics;
    } else if (isTranslated && showTranslated) {
      tooltip = S.of(context).showOriginalLyrics;
    } else if (isTranslated && !showTranslated) {
      tooltip = S.of(context).showTranslatedLyrics;
    } else {
      tooltip = S.of(context).translateLyrics;
    }

    return FloatingActionButton.small(
      heroTag: 'translate_lyrics',
      onPressed: isTranslating
          ? null
          : () async {
              try {
                await ref
                    .read(lyricControllerProvider.notifier)
                    .toggleTranslation();
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of(context).lyricTranslationFailed),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
      tooltip: tooltip,
      child: isTranslating
          ? const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(Icons.translate,
              color: (isTranslated && showTranslated)
                  ? cs.primary
                  : null),
    );
  }
}

/// ===================================================================
/// Extracted widget: lyric hint chip — overlays on cover art corner
/// ===================================================================
class _LyricHintChip extends ConsumerWidget {
  final VoidCallback onDismiss;
  final VoidCallback onTap;

  const _LyricHintChip({
    required this.onDismiss,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lyricState = ref.watch(lyricControllerProvider);
    if (lyricState.lyrics.isEmpty) return const SizedBox.shrink();

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, opacity, child) {
        return Opacity(
          opacity: opacity,
          child: child,
        );
      },
      child: GestureDetector(
        onTap: () {
          onTap();
          onDismiss();
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
            ),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.lyrics_outlined, size: 14,
                    color: Colors.white.withValues(alpha: 0.9)),
                  const SizedBox(width: 6),
                  Text(
                    S.of(context).lyricHintTapCover,
                    style: const TextStyle(
                      fontSize: 11,
                      color: Colors.white,
                      fontWeight: FontWeight.w500,
                      letterSpacing: 0.2,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// ===================================================================
/// Extracted widget: portrait lyric view with locked fullscreen mode
/// Manages _isLyricLocked / _showUnlockButton internally
/// ===================================================================
class _PortraitLyricView extends ConsumerStatefulWidget {
  final Duration? seekingPosition;
  final ValueChanged<Duration>? onLyricSeek;
  final VoidCallback onBackToCover;
  final List<Color>? gradientColors;

  const _PortraitLyricView({
    super.key,
    required this.seekingPosition,
    this.onLyricSeek,
    required this.onBackToCover,
    this.gradientColors,
  });

  @override
  ConsumerState<_PortraitLyricView> createState() =>
      _PortraitLyricViewState();
}

class _PortraitLyricViewState extends ConsumerState<_PortraitLyricView> {
  bool _isLyricLocked = false;
  bool _showUnlockButton = false;

  void _enterLyricFullscreen() {
    setState(() {
      _isLyricLocked = true;
      _showUnlockButton = false;
    });
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _exitLyricFullscreen() {
    setState(() {
      _isLyricLocked = false;
      _showUnlockButton = false;
    });
    SystemChrome.setEnabledSystemUIMode(
      SystemUiMode.manual,
      overlays: SystemUiOverlay.values,
    );
  }

  void _handleLockedTap() {
    setState(() => _showUnlockButton = !_showUnlockButton);
    if (_showUnlockButton) {
      Future.delayed(const Duration(seconds: 3), () {
        if (mounted && _showUnlockButton) {
          setState(() => _showUnlockButton = false);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    if (_isLyricLocked) {
      return GestureDetector(
        onTap: _handleLockedTap,
        onLongPress: _handleLockedTap,
        child: Stack(children: [
          FullLyricDisplay(
            seekingPosition: widget.seekingPosition,
            onLyricSeek: widget.onLyricSeek,
            isPortrait: true, isLocked: true,
            gradientColors: widget.gradientColors,
          ),
          if (_showUnlockButton)
            Positioned(
              top: MediaQuery.of(context).padding.top + 16,
              left: 0, right: 0,
              child: Center(
                child: AnimatedOpacity(
                  opacity: 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Container(
                    decoration: BoxDecoration(
                      color: cs.surfaceContainerHighest
                          .withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8, offset: const Offset(0, 2))],
                    ),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: _exitLyricFullscreen,
                        borderRadius: BorderRadius.circular(24),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            Icon(Icons.lock_open, size: 20,
                              color: cs.primary),
                            const SizedBox(width: 8),
                            Text(S.of(context).unlock,
                              style: tt.labelLarge?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold)),
                          ]),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
    }

    return Stack(children: [
      FullLyricDisplay(
        seekingPosition: widget.seekingPosition,
        onLyricSeek: widget.onLyricSeek,
        isPortrait: true,
        gradientColors: widget.gradientColors,
        onLongPress: _enterLyricFullscreen,
      ),
      const Positioned(left: 16, bottom: 16, child: _TranslateButton()),
      Positioned(right: 16, bottom: 16,
        child: FloatingActionButton(
          onPressed: widget.onBackToCover,
          tooltip: S.of(context).backToCover,
          child: const Icon(Icons.album),
        ),
      ),
    ]);
  }

  @override
  void dispose() {
    if (_isLyricLocked) {
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.manual,
        overlays: SystemUiOverlay.values,
      );
    }
    super.dispose();
  }
}

/// ===================================================================
/// Extracted widget: controls + position — isolates position tick rebuilds
/// ===================================================================
class _PlayerControlsWithPosition extends ConsumerWidget {
  final bool isLandscape;
  final bool isSeekingManually;
  final double seekValue;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final Duration? seekingPosition;
  final int? workId;
  final String? currentProgress;
  final VoidCallback? onMarkPressed;
  final VoidCallback? onDetailPressed;
  final List<Color>? gradientColors;
  final VoidCallback? onGradientRefresh;

  const _PlayerControlsWithPosition({
    required this.isLandscape,
    required this.isSeekingManually,
    required this.seekValue,
    required this.onSeekChanged,
    required this.onSeekEnd,
    this.seekingPosition,
    this.workId,
    this.currentProgress,
    this.onMarkPressed,
    this.onDetailPressed,
    this.gradientColors,
    this.onGradientRefresh,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final audioState = ref.watch(audioPlayerControllerProvider);

    return PlayerControlsWidget(
      isLandscape: isLandscape,
      audioState: audioState,
      isSeekingManually: isSeekingManually,
      seekValue: seekValue,
      onSeekChanged: onSeekChanged,
      onSeekEnd: onSeekEnd,
      gradientColors: gradientColors,
      seekingPosition: seekingPosition,
      workId: workId,
      currentProgress: currentProgress,
      onMarkPressed: onMarkPressed,
      onDetailPressed: onDetailPressed,
      onGradientRefresh: onGradientRefresh,
    );
  }
}

/// ===================================================================
/// Main screen state
/// ===================================================================
class _AudioPlayerScreenState extends ConsumerState<AudioPlayerScreen>
    with SingleTickerProviderStateMixin {
  double _dragOffset = 0;
  bool _isDragging = false;
  late AnimationController _dismissCtrl;
  bool _isSeekingManually = false;
  double _seekValue = 0.0;
  bool _showLyricHint = false;
  String? _currentProgress;
  int? _currentRating;
  int? _currentWorkId;
  bool _isFavorited = false;
  bool _isFavLoading = false;
  List<Color>? _gradientColors;
  Duration? _seekingPosition;
  bool _showLyricView = false;
  bool _showSwipeHint = false;
  StreamSubscription<Duration>? _seekCompletionSub;
  int _seekGeneration = 0;
  /// Tracks whether SystemChrome.setSystemUIOverlayStyle has been called.
  /// The fullscreen player always uses a dark canvas (Colors.black / #111111),
  /// so the status bar style never needs to change after initial setup.
  /// Guarding this avoids a platform-channel method call on every build().
  bool _systemUiStyleSet = false;

  /// Guards against double-clicking the "Generate AI Lyrics" button.
  bool _isTranscribing = false;

  /// Returns the local file path for AI transcription, or null if streamed.
  String? _getLocalAudioPath(AudioTrack? track) {
    final url = track?.url;
    if (url == null || !url.startsWith('file://')) return null;
    return url.replaceFirst('file://', '');
  }

  /// Generate AI lyrics for the current local audio file.
  /// Shows the model picker dialog first, then transcribes with chosen settings.
  Future<void> _onGenerateAiLyrics() async {
    if (_isTranscribing) return;

    final track = ref.read(currentTrackProvider).valueOrNull;
    if (track == null) return;
    final audioPath = _getLocalAudioPath(track);
    if (audioPath == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Only local audio files are supported for AI transcription'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final aiService = ref.read(aiModelServiceProvider);
    final settings = ref.read(aiSettingsProvider);

    final installedConfigs = <AiModelConfig>[];
    for (final config in aiModelConfigs) {
      if (await aiService.checkModelInstalled(model: config.model)) {
        installedConfigs.add(config);
      }
    }

    if (installedConfigs.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).aiModelRequired),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    WhisperModel initialModel;
    try {
      initialModel = WhisperModel.values.firstWhere(
        (m) => m.name == settings.selectedModel,
      );
      if (!installedConfigs.any((c) => c.model == initialModel)) {
        initialModel = installedConfigs.first.model;
      }
    } catch (_) {
      initialModel = installedConfigs.first.model;
    }

    if (!mounted) return;
    final config = await showAIModelPickerDialog(
      context,
      installedModels: installedConfigs,
      initialModel: initialModel,
      initialThreads: settings.transcriptionThreads,
      initialSplitOnWord: settings.splitOnWord,
    );

    if (config == null || !mounted) return;

    setState(() => _isTranscribing = true);
    try {
      final lrcPath = await aiService.generateLrc(
        audioPath,
        track.title,
        model: config.model,
        threads: config.threads,
        splitOnWord: config.splitOnWord,
      );
      if (mounted) {
        if (lrcPath != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(S.of(context).aiTranscribeComplete),
              behavior: SnackBarBehavior.floating,
            ),
          );
          ref
              .read(lyricControllerProvider.notifier)
              .loadLyricFromLocalFile(lrcPath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).aiTranscribeFailed(e.toString())),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isTranscribing = false);
      }
    }
  }

  /// In landscape mode, only drags started on the cover/controls side (left ~40%)
  /// should trigger dismiss — the right side (lyrics) must remain scrollable.
  bool _isValidDismissDrag = false;

  /// Force-dark status bar + nav bar for the fullscreen player.
  /// The player background is always dark regardless of theme.
  static const _darkSystemUi = SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Colors.transparent,
  );

  @override
  void initState() {
    super.initState();
    _initLyricHint();
    _initSwipeHint();
    StreamingSpeedTracker.instance.start();
    _dismissCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _dismissCtrl.addListener(_onDismissUpdate);
  }

  Future<void> _initLyricHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasShown = prefs.getBool('lyric_hint_has_shown') ?? false;
    if (!hasShown) {
      setState(() => _showLyricHint = true);
      await prefs.setBool('lyric_hint_has_shown', true);
      Future.delayed(const Duration(seconds: 6), () {
        if (mounted) setState(() => _showLyricHint = false);
      });
    }
  }

  Future<void> _initSwipeHint() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final hasShown = prefs.getBool('swipe_dismiss_hint_shown') ?? false;
    if (!hasShown) {
      await prefs.setBool('swipe_dismiss_hint_shown', true);
      await Future.delayed(const Duration(milliseconds: 600));
      if (!mounted) return;
      setState(() => _showSwipeHint = true);
      Future.delayed(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showSwipeHint = false);
      });
    }
  }

  Future<void> _loadCurrentProgress(int workId) async {
    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final workData = await apiService.getWork(workId);
      final work = Work.fromJson(workData);
      if (mounted && _currentWorkId == workId) {
        setState(() { _currentProgress = work.progress; _currentRating = work.userRating; });
      }
    } catch (e) {
      LogService.instance.warning('Failed to load progress for work $workId: $e', tag: 'Playback');
    }
  }

  /// Check if the current work is in user's favorites.
  /// Uses an in-memory cache so re-playing the same work within a session
  /// is instant. Iterates at most 2 pages (40 works) — covers the vast
  /// majority of users without excessive API calls.
  Future<void> _checkFavoriteStatus(int workId) async {
    if (_favoriteCache.containsKey(workId)) {
      final cached = _favoriteCache[workId]!;
      if (mounted && cached != _isFavorited) {
        setState(() => _isFavorited = cached);
      }
      return;
    }

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      for (int page = 1; page <= 2; page++) {
        final favorites = await apiService.getFavorites(page: page, pageSize: 20);
        final worksList = favorites['works'] as List? ?? [];
        if (worksList.any((w) => w is Map && w['id'] == workId)) {
          _favoriteCache[workId] = true;
          if (mounted) {
            setState(() => _isFavorited = true);
          }
          return;
        }
        if (worksList.length < 20) break;
      }
      _favoriteCache[workId] = false;
    } catch (_) {
    }
  }

  /// Toggle favorite status for the current work.
  Future<void> _toggleFavorite(int workId) async {
    if (_isFavLoading) return;
    setState(() => _isFavLoading = true);

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      if (_isFavorited) {
        await apiService.removeFromFavorites(workId);
      } else {
        await apiService.addToFavorites(workId);
      }
      if (mounted) {
        _favoriteCache[workId] = !_isFavorited;
        setState(() => _isFavorited = !_isFavorited);
        HapticFeedback.lightImpact();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(_isFavorited
                  ? S.of(context).alreadyFavorited
                  : 'Removed from favorites'),
              duration: const Duration(seconds: 1),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to toggle favorite'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isFavLoading = false);
    }
  }

  /// Called when [track]'s workId differs from [_currentWorkId].
  /// Extracts gradient colors immediately and defers progress/favorite API
  /// calls to let the route entrance animation settle.
  void _onTrackChanged(AudioTrack track) {
    if (track.workId != null && _currentWorkId != track.workId) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && track.workId != null &&
            _extractedCoverForWorkId != track.workId) {
          _extractedCoverForWorkId = track.workId;
          setState(() { _currentWorkId = track.workId; _currentProgress = null; _isFavorited = false; });
          _extractGradientColors(track.workId, track.artworkUrl);
          Future.delayed(const Duration(milliseconds: 400), () {
            if (mounted && _currentWorkId == track.workId) {
              _loadCurrentProgress(track.workId!);
              _checkFavoriteStatus(track.workId!);
            }
          });
        }
      });
    }
  }

  /// Track which work's cover has been extracted to avoid duplicate work.
  int? _extractedCoverForWorkId;
  /// Simple in-memory cache for favorite status checks — avoids redundant
  /// API calls across track changes.
  final Map<int, bool> _favoriteCache = {};

  void _handleRefreshGradient() {
    ArtworkColorExtractor.clearCache();
    _extractGradientColors(_currentWorkId, null);
    _extractedCoverForWorkId = null;
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Refreshing gradient colors…'),
          duration: Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _extractGradientColors(int? workId, String? artworkUrl) async {
    final coverUrl = _buildWorkCoverUrl(workId, artworkUrl) ?? artworkUrl;
    if (coverUrl == null) return;

    Uint8List? preloadedBytes;
    if (workId != null && !coverUrl.startsWith('file://')) {
      try {
        final cacheKey = 'work_cover_$workId';
        final cached = await DefaultCacheManager().getFileFromCache(cacheKey);
        if (cached != null && await cached.file.exists()) {
          preloadedBytes = await cached.file.readAsBytes();
        }
      } catch (_) {
      }
    }

    final colors = await ArtworkColorExtractor.extract(
      coverUrl,
      preloadedBytes: preloadedBytes,
    );
    if (mounted && workId == _currentWorkId) {
      setState(() => _gradientColors = colors);
    }
  }

  String? _buildWorkCoverUrl(int? workId, String? artworkUrl) {
    if (artworkUrl != null && artworkUrl.startsWith('file://')) return artworkUrl;
    if (workId == null) return null;
    final authState = ref.read(authProvider);
    final host = authState.host ?? '';
    final token = authState.token ?? '';
    if (host.isEmpty) return null;
    var normalizedHost = host;
    if (!normalizedHost.startsWith('http://') && !normalizedHost.startsWith('https://')) {
      normalizedHost = 'https://$normalizedHost';
    }
    return token.isNotEmpty
        ? '$normalizedHost/api/cover/$workId?token=$token'
        : '$normalizedHost/api/cover/$workId';
  }

  void _handleDragStart(DragStartDetails details) {
    _isDragging = true;
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;
    if (isLandscape) {
      final screenWidth = MediaQuery.sizeOf(context).width;
      final isInTopZone = details.localPosition.dy < 80;
      final isOnCoverSide = details.localPosition.dx < screenWidth * 0.42;
      _isValidDismissDrag = isInTopZone || isOnCoverSide;
    } else {
      _isValidDismissDrag = true;
    }
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    if (!_isValidDismissDrag) return;
    setState(() {
      _dragOffset = max(0.0, _dragOffset + details.delta.dy);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    _isDragging = false;
    if (!_isValidDismissDrag) {
      _isValidDismissDrag = false;
      return;
    }
    _isValidDismissDrag = false;
    final screenHeight = MediaQuery.sizeOf(context).height;
    final threshold = screenHeight * 0.25;

    if (_dragOffset > threshold || (details.primaryVelocity ?? 0) > 500) {
      ref.read(isFullscreenPlayerActiveProvider.notifier).state = false;
      setState(() => _dragOffset = 0);
      Navigator.maybeOf(context)?.pop();
    } else {
      _dismissCtrl
        ..value = (_dragOffset / screenHeight).clamp(0.0, 1.0)
        ..reverse();
    }
  }

  void _onDismissUpdate() {
    if (!mounted) return;
    setState(() {
      _dragOffset = _dismissCtrl.value * MediaQuery.sizeOf(context).height;
    });
  }

  void _handleSeekChanged(double value) {
    final dur = ref.read(durationProvider).value ?? Duration.zero;
    setState(() {
      _isSeekingManually = true;
      _seekValue = value;
      _seekingPosition = Duration(milliseconds: (value * dur.inMilliseconds).round());
    });
  }

  void _handleSeekEnd(double value) {
    final dur = ref.read(durationProvider).value ?? Duration.zero;
    final newPosition = Duration(milliseconds: (value * dur.inMilliseconds).round());
    LogService.instance.debug('[SEEKBAR SEEK] target=${newPosition.inMilliseconds}ms', tag: 'AudioPlayer');
    setState(() => _seekingPosition = newPosition);
    ref.read(audioPlayerControllerProvider.notifier).seekAndPersist(newPosition);

    _listenForSeekCompletion(newPosition);
  }

  /// Called when the user taps a lyric line to seek to its timestamp.
  /// The parent must be notified so it can:
  ///   1. Override the stale [_seekingPosition] (from a previous seekbar
  ///      interaction that hasn't completed yet) with the tapped position.
  ///   2. Invalidate the old [_seekCompletionSub] so it doesn't clear
  ///      [_seekingPosition] prematurely when an unrelated position tick fires.
  ///   3. Optionally [_isSeekingManually] + [_seekValue] so the seekbar
  ///      immediately reflects the tapped position instead of waiting for
  ///      the async [positionProvider] stream to catch up.
  void _onLyricSeek(Duration position) {
    final dur = ref.read(durationProvider).value ?? Duration.zero;
    setState(() {
      _seekingPosition = position;
      _isSeekingManually = true;
      _seekValue = dur.inMilliseconds > 0
          ? position.inMilliseconds / dur.inMilliseconds
          : 0.0;
    });
    _listenForSeekCompletion(position);
  }

  /// Shared helper: subscribe to [positionStream] and wait until the
  /// position reaches [target] (within 200ms), then clear seek state.
  /// Includes a 2s safety fallback in case the stream never catches up.
  /// [_seekGeneration] is incremented to invalidate any previous listener.
  void _listenForSeekCompletion(Duration target) {
    final currentGen = ++_seekGeneration;
    _seekCompletionSub?.cancel();
    final service = ref.read(audioPlayerServiceProvider);
    _seekCompletionSub = service.positionStream.listen((pos) {
      if (currentGen != _seekGeneration) return;
      if ((pos - target).abs() <= const Duration(milliseconds: 200)) {
        _seekCompletionSub?.cancel();
        _seekCompletionSub = null;
        if (mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || currentGen != _seekGeneration) return;
            setState(() { _isSeekingManually = false; _seekingPosition = null; });
          });
        }
      }
    });

    Future.delayed(const Duration(seconds: 2), () {
      if (currentGen != _seekGeneration) return;
      _seekCompletionSub?.cancel();
      _seekCompletionSub = null;
      if (mounted) {
        setState(() { _isSeekingManually = false; _seekingPosition = null; });
      }
    });
  }

  @override
  void dispose() {
    _seekCompletionSub?.cancel();
    _dismissCtrl.dispose();
    StreamingSpeedTracker.instance.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isLandscape = MediaQuery.orientationOf(context) == Orientation.landscape;

    ref.watch(lyricAutoLoaderProvider);
    ref.watch(audioFormatInfoProvider);

    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    if (!_systemUiStyleSet) {
      _systemUiStyleSet = true;
      SystemChrome.setSystemUIOverlayStyle(_darkSystemUi);
    }

    final screenHeight = MediaQuery.sizeOf(context).height;
    final dragProgress = (_dragOffset / screenHeight).clamp(0.0, 1.0);
    final dragOpacity = 1.0 - dragProgress * 0.5;

    return Scaffold(
      backgroundColor:
          (_isDragging || _dismissCtrl.isAnimating) ? Colors.transparent : Colors.black,
      extendBodyBehindAppBar: true,
      body: GestureDetector(
        onVerticalDragStart: _handleDragStart,
        onVerticalDragUpdate: _handleDragUpdate,
        onVerticalDragEnd: _handleDragEnd,
        child: Transform.translate(
          offset: Offset(0, _dragOffset),
          child: Opacity(
            opacity: dragOpacity,
            child: Stack(children: [
              if (currentTrack.valueOrNull != null)
                _buildBlurredBackground(currentTrack.valueOrNull!),

              _buildGradientOverlay(),

              Positioned.fill(
                child: AnimatedOpacity(
                  opacity: _showLyricView ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 350),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.4),
                  ),
                ),
              ),

              SafeArea(
                child: isLandscape
                    ? _buildLandscapeLayout(context, currentTrack, theme, cs)
                    : _buildPortraitLayout(context, currentTrack, theme, cs),
              ),

            ]),
          ),
        ),
      ),
    );
  }

  /// One-time tooltip: "Swipe down to close" — shown once on first fullscreen open.
  Widget _buildSwipeHint() {
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 4),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.keyboard_arrow_down,
                size: 16, color: Colors.white.withValues(alpha: 0.8)),
              const SizedBox(width: 4),
              Text(
                'Swipe down to close',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.8),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Drag handle pill at the very top — visual cue for swipe-to-dismiss.
  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 6, bottom: 2),
      child: Center(
        child: Container(
          width: 36,
          height: 4,
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.35),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ),
    );
  }

  /// Small overlay top bar: back button + AI generate + background toggle + queue button
  Widget _buildTopBar(BuildContext context) {
    final showBlur = ref.watch(showBlurredBackgroundProvider);
    final currentTrack = ref.watch(currentTrackProvider).valueOrNull;
    final localAudioPath = _getLocalAudioPath(currentTrack);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              ref
                  .read(isFullscreenPlayerActiveProvider.notifier)
                  .state = false;
              Navigator.of(context).pop();
            },
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: const CircleBorder(),
            ),
          ),
          const Spacer(),
          if (localAudioPath != null)
            IconButton(
              onPressed: _isTranscribing ? null : _onGenerateAiLyrics,
              icon: _isTranscribing
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white70,
                      ),
                    )
                  : const Icon(Icons.auto_awesome, color: Colors.white),
              tooltip: _isTranscribing
                  ? S.of(context).aiTranscribing
                  : S.of(context).aiGenerateLyrics,
              style: IconButton.styleFrom(
                backgroundColor: _isTranscribing
                    ? Colors.white.withValues(alpha: 0.08)
                    : Colors.white.withValues(alpha: 0.15),
                shape: const CircleBorder(),
              ),
            ),
          if (localAudioPath != null) const SizedBox(width: 4),
          IconButton(
            icon: Icon(
              showBlur ? Icons.blur_on : Icons.blur_off,
              color: Colors.white,
            ),
            onPressed: () => ref
                .read(showBlurredBackgroundProvider.notifier)
                .state = !showBlur,
            tooltip: showBlur ? 'Hide background' : 'Show background',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.info_outline, color: Colors.white),
            onPressed: () => showAudioInfoSheet(context, ref),
            tooltip: 'Audio Information',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.article_outlined, color: Colors.white),
            onPressed: () {
              final track = ref.read(currentTrackProvider).valueOrNull;
              if (track != null) {
                showWorkInfoPanel(context, ref, track);
              }
            },
            tooltip: 'Work Info',
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: const CircleBorder(),
            ),
          ),
          const SizedBox(width: 4),
          IconButton(
            icon: const Icon(Icons.queue_music, color: Colors.white),
            onPressed: () => PlaylistDialog.show(context),
            tooltip: S.of(context).playlistTitle,
            style: IconButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.15),
              shape: const CircleBorder(),
            ),
          ),
        ],
      ),
    );
  }

  /// Full-screen blurred cover background (YouTube Music style).
  /// Can be toggled off via [showBlurredBackgroundProvider] — falls back to
  /// a solid theme-colored background when disabled.
  Widget _buildBlurredBackground(AudioTrack track) {
    final showBlur = ref.watch(showBlurredBackgroundProvider);

    if (!showBlur) {
      return Positioned.fill(
        child: Container(
          color: const Color(0xFF111111),
        ),
      );
    }

    final coverUrl = _buildWorkCoverUrl(track.workId, track.artworkUrl) ??
        track.artworkUrl;
    if (coverUrl == null) return const SizedBox.shrink();

    Widget imageWidget;
    if (coverUrl.startsWith('file://')) {
      imageWidget = Image.file(
        File(coverUrl.replaceFirst('file://', '')),
        fit: BoxFit.cover,
        cacheWidth: 720,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      imageWidget = CachedNetworkImage(
        imageUrl: coverUrl,
        fit: BoxFit.cover,
        memCacheWidth: 720,
        cacheKey: track.workId != null
            ? 'work_cover_${track.workId}'
            : null,
        imageBuilder: (context, imageProvider) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (track.workId != null &&
                _extractedCoverForWorkId != track.workId) {
              _extractedCoverForWorkId = track.workId;
              _extractGradientColors(track.workId, track.artworkUrl);
            }
          });
          return Image(image: imageProvider, fit: BoxFit.cover);
        },
        errorWidget: (_, __, ___) => const SizedBox.shrink(),
        placeholder: (_, __) => const SizedBox.shrink(),
      );
    }

    return Positioned.fill(
      child: RepaintBoundary(
        child: ClipRect(
          child: ImageFiltered(
            imageFilter: ImageFilter.blur(sigmaX: 3, sigmaY: 3),
            child: imageWidget,
          ),
        ),
      ),
    );
  }

  /// Gradient overlay for text readability.
  /// When blurred background is disabled, uses a lighter gradient so the
  /// theme color shows through instead of being drowned in black.
  Widget _buildGradientOverlay() {
    final showBlur = ref.watch(showBlurredBackgroundProvider);

    return Positioned.fill(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: showBlur
                ? const [
                    Color(0xD0000000),
                    Color(0x44000000),
                    Color(0xB3000000),
                  ]
                : const [
                    Color(0xCC000000),
                    Color(0x66000000),
                    Color(0xAA000000),
                  ],
            stops: const [0.0, 0.3, 1.0],
          ),
        ),
      ),
    );
  }

  Widget _buildPortraitLayout(BuildContext context, AsyncValue currentTrack, ThemeData theme, ColorScheme cs) {
    return currentTrack.when(
      data: (track) {
        if (track == null) {
          return Center(
            child: Text(S.of(context).noAudioPlaying,
              style: const TextStyle(color: Colors.white)),
          );
        }

        _onTrackChanged(track);

        final workCoverUrl = _buildWorkCoverUrl(track.workId, track.artworkUrl);

        return Column(children: [
          _buildDragHandle(),
          if (_showSwipeHint)
            _buildSwipeHint(),
          _buildTopBar(context),

          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 350),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              transitionBuilder: (child, animation) {
                return FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween<double>(begin: 0.92, end: 1.0).animate(
                      CurvedAnimation(
                        parent: animation,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                    child: child,
                  ),
                );
              },
              child: _showLyricView
                  ? _PortraitLyricView(
                      key: const ValueKey('PortraitLyricView'),
                      seekingPosition: _seekingPosition,
                      onLyricSeek: _onLyricSeek,
                      gradientColors: _gradientColors,
                      onBackToCover: () => setState(() => _showLyricView = false),
                    )
                  : _buildCoverContent(track, workCoverUrl),
            ),
          ),

          if (!_showLyricView) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: Text(track.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (track.workId != null)
                      _buildFavoriteButton(track.workId!),
                  ],
                ),
                const SizedBox(height: 4),
                if (track.artist != null)
                  Text(track.artist!,
                    style: TextStyle(
                      fontSize: 15,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
              const SizedBox(height: 4),
              Consumer(
                builder: (context, ref, child) {
                  final audioFormat = ref.watch(audioFormatInfoProvider);
                  final dacNameAsync = ref.watch(activeUsbDacNameProvider);
                  final exclusiveStateAsync = ref.watch(exclusiveAudioStateProvider);
                  final showUsbBadge = Platform.isAndroid &&
                      exclusiveStateAsync.when(
                        data: (s) => s.enabled,
                        loading: () => false,
                        error: (_, __) => false,
                      ) &&
                      dacNameAsync.when(
                        data: (n) => n.isNotEmpty,
                        loading: () => false,
                        error: (_, __) => false,
                      );
                  final dacName = dacNameAsync.when(
                    data: (n) => n,
                    loading: () => '',
                    error: (_, __) => '',
                  );
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _AudioInfoBadgeInPlayer(audioFormatAsync: audioFormat),
                      const SizedBox(width: 6),
                      const _OutputDevicePill(),
                      const SizedBox(width: 6),
                      const _StreamingSpeedBadge(),
                      if (showUsbBadge) const SizedBox(width: 6),
                      if (showUsbBadge) _UsbDacBadgeInPlayer(dacName: dacName),
                    ],
                  );
                },
              ),
              ]),
            ),
            const SizedBox(height: 8),
            Consumer(builder: (context, ref, child) {
              final hasLyrics = ref.watch(
                lyricControllerProvider.select((s) => s.lyrics.isNotEmpty),
              );
              return GestureDetector(
                onTap: hasLyrics
                    ? () => setState(() => _showLyricView = true)
                    : null,
                child: LyricDisplay(albumName: track.album),
              );
            }),
          ],

          const SizedBox(height: 8),

          Theme(
            data: theme.copyWith(
              colorScheme: ColorScheme.fromSeed(
                seedColor: cs.primary,
                brightness: Brightness.dark,
              ),
            ),
            child: _PlayerControlsWithPosition(
              isLandscape: false,
              isSeekingManually: _isSeekingManually,
              seekValue: _seekValue,
              onSeekChanged: _handleSeekChanged,
              onSeekEnd: _handleSeekEnd,
              seekingPosition: _seekingPosition,
              workId: track.workId,
              currentProgress: _currentProgress,
              gradientColors: _gradientColors,
              onGradientRefresh: _handleRefreshGradient,
              onMarkPressed: track.workId != null
                  ? () => _showMarkDialog(context, track.workId!, track.title)
                  : null,
              onDetailPressed: track.workId != null
                  ? () => _navigateToWorkDetail(context, track.workId!)
                  : null,
            ),
          ),

          const SizedBox(height: 8),
        ]);
      },
      loading: () => const Center(child: CircularProgressIndicator(color: Colors.white)),
      error: (error, stack) => Center(
        child: Text(S.of(context).errorWithMessage(error.toString()),
          style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Extracted cover content widget with proper key for AnimatedSwitcher transitions.
  Widget _buildCoverContent(AudioTrack track, String? workCoverUrl) {
    return GestureDetector(
      key: const ValueKey('CoverContent'),
      onDoubleTapDown: (details) {
        final xPercent = details.localPosition.dx /
            MediaQuery.of(context).size.width;
        HapticFeedback.mediumImpact();
        if (xPercent < 0.5) {
          ref
              .read(audioPlayerControllerProvider.notifier)
              .seekBackward(const Duration(seconds: 10));
        } else {
          ref
              .read(audioPlayerControllerProvider.notifier)
              .seekForward(const Duration(seconds: 10));
        }
      },
      child: Center(
        child: Consumer(builder: (context, ref, child) {
          final hasLyrics = ref.watch(
            lyricControllerProvider.select((s) => s.lyrics.isNotEmpty),
          );
          return Stack(
            alignment: Alignment.center,
            children: [
              PlayerCoverWidget(
                track: track,
                workCoverUrl: workCoverUrl,
                onTap: hasLyrics
                    ? () => setState(() => _showLyricView = true)
                    : null,
                onSwipeLeft: () {
                  HapticFeedback.lightImpact();
                  ref
                      .read(audioPlayerControllerProvider.notifier)
                      .skipToNext();
                },
                onSwipeRight: () {
                  HapticFeedback.lightImpact();
                  ref
                      .read(audioPlayerControllerProvider.notifier)
                      .skipToPrevious();
                },
              ),
              if (_showLyricHint && hasLyrics)
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: _LyricHintChip(
                    onDismiss: () => setState(() => _showLyricHint = false),
                    onTap: () => setState(() => _showLyricView = true),
                  ),
                ),
            ],
          );
        }),
      ),
    );
  }

  Widget _buildLandscapeLayout(BuildContext context, AsyncValue currentTrack, ThemeData theme, ColorScheme cs) {
    return currentTrack.when(
      data: (track) {
        if (track == null) {
          return Center(
            child: Text(S.of(context).noAudioPlaying,
              style: const TextStyle(color: Colors.white)),
          );
        }

        _onTrackChanged(track);

        final workCoverUrl = _buildWorkCoverUrl(track.workId, track.artworkUrl);

        return Column(children: [
          _buildDragHandle(),
          if (_showSwipeHint)
            _buildSwipeHint(),
          _buildTopBar(context),
          Expanded(
            child: Row(children: [
              Expanded(
                flex: 2,
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final maxCoverSize = constraints.maxWidth * 0.7;
                    final coverSize = maxCoverSize.clamp(100.0,
                        constraints.maxHeight * 0.55);

                    return Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        ConstrainedBox(
                          constraints: BoxConstraints(
                            maxHeight: coverSize,
                            maxWidth: coverSize,
                          ),
                          child: PlayerCoverWidget(
                              track: track,
                              workCoverUrl: workCoverUrl,
                              isLandscape: true,
                              onSwipeLeft: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(audioPlayerControllerProvider
                                        .notifier)
                                    .skipToNext();
                              },
                              onSwipeRight: () {
                                HapticFeedback.lightImpact();
                                ref
                                    .read(audioPlayerControllerProvider
                                        .notifier)
                                    .skipToPrevious();
                              },
                            ),
                        ),
                        const SizedBox(height: 16),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(track.title,
                                  style: const TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                  textAlign: TextAlign.center,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis),
                              ),
                              if (track.workId != null) ...[const SizedBox(width: 6), _buildFavoriteButton(track.workId!)],
                            ],
                          ),
                        ),
                        if (track.artist != null) ...[
                          const SizedBox(height: 4),
                          Text(track.artist!,
                            style: TextStyle(
                              fontSize: 14,
                              color: Colors.white.withValues(alpha: 0.8),
                            ),
                            textAlign: TextAlign.center,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                        ],
                        const SizedBox(height: 4),
                        Consumer(
                          builder: (context, ref, child) {
                            final audioFormat = ref.watch(audioFormatInfoProvider);
                            final dacNameAsync = ref.watch(activeUsbDacNameProvider);
                            final exclusiveStateAsync = ref.watch(exclusiveAudioStateProvider);
                            final showUsbBadge = Platform.isAndroid &&
                                exclusiveStateAsync.when(
                                  data: (s) => s.enabled,
                                  loading: () => false,
                                  error: (_, __) => false,
                                ) &&
                                dacNameAsync.when(
                                  data: (n) => n.isNotEmpty,
                                  loading: () => false,
                                  error: (_, __) => false,
                                );
                            final dacName = dacNameAsync.when(
                              data: (n) => n,
                              loading: () => '',
                              error: (_, __) => '',
                            );
                            return Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _AudioInfoBadgeInPlayer(audioFormatAsync: audioFormat),
                                const SizedBox(width: 6),
                                const _OutputDevicePill(),
                                const SizedBox(width: 6),
                                const _StreamingSpeedBadge(),
                                if (showUsbBadge) const SizedBox(width: 6),
                                if (showUsbBadge) _UsbDacBadgeInPlayer(dacName: dacName),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 12),
                        Theme(
                          data: theme.copyWith(
                            colorScheme: ColorScheme.fromSeed(
                              seedColor: cs.primary,
                              brightness: Brightness.dark,
                            ),
                          ),
                          child: _PlayerControlsWithPosition(
                            isLandscape: true,
                            isSeekingManually: _isSeekingManually,
                            seekValue: _seekValue,
                            onSeekChanged: _handleSeekChanged,
                            onSeekEnd: _handleSeekEnd,
                            seekingPosition: _seekingPosition,
                            workId: track.workId,
                            currentProgress: _currentProgress,
                            gradientColors: _gradientColors,
                            onGradientRefresh: _handleRefreshGradient,
                            onMarkPressed: track.workId != null
                                ? () => _showMarkDialog(
                                    context, track.workId!, track.title)
                                : null,
                            onDetailPressed: track.workId != null
                                ? () => _navigateToWorkDetail(
                                    context, track.workId!)
                                : null,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              Container(width: 1, color: Colors.white.withValues(alpha: 0.15)),
              Expanded(
                flex: 3,
                child: Consumer(builder: (context, ref, child) {
                  final isEmpty = ref.watch(
                    lyricControllerProvider.select((s) => s.lyrics.isEmpty),
                  );
                  if (isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.lyrics_outlined,
                            size: 56,
                            color: Colors.white.withValues(alpha: 0.4)),
                          const SizedBox(height: 16),
                          Text(
                            S.of(context).noSubtitlesAvailable,
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.7),
                              fontSize: 15),
                          ),
                          const SizedBox(height: 24),
                          OutlinedButton.icon(
                            onPressed: _isTranscribing
                                ? null
                                : _onGenerateAiLyrics,
                            icon: _isTranscribing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white70,
                                    ),
                                  )
                                : const Icon(Icons.auto_awesome,
                                    size: 18),
                            label: Text(
                                _isTranscribing
                                    ? S.of(context).aiTranscribing
                                    : S.of(context).aiGenerateLyrics),
                            style: OutlinedButton.styleFrom(
                              foregroundColor:
                                  Colors.white.withValues(alpha: 0.9),
                              side: BorderSide(
                                color: Colors.white
                                    .withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }
                  return Stack(children: [
                    FullLyricDisplay(
                      seekingPosition: _seekingPosition,
                      onLyricSeek: _onLyricSeek,
                      gradientColors: _gradientColors,
                    ),
                    const Positioned(
                        right: 16, bottom: 16, child: _TranslateButton()),
                  ]);
                }),
              ),
            ]),
          ),
        ]);
      },
      loading: () => const Center(
        child: CircularProgressIndicator(color: Colors.white)),
      error: (error, stack) => Center(
        child: Text(S.of(context).errorWithMessage(error.toString()),
          style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  /// Build the favorite toggle heart button.
  Widget _buildFavoriteButton(int workId) {
    return SizedBox(
      width: 32,
      height: 32,
      child: IconButton(
        onPressed: _isFavLoading ? null : () => _toggleFavorite(workId),
        icon: _isFavLoading
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white70,
                ),
              )
            : Icon(
                _isFavorited ? Icons.favorite : Icons.favorite_border,
                color: _isFavorited ? Colors.red[400] : Colors.white70,
              ),
        iconSize: 20,
        padding: EdgeInsets.zero,
        tooltip: _isFavorited ? 'Remove from favorites' : 'Add to favorites',
      ),
    );
  }

  Future<void> _showMarkDialog(BuildContext context, int workId, String? workTitle) async {
    final manager = WorkBookmarkManager(ref: ref, context: context);
    await manager.showMarkDialog(
      workId: workId,
      currentProgress: _currentProgress,
      currentRating: _currentRating,
      workTitle: workTitle,
      onChanged: (newProgress, newRating) {
        if (mounted) setState(() { _currentProgress = newProgress; _currentRating = newRating; });
      },
    );
  }

  Future<void> _navigateToWorkDetail(BuildContext context, int workId) async {
    try {
      if (context.mounted) {
        showDialog(context: context, barrierDismissible: false,
          builder: (context) => const Center(child: CircularProgressIndicator()));
      }
      final apiService = ref.read(kikoeruApiServiceProvider);
      final workData = await apiService.getWork(workId);
      final work = Work.fromJson(workData);
      if (context.mounted) {
        Navigator.of(context).pop();
        Navigator.of(context).push(MaterialPageRoute(
          builder: (context) => WorkDetailScreen(work: work)));
      }
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).loadFailedWithError(e.toString()))));
      }
    }
  }
}

/// Audio output device pill — auto-detects speaker / wired headphone / USB DAC / Bluetooth.
/// Watches [activeOutputDeviceProvider] for reactive updates (plug/unplug).
/// Features a brief glow highlight animation when the output device changes.
class _OutputDevicePill extends ConsumerStatefulWidget {
  const _OutputDevicePill();

  @override
  ConsumerState<_OutputDevicePill> createState() => _OutputDevicePillState();
}

class _OutputDevicePillState extends ConsumerState<_OutputDevicePill>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowCtrl;
  late final Animation<double> _glowAnim;
  String _lastDeviceType = '';

  @override
  void initState() {
    super.initState();
    _glowCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );
    _glowAnim = CurvedAnimation(
      parent: _glowCtrl,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _glowCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final deviceTypeAsync = ref.watch(activeOutputDeviceProvider);
    return deviceTypeAsync.when(
      data: (type) {
        if (type != _lastDeviceType && _lastDeviceType.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _glowCtrl.forward(from: 0.0);
          });
        }
        _lastDeviceType = type;

        final (IconData icon, String label) = switch (type) {
          'usb_dac' || 'usb_detected' => (Icons.usb, 'USB DAC'),
          'wired_headphones' || 'headphones' => (Icons.headphones, 'Earphone'),
          'bluetooth' => (Icons.bluetooth, 'Bluetooth'),
          _ => (Icons.speaker, 'Speaker'),
        };
        final cs = Theme.of(context).colorScheme;

        return AnimatedBuilder(
          animation: _glowAnim,
          builder: (context, child) {
            final glow = (1.0 - _glowCtrl.value).clamp(0.0, 1.0);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(4),
                boxShadow: glow > 0.01
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: glow * 0.45),
                          blurRadius: 4 + glow * 8,
                          spreadRadius: glow * 2,
                        ),
                      ]
                    : null,
              ),
              child: child,
            );
          },
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeInCubic,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: ScaleTransition(
                  scale: Tween<double>(begin: 0.85, end: 1.0).animate(
                    CurvedAnimation(
                      parent: animation,
                      curve: Curves.easeOutBack,
                    ),
                  ),
                  child: child,
                ),
              );
            },
            child: Row(
              key: ValueKey('output_$type'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 9, color: cs.onSurfaceVariant),
                const SizedBox(width: 3),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                  ),
                ),
              ],
            ),
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Real-time streaming speed pill — shows estimated download speed.
/// Only visible when actively streaming a network URL.
class _StreamingSpeedBadge extends ConsumerStatefulWidget {
  const _StreamingSpeedBadge();

  @override
  ConsumerState<_StreamingSpeedBadge> createState() => _StreamingSpeedBadgeState();
}

class _StreamingSpeedBadgeState extends ConsumerState<_StreamingSpeedBadge> {
  SpeedIndicatorState? _lastState;

  @override
  Widget build(BuildContext context) {
    final speedAsync = ref.watch(streamingSpeedProvider);
    return speedAsync.when(
      data: (state) {
        if (!state.isVisible) return const SizedBox.shrink();

        final cs = Theme.of(context).colorScheme;

        final (Color bg, Color fg) = switch (state.state) {
          SpeedIndicatorState.streaming => (
            Colors.green.withValues(alpha: 0.35),
            Colors.greenAccent,
          ),
          SpeedIndicatorState.slow => (
            Colors.orange.withValues(alpha: 0.35),
            Colors.orangeAccent,
          ),
          SpeedIndicatorState.buffering => (
            cs.error.withValues(alpha: 0.35),
            cs.error,
          ),
          SpeedIndicatorState.cached => (
            cs.surfaceContainerHighest.withValues(alpha: 0.8),
            cs.onSurfaceVariant,
          ),
          SpeedIndicatorState.hidden => (Colors.transparent, Colors.transparent),
        };

        final label = switch (state.state) {
          SpeedIndicatorState.cached => 'Cached',
          _ => state.displaySpeed,
        };

        final isNew = _lastState == null ||
            (_lastState == SpeedIndicatorState.hidden &&
                state.state != SpeedIndicatorState.hidden);
        _lastState = state.state;

        Widget pill = Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 9,
              color: fg,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        );

        if (isNew) {
          pill = TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.7, end: 1.0),
            duration: const Duration(milliseconds: 300),
            curve: Curves.easeOutBack,
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child: pill,
          );
        }

        return pill;
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Small USB DAC badge for the fullscreen player.
class _UsbDacBadgeInPlayer extends StatelessWidget {
  final String dacName;
  const _UsbDacBadgeInPlayer({required this.dacName});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.usb, size: 9, color: cs.onPrimaryContainer),
          const SizedBox(width: 3),
          Text(
            dacName.length > 12 ? '${dacName.substring(0, 11)}…' : dacName,
            style: tt.labelSmall?.copyWith(
              fontSize: 9,
              color: cs.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Neutron/UAPP-style audio info badge — shows codec, bit depth, sample rate,
/// and estimated bitrate in compact pills.
class _AudioInfoBadgeInPlayer extends StatelessWidget {
  final AsyncValue<AudioFormatInfo?> audioFormatAsync;

  const _AudioInfoBadgeInPlayer({required this.audioFormatAsync});

  @override
  Widget build(BuildContext context) {
    return audioFormatAsync.when(
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;

        final pills = <Widget>[
          _InfoPill(
            label: info.codec.toUpperCase(),
            color: cs.primary.withValues(alpha: 0.7),
            textColor: cs.onPrimary,
          ),
        ];

        if (info.bitDepth != null) {
          pills.add(const SizedBox(width: 4));
          pills.add(_InfoPill(
            label: '${info.bitDepth}bit',
            color: cs.tertiary.withValues(alpha: 0.7),
            textColor: cs.onTertiary,
          ));
        }

        if (info.sampleRate != null) {
          pills.add(const SizedBox(width: 4));
          pills.add(_InfoPill(
            label:
                '${(info.sampleRate! / 1000).toStringAsFixed(info.sampleRate! % 1000 == 0 ? 0 : 1)}kHz',
            color: cs.secondary.withValues(alpha: 0.7),
            textColor: cs.onSecondary,
          ));
        }

        final bitrate = info.estimatedBitrateKbps;
        if (bitrate != null) {
          pills.add(const SizedBox(width: 4));
          pills.add(_InfoPill(
            label: bitrate >= 1000
                ? '${(bitrate / 1000).toStringAsFixed(1)}Mbps'
                : '${bitrate}kbps',
            color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
            textColor: cs.onSurfaceVariant,
          ));
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: pills,
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Single pill in the audio info badge row.
class _InfoPill extends StatelessWidget {
  final String label;
  final Color color;
  final Color textColor;

  const _InfoPill({
    required this.label,
    required this.color,
    required this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          color: textColor,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}