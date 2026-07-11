import 'package:dio/dio.dart';

/// Configuration values shared across all strategy implementations.
class StrategyConfig {
  final String? token;
  final String? host;
  final int subtitle;
  final String order;
  final String sort;

  const StrategyConfig({
    this.token,
    this.host,
    this.subtitle = 0,
    this.order = 'create_date',
    this.sort = 'desc',
  });

  StrategyConfig copyWith({
    String? token,
    String? host,
    int? subtitle,
    String? order,
    String? sort,
  }) {
    return StrategyConfig(
      token: token ?? this.token,
      host: host ?? this.host,
      subtitle: subtitle ?? this.subtitle,
      order: order ?? this.order,
      sort: sort ?? this.sort,
    );
  }
}

/// Abstract strategy that defines the API contract for different server types.
///
/// Implementations: [OfficialKikoeruApiStrategy] (api.asmr-*.com) and
/// [CustomKikoeruApiStrategy] (self-hosted / local servers).
abstract class KikoeruApiStrategy {
  KikoeruApiStrategy(this.dio, this.config);

  final Dio dio;
  StrategyConfig config;

  /// Whether this strategy handles the official ASMR.one server.
  bool get isOfficial;

  Future<Map<String, dynamic>> login(String username, String password);
  Future<Map<String, dynamic>> register(String username, String password);
  Future<Map<String, dynamic>> getUserInfo();

  Future<Map<String, dynamic>> getWorks({
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  });

  Future<Map<String, dynamic>> getPopularWorks({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  });

  Future<Map<String, dynamic>> getRecommendedWorks({
    String? recommenderUuid,
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  });

  Future<Map<String, dynamic>> getWork(int workId);

  Future<Map<String, dynamic>> getWorksByTag({
    required int tagId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  });

  Future<Map<String, dynamic>> getWorksByVa({
    required String vaId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  });

  Future<Map<String, dynamic>> searchWorks({
    required String keyword,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
    bool includeTranslationWorks = true,
  });

  Future<Map<String, dynamic>> getWorkReviews(int workId, {
    int page = 1,
    int pageSize = 20,
  });

  Future<Map<String, dynamic>> getMyReviews({
    int page = 1,
    int pageSize = 20,
    String? filter,
    String order = 'updated_at',
    String sort = 'desc',
  });

  Future<Map<String, dynamic>> updateReviewProgress(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  });

  Future<void> deleteReview(int workId);

  Future<Map<String, dynamic>> getFavorites({
    int page = 1,
    int pageSize = 20,
  });

  /// Fetches multiple server pages and combines them into one logical page.
  ///
  /// Some servers (especially custom/local) return at most [serverPageSize]
  /// items per page. This helper merges the relevant server pages into a
  /// single result that matches the requested [page] / [pageSize].
  Future<Map<String, dynamic>> fetchCombinedPages({
    required int page,
    required int pageSize,
    required Future<Map<String, dynamic>> Function(int page) fetcher,
    String listKey = 'works',
    int serverPageSize = 12,
  }) async {
    final startItemIndex = (page - 1) * pageSize;
    final endItemIndex = startItemIndex + pageSize;

    final startServerPage = (startItemIndex / serverPageSize).floor() + 1;
    final endServerPage = ((endItemIndex - 1) / serverPageSize).floor() + 1;

    final combinedList = <dynamic>[];
    var totalCount = 0;

    final futures = <Future<Map<String, dynamic>>>[];
    for (int p = startServerPage; p <= endServerPage; p++) {
      futures.add(fetcher(p));
    }

    final results = await Future.wait(futures);

    for (final result in results) {
      List<dynamic> list = [];
      if (result[listKey] != null) {
        list = (result[listKey] as List?) ?? [];
      } else if (result['works'] != null) {
        list = (result['works'] as List?) ?? [];
      } else if (result['reviews'] != null) {
        list = (result['reviews'] as List?) ?? [];
      }

      combinedList.addAll(list);

      if (result['pagination'] != null &&
          result['pagination']['totalCount'] != null) {
        totalCount = result['pagination']['totalCount'];
      }
    }

    final globalStartIndex = (startServerPage - 1) * serverPageSize;
    final localStartIndex = startItemIndex - globalStartIndex;

    List<dynamic> finalItems = [];
    if (localStartIndex < combinedList.length) {
      final localEndIndex = localStartIndex + pageSize;
      final actualEndIndex =
          localEndIndex > combinedList.length ? combinedList.length : localEndIndex;
      finalItems = combinedList.sublist(localStartIndex, actualEndIndex);
    }

    return {
      listKey: finalItems,
      'pagination': {
        'currentPage': page,
        'pageSize': pageSize,
        'totalCount': totalCount,
      },
    };
  }
}