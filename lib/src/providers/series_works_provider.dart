import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart';

/// State for works in the same circle/series as a given work.
class SeriesWorksState {
  final List<Work> works;
  final bool isLoading;
  final String? error;

  const SeriesWorksState({
    this.works = const [],
    this.isLoading = false,
    this.error,
  });

  SeriesWorksState copyWith({
    List<Work>? works,
    bool? isLoading,
    String? error,
  }) {
    return SeriesWorksState(
      works: works ?? this.works,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

class SeriesWorksNotifier extends StateNotifier<SeriesWorksState> {
  final Ref ref;
  final int workId;

  SeriesWorksNotifier(this.ref, this.workId)
      : super(const SeriesWorksState());

  /// Load works from the same circle as [work].
  /// Searches by circle name, then filters out the current work.
  Future<void> loadCircleWorks(Work work) async {
    final circleName = work.name; // circleTitle getter returns name ?? ''
    if (circleName == null || circleName.isEmpty || work.circleId == null) {
      state = const SeriesWorksState();
      return;
    }

    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);

      // Search by circle name to find works from the same circle
      final data = await apiService.searchWorks(
        keyword: '\$circle:$circleName\$',
        page: 1,
        pageSize: 20,
        order: 'rate_average_2dp',
        sort: 'desc',
      );

      final worksList = data['works'] as List? ?? [];
      final allWorks = worksList.map((json) => Work.fromJson(json)).toList();

      // Filter out the current work and limit to reasonable count
      final filtered = allWorks
          .where((w) => w.id != work.id)
          .take(12)
          .toList();

      state = SeriesWorksState(works: filtered);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }
}

/// Provider keyed by workId — fetches works from the same circle.
final seriesWorksProvider = StateNotifierProvider.family<
    SeriesWorksNotifier, SeriesWorksState, int>(
  (ref, workId) => SeriesWorksNotifier(ref, workId),
);
