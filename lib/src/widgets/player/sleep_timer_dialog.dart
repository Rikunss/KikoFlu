import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/audio_provider.dart';
import '../responsive_dialog.dart';
import '../../../l10n/app_localizations.dart';

/// 定时器对话框
class SleepTimerDialog extends ConsumerStatefulWidget {
  const SleepTimerDialog({super.key});

  static void show(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: !Platform.isIOS,
      builder: (context) => const SleepTimerDialog(),
    );
  }

  @override
  ConsumerState<SleepTimerDialog> createState() => _SleepTimerDialogState();
}

class _SleepTimerDialogState extends ConsumerState<SleepTimerDialog> {
  bool _isTimeMode = false;
  bool _finishCurrentTrack = false;
  TimeOfDay _selectedTime = TimeOfDay.now();

  @override
  Widget build(BuildContext context) {
    final timerState = ref.watch(sleepTimerProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return ResponsiveAlertDialog(
      title: Text(S.of(context).sleepTimerTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (timerState.isActive) ...[
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    Icon(
                      timerState.waitingForTrackEnd
                          ? Icons.hourglass_bottom
                          : Icons.timer,
                      size: 48,
                      color: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      timerState.waitingForTrackEnd ? S.of(context).aboutToStop : S.of(context).remainingTime,
                      style: textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onPrimaryContainer,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      timerState.formattedTime,
                      style: textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimaryContainer,
                        fontSize: timerState.waitingForTrackEnd ? 32 : null,
                        fontFeatures: const [
                          FontFeature.tabularFigures(),
                        ],
                      ),
                    ),
                    if (timerState.finishCurrentTrack &&
                        !timerState.waitingForTrackEnd) ...[
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surface.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.queue_music,
                              size: 14,
                              color: colorScheme.onPrimaryContainer,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              S.of(context).finishCurrentTrack,
                              style: textTheme.bodySmall?.copyWith(
                                    color: colorScheme.onPrimaryContainer,
                                  ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  _buildAdjustButton(
                    context,
                    ref,
                    colorScheme,
                    icon: Icons.add,
                    label: '+${S.of(context).nMinutes(5)}',
                    onTap: () {
                      ref
                          .read(sleepTimerProvider.notifier)
                          .addTime(const Duration(minutes: 5));
                    },
                  ),
                  _buildAdjustButton(
                    context,
                    ref,
                    colorScheme,
                    icon: Icons.add,
                    label: '+${S.of(context).nMinutes(10)}',
                    onTap: () {
                      ref
                          .read(sleepTimerProvider.notifier)
                          .addTime(const Duration(minutes: 10));
                    },
                  ),
                  _buildAdjustButton(
                    context,
                    ref,
                    colorScheme,
                    icon: Icons.cancel_outlined,
                    label: S.of(context).cancelTimer,
                    color: colorScheme.error,
                    onTap: () {
                      ref.read(sleepTimerProvider.notifier).cancelTimer();
                    },
                  ),
                ],
              ),
            ] else ...[
              SegmentedButton<bool>(
                segments: [
                  ButtonSegment(
                    value: false,
                    icon: const Icon(Icons.timer_outlined),
                    label: Text(S.of(context).duration),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: const Icon(Icons.schedule),
                    label: Text(S.of(context).specifyTime),
                  ),
                ],
                selected: {_isTimeMode},
                onSelectionChanged: (Set<bool> selected) {
                  setState(() {
                    _isTimeMode = selected.first;
                  });
                },
              ),
              const SizedBox(height: 20),
              if (_isTimeMode) ...[
                _buildTimePickerSection(context, ref, colorScheme, textTheme),
              ] else ...[
                Text(
                  S.of(context).selectTimerDuration,
                  style: textTheme.titleMedium,
                ),
                const SizedBox(height: 16),
                _buildTimeGrid(context, ref, colorScheme, textTheme),
                _buildWaitingForTrackEndSection(context, ref, textTheme),
              ],
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(S.of(context).close),
        ),
      ],
    );
  }

