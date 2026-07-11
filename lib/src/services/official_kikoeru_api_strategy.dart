import 'kikoeru_api_strategy.dart';
import 'cache_service.dart';
import 'log_service.dart';
import 'kikoeru_api_service.dart' show KikoeruApiException;

final _log = LogService.instance;

/// Strategy for the official ASMR.one server (api.asmr-*.com).
class OfficialKikoeruApiStrategy extends KikoeruApiStrategy {
  OfficialKikoeruApiStrategy(super.dio, super.config);

  @override
  bool get isOfficial => true;

  // ── Authentication ──

  @override
  Future<Map<String, dynamic>> login(String username, String password) async {
    try {
      final response = await dio.post(
        '/api/auth/me',
        data: {'name': username, 'password': password},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Login failed', e);
    }
  }

  @override
  Future<Map<String, dynamic>> register(
      String username, String password) async {
    try {
      // Step 1: Get recommender UUID
      String recommenderUuid = '766cc58d-7f1e-4958-9a93-913400f378dc';

      // Temporarily clear token to get registration info
      // savedConfig is declared OUTSIDE the inner try so that finally can use it
      final savedToken = config.token;
      final savedConfig = config;
      config = savedConfig.copyWith(token: null);

      try {
        // We make a POST without the Bearer header (interceptor skips /api/auth/*)
        // to get the recommender UUID (only works without auth).
        final recommenderResponse = await dio.post(
          '/api/recommender/recommend-for-user',
          data: {'keyword': ' ', 'page': 1, 'pageSize': 20},
        );

        if (recommenderResponse.data is Map) {
          if (recommenderResponse.data['uuid'] != null) {
            recommenderUuid = recommenderResponse.data['uuid'];
          } else if (recommenderResponse.data['recommenderUuid'] != null) {
            recommenderUuid = recommenderResponse.data['recommenderUuid'];
          }
        }
      } catch (e) {
        _log.warning('Failed to get recommender, using default: $e');
      } finally {
        config = savedConfig;
      }

      // Step 2: Register with recommender UUID
      config = config.copyWith(token: null);
      final response = await dio.post(
        '/api/auth/reg',
        data: {
          'name': username,
          'password': password,
          'recommenderUuid': recommenderUuid,
        },
      );

      if (response.data is Map && response.data['token'] != null) {
        config = config.copyWith(token: response.data['token']);
      } else {
        config = config.copyWith(token: savedToken);
      }

      return response.data;
    } catch (e) {
      throw KikoeruApiException('Registration failed', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getUserInfo() async {
    try {
      final response = await dio.get('/api/auth/me');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get user info', e);
    }
  }

  // ── Works ──

  @override
  Future<Map<String, dynamic>> getWorks({
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'order': order ?? config.order,
        'sort': sort ?? config.sort,
        'subtitle': subtitle ?? config.subtitle,
        'seed': seed ?? 21,
      };

      final response = await dio.get('/api/works', queryParameters: queryParams);
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getPopularWorks({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      final data = <String, dynamic>{
        'keyword': keyword ?? ' ',
        'page': page,
        'pageSize': pageSize,
        'subtitle': subtitle ?? 0,
        'localSubtitledWorks': <String>[],
        'withPlaylistStatus': withPlaylistStatus ?? <String>[],
      };

      final response = await dio.post('/api/recommender/popular', data: data);
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get popular works', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getRecommendedWorks({
    String? recommenderUuid,
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    try {
      final data = <String, dynamic>{
        'keyword': keyword ?? ' ',
        'recommenderUuid': recommenderUuid ?? '',
        'page': page,
        'pageSize': pageSize,
        'subtitle': subtitle ?? 0,
        'localSubtitledWorks': <String>[],
        'withPlaylistStatus': withPlaylistStatus ?? <String>[],
      };

      final response = await dio.post(
        '/api/recommender/recommend-for-user',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get recommended works', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getWork(int workId) async {
    try {
      final cachedData = await CacheService.getCachedWorkDetail(workId);
      if (cachedData != null) {
        _log.info('Work detail cache hit: $workId', tag: 'API');
        return cachedData;
      }

      _log.info('Work detail cache miss, fetching: $workId', tag: 'API');
      final response = await dio.get('/api/work/$workId?v=2');
      final data = response.data as Map<String, dynamic>;

      await CacheService.cacheWorkDetail(workId, data);
      return data;
    } catch (e) {
      throw KikoeruApiException('Failed to get work', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getWorksByTag({
    required int tagId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'order': order ?? config.order,
        'sort': sort ?? config.sort,
        'subtitle': subtitle ?? config.subtitle,
        'seed': seed ?? 21,
      };

      final response = await dio.get(
        '/api/tags/$tagId/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works by tag', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getWorksByVa({
    required String vaId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) async {
    try {
      final queryParams = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'order': order ?? config.order,
        'sort': sort ?? config.sort,
        'subtitle': subtitle ?? config.subtitle,
        'seed': seed ?? 21,
      };

      final response = await dio.get(
        '/api/vas/$vaId/works',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get works by VA', e);
    }
  }

  @override
  Future<Map<String, dynamic>> searchWorks({
    required String keyword,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
    bool includeTranslationWorks = true,
  }) async {
    try {
      final encodedKeyword = Uri.encodeComponent(keyword);
      final queryParams = <String, dynamic>{
        'page': page,
        'pageSize': pageSize,
        'order': order ?? config.order,
        'sort': sort ?? config.sort,
        'subtitle': subtitle ?? config.subtitle,
        'includeTranslationWorks': includeTranslationWorks,
      };

      final response = await dio.get(
        '/api/search/$encodedKeyword',
        queryParameters: queryParams,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to search works', e);
    }
  }

  // ── Reviews ──

  @override
  Future<Map<String, dynamic>> getWorkReviews(int workId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    try {
      final response = await dio.get(
        '/api/review/$workId',
        queryParameters: {'page': page, 'pageSize': pageSize},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get reviews', e);
    }
  }

  @override
  Future<Map<String, dynamic>> getMyReviews({
    int page = 1,
    int pageSize = 20,
    String? filter,
    String order = 'updated_at',
    String sort = 'desc',
  }) async {
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      serverPageSize: 20,
      fetcher: (p) async {
        try {
          final query = <String, dynamic>{
            'page': p,
            'pageSize': 20,
            'order': order,
            'sort': sort,
          };
          if (filter != null && filter.isNotEmpty) {
            query['filter'] = filter;
          }
          final response = await dio.get('/api/review', queryParameters: query);
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get my reviews', e);
        }
      },
    );
  }

  @override
  Future<Map<String, dynamic>> updateReviewProgress(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) async {
    try {
      final data = <String, dynamic>{'work_id': workId};
      if (progress != null) data['progress'] = progress;
      if (rating != null) data['rating'] = rating;
      if (reviewText != null) data['review_text'] = reviewText;

      final response = await dio.put('/api/review', data: data);

      await CacheService.invalidateWorkDetailCache(workId);
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to update review progress', e);
    }
  }

  @override
  Future<void> deleteReview(int workId) async {
    try {
      await dio.delete('/api/review', queryParameters: {'work_id': workId});
      await CacheService.invalidateWorkDetailCache(workId);
    } catch (e) {
      throw KikoeruApiException('Failed to delete review', e);
    }
  }

  // ── Favorites ──

  @override
  Future<Map<String, dynamic>> getFavorites({
    int page = 1,
    int pageSize = 20,
  }) async {
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      serverPageSize: 20,
      fetcher: (p) async {
        try {
          final response = await dio.get(
            '/api/favourites',
            queryParameters: {'page': p, 'pageSize': 20},
          );
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get favorites', e);
        }
      },
    );
  }
}
