import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import 'package:kikoeru_flutter/l10n/localizations_ext.dart';
import '../../services/backup_service.dart';
import '../../services/log_service.dart';
import '../../widgets/custom_file_picker.dart';

final _log = LogService.instance;

/// Screen for creating and restoring app data backups.
class BackupRestoreScreen extends StatefulWidget {
  const BackupRestoreScreen({super.key});

  @override
  State<BackupRestoreScreen> createState() => _BackupRestoreScreenState();
}

class _BackupRestoreScreenState extends State<BackupRestoreScreen> {
  bool _isExporting = false;
  bool _isImporting = false;

  Future<void> _exportBackup() async {
    final s = sLoc(context);

    String? outputDir = await _pickDirectory(
      dialogTitle: s.backupSelectExportDir,
    );
    if (outputDir == null || !mounted) return;

    final timestamp = DateTime.now()
        .toIso8601String()
        .replaceAll(':', '-')
        .split('.')
        .first;
    final filename = 'kikoflu_backup_$timestamp.zip';

    setState(() => _isExporting = true);
    try {
      final destPath = p.join(outputDir, filename);
      await BackupService.exportBackup(destPath);

      if (!mounted) return;

      final file = File(destPath);
      final sizeStr = _formatFileSize(await file.length());

      _showSuccessDialog(
        title: s.backupExportSuccess,
        message: s.backupSavedTo(destPath, sizeStr),
      );
    } catch (e) {
      _log.error('[Backup] Export failed: $e');
      if (!mounted) return;
      _showErrorDialog(s.backupExportFailed('$e'));
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _importBackup() async {
    final s = sLoc(context);

    final filePath = await CustomFilePicker.pickFile(
      context: context,
      title: s.backupSelectImportFile,
      allowedExtensions: ['.zip'],
    );
    if (filePath == null || !mounted) return;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupRestoreConfirmTitle),
        content: Text(s.backupRestoreConfirmMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text(s.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: Text(s.confirm),
          ),
        ],
      ),
    );
    if (confirm != true || !mounted) return;

    setState(() => _isImporting = true);
    try {
      final warnings = await BackupService.importBackup(filePath);

      if (!mounted) return;

      final buffer = StringBuffer(s.backupRestoreSuccess);
      if (warnings.isNotEmpty) {
        buffer.write('\n\n');
        buffer.writeln(s.backupRestoreWarnings);
        for (final w in warnings) {
          buffer.writeln('• $w');
        }
      }

      _showSuccessDialog(
        title: s.backupRestoreSuccessTitle,
        message: buffer.toString(),
        dismissLabel: s.backupRestartApp,
      );
    } catch (e) {
      _log.error('[Backup] Import failed: $e');
      if (!mounted) return;
      _showErrorDialog(s.backupRestoreFailed('$e'));
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  Future<String?> _pickDirectory({required String dialogTitle}) async {
    return CustomFilePicker.pickDirectory(
      context: context,
      title: dialogTitle,
    );
  }

  void _showSuccessDialog({
    required String title,
    required String message,
    String? dismissLabel,
  }) {
    final s = sLoc(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.check_circle, color: Colors.green, size: 48),
        title: Text(title),
        content: SingleChildScrollView(
          child: Text(message),
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              if (dismissLabel != null) {
                _showRestartPrompt();
              }
            },
            child: Text(dismissLabel ?? s.ok),
          ),
        ],
      ),
    );
  }

  void _showErrorDialog(String message) {
    final s = sLoc(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        icon: const Icon(Icons.error, color: Colors.red, size: 48),
        title: Text(s.backupError),
        content: Text(message),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.ok),
          ),
        ],
      ),
    );
  }

  void _showRestartPrompt() {
    final s = sLoc(context);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.backupRestartRequired),
        content: Text(s.backupRestartRequiredDesc),
        actions: [
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(s.ok),
          ),
        ],
      ),
    );
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = sLoc(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(s.backupTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.info_outline, color: colorScheme.primary),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      s.backupInfoDescription,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 24),

          _SectionHeader(
            icon: Icons.file_download_outlined,
            title: s.backupExportTitle,
            subtitle: s.backupExportSubtitle,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.secondaryContainer,
                child: Icon(
                  Icons.backup_rounded,
                  color: colorScheme.onSecondaryContainer,
                ),
              ),
              title: Text(s.backupCreateBackup),
              subtitle: Text(s.backupCreateBackupDesc),
              trailing: _isExporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isExporting || _isImporting ? null : _exportBackup,
            ),
          ),
          const SizedBox(height: 24),

          _SectionHeader(
            icon: Icons.file_upload_outlined,
            title: s.backupRestoreTitle,
            subtitle: s.backupRestoreSubtitle,
          ),
          const SizedBox(height: 8),
          Card(
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.tertiaryContainer,
                child: Icon(
                  Icons.restore_rounded,
                  color: colorScheme.onTertiaryContainer,
                ),
              ),
              title: Text(s.backupRestoreFromBackup),
              subtitle: Text(s.backupRestoreFromBackupDesc),
              trailing: _isImporting
                  ? const SizedBox(
                      width: 24,
                      height: 24,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.chevron_right),
              onTap: _isExporting || _isImporting ? null : _importBackup,
            ),
          ),
          const SizedBox(height: 24),

          _SectionHeader(
            icon: Icons.storage_outlined,
            title: s.backupDataIncluded,
            subtitle: '',
          ),
          const SizedBox(height: 8),
          Card(
            child: Column(
              children: [
                _DataRow(
                  icon: Icons.storage_rounded,
                  text: s.backupDatabases,
                  detail: 'accounts.db, history.db, subtitle_library.db',
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _DataRow(
                  icon: Icons.inventory_2_outlined,
                  text: s.backupHiveBoxes,
                  detail: 'settings.hive, users.hive',
                ),
                const Divider(height: 1, indent: 16, endIndent: 16),
                _DataRow(
                  icon: Icons.tune_rounded,
                  text: s.backupPreferences,
                  detail: s.backupAllSettings,
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 20, color: theme.colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.primary,
            ),
          ),
          if (subtitle.isNotEmpty) ...[
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                subtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  final IconData icon;
  final String text;
  final String detail;

  const _DataRow({
    required this.icon,
    required this.text,
    required this.detail,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      dense: true,
      leading: Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
      title: Text(text, style: theme.textTheme.bodyMedium),
      subtitle: Text(
        detail,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}