import 'dart:convert';
import 'kikoeru_api_strategy.dart';
import 'cache_service.dart';
import 'log_service.dart';
import 'kikoeru_api_service.dart' show KikoeruApiException;

final _log = LogService.instance;

/// Strategy for self-hosted / local Kikoeru servers.
///
/// Key differences from the official server:
/// - Uses `lyric` query param instead of `subtitle`
/// - Maps `create_date` → `release` for sort order
/// - Many endpoints return at most 12 items per page (uses [_fetchCombinedPages])
/// - Recommender endpoints replaced with basic `/api/works` queries
/// - Work reviews are not supported (returns empty)
/// - Search uses a JSON-based advanced query format
class CustomKikoeruApiStrategy extends KikoeruApiStrategy {
  CustomKikoeruApiStrategy(super.dio, super.config);

  @override
  bool get isOfficial => false;

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
      // Custom server registration without recommender
      final savedToken = config.token;
      config = config.copyWith(token: null);

      final response = await dio.post(
        '/api/auth/reg',
        data: {'name': username, 'password': password},
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
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      fetcher: (p) async {
        try {
          String effectiveOrder = order ?? config.order;
          int? nsfwParam;

          if (effectiveOrder == 'create_date') {
            effectiveOrder = 'release';
          } else if (effectiveOrder == 'nsfw') {
            effectiveOrder = 'release';
            nsfwParam = 1;
          }

          final queryParams = <String, dynamic>{
            'page': p,
            'pageSize': 12,
            'order': effectiveOrder,
            'sort': sort ?? config.sort,
            'lyric': (subtitle ?? config.subtitle) == 1 ? 'local' : '',
            'seed': seed ?? 21,
          };
          if (nsfwParam != null) queryParams['nsfw'] = nsfwParam;

          final response = await dio.get('/api/works', queryParameters: queryParams);
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get works', e);
        }
      },
    );
  }

  @override
  Future<Map<String, dynamic>> getPopularWorks({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) async {
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      fetcher: (p) async {
        try {
          final queryParams = <String, dynamic>{
            'page': p,
            'pageSize': 12,
            'order': 'dl_count',
            'sort': 'desc',
            'lyric': (subtitle ?? 0) == 1 ? 'local' : '',
          };

          final response = await dio.get('/api/works', queryParameters: queryParams);
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get popular works', e);
        }
      },
    );
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
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      fetcher: (p) async {
        try {
          final queryParams = <String, dynamic>{
            'page': p,
            'pageSize': 12,
            'order': 'random',
            'sort': 'desc',
            'lyric': (subtitle ?? 0) == 1 ? 'local' : '',
            'seed': DateTime.now().millisecondsSinceEpoch % 1000,
          };

          final response = await dio.get('/api/works', queryParameters: queryParams);
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get recommended works', e);
        }
      },
    );
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
      final response = await dio.get('/api/work/$workId');
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
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      fetcher: (p) async {
        try {
          final queryParams = <String, dynamic>{
            'page': p,
            'pageSize': 12,
            'order': order ?? config.order,
            'sort': sort ?? config.sort,
            'lyric': (subtitle ?? config.subtitle) == 1 ? 'local' : '',
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
      },
    );
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
    return fetchCombinedPages(
      page: page,
      pageSize: pageSize,
      fetcher: (p) async {
        try {
          final queryParams = <String, dynamic>{
            'page': p,
            'pageSize': 12,
            'order': order ?? config.order,
            'sort': sort ?? config.sort,
            'lyric': (subtitle ?? config.subtitle) == 1 ? 'local' : '',
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
      },
    );
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
      String effectiveOrder = order ?? config.order;
      if (effectiveOrder == 'create_date') {
        effectiveOrder = 'release';
      }

      dynamic keywordValue;
      int? nsfwParam;

      try {
        final decoded = jsonDecode(keyword);
        if (decoded is List) {
          keywordValue = keyword;
        } else {
          throw const FormatException('Not a list');
        }
      } catch (_) {
        final conditions = <Map<String, dynamic>>[];
        final regex = RegExp(r'\$(-?)([a-zA-Z]+):([^$]+)\$');
        String remainingText = keyword;

        for (final match in regex.allMatches(keyword)) {
          final isExclude = match.group(1) == '-';
          final type = match.group(2);
          final value = match.group(3);

          if (!isExclude && value != null) {
            if (type == 'tag') {
              conditions.add({'t': 3, 'd': 0, 'name': value});
            } else if (type == 'va' || type == 'circle') {
              conditions.add({'t': 2, 'd': '0', 'name': value});
            } else if (type == 'age') {
              if (value == 'general') {
              nsfwParam = 1;
            } else if (value == 'adult') {
              nsfwParam = 2;
            }
            }
          }
          remainingText = remainingText.replaceFirst(match.group(0)!, '');
        }

        final plainText = remainingText.trim();
        if (plainText.isNotEmpty) {
          if (RegExp(r'^[Rr][Jj]\d+$', caseSensitive: false).hasMatch(plainText)) {
            conditions.add({'t': 5, 'd': plainText.toUpperCase(), 'name': plainText});
          } else {
            conditions.add({'t': 1, 'd': plainText, 'name': plainText});
          }
        }

        if (conditions.isEmpty && keyword.isNotEmpty) {
          conditions.add({'t': 1, 'd': keyword, 'name': keyword});
        }

        // Resolve IDs for tags / VAs
        if (conditions.isNotEmpty) {
          List<dynamic>? allTags;
          List<dynamic>? allVas;
          List<dynamic>? allCircles;

          for (var i = 0; i < conditions.length; i++) {
            final condition = conditions[i];
            final name = condition['name'] as String;

            if (condition['t'] == 3 && condition['d'] == 0) {
              try {
                if (allTags == null) {
                  final tagsResp = await dio.get('/api/tags/');
                  allTags = tagsResp.data as List<dynamic>;
                  _log.info('Loaded ${allTags.length} tags for search resolution', tag: 'API');
                }
                final idx = allTags.indexWhere(
                  (t) => (t['name'] as String).toLowerCase() == name.toLowerCase(),
                );
                condition['d'] = idx >= 0 ? allTags[idx]['id'] : name;
              } catch (e) {
                _log.error('Failed to resolve tag ID for "$name": $e', tag: 'API');
                condition['t'] = 1;
                condition['d'] = name;
              }
            } else if (condition['t'] == 2 && condition['d'] == '0') {
              bool resolved = false;
              try {
                if (allVas == null) {
                  final vasResp = await dio.get('/api/vas/');
                  allVas = vasResp.data as List<dynamic>;
                }
                final idx = allVas.indexWhere(
                  (v) => (v['name'] as String).toLowerCase() == name.toLowerCase(),
                );
                if (idx >= 0) {
                  condition['d'] = allVas[idx]['id'];
                  resolved = true;
                }
              } catch (e) {
                _log.warning('Failed to resolve VA ID for "$name": $e', tag: 'API');
              }

              if (!resolved) {
                try {
                  if (allCircles == null) {
                    final circlesResp = await dio.get('/api/circles/');
                    allCircles = circlesResp.data as List<dynamic>;
                  }
                  final idx = allCircles.indexWhere(
                    (c) => (c['name'] as String).toLowerCase() == name.toLowerCase(),
                  );
                  if (idx >= 0) {
                    condition['d'] = allCircles[idx]['id'];
                    resolved = true;
                  }
                } catch (e) {
                  _log.warning('Failed to resolve circle ID for "$name": $e', tag: 'API');
                }
              }

              if (!resolved) {
                condition['t'] = 1;
                condition['d'] = name;
              }
            }
          }
        }

        keywordValue = jsonEncode(conditions);
      }

      return fetchCombinedPages(
        page: page,
        pageSize: pageSize,
        fetcher: (p) async {
          final queryParams = <String, dynamic>{
            'keyword': keywordValue,
            'page': p,
            'pageSize': 12,
            'order': effectiveOrder,
            'sort': sort ?? config.sort,
            'isAdvance': 1,
            'lyric': (subtitle ?? config.subtitle) == 1 ? 'local' : '',
            'seed': seed ?? 0,
          };
          if (nsfwParam != null) queryParams['nsfw'] = nsfwParam;

          final response = await dio.get('/api/search', queryParameters: queryParams);
          return response.data;
        },
      );
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
    // Local backend does not support getting reviews for a specific work
    return {
      'reviews': [],
      'pagination': {'currentPage': 1, 'pageSize': pageSize, 'totalCount': 0},
    };
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
      fetcher: (p) async {
        try {
          final query = <String, dynamic>{
            'page': p,
            'pageSize': 12,
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
    _log.info('Updating review: workId=$workId, progress=$progress, rating=$rating', tag: 'API');
    try {
      final data = <String, dynamic>{'work_id': workId};
      final queryParams = <String, dynamic>{};

      if (progress != null) {
        data['progress'] = progress;
      } else {
        queryParams['starOnly'] = true;
      }
      if (rating != null) {
        data['rating'] = rating;
      } else {
        queryParams['starOnly'] = false;
        queryParams['progressOnly'] = true;
      }
      if (reviewText != null) data['review_text'] = reviewText;
      if ((progress != null && rating != null) || reviewText != null) {
        queryParams['starOnly'] = false;
      }

      final response = await dio.put(
        '/api/review',
        data: data,
        queryParameters: queryParams,
      );

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
      fetcher: (p) async {
        try {
          final response = await dio.get(
            '/api/favourites',
            queryParameters: {'page': p, 'pageSize': 12},
          );
          return response.data;
        } catch (e) {
          throw KikoeruApiException('Failed to get favorites', e);
        }
      },
    );
  }
}
