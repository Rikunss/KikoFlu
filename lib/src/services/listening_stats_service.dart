import '../models/history_record.dart';
import 'history_database.dart';

/// Statistics computed from playback history.
class ListeningStats {
  /// Total unique works ever played.
  final int totalWorksPlayed;

  /// Works likely completed (position >= 70% of duration or duration not available).
  final int completedWorks;

  /// Works partially played.
  final int inProgressWorks;

  /// Approximate total listening time (sum of lastPositionMs across records).
  final Duration approximateListeningTime;

  /// Current listening streak in days.
  final int currentStreakDays;

  /// Longest streak ever recorded.
  final int longestStreakDays;

  /// Daily play count for the last 14 days (most recent first).
  final List<DailyActivity> dailyActivity;

  /// Top voice actors by play count.
  final List<VaStat> topVAs;

  /// Top circles by play count.
  final List<CircleStat> topCircles;

  /// Most recently played works.
  final List<HistoryRecord> recentPlays;

  const ListeningStats({
    required this.totalWorksPlayed,
    required this.completedWorks,
    required this.inProgressWorks,
    required this.approximateListeningTime,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.dailyActivity,
    required this.topVAs,
    required this.topCircles,
    required this.recentPlays,
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
    topVAs: [],
    topCircles: [],
    recentPlays: [],
  );
}

/// Daily play activity.
class DailyActivity {
  final DateTime date;
  final int playCount;

  const DailyActivity({required this.date, required this.playCount});
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

    // ── Basic counts ──
    final totalWorks = allRecords.length;
    int completed = 0;
    int inProgress = 0;
    int totalPositionMs = 0;

    for (final record in allRecords) {
      totalPositionMs += record.lastPositionMs;

      final dur = record.work.duration ?? 0;
      if (dur > 0 && record.lastPositionMs >= dur * 0.7) {
        completed++;
      } else if (record.lastPositionMs > 0) {
        inProgress++;
      }
    }

    final approximateTime = Duration(milliseconds: totalPositionMs);

    // ── Daily activity (last 14 days) ──
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

    // ── Streak calculation ──
    final uniqueDays = dayCounts.keys
        .map((ms) => DateTime.fromMillisecondsSinceEpoch(ms))
        .toList()
      ..sort((a, b) => b.compareTo(a)); // most recent first

    int currentStreak = 0;
    if (uniqueDays.isNotEmpty) {
      final mostRecent = uniqueDays.first;
      if (mostRecent.isAfter(today.subtract(const Duration(days: 2)))) {
        // Check if the streak includes today or yesterday
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

    // Longest streak
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

    // ── Top VAs ──
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

    // ── Top Circles ──
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

    // ── Recent plays ──
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
      topVAs: topVAs,
      topCircles: topCircles,
      recentPlays: recentPlays,
    );
    _lastFetch = DateTime.now();
    return _cached!;
  }
}
