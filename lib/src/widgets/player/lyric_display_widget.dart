import 'dart:async';
import 'dart:ui' show ImageFilter, PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/lyric.dart';
import '../../providers/audio_provider.dart';
import '../../providers/lyric_provider.dart';
import '../../providers/player_lyric_style_provider.dart';
import '../../providers/settings_provider.dart';
import '../../../l10n/app_localizations.dart';

/// 小字幕显示组件（在封面下方显示当前字幕）
class LyricDisplay extends ConsumerWidget {
  final String? albumName;

  const LyricDisplay({super.key, this.albumName});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentLyric = ref.watch(currentLyricTextProvider);
    final lyricState = ref.watch(lyricControllerProvider);
    final lyricSettings = ref.watch(playerLyricSettingsProvider);

    if (lyricState.lyrics.isNotEmpty) {
      return AnimatedSize(
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeInOut,
        child: Container(
          constraints: const BoxConstraints(minHeight: 23),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
          child: Center(
            child: Text(
              currentLyric ?? '♪',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.bold,
                    height: lyricSettings.smallLineHeight,
                    fontSize: lyricSettings.smallFontSize,
                  ),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    if (albumName != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        child: Text(
          albumName!,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      );
    }

    return const SizedBox.shrink();
  }
}

/// Auto-translate notification banner phase.
enum _BannerPhase { hidden, translating, done }

/// ===================================================================
/// Focus Lyrics — Full-screen lyric display
///
/// Apple Music-inspired lyric display:
///   - Active line: full scale, full opacity, bold, high contrast
///   - Nearby lines: progressively smaller scale & lower opacity
///   - Far lines: very faint (with blur)
///   - Smooth 300ms transitions via AnimatedOpacity / AnimatedScale
///   - Lyrics are left-aligned for better readability
///   - No background card decorations — purely typographic focus
/// ===================================================================
class FullLyricDisplay extends ConsumerStatefulWidget {
  final Duration? seekingPosition;
  final bool isPortrait;
  final bool isLocked;
  final VoidCallback? onLongPress;

  const FullLyricDisplay({
    super.key,
    this.seekingPosition,
    this.isPortrait = false,
    this.isLocked = false,
    this.onLongPress,
  });

  @override
  ConsumerState<FullLyricDisplay> createState() => _FullLyricDisplayState();
}

class _FullLyricDisplayState extends ConsumerState<FullLyricDisplay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  int? _currentLyricIndex;
  List<LyricLine>? _lastRawLyrics; // track change detection
  bool _autoScroll = true;
  bool _autoScrollPausedByDrag = false;
  bool _isUserScrolling = false;
  double _dragStartOffset = 0;
  Timer? _indicatorTimer;
  String? _indicatorLabel;
  Timer? _autoScrollTimer;

  // Auto-translate notification banner state
  _BannerPhase _bannerPhase = _BannerPhase.hidden;
  Timer? _bannerTimer;
  String _targetLanguageName = '';

  static const Duration _animDuration = Duration(milliseconds: 300);
  static const Curve _animCurve = Curves.easeOutCubic;

  @override
  void dispose() {
    _scrollController.dispose();
    _indicatorTimer?.cancel();
    _autoScrollTimer?.cancel();
    _bannerTimer?.cancel();
    _itemKeys.clear();
    super.dispose();
  }

  /// Set indicator label WITHOUT setState — safe to call during build().
  void _setIndicatorDuringBuild(String label) {
    _indicatorTimer?.cancel();
    _indicatorLabel = label;
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _indicatorLabel = null);
    });
  }

  void _showIndicator(String label) {
    _indicatorTimer?.cancel();
    setState(() => _indicatorLabel = label);
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _indicatorLabel = null);
    });
  }

  GlobalKey _getKeyForIndex(int index) {
    return _itemKeys.putIfAbsent(index, () => GlobalKey());
  }

  /// Find current lyric index by walking backwards (last startTime <= position)
  int _getCurrentLyricIndex(Duration position, List<LyricLine> lyrics) {
    for (int i = lyrics.length - 1; i >= 0; i--) {
      if (position >= lyrics[i].startTime) return i;
    }
    return -1;
  }

  /// Scroll to center the lyric at [index] in the viewport.
  ///
  /// Uses [Scrollable.ensureVisible] when the item is already rendered.
  /// When the item is off-screen (ListView virtualization), estimates the
  /// scroll offset to jump there first, then fine-tunes after the item renders.
  void _scrollToLyric(int index, {bool animate = true}) {
    if (!_autoScroll || !_scrollController.hasClients) return;

    final key = _getKeyForIndex(index);
    final itemContext = key.currentContext;

    if (itemContext != null) {
      // Item already rendered — fine-tune to exact center.
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.48,
        duration: animate ? _animDuration : Duration.zero,
        curve: _animCurve,
      );
    } else {
      // Item not rendered yet (ListView virtualization).
      // Jump to estimated position first — this forces ListView to build
      // the target item. Then fine-tune with smooth animation.
      // Uses jumpTo (no animation) to avoid competing scroll animations.
      // Note: can't use cached mediaQueryHeight here because this method
      // runs outside build() scope — called from postFrameCallback.
      final centrePadding = MediaQuery.of(context).size.height * 0.38;
      // Typical lyric item height: fontSize~20 × lineHeight~1.5 + vertical padding 28
      const approxItemHeight = 58.0;
      final targetOffset = (index * approxItemHeight) - centrePadding;
      final clamped = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.jumpTo(clamped);

      // After the item is rendered, animate to exact center.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final ctx = key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            alignment: 0.48,
            duration: animate ? _animDuration : Duration.zero,
            curve: _animCurve,
          );
        }
      });
    }
  }

  /// Tapping a lyric line seeks to that timestamp
  void _onLyricTap(int index) {
    final lyricState = ref.read(lyricControllerProvider);
    final displayLyrics = lyricState.displayLyrics;
    if (index < 0 || index >= displayLyrics.length) return;

    final targetTime = displayLyrics[index].startTime;
    ref
        .read(audioPlayerControllerProvider.notifier)
        .seekAndPersist(targetTime);

    _autoScrollTimer?.cancel();
    _autoScrollPausedByDrag = false;
    setState(() => _autoScroll = false);
    _showIndicator('Manual Scroll');
    _autoScrollTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        setState(() => _autoScroll = true);
        _showIndicator('Auto Scroll');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(lyricControllerProvider);
    final position = ref.watch(positionProvider);
    final lyricSettings = ref.watch(playerLyricSettingsProvider);
    final autoTranslateEnabled = ref.watch(autoTranslateLyricsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final mediaQueryHeight = MediaQuery.of(context).size.height;
    final paddingTop = MediaQuery.of(context).padding.top;

    // ---- Auto-translate banner listener -------------------------------
    // Detect auto-translate state transitions (only when feature is enabled)
    ref.listen(lyricControllerProvider, (prev, next) {
      if (!autoTranslateEnabled || prev == null) return;

      if (next.isTranslating &&
          !prev.isTranslating &&
          _bannerPhase == _BannerPhase.hidden) {
        // Auto-translation just started → show "Translating…" banner
        _targetLanguageName = _nativeLanguageName(
          PlatformDispatcher.instance.locale.languageCode,
        );
        setState(() => _bannerPhase = _BannerPhase.translating);
      } else if (!next.isTranslating &&
          next.isTranslated &&
          prev.isTranslating &&
          !prev.isTranslated &&
          _bannerPhase == _BannerPhase.translating) {
        // Auto-translation just completed → show "Translated ✓" for 2s
        setState(() => _bannerPhase = _BannerPhase.done);
        _bannerTimer?.cancel();
        _bannerTimer = Timer(const Duration(seconds: 2), () {
          if (mounted) setState(() => _bannerPhase = _BannerPhase.hidden);
        });
      }
    });

    // ---- Data -----------------------------------------------------------
    final displayLyrics = lyricState.displayLyrics;
    final displayPosition = position.when(
      data: (pos) => widget.seekingPosition ?? pos,
      loading: () => Duration.zero,
      error: (_, __) => Duration.zero,
    );
    final currentIndex =
        _getCurrentLyricIndex(displayPosition, displayLyrics);

    // ---- Track change detection ----------------------------------------
    // When the raw lyrics list reference changes (track change), reset
    // _currentLyricIndex so auto-scroll always triggers for the new track.
    if (lyricState.lyrics != _lastRawLyrics) {
      _lastRawLyrics = lyricState.lyrics;
      _currentLyricIndex = null;
      _autoScrollPausedByDrag = false;
      _autoScroll = true;
    }

    // ---- Auto-scroll side-effect (triggered only on line change) --------
    if (currentIndex != _currentLyricIndex && currentIndex >= 0) {
      _currentLyricIndex = currentIndex;
      // Auto-resume auto-scroll when lyric progresses (if paused by drag).
      // This mimics Apple Music: manual scroll pauses auto-scroll until the
      // next lyric line naturally arrives.
      if (_autoScrollPausedByDrag) {
        _autoScrollPausedByDrag = false;
        _autoScroll = true;
        _setIndicatorDuringBuild('Auto Scroll');
      }
      final animate = widget.seekingPosition == null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollToLyric(currentIndex, animate: animate);
      });
    }

    // ---- Empty / loading / error ----------------------------------------
    if (displayLyrics.isEmpty) {
      return position.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => Center(child: Text(S.of(context).loadFailed)),
        data: (_) => Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.lyrics_outlined, size: 64,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              const SizedBox(height: 16),
              Text(S.of(context).noSubtitlesAvailable,
                  style: textTheme.bodyLarge
                      ?.copyWith(color: colorScheme.onSurfaceVariant)),
            ],
          ),
        ),
      );
    }

    // ---- Focus Lyrics UI ------------------------------------------------
    // Large top/bottom padding ensures the active line sits at the visual
    // centre even for the first / last lyrics.
    final centrePadding = mediaQueryHeight * 0.38;

    return Stack(
      children: [
        // ---- Auto-translate notification banner -----------------------
        // AnimatedSize at top: grows downward when appearing (shrink-down),
        // collapses upward when hiding (shrink-up).
        Positioned(
          top: paddingTop + 4,
          left: 0,
          right: 0,
          child: IgnorePointer(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: _bannerPhase != _BannerPhase.hidden
                  ? _buildAutoTranslateBanner()
                  : const SizedBox(width: double.infinity, height: 0),
            ),
          ),
        ),

        GestureDetector(
          onLongPress: widget.onLongPress,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              // Only pause auto-scroll for user-initiated drags (not programmatic
              // scrolls).  Only pause if the user actually scrolled > 200 px
              // (threshold), so tiny accidental scrolls don't disrupt playback.
              if (notification is ScrollStartNotification &&
                  notification.dragDetails != null && mounted) {
                _isUserScrolling = true;
                _dragStartOffset = notification.metrics.pixels;
              } else if (notification is ScrollEndNotification) {
                _isUserScrolling = false;
              } else if (notification is ScrollUpdateNotification &&
                  _isUserScrolling &&
                  _autoScroll &&
                  mounted &&
                  (notification.metrics.pixels - _dragStartOffset).abs() >
                      200) {
                _autoScroll = false;
                _autoScrollPausedByDrag = true;
                _showIndicator('Manual Scroll');
              }
              return false;
            },
            child: ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(
              left: 28,
              right: 20,
              top: centrePadding,
              bottom: centrePadding,
            ),
            itemCount: displayLyrics.length,
            // itemBuilder is called only for visible items.  Properties are
            // derived from `distance` so that the same number & type of widgets
            // are returned every time — only the animated values change.
                  itemBuilder: (context, index) {
              final lyric = displayLyrics[index];
              final distance = (index - currentIndex).abs();
              final isActive = distance == 0;

              // ---- Visual parameters by distance ------------------------
              double opacity;
              double scale;
              Color textColor;
              FontWeight fontWeight;
              double fontSize;

              // Active line: full emphasis — Apple Music bold style
              if (isActive) {
                opacity = 1.0;
                scale = 1.0;
                textColor = colorScheme.onSurface;
                fontWeight = FontWeight.w800;
                fontSize = lyricSettings.fullActiveFontSize;
              }
              // ±1: nearby — still bold
              else if (distance == 1) {
                opacity = 0.85;
                scale = 0.95;
                textColor = colorScheme.onSurfaceVariant;
                fontWeight = FontWeight.w600;
                fontSize = lyricSettings.fullInactiveFontSize;
              }
              // ±2: further
              else if (distance == 2) {
                opacity = 0.65;
                scale = 0.90;
                textColor = colorScheme.onSurfaceVariant;
                fontWeight = FontWeight.w500;
                fontSize = lyricSettings.fullInactiveFontSize - 1;
              }
              // ±3: fading
              else if (distance == 3) {
                opacity = 0.45;
                scale = 0.85;
                textColor = colorScheme.onSurfaceVariant;
                fontWeight = FontWeight.w400;
                fontSize = lyricSettings.fullInactiveFontSize - 2;
              }
              // >3: faint + subtle blur (still readable for tap-to-seek)
              else {
                opacity = 0.35;
                scale = 0.80;
                textColor = colorScheme.onSurfaceVariant;
                fontWeight = FontWeight.w300;
                fontSize = lyricSettings.fullInactiveFontSize - 3;
              }

              // ---- Build the lyric row ----------------------------------
              Widget row = GestureDetector(
                key: _getKeyForIndex(index),
                onTap: widget.isLocked ? null : () => _onLyricTap(index),
                onLongPress: widget.onLongPress,
                child: AnimatedOpacity(
                  opacity: opacity,
                  duration: _animDuration,
                  curve: _animCurve,
                  child: AnimatedScale(
                    scale: scale,
                    duration: _animDuration,
                    curve: _animCurve,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: AnimatedDefaultTextStyle(
                        duration: _animDuration,
                        curve: _animCurve,
                        style: (textTheme.bodyLarge ?? const TextStyle()).copyWith(
                          color: textColor,
                          fontWeight: fontWeight,
                          fontSize: fontSize,
                          height: lyricSettings.fullLineHeight,
                        ),
                        child: Text(
                          lyric.text,
                          textAlign: TextAlign.left,
                        ),
                      ),
                    ),
                  ),
                ),
              );

              // Apply subtle blur for far-away lines — just enough to
              // visually de-emphasise without hiding for tap-to-seek.
              if (distance > 3) {
                row = ClipRect(
                  child: ImageFiltered(
                    imageFilter: ImageFilter.blur(sigmaX: 0.6, sigmaY: 0.6),
                    child: row,
                  ),
                );
              }

              return row;
            },
          ),
        ),
      ),
        // -----------------------------------------------------------------
        // Scroll-mode indicator — appears briefly when auto-scroll toggles.
        // Positioned at top-center, auto-hides after 2 seconds.
        // -----------------------------------------------------------------
        if (_indicatorLabel != null)
          Positioned(
            top: paddingTop + 60,
            left: 0,
            right: 0,
            child: IgnorePointer(
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        _autoScroll
                            ? Icons.vertical_align_center
                            : Icons.touch_app,
                        size: 14,
                        color: Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _indicatorLabel ?? '',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// Build the auto-translate notification pill at the top of the lyric view.
  Widget _buildAutoTranslateBanner() {
    final isTranslating = _bannerPhase == _BannerPhase.translating;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isTranslating) ...[
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.white70,
              ),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                S.of(context).autoTranslateBannerTranslating(_targetLanguageName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ] else ...[
            const Icon(Icons.check_circle_outline,
                size: 16, color: Color(0xFF81C784)),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                S.of(context).autoTranslateBannerDone(_targetLanguageName),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Map language codes to their native display names.
  String _nativeLanguageName(String code) {
    switch (code) {
      case 'en':
        return 'English';
      case 'ja':
        return '日本語';
      case 'zh':
      case 'zh_CN':
        return '简体中文';
      case 'zh_TW':
      case 'zh_HK':
        return '繁體中文';
      case 'ru':
        return 'Русский';
      case 'ko':
        return '한국어';
      case 'id':
        return 'Bahasa Indonesia';
      case 'de':
        return 'Deutsch';
      case 'fr':
        return 'Français';
      case 'es':
        return 'Español';
      default:
        return code;
    }
  }
}
