import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers/settings_provider.dart';
import '../../services/translation_service.dart';
import '../../utils/l10n_extensions.dart';
import '../../utils/snackbar_util.dart';

/// Translation settings screen — MD3 consolidated section.
///
/// Features: Translation Source selection (Google/Youdao/Microsoft/LLM),
/// LLM Configuration (API URL, Key, Model, Prompt, Concurrency) — shown
/// inline when LLM source is selected.
class TranslationScreen extends ConsumerStatefulWidget {
  const TranslationScreen({super.key});

  @override
  ConsumerState<TranslationScreen> createState() => _TranslationScreenState();
}

class _TranslationScreenState extends ConsumerState<TranslationScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _apiUrlController;
  late TextEditingController _apiKeyController;
  late TextEditingController _modelController;
  late TextEditingController _promptController;
  late double _concurrency;

  @override
  void initState() {
    super.initState();
    final settings = ref.read(llmSettingsProvider);
    _apiUrlController = TextEditingController(text: settings.apiUrl);
    _apiKeyController = TextEditingController(text: settings.apiKey);
    _modelController = TextEditingController(text: settings.model);
    _promptController = TextEditingController(text: settings.prompt);
    _concurrency = settings.concurrency.toDouble();

    Future.microtask(() {
      if (mounted && _promptController.text.isEmpty) {
        final locale = Localizations.localeOf(context);
        _promptController.text =
            TranslationService.getDefaultLLMPrompt(locale);
      }
    });
  }

  @override
  void dispose() {
    _apiUrlController.dispose();
    _apiKeyController.dispose();
    _modelController.dispose();
    _promptController.dispose();
    super.dispose();
  }

  Future<void> _saveLLMSettings() async {
    if (!_formKey.currentState!.validate()) return;

    final settings = LLMSettings(
      apiUrl: _apiUrlController.text.trim(),
      apiKey: _apiKeyController.text.trim(),
      model: _modelController.text.trim(),
      prompt: _promptController.text.trim(),
      concurrency: _concurrency.toInt(),
    );

    await ref.read(llmSettingsProvider.notifier).updateSettings(settings);

    if (mounted) {
      SnackBarUtil.showSuccess(context, S.of(context).settingsSaved);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentSource = ref.watch(translationSourceProvider);
    final s = S.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsTranslation),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    _buildSourceCard(context, ref, currentSource, s),
                    const SizedBox(height: 16),

                    _buildAutoTranslateCard(context, s),
                    const SizedBox(height: 16),

                    if (currentSource == TranslationSource.llm) ...[
                      _buildLLMForm(context, s),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _saveLLMSettings();
                          },
                          icon: const Icon(Icons.save_rounded),
                          label: Text(s.saveSettings),
                        ),
                      ),
                    ],

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

  Widget _buildAutoTranslateCard(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final autoTranslate = ref.watch(autoTranslateLyricsProvider);

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
          child: Icon(Icons.lyrics_rounded,
              color: colorScheme.primary, size: 22),
        ),
        title: Text(
          s.autoTranslateLyrics,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        subtitle: Text(
          autoTranslate
              ? s.autoTranslateLyricsEnabled
              : s.autoTranslateLyricsDisabled,
          style: TextStyle(
            fontSize: 12,
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        value: autoTranslate,
        onChanged: (value) {
          HapticFeedback.lightImpact();
          ref.read(autoTranslateLyricsProvider.notifier).toggle(value);
          if (context.mounted) {
            SnackBarUtil.showInfo(
              context,
              value
                  ? s.autoTranslateLyricsEnabled
                  : s.autoTranslateLyricsDisabled,
            );
          }
        },
      ),
    );
  }

  Widget _buildSourceCard(
    BuildContext context,
    WidgetRef ref,
    TranslationSource currentSource,
    S s,
  ) {
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.translate_rounded,
                      color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  s.translationSourceSettings,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          RadioGroup<TranslationSource>(
            groupValue: currentSource,
            onChanged: (TranslationSource? value) {
              if (value != null) {
                HapticFeedback.lightImpact();
                _trySelectSource(ref, value, s);
              }
            },
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: _buildSourceOptions(
                context: context,
                ref: ref,
                currentSource: currentSource,
                s: s,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Try to select the given translation source.
  /// Shows LLM configuration dialog if LLM is selected but not configured.
  void _trySelectSource(WidgetRef ref, TranslationSource source, S s) {
    if (source == TranslationSource.llm) {
      final llmSettings = ref.read(llmSettingsProvider);
      if (llmSettings.apiKey.isEmpty) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(s.needsConfiguration),
            content: Text(s.llmConfigRequiredMessage),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(s.cancel),
              ),
              TextButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  ref
                      .read(translationSourceProvider.notifier)
                      .updateSource(TranslationSource.llm);
                },
                child: Text(s.goToConfigure),
              ),
            ],
          ),
        );
        return;
      }
    }
    ref.read(translationSourceProvider.notifier).updateSource(source);
  }

  /// Build all source option tiles with proper dividers (no trailing divider on last).
  List<Widget> _buildSourceOptions({
    required BuildContext context,
    required WidgetRef ref,
    required TranslationSource currentSource,
    required S s,
  }) {
    const sources = TranslationSource.values;
    return List.generate(sources.length, (index) {
      final source = sources[index];
      final isLast = index == sources.length - 1;
      final isSelected = currentSource == source;
      return _buildSourceOption(
        context: context,
        ref: ref,
        source: source,
        currentSource: currentSource,
        isSelected: isSelected,
        isLast: isLast,
        s: s,
      );
    });
  }

  Widget _buildSourceOption({
    required BuildContext context,
    required WidgetRef ref,
    required TranslationSource source,
    required TranslationSource currentSource,
    required bool isSelected,
    required bool isLast,
    required S s,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final String description;
    switch (source) {
      case TranslationSource.google:
        description = s.translationDescGoogle;
        break;
      case TranslationSource.llm:
        description = s.translationDescLlm;
        break;
    }

    final IconData icon;
    switch (source) {
      case TranslationSource.google:
        icon = Icons.translate_rounded;
        break;
      case TranslationSource.llm:
        icon = Icons.psychology_rounded;
        break;
    }

    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: isSelected
                ? colorScheme.primary.withValues(alpha: 0.12)
                : colorScheme.surfaceContainerHighest,
            radius: 20,
            child: Icon(
              icon,
              color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
              size: 20,
            ),
          ),
          title: Text(
            source.localizedName(context),
            style: TextStyle(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          subtitle: description.isNotEmpty
              ? Text(
                  description,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                )
              : null,
          trailing: Radio<TranslationSource>(
            value: source,
          ),
          onTap: () {
            HapticFeedback.lightImpact();
            _trySelectSource(ref, source, s);
          },
        ),
        if (!isLast)
          Divider(
            height: 1,
            indent: 72,
            color: colorScheme.outlineVariant,
          ),
      ],
    );
  }

  Widget _buildLLMForm(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Form(
      key: _formKey,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 16, bottom: 8),
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Icon(Icons.psychology_rounded,
                      color: colorScheme.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Text(
                  s.llmTranslationSettings,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),

          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            clipBehavior: Clip.antiAlias,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _apiUrlController,
                    decoration: InputDecoration(
                      labelText: s.apiEndpointUrl,
                      hintText: 'https://api.openai.com/v1/chat/completions',
                      helperText: s.openaiCompatibleEndpoint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return s.pleaseEnterApiUrl;
                      }
                      if (!value.startsWith('http')) {
                        return s.pleaseEnterValidUrl;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _apiKeyController,
                    decoration: const InputDecoration(
                      labelText: 'API Key',
                      hintText: 'sk-...',
                      border: OutlineInputBorder(),
                    ),
                    obscureText: true,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return s.pleaseEnterApiKey;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _modelController,
                    decoration: InputDecoration(
                      labelText: s.modelName,
                      hintText: 'gpt-3.5-turbo',
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return s.pleaseEnterModelName;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(s.concurrencyCount,
                          style: theme.textTheme.bodyMedium),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${_concurrency.toInt()}',
                          style: theme.textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: colorScheme.onPrimaryContainer,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.concurrencyDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Slider(
                    value: _concurrency,
                    min: 1,
                    max: 10,
                    divisions: 9,
                    label: '${_concurrency.toInt()}',
                    onChanged: (value) {
                      setState(() {
                        _concurrency = value;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
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
                    s.promptSection,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    s.promptDescription,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _promptController,
                    maxLines: 5,
                    decoration: InputDecoration(
                      border: const OutlineInputBorder(),
                      hintText: s.enterSystemPrompt,
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return s.pleaseEnterPrompt;
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 8),
                  TextButton.icon(
                    onPressed: () {
                      final locale = Localizations.localeOf(context);
                      _promptController.text =
                          TranslationService.getDefaultLLMPrompt(locale);
                    },
                    icon: const Icon(Icons.restore_rounded, size: 18),
                    label: Text(s.restoreDefaultPrompt),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}