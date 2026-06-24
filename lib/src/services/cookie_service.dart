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
}
