import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../providers/batch_transcription_provider.dart';
import '../../l10n/app_localizations.dart';

/// A bottom sheet that shows detailed batch transcription progress.
///
/// Displays:
/// - Overall progress bar with percentage
/// - Current file being transcribed with animated indicator
/// - Full file list with per-file status icons
/// - Cancel / Dismiss button depending on state
///
/// Opens via [showBatchTranscriptionSheet].
class BatchTranscriptionSheet extends ConsumerStatefulWidget {
  const BatchTranscriptionSheet({super.key});

  /// Show the sheet from a parent [BuildContext].
  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const BatchTranscriptionSheet(),
    );
  }

  @override
  ConsumerState<BatchTranscriptionSheet> createState() =>
      _BatchTranscriptionSheetState();
}

class _BatchTranscriptionSheetState
    extends ConsumerState<BatchTranscriptionSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.6, end: 1.0).animate(
      CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(batchTranscriptionProvider);
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom,
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.only(top: 8, bottom: 4),
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: cs.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome, color: cs.primary, size: 22),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _headerTitle(state),
                        style: tt.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (state.status == BatchJobStatus.running)
                      _buildPulseDot(cs),
                  ],
                ),
              ),
              const Divider(height: 1),

              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  children: [
                    _buildOverallProgress(state, cs, tt),

                    const SizedBox(height: 16),

                    if (state.status == BatchJobStatus.running &&
                        state.currentIndex >= 0 &&
                        state.currentIndex < state.files.length) ...[
                      _buildCurrentFile(state, cs, tt),
                      const SizedBox(height: 16),
                    ],

                    if (state.status == BatchJobStatus.completed ||
                        state.status == BatchJobStatus.cancelled) ...[
                      _buildSummary(state, cs, tt),
                      const SizedBox(height: 16),
                    ],

                    Row(
                      children: [
                        Icon(Icons.list, size: 16, color: cs.onSurfaceVariant),
                        const SizedBox(width: 6),
                        Text(
                          S.of(context).nFiles(state.totalFiles),
                          style: tt.labelMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        if (state.doneCount > 0)
                          Text(
                            '${state.doneCount} done',
                            style: tt.labelSmall?.copyWith(
                              color: Colors.green[600],
                            ),
                          ),
                        if (state.doneCount > 0 && state.failedCount > 0)
                          Text(
                            ' · ',
                            style: tt.labelSmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        if (state.failedCount > 0)
                          Text(
                            '${state.failedCount} failed',
                            style: tt.labelSmall?.copyWith(
                              color: Colors.red[600],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    if (state.files.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24),
                        child: Center(
                          child: Text(
                            'No files',
                            style: tt.bodyMedium?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      )
                    else
                      ...List.generate(state.files.length, (i) {
                        final file = state.files[i];
                        return _buildFileItem(file, i, state, cs, tt);
                      }),

                    const SizedBox(height: 12),

                    _buildBottomAction(state, cs, tt),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _headerTitle(BatchTranscriptionState state) {
    switch (state.status) {
      case BatchJobStatus.running:
        return 'AI Transcription';
      case BatchJobStatus.completed:
        return state.failedCount > 0
            ? 'Completed (${state.failedCount} failed)'
            : 'Completed ✓';
      case BatchJobStatus.cancelled:
        return 'Cancelled';
      case BatchJobStatus.idle:
        return 'Batch Transcription';
    }
  }

  Widget _buildPulseDot(ColorScheme cs) {
    return FadeTransition(
      opacity: _pulseAnim,
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(
          color: cs.primary,
          shape: BoxShape.circle,
        ),
      ),
    );
  }

  Widget _buildOverallProgress(
      BatchTranscriptionState state, ColorScheme cs, TextTheme tt) {
    final progress = state.totalFiles > 0
        ? (state.doneCount + state.failedCount) / state.totalFiles
        : 0.0;
    final percent = (progress * 100).round();

    return Card(
      elevation: 0,
      color: cs.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Files', style: tt.labelMedium),
                const Spacer(),
                Text(
                  '${state.doneCount + state.failedCount}/${state.totalFiles}',
                  style: tt.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                const SizedBox(width: 4),
                Text(
                  '($percent%)',
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: cs.surfaceContainerLow,
                valueColor: AlwaysStoppedAnimation(
                  state.failedCount > 0
                      ? Colors.orange
                      : cs.primary,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _statChip(
                    Icons.check_circle, Colors.green[600]!, state.doneCount, cs),
                const SizedBox(width: 8),
                _statChip(
                    Icons.hourglass_empty, cs.onSurfaceVariant, state.queuedCount, cs),
                if (state.failedCount > 0) ...[
                  const SizedBox(width: 8),
                  _statChip(
                      Icons.error, Colors.red[600]!, state.failedCount, cs),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, Color color, int count, ColorScheme cs) {
    if (count == 0) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentFile(
      BatchTranscriptionState state, ColorScheme cs, TextTheme tt) {
    final current = state.files[state.currentIndex];
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: cs.primaryContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: cs.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: cs.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Transcribing…',
                  style: tt.labelSmall?.copyWith(
                    color: cs.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  current.displayName,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummary(
      BatchTranscriptionState state, ColorScheme cs, TextTheme tt) {
    final isCancelled = state.status == BatchJobStatus.cancelled;
    final bgColor = isCancelled
        ? Colors.orange.withValues(alpha: 0.1)
        : state.failedCount > 0
            ? Colors.orange.withValues(alpha: 0.1)
            : Colors.green.withValues(alpha: 0.1);
    final icon = isCancelled
        ? Icons.cancel
        : state.failedCount > 0
            ? Icons.warning_amber
            : Icons.check_circle;
    final iconColor = isCancelled
        ? Colors.orange
        : state.failedCount > 0
            ? Colors.orange
            : Colors.green[600]!;
    final title = isCancelled
        ? 'Batch Cancelled'
        : state.failedCount > 0
            ? 'Completed with errors'
            : 'All files transcribed successfully';

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: iconColor, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    style: tt.titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 2),
                Text(
                  '${state.doneCount} succeeded · ${state.failedCount} failed',
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFileItem(BatchFile file, int index,
      BatchTranscriptionState state, ColorScheme cs, TextTheme tt) {
    final isCurrent = index == state.currentIndex &&
        state.status == BatchJobStatus.running &&
        file.status == BatchFileStatus.transcribing;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        decoration: BoxDecoration(
          color: isCurrent
              ? cs.primaryContainer.withValues(alpha: 0.25)
              : file.status == BatchFileStatus.done
                  ? Colors.green.withValues(alpha: 0.06)
                  : file.status == BatchFileStatus.failed
                      ? Colors.red.withValues(alpha: 0.06)
                      : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: isCurrent
              ? Border.all(
                  color: cs.primary.withValues(alpha: 0.3), width: 1)
              : null,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        child: Row(
          children: [
            _fileStatusIcon(file.status, cs, isCurrent),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                file.displayName,
                style: tt.bodySmall?.copyWith(
                  fontWeight:
                      isCurrent ? FontWeight.w600 : FontWeight.w400,
                  color: file.status == BatchFileStatus.failed
                      ? Colors.red[700]
                      : null,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (file.errorMessage != null)
              IconButton(
                onPressed: () => _showError(context, file.errorMessage!),
                icon: Icon(Icons.info_outline, size: 16, color: Colors.red[400]),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                tooltip: file.errorMessage,
              ),
          ],
        ),
      ),
    );
  }

  Widget _fileStatusIcon(
      BatchFileStatus status, ColorScheme cs, bool isCurrent) {
    switch (status) {
      case BatchFileStatus.queued:
        return Icon(Icons.hourglass_empty,
            size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.5));
      case BatchFileStatus.transcribing:
        if (isCurrent) {
          return SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: cs.primary,
            ),
          );
        }
        return Icon(Icons.music_note, size: 18, color: cs.primary);
      case BatchFileStatus.done:
        return Icon(Icons.check_circle, size: 18, color: Colors.green[600]);
      case BatchFileStatus.failed:
        return Icon(Icons.error, size: 18, color: Colors.red[600]);
    }
  }

  Widget _buildBottomAction(
      BatchTranscriptionState state, ColorScheme cs, TextTheme tt) {
    switch (state.status) {
      case BatchJobStatus.running:
        return SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () {
              ref.read(batchTranscriptionProvider.notifier).cancel();
            },
            icon: const Icon(Icons.stop, size: 18),
            label: Text(S.of(context).cancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red[600],
              side: BorderSide(color: Colors.red[300]!),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        );
      case BatchJobStatus.completed:
      case BatchJobStatus.cancelled:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () {
              ref.read(batchTranscriptionProvider.notifier).clear();
              Navigator.of(context).pop();
            },
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
            child: Text(S.of(context).close),
          ),
        );
      case BatchJobStatus.idle:
        return const SizedBox.shrink();
    }
  }

  void _showError(BuildContext context, String error) {
    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Transcription Error'),
        content: SingleChildScrollView(
          child: Text(error, style: const TextStyle(fontSize: 13)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(ctx).close),
          ),
        ],
      ),
    );
  }
}