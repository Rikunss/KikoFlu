import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import 'audio_format_settings_screen.dart';
import 'blocked_items_screen.dart';
import 'equalizer_screen.dart';
import 'llm_settings_screen.dart';
import '../models/sort_options.dart';
import '../providers/audio_provider.dart';
import '../providers/equalizer_provider.dart';
import '../providers/settings_provider.dart';
import '../services/equalizer_service.dart';
import '../utils/l10n_extensions.dart';
import '../utils/snackbar_util.dart';
import '../widgets/scrollable_appbar.dart';
import '../widgets/sort_dialog.dart';

/// 偏好设置页面
class PreferencesScreen extends ConsumerWidget {
  const PreferencesScreen({super.key});

  void _showSubtitleLibraryPriorityDialog(BuildContext context, WidgetRef ref) {
    final currentPriority = ref.read(subtitleLibraryPriorityProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          S.of(context).subtitleLibraryPriority,
          style: const TextStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).selectSubtitlePriority,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            RadioGroup<SubtitleLibraryPriority>(
              groupValue: currentPriority,
              onChanged: (SubtitleLibraryPriority? value) {
                if (value != null) {
                  ref
                      .read(subtitleLibraryPriorityProvider.notifier)
                      .updatePriority(value);
                  Navigator.pop(context);
                  SnackBarUtil.showSuccess(
                    context,
                    S.of(context).setToValue(value.localizedName(context)),
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: SubtitleLibraryPriority.values.map((priority) {
                  return RadioListTile<SubtitleLibraryPriority>(
                    title: Text(priority.localizedName(context)),
                    subtitle: Text(
                      priority == SubtitleLibraryPriority.highest
                          ? S.of(context).subtitlePriorityHighestDesc
                          : S.of(context).subtitlePriorityLowestDesc,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: priority,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).close),
          ),
        ],
      ),
    );
  }

  void _showDefaultSortDialog(BuildContext context, WidgetRef ref) {
    final currentSort = ref.read(defaultSortProvider);

    showDialog(
      context: context,
      builder: (context) => CommonSortDialog(
        title: S.of(context).defaultSortSettings,
        currentOption: currentSort.order,
        currentDirection: currentSort.direction,
        availableOptions: SortOrder.values
            .where((option) => option != SortOrder.updatedAt)
            .toList(),
        onSort: (option, direction) {
          ref
              .read(defaultSortProvider.notifier)
              .updateDefaultSort(option, direction);
          SnackBarUtil.showSuccess(
            context,
            S.of(context).defaultSortUpdated,
          );
        },
        autoClose: false,
      ),
    );
  }

  void _showTranslationSourceDialog(BuildContext context, WidgetRef ref) {
    final currentSource = ref.read(translationSourceProvider);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          S.of(context).translationSourceSettings,
          style: const TextStyle(fontSize: 18),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              S.of(context).selectTranslationProvider,
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 16),
            RadioGroup<TranslationSource>(
              groupValue: currentSource,
              onChanged: (TranslationSource? value) {
                if (value != null) {
                  if (value == TranslationSource.llm) {
                    final llmSettings = ref.read(llmSettingsProvider);
                    if (llmSettings.apiKey.isEmpty) {
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text(S.of(context).needsConfiguration),
                          content:
                              Text(S.of(context).llmConfigRequiredMessage),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: Text(S.of(context).cancel),
                            ),
                            TextButton(
                              onPressed: () async {
                                Navigator.pop(context);
                                Navigator.pop(
                                    context);
                                await Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (context) =>
                                        const LLMSettingsScreen(),
                                  ),
                                );

                                final newSettings =
                                    ref.read(llmSettingsProvider);
                                if (newSettings.apiKey.isNotEmpty) {
                                  ref
                                      .read(
                                          translationSourceProvider.notifier)
                                      .updateSource(TranslationSource.llm);
                                  if (context.mounted) {
                                    SnackBarUtil.showSuccess(
                                      context,
                                      S.of(context).autoSwitchedToLlm,
                                    );
                                  }
                                }
                              },
                              child: Text(S.of(context).goToConfigure),
                            ),
                          ],
                        ),
                      );
                      return;
                    }
                  }

                  ref
                      .read(translationSourceProvider.notifier)
                      .updateSource(value);
                  Navigator.pop(context);
                  SnackBarUtil.showSuccess(
                    context,
                    S.of(context).setToValue(value.localizedName(context)),
                  );
                }
              },
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: TranslationSource.values.map((source) {
                  return RadioListTile<TranslationSource>(
                    title: Text(source.localizedName(context)),
                    subtitle: Text(
                      _getTranslationSourceDescription(context, source),
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    value: source,
                  );
                }).toList(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(S.of(context).close),
          ),
        ],
      ),
    );
  }

  String _getTranslationSourceDescription(BuildContext context, TranslationSource source) {
    final s = S.of(context);
    switch (source) {
      case TranslationSource.google:
        return s.translationDescGoogle;
      case TranslationSource.llm:
        return s.translationDescLlm;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;
    final platform = theme.platform;
    final priority = ref.watch(subtitleLibraryPriorityProvider);
    final defaultSort = ref.watch(defaultSortProvider);
    final translationSource = ref.watch(translationSourceProvider);

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(S.of(context).preferenceSettings, style: const TextStyle(fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: Icon(Icons.library_books, color: colorScheme.primary),
                  title: Text(S.of(context).subtitleLibraryPriority),
                  subtitle: Text(S.of(context).currentSettingLabel(priority.localizedName(context))),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showSubtitleLibraryPriorityDialog(context, ref);
                  },
                ),
                Divider(color: colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.sort, color: colorScheme.primary),
                  title: Text(S.of(context).defaultSortSettingTitle),
                  subtitle: Text(
                      '${defaultSort.order.localizedLabel(context)} - ${defaultSort.direction.localizedLabel(context)}'),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showDefaultSortDialog(context, ref);
                  },
                ),
                Divider(color: colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.translate, color: colorScheme.primary),
                  title: Text(S.of(context).translationSource),
                  subtitle: Text(S.of(context).currentSettingLabel(translationSource.localizedName(context))),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    _showTranslationSourceDialog(context, ref);
                  },
                ),
                if (translationSource == TranslationSource.llm) ...[
                  Divider(color: colorScheme.outlineVariant),
                  ListTile(
                    leading: Icon(Icons.settings_input_component, color: colorScheme.primary),
                    title: Text(S.of(context).llmSettings),
                    subtitle: Text(S.of(context).llmSettingsSubtitle),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (context) => const LLMSettingsScreen(),
                        ),
                      );
                    },
                  ),
                ],
                Divider(color: colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.audio_file, color: colorScheme.primary),
                  title: Text(S.of(context).audioFormatPreference),
                  subtitle: Text(S.of(context).audioFormatSubtitle),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const AudioFormatSettingsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: colorScheme.outlineVariant),
                ListTile(
                  leading: Icon(Icons.block, color: colorScheme.primary),
                  title: Text(S.of(context).blockingSettings),
                  subtitle: Text(S.of(context).blockingSettingsSubtitle),
                  trailing: const Icon(Icons.arrow_forward_ios),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (context) => const BlockedItemsScreen(),
                      ),
                    );
                  },
                ),
                Divider(color: colorScheme.outlineVariant),
                SwitchListTile(
                  secondary: Icon(Icons.sync, color: colorScheme.primary),
                  title: Text(S.of(context).progressSync),
                  subtitle: Text(
                    ref.watch(progressSyncProvider)
                        ? S.of(context).progressSyncEnabled
                        : S.of(context).progressSyncDisabled,
                    style: const TextStyle(fontSize: 12),
                  ),
                  value: ref.watch(progressSyncProvider),
                  onChanged: (value) {
                    ref.read(progressSyncProvider.notifier).toggle(value);
                    if (context.mounted) {
                      SnackBarUtil.showInfo(
                        context,
                        value
                            ? S.of(context).progressSyncEnabled
                            : S.of(context).progressSyncDisabled,
                      );
                    }
                  },
                ),
                if (platform == TargetPlatform.android ||
                    platform == TargetPlatform.windows ||
                    platform == TargetPlatform.macOS) ...[
                  Divider(color: colorScheme.outlineVariant),
                  SwitchListTile(
                    secondary: Icon(Icons.surround_sound, color: colorScheme.primary),
                    title: Text(S.of(context).audioPassthrough),
                    subtitle: Text(
                      (platform == TargetPlatform.windows ||
                              platform == TargetPlatform.macOS)
                          ? S.of(context).audioPassthroughDescWindows
                          : S.of(context).audioPassthroughDescAndroid,
                      style: const TextStyle(fontSize: 12),
                    ),
                    value: ref.watch(audioPassthroughProvider),
                    onChanged: (value) async {
                      if (value) {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(S.of(context).warning),
                            content:
                                Text(S.of(context).audioPassthroughWarning),
                            actions: [
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(false),
                                child: Text(S.of(context).cancel),
                              ),
                              TextButton(
                                onPressed: () =>
                                    Navigator.of(context).pop(true),
                                child: Text(S.of(context).confirm),
                              ),
                            ],
                          ),
                        );

                        if (confirmed != true) return;
                      }

                      ref.read(audioPassthroughProvider.notifier).toggle(value);
                      if (context.mounted) {
                        SnackBarUtil.showSuccess(
                          context,
                          value
                              ? ((platform ==
                                          TargetPlatform.windows ||
                                      platform ==
                                          TargetPlatform.macOS)
                                  ? S.of(context).exclusiveModeEnabled
                                  : S.of(context).audioPassthroughEnabled)
                              : S.of(context).audioPassthroughDisabled,
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 16),
          _buildEqualizerCard(context, ref, colorScheme),
          const SizedBox(height: 16),
          _buildCrossfadeCard(context, ref, colorScheme, textTheme),
        ],
      ),
    );
  }

  Widget _buildEqualizerCard(BuildContext context, WidgetRef ref, ColorScheme colorScheme) {
    final eqEnabled = ref.watch(equalizerEnabledProvider);
    final eqPreset = ref.watch(equalizerActivePresetProvider);
    final isSupported = ref.watch(equalizerDeviceSupportProvider);

    final presetName = EqualizerService.presets
        .where((p) => p.id == eqPreset)
        .firstOrNull
        ?.name ?? (eqPreset == 'custom' ? S.of(context).equalizerCustom : '');

    return Card(
      child: ListTile(
        leading: Icon(Icons.equalizer, color: colorScheme.primary),
        title: Text(S.of(context).equalizerTitle),
        subtitle: Text(
          eqEnabled && isSupported
              ? '${S.of(context).equalizerActive}: $presetName'
              : !isSupported
                  ? S.of(context).equalizerNotSupported
                  : S.of(context).equalizerDisabled,
          style: TextStyle(
            fontSize: 12,
            color: eqEnabled && isSupported
                ? colorScheme.primary.withValues(alpha: 0.8)
                : null,
          ),
        ),
        trailing: const Icon(Icons.arrow_forward_ios),
        onTap: () {
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => const EqualizerScreen(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCrossfadeCard(BuildContext context, WidgetRef ref, ColorScheme colorScheme, TextTheme textTheme) {
    final crossfadeMs = ref.watch(crossfadeDurationProvider);
    final crossfadeEnabled = crossfadeMs > 0;

    return Card(
      child: Column(
        children: [
          SwitchListTile(
            secondary: Icon(Icons.swap_horiz, color: colorScheme.primary),
            title: Text(S.of(context).crossfadeTitle),
            subtitle: Text(
              crossfadeEnabled
                  ? S.of(context).crossfadeEnabledWithDuration(crossfadeMs)
                  : S.of(context).gaplessPlaybackEnabled,
              style: TextStyle(
                color: crossfadeEnabled
                    ? colorScheme.primary.withValues(alpha: 0.8)
                    : null,
              ),
            ),
            value: crossfadeEnabled,
            onChanged: (value) {
              final newMs = value ? 3000 : 0;
              ref.read(crossfadeDurationProvider.notifier).updateDuration(newMs);
              ref.read(audioPlayerControllerProvider.notifier).setCrossfadeDuration(
                Duration(milliseconds: newMs),
              );
              if (context.mounted) {
                SnackBarUtil.showInfo(
                  context,
                  value
                      ? S.of(context).crossfadeEnabledWithDuration(newMs)
                      : S.of(context).gaplessPlaybackEnabled,
                );
              }
            },
          ),
          if (crossfadeEnabled) ...[
            Divider(height: 1, color: colorScheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        S.of(context).crossfadeDurationLabel,
                        style: textTheme.bodyMedium,
                      ),
                      const Spacer(),
                      Text(
                        crossfadeMs >= 1000
                            ? '${(crossfadeMs / 1000).toStringAsFixed(1)}s'
                            : '${crossfadeMs}ms',
                        style: textTheme.bodyMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: colorScheme.primary,
                            ),
                      ),
                    ],
                  ),
                  Slider(
                    value: crossfadeMs.toDouble(),
                    min: 500,
                    max: 10000,
                    divisions: 19,
                    label: crossfadeMs >= 1000
                        ? '${(crossfadeMs / 1000).toStringAsFixed(1)}s'
                        : '${crossfadeMs}ms',
                    onChanged: (value) {
                      final rounded = (value / 500).round() * 500;
                      ref.read(crossfadeDurationProvider.notifier).updateDuration(rounded);
                      ref.read(audioPlayerControllerProvider.notifier).setCrossfadeDuration(
                        Duration(milliseconds: rounded),
                      );
                    },
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Text(
                        S.of(context).crossfadeMinLabel,
                        style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                      const Spacer(),
                      Text(
                        S.of(context).crossfadeMaxLabel,
                        style: textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
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
                            S.of(context).crossfadeDescription,
                            style: textTheme.bodySmall?.copyWith(
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
}