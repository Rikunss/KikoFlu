import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Focused service for server cookie management.
///
/// Extracted from [StorageService] to break the coupling between HTTP/network
/// code and the generic key-value storage layer. Network files that need cookie
/// headers import this service instead of [StorageService].
///
/// Uses FlutterSecureStorage for secure cookie persistence.
class CookieService {
  static const String _cookieKey = 'server_cookie';
  static const _secureStorage = FlutterSecureStorage();
  static String? _cachedCookie;

  /// Initialize the service. Reads cached cookie from secure storage.
  static Future<void> init() async {
    _cachedCookie = await _secureStorage.read(key: _cookieKey);
  }

  /// Ensure the service is initialized. Safe to call multiple times.
  static Future<void> ensureInitialized() async {
    _cachedCookie ??= await _secureStorage.read(key: _cookieKey);
  }

  /// Synchronous getter for HTTP cookie headers.
  /// Returns an empty map if no cookie is configured.
  /// Safe to call from Dio interceptors (non-async context).
  static Map<String, String> get serverCookieHeaders {
    final cookie = _cachedCookie;
    if (cookie != null && cookie.isNotEmpty) {
      return {'Cookie': cookie};
    }
    return {};
  }

  /// Get the stored server cookie value.
  static Future<String?> getCookie() async {
    _cachedCookie = await _secureStorage.read(key: _cookieKey);
    return _cachedCookie;
  }

  /// Store a server cookie value.
  /// Pass `null` to clear the stored cookie.
  static Future<void> setCookie(String? cookie) async {
    if (cookie != null && cookie.isNotEmpty) {
      await _secureStorage.write(key: _cookieKey, value: cookie);
      _cachedCookie = cookie;
    } else {
      await _secureStorage.delete(key: _cookieKey);
      _cachedCookie = null;
    }
  }

  /// Remove the stored server cookie.
  static Future<void> clearCookie() async {
    await _secureStorage.delete(key: _cookieKey);
    _cachedCookie = null;
  }

  /// Complete HTTP headers for cover image requests, including auth, language,
  /// and anti-bot headers required by ASMR.one official server.
  ///
  /// Pass [token] to include the `Authorization: Bearer` header.
  /// Returns an empty map if no cookie is configured and no token is provided
  /// (callers should still pass these headers to satisfy server checks).
  static Map<String, String> coverHttpHeaders({String? token}) {
    final headers = <String, String>{};

    // Cookie (from server login session)
    final cookie = _cachedCookie;
    if (cookie != null && cookie.isNotEmpty) {
      headers['Cookie'] = cookie;
    }

    // Required for ASMR.one — blocks non-Chinese Accept-Language
    headers['Accept-Language'] = 'zh-CN,zh;q=0.9';

    // Standard browser headers for anti-bot protection
    headers['User-Agent'] =
        'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 '
        '(KHTML, like Gecko) Chrome/142.0.0.0 Safari/537.36';
    headers['Referer'] = 'https://www.asmr.one/';
    headers['Origin'] = 'https://www.asmr.one';

    // Auth token — the server may reject query-param tokens
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }

    return headers;
  }
}
