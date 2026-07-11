import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import 'waveform_seeker.dart';

import '../../providers/audio_provider.dart';
import '../../providers/floating_lyric_provider.dart';
import '../../providers/lyric_provider.dart';
import '../../providers/player_buttons_provider.dart';
import '../responsive_dialog.dart';
import '../subtitle_adjustment_dialog.dart';
import '../volume_control.dart';
import '../../screens/equalizer_screen.dart';
import '../../services/bookmark_service.dart';
import 'sleep_timer_button.dart';
import 'sleep_timer_dialog.dart';
import 'bookmarks_sheet.dart';
import '../../../l10n/app_localizations.dart';

/// 播放器控制组件
class PlayerControlsWidget extends ConsumerStatefulWidget {
  final bool isLandscape;
  final AudioPlayerState audioState;
  final bool isSeekingManually;
  final double seekValue;
  final ValueChanged<double> onSeekChanged;
  final ValueChanged<double> onSeekEnd;
  final Duration? seekingPosition;
  final int? workId;
  final String? currentProgress;
  final VoidCallback? onMarkPressed;
  final VoidCallback? onDetailPressed;

  /// Optional gradient colours extracted from album artwork.
  final List<Color>? gradientColors;

  /// Called on long-press of the seekbar — used to refresh gradient colours.
  final VoidCallback? onGradientRefresh;

