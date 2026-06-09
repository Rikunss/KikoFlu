import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';

import '../models/audio_track.dart';
import '../providers/audio_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/lyric_provider.dart';
import '../providers/exclusive_audio_provider.dart';
import '../screens/audio_player_screen.dart';
import 'privacy_blur_cover.dart';
import 'volume_control.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  final bool enableArtworkHero;

  const MiniPlayer({super.key, this.enableArtworkHero = true});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> {
  String? _lastTrackId;
  bool _isAdjustingVolume = false;
  double _tempVolume = 1.0;
  PointerEvent? _swipeStart;

  @override
  Widget build(BuildContext context) {
    final currentTrack = ref.watch(currentTrackProvider);
    final isPlaying = ref.watch(isPlayingProvider);
    final isTrackLoading = ref.watch(isTrackLoadingProvider).valueOrNull ?? false;
    final authState = ref.watch(authProvider);
    final isMiniPlayerVisible = ref.watch(miniPlayerVisibilityProvider);

    // 启用自动字幕加载器
    ref.watch(lyricAutoLoaderProvider);

    return currentTrack.when(
      data: (track) {
        if (track != null && _lastTrackId != null && track.id != _lastTrackId) {
          _lastTrackId = track.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(miniPlayerVisibilityProvider.notifier).show();
            }
          });
        } else if (track != null && _lastTrackId == null) {
          _lastTrackId = track.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              ref.read(miniPlayerVisibilityProvider.notifier).show();
            }
          });
        }

        if (track == null || !isMiniPlayerVisible) {
          return const SizedBox.shrink();
        }

        // Build work cover URL
        String? workCoverUrl;
        if (track.artworkUrl != null &&
            track.artworkUrl!.startsWith('file://')) {
          workCoverUrl = track.artworkUrl;
        } else if (track.workId != null) {
          final host = authState.host ?? '';
          final token = authState.token ?? '';
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

        return Dismissible(
          key: Key('miniplayer_${track.id}'),
          direction: DismissDirection.down,
          background: Container(color: Colors.transparent),
          onDismissed: (direction) {
            ref.read(audioPlayerControllerProvider.notifier).stop();
            ref.read(miniPlayerVisibilityProvider.notifier).hide();
            _lastTrackId = null;
          },
          child: Consumer(
            builder: (context, ref, child) {
              final currentLyric = ref.watch(currentLyricTextProvider);
              final lyricState = ref.watch(lyricControllerProvider);
              final hasLyrics = lyricState.lyrics.isNotEmpty;
              final shouldShowLyric =
                  isPlaying && hasLyrics && currentLyric != null;

              final cs = Theme.of(context).colorScheme;
              final dividerColor = cs.outline.withValues(alpha: 0.15);

              // Listener (not GestureDetector!) to detect UPWARD swipes
              // for opening the fullscreen player. Listener doesn't
              // participate in the gesture arena, so it won't conflict
              // with Dismissible's vertical drag recognizer.
              return Listener(
                onPointerDown: (event) => _swipeStart = event,
                onPointerUp: (event) {
                  if (_swipeStart != null) {
                    final dy = event.position.dy - _swipeStart!.position.dy;
                    final dt = event.timeStamp - _swipeStart!.timeStamp;
                    if (dy < -50 && dt < const Duration(milliseconds: 300)) {
                      Navigator.of(context).push(
                        _PlayerPageRoute(
                          builder: (context) => const AudioPlayerScreen(),
                        ),
                      );
                    }
                    _swipeStart = null;
                  }
                },
                child: Container(
                color: cs.surface,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // ── Thin progress bar at the top (extracted widget) ──
                    const _MiniProgressBar(),

                    // ── Content row: artwork + info | controls ──
                    SizedBox(
                      height: shouldShowLyric ? 82 : 66,
                      child: Row(
                        children: [
                          // Left: artwork + info → tap opens full player
                          Expanded(
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: () {
                                Navigator.of(context).push(
                                  _PlayerPageRoute(
                                    builder: (context) =>
                                        const AudioPlayerScreen(),
                                  ),
                                );
                              },
                              child: Row(
                                children: [
                                  const SizedBox(width: 8),
                                  // Album art
                                  _buildArtwork(
                                    context,
                                    track,
                                    workCoverUrl: workCoverUrl,
                                  ),
                                  const SizedBox(width: 10),
                                  // Track info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          track.title,
                                          style: Theme.of(context).textTheme.bodyMedium
                                              ?.copyWith(
                                            fontWeight: FontWeight.w500,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        if (track.artist != null) ...[
                                          const SizedBox(height: 1),
                                          Text(
                                            track.artist!,
                                            style: Theme.of(context).textTheme.bodySmall
                                                ?.copyWith(
                                              color: cs.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                        // Audio format pills + output device (compact)
                                        const Padding(
                                          padding: EdgeInsets.only(top: 1),
                                          child: Row(
                                            children: [
                                              _MiniAudioFormatPills(),
                                              SizedBox(width: 3),
                                              _MiniOutputDevicePill(),
                                            ],
                                          ),
                                        ),
                                        // Lyric line (compact, below artist/pills)
                                        if (shouldShowLyric)
                                          Padding(
                                            padding:
                                                const EdgeInsets.only(top: 2),
                                            child: Text(
                                              currentLyric,
                                              style: Theme.of(context).textTheme.labelSmall
                                                  ?.copyWith(
                                                color: cs.primary,
                                                fontWeight: FontWeight.w600,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          // Controls
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(audioPlayerControllerProvider
                                            .notifier)
                                        .skipToPrevious();
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e
                                            .toString()
                                            .replaceAll('Exception: ', '')),
                                        duration:
                                            const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.skip_previous),
                                iconSize: 22,
                              ),
                              if (isTrackLoading)
                                const SizedBox(
                                  width: 28,
                                  height: 28,
                                  child: Padding(
                                    padding: EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2.5),
                                  ),
                                )
                              else
                                IconButton(
                                  onPressed: () {
                                    if (isPlaying) {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .pause();
                                    } else {
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .play();
                                    }
                                  },
                                  icon: Icon(
                                    isPlaying
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                  ),
                                  iconSize: 26,
                                ),
                              IconButton(
                                onPressed: () async {
                                  try {
                                    await ref
                                        .read(audioPlayerControllerProvider
                                            .notifier)
                                        .skipToNext();
                                  } catch (e) {
                                    if (!context.mounted) return;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(e
                                            .toString()
                                            .replaceAll('Exception: ', '')),
                                        duration:
                                            const Duration(seconds: 1),
                                      ),
                                    );
                                  }
                                },
                                icon: const Icon(Icons.skip_next),
                                iconSize: 22,
                              ),
                              Consumer(
                                builder: (context, ref, child) {
                                  final audioState = ref
                                      .watch(audioPlayerControllerProvider);
                                  final displayVolume = _isAdjustingVolume
                                      ? _tempVolume
                                      : audioState.volume;
                                  return VolumeControl(
                                    volume: displayVolume,
                                    onVolumeChanged: (value) {
                                      setState(() {
                                        _isAdjustingVolume = true;
                                        _tempVolume = value;
                                      });
                                      ref
                                          .read(audioPlayerControllerProvider
                                              .notifier)
                                          .setVolume(value);
                                    },
                                    onVolumeChangeEnd: () {
                                      setState(() =>
                                          _isAdjustingVolume = false);
                                    },
                                    iconSize: 22,
                                  );
                                },
                              ),
                              const SizedBox(width: 4),
                            ],
                          ),
                        ],
                      ),
                    ),

                    // ── Divider line to separate from nav ──
                    Divider(height: 0, thickness: 0.5, color: dividerColor),
                  ],
                ),
              ),
            );
            },
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }

  Widget _buildArtwork(
    BuildContext context,
    AudioTrack track, {
    String? workCoverUrl,
  }) {
    final cs = Theme.of(context).colorScheme;
    final image = Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        color: cs.surfaceContainerHighest,
      ),
      child: (workCoverUrl ?? track.artworkUrl) != null
          ? PrivacyBlurCover(
              borderRadius: BorderRadius.circular(6),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: (workCoverUrl ?? track.artworkUrl)
                                ?.startsWith('file://') ??
                        false
                    ? Image.file(
                        File((workCoverUrl ?? track.artworkUrl)!
                            .replaceFirst('file://', '')),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return const Icon(Icons.album, size: 28);
                        },
                      )
                    : CachedNetworkImage(
                        imageUrl: (workCoverUrl ?? track.artworkUrl)!,
                        cacheKey: track.workId != null
                            ? 'work_cover_${track.workId}'
                            : null,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) =>
                            const Icon(Icons.album, size: 28),
                        placeholder: (context, url) => const Center(
                          child: CircularProgressIndicator(),
                        ),
                      ),
              ),
            )
          : const Icon(Icons.album, size: 28),
    );

    if (!widget.enableArtworkHero) {
      return image;
    }

    return Hero(
      tag: 'audio_player_artwork_${track.id}',
      child: image,
    );
  }
}

