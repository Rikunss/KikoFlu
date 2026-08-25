import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../providers/floating_lyric_style_provider.dart';
import '../widgets/scrollable_appbar.dart';

class FloatingLyricStyleScreen extends ConsumerWidget {
  const FloatingLyricStyleScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final style = ref.watch(floatingLyricStyleProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(S.of(context).floatingLyricStyle, style: const TextStyle(fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildPreviewCard(context, style, colorScheme, textTheme),
          const SizedBox(height: 24),

          _buildPresetsCard(context, ref, colorScheme, textTheme),
          const SizedBox(height: 24),

          _buildTransparencyModeCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildFontSizeCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildOpacityCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildFontCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildColorsCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildShadowCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildShapeCard(context, ref, style, colorScheme, textTheme),
          const SizedBox(height: 16),

          _buildResetButton(context, ref),
          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildPreviewCard(BuildContext context, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).preview,
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            Center(
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: style.effectivePaddingHorizontal,
                  vertical: style.effectivePaddingVertical,
                ),
                decoration: BoxDecoration(
                  color: style.backgroundColorWithOpacity,
                  borderRadius: BorderRadius.circular(style.effectiveCornerRadius),
                ),
                child: Text(
                  S.of(context).sampleSubtitleContent,
                  style: TextStyle(
                    color: style.textColor,
                    fontSize: style.fontSize,
                    fontWeight: style.fontWeight,
                    fontFamily: style.fontFamily.isNotEmpty ? style.fontFamily : null,
                    letterSpacing: 0.5,
                    shadows: style.shadowEnabled
                        ? [
                            Shadow(
                              offset: const Offset(1.0, 1.0),
                              blurRadius: style.shadowBlur,
                              color: style.shadowColor,
                            ),
                            Shadow(
                              offset: const Offset(-1.0, -1.0),
                              blurRadius: style.shadowBlur,
                              color: style.shadowColor,
                            ),
                          ]
                        : null,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPresetsCard(BuildContext context, WidgetRef ref, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).presetStyles,
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: FloatingLyricStylePreset.values.map((preset) {
                return GestureDetector(
                  onTap: () {
                    ref
                        .read(floatingLyricStyleProvider.notifier)
                        .applyPreset(preset, context);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: preset.previewBg,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: colorScheme.outline.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        color: preset.previewTextColor,
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTransparencyModeCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Display Mode',
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),
            SegmentedButton<TransparencyMode>(
              segments: const [
                ButtonSegment(
                  value: TransparencyMode.pill,
                  label: Text('Pill'),
                  icon: Icon(Icons.rounded_corner, size: 18),
                ),
                ButtonSegment(
                  value: TransparencyMode.overlay,
                  label: Text('Overlay'),
                  icon: Icon(Icons.visibility_off, size: 18),
                ),
                ButtonSegment(
                  value: TransparencyMode.card,
                  label: Text('Card'),
                  icon: Icon(Icons.crop_square, size: 18),
                ),
              ],
              selected: {style.transparencyMode},
              onSelectionChanged: (selected) {
                if (selected.isNotEmpty) {
                  ref.read(floatingLyricStyleProvider.notifier)
                      .updateTransparencyMode(selected.first);
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontSizeCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  S.of(context).fontSize,
                  style: textTheme.titleSmall,
                ),
                Text(
                  '${style.fontSize.toInt()}',
                  style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: style.fontSize,
              min: 10,
              max: 28,
              divisions: 18,
              label: '${style.fontSize.toInt()}',
              onChanged: (value) {
                ref
                    .read(floatingLyricStyleProvider.notifier)
                    .updateFontSize(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpacityCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  S.of(context).backgroundOpacity,
                  style: textTheme.titleSmall,
                ),
                Text(
                  '${(style.opacity * 100).toInt()}%',
                  style: textTheme.bodyMedium?.copyWith(
                        color: colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            Slider(
              value: style.opacity,
              min: 0.0,
              max: 1.0,
              divisions: 20,
              label: '${(style.opacity * 100).toInt()}%',
              onChanged: (value) {
                ref
                    .read(floatingLyricStyleProvider.notifier)
                    .updateOpacity(value);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Font Settings',
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 12),

            // Font Family
            Text('Font Family', style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildFontChip(context, ref, 'System', '', style.fontFamily, colorScheme),
                _buildFontChip(context, ref, 'Monospace', 'monospace', style.fontFamily, colorScheme),
                _buildFontChip(context, ref, 'Serif', 'serif', style.fontFamily, colorScheme),
              ],
            ),
            const SizedBox(height: 16),

            // Font Weight
            Text('Font Weight', style: textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildWeightChip(context, ref, 'Light', FontWeight.w300, style.fontWeight, colorScheme),
                _buildWeightChip(context, ref, 'Regular', FontWeight.w400, style.fontWeight, colorScheme),
                _buildWeightChip(context, ref, 'Medium', FontWeight.w500, style.fontWeight, colorScheme),
                _buildWeightChip(context, ref, 'SemiBold', FontWeight.w600, style.fontWeight, colorScheme),
                _buildWeightChip(context, ref, 'Bold', FontWeight.bold, style.fontWeight, colorScheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFontChip(BuildContext context, WidgetRef ref, String label, String family, String currentFamily, ColorScheme colorScheme) {
    final isSelected = currentFamily == family;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(floatingLyricStyleProvider.notifier).updateFontFamily(family);
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : null,
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
    );
  }

  Widget _buildWeightChip(BuildContext context, WidgetRef ref, String label, FontWeight weight, FontWeight currentWeight, ColorScheme colorScheme) {
    final isSelected = currentWeight == weight;
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (_) {
        ref.read(floatingLyricStyleProvider.notifier).updateFontWeight(weight);
      },
      selectedColor: colorScheme.primaryContainer,
      labelStyle: TextStyle(
        color: isSelected ? colorScheme.onPrimaryContainer : null,
        fontWeight: isSelected ? FontWeight.bold : null,
      ),
    );
  }

  Widget _buildColorsCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).colorSettings,
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 16),
            _buildColorPickerRow(
              context,
              ref,
              S.of(context).fontColor,
              style.textColor,
              (color) {
                ref.read(floatingLyricStyleProvider.notifier).updateTextColor(color);
              },
              colorScheme,
            ),
            const SizedBox(height: 16),
            _buildColorPickerRow(
              context,
              ref,
              S.of(context).backgroundColor,
              style.backgroundColor,
              (color) {
                ref.read(floatingLyricStyleProvider.notifier).updateBackgroundColor(color);
              },
              colorScheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildColorPickerRow(
    BuildContext context,
    WidgetRef ref,
    String label,
    Color currentColor,
    Function(Color) onColorSelected,
    ColorScheme colorScheme,
  ) {
    final presetColors = [
      Colors.white,
      Colors.black,
      const Color(0xFF212121),
      const Color(0xFFE3F2FD),
      const Color(0xFFFFF9C4),
      const Color(0xFFFFCDD2),
      const Color(0xFFC8E6C9),
      const Color(0xFF1A237E),
      const Color(0xFF0D47A1),
      const Color(0xFF1B5E20),
      const Color(0xFFE91E63),
      const Color(0xFF6A1B9A),
      const Color(0xFF2196F3),
      const Color(0xFF4CAF50),
      const Color(0xFFFF9800),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodyMedium),
            // Current color circle + edit button
            GestureDetector(
              onTap: () => _openColorPicker(context, currentColor, onColorSelected),
              child: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: currentColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outline.withValues(alpha: 0.5),
                    width: 2,
                  ),
                ),
                child: Icon(
                  Icons.edit,
                  size: 14,
                  color: currentColor.computeLuminance() > 0.5
                      ? Colors.black
                      : Colors.white,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [...presetColors, null].map((color) {
            if (color == null) {
              // Custom color button
              return GestureDetector(
                onTap: () => _openColorPicker(context, currentColor, onColorSelected),
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: colorScheme.outline.withValues(alpha: 0.3),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.add,
                    size: 18,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              );
            }
            final isSelected = color.toARGB32() == currentColor.toARGB32();
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: isSelected
                        ? colorScheme.primary
                        : Colors.grey.withValues(alpha: 0.3),
                    width: isSelected ? 3 : 1,
                  ),
                  boxShadow: isSelected
                      ? [
                          BoxShadow(
                            color: colorScheme.primary.withValues(alpha: 0.4),
                            blurRadius: 6,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
                child: isSelected
                    ? Icon(
                        Icons.check,
                        color: color.computeLuminance() > 0.5
                            ? Colors.black
                            : Colors.white,
                        size: 18,
                      )
                    : null,
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _openColorPicker(BuildContext context, Color currentColor, Function(Color) onColorSelected) {
    Color pickerColor = currentColor;
    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: const Text('Pick a color'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Color grid
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Colors.white, Colors.black, const Color(0xFF212121),
                  const Color(0xFFE3F2FD), const Color(0xFFFFF9C4), const Color(0xFFFFCDD2),
                  const Color(0xFFC8E6C9), const Color(0xFF1A237E), const Color(0xFF0D47A1),
                  const Color(0xFF1B5E20), const Color(0xFFE91E63), const Color(0xFF6A1B9A),
                  const Color(0xFF2196F3), const Color(0xFF4CAF50), const Color(0xFFFF9800),
                  const Color(0xFF795548), const Color(0xFF607D8B), const Color(0xFFF44336),
                  const Color(0xFF9C27B0), const Color(0xFF3F51B5), const Color(0xFF009688),
                ].map((color) => GestureDetector(
                  onTap: () => setDialogState(() => pickerColor = color),
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: pickerColor.toARGB32() == color.toARGB32()
                            ? Colors.blue
                            : Colors.grey.withValues(alpha: 0.3),
                        width: pickerColor.toARGB32() == color.toARGB32() ? 3 : 1,
                      ),
                    ),
                  ),
                )).toList(),
              ),
              const SizedBox(height: 16),
              // Preview
              Container(
                width: double.infinity,
                height: 40,
                decoration: BoxDecoration(
                  color: pickerColor,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
                ),
                child: Center(
                  child: Text(
                    'Preview',
                    style: TextStyle(
                      color: pickerColor.computeLuminance() > 0.5 ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                onColorSelected(pickerColor);
                Navigator.pop(context);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildShadowCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Text Shadow',
                  style: textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                Switch(
                  value: style.shadowEnabled,
                  onChanged: (val) {
                    ref.read(floatingLyricStyleProvider.notifier)
                        .updateShadowEnabled(val);
                  },
                ),
              ],
            ),
            if (style.shadowEnabled) ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Shadow Blur', style: textTheme.bodyMedium),
                  Text(
                    '${style.shadowBlur.toStringAsFixed(1)}',
                    style: textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Slider(
                value: style.shadowBlur,
                min: 0,
                max: 10,
                divisions: 20,
                label: style.shadowBlur.toStringAsFixed(1),
                onChanged: (value) {
                  ref.read(floatingLyricStyleProvider.notifier)
                      .updateShadowBlur(value);
                },
              ),
              const SizedBox(height: 8),
              _buildColorPickerRow(
                context,
                ref,
                'Shadow Color',
                style.shadowColor,
                (color) {
                  ref.read(floatingLyricStyleProvider.notifier)
                      .updateShadowColor(color);
                },
                colorScheme,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildShapeCard(BuildContext context, WidgetRef ref, FloatingLyricStyle style, ColorScheme colorScheme, TextTheme textTheme) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).shapeSettings,
              style: textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 8),
            _buildSliderRow(
              context,
              S.of(context).cornerRadius,
              style.cornerRadius,
              0, 24, 24,
              (v) => ref.read(floatingLyricStyleProvider.notifier).updateCornerRadius(v),
              colorScheme,
            ),
            const SizedBox(height: 8),
            _buildSliderRow(
              context,
              S.of(context).horizontalPadding,
              style.paddingHorizontal,
              12, 40, 28,
              (v) => ref.read(floatingLyricStyleProvider.notifier).updatePaddingHorizontal(v),
              colorScheme,
            ),
            const SizedBox(height: 8),
            _buildSliderRow(
              context,
              S.of(context).verticalPadding,
              style.paddingVertical,
              6, 20, 14,
              (v) => ref.read(floatingLyricStyleProvider.notifier).updatePaddingVertical(v),
              colorScheme,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderRow(
    BuildContext context,
    String label,
    double value,
    double min,
    double max,
    int divisions,
    Function(double) onChanged,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(label, style: Theme.of(context).textTheme.bodyMedium),
                  Text(
                    '${value.toInt()}',
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
              Slider(
                value: value,
                min: min,
                max: max,
                divisions: divisions,
                label: '${value.toInt()}',
                onChanged: onChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildResetButton(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: () {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(S.of(context).resetStyle),
            content: Text(S.of(context).resetStyleConfirm),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(S.of(context).cancel),
              ),
              FilledButton(
                onPressed: () {
                  ref.read(floatingLyricStyleProvider.notifier).reset();
                  Navigator.pop(context);
                },
                child: Text(S.of(context).reset),
              ),
            ],
          ),
        );
      },
      icon: const Icon(Icons.restore),
      label: Text(S.of(context).restoreDefaultStyle),
    );
  }
}
