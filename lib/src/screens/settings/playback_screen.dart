import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../equalizer_screen.dart';
import '../audio_format_settings_screen.dart';
import 'usb_dac_settings_screen.dart';
import '../../providers/audio_provider.dart';
import '../../providers/equalizer_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/equalizer_service.dart';
import '../../services/audio_player_service.dart';
import '../../services/replay_gain_service.dart';
import '../../utils/snackbar_util.dart';

/// Playback settings screen — MD3 consolidated section.
///
/// Groups: Equalizer, Crossfade & Gapless, Audio Format Priority,
/// Audio Passthrough — previously scattered across PreferencesScreen.
class PlaybackScreen extends ConsumerWidget {
  const PlaybackScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsPlayback),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Equalizer Section ──
                    _buildEqualizerCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Crossfade & Gapless Section ──
                    _buildCrossfadeCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── ReplayGain Section ──
                    _buildReplayGainCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Audio Format Priority Section ──
                    _buildAudioFormatCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Preferred Sample Rate Section ──
                    _buildSampleRateCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── USB DAC (Beta) Section ──
                    _buildUsbDacCard(context, ref, s),
                    const SizedBox(height: 16),

                    // ── Audio Passthrough Section ──
                    _buildPassthroughCard(context, ref, s),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ]),
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Equalizer Card
  // ──────────────────────────────────────────────

  Widget _buildEqualizerCard(BuildContext context, WidgetRef ref, S s) {
    final eqEnabled = ref.watch(equalizerEnabledProvider);
    final eqPreset = ref.watch(equalizerActivePresetProvider);
    final isSupported = ref.watch(equalizerDeviceSupportProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final presetName = EqualizerService.presets
            .where((p) => p.id == eqPreset)
            .firstOrNull
            ?.name ??
        (eqPreset == 'custom' ? s.equalizerCustom : '');

    final subtitle = eqEnabled && isSupported
        ? '${s.equalizerActive}: $presetName'
        : !isSupported
            ? s.equalizerNotSupported
            : s.equalizerDisabled;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.equalizer, color: colorScheme.primary, size: 22),
            ),
            title: Text(s.equalizerTitle),
            subtitle: Text(
              subtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: eqEnabled && isSupported
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: () {
              HapticFeedback.lightImpact();
              _navigate(context, const EqualizerScreen());
            },
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Crossfade & Gapless Card
  // ──────────────────────────────────────────────

  Widget _buildCrossfadeCard(BuildContext context, WidgetRef ref, S s) {
    final crossfadeMs = ref.watch(crossfadeDurationProvider);
    final crossfadeEnabled = crossfadeMs > 0;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.swap_horiz_rounded, color: colorScheme.primary, size: 22),
            ),
            title: Text(s.crossfadeTitle),
            subtitle: Text(
              crossfadeEnabled
                  ? s.crossfadeEnabledWithDuration(crossfadeMs)
                  : s.gaplessPlaybackEnabled,
              style: theme.textTheme.bodySmall?.copyWith(
                color: crossfadeEnabled
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            value: crossfadeEnabled,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              final newMs = value ? 3000 : 0;
              ref.read(crossfadeDurationProvider.notifier).updateDuration(newMs);
              ref.read(audioPlayerControllerProvider.notifier).setCrossfadeDuration(
                    Duration(milliseconds: newMs),
                  );
              if (context.mounted) {
                SnackBarUtil.showInfo(
                  context,
                  value
                      ? s.crossfadeEnabledWithDuration(newMs)
                      : s.gaplessPlaybackEnabled,
                );
              }
            },
          ),
          if (crossfadeEnabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Duration label + value
                  Row(
                    children: [
                      Text(
                        s.crossfadeDurationLabel,
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        _formatDurationLabel(crossfadeMs),
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: crossfadeMs.toDouble(),
                    min: 500,
                    max: 10000,
                    divisions: 19,
                    label: _formatDurationLabel(crossfadeMs),
                    onChanged: (value) {
                      final rounded = (value / 500).round() * 500;
                      ref.read(crossfadeDurationProvider.notifier).updateDuration(rounded);
                      ref.read(audioPlayerControllerProvider.notifier).setCrossfadeDuration(
                            Duration(milliseconds: rounded),
                          );
                    },
                  ),
                  // Min / Max labels
                  Row(
                    children: [
                      Text(
                        s.crossfadeMinLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        s.crossfadeMaxLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            s.crossfadeDescription,
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _formatDurationLabel(int ms) {
    if (ms >= 1000) {
      return '${(ms / 1000).toStringAsFixed(1)}s';
    }
    return '${ms}ms';
  }

  // ──────────────────────────────────────────────
  // ReplayGain Card
  // ──────────────────────────────────────────────

  Widget _buildReplayGainCard(BuildContext context, WidgetRef ref, S s) {
    final rgSettings = ref.watch(replayGainSettingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.volume_up, color: colorScheme.primary, size: 22),
            ),
            title: const Text('ReplayGain'),
            subtitle: Text(
              rgSettings.enabled
                  ? 'Pre-amp: ${rgSettings.preampDb.toStringAsFixed(1)} dB'
                  : 'Off — gain metadata ignored',
              style: theme.textTheme.bodySmall?.copyWith(
                color: rgSettings.enabled
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            value: rgSettings.enabled,
            onChanged: (value) {
              HapticFeedback.lightImpact();
              ref.read(replayGainSettingsProvider.notifier).toggle(value);
              ReplayGainService.instance.setEnabled(value);
              AudioPlayerService.instance.reapplyAudioGain();
              if (context.mounted) {
                SnackBarUtil.showInfo(
                  context,
                  value ? 'ReplayGain enabled' : 'ReplayGain disabled',
                );
              }
            },
          ),
          if (rgSettings.enabled) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Pre-amp label + value
                  Row(
                    children: [
                      Text(
                        'Pre-amp',
                        style: theme.textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${rgSettings.preampDb.toStringAsFixed(1)} dB',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Slider(
                    value: rgSettings.preampDb,
                    min: -12.0,
                    max: 12.0,
                    divisions: 48, // 0.5 dB steps
                    label: '${rgSettings.preampDb.toStringAsFixed(1)} dB',
                    onChanged: (value) {
                      ref
                          .read(replayGainSettingsProvider.notifier)
                          .setPreampDb(value);
                      ReplayGainService.instance.setPreampDb(value);
                      AudioPlayerService.instance.reapplyAudioGain();
                    },
                  ),
                  // Min / Max labels
                  Row(
                    children: [
                      Text(
                        '-12 dB',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        ' (quieter)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '(louder)',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant
                              .withValues(alpha: 0.6),
                        ),
                      ),
                      Text(
                        ' +12 dB',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 16,
                          color: colorScheme.primary,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ReplayGain applies a gain adjustment based on the '
                            'track\'s loudness metadata. Pre-amp adds an '
                            'additional boost or cut on top.',
                            style: theme.textTheme.bodySmall?.copyWith(
                              height: 1.4,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Audio Format Priority Card
  // ──────────────────────────────────────────────

  Widget _buildAudioFormatCard(BuildContext context, WidgetRef ref, S s) {
    final preference = ref.watch(audioFormatPreferenceProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show first 2 formats as summary, "+X more"
    final topFormats = preference.priority.take(2).map((f) => f.displayName).join(', ');
    final remaining = preference.priority.length - 2;
    final subtitle = remaining > 0
        ? '$topFormats +$remaining'
        : topFormats;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.audio_file, color: colorScheme.primary, size: 22),
        ),
        title: Text(s.audioFormatPreference),
        subtitle: Text(
          subtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: () {
          HapticFeedback.lightImpact();
          _navigate(context, const AudioFormatSettingsScreen());
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Preferred Sample Rate Card
  // ──────────────────────────────────────────────

  Widget _buildSampleRateCard(BuildContext context, WidgetRef ref, S s) {
    final currentRate = ref.watch(preferredSampleRateProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.tune, color: colorScheme.primary, size: 22),
            ),
            title: Text(s.preferredSampleRate),
            subtitle: Text(
              currentRate == PreferredSampleRate.auto
                  ? s.preferredSampleRateAuto
                  : currentRate.displayName,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: DropdownButton<PreferredSampleRate>(
              value: currentRate,
              underline: const SizedBox.shrink(),
              isDense: true,
              onChanged: (rate) {
                if (rate != null) {
                  HapticFeedback.lightImpact();
                  ref.read(preferredSampleRateProvider.notifier).updateRate(rate);
                }
              },
              items: PreferredSampleRate.values.map((rate) {
                return DropdownMenuItem(
                  value: rate,
                  child: Text(
                    rate == PreferredSampleRate.auto
                        ? s.preferredSampleRateAuto
                        : rate.displayName,
                    style: theme.textTheme.bodySmall,
                  ),
                );
              }).toList(),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Icon(
                  Icons.info_outline,
                  size: 14,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    s.preferredSampleRateDesc,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }


  // ──────────────────────────────────────────────
  // USB DAC (Beta) Card
  // ──────────────────────────────────────────────

  Widget _buildUsbDacCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!Platform.isAndroid) {
      return const SizedBox.shrink();
    }

    final settings = ref.watch(bitPerfectPlaybackProvider);

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.usb, color: colorScheme.primary, size: 22),
        ),
        title: Row(
          children: [
            const Text('USB DAC (Beta)'),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: colorScheme.tertiaryContainer,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                'Beta',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: colorScheme.onTertiaryContainer,
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
        subtitle: Text(
          settings.enabled
              ? 'USB DAC Routing: Active'
              : 'USB DAC, AAudio exclusive mode',
          style: theme.textTheme.bodySmall?.copyWith(
            color: settings.enabled
                ? colorScheme.primary.withValues(alpha: 0.8)
                : colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: () {
          HapticFeedback.lightImpact();
          _navigate(context, const UsbDacSettingsScreen());
        },
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Audio Passthrough Card
  // ──────────────────────────────────────────────

  Widget _buildPassthroughCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    if (!Platform.isAndroid && !Platform.isWindows && !Platform.isMacOS) {
      return const SizedBox.shrink();
    }

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: SwitchListTile(
        secondary: CircleAvatar(
          backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
          child: Icon(Icons.surround_sound, color: colorScheme.primary, size: 22),
        ),
        title: Text(s.audioPassthrough),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Platform.isWindows || Platform.isMacOS
                  ? s.audioPassthroughDescWindows
                  : s.audioPassthroughDescAndroid,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            if (Platform.isWindows) ...[
              const SizedBox(height: 4),
              Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      'Restart playback to apply',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                        fontStyle: FontStyle.italic,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        value: ref.watch(audioPassthroughProvider),
        onChanged: (value) async {
          HapticFeedback.lightImpact();
          if (value) {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (context) => AlertDialog(
                title: Text(s.warning),
                content: Text(s.audioPassthroughWarning),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(false),
                    child: Text(s.cancel),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(true),
                    child: Text(s.confirm),
                  ),
                ],
              ),
            );
            if (confirmed != true) return;
          }

          ref.read(audioPassthroughProvider.notifier).toggle(value);

          // On desktop, sync the AudioPlayerService exclusive mode flag
          // so the audio info sheet shows the correct status.
          if (Platform.isWindows || Platform.isMacOS) {
            AudioPlayerService.instance.setExclusiveMode(value);
          }

          if (context.mounted) {
            SnackBarUtil.showSuccess(
              context,
              value
                  ? (Platform.isWindows || Platform.isMacOS
                      ? s.exclusiveModeEnabled
                      : s.audioPassthroughEnabled)
                  : s.audioPassthroughDisabled,
            );
          }
        },
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
