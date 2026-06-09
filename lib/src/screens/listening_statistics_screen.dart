import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../providers/listening_stats_provider.dart';
import '../services/listening_stats_service.dart';
import '../models/history_record.dart';
import '../models/work.dart';
import '../widgets/history_work_card.dart';

/// Listening Statistics Dashboard
///
/// Shows overview cards, daily activity bar chart, top VAs, top circles,
/// and recent plays computed from playback history.
class ListeningStatisticsScreen extends ConsumerWidget {
  const ListeningStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(listeningStatsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(S.of(context).listeningStatsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: S.of(context).refresh,
            onPressed: () => refreshListeningStats(ref),
          ),
        ],
      ),
      body: statsAsync.when(
        data: (stats) => _StatsContent(stats: stats),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, size: 64,
                    color: Theme.of(context).colorScheme.error),
                const SizedBox(height: 16),
                Text(
                  S.of(context).loadFailed,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  '$err',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => refreshListeningStats(ref),
                  icon: const Icon(Icons.refresh),
                  label: Text(S.of(context).retry),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatsContent extends ConsumerWidget {
  final ListeningStats stats;

  const _StatsContent({required this.stats});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (stats.totalWorksPlayed == 0) {
      return _buildEmptyState(context);
    }

    return RefreshIndicator(
      onRefresh: () async => refreshListeningStats(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          // ── Overview Cards Grid ──
          _buildOverviewGrid(context),

          const SizedBox(height: 24),

          // ── Daily Activity Bar Chart ──
          _SectionHeader(
            icon: Icons.bar_chart_rounded,
            title: S.of(context).statsDailyActivity,
          ),
          const SizedBox(height: 12),
          _DailyActivityChart(activity: stats.dailyActivity),

          const SizedBox(height: 24),

          // ── Top Voice Actors ──
          if (stats.topVAs.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.mic_rounded,
              title: S.of(context).statsTopVAs,
            ),
            const SizedBox(height: 8),
            _TopVAsList(vas: stats.topVAs),
            const SizedBox(height: 24),
          ],

          // ── Top Circles ──
          if (stats.topCircles.isNotEmpty) ...[
            _SectionHeader(
              icon: Icons.group_rounded,
              title: S.of(context).statsTopCircles,
            ),
            const SizedBox(height: 8),
            _TopCirclesList(circles: stats.topCircles),
            const SizedBox(height: 24),
          ],

          // ── Recent Plays ──
          _SectionHeader(
            icon: Icons.history_rounded,
            title: S.of(context).statsRecentPlays,
          ),
          const SizedBox(height: 8),
          _RecentPlaysGrid(records: stats.recentPlays),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: cs.primaryContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bar_chart_rounded, size: 56, color: cs.primary),
            ),
            const SizedBox(height: 24),
            Text(
              S.of(context).statsNoData,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              S.of(context).statsNoDataDesc,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewGrid(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Format listening time
    final totalMinutes = stats.approximateListeningTime.inMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0
        ? '${S.of(context).nHours(hours)} ${S.of(context).nMinutes(mins)}'
        : S.of(context).nMinutes(mins);

    final cards = [
      _OverviewCardData(
        icon: Icons.headphones_rounded,
        color: cs.primary,
        value: '${stats.totalWorksPlayed}',
        label: S.of(context).statsWorksPlayed,
      ),
      _OverviewCardData(
        icon: Icons.check_circle_rounded,
        color: Colors.green,
        value: '${stats.completedWorks}',
        label: S.of(context).statsCompleted,
      ),
      _OverviewCardData(
        icon: Icons.access_time_rounded,
        color: cs.tertiary,
        value: timeStr,
        label: S.of(context).statsListeningTime,
      ),
      _OverviewCardData(
        icon: Icons.local_fire_department_rounded,
        color: Colors.deepOrange,
        value: '${stats.currentStreakDays}',
        label: S.of(context).statsStreakDays,
        suffix: S.of(context).statsDays,
      ),
    ];

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.4,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: cards.length,
      itemBuilder: (context, index) => _buildOverviewCard(
        context, cards[index], cs, theme,
      ),
    );
  }

  Widget _buildOverviewCard(
    BuildContext context,
    _OverviewCardData data,
    ColorScheme cs,
    ThemeData theme,
  ) {
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: data.color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(data.icon, size: 20, color: data.color),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    data.value,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: data.color,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (data.suffix != null) ...[
                  const SizedBox(width: 2),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      data.suffix!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 2),
            Text(
              data.label,
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════
// Supporting Widgets
// ═══════════════════════════════════════════════════

class _OverviewCardData {
  final IconData icon;
  final Color color;
  final String value;
  final String label;
  final String? suffix;

  const _OverviewCardData({
    required this.icon,
    required this.color,
    required this.value,
    required this.label,
    this.suffix,
  });
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({required this.icon, required this.title});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, size: 18, color: cs.primary),
        const SizedBox(width: 8),
        Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Simple bar chart for daily activity (last 14 days).
class _DailyActivityChart extends StatelessWidget {
  final List<DailyActivity> activity;

  const _DailyActivityChart({required this.activity});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final maxCount = activity.fold<int>(0, (m, a) => a.playCount > m ? a.playCount : m);
    final maxBarHeight = 120.0;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 16, 8, 12),
        child: SizedBox(
          height: 160,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(activity.length, (i) {
              final day = activity[i];
              final barHeight = maxCount > 0
                  ? (day.playCount / maxCount) * maxBarHeight
                  : 0.0;
              final isToday = i == activity.length - 1;
              final dayLabel = _dayLabel(day.date);

              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      if (day.playCount > 0)
                        Text(
                          '${day.playCount}',
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontSize: 9,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      const SizedBox(height: 2),
                      Container(
                        height: barHeight.clamp(0.0, maxBarHeight),
                        decoration: BoxDecoration(
                          borderRadius: const BorderRadius.vertical(
                            top: Radius.circular(4),
                          ),
                          color: isToday ? cs.primary : cs.primary.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        dayLabel,
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontSize: 9,
                          color: cs.onSurfaceVariant,
                          fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime date) {
    final weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  }
}

/// Top voice actors list with rank indicators.
class _TopVAsList extends StatelessWidget {
  final List<VaStat> vas;

  const _TopVAsList({required this.vas});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: List.generate(vas.length, (i) {
            final va = vas[i];
            final rankColor = i == 0
                ? Colors.amber
                : i == 1
                    ? Colors.grey.shade400
                    : i == 2
                        ? Colors.brown.shade300
                        : Colors.transparent;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: ListTile(
                dense: true,
                leading: rankColor != Colors.transparent
                    ? Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: rankColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                              color: rankColor,
                            ),
                          ),
                        ),
                      )
                    : SizedBox(
                        width: 28,
                        child: Center(
                          child: Text(
                            '${i + 1}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                title: Text(va.name, style: const TextStyle(fontSize: 14)),
                trailing: Text(
                  S.of(context).nPlaysCount(va.playCount),
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Top circles list.
class _TopCirclesList extends StatelessWidget {
  final List<CircleStat> circles;

  const _TopCirclesList({required this.circles});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          children: List.generate(circles.length, (i) {
            final circle = circles[i];
            return ListTile(
              dense: true,
              leading: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${i + 1}',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: cs.primary,
                    ),
                  ),
                ),
              ),
              title: Text(circle.name, style: const TextStyle(fontSize: 14)),
              trailing: Text(
                S.of(context).nPlaysCount(circle.playCount),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

/// Recent plays grid using the existing HistoryWorkCard widget.
class _RecentPlaysGrid extends StatelessWidget {
  final List<HistoryRecord> records;

  const _RecentPlaysGrid({required this.records});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
            maxCrossAxisExtent: 180,
            childAspectRatio: 0.72,
            crossAxisSpacing: 8,
            mainAxisSpacing: 8,
          ),
          itemCount: records.length,
          itemBuilder: (context, index) {
            final record = records[index];
            return RepaintBoundary(
              child: HistoryWorkCard(
                key: ValueKey('stats_${record.work.id}'),
                record: record,
              ),
            );
          },
        ),
      ),
    );
  }
}
