import 'dart:async';
import 'dart:ui' show PlatformDispatcher;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
/// Rata kiri lyric display:
///   - Active line: bold (w800), karaoke left-to-right sweep + pill background
///   - Non-active lines: uniform — same position, same size, same opacity
///   - Karaoke progress spans entire wrapped text block as one unit
///   - Smooth 300ms transitions via AnimatedDefaultTextStyle
///   - Lyrics are left-aligned for better readability
///   - No background card decorations — purely typographic focus
///
/// Performance: Position tracking via ref.listenManual (no rebuild). Only
/// setState() is called when the active lyric index actually changes (~3s
/// intervals) instead of rebuilding the entire ListView every 200ms.
/// ===================================================================
class FullLyricDisplay extends ConsumerStatefulWidget {
  final Duration? seekingPosition;
  final bool isPortrait;
  final bool isLocked;
  final VoidCallback? onLongPress;
  final ValueChanged<Duration>? onLyricSeek;
  final List<Color>? gradientColors;

  const FullLyricDisplay({
    super.key,
    this.seekingPosition,
    this.isPortrait = false,
    this.isLocked = false,
    this.onLongPress,
    this.onLyricSeek,
    this.gradientColors,
  });

  @override
  ConsumerState<FullLyricDisplay> createState() => _FullLyricDisplayState();
}

class _FullLyricDisplayState extends ConsumerState<FullLyricDisplay> {
  final ScrollController _scrollController = ScrollController();
  final Map<int, GlobalKey> _itemKeys = {};
  List<LyricLine>? _lastRawLyrics; // track change detection
  bool _autoScroll = true;
  bool _autoScrollPausedByDrag = false;
  bool _isUserScrolling = false;
  double _dragStartOffset = 0;
  Timer? _autoScrollTimer;

  /// Index of the currently active (highlighted) lyric line.
  /// Updated by [_onPositionChanged] which runs on every position tick
  /// (~200ms) via [ref.listenManual]. Only triggers [setState] when the
  /// value actually changes, avoiding unnecessary rebuilds of the ListView.
  int _activeIndex = -1;

  /// Whether [_activeIndex] has been initialized from the current position.
  /// Prevents redundant work in [build()] on subsequent frames.
  bool _activeIndexInitialized = false;

  // Indicator overlay — ValueNotifier so AnimatedBuilder can rebuild
  // the indicator independently without triggering full widget rebuild.
  final ValueNotifier<String?> _indicatorNotifier = ValueNotifier(null);
  Timer? _indicatorTimer;

  // Seek grace period — after seeking ends, cache the seek target so
  // the display doesn't revert to stale position while audio catches up.
  Duration? _cachedSeekPosition;
  bool _seekGraceActive = false;
  Timer? _seekGraceTimer; // safety net: forces grace period to end after 1s

  // Scroll generation counter — incremented on every new scroll attempt.
  // Pending retries from _retryScrollToItem check this and bail if a newer
  // scroll has superseded them (prevents stale retries during rapid seeks).
  int _scrollGeneration = 0;

  // Auto-translate notification banner state
  _BannerPhase _bannerPhase = _BannerPhase.hidden;
  Timer? _bannerTimer;
  String _targetLanguageName = '';

  static const Duration _animDuration = Duration(milliseconds: 300);
  static const Curve _animCurve = Curves.easeOutCubic;

  // Karaoke TextPainter cache — avoids TextPainter.layout() on every 200ms tick
  String? _karaokeCacheKey;
  _KaraokeLayout? _karaokeLayout;

  // Auto-translate listener state — synced in build() for the
  // initState-registered listener to read.
  bool _autoTranslateEnabled = false;

