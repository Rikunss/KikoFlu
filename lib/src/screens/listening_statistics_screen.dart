import 'dart:math' show pi;
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

// ═══════════════════════════════════════════════════════════════
// Main Content
// ═══════════════════════════════════════════════════════════════

class _StatsContent extends ConsumerStatefulWidget {
  final ListeningStats stats;

  const _StatsContent({required this.stats});

  @override
  ConsumerState<_StatsContent> createState() => _StatsContentState();
}

class _StatsContentState extends ConsumerState<_StatsContent>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  late final Animation<double> _fadeIn;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _fadeIn = CurvedAnimation(parent: _animCtrl, curve: Curves.easeOutCubic);
    _animCtrl.forward();
  }

  @override
  void didUpdateWidget(covariant _StatsContent oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Re-trigger animation when stats change
    if (oldWidget.stats.totalWorksPlayed != widget.stats.totalWorksPlayed) {
      _animCtrl.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.stats.totalWorksPlayed == 0) {
      return _EmptyStats();
    }

    return RefreshIndicator(
      onRefresh: () async => refreshListeningStats(ref),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          // ── Hero Header ──
          FadeTransition(
            opacity: _fadeIn,
            child: _HeroHeader(stats: widget.stats),
          ),
          const SizedBox(height: 10),

          // ── Overview Stats Grid ──
          FadeTransition(
            opacity: _fadeIn,
            child: _OverviewGrid(stats: widget.stats),
          ),
          const SizedBox(height: 28),

          // ── Daily Activity ──
          FadeTransition(
            opacity: _fadeIn,
            child: _SectionHeader(
              icon: Icons.bar_chart_rounded,
              title: S.of(context).statsDailyActivity,

            ),
          ),
          const SizedBox(height: 12),
          FadeTransition(
            opacity: _fadeIn,
            child: _DailyActivityChart(activity: widget.stats.dailyActivity),
          ),
          const SizedBox(height: 28),

          // ── Top VAs ──
          if (widget.stats.topVAs.isNotEmpty) ...[
            FadeTransition(
              opacity: _fadeIn,
              child: _SectionHeader(
                icon: Icons.mic_rounded,
                title: S.of(context).statsTopVAs,
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

          // ── Top Circles ──
          if (widget.stats.topCircles.isNotEmpty) ...[
            FadeTransition(
              opacity: _fadeIn,
              child: _SectionHeader(
                icon: Icons.group_rounded,
                title: S.of(context).statsTopCircles,
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

          // ── Recent Plays ──
          FadeTransition(
            opacity: _fadeIn,
            child: _SectionHeader(
              icon: Icons.history_rounded,
              title: S.of(context).statsRecentPlays,
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

// ═══════════════════════════════════════════════════════════════
// Empty State
// ═══════════════════════════════════════════════════════════════

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
            // Decorative illustration
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

// ═══════════════════════════════════════════════════════════════
// Hero Header
// ═══════════════════════════════════════════════════════════════

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
          // Total works — big number
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
          // Quick stats chips
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

// ═══════════════════════════════════════════════════════════════
// Overview Grid
// ═══════════════════════════════════════════════════════════════

class _OverviewGrid extends StatelessWidget {
  final ListeningStats stats;

  const _OverviewGrid({required this.stats});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final completionRate = stats.totalWorksPlayed > 0
        ? (stats.completedWorks / stats.totalWorksPlayed)
        : 0.0;

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
        _CompletionRingCard(
          rate: completionRate,
          label: S.of(context).statsCompleted,
          completed: stats.completedWorks,
          total: stats.totalWorksPlayed,
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
            // Icon with subtle background
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: iconColor),
            ),
            const Spacer(),
            // Value row
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

/// Circular completion ring card.
class _CompletionRingCard extends StatelessWidget {
  final double rate;
  final String label;
  final int completed;
  final int total;

  const _CompletionRingCard({
    required this.rate,
    required this.label,
    required this.completed,
    required this.total,
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
            colors: [
              Colors.green.withValues(alpha: 0.12),
              Colors.green.withValues(alpha: 0.03),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            const Spacer(),
            // Circular progress
            SizedBox(
              width: 56,
              height: 56,
              child: CustomPaint(
                painter: _RingPainter(
                  progress: rate,
                  color: Colors.green,
                  backgroundColor: cs.surfaceContainerHighest,
                ),
                child: Center(
                  child: Text(
                    '${(rate * 100).round()}%',
                    style: tt.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade700,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: tt.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// Custom painter for the completion ring.
class _RingPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;

  _RingPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - 8) / 2;
    const strokeWidth = 5.0;

    // Background ring
    final bgPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, bgPaint);

    // Progress arc
    final progressPaint = Paint()
      ..shader = LinearGradient(
        colors: [color, color.withValues(alpha: 0.6)],
      ).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -pi / 2, // Start from top
      progress * 2 * pi,
      false,
      progressPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress;
}

// ═══════════════════════════════════════════════════════════════
// Section Header
// ═══════════════════════════════════════════════════════════════

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

// ═══════════════════════════════════════════════════════════════
// Daily Activity Chart
// ═══════════════════════════════════════════════════════════════

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
              // Y-axis legend row
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
              // Bars
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
                            // Count label above bar
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
                            // Gradient bar
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
                            // Day label
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

// ═══════════════════════════════════════════════════════════════
// Top Lists (VAs / Circles)
// ═══════════════════════════════════════════════════════════════

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
                  // Rank badge
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
                  // Name
                  Expanded(
                    child: Text(
                      item.name,
                      style: const TextStyle(fontSize: 13),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Mini progress bar
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
                  // Count
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

// ═══════════════════════════════════════════════════════════════
// Recent Plays Grid
// ═══════════════════════════════════════════════════════════════

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
