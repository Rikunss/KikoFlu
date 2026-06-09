import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/equalizer_provider.dart';
import '../services/equalizer_service.dart';
import '../widgets/scrollable_appbar.dart';

/// Equalizer settings screen
class EqualizerScreen extends ConsumerStatefulWidget {
  const EqualizerScreen({super.key});

  @override
  ConsumerState<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends ConsumerState<EqualizerScreen> {
  @override
  void initState() {
    super.initState();
    // Initialize EQ service
    EqualizerService.instance.initialize();
  }

  @override
  Widget build(BuildContext context) {
    final eqState = ref.watch(equalizerStateProvider);
    final isSupported = ref.watch(equalizerDeviceSupportProvider);
    final s = S.of(context);

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(s.equalizerTitle, style: const TextStyle(fontSize: 18)),
        actions: [
          if (eqState.valueOrNull != null)
            IconButton(
              icon: Icon(
                eqState.value!.enabled
                    ? Icons.equalizer
                    : Icons.equalizer_outlined,
                color: eqState.value!.enabled
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              tooltip: eqState.value!.enabled
                  ? s.equalizerEnabled
                  : s.equalizerDisabled,
              onPressed: () {
                EqualizerService.instance.toggleEnabled();
              },
            ),
        ],
      ),
      body: eqState.when(
        data: (state) {
          if (!Platform.isAndroid && !Platform.isIOS && !Platform.isMacOS) {
            return _buildUnsupported(context, s);
          }
          if (!isSupported && !Platform.isAndroid) {
            return _buildUnsupported(context, s);
          }
          return _buildEqualizer(context, state, s);
        },
        loading: () => _buildLoadingSkeleton(context),
        error: (err, _) => _buildErrorState(context, err.toString(), s),
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 0.7),
          duration: const Duration(milliseconds: 1000),
          builder: (context, value, child) {
            return Card(
              elevation: 0,
              color: cs.surfaceContainerLow,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: value * 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            height: 14,
                            width: 100,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: value * 0.6),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                          const SizedBox(height: 6),
                          Container(
                            height: 12,
                            width: 140,
                            decoration: BoxDecoration(
                              color: cs.surfaceContainerHighest
                                  .withValues(alpha: value * 0.4),
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 40,
                      height: 24,
                      decoration: BoxDecoration(
                        color: cs.surfaceContainerHighest
                            .withValues(alpha: value * 0.3),
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
        const SizedBox(height: 16),
        // Band sliders skeleton
        TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.3, end: 0.7),
          duration: const Duration(milliseconds: 1000),
          builder: (context, value, child) {
            return Opacity(
              opacity: value,
              child: Card(
                elevation: 0,
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    height: 280,
                    child: Center(
                      child: CircularProgressIndicator(),
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

  Widget _buildErrorState(BuildContext context, String error, S s) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 40, color: cs.error),
            ),
            const SizedBox(height: 20),
            Text(
              'Error',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUnsupported(BuildContext context, S s) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.equalizer_outlined,
                size: 40,
                color: cs.primary,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              s.equalizerNotSupported,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              Platform.isAndroid
                  ? s.equalizerNotSupportedAndroid
                  : s.equalizerNotSupportedOther,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEqualizer(BuildContext context, EqualizerState state, S s) {
    final cs = Theme.of(context).colorScheme;
    final activePresetName = EqualizerService.presets
        .where((p) => p.id == state.activePresetId)
        .firstOrNull
        ?.name ?? (state.activePresetId == 'custom' ? s.equalizerCustom : '');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Enable/disable switch
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            secondary: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(
                state.enabled ? Icons.equalizer : Icons.equalizer_outlined,
                color: state.enabled ? cs.primary : cs.onSurfaceVariant,
                size: 22,
              ),
            ),
            title: Text(s.equalizerTitle),
            subtitle: Text(
              state.enabled
                  ? '${s.equalizerActive}: $activePresetName'
                  : s.equalizerDisabled,
              style: TextStyle(
                color: state.enabled ? cs.primary : cs.onSurfaceVariant,
              ),
            ),
            value: state.enabled,
            onChanged: (_) {
              HapticFeedback.lightImpact();
              EqualizerService.instance.toggleEnabled();
            },
          ),
        ),
        const SizedBox(height: 16),

        // Presets
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.equalizerPresets,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: EqualizerService.presets.map((preset) {
                    final isActive = state.activePresetId == preset.id;
                    return FilterChip(
                      label: Text(preset.name),
                      selected: isActive,
                      selectedColor: cs.primaryContainer,
                      onSelected: state.enabled
                          ? (selected) {
                              HapticFeedback.lightImpact();
                              if (selected) {
                                EqualizerService.instance
                                    .applyPreset(preset.id);
                              }
                            }
                          : null,
                    );
                  }).toList(),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Band sliders
        Row(
          children: [
            Text(
              s.equalizerCustomBands,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const Spacer(),
            Text(
              '${state.gains.where((g) => g > 0).isNotEmpty ? "+" : ""}${state.gains.isEmpty ? "0" : state.gains.reduce((a, b) => a.abs() > b.abs() ? a : b).toStringAsFixed(1)}dB',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                  ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: cs.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: SizedBox(
              height: 280,
              child: Column(
                children: [
                  // dB scale labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: [
                        Text(
                          '+12dB',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const Spacer(),
                        Text(
                          '0dB',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                        const Spacer(),
                        Text(
                          '-12dB',
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  // Band sliders
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: List.generate(10, (index) {
                        return Expanded(
                          child: _BandSlider(
                            index: index,
                            label: EqualizerService.bandLabels[index],
                            value: state.gains[index],
                            enabled: state.enabled,
                            onChanged: (value) {
                              EqualizerService.instance
                                  .setBandGain(index, value);
                            },
                          ),
                        );
                      }),
                    ),
                  ),
                  // Band labels
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Row(
                      children: EqualizerService.bandLabels.map((label) {
                        return Expanded(
                          child: Text(
                            label,
                            textAlign: TextAlign.center,
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),

        // Reset button
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              HapticFeedback.lightImpact();
              EqualizerService.instance.resetToFlat();
            },
            icon: const Icon(Icons.restart_alt),
            label: Text(s.equalizerReset),
          ),
        ),
        const SizedBox(height: 16),

        // Info card
        if (!Platform.isAndroid) ...[
          Card(
            elevation: 0,
            color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.equalizerInfo,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.4,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }
}

/// Individual band slider widget
class _BandSlider extends StatelessWidget {
  final int index;
  final String label;
  final double value;
  final bool enabled;
  final ValueChanged<double> onChanged;

  const _BandSlider({
    required this.index,
    required this.label,
    required this.value,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final gainColor = value > 0
        ? cs.tertiary
        : value < 0
            ? cs.error
            : cs.onSurfaceVariant;

    return Column(
      children: [
        // Current dB value
        Text(
          '${value >= 0 ? "+" : ""}${value.toStringAsFixed(0)}',
          style: TextStyle(
            fontSize: 9,
            fontWeight: value.abs() > 3 ? FontWeight.bold : FontWeight.normal,
            color: gainColor,
          ),
        ),
        const SizedBox(height: 2),
        // Vertical slider
        Expanded(
          child: RotatedBox(
            quarterTurns: -1,
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                activeTrackColor: value > 0
                    ? cs.tertiary
                    : value < 0
                        ? cs.error
                        : cs.primary,
                inactiveTrackColor: cs.surfaceContainerHighest,
                thumbColor: enabled
                    ? (value > 0
                        ? cs.tertiary
                        : value < 0
                            ? cs.error
                            : cs.primary)
                    : cs.onSurface.withValues(alpha: 0.3),
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 6,
                ),
                overlayShape: const RoundSliderOverlayShape(
                  overlayRadius: 12,
                ),
              ),
              child: Slider(
                value: value.clamp(-12.0, 12.0),
                min: -12,
                max: 12,
                divisions: 24,
                onChanged: enabled ? onChanged : null,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
