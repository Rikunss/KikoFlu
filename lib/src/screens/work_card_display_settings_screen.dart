import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/work_card_display_provider.dart';
import '../widgets/scrollable_appbar.dart';

class WorkCardDisplaySettingsScreen extends ConsumerWidget {
  const WorkCardDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final settings = ref.watch(workCardDisplayProvider);
    final notifier = ref.read(workCardDisplayProvider.notifier);

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(
          S.of(context).workCardDisplaySettings,
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
                    Icons.star,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).ratingInfo),
                  subtitle: Text(S.of(context).showRatingAndReviewCount),
                  value: settings.showRating,
                  onChanged: (_) => notifier.toggleRating(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.attach_money,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).priceInfo),
                  subtitle: Text(S.of(context).showWorkPrice),
                  value: settings.showPrice,
                  onChanged: (_) => notifier.togglePrice(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.access_time,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).durationInfo),
                  subtitle: Text(S.of(context).showWorkTotalDuration),
                  value: settings.showDuration,
                  onChanged: (_) => notifier.toggleDuration(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.shopping_cart,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).salesInfo),
                  subtitle: Text(S.of(context).showWorkSalesCount),
                  value: settings.showSales,
                  onChanged: (_) => notifier.toggleSales(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.calendar_today,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).releaseDateInfo),
                  subtitle: Text(S.of(context).showWorkReleaseDate),
                  value: settings.showReleaseDate,
                  onChanged: (_) => notifier.toggleReleaseDate(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.group,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).circleInfo),
                  subtitle: Text(S.of(context).showWorkCircle),
                  value: settings.showCircle,
                  onChanged: (_) => notifier.toggleCircle(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.closed_caption,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).subtitleTagLabel),
                  subtitle: Text(S.of(context).showSubtitleTagOnCard),
                  value: settings.showSubtitleTag,
                  onChanged: (_) => notifier.toggleSubtitleTag(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}