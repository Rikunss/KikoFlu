import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/listening_stats_service.dart';
import '../services/playback_history_service.dart';

/// Provider that computes and caches listening statistics.
/// Auto-recomputes whenever playback history is updated.
final listeningStatsProvider = FutureProvider<ListeningStats>((ref) async {
  // Watch for history updates to trigger recomputation
  ref.watch(_historyUpdateTriggerProvider);

  return ListeningStatsService.instance.compute();
});

/// Hidden provider that fires whenever playback history changes.
final _historyUpdateTriggerProvider = StreamProvider<int?>((ref) {
  ref.onDispose(() {});
  return PlaybackHistoryService.instance.historyUpdatedStream;
});

/// Force-refresh listening stats.
void refreshListeningStats(WidgetRef ref) {
  ListeningStatsService.instance.compute(forceRefresh: true);
  ref.invalidate(listeningStatsProvider);
}
