import 'dart:async';

import '../models/history_record.dart';
import 'history_database.dart';
import 'playback_history_service.dart';

/// A personal milestone achieved by the user.
class Milestone {
  final String id;
  final String title;
  final String description;
  final bool achieved;
  final double progress;
  final String iconId;

  const Milestone({
    required this.id,
    required this.title,
    required this.description,
    required this.achieved,
    required this.progress,
    required this.iconId,
  });
}

/// Statistics computed from playback history.
class ListeningStats {
  /// Total unique works ever played.
  final int totalWorksPlayed;

  /// Works likely completed (position >= 70% of duration or duration not available).
  final int completedWorks;

  /// Works partially played.
  final int inProgressWorks;

  /// Approximate total listening time (sum of totalListenedMs across records,
  /// falling back to lastPositionMs for pre-migration records).
  final Duration approximateListeningTime;

  /// Current listening streak in days.
  final int currentStreakDays;

  /// Longest streak ever recorded.
  final int longestStreakDays;

  /// Daily play count for the last 14 days (most recent first).
  final List<DailyActivity> dailyActivity;

  /// Weekly stats for the last 4 weeks.
  final List<WeeklyStats> weeklyStats;

  /// Monthly stats for the last 6 months.
  final List<MonthlyStats> monthlyStats;

  /// Top voice actors by play count.
  final List<VaStat> topVAs;

  /// Top circles by play count.
  final List<CircleStat> topCircles;

  /// Most recently played works.
  final List<HistoryRecord> recentPlays;

  /// Personal milestones achieved or in progress.
  final List<Milestone> milestones;

  const ListeningStats({
    required this.totalWorksPlayed,
    required this.completedWorks,
    required this.inProgressWorks,
    required this.approximateListeningTime,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.dailyActivity,
    required this.weeklyStats,
    required this.monthlyStats,
    required this.topVAs,
    required this.topCircles,
    required this.recentPlays,
    required this.milestones,
  });

  /// Empty stats when no history exists.
  static const empty = ListeningStats(
    totalWorksPlayed: 0,
    completedWorks: 0,
    inProgressWorks: 0,
    approximateListeningTime: Duration.zero,
    currentStreakDays: 0,
    longestStreakDays: 0,
    dailyActivity: [],
    weeklyStats: [],
    monthlyStats: [],
    topVAs: [],
    topCircles: [],
    recentPlays: [],
    milestones: [],
  );
}

/// Daily play activity.
class DailyActivity {
  final DateTime date;
  final int playCount;

  const DailyActivity({required this.date, required this.playCount});
}

/// Weekly play stats.
class WeeklyStats {
  final DateTime startDate;
  final int playCount;
  final double listeningHours;

  const WeeklyStats({
    required this.startDate,
    required this.playCount,
    required this.listeningHours,
  });
}

/// Monthly play stats.
class MonthlyStats {
  final int year;
  final int month;
  final int playCount;
  final double listeningHours;

  const MonthlyStats({
    required this.year,
    required this.month,
    required this.playCount,
    required this.listeningHours,
  });
}

/// Voice actor play statistics.
class VaStat {
  final String name;
  final int playCount;

  const VaStat({required this.name, required this.playCount});
}

/// Circle play statistics.
class CircleStat {
  final String name;
  final int playCount;

  const CircleStat({required this.name, required this.playCount});
}

/// Service that reads playback history and computes listening statistics.
class ListeningStatsService {
  static final ListeningStatsService instance = ListeningStatsService._();
  ListeningStatsService._();

  ListeningStats? _cached;
  DateTime? _lastFetch;
  StreamSubscription? _historySub;
  bool _initialized = false;

  /// Start listening to [PlaybackHistoryService.historyUpdatedStream] so the
  /// cache is automatically invalidated whenever a new history record is written.
  /// Throttled: cache is only cleared if the last computation was at least 15
  /// seconds ago, preventing recomputation on every 5-second checkpoint tick
  /// during active playback.
  /// Safe to call multiple times.
  void subscribeToHistoryUpdates() {
    if (_initialized) return;
    _initialized = true;
    _historySub = PlaybackHistoryService.instance.historyUpdatedStream.listen((_) {
      if (_lastFetch == null ||
          DateTime.now().difference(_lastFetch!).inSeconds >= 15) {
        _cached = null;
        _lastFetch = null;
      }
    });
  }

  /// Stop listening to history updates.
  void unsubscribeFromHistoryUpdates() {
    _historySub?.cancel();
    _historySub = null;
    _initialized = false;
  }