  Widget _buildWaitingForTrackEndSection(BuildContext context, WidgetRef ref, TextTheme textTheme) {
    return InkWell(
      onTap: () {
        setState(() {
          _finishCurrentTrack = !_finishCurrentTrack;
        });
      },
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: Checkbox(
                value: _finishCurrentTrack,
                onChanged: (value) {
                  setState(() {
                    _finishCurrentTrack = value ?? false;
                  });
                },
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(4),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              S.of(context).finishCurrentTrack,
              style: textTheme.bodyMedium,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTimePickerSection(BuildContext context, WidgetRef ref, ColorScheme colorScheme, TextTheme textTheme) {
    return Column(
      children: [
        Text(
          S.of(context).selectStopTime,
          style: textTheme.titleMedium,
        ),
        const SizedBox(height: 16),
        InkWell(
          onTap: () async {
            final TimeOfDay? picked = await showTimePicker(
              context: context,
              initialTime: _selectedTime,
              builder: (context, child) {
                return MediaQuery(
                  data: MediaQuery.of(context).copyWith(
                    alwaysUse24HourFormat: true,
                  ),
                  child: child!,
                );
              },
            );
            if (picked != null) {
              setState(() {
                _selectedTime = picked;
              });
            }
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.access_time,
                  size: 48,
                  color: colorScheme.onSecondaryContainer,
                ),
                const SizedBox(height: 12),
                Text(
                  _selectedTime.format(context),
                  style: textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSecondaryContainer,
                        fontSize: 40,
                      ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: () {
            final now = DateTime.now();
            final targetTime = DateTime(
              now.year,
              now.month,
              now.day,
              _selectedTime.hour,
              _selectedTime.minute,
            );

            final finalTime = targetTime.isBefore(now)
                ? targetTime.add(const Duration(days: 1))
                : targetTime;

            ref.read(sleepTimerProvider.notifier).setTimerUntil(
                  finalTime,
                  finishCurrentTrack: _finishCurrentTrack,
                );
            Navigator.of(context).pop();
          },
          icon: const Icon(Icons.check),
          label: Text(S.of(context).confirm),
        ),
      ],
    );
  }

  Widget _buildTimeGrid(BuildContext context, WidgetRef ref, ColorScheme colorScheme, TextTheme textTheme) {
    final presetTimes = [
      (const Duration(minutes: 5), S.of(context).nMinutes(5), Icons.timer),
      (const Duration(minutes: 10), S.of(context).nMinutes(10), Icons.timer),
      (const Duration(minutes: 15), S.of(context).nMinutes(15), Icons.bedtime_outlined),
      (const Duration(minutes: 30), S.of(context).nMinutes(30), Icons.bedtime_outlined),
      (const Duration(hours: 1), S.of(context).nHours(1), Icons.bedtime),
      (const Duration(hours: 2), S.of(context).nHours(2), Icons.bedtime),
    ];

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      alignment: WrapAlignment.center,
      children: presetTimes.map((preset) {
        final (duration, label, icon) = preset;
        return _buildTimeCard(
          context,
          ref,
          colorScheme,
          textTheme,
          duration: duration,
          label: label,
          icon: icon,
        );
      }).toList(),
    );
  }

  Widget _buildTimeCard(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme,
    TextTheme textTheme, {
    required Duration duration,
    required String label,
    required IconData icon,
  }) {
    return InkWell(
      onTap: () {
        ref.read(sleepTimerProvider.notifier).setTimer(
              duration,
              finishCurrentTrack: _finishCurrentTrack,
            );
      },
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 32,
              color: colorScheme.primary,
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdjustButton(
    BuildContext context,
    WidgetRef ref,
    ColorScheme colorScheme, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return OutlinedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        side: BorderSide(
          color: color ?? colorScheme.outline,
        ),
      ),
    );
  }
}