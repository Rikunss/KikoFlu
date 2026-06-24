import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../l10n/app_localizations.dart';
import '../blocked_items_screen.dart';
import '../lock_screen_setup_sheet.dart';
import '../../providers/settings_provider.dart';
import '../../services/app_lock_service.dart';
import '../../services/log_service.dart';
import '../../utils/snackbar_util.dart';

/// Auto-lock timeout options.
final _autoLockOptions = <int>[-1, 0, 1, 5, 15, 30];

/// State for App Lock toggles.
class AppLockSettingsState {
  final bool lockEnabled;
  final bool bioEnabled;

  const AppLockSettingsState({
    this.lockEnabled = false,
    this.bioEnabled = false,
  });
}

/// Notifier for App Lock settings — mirrors [AppLockService] state.
/// Uses the same pattern as [PrivacyModeSettingsNotifier] which works
/// reliably across all devices (unlike local setState or StateProvider
/// which fail to trigger rebuilds on some MIUI devices).
class AppLockSettingsNotifier extends StateNotifier<AppLockSettingsState> {
  AppLockSettingsNotifier() : super(AppLockSettingsState(
    lockEnabled: AppLockService.instance.isEnabled,
    bioEnabled: AppLockService.instance.isBiometricEnabled,
  ));

  void updateLockEnabled(bool value) {
    state = AppLockSettingsState(
      lockEnabled: value,
      bioEnabled: value ? state.bioEnabled : false,
    );
  }

  void updateBioEnabled(bool value) {
    state = AppLockSettingsState(
      lockEnabled: state.lockEnabled,
      bioEnabled: value,
    );
  }

  void setFromService() {
    state = AppLockSettingsState(
      lockEnabled: AppLockService.instance.isEnabled,
      bioEnabled: AppLockService.instance.isBiometricEnabled,
    );
  }
}

