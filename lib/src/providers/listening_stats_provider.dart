import 'dart:async';

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
/// Debounced to avoid constant UI rebuilds during playback (checkpoint every 5s).
final _historyUpdateTriggerProvider = StreamProvider<int?>((ref) {
  ref.onDispose(() {});
  return PlaybackHistoryService.instance.historyUpdatedStream
      .transform(_Debouncer<int?>(const Duration(seconds: 5)));
});

/// Force-refresh listening stats.
void refreshListeningStats(WidgetRef ref) {
  ListeningStatsService.instance.compute(forceRefresh: true);
  ref.invalidate(listeningStatsProvider);
}

/// Simple stream debouncer: only emits the last event after [duration]
/// of inactivity.
class _Debouncer<T> extends StreamTransformerBase<T, T> {
  final Duration duration;
  const _Debouncer(this.duration);

  @override
  Stream<T> bind(Stream<T> stream) {
    Timer? timer;
    T? lastValue;
    return stream.transform(
      StreamTransformer<T, T>.fromHandlers(
        handleData: (data, sink) {
          lastValue = data;
          timer?.cancel();
          timer = Timer(duration, () {
            sink.add(lastValue as T);
          });
        },
        handleDone: (sink) {
          timer?.cancel();
          if (lastValue != null) {
            sink.add(lastValue as T);
          }
          sink.close();
        },
      ),
    );
  }
}
