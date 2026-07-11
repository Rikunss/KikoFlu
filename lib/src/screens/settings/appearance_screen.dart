import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../player_buttons_settings_screen.dart';
import '../player_lyric_style_screen.dart';
import '../work_detail_display_settings_screen.dart';
import '../work_card_display_settings_screen.dart';
import '../../providers/theme_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/locale_provider.dart';

/// Appearance settings screen — MD3 consolidated section.
///
/// Groups: Theme (mode + color scheme), Language, Player Controls,
/// Display (Work Details, Work Cards, Page Size).
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = S.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsAppearance),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    _buildThemeSection(context, ref, s),
                    const SizedBox(height: 16),

                    _buildLanguageCard(context, ref, s),
                    const SizedBox(height: 16),

                    _buildPlayerControlsCard(context, ref, s),
                    const SizedBox(height: 16),

                    _buildDisplayCard(context, ref, s),
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

  Widget _buildThemeSection(BuildContext context, WidgetRef ref, S s) {
    final themeSettings = ref.watch(themeSettingsProvider);
    final theme = Theme.of(context);

    return Column(
      children: [
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.themeMode,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: SegmentedButton<AppThemeMode>(
                    segments: [
                      ButtonSegment(
                        value: AppThemeMode.system,
                        label: Text(s.themeModeSystem),
                        icon: const Icon(Icons.brightness_auto_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.light,
                        label: Text(s.themeModeLight),
                        icon: const Icon(Icons.light_mode_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.dark,
                        label: Text(s.themeModeDark),
                        icon: const Icon(Icons.dark_mode_rounded, size: 18),
                      ),
                      ButtonSegment(
                        value: AppThemeMode.trueBlack,
                        label: Text(s.themeModeTrueBlack),
                        icon: const Icon(Icons.contrast_rounded, size: 18),
                      ),
                    ],
                    selected: {themeSettings.themeMode},
                    onSelectionChanged: (selected) {
                      ref
                          .read(themeSettingsProvider.notifier)
                          .setThemeMode(selected.first);
                    },
                    showSelectedIcon: false,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          color: theme.colorScheme.surfaceContainerLow,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.colorTheme,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFF146683),
                      label: s.colorSchemeOceanBlue,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.oceanBlue,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.oceanBlue),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFFB4276E),
                      label: s.colorSchemeSakuraPink,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.sakuraPink,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.sakuraPink),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFF904D00),
                      label: s.colorSchemeSunsetOrange,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.sunsetOrange,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.sunsetOrange),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFF6750A4),
                      label: s.colorSchemeLavenderPurple,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.lavenderPurple,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.lavenderPurple),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFF3A6F41),
                      label: s.colorSchemeForestGreen,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.forestGreen,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.forestGreen),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFFC62828),
                      label: s.colorSchemeCrimsonRed,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.crimsonRed,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.crimsonRed),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFFFF8F00),
                      label: s.colorSchemeAmberGold,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.amberGold,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.amberGold),
                    ),
                    _buildColorSwatch(
                      context: context,
                      color: const Color(0xFF455A64),
                      label: s.colorSchemeSlateGray,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.slateGray,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.slateGray),
                    ),
                    _buildDynamicColorSwatch(
                      context: context,
                      s: s,
                      isSelected: themeSettings.colorSchemeType ==
                          ColorSchemeType.dynamic,
                      onTap: () => ref
                          .read(themeSettingsProvider.notifier)
                          .setColorSchemeType(ColorSchemeType.dynamic),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildColorSwatch({
    required BuildContext context,
    required Color color,
    required String label,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 6,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDynamicColorSwatch({
    required BuildContext context,
    required S s,
    required bool isSelected,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        width: 56,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 40,
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
                  color: isSelected
                      ? theme.colorScheme.primary
                      : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: isSelected
                  ? const Icon(Icons.check, color: Colors.white, size: 18)
                  : null,
            ),
            const SizedBox(height: 4),
            Text(
              s.colorSchemeDynamic,
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLanguageCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentLocale = ref.watch(localeProvider);

    String localeLabel;
    if (currentLocale == null) {
      localeLabel = s.languageSystem;
    } else if (currentLocale.scriptCode == 'Hant') {
      localeLabel = s.languageZhTw;
    } else {
      localeLabel = switch (currentLocale.languageCode) {
        'zh' => s.languageZh,
        'en' => s.languageEn,
        'ja' => s.languageJa,
        'ru' => s.languageRu,
        _ => currentLocale.languageCode,
      };
    }

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
              child: Icon(Icons.language_rounded, color: colorScheme.primary, size: 22),
            ),
            title: Text(s.settingsLanguage),
            subtitle: Text(
              localeLabel,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: () {
              HapticFeedback.lightImpact();
              _showLanguagePicker(context, ref, s);
            },
          ),
        );
  }

  void _showLanguagePicker(BuildContext context, WidgetRef ref, S s) {
    final currentLocale = ref.read(localeProvider);
    final options = <(String, Locale?)>[
      (s.languageSystem, null),
      (s.languageZh, const Locale('zh')),
      (s.languageZhTw, const Locale.fromSubtags(languageCode: 'zh', scriptCode: 'Hant')),
      (s.languageEn, const Locale('en')),
      (s.languageJa, const Locale('ja')),
      (s.languageRu, const Locale('ru')),
    ];

    showDialog(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(s.settingsLanguage),
        children: [
          RadioGroup<int>(
            groupValue: options.indexWhere(
              (o) =>
                  o.$2?.languageCode == currentLocale?.languageCode &&
                  o.$2?.scriptCode == currentLocale?.scriptCode,
            ),
            onChanged: (int? index) {
              if (index != null && index >= 0 && index < options.length) {
                ref.read(localeProvider.notifier).setLocale(options[index].$2);
                Navigator.of(ctx).pop();
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final option in options)
                  RadioListTile<int>(
                    title: Text(option.$1),
                    value: options.indexOf(option),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPlayerControlsCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isDesktop = theme.platform != TargetPlatform.android && theme.platform != TargetPlatform.iOS;
    final maxVisible = isDesktop ? 5 : 4;

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
                  child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                ),
                title: Text(s.playerButtonSettings),
                subtitle: Text(
                  s.buttonDisplayRulesDesc(maxVisible),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigate(context, const PlayerButtonsSettingsScreen());
                },
              ),
              Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.lyrics_rounded, color: colorScheme.primary, size: 22),
                ),
                title: Text(s.playerLyricStyle),
                subtitle: Text(
                  s.playerLyricStyleSubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigate(context, const PlayerLyricStyleScreen());
                },
              ),
            ],
          ),
    );
  }

  Widget _buildDisplayCard(BuildContext context, WidgetRef ref, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final pageSize = ref.watch(pageSizeProvider);

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
                  child: Icon(Icons.visibility_rounded, color: colorScheme.primary, size: 22),
                ),
                title: Text(s.workDetailDisplaySettings),
                subtitle: Text(
                  s.workDetailDisplaySubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigate(context, const WorkDetailDisplaySettingsScreen());
                },
              ),
              Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.grid_view_rounded, color: colorScheme.primary, size: 22),
                ),
                title: Text(s.workCardDisplaySettings),
                subtitle: Text(
                  s.workCardDisplaySubtitle,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
                onTap: () {
                  HapticFeedback.lightImpact();
                  _navigate(context, const WorkCardDisplaySettingsScreen());
                },
              ),
              Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
              ListTile(
                leading: CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.format_list_numbered_rounded, color: colorScheme.primary, size: 22),
                ),
                title: Text(s.pageSizeSettings),
                subtitle: Text(
                  s.pageSizeCurrent(pageSize),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: DropdownButton<int>(
                  value: pageSize,
                  underline: const SizedBox(),
                  items: [20, 40, 60, 100].map((int value) {
                    return DropdownMenuItem<int>(
                      value: value,
                      child: Text(value.toString()),
                    );
                  }).toList(),
                  onChanged: (int? newValue) {
                    if (newValue != null) {
                      HapticFeedback.lightImpact();
                      ref
                          .read(pageSizeProvider.notifier)
                          .updatePageSize(newValue);
                    }
                  },
                ),
              ),
            ],
          ),
        );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}