  const PlayerControlsWidget({
    super.key,
    required this.isLandscape,
    required this.audioState,
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
  ConsumerState<PlayerControlsWidget> createState() =>
      _PlayerControlsWidgetState();
}

/// Format [Duration] to display string (e.g. "1:23:45" or "3:45").
/// Top-level so leaf ConsumerWidgets can reuse it.
String formatDuration(Duration duration) {
  String twoDigits(int n) => n.toString().padLeft(2, '0');
  final hours = duration.inHours;
  final minutes = duration.inMinutes.remainder(60);
  final seconds = duration.inSeconds.remainder(60);

  if (hours > 0) {
    return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
  } else {
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }
}

class _PlayerControlsWidgetState extends ConsumerState<PlayerControlsWidget> {

  /// Builds seekbar + time labels section.
  /// The time labels use leaf ConsumerWidgets so only the position text
  /// rebuilds on every 200ms tick — the Row wrapper stays stable.
  Widget _buildSeekSection(BuildContext context) {
    return Column(children: [
      Consumer(
        builder: (context, ref, child) {
          final progress = ref.watch(playbackProgressProvider);
          final pos = progress.position;
          final dur = progress.duration ?? Duration.zero;
          final isPlaying = ref.watch(isPlayingProvider);

          final seekValue = (widget.isSeekingManually
                  ? widget.seekValue
                  : dur.inMilliseconds > 0
                      ? pos.inMilliseconds / dur.inMilliseconds
                      : 0.0)
              .clamp(0.0, 1.0);

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: WaveformSeeker(
              value: seekValue,
              duration: dur,
              isPlaying: isPlaying,
              gradientColors: widget.gradientColors,
              onChanged: widget.onSeekChanged,
              onChangeEnd: widget.onSeekEnd,
              onLongPress: widget.onGradientRefresh,
            ),
          );
        },
      ),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _PositionText(
              isSeekingManually: widget.isSeekingManually,
              seekValue: widget.seekValue,
            ),
            const _DurationText(),
          ],
        ),
      ),
    ]);
  }

  void _showSpeedDialog(
      BuildContext context, WidgetRef ref, double currentSpeed) {
    double localSpeed = currentSpeed;

    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => ResponsiveAlertDialog(
        title: Text(S.of(context).playbackSpeed),
        content: StatefulBuilder(
          builder: (context, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Slider(
                  value: localSpeed,
                  min: 0.25,
                  max: 2.5,
                  divisions: 9,
                  label: '${localSpeed.toStringAsFixed(1)}x',
                  onChanged: (value) {
                    setState(() {
                      localSpeed = value;
                    });
                    ref
                        .read(audioPlayerControllerProvider.notifier)
                        .setSpeed(value);
                  },
                ),
                Text('${localSpeed.toStringAsFixed(1)}x'),
              ],
            );
          },
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).confirm),
          ),
        ],
      ),
    );
  }

  void _showMoreMenu(BuildContext context, WidgetRef ref) {
    final isDesktop = !Platform.isAndroid && !Platform.isIOS;
    final config = isDesktop
        ? ref.read(playerButtonsConfigDesktopProvider)
        : ref.read(playerButtonsConfigMobileProvider);
    final moreButtons = config.getMoreButtons(isDesktop);

    showModalBottomSheet(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ...moreButtons.map((buttonType) {
                return _buildMenuItemForButton(
                    context, ref, buttonType, setState);
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItemForButton(
      BuildContext context, WidgetRef ref, PlayerButtonType buttonType,
      [StateSetter? setState]) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    switch (buttonType) {
      case PlayerButtonType.seekBackward:
        return ListTile(
          leading: const Icon(Icons.replay_10),
          title: Text(S.of(context).backward10s),
          onTap: () {
            Navigator.pop(context);
            ref
                .read(audioPlayerControllerProvider.notifier)
                .seekBackward(const Duration(seconds: 10));
          },
        );
      case PlayerButtonType.seekForward:
        return ListTile(
          leading: const Icon(Icons.forward_10),
          title: Text(S.of(context).forward10s),
          onTap: () {
            Navigator.pop(context);
            ref
                .read(audioPlayerControllerProvider.notifier)
                .seekForward(const Duration(seconds: 10));
          },
        );
      case PlayerButtonType.sleepTimer:
        final timerState = ref.watch(sleepTimerProvider);
        return ListTile(
          leading: Icon(
            timerState.isActive ? Icons.timer : Icons.timer_outlined,
            color: timerState.isActive
                ? cs.primary
                : null,
          ),
          title: Text(S.of(context).sleepTimer),
          trailing: timerState.isActive && timerState.remainingTime != null
              ? Text(
                  timerState.formattedTime,
                  style: tt.bodyMedium?.copyWith(
                        color: cs.primary,
                      ),
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            SleepTimerDialog.show(context);
          },
        );
      case PlayerButtonType.speed:
        return ListTile(
          leading: const Icon(Icons.speed),
          title: Text(S.of(context).playbackSpeed),
          trailing: Text(
            '${widget.audioState.speed.toStringAsFixed(1)}x',
            style: tt.bodyMedium?.copyWith(
                  color: cs.primary,
                ),
          ),
          onTap: () {
            Navigator.pop(context);
            _showSpeedDialog(context, ref, widget.audioState.speed);
          },
        );
      case PlayerButtonType.repeat:
        return ListTile(
          leading: Icon(
            switch (widget.audioState.repeatMode) {
              LoopMode.off => Icons.repeat,
              LoopMode.one => Icons.repeat_one,
              LoopMode.all => Icons.repeat_on,
            },
            color: widget.audioState.repeatMode != LoopMode.off
                ? cs.primary
                : null,
          ),
          title: Text(S.of(context).repeatMode),
          trailing: Text(
            switch (widget.audioState.repeatMode) {
              LoopMode.off => S.of(context).repeatOff,
              LoopMode.one => S.of(context).repeatOne,
              LoopMode.all => S.of(context).repeatAll,
            },
            style: tt.bodyMedium?.copyWith(
                  color: widget.audioState.repeatMode != LoopMode.off
                      ? cs.primary
                      : null,
                ),
          ),
          onTap: () {
            final nextMode = switch (widget.audioState.repeatMode) {
              LoopMode.off => LoopMode.one,
              LoopMode.one => LoopMode.all,
              LoopMode.all => LoopMode.off,
            };
            ref
                .read(audioPlayerControllerProvider.notifier)
                .setRepeatMode(nextMode);
            Navigator.pop(context);
          },
        );
      case PlayerButtonType.mark:
        return ListTile(
          leading: Icon(
            widget.currentProgress != null
                ? Icons.bookmark
                : Icons.bookmark_border,
            color: widget.currentProgress != null
                ? cs.primary
                : null,
          ),
          title: Text(S.of(context).addMark),
          trailing: widget.currentProgress != null
              ? Icon(
                  Icons.check_circle,
                  color: cs.primary,
                  size: 20,
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            if (widget.onMarkPressed != null) {
              widget.onMarkPressed!();
            }
          },
        );
      case PlayerButtonType.detail:
        return ListTile(
          leading: const Icon(Icons.info_outline),
          title: Text(S.of(context).viewDetail),
          onTap: () {
            Navigator.pop(context);
            if (widget.onDetailPressed != null) {
              widget.onDetailPressed!();
            }
          },
        );
      case PlayerButtonType.volume:
        final currentVolume = ref.read(audioPlayerControllerProvider).volume;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.volume_up),
              title: Text(S.of(context).volume),
              trailing: Text(
                '${(currentVolume * 100).round()}%',
                style: tt.bodyMedium?.copyWith(
                      color: cs.primary,
                    ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.volume_down,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                  Expanded(
                    child: Slider(
                      value: currentVolume,
                      onChanged: (value) {
                        ref
                            .read(audioPlayerControllerProvider.notifier)
                            .setVolume(value);
                        if (setState != null) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  Icon(
                    Icons.volume_up,
                    size: 20,
                    color: cs.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ],
        );
      case PlayerButtonType.subtitleAdjustment:
        final timelineOffset = ref.watch(
          lyricControllerProvider.select((s) => s.timelineOffset),
        );
        final hasOffset = timelineOffset != Duration.zero;
        return ListTile(
          leading: Icon(
            Icons.tune,
            color: hasOffset ? cs.primary : null,
          ),
          title: Text(S.of(context).subtitleTimingAdjustment),
          trailing: hasOffset
              ? Text(
                  '${timelineOffset.inMilliseconds}ms',
                  style: tt.bodyMedium?.copyWith(
                        color: cs.primary,
                      ),
                )
              : null,
          onTap: () {
            Navigator.pop(context);
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (context) => const SubtitleAdjustmentDialog(),
            );
          },
        );
      case PlayerButtonType.floatingLyric:
        return Consumer(
          builder: (context, ref, child) {
            final isEnabled = ref.watch(floatingLyricEnabledProvider);
            return ListTile(
              leading: Icon(
                Icons.picture_in_picture_alt,
                color: isEnabled ? cs.primary : null,
              ),
              title: Text(S.of(context).floatingSubtitle),
              trailing: Transform.scale(
                scale: 0.8,
                alignment: Alignment.centerRight,
                child: Switch(
                  value: isEnabled,
                  onChanged: (value) {
                    ref.read(floatingLyricEnabledProvider.notifier).toggle();
                  },
                ),
              ),
              onTap: () {
                ref.read(floatingLyricEnabledProvider.notifier).toggle();
              },
            );
          },
        );
      case PlayerButtonType.equalizer:
        return ListTile(
          leading: Icon(
            Icons.equalizer,
            color: cs.primary,
          ),
          title: Text(S.of(context).equalizerTitle),
          onTap: () {
            Navigator.pop(context);
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (context) => const EqualizerScreen(),
              ),
            );
          },
        );
      case PlayerButtonType.bookmark:
        return ListTile(
          leading: const Icon(Icons.bookmark_rounded),
          title: Text(S.of(context).audioBookmarksTitle),
          onTap: () {
            Navigator.pop(context);
            BookmarksSheet.show(context);
          },
        );
    }
  }

  Widget _buildButton(BuildContext context, WidgetRef ref,
      ColorScheme colorScheme,
      PlayerButtonType buttonType, bool isLandscape) {
    final iconSize = isLandscape ? 24.0 : null;

    switch (buttonType) {
      case PlayerButtonType.seekBackward:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekBackward(const Duration(seconds: 10));
              },
              icon: const Icon(Icons.replay_10),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.seekForward:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekForward(const Duration(seconds: 10));
              },
              icon: const Icon(Icons.forward_10),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.sleepTimer:
        return SleepTimerButton(iconSize: iconSize);
      case PlayerButtonType.volume:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            VolumeControl(
              volume: widget.audioState.volume,
              onVolumeChanged: (value) {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .setVolume(value);
              },
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.speed:
        return SizedBox(
          height: isLandscape ? 40 : 62,
          child: Align(
            alignment: Alignment.center,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  onPressed: () {
                    _showSpeedDialog(context, ref, widget.audioState.speed);
                  },
                  icon: Icon(
                    Icons.speed,
                    color: widget.audioState.speed != 1.0
                        ? colorScheme.primary
                        : null,
                  ),
                  iconSize: iconSize,
                  padding: isLandscape ? EdgeInsets.zero : null,
                  constraints: isLandscape
                      ? const BoxConstraints(minWidth: 36, minHeight: 36)
                      : null,
                  visualDensity: isLandscape
                      ? VisualDensity.compact
                      : VisualDensity.standard,
                ),
                if (widget.audioState.speed != 1.0)
                  Text(
                    '${widget.audioState.speed.toStringAsFixed(1)}x',
                    style: TextStyle(
                      fontSize: 9,
                      height: 1.0,
                      color: colorScheme.primary,
                      fontWeight: FontWeight.w500,
                      fontFeatures: const [
                        FontFeature.tabularFigures(),
                      ],
                    ),
                  ),
                if (widget.audioState.speed == 1.0)
                  SizedBox(height: isLandscape ? 4 : 14),
              ],
            ),
          ),
        );
      case PlayerButtonType.repeat:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                final nextMode = switch (widget.audioState.repeatMode) {
                  LoopMode.off => LoopMode.one,
                  LoopMode.one => LoopMode.all,
                  LoopMode.all => LoopMode.off,
                };
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .setRepeatMode(nextMode);
              },
              icon: Icon(
                switch (widget.audioState.repeatMode) {
                  LoopMode.off => Icons.repeat,
                  LoopMode.one => Icons.repeat_one,
                  LoopMode.all => Icons.repeat_on,
                },
                color: widget.audioState.repeatMode != LoopMode.off
                    ? colorScheme.primary
                    : null,
              ),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.mark:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.onMarkPressed,
              icon: Icon(
                widget.currentProgress != null
                    ? Icons.bookmark
                    : Icons.bookmark_border,
                color: widget.currentProgress != null
                    ? colorScheme.primary
                    : null,
              ),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.detail:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: widget.onDetailPressed,
              icon: const Icon(Icons.info_outline),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.subtitleAdjustment:
        final hasOffset = ref.watch(
          lyricControllerProvider.select((s) => s.timelineOffset != Duration.zero),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  barrierColor: Colors.transparent,
                  builder: (context) => const SubtitleAdjustmentDialog(),
                );
              },
              icon: Badge(
                isLabelVisible: hasOffset,                                backgroundColor: colorScheme.primary,
                child: const Icon(Icons.tune),
              ),
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.floatingLyric:
        final isEnabled = ref.watch(floatingLyricEnabledProvider);
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                ref.read(floatingLyricEnabledProvider.notifier).toggle();
              },
              icon: Icon(
                isEnabled
                    ? Icons.picture_in_picture_alt
                    : Icons.picture_in_picture_alt_outlined,
                color: isEnabled ? colorScheme.primary : null,
              ),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.equalizer:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (context) => const EqualizerScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.equalizer),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
      case PlayerButtonType.bookmark:
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              onPressed: () {
                final service = ref.read(bookmarkServiceProvider);
                final currentTrack = ref.read(currentTrackProvider).valueOrNull;
                if (currentTrack != null) {
                  final position = ref.read(positionProvider).valueOrNull ??
                      Duration.zero;
                  service.add(
                    trackId: currentTrack.id,
                    workId: currentTrack.workId,
                    position: position,
                    trackTitle: currentTrack.title,
                  );
                  HapticFeedback.lightImpact();
                  ScaffoldMessenger.of(context).clearSnackBars();
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(S.of(context).audioBookmarkAdded(position.inMilliseconds > 0
                          ? formatDuration(position)
                          : '0:00')),
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 2),
                      action: SnackBarAction(
                        label: S.of(context).audioBookmarksView,
                        onPressed: () => BookmarksSheet.show(context),
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.bookmark_add_outlined),
              iconSize: iconSize,
            ),
            if (!isLandscape) const SizedBox(height: 14),
          ],
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final iconSize = widget.isLandscape ? 24.0 : 48.0;
    final playButtonSize = widget.isLandscape ? 64.0 : 72.0;
    final playIconSize = widget.isLandscape ? 32.0 : 36.0;

    return Column(
      children: [
        _buildSeekSection(context),
        SizedBox(height: widget.isLandscape ? 20 : 16),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .skipToPrevious();
              },
              icon: const Icon(Icons.skip_previous),
              iconSize: iconSize,
            ),
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekBackward(const Duration(seconds: 10));
                HapticFeedback.lightImpact();
              },
              icon: const Icon(Icons.replay_10),
              iconSize: widget.isLandscape ? 22 : iconSize * 0.7,
            ),
            Consumer(
              builder: (context, ref, child) {
                final isPlaying = ref.watch(isPlayingProvider);
                return Container(
                  width: playButtonSize,
                  height: playButtonSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colorScheme.primary,
                  ),
                  child: IconButton(
                    onPressed: () {
                      if (isPlaying) {
                        ref.read(audioPlayerControllerProvider.notifier).pause();
                      } else {
                        ref.read(audioPlayerControllerProvider.notifier).play();
                      }
                    },
                    icon: Icon(
                      isPlaying ? Icons.pause : Icons.play_arrow,
                      color: colorScheme.onPrimary,
                    ),
                    iconSize: playIconSize,
                  ),
                );
              },
            ),
            IconButton(
              onPressed: () {
                ref
                    .read(audioPlayerControllerProvider.notifier)
                    .seekForward(const Duration(seconds: 10));
                HapticFeedback.lightImpact();
              },
              icon: const Icon(Icons.forward_10),
              iconSize: widget.isLandscape ? 22 : iconSize * 0.7,
            ),
            IconButton(
              onPressed: () {
                ref.read(audioPlayerControllerProvider.notifier).skipToNext();
              },
              icon: Consumer(
                builder: (context, ref, child) {
                  final canSkipNext = ref.watch(canSkipNextProvider);
                  final baseColor = colorScheme.onSurface;
                  return Icon(
                    Icons.skip_next,
                    color:
                        canSkipNext ? null : baseColor.withValues(alpha: 0.3),
                  );
                },
              ),
              iconSize: iconSize,
            ),
          ],
        ),
        SizedBox(height: widget.isLandscape ? 16 : 12),
        Consumer(
          builder: (context, ref, child) {
            final isDesktop = !Platform.isAndroid && !Platform.isIOS;
            final config = isDesktop
                ? ref.watch(playerButtonsConfigDesktopProvider)
                : ref.watch(playerButtonsConfigMobileProvider);
            final visibleButtons = config.getVisibleButtons(isDesktop);

            final dedupedButtons = visibleButtons.where(
              (b) => b != PlayerButtonType.seekBackward &&
                     b != PlayerButtonType.seekForward,
            ).toList();

            return Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                ...dedupedButtons
                    .map((type) =>
                        _buildButton(context, ref, colorScheme, type, widget.isLandscape))
                    ,
                Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      onPressed: () {
                        _showMoreMenu(context, ref);
                      },
                      icon: Builder(
                        builder: (context) {
                          final moreButtons = config.getMoreButtons(isDesktop);
                          final hasSpeedInMore =
                              moreButtons.contains(PlayerButtonType.speed);
                          final hasRepeatInMore =
                              moreButtons.contains(PlayerButtonType.repeat);
                          final hasSleepTimerInMore =
                              moreButtons.contains(PlayerButtonType.sleepTimer);
                          final hasSubtitleAdjustmentInMore = moreButtons
                              .contains(PlayerButtonType.subtitleAdjustment);
                          final hasFloatingLyricInMore = moreButtons
                              .contains(PlayerButtonType.floatingLyric);
                          final timerState = ref.watch(sleepTimerProvider);
                          final hasSubtitleOffset = ref.watch(
                            lyricControllerProvider.select(
                              (s) => s.timelineOffset != Duration.zero,
                            ),
                          );
                          final isFloatingLyricEnabled =
                              ref.watch(floatingLyricEnabledProvider);

                          final shouldShowBadge = (hasSpeedInMore &&
                                  widget.audioState.speed != 1.0) ||
                              (hasRepeatInMore &&
                                  widget.audioState.repeatMode !=
                                      LoopMode.off) ||
                              (hasSleepTimerInMore && timerState.isActive) ||
                              (hasSubtitleAdjustmentInMore &&
                                  hasSubtitleOffset) ||
                              (hasFloatingLyricInMore &&
                                  isFloatingLyricEnabled);

                          return Badge(
                            isLabelVisible: shouldShowBadge,                                backgroundColor: colorScheme.primary,
                            child: const Icon(Icons.more_horiz),
                          );
                        },
                      ),
                      iconSize: widget.isLandscape ? 24 : null,
                    ),
                    if (!widget.isLandscape) const SizedBox(height: 14),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

/// Position time label — watches [positionProvider] independently so
/// the time labels Row does not rebuild on every 200ms position tick.
/// Only this single Text widget rebuilds when the position updates.
class _PositionText extends ConsumerWidget {
  final bool isSeekingManually;
  final double seekValue;

  const _PositionText({
    required this.isSeekingManually,
    required this.seekValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final progress = ref.watch(playbackProgressProvider);
    final pos = progress.position;
    final dur = progress.duration ?? Duration.zero;
    final displayPos = isSeekingManually
        ? Duration(milliseconds: (seekValue * dur.inMilliseconds).round())
        : pos;
    final theme = Theme.of(context);
    return Text(
      formatDuration(displayPos),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}

/// Duration time label — watches [durationProvider] independently so
/// the time labels Row does not rebuild on every 200ms position tick.
/// Duration rarely changes (only on track change), so this widget
/// almost never rebuilds, keeping the UI thread free for position updates.
class _DurationText extends ConsumerWidget {
  const _DurationText();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dur = ref.watch(durationProvider).value ?? Duration.zero;
    final theme = Theme.of(context);
    return Text(
      formatDuration(dur),
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }
}