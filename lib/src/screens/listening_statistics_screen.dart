import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../l10n/app_localizations.dart';
import '../providers/listening_stats_provider.dart';
import '../services/listening_stats_service.dart';
import '../models/history_record.dart';
import '../widgets/history_work_card.dart';

/// Listening Statistics Dashboard
///
/// Shows overview cards, daily activity bar chart, top VAs, top circles,
/// and recent plays computed from playback history.
class ListeningStatisticsScreen extends ConsumerWidget {
  const ListeningStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
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
        loading: () => const Center(
          child: SizedBox(
            width: 36,
            height: 36,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
        ),
        error: (err, _) => _buildErrorState(context, ref, cs, tt, err),
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    ColorScheme cs,
    TextTheme tt,
    Object err,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.errorContainer.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.error_outline_rounded,
                  size: 48, color: cs.error),
            ),
            const SizedBox(height: 20),
            Text(S.of(context).loadFailed,
                style: tt.titleLarge?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text('$err',
                textAlign: TextAlign.center,
                style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => refreshListeningStats(ref),
              icon: const Icon(Icons.refresh_rounded),
              label: Text(S.of(context).retry),
            ),
          ],
        ),
      ),
    );
  }
}

class _StatsContent extends ConsumerStatefulWidget {
  final ListeningStats stats;

  const _StatsContent({required this.stats});

  @override
  ConsumerState<_StatsContent> createState() => _StatsContentState();
}

