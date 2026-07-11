import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
import 'log_service.dart';
import 'storage_service.dart';

/// Service for managing app lock (biometric + PIN).
///
/// Persistence is done via SharedPreferences:
/// - `app_lock_enabled` (bool) — master toggle
/// - `app_lock_pin_hash` (String) — SHA256 hash of PIN (hex)
/// - `app_lock_biometric` (bool) — use biometric when available
class AppLockService {
  AppLockService._();
  static final AppLockService instance = AppLockService._();

  static const _enabledKey = 'app_lock_enabled';
  static const _pinHashKey = 'app_lock_pin_hash';
  static const _biometricKey = 'app_lock_biometric';
  static const _autoLockTimeoutKey = 'app_lock_auto_lock_timeout';
  static const _defaultTimeout = 5;

  int _lockGeneration = 0;
  DateTime? _backgroundedAt;

  final LocalAuthentication _localAuth = LocalAuthentication();

  /// MethodChannel to notify the native Quick Settings tile to refresh.
  static const _tileChannel = MethodChannel('com.kikoeru.flutter/app_lock_tile');

  /// Whether app lock is enabled.
  bool get isEnabled => StorageService.getBool(_enabledKey) ?? false;

  /// Whether biometric is the preferred method (vs PIN-only).
  bool get isBiometricEnabled => StorageService.getBool(_biometricKey) ?? false;

  /// Whether a PIN has been set.
  bool get hasPin {
    final hash = StorageService.getString(_pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  /// Check if device has biometric hardware enrolled (Face ID / fingerprint).
  /// Supports Android (fingerprint/face), iOS (Face ID/Touch ID),
  /// Windows (Windows Hello), and macOS (Touch ID).
  ///
  /// Includes a 3-second timeout to avoid hanging on devices where the
  /// `local_auth` plugin doesn't respond (common on some MIUI/Xiaomi ROMs).
  Future<bool> canUseBiometric() async {
    if (!Platform.isAndroid && !Platform.isIOS &&
        !Platform.isWindows && !Platform.isMacOS) {
      return false;
    }
    try {
      final canCheck = await _localAuth.canCheckBiometrics
          .timeout(const Duration(seconds: 3));
      if (!canCheck) return false;
      final enrolled = await _localAuth.isDeviceSupported()
          .timeout(const Duration(seconds: 3));
      return enrolled;
    } on TimeoutException {
      LogService.instance.warning('[AppLockService] canUseBiometric timed out — device may not respond', tag: 'AppLock');
      return false;
    } catch (e) {
      LogService.instance.warning('[AppLockService] canUseBiometric error: $e', tag: 'AppLock');
      return false;
    }
  }

  /// Available biometric types (for UI display).
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }

  /// Prompt the user for biometric authentication.
  /// Returns `true` on success.
  Future<bool> authenticateBiometric({String reason = 'Unlock KikoFlu'}) async {
    try {
      final useBiometricOnly = Platform.isAndroid || Platform.isIOS;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: useBiometricOnly,
        persistAcrossBackgrounding: useBiometricOnly,
      );
    } catch (e) {
      LogService.instance.warning('[AppLockService] authenticateBiometric error: $e', tag: 'AppLock');
      return false;
    }
  }

  /// Simple SHA256 hash for PIN (hex-encoded).
  /// Note: This is NOT cryptographically secure for production security.
  /// For a music player app, it's sufficient to deter casual access.
  String _hashPin(String pin) {
    final bytes = utf8.encode('kikoflu_${pin}_salt!');
    final hash = _simpleHash(bytes);
    return hash;
  }

  String _simpleHash(List<int> bytes) {
    var h = List<int>.filled(32, 0);
    for (var i = 0; i < bytes.length; i++) {
      h[i % 32] = (h[i % 32] + bytes[i] + (i * 7) % 256) & 0xFF;
      for (var j = 0; j < 3; j++) {
        for (var k = 0; k < 31; k++) {
          h[k] = (h[k] ^ ((h[k + 1] << 3) & 0xFF)) & 0xFF;
        }
      }
    }
    return h.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }

  /// Verify a PIN against the stored hash.
  bool verifyPin(String pin) {
    final storedHash = StorageService.getString(_pinHashKey);
    if (storedHash == null || storedHash.isEmpty) return false;
    return _hashPin(pin) == storedHash;
  }

  /// Set (or change) the PIN. Stores the hash.
  Future<void> setPin(String pin) async {
    await StorageService.setString(_pinHashKey, _hashPin(pin));
  }

  /// Remove PIN.
  Future<void> removePin() async {
    await StorageService.remove(_pinHashKey);
  }

  /// Request the native Android Quick Settings tile to refresh its state.
  /// Safe to call on any platform — silently ignored on non-Android.
  ///
  /// Uses a 2-second timeout to avoid hanging on devices where the
  /// MethodChannel has no registered handler (e.g., MIUI/Xiaomi ROMs
  /// where `invokeMethod` may silently block instead of throwing
  /// `MissingPluginException`).
  Future<void> _updateTile() async {
    if (!Platform.isAndroid) return;
    try {
      await _tileChannel
          .invokeMethod('updateAppLockTile')
          .timeout(const Duration(seconds: 2));
    } catch (_) {
    }
  }

  /// Enable app lock with biometric and/or PIN.
  /// [biometric] — use biometric when available (falls back to PIN).
  /// [pin] — PIN code (required if biometric unavailable OR as fallback).
  Future<void> enable({
    bool biometric = true,
    String? pin,
  }) async {
    if (pin != null && pin.isNotEmpty) {
      await setPin(pin);
    }
    await StorageService.setBool(_biometricKey, biometric);
    await StorageService.setBool(_enabledKey, true);
    await _updateTile();
  }

  /// Disable app lock entirely.
  Future<void> disable() async {
    await StorageService.setBool(_enabledKey, false);
    await StorageService.setBool(_biometricKey, false);
    await removePin();
    await _updateTile();
  }

  /// Update biometric-only preference.
  Future<void> setBiometricEnabled(bool value) async {
    await StorageService.setBool(_biometricKey, value);
    await _updateTile();
  }

  /// Auto-lock timeout in minutes (0 = immediately, -1 = never).
  int get autoLockTimeoutMinutes =>
      StorageService.getInt(_autoLockTimeoutKey) ?? _defaultTimeout;

  /// Set auto-lock timeout.
  Future<void> setAutoLockTimeout(int minutes) async {
    await StorageService.setInt(_autoLockTimeoutKey, minutes);
    await _updateTile();
  }

  /// Current lock generation — incrementing forces a fresh lock screen.
  int get lockGeneration => _lockGeneration;

  /// Mark the moment the app went to background.
  void notifyAppBackgrounded() {
    _backgroundedAt = DateTime.now();
  }

  /// Called when the app returns to foreground.
  /// Returns `true` if the app should auto-relock.
  bool notifyAppForegrounded() {
    final timeout = autoLockTimeoutMinutes;
    if (timeout < 0) return false;

    if (_backgroundedAt == null) {
      return false;
    }

    final elapsed = DateTime.now().difference(_backgroundedAt!);
    _backgroundedAt = null;

    if (timeout == 0) {
      _lockGeneration++;
      return true;
    }

    if (elapsed.inMinutes >= timeout) {
      _lockGeneration++;
      return true;
    }
    return false;
  }
}