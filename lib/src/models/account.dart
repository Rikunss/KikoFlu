import 'package:equatable/equatable.dart';
import '../utils/security_utils.dart';

class Account extends Equatable {
  final int? id;
  final String username;
  final String password;
  final String host;
  final bool isActive;
  final String? serverCookie;
  final DateTime? createdAt;
  final DateTime? lastUsedAt;

  const Account({
    this.id,
    required this.username,
    required this.password,
    required this.host,
    this.isActive = false,
    this.serverCookie,
    this.createdAt,
    this.lastUsedAt,
  });

  factory Account.fromMap(Map<String, dynamic> map) {
    return Account(
      id: map['id'] as int?,
      username: map['username'] as String,
      password: map['password'] as String,
      host: map['host'] as String,
      isActive: (map['isActive'] as int) == 1,
      serverCookie: map['serverCookie'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : null,
      lastUsedAt: map['lastUsedAt'] != null
          ? DateTime.parse(map['lastUsedAt'] as String)
          : null,
    );
  }

  /// Create Account from database map, decrypting the password.
  static Future<Account> fromMapDecrypted(Map<String, dynamic> map) async {
    final encryptedPassword = map['password'] as String;
    final password = await SecurityUtils.decrypt(encryptedPassword);
    return Account(
      id: map['id'] as int?,
      username: map['username'] as String,
      password: password,
      host: map['host'] as String,
      isActive: (map['isActive'] as int) == 1,
      serverCookie: map['serverCookie'] as String?,
      createdAt: map['createdAt'] != null
          ? DateTime.parse(map['createdAt'] as String)
          : null,
      lastUsedAt: map['lastUsedAt'] != null
          ? DateTime.parse(map['lastUsedAt'] as String)
          : null,
    );
  }

  /// Convert to database map, encrypting the password.
  Future<Map<String, dynamic>> toMapEncrypted() async {
    final encryptedPassword = await SecurityUtils.encrypt(password);
    return {
      'id': id,
      'username': username,
      'password': encryptedPassword,
      'host': host,
      'isActive': isActive ? 1 : 0,
      'serverCookie': serverCookie,
      'createdAt': createdAt?.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  /// WARNING: Returns plaintext password. Use [toMapEncrypted] for database writes.
  /// Only safe for in-memory operations where password is already needed.
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'username': username,
      'password': password,
      'host': host,
      'isActive': isActive ? 1 : 0,
      'serverCookie': serverCookie,
      'createdAt': createdAt?.toIso8601String(),
      'lastUsedAt': lastUsedAt?.toIso8601String(),
    };
  }

  Account copyWith({
    int? id,
    String? username,
    String? password,
    String? host,
    bool? isActive,
    String? serverCookie,
    DateTime? createdAt,
    DateTime? lastUsedAt,
  }) {
    return Account(
      id: id ?? this.id,
      username: username ?? this.username,
      password: password ?? this.password,
      host: host ?? this.host,
      isActive: isActive ?? this.isActive,
      serverCookie: serverCookie ?? this.serverCookie,
      createdAt: createdAt ?? this.createdAt,
      lastUsedAt: lastUsedAt ?? this.lastUsedAt,
    );
  }

  @override
  List<Object?> get props => [
        id,
        username,
        password,
        host,
        isActive,
        serverCookie,
        createdAt,
        lastUsedAt,
      ];

  @override
  String toString() =>
      'Account(id: $id, username: $username, host: $host, isActive: $isActive, serverCookie: $serverCookie)';
}