/// Compact audio format pills for the mini player.
class _MiniAudioFormatPills extends ConsumerWidget {
  const _MiniAudioFormatPills();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fmtAsync = ref.watch(audioFormatInfoProvider);
    return fmtAsync.when(
      data: (info) {
        if (info == null) return const SizedBox.shrink();
        final cs = Theme.of(context).colorScheme;

        final pills = <Widget>[];

        pills.add(_MiniPill(
          label: info.codec.toUpperCase(),
          color: cs.primary.withValues(alpha: 0.7),
        ));

        if (info.bitDepth != null) {
          pills.add(const SizedBox(width: 3));
          pills.add(_MiniPill(
            label: '${info.bitDepth}bit',
            color: cs.tertiary.withValues(alpha: 0.7),
          ));
        }

        if (info.sampleRate != null) {
          pills.add(const SizedBox(width: 3));
          pills.add(_MiniPill(
            label:
                '${(info.sampleRate! / 1000).toStringAsFixed(info.sampleRate! % 1000 == 0 ? 0 : 1)}kHz',
            color: cs.secondary.withValues(alpha: 0.7),
          ));
        }

        return Row(children: pills);
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}

/// Tiny audio output device pill for the mini player.
/// Features a brief glow highlight animation when the output device changes.
class _MiniOutputDevicePill extends ConsumerStatefulWidget {
  const _MiniOutputDevicePill();

  @override
  ConsumerState<_MiniOutputDevicePill> createState() =>
      _MiniOutputDevicePillState();
}

class _MiniOutputDevicePillState extends ConsumerState<_MiniOutputDevicePill>
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
        // Trigger brief glow on device type change (skip initial mount)
        if (type != _lastDeviceType && _lastDeviceType.isNotEmpty && mounted) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _glowCtrl.forward(from: 0.0);
          });
        }
        _lastDeviceType = type;

        final (IconData icon, String label) = switch (type) {
          'usb_dac' || 'usb_detected' => (Icons.usb, 'USB'),
          'wired_headphones' || 'headphones' => (Icons.headphones, 'HP'),
          'bluetooth' => (Icons.bluetooth, 'BT'),
          _ => (Icons.speaker, 'Speaker'),
        };
        final cs = Theme.of(context).colorScheme;

        return AnimatedBuilder(
          animation: _glowAnim,
          builder: (context, child) {
            final glow = (1.0 - _glowCtrl.value).clamp(0.0, 1.0);
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withValues(alpha: 0.8),
                borderRadius: BorderRadius.circular(3),
                boxShadow: glow > 0.01
                    ? [
                        BoxShadow(
                          color: cs.primary.withValues(alpha: glow * 0.45),
                          blurRadius: 3 + glow * 6,
                          spreadRadius: glow * 1.5,
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
              key: ValueKey('mini_output_$type'),
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 8, color: cs.onSurfaceVariant),
                const SizedBox(width: 2),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.2,
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

/// Extracted progress bar widget — only rebuilds on position/duration changes.
/// Does NOT cause the entire mini player to rebuild on each position tick.
class _MiniProgressBar extends ConsumerStatefulWidget {
  const _MiniProgressBar();

  @override
  ConsumerState<_MiniProgressBar> createState() => _MiniProgressBarState();
}

class _MiniProgressBarState extends ConsumerState<_MiniProgressBar> {
  bool _isDragging = false;
  double _dragValue = 0.0;

  @override
  Widget build(BuildContext context) {
    final position = ref.watch(positionProvider);
    final duration = ref.watch(durationProvider);

    final progress = position.when(
      data: (pos) => duration.when(
        data: (dur) => dur != null && dur.inMilliseconds > 0
            ? pos.inMilliseconds / dur.inMilliseconds
            : 0.0,
        loading: () => 0.0,
        error: (_, __) => 0.0,
      ),
      loading: () => 0.0,
      error: (_, __) => 0.0,
    );

    final displayProgress = _isDragging ? _dragValue : progress;
    final cs = Theme.of(context).colorScheme;
    final dividerColor = cs.outline.withValues(alpha: 0.15);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => setState(() => _isDragging = true),
      onHorizontalDragUpdate: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = details.localPosition.dx;
          final width = box.size.width;
          setState(() => _dragValue = (localPosition / width).clamp(0.0, 1.0));
        }
      },
      onHorizontalDragEnd: (_) {
        final dur = duration.valueOrNull;
        if (dur != null) {
          final seekPosition = Duration(
            milliseconds: (_dragValue * dur.inMilliseconds).round(),
          );
          ref
              .read(audioPlayerControllerProvider.notifier)
              .seekAndPersist(seekPosition);
        }
        setState(() => _isDragging = false);
      },
      onTapUp: (details) {
        final box = context.findRenderObject() as RenderBox?;
        if (box != null) {
          final localPosition = details.localPosition.dx;
          final width = box.size.width;
          final value = (localPosition / width).clamp(0.0, 1.0);
          final dur = duration.valueOrNull;
          if (dur != null) {
            final seekPosition = Duration(
              milliseconds: (value * dur.inMilliseconds).round(),
            );
            ref
                .read(audioPlayerControllerProvider.notifier)
                .seekAndPersist(seekPosition);
          }
        }
      },
      child: Container(
        height: 2,
        color: dividerColor,
        alignment: Alignment.centerLeft,
        child: FractionallySizedBox(
          widthFactor: displayProgress.clamp(0.0, 1.0),
          child: Container(color: cs.primary),
        ),
      ),
    );
  }
}

