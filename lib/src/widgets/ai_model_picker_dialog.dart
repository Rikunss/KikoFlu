import 'package:flutter/material.dart';
import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../l10n/app_localizations.dart';
import '../services/ai_model_service.dart';

/// Configuration returned by [showAIModelPickerDialog].
class AITranscriptionConfig {
  final WhisperModel model;
  final int threads;
  final bool splitOnWord;

  const AITranscriptionConfig({
    required this.model,
    required this.threads,
    required this.splitOnWord,
  });
}

/// Shows a modal dialog that lets the user pick an AI model, thread count,
/// and word-level toggle before starting transcription.
///
/// Returns an [AITranscriptionConfig] if the user taps "Transcribe",
/// or `null` if cancelled.
///
/// [installedModels] — list of models that are available on disk.
/// [initialModel] — pre-selected model (usually from settings).
/// [fileCount] — optional text like "8 files" shown below the title.
Future<AITranscriptionConfig?> showAIModelPickerDialog(
  BuildContext context, {
  required List<AiModelConfig> installedModels,
  required WhisperModel initialModel,
  required int initialThreads,
  required bool initialSplitOnWord,
  String? fileCount,
}) {
  assert(installedModels.isNotEmpty, 'Must have at least one installed model');

  return showDialog<AITranscriptionConfig>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) => _AIModelPickerDialog(
      installedModels: installedModels,
      initialModel: initialModel,
      initialThreads: initialThreads,
      initialSplitOnWord: initialSplitOnWord,
      fileCount: fileCount,
    ),
  );
}

class _AIModelPickerDialog extends StatefulWidget {
  final List<AiModelConfig> installedModels;
  final WhisperModel initialModel;
  final int initialThreads;
  final bool initialSplitOnWord;
  final String? fileCount;

  const _AIModelPickerDialog({
    required this.installedModels,
    required this.initialModel,
    required this.initialThreads,
    required this.initialSplitOnWord,
    this.fileCount,
  });

  @override
  State<_AIModelPickerDialog> createState() => _AIModelPickerDialogState();
}

class _AIModelPickerDialogState extends State<_AIModelPickerDialog> {
  late WhisperModel _selectedModel;
  late int _threads;
  late bool _splitOnWord;

  @override
  void initState() {
    super.initState();
    _selectedModel = widget.initialModel;
    _threads = widget.initialThreads;
    _splitOnWord = widget.initialSplitOnWord;
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.auto_awesome, color: cs.primary, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'AI Transcription',
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // File count subtitle (for batch)
            if (widget.fileCount != null) ...[
              Text(
                widget.fileCount!,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 12),
            ],

            // ── Model List ──
            Text(
              'Model',
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),
            ...widget.installedModels.map((config) {
              final isSelected = _selectedModel == config.model;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => setState(() => _selectedModel = config.model),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? cs.primaryContainer.withValues(alpha: 0.5)
                          : cs.surfaceContainerHighest.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? cs.primary : Colors.transparent,
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isSelected
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 20,
                          color: isSelected ? cs.primary : cs.onSurfaceVariant,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                config.displayName,
                                style: tt.bodyMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${config.sizeLabel}  |  ${config.speed}  ${config.accuracy}',
                                style: tt.bodySmall?.copyWith(
                                  color: cs.onSurfaceVariant,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),

            const Divider(height: 24),

            // ── Advanced Settings ──
            Text(
              'Pengaturan',
              style: tt.labelLarge?.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 8),

            // Threads dropdown
            Row(
              children: [
                Icon(Icons.memory, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Text('Threads', style: tt.bodyMedium),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _threads,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      isDense: true,
                    ),
                    items: [1, 2, 4, 6, 8]
                        .map((t) => DropdownMenuItem(
                              value: t,
                              child: Text('$t Thread${t > 1 ? 's' : ''}'),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _threads = v);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Word-Level toggle
            Row(
              children: [
                Icon(Icons.timer, size: 18, color: cs.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Word-Level', style: tt.bodyMedium),
                      Text(
                        _splitOnWord
                            ? 'Per-word timestamps — ~2x slower'
                            : 'Per-sentence timestamps — faster',
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _splitOnWord,
                  onChanged: (v) => setState(() => _splitOnWord = v),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: Text(s.cancel),
        ),
        FilledButton.icon(
          onPressed: () {
            final config = AITranscriptionConfig(
              model: _selectedModel,
              threads: _threads,
              splitOnWord: _splitOnWord,
            );
            Navigator.of(context).pop(config);
          },
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('Transcribe'),
        ),
      ],
    );
  }
}