  @override
  void initState() {
    super.initState();
    // Register auto-translate listener ONCE
    ref.listenManual<LyricState>(lyricControllerProvider, _onAutoTranslateChanged);

    // Position listener — runs on every tick (~200ms) but does NOT rebuild
    // the widget. Only calls setState() when the active index changes (~3s).
    ref.listenManual(positionProvider, (prev, next) {
      if (!mounted) return;
      _onPositionChanged(next.valueOrNull ?? Duration.zero);
    });
  }

  @override
  void didUpdateWidget(FullLyricDisplay oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Detect seek START: when seekingPosition transitions from null → value.
    if (widget.seekingPosition != null &&
        oldWidget.seekingPosition == null) {
      _cachedSeekPosition = widget.seekingPosition;
      _seekGraceActive = true;
      _activeIndex = -1; // force index change detection on next tick
      _seekGraceTimer?.cancel();
      _seekGraceTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _seekGraceActive = false;
          _cachedSeekPosition = null;
        }
      });

      // Force auto-scroll on seek
      _autoScroll = true;
      _autoScrollPausedByDrag = false;
      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _indicatorTimer?.cancel();
    _indicatorNotifier.dispose();
    _seekGraceTimer?.cancel();
    _autoScrollTimer?.cancel();
    _bannerTimer?.cancel();
    _itemKeys.clear();
    super.dispose();
  }

  /// Callback for position changes — runs on every 200ms tick.
  /// Computes the effective position (with seek grace period), updates
  /// [_activeIndex], handles auto-scroll, and calls [setState] ONLY when
  /// the index changes.
  void _onPositionChanged(Duration position) {
    final displayLyrics = ref.read(lyricControllerProvider).displayLyrics;
    if (displayLyrics.isEmpty) return;

    // Compute effective position with seek grace period
    final Duration effectivePos;
    if (widget.seekingPosition != null) {
      effectivePos = widget.seekingPosition!;
      // Keep-alive: re-start grace timer on every tick during seek so it
      // doesn't expire mid-seek. The old Consumer code did this implicitly
      // by running the timer reset block every 200ms.
      _cachedSeekPosition = widget.seekingPosition;
      _seekGraceActive = true;
      _seekGraceTimer?.cancel();
      _seekGraceTimer = Timer(const Duration(seconds: 1), () {
        if (mounted) {
          _seekGraceActive = false;
          _cachedSeekPosition = null;
        }
      });
    } else if (_seekGraceActive && _cachedSeekPosition != null) {
      effectivePos = _cachedSeekPosition!;
      // End grace if position stream has caught up
      if (position >= _cachedSeekPosition!) {
        _seekGraceActive = false;
        _cachedSeekPosition = null;
        _seekGraceTimer?.cancel();
      }
    } else {
      effectivePos = position;
    }

    final newIndex = _getCurrentLyricIndex(effectivePos, displayLyrics);

    if (newIndex < 0) return;

    // Only proceed when the index actually changes — this is the key
    // optimization that avoids rebuilding the ListView on every 200ms tick.
    if (newIndex == _activeIndex) return;

    _activeIndex = newIndex;

    // Resume auto-scroll if previously paused by drag
    if (_autoScrollPausedByDrag) {
      _autoScrollPausedByDrag = false;
      _autoScroll = true;
      _indicatorNotifier.value = 'Auto Scroll';
      _indicatorTimer?.cancel();
      _indicatorTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) _indicatorNotifier.value = null;
      });
    }

    // Schedule auto-scroll if active
    if (_autoScroll) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scrollToLyric(newIndex, animate: widget.seekingPosition == null);
        }
      });
    }

    setState(() {}); // trigger rebuild for item styling change
  }

  /// Callback for [lyricControllerProvider] changes — handles auto-translate
  /// banner transitions. Registered once in [initState]; reads from
  /// [_autoTranslateEnabled] (synced in build()) instead of capturing a
  /// local variable by closure (which would be stale across re-registrations).
  void _onAutoTranslateChanged(LyricState? prev, LyricState next) {
    if (!_autoTranslateEnabled || prev == null) return;

    if (next.isTranslating &&
        !prev.isTranslating &&
        _bannerPhase == _BannerPhase.hidden) {
      _targetLanguageName = _nativeLanguageName(
        PlatformDispatcher.instance.locale.languageCode,
      );
      setState(() => _bannerPhase = _BannerPhase.translating);
    } else if (!next.isTranslating &&
        next.isTranslated &&
        prev.isTranslating &&
        !prev.isTranslated &&
        _bannerPhase == _BannerPhase.translating) {
      setState(() => _bannerPhase = _BannerPhase.done);
      _bannerTimer?.cancel();
      _bannerTimer = Timer(const Duration(seconds: 2), () {
        if (mounted) setState(() => _bannerPhase = _BannerPhase.hidden);
      });
    }
  }

  /// Returns cached [_KaraokeLayout] for the given text/style/width, or
  /// creates and caches a new one. Only the [progress] changes between
  /// 200ms position ticks — layout is reused.
  _KaraokeLayout _getKaraokeLayout(
      String text, TextStyle style, double constraintWidth) {
    final key =
        '"$text"|${style.fontSize}|${style.fontWeight}|${style.height}|${style.letterSpacing}|${style.fontFamily}|$constraintWidth';
    if (_karaokeCacheKey == key && _karaokeLayout != null) {
      return _karaokeLayout!;
    }

    final tp = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: constraintWidth);

    // Precompute per-line boundaries (character index of first char on each line)
    final lineStarts = <int>[0];
    final totalChars = text.length;
    for (int i = 1; i < totalChars; i++) {
      final prevPos = tp.getOffsetForCaret(
          TextPosition(offset: i - 1), Rect.zero);
      final currPos =
          tp.getOffsetForCaret(TextPosition(offset: i), Rect.zero);
      if (currPos.dy != prevPos.dy) {
        lineStarts.add(i);
      }
    }

    // Compute per-line heights
    final lineHeights = <double>[];
    for (int i = 0; i < lineStarts.length; i++) {
      if (i < lineStarts.length - 1) {
        final nextLinePos = tp.getOffsetForCaret(
            TextPosition(offset: lineStarts[i + 1]), Rect.zero);
        final thisLinePos = tp.getOffsetForCaret(
            TextPosition(offset: lineStarts[i]), Rect.zero);
        lineHeights.add(nextLinePos.dy - thisLinePos.dy);
      } else {
        // Last line — estimate from remaining text height
        final thisLinePos = tp.getOffsetForCaret(
            TextPosition(offset: lineStarts[i]), Rect.zero);
        lineHeights.add(tp.height - thisLinePos.dy);
      }
    }

    final layout = _KaraokeLayout(
      textPainter: tp,
      lineStarts: lineStarts,
      lineHeights: lineHeights,
    );

    _karaokeCacheKey = key;
    _karaokeLayout = layout;
    return layout;
  }

  void _showIndicator(String label) {
    _indicatorTimer?.cancel();
    _indicatorNotifier.value = label;
    _indicatorTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) _indicatorNotifier.value = null;
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

  /// Retry scrolling to [key] in postFrameCallback up to [attempts] times.
  ///
  /// Each retry scrolls further DOWN by (multiplier × 30% viewport) from the
  /// original [baseOffset], forcing the ListView to build it. All retries
  /// go DOWN because:
  ///   - Most seeks are forward (position increases) → proportional estimate
  ///     tends to UNDERESTIMATE actual scroll offset (active items have larger
  ///     padding + font), so the target is likely below the estimated position.
  ///   - For backward seeks the proportional estimate is accurate enough that
  ///     the initial jumpTo already renders the target.
  void _retryScrollToItem({
    required GlobalKey key,
    required int attempts,
    required bool animate,
    double baseOffset = 0,
    int scrollGen = 0,
  }) {
    if (!mounted || attempts <= 0) return;
    if (scrollGen != _scrollGeneration) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || scrollGen != _scrollGeneration) return;
      final ctx = key.currentContext;
      if (ctx != null) {
        Scrollable.ensureVisible(
          ctx,
          alignment: 0.48,
          duration: animate ? _animDuration : Duration.zero,
          curve: _animCurve,
        );
      } else {
        final viewH = _scrollController.position.viewportDimension;
        final multiplier = 3 - attempts; // 2→1, 1→2
        final newOff = (baseOffset + viewH * 0.3 * multiplier)
            .clamp(0.0, _scrollController.position.maxScrollExtent);
        _scrollController.jumpTo(newOff);
        _retryScrollToItem(
          key: key,
          attempts: attempts - 1,
          animate: animate,
          baseOffset: baseOffset,
          scrollGen: scrollGen,
        );
      }
    });
  }

  /// Scroll to center the lyric at [index] in the viewport.
  ///
  /// Uses [Scrollable.ensureVisible] when the item is already rendered.
  /// When the item is off-screen (ListView virtualization), estimates the
  /// scroll offset to jump there first, then fine-tunes after the item renders.
  void _scrollToLyric(int index, {bool animate = true}) {
    if (!_autoScroll || !_scrollController.hasClients) return;
    _scrollGeneration++;

    final key = _getKeyForIndex(index);
    final itemContext = key.currentContext;

    if (itemContext != null) {
      Scrollable.ensureVisible(
        itemContext,
        alignment: 0.48,
        duration: animate ? _animDuration : Duration.zero,
        curve: _animCurve,
      );
    } else {
      final centrePadding = MediaQuery.of(context).size.height * 0.38;
      final displayLyrics = ref.read(lyricControllerProvider).displayLyrics;
      final totalItems = displayLyrics.length;
      final maxExtent = _scrollController.position.maxScrollExtent;
      final ratio = totalItems > 0 ? (index + 0.5) / totalItems : 0.0;
      final estimatedOffset = (ratio * maxExtent) - centrePadding;
      final clamped = estimatedOffset.clamp(0.0, maxExtent);
      _scrollController.jumpTo(clamped);

      _retryScrollToItem(
        key: key,
        attempts: 2,
        animate: animate,
        baseOffset: clamped,
        scrollGen: _scrollGeneration,
      );
    }
  }

  /// Tapping a lyric line seeks to that timestamp
  void _onLyricTap(int index) {
    final lyricState = ref.read(lyricControllerProvider);
    final displayLyrics = lyricState.displayLyrics;
    if (index < 0 || index >= displayLyrics.length) return;

    HapticFeedback.lightImpact();

    final targetTime = displayLyrics[index].startTime;

    _seekGraceActive = false;
    _cachedSeekPosition = null;
    _seekGraceTimer?.cancel();

    widget.onLyricSeek?.call(targetTime);

    ref
        .read(audioPlayerControllerProvider.notifier)
        .seekAndPersist(targetTime);

    _autoScroll = true;
    _autoScrollPausedByDrag = false;
    _activeIndex = index;
    _seekGraceActive = true;
    _cachedSeekPosition = targetTime;
    _seekGraceTimer?.cancel();
    _seekGraceTimer = Timer(const Duration(seconds: 1), () {
      if (mounted) {
        _seekGraceActive = false;
        _cachedSeekPosition = null;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final lyricState = ref.watch(lyricControllerProvider);
    final lyricSettings = ref.watch(playerLyricSettingsProvider);
    final autoTranslateEnabled = ref.watch(autoTranslateLyricsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final mediaQueryHeight = MediaQuery.of(context).size.height;
    final paddingTop = MediaQuery.of(context).padding.top;

    // ---- Data -----------------------------------------------------------
    final displayLyrics = lyricState.displayLyrics;
    _autoTranslateEnabled = autoTranslateEnabled; // sync for auto-translate listener

    // ---- Track change detection -----------------------------------------
    if (lyricState.lyrics != _lastRawLyrics) {
      _lastRawLyrics = lyricState.lyrics;
      _autoScrollPausedByDrag = false;
      _autoScroll = true;
      _itemKeys.clear();
      _activeIndex = -1;

      _seekGraceActive = false;
      _cachedSeekPosition = null;
      _seekGraceTimer?.cancel();
      _seekGraceTimer = null;

      _autoScrollTimer?.cancel();
      _autoScrollTimer = null;

      _indicatorNotifier.value = null;
      _indicatorTimer?.cancel();
      _indicatorTimer = null;
    }

    // ---- Empty / loading / error ----------------------------------------
    if (displayLyrics.isEmpty) {
      if (lyricState.isLoading) {
        return _LyricSkeletonShimmer(gradientColors: widget.gradientColors);
      }

      return Consumer(builder: (context, ref, _) {
        final pos = ref.watch(positionProvider);
        return pos.when(
          loading: () => const SizedBox.shrink(),
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
      });
    }

    // ---- Initialize active index on first frame ------------------------
    // ref.listenManual only fires on the NEXT stream emission (~200ms delay),
    // so without this, the first build would show no active lyric line.
    if (!_activeIndexInitialized && displayLyrics.isNotEmpty) {
      final pos = ref.read(positionProvider).valueOrNull;
      if (pos != null) {
        _activeIndex = _getCurrentLyricIndex(pos, displayLyrics);
      }
      _activeIndexInitialized = true;
    }

    // ---- Focus Lyrics UI ------------------------------------------------
    final centrePadding = mediaQueryHeight * 0.38;

    // Compute display index — uses seekingPosition override when active
    final displayIndex = widget.seekingPosition != null
        ? _getCurrentLyricIndex(widget.seekingPosition!, displayLyrics)
        : _activeIndex;

    return Stack(
      children: [
        // ---- Background ambient gradient from album art -----------------
        if (widget.gradientColors != null && widget.gradientColors!.isNotEmpty)
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: Alignment.center,
                  radius: 0.9,
                  colors: [
                    widget.gradientColors!.first.withValues(alpha: 0.12),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

        // ---- Auto-translate notification banner -----------------------
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

        // ---- Lyric ListView (does NOT depend on positionProvider) ------
        // This section only rebuilds when [displayLyrics] changes (track
        // change) or when [_activeIndex] changes (~3s intervals). Position
        // ticks (~200ms) are handled by the listener in [_onPositionChanged]
        // which calls setState() only when the active index actually changes.
        GestureDetector(
          onLongPress: widget.onLongPress,
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
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
                  (notification.metrics.pixels - _dragStartOffset)
                          .abs() >
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
              itemBuilder: (context, index) {
                final lyric = displayLyrics[index];
                final isActive = index == displayIndex;

                // ---- Visual parameters --------------------------------
                Color textColor;
                FontWeight fontWeight;
                double fontSize;

                if (isActive) {
                  textColor = colorScheme.onSurface;
                  fontWeight = FontWeight.w800;
                  fontSize = lyricSettings.fullActiveFontSize;
                } else {
                  textColor = colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.55);
                  fontWeight = FontWeight.w500;
                  fontSize = lyricSettings.fullInactiveFontSize;
                }

                // ---- Build the lyric row ------------------------------
                Widget textWidget;
                if (isActive) {
                  final nextStartTime = index < displayLyrics.length - 1
                      ? displayLyrics[index + 1].startTime
                      : lyric.startTime + const Duration(seconds: 5);
                  textWidget =
                      _buildActiveLyricText(lyric, nextStartTime);
                } else {
                  textWidget = Text(
                    lyric.text,
                    textAlign: TextAlign.left,
                  );
                }

                Widget row = GestureDetector(
                  key: _getKeyForIndex(index),
                  onTap: widget.isLocked
                      ? null
                      : () => _onLyricTap(index),
                  onLongPress: widget.onLongPress,
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: isActive ? 20.0 : 14.0,
                    ),
                    child: AnimatedDefaultTextStyle(
                      duration: _animDuration,
                      curve: _animCurve,
                      style: (textTheme.bodyLarge ??
                              const TextStyle())
                          .copyWith(
                        color: textColor,
                        fontWeight: fontWeight,
                        fontSize: fontSize,
                        height: lyricSettings.fullLineHeight,
                      ),
                      child: textWidget,
                    ),
                  ),
                );

                return row;
              },
            ),
          ),
        ),

        // ---- Scroll-mode indicator ------------------------------------
        // Uses AnimatedBuilder with ValueNotifier so the indicator
        // can show/hide without rebuilding the parent widget tree.
        AnimatedBuilder(
          animation: _indicatorNotifier,
          builder: (context, _) {
            final label = _indicatorNotifier.value;
            if (label == null) return const SizedBox.shrink();
            return Positioned(
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
                          label,
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
            );
          },
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

  /// Build karaoke-style active lyric line with sequential character-by-character
  /// left-to-right sweep across the ENTIRE text block (including wrapped lines).
  ///
  /// Progress is calculated as:
  ///   progress = (currentPos - startTime) / (nextStartTime - startTime)
  ///
  /// This uses its own Consumer on [positionProvider], but only 1 widget
  /// (the active lyric line) has this consumer — all other lines use a
  /// plain [Text] widget. So the karaoke Consumer rebuild only affects
  /// 1 widget, not the entire ListView.
  Widget _buildActiveLyricText(LyricLine lyric, Duration nextStartTime) {
    final text = lyric.text;
    final lineDuration = nextStartTime - lyric.startTime;

    final pillColor = widget.gradientColors?.first.withValues(alpha: 0.18) ??
        Colors.white.withValues(alpha: 0.15);

    return Consumer(builder: (context, ref, _) {
      final position = ref.watch(positionProvider).valueOrNull ?? Duration.zero;

      final Duration effectivePos;
      if (widget.seekingPosition != null) {
        effectivePos = widget.seekingPosition!;
      } else if (_seekGraceActive && _cachedSeekPosition != null) {
        effectivePos = _cachedSeekPosition!;
      } else {
        effectivePos = position;
      }

      final elapsed = effectivePos - lyric.startTime;
      final progress = lineDuration > Duration.zero
          ? (elapsed.inMilliseconds / lineDuration.inMilliseconds)
              .clamp(0.0, 1.0)
          : 1.0;

      final sungColor = widget.gradientColors?.first ??
          Theme.of(context).colorScheme.primary;
      final upcomingColor = Theme.of(context).colorScheme.onSurface
          .withValues(alpha: 0.35);

      final inheritedStyle = DefaultTextStyle.of(context).style;

      return IntrinsicWidth(
        child: AnimatedContainer(
          duration: _animDuration,
          curve: _animCurve,
          decoration: BoxDecoration(
            color: pillColor,
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          child: LayoutBuilder(builder: (context, constraints) {
            final maxWidth = constraints.maxWidth;
            final karaokeLayout =
                _getKaraokeLayout(text, inheritedStyle, maxWidth);
            return Stack(
              children: [
                Text(
                  text,
                  style: inheritedStyle.copyWith(color: upcomingColor),
                  textAlign: TextAlign.left,
                ),
                ClipPath(
                  clipper: _KaraokeClipper(
                    text: text,
                    progress: progress,
                    layout: karaokeLayout,
                  ),
                  child: Text(
                    text,
                    style: inheritedStyle.copyWith(color: sungColor),
                    textAlign: TextAlign.left,
                  ),
                ),
              ],
            );
          }),
        ),
      );
    });
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

/// Precomputed karaoke layout data: TextPainter + per-line boundaries.
///
/// Created once per text/style/width combination and cached until the
/// active lyric or layout changes. The [TextPainter] is reused across
/// multiple position ticks, avoiding repeated [TextPainter.layout] calls.
class _KaraokeLayout {
  final TextPainter textPainter;
  final List<int> lineStarts; // character index of first char on each visual line
  final List<double> lineHeights; // height of each visual line (px)

  _KaraokeLayout({
    required this.textPainter,
    required this.lineStarts,
    required this.lineHeights,
  });
}

/// Custom clipper that reveals text characters sequentially from left to right.
///
/// Unlike [ShaderMask] with [LinearGradient] (which colors by x-position,
/// revealing all lines at the same horizontal position simultaneously),
/// this clipper uses [TextPainter.getOffsetForCaret] to determine line
/// boundaries and clips character by character.
///
/// Accepts a precomputed [_KaraokeLayout] so [TextPainter.layout] runs
/// only once per text/style/width change, not every 200ms tick.
class _KaraokeClipper extends CustomClipper<Path> {
  final String text;
  final double progress;
  final _KaraokeLayout layout;

  _KaraokeClipper({
    required this.text,
    required this.progress,
    required this.layout,
  });

  @override
  Path getClip(Size size) {
    final path = Path();
    if (progress <= 0.0 || text.isEmpty) return path;
    if (progress >= 1.0) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      return path;
    }

    final totalChars = text.length;
    final cutoffChar = (totalChars * progress).ceil().clamp(0, totalChars);
    if (cutoffChar <= 0) return path;
    if (cutoffChar >= totalChars) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, size.height));
      return path;
    }

    final lineStarts = layout.lineStarts;
    int lineIdx = lineStarts.length - 1;
    for (int i = 0; i < lineStarts.length; i++) {
      if (cutoffChar < lineStarts[i]) {
        lineIdx = i - 1;
        break;
      }
    }

    double lineTop = 0;
    for (int i = 0; i < lineIdx; i++) {
      lineTop += layout.lineHeights[i];
    }

    if (lineTop > 0) {
      path.addRect(Rect.fromLTWH(0, 0, size.width, lineTop));
    }

    final tp = layout.textPainter;
    final cutoffPos = tp.getOffsetForCaret(
      TextPosition(offset: cutoffChar), Rect.zero);
    path.addRect(Rect.fromLTWH(
      0, lineTop, cutoffPos.dx, layout.lineHeights[lineIdx]));

    return path;
  }

  @override
  bool shouldReclip(_KaraokeClipper oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.layout != layout;
  }
}

/// Apple Music-style skeleton shimmer shown while lyrics are loading.
/// Renders 5 rounded bars of varying widths with a sweeping shimmer gradient.
class _LyricSkeletonShimmer extends StatefulWidget {
  final List<Color>? gradientColors;

  const _LyricSkeletonShimmer({this.gradientColors});

  @override
  State<_LyricSkeletonShimmer> createState() => _LyricSkeletonShimmerState();
}

class _LyricSkeletonShimmerState extends State<_LyricSkeletonShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const barFractions = [0.72, 0.52, 0.82, 0.38, 0.62];

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final fraction in barFractions) ...[
                  FractionallySizedBox(
                    widthFactor: fraction,
                    child: Container(
                      height: 24,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        gradient: LinearGradient(
                          colors: widget.gradientColors != null &&
                                  widget.gradientColors!.length >= 2
                              ? [
                                  widget.gradientColors![0]
                                      .withValues(alpha: 0.15),
                                  widget.gradientColors![1]
                                      .withValues(alpha: 0.25),
                                  widget.gradientColors![0]
                                      .withValues(alpha: 0.15),
                                ]
                              : const [
                                  Color(0xFF2A2A2A),
                                  Color(0xFF404040),
                                  Color(0xFF2A2A2A),
                                ],
                          stops: [
                            (_controller.value - 0.3).clamp(0.0, 1.0),
                            _controller.value.clamp(0.0, 1.0),
                            (_controller.value + 0.3).clamp(0.0, 1.0),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
