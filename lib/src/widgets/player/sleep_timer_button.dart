import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import 'sleep_timer_dialog.dart';

/// 定时器按钮/指示器
class SleepTimerButton extends ConsumerWidget {
  final double? iconSize;

  const SleepTimerButton({
    super.key,
    this.iconSize,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timerState = ref.watch(sleepTimerProvider);
    final isLandscapeCompact =
        iconSize != null;

    if (timerState.isActive) {
      return SizedBox(
        height: iconSize == null ? 62 : 40,
        child: Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => SleepTimerDialog.show(context),
                icon: Icon(
                  timerState.waitingForTrackEnd
                      ? Icons.hourglass_bottom
                      : Icons.timer,
                  color: Theme.of(context).colorScheme.primary,
                ),
                iconSize: iconSize,
                padding: isLandscapeCompact ? EdgeInsets.zero : null,
                constraints: isLandscapeCompact
                    ? const BoxConstraints(minWidth: 36, minHeight: 36)
                    : null,
                visualDensity: isLandscapeCompact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              if (timerState.remainingTime != null)
                Text(
                  timerState.formattedTime,
                  style: TextStyle(
                    fontSize: 9,
                    height: 1.0,
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w500,
                    fontFeatures: const [
                      FontFeature.tabularFigures(),
                    ],
                  ),
                ),
            ],
          ),
        ),
      );
    } else {
      return SizedBox(
        height: iconSize == null ? 62 : 40,
        child: Align(
          alignment: Alignment.center,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                onPressed: () => SleepTimerDialog.show(context),
                icon: const Icon(Icons.timer_outlined),
                iconSize: iconSize,
                padding: isLandscapeCompact ? EdgeInsets.zero : null,
                constraints: isLandscapeCompact
                    ? const BoxConstraints(minWidth: 36, minHeight: 36)
                    : null,
                visualDensity: isLandscapeCompact
                    ? VisualDensity.compact
                    : VisualDensity.standard,
              ),
              SizedBox(height: iconSize == null ? 14 : 4),
            ],
          ),
        ),
      );
    }
  }
}