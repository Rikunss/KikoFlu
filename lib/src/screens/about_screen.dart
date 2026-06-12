import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/log_service.dart';
import '../providers/update_provider.dart';
import '../widgets/scrollable_appbar.dart';
import '../../l10n/app_localizations.dart';

class AboutScreen extends ConsumerStatefulWidget {
  const AboutScreen({super.key});

  @override
  ConsumerState<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends ConsumerState<AboutScreen> {
  static final Uri _repoUri =
      Uri.parse('https://github.com/Meteor-Sage/Kikoeru-Flutter');
  late final Future<_AboutData> _aboutFuture;

  @override
  void initState() {
    super.initState();
    _aboutFuture = _loadAboutData();

    // Mark update as notified when entering this screen (hide red dot only)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final updateService = ref.read(updateServiceProvider);
      updateService.markAsNotified();
      // Only hide red dot, keep the "New Version" badge visible
      ref.read(showUpdateRedDotProvider.notifier).state = false;
    });
  }

  Future<_AboutData> _loadAboutData() async {
    var version = 'Unknown';
    var buildNumber = '';
    try {
      final info = await PackageInfo.fromPlatform();
      version = info.version;
      buildNumber = info.buildNumber;
    } catch (error, stackTrace) {
      LogService.instance.error('AboutScreen: failed to load app version: $error', tag: 'UI');
      LogService.instance.error('AboutScreen: stackTrace: $stackTrace', tag: 'UI');
    }

    var licenseText = 'Failed to load LICENSE';
    try {
      final raw = await rootBundle.loadString('LICENSE');
      licenseText = raw.trim().isEmpty ? 'LICENSE is empty' : raw.trim();
    } catch (error, stackTrace) {
      LogService.instance.error('AboutScreen: failed to load license: $error', tag: 'UI');
      LogService.instance.error('AboutScreen: license stackTrace: $stackTrace', tag: 'UI');
    }

    return _AboutData(
      version: version,
      buildNumber: buildNumber,
      license: licenseText,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(S.of(context).aboutTitle, style: const TextStyle(fontSize: 18)),
      ),
      body: FutureBuilder<_AboutData>(
        future: _aboutFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return _buildLoadingSkeleton(context);
          }

          if (!snapshot.hasData) {
            return _buildErrorState(context);
          }

          final data = snapshot.data!;
          final versionLabel = data.buildNumber.isNotEmpty
              ? '${data.version} (${data.buildNumber})'
              : data.version;

          final updateInfo = ref.watch(updateInfoProvider);
          final isCheckingUpdate = ref.watch(isCheckingUpdateProvider);

          final cs = Theme.of(context).colorScheme;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Update check card - shown at top if update available
              if (updateInfo != null && updateInfo.hasNewVersion)
                _buildUpdateCard(context, cs, updateInfo),
              if (updateInfo != null && updateInfo.hasNewVersion)
                const SizedBox(height: 16),

              _buildInfoCard(
                context: context,
                icon: Icons.verified,
                iconColor: cs.primary,
                title: S.of(context).versionInfo,
                subtitle: S.of(context).currentVersion(versionLabel),
                trailing: isCheckingUpdate
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : TextButton(
                        onPressed: _manualCheckUpdate,
                        child: Text(S.of(context).checkUpdate),
                      ),
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                context: context,
                icon: Icons.person_outline,
                iconColor: cs.primary,
                title: S.of(context).author,
                subtitle: 'Meteor-Sage, Rikunss',
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                context: context,
                icon: Icons.link,
                iconColor: cs.primary,
                title: S.of(context).projectRepo,
                subtitle: _repoUri.toString(),
                trailing: Icon(Icons.open_in_new,
                    size: 18, color: cs.onSurfaceVariant.withValues(alpha: 0.6)),
                onTap: _openRepository,
              ),
              const SizedBox(height: 12),
              _buildInfoCard(
                context: context,
                icon: Icons.gavel_outlined,
                iconColor: cs.primary,
                title: S.of(context).openSourceLicense,
                subtitle: 'LICENSE',
                trailing: Icon(Icons.chevron_right,
                    size: 24, color: cs.onSurfaceVariant.withValues(alpha: 0.5)),
                onTap: () => _showLicenseDialog(data.license),
              ),
              const SizedBox(height: 24),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLoadingSkeleton(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: List.generate(
        4,
        (index) => Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.3, end: 0.7),
            duration: const Duration(milliseconds: 1000),
            builder: (context, value, child) {
              return Card(
                elevation: 0,
                color: cs.surfaceContainerLow,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest
                              .withValues(alpha: value * 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              height: 14,
                              width: 120,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: value * 0.6),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              height: 12,
                              width: 180,
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest
                                    .withValues(alpha: value * 0.4),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 40,
                color: cs.error,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              S.of(context).loadFailed,
              style: tt.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).failedToLoadAbout,
              style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            FilledButton.tonalIcon(
              onPressed: () {
                HapticFeedback.lightImpact();
                setState(() {
                  _aboutFuture = _loadAboutData();
                });
              },
              icon: const Icon(Icons.refresh, size: 18),
              label: Text(S.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUpdateCard(
      BuildContext context, ColorScheme cs, dynamic updateInfo) {
    final tt = Theme.of(context).textTheme;
    final s = S.of(context);
    return Card(
      elevation: 0,
      color: cs.secondaryContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticFeedback.lightImpact();
          _openUrl(updateInfo.releaseUrl);
        },
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: cs.onSecondaryContainer.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.system_update,
                  color: cs.onSecondaryContainer,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      s.newVersionFound,
                      style: tt.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: cs.onSecondaryContainer,
                          ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      s.newVersionAvailable(
                          updateInfo.latestVersion, updateInfo.currentVersion),
                      style: tt.bodySmall?.copyWith(
                            color: cs.onSecondaryContainer,
                          ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                Icons.open_in_new,
                size: 18,
                color: cs.onSecondaryContainer.withValues(alpha: 0.7),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap != null
            ? () {
                HapticFeedback.lightImpact();
                onTap();
              }
            : null,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 20),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: tt.titleSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: tt.bodySmall?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing],
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRepository() async {
    await _openUrl(_repoUri.toString());
  }

  Future<void> _openUrl(String urlString) async {
    try {
      final uri = Uri.parse(urlString);
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).cannotOpenLink)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(S.of(context).openLinkFailed(error.toString()))),
      );
    }
  }

  Future<void> _manualCheckUpdate() async {
    if (ref.read(isCheckingUpdateProvider)) return;

    ref.read(isCheckingUpdateProvider.notifier).state = true;

    try {
      final updateService = ref.read(updateServiceProvider);
      final updateInfo = await updateService.checkForUpdates(force: true);

      if (!mounted) return;

      if (updateInfo != null && updateInfo.hasNewVersion) {
        ref.read(updateInfoProvider.notifier).state = updateInfo;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(S.of(context).foundNewVersion(updateInfo.latestVersion)),
            action: SnackBarAction(
              label: S.of(context).view,
              onPressed: () => _openUrl(updateInfo.releaseUrl),
            ),
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).alreadyLatestVersion)),
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(S.of(context).checkUpdateFailed)),
      );
    } finally {
      if (mounted) {
        ref.read(isCheckingUpdateProvider.notifier).state = false;
      }
    }
  }

  void _showLicenseDialog(String license) {
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(S.of(context).openSourceLicense),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: SelectableText(license),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text(S.of(context).close),
            ),
          ],
        );
      },
    );
  }
}

class _AboutData {
  final String version;
  final String buildNumber;
  final String license;

  const _AboutData({
    required this.version,
    required this.buildNumber,
    required this.license,
  });
}
