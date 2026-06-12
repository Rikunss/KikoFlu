import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/work_detail_display_provider.dart';
import '../widgets/scrollable_appbar.dart';

class WorkDetailDisplaySettingsScreen extends ConsumerWidget {
  const WorkDetailDisplaySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(workDetailDisplayProvider);
    final notifier = ref.read(workDetailDisplayProvider.notifier);
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(
          S.of(context).workDetailDisplaySettings,
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
                  subtitle: Text(S.of(context).showWorkDuration),
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
                    Icons.open_in_new,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).externalLinkInfo),
                  subtitle: Text(S.of(context).showExternalLinks),
                  value: settings.showExternalLinks,
                  onChanged: (_) => notifier.toggleExternalLinks(),
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
                    Icons.translate,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).translateButtonLabel),
                  subtitle: Text(S.of(context).showTranslateButton),
                  value: settings.showTranslateButton,
                  onChanged: (_) => notifier.toggleTranslateButton(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.closed_caption,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).subtitleTagLabel),
                  subtitle: Text(S.of(context).showSubtitleTagOnCover),
                  value: settings.showSubtitleTag,
                  onChanged: (_) => notifier.toggleSubtitleTag(),
                ),
                Divider(color: cs.outlineVariant),
                SwitchListTile(
                  secondary: Icon(
                    Icons.recommend_outlined,
                    color: cs.primary,
                  ),
                  title: Text(S.of(context).recommendationsLabel),
                  subtitle: Text(S.of(context).showRecommendations),
                  value: settings.showRecommendations,
                  onChanged: (_) => notifier.toggleRecommendations(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
