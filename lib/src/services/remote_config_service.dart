import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/firebase_config.dart';
import 'log_service.dart';

class RemoteConfigService {
  static RemoteConfigService? _instance;
  static RemoteConfigService get instance => _instance ??= RemoteConfigService._();

  RemoteConfigService._({Dio? dio}) : _dio = dio ?? Dio();

  /// For backward compatibility: RemoteConfigService() returns the same singleton.
  factory RemoteConfigService({Dio? dio}) {
    _instance ??= RemoteConfigService._(dio: dio);
    return _instance!;
  }

  static const String _installationsBase =
      'https://firebaseinstallations.googleapis.com/v1';
  static const String _remoteConfigBase =
      'https://firebaseremoteconfig.googleapis.com/v1';

  static const String _keyFid = 'remote_config_fid';
  static const String _keyToken = 'remote_config_token';
  static const String _keyRefreshToken = 'remote_config_refresh_token';
  static const String _keyEntries = 'remote_config_entries';
  static const String _keyLastFetchTime = 'remote_config_last_fetch_time';

  static const Duration _minFetchInterval = Duration(minutes: 5);

  /// Whether a force refresh is pending (e.g. after app resume).
  bool _forceRefreshPending = false;

  final Dio _dio;

  bool get isConfigured => FirebaseConfig.isConfigured;

  /// Schedule a force refresh on next fetchEntries() call.
  /// Call this when app resumes from background or on pull-to-refresh.
  void scheduleForceRefresh() {
    _forceRefreshPending = true;
  }

  Future<Map<String, String>> fetchEntries({bool force = false}) async {
    if (!isConfigured) {
      LogService.instance.debug(
        '[RemoteConfig] Skipped: Firebase not configured',
        tag: 'RemoteConfig',
      );
      return const {};
    }

    final prefs = await SharedPreferences.getInstance();

    // Check if force refresh is pending
    final shouldForce = force || _forceRefreshPending;
    if (_forceRefreshPending) {
      _forceRefreshPending = false;
      LogService.instance.debug(
        '[RemoteConfig] Force refresh triggered',
        tag: 'RemoteConfig',
      );
    }

    if (!shouldForce) {
      final lastFetch = prefs.getInt(_keyLastFetchTime) ?? 0;
      final now = DateTime.now().millisecondsSinceEpoch;
      if (now - lastFetch < _minFetchInterval.inMilliseconds) {
        final cached = _readCachedEntries(prefs);
        if (cached.isNotEmpty) return cached;
      }
    }

    try {
      final (fid, token) = await _ensureInstallation(prefs);
      final entries = await _fetchFromServer(fid, token);

      await prefs.setString(_keyEntries, jsonEncode(entries));
      await prefs.setInt(
        _keyLastFetchTime,
        DateTime.now().millisecondsSinceEpoch,
      );

      return entries;
    } catch (e) {
      LogService.instance.warning(
        '[RemoteConfig] Fetch failed, falling back to cache: $e',
        tag: 'RemoteConfig',
      );
      return _readCachedEntries(prefs);
    }
  }

  Future<String> getString(String key) async {
    final entries = await fetchEntries();
    return entries[key] ?? '';
  }

  Map<String, String> _readCachedEntries(SharedPreferences prefs) {
    final raw = prefs.getString(_keyEntries);
    if (raw == null || raw.isEmpty) return const {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return const {};
      return decoded.map((k, v) => MapEntry(k, v.toString()));
    } catch (e) {
      LogService.instance.warning(
        '[RemoteConfig] Failed to parse cached entries: $e',
        tag: 'RemoteConfig',
      );
      return const {};
    }
  }

  Future<(String, String)> _ensureInstallation(
    SharedPreferences prefs,
  ) async {
    final cachedFid = prefs.getString(_keyFid);
    final cachedToken = prefs.getString(_keyToken);

    if (cachedFid != null &&
        cachedFid.isNotEmpty &&
        cachedToken != null &&
        cachedToken.isNotEmpty) {
      return (cachedFid, cachedToken);
    }

    final fid = _generateFid();
    final response = await _dio.post(
      '$_installationsBase/projects/${FirebaseConfig.projectId}/installations',
      options: Options(
        headers: {
          'Content-Type': 'application/json',
          'Accept': 'application/json',
          'x-goog-api-key': FirebaseConfig.apiKey,
        },
        contentType: 'application/json',
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
      data: {
        'fid': fid,
        'appId': FirebaseConfig.appId,
        'authVersion': 'FIS_v2',
        'sdkVersion': 'w:0.0.0',
      },
    );

    if (response.statusCode != 200 && response.statusCode != 201) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final data = response.data as Map<String, dynamic>;
    final serverFid = data['fid'] as String? ?? '';
    final authToken =
        (data['authToken'] as Map<String, dynamic>?)?['token'] as String? ?? '';
    final refreshToken = data['refreshToken'] as String? ?? '';

    if (serverFid.isEmpty || authToken.isEmpty) {
      throw StateError('Firebase installation response missing fid/token');
    }

    await prefs.setString(_keyFid, serverFid);
    await prefs.setString(_keyToken, authToken);
    if (refreshToken.isNotEmpty) {
      await prefs.setString(_keyRefreshToken, refreshToken);
    }

    return (serverFid, authToken);
  }

  /// FID: 22-char base64url string starting with c–f (Firebase SDK rule).
  static String _generateFid() {
    final random = Random.secure();
    final bytes = List<int>.generate(17, (_) => random.nextInt(256));
    bytes[0] = 0x70 + (bytes[0] % 0x10);
    final encoded = base64Url.encode(bytes).replaceAll('=', '');
    return encoded.substring(0, 22);
  }

  Future<Map<String, String>> _fetchFromServer(String fid, String token) async {
    final response = await _dio.post(
      '$_remoteConfigBase/projects/${FirebaseConfig.projectId}'
      '/namespaces/firebase:fetch'
      '?key=${FirebaseConfig.apiKey}',
      options: Options(
        headers: {
          'x-goog-api-key': FirebaseConfig.apiKey,
          'X-Goog-Firebase-Installations-Auth': token,
          'Content-Type': 'application/json',
        },
        contentType: 'application/json',
        receiveTimeout: const Duration(seconds: 10),
        sendTimeout: const Duration(seconds: 10),
      ),
      data: {
        'appInstanceId': fid,
        'appInstanceIdToken': token,
        'appId': FirebaseConfig.appId,
        'sdkVersion': 'w:0.0.0',
        'languageCode': 'en',
      },
    );

    if (response.statusCode != 200) {
      throw DioException(
        requestOptions: response.requestOptions,
        response: response,
        type: DioExceptionType.badResponse,
      );
    }

    final data = response.data as Map<String, dynamic>;
    final entries = data['entries'];
    if (entries is! Map<String, dynamic>) return const {};

    return entries.map((k, v) => MapEntry(k, v.toString()));
  }

  Future<void> clearCache() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyFid);
    await prefs.remove(_keyToken);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyEntries);
    await prefs.remove(_keyLastFetchTime);
  }
}
