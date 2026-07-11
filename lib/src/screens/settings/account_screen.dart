import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../l10n/app_localizations.dart';
import '../../../src/services/log_service.dart';
import '../../providers/auth_provider.dart';
import '../../providers/floating_lyric_provider.dart';
import '../../utils/snackbar_util.dart';
import '../account_management_screen.dart';
import '../floating_lyric_style_screen.dart';
import '../login_screen.dart';

/// MD3 Account screen consolidating Account Management, Floating Lyric,
/// and Permissions.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool _notificationGranted = false;
  bool _ignoreBatteryOptimizationsGranted = false;
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    if (Platform.isAndroid) {
      _checkPermissions();
    } else {
      _isCheckingPermissions = false;
    }
  }

  Future<void> _checkPermissions() async {
    setState(() => _isCheckingPermissions = true);
    try {
      _notificationGranted =
          await Permission.notification.status.then((s) => s.isGranted);
      _ignoreBatteryOptimizationsGranted =
          await Permission.ignoreBatteryOptimizations.status
              .then((s) => s.isGranted);
    } catch (e) {
      LogService.instance.error('Permission check failed: $e');
    }
    if (mounted) setState(() => _isCheckingPermissions = false);
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();
      if (!mounted) return;
      if (status.isGranted) {
        SnackBarUtil.showSuccess(
            context, S.of(context).notificationPermissionGranted);
        await _checkPermissions();
      } else if (status.isDenied) {
        SnackBarUtil.showWarning(
            context, S.of(context).notificationPermissionDenied);
      } else if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog(S.of(context).notificationPermission);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context,
            S.of(context)
                .requestNotificationFailed(e.toString()));
      }
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();
      if (!mounted) return;
      if (status.isGranted) {
        SnackBarUtil.showSuccess(
            context, S.of(context).backgroundPermissionGranted);
        await _checkPermissions();
      } else if (status.isDenied) {
        SnackBarUtil.showWarning(
            context, S.of(context).backgroundPermissionDenied);
      } else if (status.isPermanentlyDenied) {
        _showOpenSettingsDialog(S.of(context).backgroundRunningPermission);
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
            context,
            S.of(context)
                .requestBackgroundFailed(e.toString()));
      }
    }
  }

  void _showOpenSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).permissionRequired(permissionName)),
        content:
            Text(S.of(ctx).permissionPermanentlyDenied(permissionName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(S.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
              if (mounted) await _checkPermissions();
            },
            child: Text(S.of(ctx).openSettings),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(S.of(ctx).logout),
        content: Text(S.of(ctx).logoutConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(S.of(ctx).cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: Text(S.of(ctx).logout),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(authProvider.notifier).logout();
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }
    }
  }

  void _navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final s = S.of(context);
    final authState = ref.watch(authProvider);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsAccount),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    _buildAccountCard(context, colorScheme, s, authState, Theme.of(context)),
                    const SizedBox(height: 8),

                    _buildFloatingLyricCard(context, colorScheme, s, Theme.of(context)),
                    const SizedBox(height: 8),

                    _buildPermissionsCard(context, colorScheme, s, Theme.of(context)),

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

  Widget _buildAccountCard(
    BuildContext context,
    ColorScheme colorScheme,
    S s,
    AuthState authState,
    ThemeData theme,
  ) {
    final currentUser = authState.currentUser;
    final isLoggedIn = authState.isLoggedIn;

    final leadingIcon = CircleAvatar(
      backgroundColor: colorScheme.primaryContainer,
      child: Icon(Icons.person_rounded, color: colorScheme.onPrimaryContainer),
    );

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: leadingIcon,
            title: Text(
              currentUser?.name ?? s.noAccounts,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: isLoggedIn
                    ? colorScheme.onSurface
                    : colorScheme.onSurfaceVariant,
              ),
            ),
            subtitle: Text(
              isLoggedIn && currentUser?.host != null
                  ? currentUser!.host!
                  : (currentUser != null ? s.offlineModeStartup : s.noAccounts),
            ),
            trailing: CircleAvatar(
              backgroundColor: isLoggedIn
                  ? colorScheme.tertiaryContainer
                  : colorScheme.errorContainer,
              radius: 16,
              child: Icon(
                isLoggedIn ? Icons.check_circle : Icons.error_outline,
                size: 18,
                color: isLoggedIn
                    ? colorScheme.onTertiaryContainer
                    : colorScheme.onErrorContainer,
              ),
            ),
          ),
          const Divider(height: 1, indent: 72),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.swap_horiz_rounded,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.accountManagement),
            subtitle: Text(
              s.accountManagementSubtitle,
              style: theme.textTheme.bodySmall,
            ),
            trailing: Icon(Icons.chevron_right,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            onTap: () => _navigate(const AccountManagementScreen()),
          ),
          const Divider(height: 1, indent: 72),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.login_rounded,
                  color: colorScheme.primary, size: 22),
            ),
            title: Text(s.addAccount),
            subtitle: Text(
              isLoggedIn
                  ? s.switchAccountTitle
                  : s.noAccounts,
              style: theme.textTheme.bodySmall,
            ),
            trailing: FilledButton.tonalIcon(
              onPressed: () async {
                final result = await Navigator.push<bool>(
                  context,
                  MaterialPageRoute(
                    builder: (_) =>
                        const LoginScreen(isAddingAccount: true),
                  ),
                );
                if (result == true && mounted) {
                  setState(() {});
                }
              },
              icon: const Icon(Icons.add, size: 18),
              label: Text(s.add),
            ),
          ),
          if (isLoggedIn) ...[
            const Divider(height: 1, indent: 72),
            ListTile(
              leading: CircleAvatar(
                backgroundColor: colorScheme.error.withValues(alpha: 0.12),
                child: Icon(Icons.logout_rounded,
                    color: colorScheme.error, size: 22),
              ),
              title: Text(s.logout,
                  style: TextStyle(color: colorScheme.error)),
              onTap: _logout,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildFloatingLyricCard(
    BuildContext context,
    ColorScheme colorScheme,
    S s,
    ThemeData theme,
  ) {
    final floatingLyricEnabled = ref.watch(floatingLyricEnabledProvider);

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          SwitchListTile(
            secondary: CircleAvatar(
              backgroundColor: colorScheme.tertiaryContainer,
              child: Icon(Icons.lyrics_rounded,
                  color: colorScheme.onTertiaryContainer),
            ),
            title: Text(s.desktopFloatingLyric),
            subtitle: Text(
              floatingLyricEnabled
                  ? s.floatingLyricEnabled
                  : s.floatingLyricDisabled,
              style: theme.textTheme.bodySmall,
            ),
            value: floatingLyricEnabled,
            onChanged: (_) {
              ref.read(floatingLyricEnabledProvider.notifier).toggle();
            },
          ),

          if (floatingLyricEnabled) ...[
            const Divider(height: 1, indent: 72),
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.palette_rounded,
                  color: colorScheme.primary, size: 22),
            ),
              title: Text(s.floatingLyricStyle),
              subtitle: Text(
                s.styleSettingsSubtitle,
                style: theme.textTheme.bodySmall,
              ),
              trailing: Icon(Icons.chevron_right,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
              onTap: () => _navigate(const FloatingLyricStyleScreen()),
            ),
          ],

          if (Platform.isAndroid && floatingLyricEnabled) ...[
            const Divider(height: 1, indent: 72),
            _buildPlatformSwitch(
              context,
              Icons.lock_outline_rounded,
              s.floatingLyricTouch,
              ref.watch(floatingLyricTouchEnabledProvider),
              (val) {
                ref
                    .read(floatingLyricTouchEnabledProvider.notifier)
                    .setEnabled(val);
              },
            ),
          ],

          if (Platform.isIOS && floatingLyricEnabled) ...[
            const Divider(height: 1, indent: 72),
            _buildPlatformSwitch(
              context,
              Icons.speed_rounded,
              s.floatingFPS,
              ref.watch(floatingLyricFPSEnabledProvider),
              (_) {
                ref
                    .read(floatingLyricFPSEnabledProvider.notifier)
                    .toggle();
              },
            ),
          ],

          if (Platform.isIOS && floatingLyricEnabled) ...[
            const Divider(height: 1, indent: 72),
            _buildPlatformSwitch(
              context,
              Icons.wifi_rounded,
              s.floatingNetworkSpeed,
              ref.watch(floatingLyricNetworkSpeedEnabledProvider),
              (_) {
                ref
                    .read(floatingLyricNetworkSpeedEnabledProvider.notifier)
                    .toggle();
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPlatformSwitch(
    BuildContext context,
    IconData icon,
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return SwitchListTile(
      secondary: CircleAvatar(
        backgroundColor: colorScheme.secondary.withValues(alpha: 0.12),
        child: Icon(icon, color: colorScheme.secondary, size: 22),
      ),
      title: Text(title),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildPermissionsCard(
    BuildContext context,
    ColorScheme colorScheme,
    S s,
    ThemeData theme,
  ) {
    if (!Platform.isAndroid) {
      return Card(
        elevation: 0,
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.secondaryContainer,
            child: Icon(Icons.security_rounded,
                color: colorScheme.onSecondaryContainer),
          ),
          title: Text(s.permissionManagement),
          subtitle: Text(
            s.permissionsNotNeeded,
            style: theme.textTheme.bodySmall,
          ),
          trailing: Icon(Icons.check_circle_outline,
              color: colorScheme.onSurfaceVariant),
        ),
      );
    }

    if (_isCheckingPermissions) {
      return const Card(
        elevation: 0,
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    return Card(
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.secondaryContainer,
              child: Icon(Icons.security_rounded,
                  color: colorScheme.onSecondaryContainer),
            ),
            title: Text(s.permissionManagement),
            subtitle: Text(
              s.permissionManagementSubtitle,
              style: theme.textTheme.bodySmall,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.refresh_rounded),
              onPressed: _checkPermissions,
              tooltip: s.refreshPermissionStatus,
            ),
          ),
          const Divider(height: 1, indent: 72),

          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.secondary.withValues(alpha: 0.12),
              child: Icon(Icons.notifications_outlined, color: colorScheme.secondary, size: 22),
            ),
            title: Text(s.notificationPermission),
            subtitle: Text(
              _notificationGranted
                  ? s.notificationGrantedStatus
                  : s.notificationDeniedStatus,
              style: theme.textTheme.bodySmall,
            ),
            trailing: _notificationGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : FilledButton(
                    onPressed: _requestNotificationPermission,
                    child: Text(s.requestPermission),
                  ),
          ),
          const Divider(height: 1, indent: 72),

          ListTile(
            leading: CircleAvatar(
              backgroundColor: colorScheme.secondary.withValues(alpha: 0.12),
              child: Icon(Icons.battery_charging_full, color: colorScheme.secondary, size: 22),
            ),
            title: Text(s.backgroundRunningPermission),
            subtitle: Text(
              _ignoreBatteryOptimizationsGranted
                  ? s.backgroundGrantedStatus
                  : s.backgroundDeniedStatus,
              style: theme.textTheme.bodySmall,
            ),
            trailing: _ignoreBatteryOptimizationsGranted
                ? const Icon(Icons.check_circle, color: Colors.green)
                : FilledButton(
                    onPressed: _requestIgnoreBatteryOptimizations,
                    child: Text(s.requestPermission),
                  ),
          ),
        ],
      ),
    );
  }
}