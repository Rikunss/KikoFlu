import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:flutter/foundation.dart' show kDebugMode;

import '../../../l10n/app_localizations.dart';
import '../../../src/providers/settings_provider.dart';
import '../../../src/services/log_service.dart';
import '../about_screen.dart';
import '../log_screen.dart';
import '../preferences_screen.dart';
import '../ui_settings_screen.dart';
import 'backup_restore_screen.dart';

/// MD3 Advanced screen consolidating Device Info, Display & Sorting,
/// Content Filtering, and Debug & Legacy tools.
class AdvancedScreen extends ConsumerStatefulWidget {
  const AdvancedScreen({super.key});

  @override
  ConsumerState<AdvancedScreen> createState() => _AdvancedScreenState();
}

class _AdvancedScreenState extends ConsumerState<AdvancedScreen> {
  late final Future<_DeviceInfo> _deviceInfoFuture;

  @override
  void initState() {
    super.initState();
    _deviceInfoFuture = _loadDeviceInfo();
  }

  Future<_DeviceInfo> _loadDeviceInfo() async {
    var version = 'Unknown';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (e) {
      LogService.instance.error('Failed to load package info: $e');
    }

    return _DeviceInfo(
      version: version,
      buildNumber: buildNumber,
      operatingSystem: Platform.operatingSystem,
      operatingSystemVersion: Platform.operatingSystemVersion,
      isAndroid: Platform.isAndroid,
      isIOS: Platform.isIOS,
      isWindows: Platform.isWindows,
      isMacOS: Platform.isMacOS,
      isLinux: Platform.isLinux,
    );
  }

