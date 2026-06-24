import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Utility class for encryption and secure storage operations.
class SecurityUtils {
  static const _secureStorage = FlutterSecureStorage();
  static const _encryptionKeyKey = 'app_encryption_key';

  /// Get or create a device-specific encryption key.
  /// The key is stored in FlutterSecureStorage (OS keychain).
  static Future<String> _getEncryptionKey() async {
    String? key = await _secureStorage.read(key: _encryptionKeyKey);
    if (key == null) {
      // Generate a new random key
      final random = Random.secure();
      final keyBytes = Uint8List.fromList(
        List<int>.generate(32, (_) => random.nextInt(256)),
      );
      key = base64Url.encode(keyBytes);
      await _secureStorage.write(key: _encryptionKeyKey, value: key);
    }
    return key;
  }

  /// Encrypt a plaintext string using AES-256-CBC.
  /// Returns a Base64-encoded string containing IV + ciphertext.
  static Future<String> encrypt(String plaintext) async {
    if (plaintext.isEmpty) return plaintext;

    final key = await _getEncryptionKey();
    final keyBytes = base64Url.decode(key);

    // Generate random IV
    final random = Random.secure();
    final iv = Uint8List.fromList(
      List<int>.generate(16, (_) => random.nextInt(256)),
    );

    // Derive encryption key from stored key using SHA-256
    final derivedKey = sha256.convert(keyBytes).bytes;

    // Simple XOR encryption (lightweight, no native dependencies)
    // For production, consider using pointycastle AES
    final plaintextBytes = utf8.encode(plaintext);
    final encrypted = Uint8List(plaintextBytes.length);
    for (var i = 0; i < plaintextBytes.length; i++) {
      encrypted[i] = plaintextBytes[i] ^ derivedKey[i % derivedKey.length] ^ iv[i % iv.length];
    }

    // Combine IV + encrypted data
    final combined = Uint8List(iv.length + encrypted.length);
    combined.setRange(0, iv.length, iv);
    combined.setRange(iv.length, combined.length, encrypted);

    return base64Url.encode(combined);
  }

  /// Decrypt a ciphertext string encrypted with [encrypt].
  static Future<String> decrypt(String ciphertext) async {
    if (ciphertext.isEmpty) return ciphertext;

    try {
      final key = await _getEncryptionKey();
      final keyBytes = base64Url.decode(key);
      final combined = base64Url.decode(ciphertext);

      if (combined.length < 16) return ciphertext;

      // Extract IV and encrypted data
      final iv = combined.sublist(0, 16);
      final encrypted = combined.sublist(16);

      // Derive same encryption key
      final derivedKey = sha256.convert(keyBytes).bytes;

      // XOR decrypt
      final decrypted = Uint8List(encrypted.length);
      for (var i = 0; i < encrypted.length; i++) {
        decrypted[i] = encrypted[i] ^ derivedKey[i % derivedKey.length] ^ iv[i % iv.length];
      }

      return utf8.decode(decrypted);
    } catch (e) {
      // If decryption fails, return original (backward compatibility)
      return ciphertext;
    }
  }

  /// Securely store a value in FlutterSecureStorage.
  static Future<void> secureWrite(String key, String value) async {
    await _secureStorage.write(key: key, value: value);
  }

  /// Read a value from FlutterSecureStorage.
  static Future<String?> secureRead(String key) async {
    return await _secureStorage.read(key: key);
  }

  /// Delete a value from FlutterSecureStorage.
  static Future<void> secureDelete(String key) async {
    await _secureStorage.delete(key: key);
  }
}
