import 'package:hive_flutter/hive_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'dart:convert';
import 'log_service.dart';

final _log = LogService.instance;

class StorageService {
  static late Box _settingsBox;
  static late Box _userBox;
  static late Box _cacheBox;
  static late SharedPreferences _prefs;
  static const _secureStorage = FlutterSecureStorage();

  static const _secureKeys = {'auth_token'};

  static Future<void> init() async {
    _settingsBox = await Hive.openBox('settings');
    _userBox = await Hive.openBox('users');
    _cacheBox = await Hive.openBox('cache');

    _prefs = await SharedPreferences.getInstance();

    await _migrateSecureKeys();
  }

  /// Migrate sensitive keys from SharedPreferences to FlutterSecureStorage.
  static Future<void> _migrateSecureKeys() async {
    for (final key in _secureKeys) {
      final value = _prefs.getString(key);
      if (value != null && value.isNotEmpty) {
        await _secureStorage.write(key: key, value: value);
        await _prefs.remove(key);
      }
    }
  }

  static Future<void> setSetting(String key, dynamic value) async {
    await _settingsBox.put(key, value);
  }

  static T? getSetting<T>(String key, {T? defaultValue}) {
    return _settingsBox.get(key, defaultValue: defaultValue) as T?;
  }

  static Future<void> removeSetting(String key) async {
    await _settingsBox.delete(key);
  }

  static Future<void> setUser(String key, dynamic value) async {
    await _userBox.put(key, value);
  }

  static T? getUser<T>(String key, {T? defaultValue}) {
    return _userBox.get(key, defaultValue: defaultValue) as T?;
  }

  static Future<void> removeUser(String key) async {
    await _userBox.delete(key);
  }

  static List<String> getAllUserKeys() {
    return _userBox.keys.cast<String>().toList();
  }

  static Future<void> setCache(String key, dynamic value) async {
    await _cacheBox.put(key, value);
  }

  static T? getCache<T>(String key, {T? defaultValue}) {
    return _cacheBox.get(key, defaultValue: defaultValue) as T?;
  }

  static Future<void> removeCache(String key) async {
    await _cacheBox.delete(key);
  }

  static Future<void> clearCache() async {
    await _cacheBox.clear();
  }

  static Future<void> setString(String key, String value) async {
    if (_secureKeys.contains(key)) {
      await _secureStorage.write(key: key, value: value);
    } else {
      await _prefs.setString(key, value);
    }
  }

  static String? getString(String key) {
    if (_secureKeys.contains(key)) {
      return null;
    }
    return _prefs.getString(key);
  }

  /// Async version that can read from secure storage.
  static Future<String?> getStringAsync(String key) async {
    if (_secureKeys.contains(key)) {
      return await _secureStorage.read(key: key);
    }
    return _prefs.getString(key);
  }

  static Future<void> setBool(String key, bool value) async {
    await _prefs.setBool(key, value);
  }

  static bool? getBool(String key) {
    return _prefs.getBool(key);
  }

  static Future<void> setInt(String key, int value) async {
    await _prefs.setInt(key, value);
  }

  static int? getInt(String key) {
    return _prefs.getInt(key);
  }

  static Future<void> remove(String key) async {
    if (_secureKeys.contains(key)) {
      await _secureStorage.delete(key: key);
    } else {
      await _prefs.remove(key);
    }
  }

  static Future<void> clear() async {
    await _prefs.clear();
  }

  static Future<SharedPreferences> getPrefs() async {
    return _prefs;
  }

  static Future<void> setMap(String key, Map<String, dynamic> value) async {
    await _prefs.setString(key, jsonEncode(value));
  }

  static Map<String, dynamic>? getMap(String key) {
    final jsonString = _prefs.getString(key);
    if (jsonString != null) {
      try {
        return jsonDecode(jsonString) as Map<String, dynamic>;
      } catch (e) {
        _log.error('Error decoding JSON for key $key: $e');
        return null;
      }
    }
    return null;
  }

  /// Close all open Hive boxes so their files can be safely copied.
  static Future<void> closeBoxes() async {
    await _settingsBox.close();
    await _userBox.close();
    await _cacheBox.close();
  }

  /// Returns HTTP headers with server cookie if configured.
  /// @deprecated Use [CookieService.serverCookieHeaders] instead.
  /// Kept for backward compatibility during migration.
  static Map<String, String> get serverCookieHeaders {
    final cookie = getString('server_cookie');
    if (cookie != null && cookie.isNotEmpty) {
      return {'Cookie': cookie};
    }
    return {};
  }
}