  void _navigate(Widget screen) {
    Navigator.of(context).push(MaterialPageRoute(builder: (_) => screen));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final s = S.of(context);

    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar.medium(
            title: Text(s.settingsAdvanced),
          ),
          SliverList(
            delegate: SliverChildListDelegate([
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    const SizedBox(height: 8),

                    Card(
                      elevation: 0,
                      color: colorScheme.tertiaryContainer,
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            Icon(Icons.info_outline,
                                size: 18,
                                color: colorScheme.onTertiaryContainer),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                s.advancedInfoBanner,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    _buildDeviceInfoCard(context, colorScheme, s),
                    const SizedBox(height: 12),

                    Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildTile(
                            context,
                            Icons.sort_rounded,
                            s.defaultSortSettings,
                            s.advancedDefaultSortOrderSubtitle,
                            () => _navigate(const UiSettingsScreen()),
                            isLast: false,
                          ),
                          _buildTile(
                            context,
                            Icons.view_agenda_rounded,
                            s.myTabsDisplaySettings,
                            s.advancedMyTabsDisplaySubtitle,
                            () => _navigate(const UiSettingsScreen()),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildTile(
                            context,
                            Icons.library_books_rounded,
                            s.subtitleLibraryPriority,
                            s.advancedSubtitlePrioritySubtitle,
                            () => _navigate(const PreferencesScreen()),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          _buildTile(
                            context,
                            Icons.backup_rounded,
                            s.backupTitle,
                            s.backupSubtitle,
                            () => _navigate(const BackupRestoreScreen()),
                            isLast: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),

                    Card(
                      elevation: 0,
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                            child: Row(
                              children: [
                                Icon(Icons.developer_mode_outlined,
                                    size: 16, color: colorScheme.tertiary),
                                const SizedBox(width: 8),
                                Text(
                                  'Developer Tools',
                                  style: theme.textTheme.labelLarge?.copyWith(
                                    color: colorScheme.tertiary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          _buildTile(
                            context,
                            Icons.article_outlined,
                            'Log Viewer',
                            'View, filter, and export application logs',
                            () => _navigate(const LogScreen()),
                            isLast: false,
                          ),
                          if (kDebugMode)
                            _buildFpsToggle(context, colorScheme),
                        ],
                      ),
                    ),
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

  Widget _buildDeviceInfoCard(
    BuildContext context,
    ColorScheme colorScheme,
    S s,
  ) {
    return FutureBuilder<_DeviceInfo>(
      future: _deviceInfoFuture,
      builder: (ctx, snapshot) {
        final info = snapshot.data;
        final isLoading = snapshot.connectionState != ConnectionState.done;

        return Card(
          elevation: 0,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.tertiaryContainer,
                      child: Icon(Icons.devices_rounded,
                          color: colorScheme.onTertiaryContainer),
                    ),
                    const SizedBox(width: 16),
                    Text(
                      s.versionInfo,
                      style: Theme.of(ctx).textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                if (isLoading)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: LinearProgressIndicator(),
                  )
                else ...[
                  _buildInfoRow(
                    ctx,
                    Icons.tag_rounded,
                    s.currentVersion(
                        info!.buildNumber.isNotEmpty
                            ? '${info.version} (${info.buildNumber})'
                            : info.version),
                  ),
                  const Divider(height: 20, indent: 36),
                  _buildInfoRow(
                    ctx,
                    Icons.computer_rounded,
                    '${info.operatingSystem} ${info.operatingSystemVersion}',
                  ),
                  const Divider(height: 20, indent: 36),
                  _buildInfoRow(
                    ctx,
                    Icons.architecture_rounded,
                    _platformLabel(info),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () => _navigate(const AboutScreen()),
                    icon: const Icon(Icons.open_in_new, size: 18),
                    label: Text(s.aboutTitle),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _platformLabel(_DeviceInfo info) {
    if (info.isAndroid) return 'Android';
    if (info.isIOS) return 'iOS';
    if (info.isWindows) return 'Windows';
    if (info.isMacOS) return 'macOS';
    if (info.isLinux) return 'Linux';
    return info.operatingSystem;
  }

  Widget _buildInfoRow(
    BuildContext context,
    IconData icon,
    String text,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            text,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ),
      ],
    );
  }

  Widget _buildTile(
    BuildContext context,
    IconData icon,
    String title,
    String subtitle,
    VoidCallback onTap, {
    bool isLast = false,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    return Column(
      children: [
        ListTile(
          leading: CircleAvatar(
            backgroundColor: colorScheme.primary.withValues(alpha: 0.12),
            child: Icon(icon, color: colorScheme.primary, size: 22),
          ),
          title: Text(title),
          subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
          trailing: Icon(Icons.chevron_right,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
          onTap: onTap,
        ),
        if (!isLast)
          Divider(
              height: 1,
              indent: 72,
              color: theme.colorScheme.outlineVariant),
      ],
    );
  }

  Widget _buildFpsToggle(BuildContext context, ColorScheme cs) {
    final showFps = ref.watch(showFpsOverlayProvider);

    return Column(
      children: [
        Divider(height: 1, indent: 72, color: cs.outlineVariant),
        SwitchListTile(
          secondary: Icon(Icons.monitor_heart_outlined,
              color: showFps ? cs.primary : null),
          title: const Text('FPS Monitor'),
          subtitle: const Text('Show real-time FPS overlay on all screens'),
          value: showFps,
          onChanged: (v) =>
              ref.read(showFpsOverlayProvider.notifier).toggle(v),
        ),
      ],
    );
  }
}

/// Device information data holder.
class _DeviceInfo {
  final String version;
  final String buildNumber;
  final String operatingSystem;
  final String operatingSystemVersion;
  final bool isAndroid;
  final bool isIOS;
  final bool isWindows;
  final bool isMacOS;
  final bool isLinux;

  const _DeviceInfo({
    required this.version,
    required this.buildNumber,
    required this.operatingSystem,
    required this.operatingSystemVersion,
    required this.isAndroid,
    required this.isIOS,
    required this.isWindows,
    required this.isMacOS,
    required this.isLinux,
  });
}