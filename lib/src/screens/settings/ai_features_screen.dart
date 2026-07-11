import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:whisper_ggml_plus/whisper_ggml_plus.dart';

import '../../../l10n/app_localizations.dart';
import '../../providers/ai_download_provider.dart';
import '../../providers/ai_settings_provider.dart';
import '../../services/ai_download_notification_service.dart';
import '../../services/ai_model_service.dart';
import '../../utils/snackbar_util.dart';
import '../../widgets/custom_file_picker.dart';

/// Settings screen for AI Transcription features.
///
/// Shows:
/// - Model selection (Tiny / Base / Small / Medium / Large V3 / Large V3 Turbo)
/// - Spec table with size, speed, accuracy, min RAM
/// - Download / Delete model buttons for the selected model
class AIFeaturesScreen extends ConsumerStatefulWidget {
  const AIFeaturesScreen({super.key});

  @override
  ConsumerState<AIFeaturesScreen> createState() => _AIFeaturesScreenState();
}

class _AIFeaturesScreenState extends ConsumerState<AIFeaturesScreen> {
  bool _isChecking = true;
  bool _modelInstalled = false;
  int? _modelSize;
  String _currentModel = 'base';

  @override
  void initState() {
    super.initState();
    _currentModel = ref.read(aiSettingsProvider).selectedModel;
    _refreshStatus();
  }

  @override
  void dispose() {
    super.dispose();
  }

  Future<void> _refreshStatus() async {
    setState(() => _isChecking = true);
    final model = _whisperModelFromName(_currentModel);
    final installed =
        await AIModelService.instance.checkModelInstalled(model: model);
    final size = await AIModelService.instance.getModelSize(model: model);
    if (mounted) {
      setState(() {
        _modelInstalled = installed;
        _modelSize = size;
        _isChecking = false;
      });
    }
  }

  WhisperModel _whisperModelFromName(String name) {
    try {
      return WhisperModel.values.firstWhere((m) => m.name == name);
    } catch (_) {
      return WhisperModel.base;
    }
  }

  Future<void> _onModelChanged(String? newModel) async {
    if (newModel == null || newModel == _currentModel) return;

    setState(() {
      _currentModel = newModel;
      _isChecking = true;
    });

    await ref.read(aiSettingsProvider.notifier).setSelectedModel(newModel);

    await _refreshStatus();
  }

  String get _modelDisplayName =>
      getConfigByModelName(_currentModel)?.displayName ?? _currentModel;