  /// Compute statistics from history database.
  /// Results are cached for 30 seconds to avoid recomputation.
  Future<ListeningStats> compute({
    bool forceRefresh = false,
  }) async {
    if (!forceRefresh &&
        _cached != null &&
        _lastFetch != null &&
        DateTime.now().difference(_lastFetch!).inSeconds < 30) {
      return _cached!;
    }

    final allRecords = await HistoryDatabase.instance.getAllHistory();
    if (allRecords.isEmpty) {
      _cached = ListeningStats.empty;
      _lastFetch = DateTime.now();
      return _cached!;
    }

    final totalWorks = allRecords.length;
    int completed = 0;
    int inProgress = 0;
    int totalPositionMs = 0;

    for (final record in allRecords) {
      totalPositionMs +=
          record.totalListenedMs > 0 ? record.totalListenedMs : record.lastPositionMs;

      final dur = record.work.duration ?? 0;
      if (dur > 0 && record.lastPositionMs >= dur * 0.7) {
        completed++;
      } else if (record.lastPositionMs > 0) {
        inProgress++;
      }
    }

    final approximateTime = Duration(milliseconds: totalPositionMs);

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dayCounts = <int, int>{};
    for (final record in allRecords) {
      final day = DateTime(
        record.lastPlayedTime.year,
        record.lastPlayedTime.month,
        record.lastPlayedTime.day,
      );
      final dayKey = day.millisecondsSinceEpoch;
      dayCounts[dayKey] = (dayCounts[dayKey] ?? 0) + 1;
    }

    final dailyActivity = <DailyActivity>[];
    for (int i = 13; i >= 0; i--) {
      final day = today.subtract(Duration(days: i));
      final dayKey = day.millisecondsSinceEpoch;
      dailyActivity.add(DailyActivity(
        date: day,
        playCount: dayCounts[dayKey] ?? 0,
      ));
    }

    final uniqueDays = dayCounts.keys
        .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms))
        .toList()
      ..sort((a, b) => b.compareTo(a));

    int currentStreak = 0;
    if (uniqueDays.isNotEmpty) {
      final mostRecent = uniqueDays.first;
      if (mostRecent.isAfter(today.subtract(const Duration(days: 2)))) {
        currentStreak = 1;
        for (int i = 1; i < uniqueDays.length; i++) {
          final expectedPrev =
              uniqueDays[i - 1].subtract(const Duration(days: 1));
          if (uniqueDays[i].isAtSameMomentAs(expectedPrev) ||
              uniqueDays[i].isAfter(expectedPrev.subtract(const Duration(hours: 12)))) {
            currentStreak++;
          } else {
            break;
          }
        }
      }
    }

    int longestStreak = 0;
    if (uniqueDays.length >= 2) {
      int run = 1;
      for (int i = 1; i < uniqueDays.length; i++) {
        final diff = uniqueDays[i - 1].difference(uniqueDays[i]).inDays;
        if (diff <= 1) {
          run++;
          if (run > longestStreak) longestStreak = run;
        } else {
          run = 1;
        }
      }
    } else if (uniqueDays.length == 1) {
      longestStreak = 1;
    }

    final vaCounts = <String, int>{};
    for (final record in allRecords) {
      final vas = record.work.vas;
      if (vas != null) {
        for (final va in vas) {
          vaCounts[va.name] = (vaCounts[va.name] ?? 0) + 1;
        }
      }
    }
    final sortedVAs = vaCounts.entries
        .map((e) => VaStat(name: e.key, playCount: e.value))
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final topVAs = sortedVAs.take(8).toList();

    final circleCounts = <String, int>{};
    for (final record in allRecords) {
      final circleName = record.work.circleTitle;
      if (circleName.isNotEmpty) {
        circleCounts[circleName] = (circleCounts[circleName] ?? 0) + 1;
      }
    }
    final sortedCircles = circleCounts.entries
        .map((e) => CircleStat(name: e.key, playCount: e.value))
        .toList()
      ..sort((a, b) => b.playCount.compareTo(a.playCount));
    final topCircles = sortedCircles.take(5).toList();

    final weeklyStats = <WeeklyStats>[];
    for (int w = 3; w >= 0; w--) {
      final weekStart = today.subtract(Duration(days: today.weekday - 1 + w * 7));
      final weekEnd = weekStart.add(const Duration(days: 7));
      int weekPlayCount = 0;
      double weekHours = 0.0;
      for (final record in allRecords) {
        if (record.lastPlayedTime.isAfter(weekStart.subtract(const Duration(hours: 1))) &&
            record.lastPlayedTime.isBefore(weekEnd)) {
          weekPlayCount++;
          final weekTimeMs =
              record.totalListenedMs > 0 ? record.totalListenedMs : record.lastPositionMs;
          weekHours += weekTimeMs / 3600000.0;
        }
      }
      weeklyStats.add(WeeklyStats(
        startDate: weekStart,
        playCount: weekPlayCount,
        listeningHours: double.parse(weekHours.toStringAsFixed(1)),
      ));
    }

    final monthlyStats = <MonthlyStats>[];
    for (int m = 5; m >= 0; m--) {
      final monthDate = DateTime(today.year, today.month - m, 1);
      int monthPlayCount = 0;
      double monthHours = 0.0;
      for (final record in allRecords) {
        if (record.lastPlayedTime.year == monthDate.year &&
            record.lastPlayedTime.month == monthDate.month) {
          monthPlayCount++;
          final monthTimeMs =
              record.totalListenedMs > 0 ? record.totalListenedMs : record.lastPositionMs;
          monthHours += monthTimeMs / 3600000.0;
        }
      }
      monthlyStats.add(MonthlyStats(
        year: monthDate.year,
        month: monthDate.month,
        playCount: monthPlayCount,
        listeningHours: double.parse(monthHours.toStringAsFixed(1)),
      ));
    }

    final totalHours = approximateTime.inMinutes / 60.0;
    final milestones = <Milestone>[
      Milestone(
        id: 'first_work',
        title: 'First Steps',
        description: 'Play your first work',
        achieved: totalWorks > 0,
        progress: totalWorks > 0 ? 1.0 : 0.0,
        iconId: 'play_circle',
      ),
      Milestone(
        id: 'ten_works',
        title: 'Getting Started',
        description: 'Play 10 different works',
        achieved: totalWorks >= 10,
        progress: (totalWorks / 10).clamp(0.0, 1.0),
        iconId: 'library_music',
      ),
      Milestone(
        id: 'fifty_works',
        title: 'Dedicated Listener',
        description: 'Play 50 different works',
        achieved: totalWorks >= 50,
        progress: (totalWorks / 50).clamp(0.0, 1.0),
        iconId: 'headphones',
      ),
      Milestone(
        id: 'hundred_works',
        title: 'Century Mark',
        description: 'Play 100 different works',
        achieved: totalWorks >= 100,
        progress: (totalWorks / 100).clamp(0.0, 1.0),
        iconId: 'emoji_events',
      ),
      Milestone(
        id: 'first_complete',
        title: 'Complete!',
        description: 'Finish your first work',
        achieved: completed > 0,
        progress: completed > 0 ? 1.0 : 0.0,
        iconId: 'check_circle',
      ),
      Milestone(
        id: 'ten_hours',
        title: 'Double Digits',
        description: 'Listen for 10 hours total',
        achieved: totalHours >= 10,
        progress: (totalHours / 10).clamp(0.0, 1.0),
        iconId: 'timer',
      ),
      Milestone(
        id: 'fifty_hours',
        title: 'Long Haul',
        description: 'Listen for 50 hours total',
        achieved: totalHours >= 50,
        progress: (totalHours / 50).clamp(0.0, 1.0),
        iconId: 'schedule',
      ),
      Milestone(
        id: 'hundred_hours',
        title: '100 Hours Club',
        description: 'Listen for 100 hours total',
        achieved: totalHours >= 100,
        progress: (totalHours / 100).clamp(0.0, 1.0),
        iconId: 'star',
      ),
      Milestone(
        id: 'week_streak_7',
        title: 'Consistent',
        description: 'Reach a 7-day streak',
        achieved: longestStreak >= 7,
        progress: (longestStreak / 7).clamp(0.0, 1.0),
        iconId: 'local_fire_department',
      ),
      Milestone(
        id: 'week_streak_30',
        title: 'Unstoppable',
        description: 'Reach a 30-day streak',
        achieved: longestStreak >= 30,
        progress: (longestStreak / 30).clamp(0.0, 1.0),
        iconId: 'whatshot',
      ),
    ];

    final sortedByTime = List<HistoryRecord>.from(allRecords)
      ..sort((a, b) => b.lastPlayedTime.compareTo(a.lastPlayedTime));
    final recentPlays = sortedByTime.take(10).toList();

    _cached = ListeningStats(
      totalWorksPlayed: totalWorks,
      completedWorks: completed,
      inProgressWorks: inProgress,
      approximateListeningTime: approximateTime,
      currentStreakDays: currentStreak,
      longestStreakDays: longestStreak,
      dailyActivity: dailyActivity,
      weeklyStats: weeklyStats,
      monthlyStats: monthlyStats,
      topVAs: topVAs,
      topCircles: topCircles,
      recentPlays: recentPlays,
      milestones: milestones,
    );
    _lastFetch = DateTime.now();
    return _cached!;
  }
}