/// Single tiny pill in the mini player format badge.
class _MiniPill extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(3),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
      ),
    );
  }
}

/// Custom page route for the audio player that supports iOS swipe-back gesture
/// while keeping the custom Hero-friendly transition animation.
///
/// - Forward (enter): scale + fade from bottom-left, Hero flies from mini player artwork
/// - Back via swipe: Cupertino slide transition (natural iOS feel)
/// - Back via button: fade out (letting Hero fly back when available)
class _PlayerPageRoute<T> extends PageRoute<T> with CupertinoRouteTransitionMixin<T> {
  _PlayerPageRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  Widget buildContent(BuildContext context) => builder(context);

  @override
  String? get title => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 400);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 400);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    if (Platform.isIOS) {
      if (popGestureInProgress) {
        return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
          this, context, animation, secondaryAnimation, child,
        );
      }

      if (animation.status == AnimationStatus.reverse) {
        return FadeTransition(opacity: animation, child: child);
      }

      if (animation.status == AnimationStatus.forward ||
          animation.status == AnimationStatus.completed) {
        const curve = Curves.easeOutCubic;
        final scale = Tween<double>(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: curve))
            .evaluate(animation);
        final opacity = CurveTween(curve: Curves.easeIn).evaluate(animation);

        return _wrapWithGestureDetector(
          context,
          Transform.scale(
            scale: scale,
            alignment: Alignment.bottomLeft,
            child: Opacity(opacity: opacity, child: child),
          ),
        );
      }
    }

    const curve = Curves.easeOutCubic;
    final scale = Tween<double>(begin: 0.0, end: 1.0)
        .chain(CurveTween(curve: curve))
        .evaluate(animation);
    final opacity = CurveTween(curve: Curves.easeIn).evaluate(animation);
    return Transform.scale(
      scale: scale,
      alignment: Alignment.bottomLeft,
      child: Opacity(opacity: opacity, child: child),
    );
  }

  Widget _wrapWithGestureDetector(BuildContext context, Widget child) {
    return CupertinoRouteTransitionMixin.buildPageTransitions<T>(
      this,
      context,
      const AlwaysStoppedAnimation(1.0),
      const AlwaysStoppedAnimation(0.0),
      child,
    );
  }
}
