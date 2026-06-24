import 'package:dio/dio.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:convert';
import '../models/work.dart';
import '../utils/server_utils.dart';
import 'cookie_service.dart';
import 'cache_service.dart';
import 'log_service.dart';
import 'kikoeru_api_strategy.dart';
import 'official_kikoeru_api_strategy.dart';
import 'custom_kikoeru_api_strategy.dart';

final _log = LogService.instance;

class KikoeruApiService {
  static const String remoteHost = ServerUtils.defaultRemoteHost;
  static const String localHost = ServerUtils.defaultLocalHost;

  /// Called when a 401 or 403 response is received from any API request.
  /// The AuthNotifier sets this to trigger auto-logout + session-expired UI.
  void Function()? onUnauthorized;

  late Dio _dio;
  // Kept for URL building (getDownloadUrl / getStreamUrl / getCoverUrl).
  String? _host;

  /// The active strategy: [OfficialKikoeruApiStrategy] or [CustomKikoeruApiStrategy].
  KikoeruApiStrategy? _strategy;

  /// Shared config that is kept in sync with [_strategy].
  StrategyConfig _currentConfig = const StrategyConfig();

  KikoeruApiService() {
    _dio = Dio();
    _setupInterceptors();
  }

  // ── Interceptors ──

  void _setupInterceptors() {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          final strategy = _strategy;

          // User-Agent differs between official and custom servers
          if (strategy?.isOfficial ?? false) {
            options.headers['User-Agent'] =
                'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
            options.headers['Referer'] = 'https://www.asmr.one/';
            options.headers['Origin'] = 'https://www.asmr.one';
          } else {
            options.headers['User-Agent'] = 'KikoFlu';
          }
          options.headers['Accept-Encoding'] = 'gzip';
          options.headers.addAll(CookieService.serverCookieHeaders);

          // Add Authorization header if token exists.
          // Skip for auth endpoints (login / register) so they can be called
          // without a Bearer token.
          final token = strategy?.config.token;
          if (token != null && token.isNotEmpty) {
            final isLoginRequest = options.method == 'POST' &&
                options.path.contains('/api/auth/me');
            final isSignupRequest = options.method == 'POST' &&
                (options.path.contains('/api/auth/signup') ||
                    options.path.contains('/api/auth/reg'));

            if (!isLoginRequest && !isSignupRequest) {
              options.headers['Authorization'] = 'Bearer $token';
            }
          }

          options.connectTimeout = const Duration(seconds: 15);
          options.receiveTimeout = const Duration(seconds: 15);
          handler.next(options);
        },
        onError: (error, handler) async {
          _log.error('API Error: ${error.message}');

          final statusCode = error.response?.statusCode;
          if ((statusCode == 401 || statusCode == 403) &&
              onUnauthorized != null &&
              !error.requestOptions.path.contains('/api/auth/')) {
            _log.warning(
                'Unauthorized (HTTP $statusCode) on ${error.requestOptions.path}, triggering session expired handler',
                tag: 'API');
            onUnauthorized!();
          }

          // Auto-retry connection timeout once
          if (error.type == DioExceptionType.connectionTimeout &&
              error.requestOptions.extra['retried'] != true) {
            _log.warning('Connection timeout detected, retrying once...', tag: 'API');
            error.requestOptions.extra['retried'] = true;
            try {
              final response = await _dio.fetch(error.requestOptions);
              return handler.resolve(response);
            } catch (_) {
              return handler.next(error);
            }
          }

          handler.next(error);
        },
      ),
    );

    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) {
          // Log request without body for sensitive endpoints
          final isAuthEndpoint = options.path.contains('/api/auth/');
          if (!isAuthEndpoint) {
            _log.info('[API] ${options.method} ${options.uri}');
          } else {
            _log.info('[API] ${options.method} ${options.path} (auth endpoint, body hidden)');
          }
          handler.next(options);
        },
        onResponse: (response, handler) {
          _log.info('[API] Response ${response.statusCode} ${response.requestOptions.path}');
          handler.next(response);
        },
        onError: (error, handler) {
          _log.error('[API] Error ${error.response?.statusCode} ${error.requestOptions.path}');
          handler.next(error);
        },
      ),
    );
  }

  // ── Shared helpers ──

  /// Sets up [host], creates the appropriate strategy, and updates config.
  void _initializeForHost(String host) {
    _host = _normalizeHost(host);
    _dio.options.baseUrl = _host!;
    _currentConfig = _currentConfig.copyWith(host: _host);
    _strategy = _createStrategy(_host!);
    _strategy!.config = _currentConfig;
  }

  /// Shared GET for simple list endpoints (tags, VAs, circles).
  Future<List<dynamic>> _simpleGet(String path, String errorMessage) async {
    try {
      final response = await _dio.get(path);
      return response.data;
    } catch (e) {
      throw KikoeruApiException(errorMessage, e);
    }
  }

  /// Filters a list of named items by [query] and maps them with [mapper].
  Future<List<T>> _searchNamedItems<T>({
    required Future<List<dynamic>> Function() fetcher,
    required String query,
    required T Function(Map<String, dynamic> json) mapper,
    required String errorMessage,
  }) async {
    try {
      final items = await fetcher();
      return items
          .where((item) =>
              item['name'].toString().toLowerCase().contains(query.toLowerCase()))
          .map((item) => mapper(item as Map<String, dynamic>))
          .toList();
    } catch (e) {
      throw KikoeruApiException(errorMessage, e);
    }
  }

  /// Shared POST for simple playlist actions (like, remove-like, delete).
  Future<Map<String, dynamic>> _playlistPostAction(
      String action, String playlistId, String errorMessage) async {
    try {
      final response =
          await _dio.post('/api/playlist/$action', data: {'id': playlistId});
      return response.data;
    } catch (e) {
      throw KikoeruApiException(errorMessage, e);
    }
  }

  // ── Initialisation ──

  void init(String token, String host) {
    // Normalize host
    _host = _normalizeHost(host);
    _dio.options.baseUrl = _host!;

    // Update config and (re)create strategy
    _currentConfig = StrategyConfig(
      token: token,
      host: _host,
      subtitle: _currentConfig.subtitle,
      order: _currentConfig.order,
      sort: _currentConfig.sort,
    );
    _strategy = _createStrategy(_host!);
    _strategy!.config = _currentConfig;

    _log.info('Initialized - host: $_host, token: ${token.isEmpty ? "empty" : "exists (${token.length} chars)"}', tag: 'API');
  }

  /// Creates the appropriate strategy for the given host.
  KikoeruApiStrategy _createStrategy(String host) {
    if (ServerUtils.isOfficialServer(host)) {
      return OfficialKikoeruApiStrategy(_dio, _currentConfig);
    } else {
      return CustomKikoeruApiStrategy(_dio, _currentConfig);
    }
  }

  /// Returns the normalized version of [host] (with protocol prefix).
  String _normalizeHost(String host) => ServerUtils.normalizeHost(host);

  // ── Configuration setters ──

  void setOrder(String order) {
    if (_currentConfig.order == order) {
      _currentConfig = _currentConfig.copyWith(
        sort: _currentConfig.sort == 'asc' ? 'desc' : 'asc',
      );
    } else {
      _currentConfig = _currentConfig.copyWith(order: order);
    }
    _strategy?.config = _currentConfig;
  }

  void setSubtitle(int subtitle) {
    _currentConfig = _currentConfig.copyWith(subtitle: subtitle);
    _strategy?.config = _currentConfig;
  }

  // ── Connectivity ──

  Future<bool> isConnected() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    return connectivityResult != ConnectivityResult.none;
  }

  Future<bool> testHostConnection(String host) async {
    final testDio = Dio();
    try {
      testDio.options.connectTimeout = const Duration(seconds: 3);
      testDio.options.receiveTimeout = const Duration(seconds: 3);

      final testHost = host.startsWith('http') ? host : 'https://$host';

      await testDio.get(
        '$testHost/api/health',
        options: Options(
          validateStatus: (status) => status! < 500,
        ),
      );
      return true;
    } catch (e) {
      _log.error('Host connection test failed for $host: $e');
      return false;
    } finally {
      testDio.close();
    }
  }

  /// Public helper so external callers can check the server type.
  bool get isOfficialServer => _strategy?.isOfficial ?? false;

  // ── Authentication ──

  Future<Map<String, dynamic>> login(
      String username, String password, String host) async {
    _initializeForHost(host);
    return _strategy!.login(username, password);
  }

  Future<Map<String, dynamic>> register(
      String username, String password, String host) async {
    _initializeForHost(host);
    return _strategy!.register(username, password);
  }

  Future<Map<String, dynamic>> getUserInfo() {
    return _strategy!.getUserInfo();
  }

  // ── Works ──

  Future<Map<String, dynamic>> getWorks({
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) {
    return _strategy!.getWorks(
      page: page,
      pageSize: pageSize,
      order: order,
      sort: sort,
      subtitle: subtitle,
      seed: seed,
    );
  }

  Future<Map<String, dynamic>> getPopularWorks({
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) {
    return _strategy!.getPopularWorks(
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      subtitle: subtitle,
      withPlaylistStatus: withPlaylistStatus,
    );
  }

  Future<Map<String, dynamic>> getRecommendedWorks({
    required String recommenderUuid,
    int page = 1,
    int pageSize = 20,
    String? keyword,
    int? subtitle,
    List<String>? withPlaylistStatus,
  }) {
    return _strategy!.getRecommendedWorks(
      recommenderUuid: recommenderUuid,
      page: page,
      pageSize: pageSize,
      keyword: keyword,
      subtitle: subtitle,
      withPlaylistStatus: withPlaylistStatus,
    );
  }

  Future<Map<String, dynamic>> getWork(int workId) {
    return _strategy!.getWork(workId);
  }

  Future<Map<String, dynamic>> getWorksByTag({
    required int tagId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) {
    return _strategy!.getWorksByTag(
      tagId: tagId,
      page: page,
      pageSize: pageSize,
      order: order,
      sort: sort,
      subtitle: subtitle,
      seed: seed,
    );
  }

  Future<Map<String, dynamic>> getWorksByVa({
    required String vaId,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
  }) {
    return _strategy!.getWorksByVa(
      vaId: vaId,
      page: page,
      pageSize: pageSize,
      order: order,
      sort: sort,
      subtitle: subtitle,
      seed: seed,
    );
  }

  Future<Map<String, dynamic>> searchWorks({
    required String keyword,
    int page = 1,
    int pageSize = 40,
    String? order,
    String? sort,
    int? subtitle,
    int? seed,
    bool includeTranslationWorks = true,
  }) {
    return _strategy!.searchWorks(
      keyword: keyword,
      page: page,
      pageSize: pageSize,
      order: order,
      sort: sort,
      subtitle: subtitle,
      seed: seed,
      includeTranslationWorks: includeTranslationWorks,
    );
  }

  // ── Tags ──

  Future<List<dynamic>> getAllTags() =>
      _simpleGet('/api/tags/', 'Failed to get tags');

  Future<List<Tag>> searchTags(String query) => _searchNamedItems<Tag>(
        fetcher: getAllTags,
        query: query,
        mapper: Tag.fromJson,
        errorMessage: 'Failed to search tags',
      );

  // ── VAs ──



  // ── Circles ──

  Future<List<dynamic>> getAllVas() =>
      _simpleGet('/api/vas/', 'Failed to get VAs');

  Future<List<Va>> searchVas(String query) => _searchNamedItems<Va>(
        fetcher: getAllVas,
        query: query,
        mapper: Va.fromJson,
        errorMessage: 'Failed to search VAs',
      );

  Future<List<dynamic>> getAllCircles() =>
      _simpleGet('/api/circles/', 'Failed to get circles');

  // ── Tracks ──

  Future<List<dynamic>> getWorkTracks(int workId) async {
    try {
      final cachedJson = await CacheService.getCachedWorkTracks(workId);
      if (cachedJson != null) {
        _log.info('从缓存加载作品文件列表: $workId', tag: 'API');
        return jsonDecode(cachedJson) as List<dynamic>;
      }

      final response = await _dio.get('/api/tracks/$workId');
      final tracks = response.data as List<dynamic>;

      await CacheService.cacheWorkTracks(workId, jsonEncode(tracks));
      _log.info('已缓存作品文件列表: $workId', tag: 'API');

      return tracks;
    } catch (e) {
      throw KikoeruApiException('Failed to get tracks', e);
    }
  }

  // ── Reviews ──

  Future<Map<String, dynamic>> getWorkReviews(int workId,
      {int page = 1, int pageSize = 20}) {
    return _strategy!.getWorkReviews(workId, page: page, pageSize: pageSize);
  }

  Future<Map<String, dynamic>> getMyReviews({
    int page = 1,
    int pageSize = 20,
    String? filter,
    String order = 'updated_at',
    String sort = 'desc',
  }) {
    return _strategy!.getMyReviews(
      page: page,
      pageSize: pageSize,
      filter: filter,
      order: order,
      sort: sort,
    );
  }

  Future<Map<String, dynamic>> updateReviewProgress(
    int workId, {
    String? progress,
    int? rating,
    String? reviewText,
  }) {
    return _strategy!.updateReviewProgress(
      workId,
      progress: progress,
      rating: rating,
      reviewText: reviewText,
    );
  }

  Future<void> deleteReview(int workId) {
    return _strategy!.deleteReview(workId);
  }

  // ── Tags (vote / attach) ──

  Future<Map<String, dynamic>> voteWorkTag({
    required int workId,
    required int tagId,
    required int status,
  }) async {
    try {
      final response = await _dio.post(
        '/api/vote/vote-work-tag',
        data: {
          'workID': workId,
          'tagID': tagId,
          'status': status,
        },
      );
      await CacheService.invalidateWorkDetailCache(workId);
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to vote work tag', e);
    }
  }

  Future<Map<String, dynamic>> attachTagsToWork({
    required int workId,
    required List<int> tagIds,
  }) async {
    try {
      final response = await _dio.post(
        '/api/vote/attach-tags-to-work',
        data: {
          'workID': workId,
          'tagIDs': tagIds,
        },
      );
      await CacheService.invalidateWorkDetailCache(workId);
      return response.data;
    } on DioException catch (e) {
      if (e.response?.statusCode == 400) {
        final errorData = e.response?.data;
        if (errorData is Map &&
            errorData['error'] == 'vote.mustBindEmailFirst') {
          throw KikoeruApiException(
            'Must bind email first',
            'vote.mustBindEmailFirst',
          );
        }
      }
      throw KikoeruApiException('Failed to attach tags to work', e);
    } catch (e) {
      throw KikoeruApiException('Failed to attach tags to work', e);
    }
  }

  // ── Favorites ──

  Future<Map<String, dynamic>> getFavorites(
      {int page = 1, int pageSize = 20}) {
    return _strategy!.getFavorites(page: page, pageSize: pageSize);
  }

  Future<void> addToFavorites(int workId) async {
    try {
      await _dio.put('/api/favourites/$workId');
    } catch (e) {
      throw KikoeruApiException('Failed to add to favorites', e);
    }
  }

  Future<void> removeFromFavorites(int workId) async {
    try {
      await _dio.delete('/api/favourites/$workId');
    } catch (e) {
      throw KikoeruApiException('Failed to remove from favorites', e);
    }
  }

  // ── Playlists ──

  Future<List<dynamic>> getPlaylists() async {
    try {
      final response = await _dio.get('/api/playlists');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlists', e);
    }
  }

  Future<Map<String, dynamic>> getUserPlaylists({
    int page = 1,
    int pageSize = 20,
    String filterBy = 'all',
  }) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlists',
        queryParameters: {
          'page': page,
          'pageSize': pageSize,
          'filterBy': filterBy,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get user playlists', e);
    }
  }

  Future<Map<String, dynamic>> createPlaylist({
    required String name,
    int privacy = 0,
    String locale = 'zh-CN',
    String? description,
    List<int>? works,
  }) async {
    try {
      final data = {
        'name': name,
        'privacy': privacy,
        'locale': locale,
        'works': works ?? [],
      };
      if (description != null && description.isNotEmpty) {
        data['description'] = description;
      }

      final response = await _dio.post(
        '/api/playlist/create-playlist',
        data: data,
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to create playlist', e);
    }
  }

  Future<Map<String, dynamic>> likePlaylist(String playlistId) =>
      _playlistPostAction('like-playlist', playlistId, 'Failed to like playlist');

  Future<Map<String, dynamic>> removeLikePlaylist(String playlistId) =>
      _playlistPostAction('remove-like-playlist', playlistId, 'Failed to remove liked playlist');

  Future<Map<String, dynamic>> deletePlaylist(String playlistId) =>
      _playlistPostAction('delete-playlist', playlistId, 'Failed to delete playlist');

  Future<Map<String, dynamic>> editPlaylistMetadata({
    required String id,
    required String name,
    required int privacy,
    required String description,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/edit-playlist-metadata',
        data: {
          'id': id,
          'data': {
            'name': name,
            'privacy': privacy,
            'description': description,
          },
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to edit playlist metadata', e);
    }
  }

  Future<Map<String, dynamic>> addWorksToPlaylist({
    required String playlistId,
    required List<String> works,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/add-works-to-playlist',
        data: {
          'id': playlistId,
          'works': works,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to add works to playlist', e);
    }
  }

  Future<Map<String, dynamic>> removeWorksFromPlaylist({
    required String playlistId,
    required List<int> works,
  }) async {
    try {
      final response = await _dio.post(
        '/api/playlist/remove-works-from-playlist',
        data: {
          'id': playlistId,
          'works': works,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to remove works from playlist', e);
    }
  }

  Future<Map<String, dynamic>> getPlaylistMetadata(String playlistId) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlist-metadata',
        queryParameters: {'id': playlistId},
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlist metadata', e);
    }
  }

  Future<Map<String, dynamic>> getPlaylistWorks({
    required String playlistId,
    int page = 1,
    int pageSize = 12,
  }) async {
    try {
      final response = await _dio.get(
        '/api/playlist/get-playlist-works',
        queryParameters: {
          'id': playlistId,
          'page': page,
          'pageSize': pageSize,
        },
      );
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get playlist works', e);
    }
  }

  // ── Progress ──

  Future<void> updateProgress(int workId, double progress) async {
    try {
      await _dio.put(
        '/api/progress/$workId',
        data: {'progress': progress},
      );
    } catch (e) {
      throw KikoeruApiException('Failed to update progress', e);
    }
  }

  Future<Map<String, dynamic>> getProgress(int workId) async {
    try {
      final response = await _dio.get('/api/progress/$workId');
      return response.data;
    } catch (e) {
      throw KikoeruApiException('Failed to get progress', e);
    }
  }

  // ── Download URLs ──

  String getDownloadUrl(String hash, String fileName) {
    return '$_host/api/media/download/$hash/$fileName';
  }

  String getStreamUrl(String hash, String fileName) {
    return '$_host/api/media/stream/$hash/$fileName';
  }

  String getCoverUrl(int workId) {
    return '$_host/api/cover/$workId';
  }

  // ── Cleanup ──

  void dispose() {
    _dio.close();
  }
}

// Provider
final kikoeruApiServiceProvider = Provider<KikoeruApiService>((ref) {
  return KikoeruApiService();
});

class KikoeruApiException implements Exception {
  final String message;
  final dynamic originalError;

  KikoeruApiException(this.message, this.originalError);

  @override
  String toString() => 'KikoeruApiException: $message';
}