  Future<void> _startDownload() async {
    final notifier = ref.read(aiDownloadProvider.notifier);
    final config = getConfigByModelName(_currentModel);
    final displayName = config?.displayName ?? _currentModel;

    notifier.reset();
    notifier.updateProgress(
      status: AiDownloadStatus.downloading,
      modelName: _currentModel,
      modelDisplayName: displayName,
      receivedBytes: 0,
      totalBytes: config?.approximateSizeBytes ?? 0,
    );

    _notifyProgress(displayName, 0.0, 0, config?.approximateSizeBytes ?? 0);

    try {
      final model = _whisperModelFromName(_currentModel);

      final path = await AIModelService.instance.downloadModel(
        model: model,
        onProgress: (received, total) {
          notifier.updateProgress(
            status: AiDownloadStatus.downloading,
            receivedBytes: received,
            totalBytes: total,
          );
          _notifyProgress(displayName, total > 0 ? received / total : 0.0,
              received, total);
        },
        isPaused: () => ref.read(aiDownloadProvider.notifier).isPauseRequested,
        onPaused: () {
          ref.read(aiDownloadProvider.notifier).markPaused();
          _notifyPaused(displayName);
        },
        isCancelled: () =>
            ref.read(aiDownloadProvider.notifier).isCancelRequested,
        onCancelled: () {
          ref.read(aiDownloadProvider.notifier).markCancelled();
          _notifyDismiss();
        },
      );

      if (ref.read(aiDownloadProvider).status != AiDownloadStatus.paused &&
          ref.read(aiDownloadProvider).status != AiDownloadStatus.idle) {
        await ref
            .read(aiSettingsProvider.notifier)
            .markModelDownloaded(path, ref.read(aiDownloadProvider).totalBytes);

        notifier.markCompleted();
        await _refreshStatus();

        _notifyCompleted(displayName);

        if (mounted) {
          SnackBarUtil.showSuccess(
            context,
            S.of(context).aiTranscribeComplete,
          );
        }
      }
    } catch (e) {
      if (ref.read(aiDownloadProvider).status == AiDownloadStatus.idle) return;
      notifier.markFailed(e.toString());
      _notifyFailed(displayName, e.toString());
      if (mounted) {
        SnackBarUtil.showError(
          context,
          S.of(context).aiTranscribeFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _resumeDownload() async {
    final state = ref.read(aiDownloadProvider);
    if (state.modelName == null) {
      await _startDownload();
      return;
    }

    final displayName = state.modelDisplayName ?? _modelDisplayName;
    final notifier = ref.read(aiDownloadProvider.notifier);
    notifier.updateProgress(
      status: AiDownloadStatus.downloading,
    );

    _notifyProgress(displayName, state.progress, state.receivedBytes,
        state.totalBytes);

    try {
      final model = _whisperModelFromName(state.modelName!);

      final path = await AIModelService.instance.downloadModel(
        model: model,
        onProgress: (received, total) {
          notifier.updateProgress(
            status: AiDownloadStatus.downloading,
            receivedBytes: received,
            totalBytes: total,
          );
          _notifyProgress(
              displayName, total > 0 ? received / total : 0.0, received, total);
        },
        isPaused: () => ref.read(aiDownloadProvider.notifier).isPauseRequested,
        onPaused: () {
          ref.read(aiDownloadProvider.notifier).markPaused();
          _notifyPaused(displayName);
        },
        isCancelled: () => ref.read(aiDownloadProvider.notifier).isCancelRequested,
        onCancelled: () {
          ref.read(aiDownloadProvider.notifier).markCancelled();
          _notifyDismiss();
        },
      );

      if (ref.read(aiDownloadProvider).status != AiDownloadStatus.paused &&
          ref.read(aiDownloadProvider).status != AiDownloadStatus.idle) {
        await ref
            .read(aiSettingsProvider.notifier)
            .markModelDownloaded(path, ref.read(aiDownloadProvider).totalBytes);

        notifier.markCompleted();
        await _refreshStatus();

        _notifyCompleted(displayName);

        if (mounted) {
          SnackBarUtil.showSuccess(
            context,
            S.of(context).aiTranscribeComplete,
          );
        }
      }
    } catch (e) {
      if (ref.read(aiDownloadProvider).status == AiDownloadStatus.idle) return;
      notifier.markFailed(e.toString());
      _notifyFailed(displayName, e.toString());
      if (mounted) {
        SnackBarUtil.showError(
          context,
          S.of(context).aiTranscribeFailed(e.toString()),
        );
      }
    }
  }

  Future<void> _deleteModel() async {
    final s = S.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.aiFeatures),
        content: Text(s.aiDeleteModelConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(s.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(s.delete),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final model = _whisperModelFromName(_currentModel);
      await AIModelService.instance.deleteModel(model: model);
      await ref.read(aiSettingsProvider.notifier).markModelDeleted();
      await _refreshStatus();
      if (mounted) {
        SnackBarUtil.showInfo(context, s.aiTranscribeComplete);
      }
    }
  }

  /// Cancel the current download — deletes partial file, resets state.
  /// Works both during active download and when paused/failed.
  Future<void> _cancelDownload() async {
    final notifier = ref.read(aiDownloadProvider.notifier);
    final dlState = ref.read(aiDownloadProvider);

    if (dlState.status == AiDownloadStatus.downloading) {
      notifier.requestCancel();
    } else {
      if (dlState.modelName != null) {
        final model = _whisperModelFromName(dlState.modelName!);
        await AIModelService.instance.cleanupPartialDownload(model: model);
      }
      notifier.markCancelled();
      _notifyDismiss();
      await _refreshStatus();
    }
  }

  Future<void> _openInBrowser() async {
    final model = _whisperModelFromName(_currentModel);
    final uri = model.modelUri;
    final config = getConfigByModelName(_currentModel);
    final displayName = config?.displayName ?? _currentModel;

    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        SnackBarUtil.showError(
          context,
          'Could not open browser',
        );
      } else if (mounted) {
        SnackBarUtil.showInfo(
          context,
          'Download $displayName via browser, then import the .bin file back.',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, e.toString());
      }
    }
  }

  Future<void> _importFromFile() async {
    final config = getConfigByModelName(_currentModel);
    final displayName = config?.displayName ?? _currentModel;

    try {
      final filePath = await CustomFilePicker.pickFile(
        context: context,
        title: 'Select Whisper model file (.bin)',
        allowedExtensions: ['.bin'],
      );

      if (filePath == null) return;

      final model = _whisperModelFromName(_currentModel);

      if (mounted) {
        SnackBarUtil.showInfo(context, 'Importing $displayName…');
      }

      final destPath = await AIModelService.instance.importModelFromFile(
        sourceFilePath: filePath,
        model: model,
      );

      final fileSize = File(filePath).lengthSync();
      await ref
          .read(aiSettingsProvider.notifier)
          .markModelDownloaded(destPath, fileSize);

      await _refreshStatus();

      if (mounted) {
        SnackBarUtil.showSuccess(
          context,
          '$displayName imported successfully!',
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, 'Import failed: $e');
      }
    }
  }

  void _notifyProgress(
      String displayName, double progress, int received, int total) {
    AiDownloadNotificationService.instance.showProgress(
      modelDisplayName: displayName,
      progress: progress,
      receivedBytes: received,
      totalBytes: total,
    );
  }

  void _notifyPaused(String displayName) {
    AiDownloadNotificationService.instance.showPaused(
      modelDisplayName: displayName,
    );
  }

  void _notifyCompleted(String displayName) {
    AiDownloadNotificationService.instance.showCompleted(
      modelDisplayName: displayName,
    );
  }

  void _notifyFailed(String displayName, String error) {
    AiDownloadNotificationService.instance.showFailed(
      modelDisplayName: displayName,
      error: error,
    );
  }

  void _notifyDismiss() {
    AiDownloadNotificationService.instance.dismiss();
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(1)} KB';
    }
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);
    final config = getConfigByModelName(_currentModel);
    final dlState = ref.watch(aiDownloadProvider);
    final isDownloading = dlState.status == AiDownloadStatus.downloading;
    final isPaused = dlState.status == AiDownloadStatus.paused;
    final isFailed = dlState.status == AiDownloadStatus.failed;

