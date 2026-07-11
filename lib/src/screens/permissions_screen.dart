import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../l10n/app_localizations.dart';
import '../../src/services/log_service.dart';
import '../utils/snackbar_util.dart';

/// 权限管理页面（仅安卓平台）
class PermissionsScreen extends StatefulWidget {
  const PermissionsScreen({super.key});

  @override
  State<PermissionsScreen> createState() => _PermissionsScreenState();
}

class _PermissionsScreenState extends State<PermissionsScreen> {
  bool _notificationGranted = false;
  bool _ignoreBatteryOptimizationsGranted = false;
  bool _isCheckingPermissions = true;

  @override
  void initState() {
    super.initState();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    setState(() {
      _isCheckingPermissions = true;
    });

    try {
      final notificationStatus = await Permission.notification.status;
      _notificationGranted = notificationStatus.isGranted;

      final batteryStatus = await Permission.ignoreBatteryOptimizations.status;
      _ignoreBatteryOptimizationsGranted = batteryStatus.isGranted;
    } catch (e) {
      LogService.instance.error('检查权限失败: $e');
    }

    if (mounted) {
      setState(() {
        _isCheckingPermissions = false;
      });
    }
  }

  Future<void> _requestNotificationPermission() async {
    try {
      final status = await Permission.notification.request();

      if (mounted) {
        if (status.isGranted) {
          SnackBarUtil.showSuccess(context, S.of(context).notificationPermissionGranted);
          await _checkPermissions();
        } else if (status.isDenied) {
          SnackBarUtil.showWarning(context, S.of(context).notificationPermissionDenied);
        } else if (status.isPermanentlyDenied) {
          _showOpenSettingsDialog(S.of(context).notificationPermission);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, S.of(context).requestNotificationFailed(e.toString()));
      }
    }
  }

  Future<void> _requestIgnoreBatteryOptimizations() async {
    try {
      final status = await Permission.ignoreBatteryOptimizations.request();

      if (mounted) {
        if (status.isGranted) {
          SnackBarUtil.showSuccess(context, S.of(context).backgroundPermissionGranted);
          await _checkPermissions();
        } else if (status.isDenied) {
          SnackBarUtil.showWarning(context, S.of(context).backgroundPermissionDenied);
        } else if (status.isPermanentlyDenied) {
          _showOpenSettingsDialog(S.of(context).backgroundRunningPermission);
        }
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, S.of(context).requestBackgroundFailed(e.toString()));
      }
    }
  }

  void _showOpenSettingsDialog(String permissionName) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(S.of(context).permissionRequired(permissionName)),
        content: Text(S.of(context).permissionPermanentlyDenied(permissionName)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(S.of(context).cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(context).pop();
              await openAppSettings();
              if (mounted) {
                await _checkPermissions();
              }
            },
            child: Text(S.of(context).openSettings),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (!Platform.isAndroid) {
      return Scaffold(
        appBar: AppBar(
          title: Text(S.of(context).permissionManagement, style: const TextStyle(fontSize: 18)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.info_outline,
                size: 64,
                color: cs.primary,
              ),
              const SizedBox(height: 16),
              Text(
                S.of(context).permissionsAndroidOnly,
                style: tt.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                S.of(context).permissionsNotNeeded,
                style: tt.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).permissionManagement, style: const TextStyle(fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _checkPermissions,
            tooltip: S.of(context).refreshPermissionStatus,
          ),
        ],
      ),
      body: _isCheckingPermissions
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Card(
                  color: cs.surfaceContainerHighest,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              Icons.lightbulb_outline,
                              color: cs.onSurfaceVariant,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              S.of(context).permissionExplanation,
                              style: tt.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        _buildPermissionExplanation(
                          context,
                          S.of(context).notificationPermission,
                          S.of(context).notificationPermissionDesc,
                        ),
                        const SizedBox(height: 8),
                        _buildPermissionExplanation(
                          context,
                          S.of(context).backgroundRunningPermission,
                          S.of(context).backgroundRunningPermissionDesc,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.notifications_outlined,
                      color: _notificationGranted
                          ? Colors.green
                          : cs.primary,
                      size: 32,
                    ),
                    title: Text(S.of(context).notificationPermission),
                    subtitle: Text(
                      _notificationGranted
                          ? S.of(context).notificationGrantedStatus
                          : S.of(context).notificationDeniedStatus,
                    ),
                    trailing: _notificationGranted
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : FilledButton(
                            onPressed: _requestNotificationPermission,
                            child: Text(S.of(context).requestPermission),
                          ),
                  ),
                ),
                const SizedBox(height: 8),

                Card(
                  child: ListTile(
                    leading: Icon(
                      Icons.battery_charging_full,
                      color: _ignoreBatteryOptimizationsGranted
                          ? Colors.green
                          : cs.primary,
                      size: 32,
                    ),
                    title: Text(S.of(context).backgroundRunningPermission),
                    subtitle: Text(
                      _ignoreBatteryOptimizationsGranted
                          ? S.of(context).backgroundGrantedStatus
                          : S.of(context).notificationDeniedStatus,
                    ),
                    trailing: _ignoreBatteryOptimizationsGranted
                        ? const Icon(Icons.check_circle, color: Colors.green)
                        : FilledButton(
                            onPressed: _requestIgnoreBatteryOptimizations,
                            child: Text(S.of(context).requestPermission),
                          ),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildPermissionExplanation(
    BuildContext context,
    String title,
    String description,
  ) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          Icons.check_circle_outline,
          size: 16,
          color: cs.primary,
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
              Text(
                description,
                style: tt.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}