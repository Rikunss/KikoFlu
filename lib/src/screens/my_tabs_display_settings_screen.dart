import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/my_tabs_display_provider.dart';
import '../providers/auth_provider.dart';
import '../utils/server_utils.dart';
import '../widgets/scrollable_appbar.dart';

class MyTabsDisplaySettingsScreen extends ConsumerWidget {
  const MyTabsDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(myTabsDisplayProvider);
    final notifier = ref.read(myTabsDisplayProvider.notifier);
    final authState = ref.watch(authProvider);
    final isOfficialServer = ServerUtils.isOfficialServer(authState.host);

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(
          S.of(context).myTabsDisplaySettings,
          style: const TextStyle(fontSize: 18),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Column(
              children: [
                SwitchListTile(
                  secondary: Icon(
                    Icons.favorite,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).onlineMarks),
                  subtitle: Text(S.of(context).showOnlineMarks),
                  value: settings.showOnlineMarks,
                  onChanged: (value) => notifier.setShowOnlineMarks(value),
                ),
                Divider(color: cs.outlineVariant),
                ListTile(
                  enabled: false,
                  leading: Icon(
                    Icons.download,
                    color: cs.onSurfaceVariant,
                  ),
                  title: Text(S.of(context).historyRecord),
                  subtitle: Text(
                    S.of(context).cannotBeDisabled,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Switch(
                    value: true,
                    onChanged: null,
                  ),
                ),
                if (isOfficialServer) ...[
                  Divider(color: cs.outlineVariant),
                  SwitchListTile(
                    secondary: Icon(
                      Icons.playlist_play,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(S.of(context).playlists),
                    subtitle: Text(S.of(context).showPlaylists),
                    value: settings.showPlaylists,
                    onChanged: (value) => notifier.setShowPlaylists(value),
                  ),
                ],
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.subtitles,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).subtitleLibrary),
                  subtitle: Text(S.of(context).showSubtitleLibrary),
                  value: settings.showSubtitleLibrary,
                  onChanged: (value) => notifier.setShowSubtitleLibrary(value),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.bar_chart_rounded,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).listeningStatsTitle),
                  subtitle: Text(S.of(context).showStats),
                  value: settings.showStats,
                  onChanged: (value) => notifier.setShowStats(value),
                ),
                Divider(color: cs.outlineVariant),
                ListTile(
                  enabled: false,
                  leading: Icon(
                    Icons.download,
                    color: cs.onSurfaceVariant,
                  ),
                  title: Text(S.of(context).downloaded),
                  subtitle: Text(
                    S.of(context).cannotBeDisabled,
                    style: TextStyle(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                  trailing: const Switch(
                    value: true,
                    onChanged: null,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}