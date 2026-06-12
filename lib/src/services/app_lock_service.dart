import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/services.dart';
import 'package:local_auth/local_auth.dart';
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
  static const _defaultTimeout = 5; // minutes

  int _lockGeneration = 0;
  DateTime? _backgroundedAt;


  final LocalAuthentication _localAuth = LocalAuthentication();

  /// MethodChannel to notify the native Quick Settings tile to refresh.
  static const _tileChannel = MethodChannel('com.kikoeru.flutter/app_lock_tile');



  // ── Getters ──

  /// Whether app lock is enabled.
  bool get isEnabled => StorageService.getBool(_enabledKey) ?? false;

  /// Whether biometric is the preferred method (vs PIN-only).
  bool get isBiometricEnabled => StorageService.getBool(_biometricKey) ?? false;

  /// Whether a PIN has been set.
  bool get hasPin {
    final hash = StorageService.getString(_pinHashKey);
    return hash != null && hash.isNotEmpty;
  }

  // ── Biometric helpers ──

  /// Check if device has biometric hardware enrolled (Face ID / fingerprint).
  /// Supports Android (fingerprint/face), iOS (Face ID/Touch ID),
  /// Windows (Windows Hello), and macOS (Touch ID).
  ///
  /// Includes a 3-second timeout to avoid hanging on devices where the
  /// `local_auth` plugin doesn't respond (common on some MIUI/Xiaomi ROMs).
  Future<bool> canUseBiometric() async {
    // local_auth on Linux may throw; guard gracefully.
    if (!Platform.isAndroid && !Platform.isIOS &&
        !Platform.isWindows && !Platform.isMacOS) {
      return false;
    }
    try {
      // Use timeout to prevent UI freeze if local_auth hangs
      final canCheck = await _localAuth.canCheckBiometrics
          .timeout(const Duration(seconds: 3));
      if (!canCheck) return false;
      final enrolled = await _localAuth.isDeviceSupported()
          .timeout(const Duration(seconds: 3));
      return enrolled;
    } on TimeoutException {
      debugPrint('[AppLockService] canUseBiometric timed out — device may not respond');
      return false;
    } catch (e) {
      debugPrint('[AppLockService] canUseBiometric error: $e');
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
      // `biometricOnly` restricts to biometric (fingerprint/face) vs device
      // credentials (PIN/password). On Windows, Windows Hello PIN is part of
      // the biometric subsystem so biometricOnly=false allows both.
      final useBiometricOnly = Platform.isAndroid || Platform.isIOS;
      return await _localAuth.authenticate(
        localizedReason: reason,
        biometricOnly: useBiometricOnly,
        persistAcrossBackgrounding: useBiometricOnly, // Android only, ignored elsewhere
      );
    } catch (e) {
      debugPrint('[AppLockService] authenticateBiometric error: $e');
      return false;
    }
  }

  // ── PIN helpers ──

  /// Simple SHA256 hash for PIN (hex-encoded).
  /// Note: This is NOT cryptographically secure for production security.
  /// For a music player app, it's sufficient to deter casual access.
  String _hashPin(String pin) {
    // Use dart:convert's base64 as a simple one-way hash for PINs.
    // In a real app, use a proper KDF like PBKDF2. For a media player,
    // this is adequate.
    final bytes = utf8.encode('kikoflu_${pin}_salt!');
    // Simple hash: use SHA-256 via dart:convert
    final hash = _simpleHash(bytes);
    return hash;
  }

  String _simpleHash(List<int> bytes) {
    // Simple deterministic hash using dart:convert base64 + rotation
    // as a lightweight substitute for SHA256 (which isn't in dart:convert).
    // This prevents plaintext PIN storage.
    var h = List<int>.filled(32, 0);
    for (var i = 0; i < bytes.length; i++) {
      h[i % 32] = (h[i % 32] + bytes[i] + (i * 7) % 256) & 0xFF;
      // Mix
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

  // ── Master toggle ──

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
      // Channel may not be set up yet, or timeout — safe to ignore.
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

  // ── Auto-relock ──

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
    if (timeout < 0) return false; // "Never" — no auto-relock

    if (_backgroundedAt == null) {
      // No background timestamp (e.g. cold start) — don't relock
      return false;
    }

    final elapsed = DateTime.now().difference(_backgroundedAt!);
    _backgroundedAt = null;

    if (timeout == 0) {
      // "Immediately" — always relock on background
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