final appLockSettingsProvider =
    StateNotifierProvider<AppLockSettingsNotifier, AppLockSettingsState>((ref) {
  return AppLockSettingsNotifier();
});

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

                    // ── App Lock (wrapped in Consumer for reliable rebuild) ──
                    Consumer(
                      builder: (context, ref, _) {
                        return _buildAppLockCard(
                          context,
                          s,
                          ref.watch(appLockSettingsProvider),
                        );
                      },
                    ),
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
  // App Lock Card
  // ──────────────────────────────────────────────

  Widget _buildAppLockCard(
      BuildContext context, S s, AppLockSettingsState appLockState) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final lockEnabled = appLockState.lockEnabled;
    final bioEnabled = appLockState.bioEnabled;

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
              child: Icon(Icons.lock_outline_rounded,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.appLockTitle),
            subtitle: Text(
              lockEnabled
                  ? s.appLockEnabledSubtitle
                  : s.appLockDisabledSubtitle,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            value: lockEnabled,
            onChanged: (value) async {
              HapticFeedback.lightImpact();
              if (value) {
                // Open setup sheet
                if (!context.mounted) return;
                final result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) => const LockScreenSetupSheet(),
                );
                if (result == true && mounted) {
                  // Re-read from service since we don't know if biometric
                  // was enabled inside the setup sheet.
                  ref.read(appLockSettingsProvider.notifier)
                      .setFromService();
                }
              } else {
                // Disable — confirm first
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Text(s.appLockDisableConfirmTitle),
                    content: Text(s.appLockDisableConfirmMessage),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(s.cancel),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(s.appLockDisable),
                      ),
                    ],
                  ),
                );
                if (confirmed == true && mounted) {
                  await AppLockService.instance.disable();
                  if (context.mounted) {
                    ref.read(appLockSettingsProvider.notifier)
                        .updateLockEnabled(false);
                    SnackBarUtil.showSuccess(context, s.appLockDisabledToast);
                  }
                }
              }
            },
          ),
          if (lockEnabled) ...[
            Divider(
              height: 1,
              indent: 72,
              color: colorScheme.outlineVariant,
            ),
            SwitchListTile(
              secondary: CircleAvatar(
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.fingerprint,
                    color: colorScheme.primary, size: 22),
              ),
              title: Text(s.appLockBiometric),
              subtitle: Text(
                bioEnabled
                    ? s.appLockBiometricEnabledSubtitle
                    : s.appLockBiometricDisabledSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              value: bioEnabled,
              onChanged: (value) async {
                HapticFeedback.lightImpact();
                try {
                  if (value) {
                    // Try biometric directly. On some devices (e.g. MIUI)
                    // canUseBiometric() hangs/times out even though biometric
                    // IS available. So we skip the availability check and let
                    // the OS handle the biometric dialog.
                    final success = await AppLockService.instance
                        .authenticateBiometric(
                      reason: s.appLockBiometricEnableReason,
                    );
                    if (success && mounted) {
                      await AppLockService.instance.setBiometricEnabled(true);
                      if (mounted) {
                        ref.read(appLockSettingsProvider.notifier)
                            .updateBioEnabled(true);
                      }
                    }
                  } else {
                    // Turn OFF — no auth needed, just update storage
                    await AppLockService.instance.setBiometricEnabled(false);
                    if (mounted) {
                      ref.read(appLockSettingsProvider.notifier)
                          .updateBioEnabled(false);
                    }
                  }
                } catch (e, stack) {
                  LogService.instance.error('[BiometricToggle] UNCAUGHT ERROR: $e\n$stack', tag: 'BiometricToggle');
                }
              },
            ),
            Divider(
              height: 1,
              indent: 72,
              color: colorScheme.outlineVariant,
            ),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.password_rounded,
                    color: colorScheme.primary, size: 22),
              ),
              title: Text(s.appLockChangePin),
              subtitle: Text(
                s.appLockChangePinSubtitle,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              trailing: Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              onTap: () async {
                if (!context.mounted) return;
                final result = await showModalBottomSheet<bool>(
                  context: context,
                  isScrollControlled: true,
                  shape: const RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.vertical(top: Radius.circular(20)),
                  ),
                  builder: (_) =>
                      const LockScreenSetupSheet(changePin: true),
                );
                if (result == true && context.mounted) {
                  SnackBarUtil.showSuccess(context, s.appLockPinChanged);
                  setState(() {});
                }
              },
            ),
            Divider(
              height: 1,
              indent: 72,
              color: colorScheme.outlineVariant,
            ),
            _buildAutoLockTimeoutTile(context, s, AppLockService.instance),
          ],
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

  // ──────────────────────────────────────────────
  // Auto-lock Timeout
  // ──────────────────────────────────────────────

  String _autoLockLabel(S s, int minutes) {
    return switch (minutes) {
      -1 => s.appLockAutoLockNever,
      0 => s.appLockAutoLockImmediately,
      1 => s.appLockAutoLock1Min,
      5 => s.appLockAutoLock5Min,
      15 => s.appLockAutoLock15Min,
      30 => s.appLockAutoLock30Min,
      _ => '$minutes ${s.appLockAutoLockMinutes}',
    };
  }

  Widget _buildAutoLockTimeoutTile(
      BuildContext context, S s, AppLockService lockService) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final currentTimeout = lockService.autoLockTimeoutMinutes;

    return ListTile(
      leading: CircleAvatar(
        backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
        child: Icon(Icons.timer_outlined,
            color: colorScheme.primary, size: 22),
      ),
      title: Text(s.appLockAutoLock),
      subtitle: Text(
        _autoLockLabel(s, currentTimeout),
        style: theme.textTheme.bodySmall?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Icon(Icons.chevron_right,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
      onTap: () async {
        if (!context.mounted) return;
        final result = await showModalBottomSheet<int>(
          context: context,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          builder: (ctx) => _AutoLockTimeoutSheet(
            current: currentTimeout,
            labels: _autoLockOptions
                .map((m) => _autoLockLabel(S.of(ctx), m))
                .toList(),
          ),
        );
        if (result != null && mounted) {
          await lockService.setAutoLockTimeout(result);
          setState(() {});
        }
      },
    );
  }

  void _navigate(BuildContext context, Widget screen) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => screen),
    );
  }
}

/// Bottom sheet for selecting auto-lock timeout.
class _AutoLockTimeoutSheet extends StatelessWidget {
  final int current;
  final List<String> labels;

  const _AutoLockTimeoutSheet({
    required this.current,
    required this.labels,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag handle
            Container(
              width: 32,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            ...List.generate(_autoLockOptions.length, (i) {
              final value = _autoLockOptions[i];
              final label = labels[i];
              final selected = value == current;
              return ListTile(
                leading: Icon(
                  selected
                      ? Icons.radio_button_checked
                      : Icons.radio_button_unchecked,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
                title: Text(
                  label,
                  style: TextStyle(
                    fontWeight:
                        selected ? FontWeight.w600 : FontWeight.normal,
                    color: selected ? cs.primary : cs.onSurface,
                  ),
                ),
                onTap: () => Navigator.pop(context, value),
              );
            }),
          ],
        ),
      ),
    );
  }
}
