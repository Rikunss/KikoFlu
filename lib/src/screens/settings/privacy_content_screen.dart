import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../blocked_items_screen.dart';
import '../../providers/settings_provider.dart';
import '../../utils/snackbar_util.dart';

/// Privacy & Content settings screen — MD3 consolidated section.
///
/// Features: Privacy Mode (master switch, blur cover, title mask),
/// Blocked Items navigation.
class PrivacyContentScreen extends ConsumerStatefulWidget {
  const PrivacyContentScreen({super.key});

  @override
  ConsumerState<PrivacyContentScreen> createState() =>
      _PrivacyContentScreenState();
}

class _PrivacyContentScreenState extends ConsumerState<PrivacyContentScreen> {
  final TextEditingController _titleController = TextEditingController();

  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      if (mounted) {
        final settings = ref.read(privacyModeSettingsProvider);
        _titleController.text = settings.customTitle;
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  void _showEditTitleDialog() {
    final settings = ref.read(privacyModeSettingsProvider);
    _titleController.text = settings.customTitle;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(context).setReplaceTitle),
        content: TextField(
          controller: _titleController,
          decoration: InputDecoration(
            labelText: S.of(context).replaceTitle,
            hintText: S.of(context).enterDisplayTitle,
            border: const OutlineInputBorder(),
          ),
          maxLength: 50,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () {
              final title = _titleController.text.trim();
              if (title.isNotEmpty) {
                ref
                    .read(privacyModeSettingsProvider.notifier)
                    .setCustomTitle(title);
                Navigator.pop(ctx);
                SnackBarUtil.showSuccess(
                    context, S.of(context).replaceTitleSaved);
              }
            },
            child: Text(S.of(context).save),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(privacyModeSettingsProvider);
    final s = S.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsPrivacyContent),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    // ── Privacy Mode Master Switch ──
                    _buildMasterSwitch(context, settings, s),
                    const SizedBox(height: 16),

                    // ── Privacy Details ──
                    _buildPrivacyDetails(context, settings, s),
                    const SizedBox(height: 16),

                    // ── Blocked Items ──
                    _buildBlockedItemsCard(context, s),
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

  // ──────────────────────────────────────────────
  // Privacy Mode — Info + Master Switch
  // ──────────────────────────────────────────────

  Widget _buildMasterSwitch(
      BuildContext context, PrivacyModeSettings settings, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
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
            Row(
              children: [
                Icon(
                  settings.enabled ? Icons.shield_rounded : Icons.shield_outlined,
                  color: settings.enabled ? colorScheme.primary : colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.enablePrivacyMode,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        settings.enabled
                            ? s.privacyModeEnabledSubtitle
                            : s.privacyModeDisabledSubtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.enabled,
                  onChanged: (value) {
                    HapticFeedback.lightImpact();
                    ref
                        .read(privacyModeSettingsProvider.notifier)
                        .setEnabled(value);
                  },
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Info description
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline,
                      size: 16, color: colorScheme.primary),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      s.privacyModeDescription,
                      style: theme.textTheme.bodySmall?.copyWith(
                        height: 1.4,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Privacy Details — Blur + Title Mask
  // ──────────────────────────────────────────────

  Widget _buildPrivacyDetails(
      BuildContext context, PrivacyModeSettings settings, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final enabled = settings.enabled;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.notifications_outlined,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.blurNotificationCover),
            subtitle: Text(
              s.blurNotificationCoverSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.blurCover,
            onChanged: enabled
                ? (value) {
                    HapticFeedback.lightImpact();
                    ref
                        .read(privacyModeSettingsProvider.notifier)
                        .setBlurCover(value);
                  }
                : null,
          ),
          Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.blur_on_rounded,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.blurInAppCover),
            subtitle: Text(
              s.blurInAppCoverSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.blurCoverInApp,
            onChanged: enabled
                ? (value) {
                    HapticFeedback.lightImpact();
                    ref
                        .read(privacyModeSettingsProvider.notifier)
                        .setBlurCoverInApp(value);
                  }
                : null,
          ),
          Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.text_fields_rounded,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.replaceTitle),
            subtitle: Text(
              s.replaceTitleSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: settings.maskTitle,
            onChanged: enabled
                ? (value) {
                    HapticFeedback.lightImpact();
                    ref
                        .read(privacyModeSettingsProvider.notifier)
                        .setMaskTitle(value);
                  }
                : null,
          ),
          Divider(height: 1, indent: 72, color: colorScheme.outlineVariant),
          ListTile(
            enabled: enabled && settings.maskTitle,
            leading: CircleAvatar(
              backgroundColor: (enabled && settings.maskTitle)
                  ? colorScheme.primary.withValues(alpha: 0.12)
                  : colorScheme.onSurface.withValues(alpha: 0.08),
              child: Icon(Icons.edit_rounded,
                  color: (enabled && settings.maskTitle)
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                  size: 22),
            ),
            title: Text(s.replaceTitleContent),
            subtitle: Text(
              settings.customTitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: enabled && settings.maskTitle
                ? _showEditTitleDialog
                : null,
          ),
        ],
      ),
    );
  }

  // ──────────────────────────────────────────────
  // Blocked Items Card
  // ──────────────────────────────────────────────

  Widget _buildBlockedItemsCard(BuildContext context, S s) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Card(
      elevation: 0,
      color: colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: colorScheme.error.withValues(alpha: 0.12),
          child: Icon(Icons.block_rounded, color: colorScheme.error, size: 22),
        ),
        title: Text(s.blockingSettings),
        subtitle: Text(
          s.blockingSettingsSubtitle,
          style: theme.textTheme.bodySmall?.copyWith(
            color: colorScheme.onSurfaceVariant,
          ),
        ),
        trailing: Icon(Icons.chevron_right,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
        onTap: () {
          HapticFeedback.lightImpact();
          _navigate(context, const BlockedItemsScreen());
        },
      ),
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}