    return Scaffold(
      appBar: AppBar(
        title: Text(s.aiFeatures),
        centerTitle: false,
        actions: [
          if (isDownloading || isPaused || isFailed)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Tooltip(
                message: isPaused
                    ? 'Download paused'
                    : isFailed
                        ? 'Download failed'
                        : 'Downloading AI model…',
                child: SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isDownloading)
                        SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            value: dlState.progress,
                          ),
                        )
                      else if (isPaused)
                        Icon(Icons.pause_circle_outline,
                            size: 24, color: colorScheme.primary)
                      else
                        Icon(Icons.error_outline,
                            size: 24, color: colorScheme.error),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      CircleAvatar(
                        backgroundColor:
                            colorScheme.primary.withValues(alpha: 0.12),
                        child: Icon(Icons.auto_awesome,
                            color: colorScheme.primary, size: 22),
                      ),
                      const SizedBox(width: 12),
                      Text(
                        s.aiFeatures,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.aiFeaturesSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.model_training,
                          size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        'AI Model',
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    initialValue: _currentModel,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      filled: true,
                      fillColor: colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.3),
                    ),
                    items: _buildModelDropdownItems(),
                    onChanged: _onModelChanged,
                  ),

                  const SizedBox(height: 16),

                  _buildModelSpecTable(theme, colorScheme, config),

                  const SizedBox(height: 16),

                  if (config != null && config.approximateSizeBytes > 500 * 1024 * 1024)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer
                            .withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.warning_amber_rounded,
                              size: 20, color: colorScheme.error),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              'Model ini membutuhkan RAM minimal ${config.minRam} dan ~${config.sizeLabel} ruang penyimpanan. Transkripsi mungkin lambat di perangkat entry-level.',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
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
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.aiModelInstalled,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_isChecking)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: CircularProgressIndicator(),
                      ),
                    )
                  else ...[
                    _buildInfoRow(
                      context,
                      Icons.inventory_2_outlined,
                      s.aiFeatures,
                      _modelInstalled
                          ? s.aiModelInstalled
                          : s.aiModelNotInstalled,
                      _modelInstalled
                          ? Colors.green
                          : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),

                    _buildInfoRow(
                      context,
                      Icons.model_training,
                      'Model',
                      _getModelDisplayName(_currentModel),
                      colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 12),

                    if (_modelSize != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildInfoRow(
                          context,
                          Icons.storage_outlined,
                          s.aiStorageUsed,
                          _formatBytes(_modelSize!),
                          colorScheme.onSurfaceVariant,
                        ),
                      ),

                    const SizedBox(height: 8),

                    if (isDownloading || isPaused || isFailed) ...[
                      LinearProgressIndicator(
                        value: isDownloading ? dlState.progress : null,
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              dlState.progressLabel,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          if (dlState.modelDisplayName != null)
                            Text(
                              dlState.modelDisplayName!,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                        ],
                      ),
                      if (isFailed && dlState.errorMessage != null) ...[
                        const SizedBox(height: 4),
                        Text(
                          dlState.errorMessage!,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.error,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 16),
                    ],

                    if (isDownloading)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => ref
                                  .read(aiDownloadProvider.notifier)
                                  .requestPause(),
                              icon: const Icon(Icons.pause_rounded),
                              label: const Text('Pause'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _cancelDownload,
                              icon: const Icon(Icons.stop_rounded,
                                  color: Colors.red),
                              label: const Text('Stop',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      )
                    else if (isPaused || isFailed)
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _resumeDownload,
                              icon: Icon(isPaused
                                  ? Icons.play_arrow_rounded
                                  : Icons.refresh_rounded),
                              label: Text(isPaused ? 'Resume' : 'Retry'),
                            ),
                          ),
                          const SizedBox(height: 8),
                          SizedBox(
                            width: double.infinity,
                            child: TextButton.icon(
                              onPressed: _cancelDownload,
                              icon: const Icon(Icons.cancel_outlined,
                                  color: Colors.red),
                              label: const Text('Cancel',
                                  style: TextStyle(color: Colors.red)),
                            ),
                          ),
                        ],
                      )
                    else if (!_modelInstalled)
                      Column(
                        children: [
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: _startDownload,
                              icon: const Icon(Icons.download_rounded),
                              label: Text(s.aiDownloadModel),
                            ),
                          ),
                          const SizedBox(height: 10),
                          _buildAlternativeDownloadRow(theme, colorScheme, s),
                        ],
                      )
                    else
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _deleteModel,
                          icon: const Icon(Icons.delete_outline_rounded),
                          label: Text(s.aiDeleteModel),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: colorScheme.error,
                            side: BorderSide(color: colorScheme.error),
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ),

          const SizedBox(height: 24),

          _buildAllModelsComparison(theme, colorScheme),

          const SizedBox(height: 24),

          _buildThreadsCard(theme, colorScheme),

          const SizedBox(height: 16),

          Card(
            elevation: 0,
            color: colorScheme.surfaceContainerLow,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        s.aiFeatures,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    s.aiFeaturesSubtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<DropdownMenuItem<String>> _buildModelDropdownItems() {
    const models = [
      ('tiny', 'Tiny', '~75 MB'),
      ('base', 'Base (Recommended)', '~150 MB'),
      ('small', 'Small', '~500 MB'),
      ('medium', 'Medium', '~1.5 GB'),
      ('large', 'Large V3', '~3 GB'),
      ('largeV3Turbo', 'Large V3 Turbo', '~1.6 GB'),
    ];

    return models.map((entry) {
      final (value, label, subtitle) = entry;
      final isSelected = value == _currentModel;
      return DropdownMenuItem<String>(
        value: value,
        child: Row(
          children: [
            if (value == 'base')
              const Icon(Icons.star, size: 14, color: Colors.amber),
            if (value != 'base') const SizedBox(width: 14),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              subtitle,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }).toList();
  }

  String _getModelDisplayName(String name) {
    switch (name) {
      case 'tiny': return 'Tiny';
      case 'base': return 'Base (Recommended)';
      case 'small': return 'Small';
      case 'medium': return 'Medium';
      case 'large': return 'Large V3';
      case 'largeV3Turbo': return 'Large V3 Turbo';
      default: return name;
    }
  }

  Widget _buildModelSpecTable(
    ThemeData theme,
    ColorScheme colorScheme,
    AiModelConfig? config,
  ) {
    if (config == null) return const SizedBox.shrink();

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          _specRow(
            theme,
            Icons.storage,
            'Size',
            config.sizeLabel,
            colorScheme,
          ),
          const Divider(height: 24),
          _specRow(
            theme,
            Icons.speed,
            'Speed',
            config.speed,
            colorScheme,
          ),
          const Divider(height: 24),
          _specRow(
            theme,
            Icons.auto_awesome,
            'Accuracy',
            config.accuracy,
            colorScheme,
          ),
          const Divider(height: 24),
          _specRow(
            theme,
            Icons.memory,
            'Min RAM',
            config.minRam,
            colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _specRow(
    ThemeData theme,
    IconData icon,
    String label,
    String value,
    ColorScheme colorScheme,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.primary),
        const SizedBox(width: 10),
        Text(
          label,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        const Spacer(),
        Text(
          value,
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildThreadsCard(ThemeData theme, ColorScheme colorScheme) {
    final settings = ref.watch(aiSettingsProvider);
    final threads = settings.transcriptionThreads;
    final isHighThreads = threads >= 6;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.tune, size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Transcription Speed',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'CPU Threads',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isHighThreads
                        ? colorScheme.errorContainer.withValues(alpha: 0.7)
                        : colorScheme.primaryContainer.withValues(alpha: 0.7),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '$threads threads',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: isHighThreads
                          ? colorScheme.onErrorContainer
                          : colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),

            Slider(
              value: threads.toDouble(),
              min: 1,
              max: 8,
              divisions: 7,
              label: '$threads threads',
              onChanged: (value) {
                ref
                    .read(aiSettingsProvider.notifier)
                    .setTranscriptionThreads(value.round());
              },
            ),

            _buildThreadsInfo(theme, colorScheme, threads),

            const SizedBox(height: 12),
            _buildSpeedEstimate(theme, colorScheme, threads),

            const SizedBox(height: 4),

            const Divider(),
            const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Word-Level Timestamps',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        settings.splitOnWord
                            ? 'Each word gets its own timestamp — ~2x slower'
                            : 'Timestamps per sentence segment — faster',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.splitOnWord,
                  onChanged: (value) {
                    ref
                        .read(aiSettingsProvider.notifier)
                        .setSplitOnWord(value);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Info/warning text for thread count.
  Widget _buildThreadsInfo(ThemeData theme, ColorScheme colorScheme, int threads) {
    if (threads >= 6) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_rounded,
                size: 18, color: colorScheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'High thread count ($threads) will make transcription faster '
                'but the device may get warm and battery drain will increase. '
                'Recommended: 4 threads for daily use.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.info_outline, size: 18, color: colorScheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'More threads = faster transcription, higher battery usage.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Speed estimate table for different models with current thread count.
  Widget _buildSpeedEstimate(ThemeData theme, ColorScheme colorScheme, int threads) {
    final multiplier = threads / 4.0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Estimated transcription time (2:30 audio)',
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w500,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              _estRow(theme, 'Small (500MB)', 4.0, multiplier),
              const Divider(height: 16),
              _estRow(theme, 'Large V3 Turbo (1.6GB)', 12.0, multiplier),
            ],
          ),
        ),
      ],
    );
  }

  Widget _estRow(ThemeData theme, String label, double baseMinutes, double multiplier) {
    final estimatedMinutes = (baseMinutes / multiplier).ceil();
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.bodySmall,
          ),
        ),
        Text(
          '~$estimatedMinutes min',
          style: theme.textTheme.bodySmall?.copyWith(
            fontWeight: FontWeight.w600,
            color: estimatedMinutes <= 3
                ? Colors.green
                : estimatedMinutes <= 8
                    ? Colors.orange
                    : Colors.red,
          ),
        ),
      ],
    );
  }

  Widget _buildAllModelsComparison(
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.table_chart_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Model Comparison',
                  style: theme.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 8),
                  _tableHeader('Model', flex: 2),
                  _tableHeader('Size'),
                  _tableHeader('Speed', flex: 1),
                  _tableHeader('RAM'),
                ],
              ),
            ),

            ...aiModelConfigs.map((cfg) {
              final isSelected = cfg.model.name == _currentModel;
              return Container(
                padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                decoration: BoxDecoration(
                  color: isSelected
                      ? colorScheme.primary.withValues(alpha: 0.08)
                      : null,
                  border: Border(
                    bottom: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Row(
                        children: [
                          if (isSelected)
                            Icon(Icons.check_circle,
                                size: 14, color: colorScheme.primary),
                          if (isSelected) const SizedBox(width: 4),
                          Text(
                            cfg.displayName,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight:
                                  isSelected ? FontWeight.w600 : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: Text(
                        cfg.sizeLabel,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Expanded(
                      flex: 1,
                      child: Text(
                        cfg.speed,
                        style: const TextStyle(fontSize: 13),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        cfg.minRam,
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Widget _tableHeader(String label, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  /// A compact row with two alternative download methods:
  /// "Download via Browser" and "Import from File".
  Widget _buildAlternativeDownloadRow(
      ThemeData theme, ColorScheme colorScheme, S s) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _openInBrowser,
                icon: const Icon(Icons.open_in_browser, size: 18),
                label: const Text('Via Browser', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: SizedBox(
              height: 40,
              child: OutlinedButton.icon(
                onPressed: _importFromFile,
                icon: const Icon(Icons.file_open, size: 18),
                label: const Text('Import File', style: TextStyle(fontSize: 13)),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String label,
    String value,
    Color valueColor,
  ) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium,
              ),
              Flexible(
                child: Text(
                  value,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: valueColor,
                    fontWeight: FontWeight.w500,
                  ),
                  textAlign: TextAlign.end,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}