import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../widgets/scrollable_appbar.dart';

class ThemeSettingsScreen extends ConsumerWidget {
  const ThemeSettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(S.of(context).themeSettings, style: const TextStyle(fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    S.of(context).themeMode,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                RadioGroup<AppThemeMode>(
                  groupValue: themeSettings.themeMode,
                  onChanged: (AppThemeMode? value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setThemeMode(value);
                    }
                  },
                  child: Column(
                    children: [
                      RadioListTile<AppThemeMode>(
                        title: Text(S.of(context).themeModeSystem),
                        subtitle: Text(S.of(context).themeModeSystemDesc),
                        value: AppThemeMode.system,
                      ),
                      RadioListTile<AppThemeMode>(
                        title: Text(S.of(context).themeModeLight),
                        subtitle: Text(S.of(context).themeModeLightDesc),
                        value: AppThemeMode.light,
                      ),
                      RadioListTile<AppThemeMode>(
                        title: Text(S.of(context).themeModeDark),
                        subtitle: Text(S.of(context).themeModeDarkDesc),
                        value: AppThemeMode.dark,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),
          Card(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    S.of(context).colorTheme,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                RadioGroup<ColorSchemeType>(
                  groupValue: themeSettings.colorSchemeType,
                  onChanged: (ColorSchemeType? value) {
                    if (value != null) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(value);
                    }
                  },
                  child: Column(
                    children: [
                      _buildColorSchemeOption(
                        context,
                        ref,
                        themeSettings,
                        ColorSchemeType.oceanBlue,
                        S.of(context).colorSchemeOceanBlue,
                        S.of(context).colorSchemeOceanBlueDesc,
                        const Color(0xFF146683),
                        colorScheme,
                        textTheme,
                      ),
                      _buildColorSchemeOption(
                        context,
                        ref,
                        themeSettings,
                        ColorSchemeType.sakuraPink,
                        S.of(context).colorSchemeSakuraPink,
                        S.of(context).colorSchemeSakuraPinkDesc,
                        const Color(0xFFB4276E),
                        colorScheme,
                        textTheme,
                      ),
                      _buildColorSchemeOption(
                        context,
                        ref,
                        themeSettings,
                        ColorSchemeType.sunsetOrange,
                        S.of(context).colorSchemeSunsetOrange,
                        S.of(context).colorSchemeSunsetOrangeDesc,
                        const Color(0xFF904D00),
                        colorScheme,
                        textTheme,
                      ),
                      _buildColorSchemeOption(
                        context,
                        ref,
                        themeSettings,
                        ColorSchemeType.lavenderPurple,
                        S.of(context).colorSchemeLavenderPurple,
                        S.of(context).colorSchemeLavenderPurpleDesc,
                        const Color(0xFF6750A4),
                        colorScheme,
                        textTheme,
                      ),
                      _buildColorSchemeOption(
                        context,
                        ref,
                        themeSettings,
                        ColorSchemeType.forestGreen,
                        S.of(context).colorSchemeForestGreen,
                        S.of(context).colorSchemeForestGreenDesc,
                        const Color(0xFF3A6F41),
                        colorScheme,
                        textTheme,
                      ),
                      const Divider(),
                      InkWell(
                        onTap: () {
                          ref
                              .read(themeSettingsProvider.notifier)
                              .setColorSchemeType(ColorSchemeType.dynamic);
                        },
                        child: Padding(
                          padding:        const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  gradient: const LinearGradient(
                                    colors: [
                                      Color(0xFFE91E63),
                                      Color(0xFF9C27B0),
                                      Color(0xFF2196F3),
                                      Color(0xFF4CAF50),
                                      Color(0xFFFFEB3B),
                                      Color(0xFFFF5722),
                                    ],
                                    begin: Alignment.topLeft,
                                    end: Alignment.bottomRight,
                                  ),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: themeSettings.colorSchemeType ==
                                            ColorSchemeType.dynamic
                                        ? colorScheme.primary
                                        : Colors.transparent,
                                    width: 2.5,
                                  ),
                                ),
                                child: themeSettings.colorSchemeType ==
                                        ColorSchemeType.dynamic
                                    ? const Icon(
                                        Icons.check,
                                        color: Colors.white,
                                        size: 16,
                                      )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      S.of(context).colorSchemeDynamic,
                                      style: textTheme.titleMedium?.copyWith(
                                            fontWeight:
                                                themeSettings
                                                            .colorSchemeType ==
                                                        ColorSchemeType.dynamic
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      S.of(context).colorSchemeDynamicDesc,
                                      style: textTheme.bodySmall?.copyWith(
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              const Radio<ColorSchemeType>(
                                value: ColorSchemeType.dynamic,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 16),

          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    S.of(context).themePreview,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.primaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              S.of(context).primaryContainer,
                              style: TextStyle(
                                color: colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.secondaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              S.of(context).secondaryContainer,
                              style: TextStyle(
                                color: colorScheme.onSecondaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.tertiaryContainer,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              S.of(context).tertiaryContainer,
                              style: TextStyle(
                                color: colorScheme.onTertiaryContainer,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Container(
                          height: 60,
                          decoration: BoxDecoration(
                            color: colorScheme.surface,
                            border: Border.all(
                              color: colorScheme.outline,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Center(
                            child: Text(
                              S.of(context).surfaceColor,
                              style: TextStyle(
                                color: colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSchemeOption(
    BuildContext context,
    WidgetRef ref,
    ThemeSettings themeSettings,
    ColorSchemeType type,
    String title,
    String subtitle,
    Color previewColor,
    ColorScheme colorScheme,
    TextTheme textTheme,
  ) {
    final isSelected = themeSettings.colorSchemeType == type;

    return InkWell(
      onTap: () {
        ref.read(themeSettingsProvider.notifier).setColorSchemeType(type);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: previewColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: previewColor.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: isSelected
                  ? const Icon(
                      Icons.check,
                      color: Colors.white,
                      size: 16,
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: textTheme.titleMedium?.copyWith(
                          fontWeight:
                              isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),
            Radio<ColorSchemeType>(
              value: type,
            ),
          ],
        ),
      ),
    );
  }
}