class _StatsContentState extends ConsumerState<_StatsContent>
    with TickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;
  late final TabController _chartTabCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
    _chartTabCtrl = TabController(length: 3, vsync: this);
  }

  @override
  void didUpdateWidget(covariant _StatsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.stats.totalWorksPlayed != widget.stats.totalWorksPlayed) {
      _animCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    _chartTabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final S l10n = S.of(context);

    if (widget.stats.totalWorksPlayed == 0) {
      return _EmptyStats();
    }

    return RefreshIndicator(
      onRefresh: () async => refreshListeningStats(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          FadeTransition(
            opacity: _fadeIn,
            child: _HeroHeader(stats: widget.stats),
          ),
          const SizedBox(height: 10),

          FadeTransition(
            opacity: _fadeIn,
            child: _OverviewGrid(stats: widget.stats),
          ),
          const SizedBox(height: 28),

          FadeTransition(
            opacity: _fadeIn,
            child: _SectionHeader(
              icon: Icons.bar_chart_rounded,
              title: l10n.statsDailyActivity,
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: _fadeIn,
            child: _ChartTabBar(tabCtrl: _chartTabCtrl),
          ),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: _fadeIn,
            child: SizedBox(
              height: 200,
              child: TabBarView(
                controller: _chartTabCtrl,
                children: [
                  _DailyActivityChart(activity: widget.stats.dailyActivity),
                  _WeeklyChart(weekly: widget.stats.weeklyStats),
                  _MonthlyChart(monthly: widget.stats.monthlyStats),
                ],
              ),
            ),
          ),
          const SizedBox(height: 28),

          FadeTransition(
            opacity: _fadeIn,
            child: _SectionHeader(
              icon: Icons.grid_on_rounded,
              title: l10n.statsHeatmap,
            ),
          ),
          const SizedBox(height: 4),
          FadeTransition(
            opacity: _fadeIn,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                l10n.statsHeatmapDesc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ),
          FadeTransition(
            opacity: _fadeIn,
            child: _ActivityHeatmap(activity: widget.stats.dailyActivity),
          ),
          const SizedBox(height: 28),

          if (widget.stats.milestones.isNotEmpty) ...[
            FadeTransition(
              opacity: _fadeIn,
              child: _SectionHeader(
                icon: Icons.emoji_events_rounded,
                title: l10n.statsMilestones,
              ),
            ),
            const SizedBox(height: 4),
            FadeTransition(
              opacity: _fadeIn,
              child: Text(
                l10n.statsMilestoneDesc,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(height: 10),
            FadeTransition(
              opacity: _fadeIn,
              child: _MilestonesSection(milestones: widget.stats.milestones),
            ),
            const SizedBox(height: 28),
          ],

          if (widget.stats.topVAs.isNotEmpty) ...[
            FadeTransition(
              opacity: _fadeIn,
              child: _SectionHeader(
                icon: Icons.mic_rounded,
                title: l10n.statsTopVAs,
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fadeIn,
              child: _TopListCard(
                items: widget.stats.topVAs
                    .map((va) => _RankedItem(
                          rank: widget.stats.topVAs.indexOf(va) + 1,
                          name: va.name,
                          count: va.playCount,
                          total: widget.stats.topVAs.first.playCount,
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 28),
          ],

          if (widget.stats.topCircles.isNotEmpty) ...[
            FadeTransition(
              opacity: _fadeIn,
              child: _SectionHeader(
                icon: Icons.group_rounded,
                title: l10n.statsTopCircles,
              ),
            ),
            const SizedBox(height: 8),
            FadeTransition(
              opacity: _fadeIn,
              child: _TopListCard(
                items: widget.stats.topCircles
                    .map((c) => _RankedItem(
                          rank: widget.stats.topCircles.indexOf(c) + 1,
                          name: c.name,
                          count: c.playCount,
                          total: widget.stats.topCircles.first.playCount,
                        ))
                    .toList(),
              ),
            ),
            const SizedBox(height: 28),
          ],

          FadeTransition(
            opacity: _fadeIn,
            child: _SectionHeader(
              icon: Icons.history_rounded,
              title: l10n.statsRecentPlays,
            ),
          ),
          const SizedBox(height: 8),
          FadeTransition(
            opacity: _fadeIn,
            child: _RecentPlaysGrid(records: widget.stats.recentPlays),
          ),
        ],
      ),
    );
  }
}

class _EmptyStats extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    cs.primaryContainer.withValues(alpha: 0.6),
                    cs.tertiaryContainer.withValues(alpha: 0.3),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bar_chart_rounded,
                  size: 52, color: cs.primary),
            ),
            const SizedBox(height: 28),
            Text(
              S.of(context).statsNoData,
              style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            Text(
              S.of(context).statsNoDataDesc,
              style: tt.bodyMedium?.copyWith(
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  final ListeningStats stats;

  const _HeroHeader({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final S l10n = S.of(context);
    final totalMinutes = stats.approximateListeningTime.inMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0
        ? '${l10n.nHours(hours)} ${l10n.nMinutes(mins)}'
        : l10n.nMinutes(mins);

    return Container(
      margin: const EdgeInsets.only(top: 4),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            cs.primaryContainer.withValues(alpha: 0.5),
            cs.surfaceContainerLow,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${stats.totalWorksPlayed}',
                  style: tt.displaySmall?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: cs.primary,
                    height: 1.0,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  S.of(context).statsWorksPlayed,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              _QuickChip(
                icon: Icons.check_circle_rounded,
                label: '${stats.completedWorks}',
                color: Colors.green,
              ),
              _QuickChip(
                icon: Icons.access_time_rounded,
                label: timeStr,
                color: cs.tertiary,
              ),
              _QuickChip(
                icon: Icons.local_fire_department_rounded,
                label: '${stats.currentStreakDays} ${l10n.statsDays}',
                color: Colors.deepOrange,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _QuickChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: color.withValues(alpha: 0.2),
          width: 0.5,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _OverviewGrid extends StatelessWidget {
  final ListeningStats stats;

  const _OverviewGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final S l10n = S.of(context);
    final totalMinutes = stats.approximateListeningTime.inMinutes;
    final hours = totalMinutes ~/ 60;
    final mins = totalMinutes % 60;
    final timeStr = hours > 0
        ? '${l10n.nHours(hours)} ${l10n.nMinutes(mins)}'
        : l10n.nMinutes(mins);

    return GridView(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 1.1,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      children: [
        _StatCard(
          icon: Icons.headphones_rounded,
          value: '${stats.totalWorksPlayed}',
          label: S.of(context).statsWorksPlayed,
          gradientColors: [cs.primary.withValues(alpha: 0.15), cs.primary.withValues(alpha: 0.05)],
          iconColor: cs.primary,
          valueColor: cs.primary,
        ),
        _StatCard(
          icon: Icons.check_circle_rounded,
          value: '${stats.completedWorks}',
          label: S.of(context).statsCompleted,
          suffix: '/ ${stats.totalWorksPlayed}',
          gradientColors: [
            Colors.green.withValues(alpha: 0.15),
            Colors.green.withValues(alpha: 0.05),
          ],
          iconColor: Colors.green,
          valueColor: Colors.green,
        ),
        _StatCard(
          icon: Icons.timer_rounded,
          value: timeStr,
          label: S.of(context).statsListeningTime,
          gradientColors: [cs.tertiary.withValues(alpha: 0.15), cs.tertiary.withValues(alpha: 0.05)],
          iconColor: cs.tertiary,
          valueColor: cs.tertiary,
        ),
        _StatCard(
          icon: Icons.local_fire_department_rounded,
          value: '${stats.currentStreakDays}',
          label: S.of(context).statsStreakDays,
          suffix: S.of(context).statsDays,
          gradientColors: [Colors.deepOrange.withValues(alpha: 0.15), Colors.orange.withValues(alpha: 0.05)],
          iconColor: Colors.deepOrange,
          valueColor: Colors.deepOrange,
        ),
      ],
    );
  }
}

/// Standard stat card with icon + big number.
class _StatCard extends StatelessWidget {
  final IconData icon;
  final String value;
  final String label;
  final String? suffix;
  final List<Color> gradientColors;
  final Color iconColor;
  final Color valueColor;

  const _StatCard({
    required this.icon,
    required this.value,
    required this.label,
    this.suffix,
    required this.gradientColors,
    required this.iconColor,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          gradient: LinearGradient(
            colors: gradientColors,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const Spacer(),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Text(
                    value,
                    style: tt.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: valueColor,
                      height: 1.0,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 3),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 3),
                    child: Text(
                      suffix!,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
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

class _ChartTabBar extends StatelessWidget {
  final TabController tabCtrl;

  const _ChartTabBar({required this.tabCtrl});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 36,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(10),
      ),
      child: TabBar(
        controller: tabCtrl,
        indicator: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        labelColor: cs.onPrimaryContainer,
        unselectedLabelColor: cs.onSurfaceVariant,
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
        unselectedLabelStyle: const TextStyle(fontSize: 13),
        dividerColor: Colors.transparent,
        tabs: [
          Tab(text: S.of(context).statsTabDaily),
          Tab(text: S.of(context).statsTabWeekly),
          Tab(text: S.of(context).statsTabMonthly),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  final List<WeeklyStats> weekly;

  const _WeeklyChart({required this.weekly});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (weekly.isEmpty) return const SizedBox.shrink();

    final maxCount = weekly.fold<int>(0, (m, w) => w.playCount > m ? w.playCount : m);
    const maxBarHeight = 80.0;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: SizedBox(
          height: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(children: [
                  Text('$maxCount',
                      style: tt.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  Expanded(child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3))),
                ]),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(weekly.length, (i) {
                    final w = weekly[i];
                    final barHeight = maxCount > 0
                        ? (w.playCount / maxCount) * maxBarHeight
                        : 0.0;
                    final isLatest = i == weekly.length - 1;

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (w.playCount > 0)
                              Text('${w.playCount}', style: tt.labelSmall?.copyWith(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Container(
                              height: barHeight.clamp(0.0, maxBarHeight),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                gradient: LinearGradient(
                                  colors: isLatest
                                      ? [cs.tertiary, cs.tertiary.withValues(alpha: 0.5)]
                                      : [cs.primary.withValues(alpha: 0.6), cs.primary.withValues(alpha: 0.25)],
                                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text('W${4 - i}', style: tt.labelSmall?.copyWith(fontSize: 8, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MonthlyChart extends StatelessWidget {
  final List<MonthlyStats> monthly;

  const _MonthlyChart({required this.monthly});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (monthly.isEmpty) return const SizedBox.shrink();

    final maxCount = monthly.fold<int>(0, (m, m2) => m2.playCount > m ? m2.playCount : m);
    const maxBarHeight = 80.0;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 12),
        child: SizedBox(
          height: 150,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(children: [
                  Text('$maxCount', style: tt.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant)),
                  const SizedBox(width: 4),
                  Expanded(child: Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3))),
                ]),
              ),
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: List.generate(monthly.length, (i) {
                    final m = monthly[i];
                    final barHeight = maxCount > 0
                        ? (m.playCount / maxCount) * maxBarHeight
                        : 0.0;
                    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

                    return Expanded(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 3),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (m.playCount > 0)
                              Text('${m.playCount}', style: tt.labelSmall?.copyWith(fontSize: 8, fontWeight: FontWeight.w600, color: cs.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Container(
                              height: barHeight.clamp(0.0, maxBarHeight),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
                                gradient: LinearGradient(
                                  colors: [
                                    Colors.green.withValues(alpha: 0.6),
                                    Colors.teal.withValues(alpha: 0.3),
                                  ],
                                  begin: Alignment.bottomCenter, end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(months[m.month - 1], style: tt.labelSmall?.copyWith(fontSize: 8, color: cs.onSurfaceVariant)),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityHeatmap extends StatelessWidget {
  final List<DailyActivity> activity;

  const _ActivityHeatmap({required this.activity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (activity.isEmpty) return const SizedBox.shrink();

    final dayData = <DateTime, int>{};
    for (final a in activity) {
      final d = DateTime(a.date.year, a.date.month, a.date.day);
      dayData[d] = a.playCount;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final cells = <int>[];
    for (int dayOffset = 13; dayOffset >= 0; dayOffset--) {
      final d = today.subtract(Duration(days: dayOffset));
      cells.add(dayData[d] ?? 0);
    }

    final maxVal = cells.fold<int>(0, (m, v) => v > m ? v : m);

    Color cellColor(int count) {
      if (count == 0) return cs.surfaceContainerHighest.withValues(alpha: 0.4);
      final intensity = count / (maxVal > 0 ? maxVal : 1);
      return Color.lerp(
        cs.primary.withValues(alpha: 0.2),
        cs.primary,
        intensity.clamp(0.0, 1.0),
      )!;
    }

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final cellSize = (constraints.maxWidth - 12) / 14;
                return Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: List.generate(14, (i) {
                    final count = cells[i];
                    return Tooltip(
                      message: '$count plays',
                      child: Container(
                        width: cellSize.clamp(8.0, 20.0),
                        height: cellSize.clamp(8.0, 20.0),
                        decoration: BoxDecoration(
                          color: cellColor(count),
                          borderRadius: BorderRadius.circular(3),
                        ),
                      ),
                    );
                  }),
                );
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Text('Less', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant)),
                const SizedBox(width: 4),
                ...[0, 1, 2, 3].map((level) => Container(
                  width: 10,
                  height: 10,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: cellColor(level * (maxVal ~/ 4)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(width: 4),
                Text('More', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant)),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Maps milestone [iconId] to Material [IconData].
IconData _milestoneIcon(String id) {
  switch (id) {
    case 'play_circle': return Icons.play_circle_rounded;
    case 'library_music': return Icons.library_music_rounded;
    case 'headphones': return Icons.headphones_rounded;
    case 'emoji_events': return Icons.emoji_events_rounded;
    case 'check_circle': return Icons.check_circle_rounded;
    case 'timer': return Icons.timer_rounded;
    case 'schedule': return Icons.schedule_rounded;
    case 'star': return Icons.star_rounded;
    case 'local_fire_department': return Icons.local_fire_department_rounded;
    case 'whatshot': return Icons.whatshot_rounded;
    default: return Icons.flag_rounded;
  }
}

/// Localized milestone title from [id].
String _milestoneTitle(BuildContext context, String id) {
  final s = S.of(context);
  switch (id) {
    case 'first_work': return s.statsMilestoneFirstSteps;
    case 'ten_works': return s.statsMilestoneGettingStarted;
    case 'fifty_works': return s.statsMilestoneListener;
    case 'hundred_works': return s.statsMilestoneCentury;
    case 'first_complete': return s.statsMilestoneComplete;
    case 'ten_hours': return s.statsMilestoneDoubleDigits;
    case 'fifty_hours': return s.statsMilestoneLongHaul;
    case 'hundred_hours': return s.statsMilestoneHundredHours;
    case 'week_streak_7': return s.statsMilestoneConsistent;
    case 'week_streak_30': return s.statsMilestoneUnstoppable;
    default: return id;
  }
}

/// Localized milestone description from [id].
String _milestoneDesc(BuildContext context, String id) {
  final s = S.of(context);
  switch (id) {
    case 'first_work': return s.statsMilestoneFirstStepsDesc;
    case 'ten_works': return s.statsMilestoneGettingStartedDesc;
    case 'fifty_works': return s.statsMilestoneListenerDesc;
    case 'hundred_works': return s.statsMilestoneCenturyDesc;
    case 'first_complete': return s.statsMilestoneCompleteDesc;
    case 'ten_hours': return s.statsMilestoneDoubleDigitsDesc;
    case 'fifty_hours': return s.statsMilestoneLongHaulDesc;
    case 'hundred_hours': return s.statsMilestoneHundredHoursDesc;
    case 'week_streak_7': return s.statsMilestoneConsistentDesc;
    case 'week_streak_30': return s.statsMilestoneUnstoppableDesc;
    default: return id;
  }
}

class _MilestonesSection extends StatelessWidget {
  final List<Milestone> milestones;

  const _MilestonesSection({required this.milestones});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: List.generate(milestones.length, (i) {
            final m = milestones[i];
            return _MilestoneCard(
              index: i,
              totalCount: milestones.length,
              milestone: m,
            );
          }),
        ),
      ),
    );
  }
}

class _MilestoneCard extends StatelessWidget {
  final int index;
  final int totalCount;
  final Milestone milestone;

  const _MilestoneCard({
    required this.index,
    required this.totalCount,
    required this.milestone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final icon = _milestoneIcon(milestone.iconId);
    final title = _milestoneTitle(context, milestone.id);
    final desc = _milestoneDesc(context, milestone.id);
    final achieved = milestone.achieved;
    final progress = milestone.progress.clamp(0.0, 1.0);

    return Padding(
      padding: EdgeInsets.only(top: index > 0 ? 6 : 0, bottom: index < totalCount - 1 ? 6 : 0),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: achieved
                  ? Colors.amber.withValues(alpha: 0.2)
                  : cs.surfaceContainerHighest,
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              size: 20,
              color: achieved ? Colors.amber.shade700 : cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: tt.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: achieved ? Colors.amber.shade700 : cs.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  desc,
                  style: tt.bodySmall?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          if (achieved)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 18, color: Colors.green.shade600),
                const SizedBox(width: 4),
                Text(S.of(context).statsCompleted,
                  style: tt.labelSmall?.copyWith(
                    fontSize: 10,
                    color: Colors.green.shade600,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: 56,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 4,
                      backgroundColor: cs.surfaceContainerHighest,
                      valueColor: AlwaysStoppedAnimation<Color>(cs.primary),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${(progress * 100).round()}%',
                    style: tt.labelSmall?.copyWith(fontSize: 9, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;

  const _SectionHeader({
    required this.icon,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(6),
          decoration: BoxDecoration(
            color: cs.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: cs.primary),
        ),
        const SizedBox(width: 10),
        Text(title, style: tt.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
      ],
    );
  }
}

class _DailyActivityChart extends StatelessWidget {
  final List<DailyActivity> activity;

  const _DailyActivityChart({required this.activity});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final maxCount = activity.fold<int>(0, (m, a) => a.playCount > m ? a.playCount : m);
    const maxBarHeight = 100.0;

    return Card(
      elevation: 0,
      color: cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 20, 12, 14),
        child: SizedBox(
          height: 170,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 6),
                child: Row(
                  children: [
                    Text('$maxCount',
                        style: tt.labelSmall?.copyWith(
                            fontSize: 9, color: cs.onSurfaceVariant)),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Divider(
                          height: 1,
                          color: cs.outlineVariant.withValues(alpha: 0.3)),
                    ),
                  ],
                ),
              ),
              Expanded(
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
                        padding: const EdgeInsets.symmetric(horizontal: 1.5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            if (day.playCount > 0)
                              Text(
                                '${day.playCount}',
                                style: tt.labelSmall?.copyWith(
                                  fontSize: 8,
                                  fontWeight: FontWeight.w600,
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                            const SizedBox(height: 2),
                            Container(
                              height: barHeight.clamp(0.0, maxBarHeight),
                              decoration: BoxDecoration(
                                borderRadius: const BorderRadius.vertical(
                                  top: Radius.circular(3),
                                ),
                                gradient: LinearGradient(
                                  colors: isToday
                                      ? [
                                          cs.primary,
                                          cs.primary.withValues(alpha: 0.6),
                                        ]
                                      : [
                                          cs.primary.withValues(alpha: 0.5),
                                          cs.primary.withValues(alpha: 0.2),
                                        ],
                                  begin: Alignment.bottomCenter,
                                  end: Alignment.topCenter,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              dayLabel,
                              style: tt.labelSmall?.copyWith(
                                fontSize: 8,
                                color: cs.onSurfaceVariant,
                                fontWeight:
                                    isToday ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _dayLabel(DateTime date) {
    const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return weekdays[date.weekday - 1];
  }
}

/// Data class for a ranked item in the top lists.
class _RankedItem {
  final int rank;
  final String name;
  final int count;
  final int total;

  const _RankedItem({
    required this.rank,
    required this.name,
    required this.count,
    required this.total,
  });
}

/// Reusable card for top VAs and top circles with mini progress bars.
class _TopListCard extends StatelessWidget {
  final List<_RankedItem> items;

  const _TopListCard({required this.items});

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
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
        child: Column(
          children: List.generate(items.length, (i) {
            final item = items[i];
            final isTop3 = item.rank <= 3;
            final rankColors = [
              Colors.amber,
              Colors.grey.shade400,
              Colors.brown.shade300,
            ];
            final rankColor = isTop3 ? rankColors[item.rank - 1] : null;

            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  SizedBox(
                    width: 28,
                    child: Center(
                      child: isTop3
                          ? Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: rankColor!.withValues(alpha: 0.2),
                                shape: BoxShape.circle,
                              ),
                              child: Center(
                                child: Text(
                                  '${item.rank}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 11,
                                    color: rankColor,
                                  ),
                                ),
                              ),
                            )
                          : Text(
                              '${item.rank}',
                              style: TextStyle(
                                fontSize: 11,
                                color: cs.onSurfaceVariant,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 60,
                    height: 6,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Stack(
                        children: [
                          Container(
                            color: cs.surfaceContainerHighest,
                          ),
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor:
                                item.total > 0 ? item.count / item.total : 0.0,
                            child: Container(
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                gradient: LinearGradient(
                                  colors: [
                                    cs.primary.withValues(alpha: 0.7),
                                    cs.primary,
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 36,
                    child: Text(
                      '${item.count}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: cs.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              ),
            );
          }),
        ),
      ),
    );
  }
}

class _RecentPlaysGrid extends StatelessWidget {
  final List<HistoryRecord> records;

  const _RecentPlaysGrid({required this.records});

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surfaceContainerLow,
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