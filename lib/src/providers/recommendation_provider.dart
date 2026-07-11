import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/work.dart';
import '../services/kikoeru_api_service.dart';

class RecommendationState {
  final List<Work> recommendations;
  final bool isLoading;
  final String? error;

  const RecommendationState({
    this.recommendations = const [],
    this.isLoading = false,
    this.error,
  });

  RecommendationState copyWith({
    List<Work>? recommendations,
    bool? isLoading,
    String? error,
  }) {
    return RecommendationState(
      recommendations: recommendations ?? this.recommendations,
      isLoading: isLoading ?? this.isLoading,
      error: error,
    );
  }
}

final _random = Random();

class RecommendationNotifier extends StateNotifier<RecommendationState> {
  final Ref ref;
  final int workId;

  RecommendationNotifier(this.ref, this.workId)
      : super(const RecommendationState());

  /// 加载推荐作品
  Future<void> loadRecommendations(Work work) async {
    if (state.isLoading) return;
    state = state.copyWith(isLoading: true, error: null);

    try {
      final apiService = ref.read(kikoeruApiServiceProvider);
      final searchTags = _selectSearchTags(work.tags ?? []);

      List<Work> allCandidates = [];

      if (searchTags.isNotEmpty) {
        final tagFutures = searchTags.map((tag) => _fetchWorksByTag(
              apiService,
              tag.id,
            ));
        final results = await Future.wait(
          tagFutures,
          eagerError: false,
        );
        for (final works in results) {
          allCandidates.addAll(works);
        }
      }

      if (allCandidates.length < 5 && work.vas != null && work.vas!.isNotEmpty) {
        final va = work.vas!.first;
        final vaWorks = await _fetchWorksByVa(apiService, va.id);
        allCandidates.addAll(vaWorks);
      }

      final seen = <int>{};
      final unique = <Work>[];
      for (final w in allCandidates) {
        if (w.id != work.id && seen.add(w.id)) {
          unique.add(w);
        }
      }

      final currentTagIds = work.tags?.map((t) => t.id).toSet() ?? {};
      unique.sort((a, b) {
        final scoreA = _relevanceScore(a, currentTagIds);
        final scoreB = _relevanceScore(b, currentTagIds);
        return scoreB.compareTo(scoreA);
      });

      final topCandidates = unique.take(30).toList()..shuffle(_random);
      final recommendations = topCandidates.take(20).toList();

      state = RecommendationState(recommendations: recommendations);
    } catch (e) {
      state = state.copyWith(isLoading: false, error: e.toString());
    }
  }

  /// 选取最具区分力的标签（最多 3 个，优先小众标签，带随机性）
  List<Tag> _selectSearchTags(List<Tag> allTags) {
    if (allTags.isEmpty) return [];

    final sorted = List<Tag>.from(allTags);
    sorted.sort((a, b) => b.name.length.compareTo(a.name.length));

    final candidates = sorted.take(6).toList()..shuffle(_random);
    return candidates.take(3).toList();
  }

  /// 计算相关度评分
  double _relevanceScore(Work candidate, Set<int> currentTagIds) {
    final candidateTagIds = candidate.tags?.map((t) => t.id).toSet() ?? {};
    final commonTags = currentTagIds.intersection(candidateTagIds).length;
    final rating = candidate.rateAverage ?? 0;
    return commonTags * 10.0 + rating * 2.0;
  }

  /// 获取标签最相关的作品（仅请求20条，按评分排序）
  Future<List<Work>> _fetchWorksByTag(
    KikoeruApiService api,
    int tagId,
  ) async {
    try {
      final data = await api.getWorksByTag(
        tagId: tagId,
        page: 1,
        pageSize: 20,
        order: 'rate_average_2dp',
        sort: 'desc',
      );
      return _parseWorks(data);
    } catch (e) {
      return [];
    }
  }

  /// 获取声优相关作品
  Future<List<Work>> _fetchWorksByVa(
    KikoeruApiService api,
    String vaId,
  ) async {
    try {
      final data = await api.getWorksByVa(
        vaId: vaId,
        page: 1,
        pageSize: 20,
        order: 'rate_average_2dp',
        sort: 'desc',
      );
      return _parseWorks(data);
    } catch (e) {
      return [];
    }
  }

  /// 解析 API 响应中的 works 列表
  List<Work> _parseWorks(Map<String, dynamic> data) {
    final worksList = data['works'];
    if (worksList is List) {
      return worksList.map((json) => Work.fromJson(json)).toList();
    }
    return [];
  }
}

/// 按 workId 区分的推荐 Provider（自动缓存）
final recommendationProvider = StateNotifierProvider.family<
    RecommendationNotifier, RecommendationState, int>(
  (ref, workId) => RecommendationNotifier(ref, workId),
);