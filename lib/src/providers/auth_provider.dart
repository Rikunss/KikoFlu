import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/user.dart';
import '../models/account.dart';
import '../services/kikoeru_api_service.dart';
import '../services/storage_service.dart';
import '../services/account_database.dart';
import '../services/log_service.dart';
import '../utils/server_utils.dart';

// Kikoeru API Service Provider
final kikoeruApiServiceProvider = Provider<KikoeruApiService>((ref) {
  return KikoeruApiService();
});

// Auth state
class AuthState extends Equatable {
  final User? currentUser;
  final String? token;
  final String? host;
  final bool isLoading;
  final String? error;
  final bool isLoggedIn;

  const AuthState({
    this.currentUser,
    this.token,
    this.host,
    this.isLoading = false,
    this.error,
    this.isLoggedIn = false,
  });

  AuthState copyWith({
    User? currentUser,
    String? token,
    String? host,
    bool? isLoading,
    String? error,
    bool? isLoggedIn,
  }) {
    return AuthState(
      currentUser: currentUser ?? this.currentUser,
      token: token ?? this.token,
      host: host ?? this.host,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
    );
  }

  @override
  List<Object?> get props =>
      [currentUser, token, host, isLoading, error, isLoggedIn];
}

// Auth notifier
class AuthNotifier extends StateNotifier<AuthState> {
  final KikoeruApiService _apiService;

  AuthNotifier(this._apiService) : super(const AuthState()) {
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    try {
      LogService.instance.debug('[Auth] Loading current user...', tag: 'Network');

      // First try to load from storage (faster)
      final token = StorageService.getString('auth_token');
      final host = StorageService.getString('server_host');
      final userJson = StorageService.getMap('current_user');

      LogService.instance.debug('[Auth] Stored token: ${token != null ? "exists" : "null"}', tag: 'Network');
      LogService.instance.debug('[Auth] Stored host: $host', tag: 'Network');

      if (token != null && host != null) {
        _apiService.init(token, host);

        User? user;
        if (userJson != null) {
          user = User.fromJson(userJson);
          LogService.instance.debug('[Auth] Loaded user from storage: ${user.name}', tag: 'Network');
        }

        state = state.copyWith(
          token: token,
          host: host,
          currentUser: user,
          isLoggedIn: true,
        );

        // Validate token by fetching user info
        try {
          LogService.instance.debug('[Auth] Validating token...', tag: 'Network');
          await _refreshUserInfo();
          LogService.instance.debug('[Auth] Token is valid, user logged in successfully', tag: 'Network');
          return; // Token is valid, we're done
        } catch (e) {
          LogService.instance.warning('[Auth] Token validation failed: $e', tag: 'Network');
          // Token is invalid, try to re-login with saved account
        }
      }

      // If no valid token, try to load from database and re-login
      LogService.instance.debug('[Auth] Checking database for active account...', tag: 'Network');
      final activeAccount = await AccountDatabase.instance.getActiveAccount();

      if (activeAccount != null) {
        // Silently re-login with saved credentials
        LogService.instance.debug(
            '[Auth] Found active account in database: ${activeAccount.username}', tag: 'Network');
        LogService.instance.debug('[Auth] Re-logging in with saved account...', tag: 'Network');

        _apiService.init('', activeAccount.host);

        final success = await login(
          activeAccount.username,
          activeAccount.password,
          activeAccount.host,
          activeAccount.serverCookie,
          silent: true, // Don't show loading state
        );

        if (success) {
          LogService.instance.debug('[Auth] Re-login successful', tag: 'Network');
          return;
        } else {
          LogService.instance.warning('[Auth] Re-login failed due to network or server issue', tag: 'Network');
          // 网络问题导致登录失败，但我们有缓存的账户信息
          // 允许用户以离线模式进入应用（可以使用本地下载内容）
          LogService.instance.warning('[Auth] Entering offline mode with cached account', tag: 'Network');

          // 使用缓存的账户信息设置基本状态
          _apiService.init('', activeAccount.host);

          state = state.copyWith(
            currentUser: User(
              name: activeAccount.username,
              group: 'guest',
              loggedIn: false, // 标记为未完全登录（离线模式）
              host: activeAccount.host,
              password: activeAccount.password,
              token: '',
              lastUpdateTime: DateTime.now(),
            ),
            host: activeAccount.host,
            token: '',
            isLoggedIn: false, // 离线模式
            error: '网络连接失败，以离线模式启动',
          );

          LogService.instance.debug('[Auth] Offline mode activated', tag: 'Network');
          return;
        }
      } else {
        LogService.instance.debug('[Auth] No active account found in database', tag: 'Network');
      }

      // If all fails, logout
      LogService.instance.debug('[Auth] No valid authentication found, logging out', tag: 'Network');
      await logout();
    } catch (e) {
      LogService.instance.error('[Auth] Failed to load saved auth: $e', tag: 'Network');

      // 在异常情况下，也尝试检查是否有缓存账户
      try {
        final activeAccount = await AccountDatabase.instance.getActiveAccount();
        if (activeAccount != null) {
          LogService.instance.warning(
              '[Auth] Exception occurred but found cached account, entering offline mode', tag: 'Network');

          _apiService.init('', activeAccount.host);

          state = state.copyWith(
            currentUser: User(
              name: activeAccount.username,
              group: 'guest',
              loggedIn: false,
              host: activeAccount.host,
              password: activeAccount.password,
              token: '',
              lastUpdateTime: DateTime.now(),
            ),
            host: activeAccount.host,
            token: '',
            isLoggedIn: false,
            error: '网络连接失败，以离线模式启动',
          );

          return;
        }
      } catch (dbError) {
        LogService.instance.error('[Auth] Failed to check database: $dbError', tag: 'Network');
      }

      await logout();
    }
  }

  Future<bool> login(
    String username,
    String password,
    String host,
    String? serverCookie, {
    bool silent = false,
  }) async {
    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    if (serverCookie != null && serverCookie.isNotEmpty) {
      await StorageService.setString('server_cookie', serverCookie);
    } else {
      await StorageService.remove('server_cookie');
    }

    try {
      LogService.instance.debug(
          '[Auth] Login attempt - username: $username, host: $host, silent: $silent', tag: 'Network');

      // 删除主机地址末尾的斜杠，以免请求资源时出现地址错误
      if (host.endsWith("/")) {
        host = host.substring(0, host.length - 1);
      }

      // Initialize API service with empty token first
      _apiService.init('', host);

      // Attempt login
      final response = await _apiService.login(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      LogService.instance.debug('[Auth] Login successful, received token', tag: 'Network');

      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      LogService.instance.debug('[Auth] Normalized host: $normalizedHost', tag: 'Network');

      // Update API service with real token and normalized host
      _apiService.init(token, normalizedHost);

      // Get user info from login response or fetch it separately
      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        // Use user info from login response
        userInfo = response;
      } else {
        // Fetch user info separately
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field to ensure proper authentication
      // For self-hosted servers, skip this check as they may not return this field
      if (ServerUtils.isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Login failed: User not logged in');
      }

      // Create complete user object with credentials and token (using normalized host)
      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        serverCookie: serverCookie,
        lastUpdateTime: DateTime.now(),
      );

      // Save to storage (using normalized host)
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

      // Save or update account in database
      try {
        final existingAccounts =
            await AccountDatabase.instance.getAllAccounts();
        final existingAccount = existingAccounts.firstWhere(
          (acc) => acc.username == username && acc.host == normalizedHost,
          orElse: () => Account(
            username: username,
            password: password,
            host: normalizedHost,
            serverCookie: serverCookie,
            isActive: true,
            createdAt: DateTime.now(),
          ),
        );

        if (existingAccount.id != null) {
          // Update existing account
          await AccountDatabase.instance.updateAccount(
            existingAccount.copyWith(
              password: password,
              isActive: true,
              serverCookie: serverCookie,
              lastUsedAt: DateTime.now(),
            ),
          );
        } else {
          // Create new account
          await AccountDatabase.instance.createAccount(
            Account(
              username: username,
              password: password,
              host: normalizedHost,
              serverCookie: serverCookie,
              isActive: true,
              createdAt: DateTime.now(),
              lastUsedAt: DateTime.now(),
            ),
          );
        }
        LogService.instance.debug('[Auth] Account saved to database', tag: 'Network');
      } catch (e) {
        LogService.instance.error('[Auth] Failed to save account to database: $e', tag: 'Network');
      }

      state = state.copyWith(
        currentUser: authenticatedUser,
        token: token,
        host: normalizedHost,
        isLoading: false,
        isLoggedIn: true,
      );

      LogService.instance.debug('[Auth] Login completed, state updated', tag: 'Network');
      return true;
    } catch (e) {
      LogService.instance.error('[Auth] Login error: $e', tag: 'Network');

      if (!silent) {
        state = state.copyWith(
          isLoading: false,
          error: 'Login failed: ${e.toString()}',
        );
      }
      return false;
    }
  }

  Future<bool> register(String username, String password, String host,
      [String? serverCookie]) async {
    state = state.copyWith(isLoading: true, error: null);

    if (serverCookie != null && serverCookie.isNotEmpty) {
      await StorageService.setString('server_cookie', serverCookie);
    } else {
      await StorageService.remove('server_cookie');
    }

    try {
      // Initialize API service
      _apiService.init('', host);

      // Attempt registration
      final response = await _apiService.register(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      // Update API service with token and normalized host
      _apiService.init(token, normalizedHost);

      // Get user info from registration response or fetch it separately
      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        // Use user info from registration response
        userInfo = response;
      } else {
        // Fetch user info separately
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field to ensure proper authentication
      // For self-hosted servers, skip this check as they may not return this field
      if (ServerUtils.isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Registration failed: User not logged in');
      }

      // Create complete user object with credentials and token (using normalized host)
      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        serverCookie: serverCookie,
        lastUpdateTime: DateTime.now(),
      );

      // Save to storage (using normalized host)
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

      // Save account to database
      try {
        await AccountDatabase.instance.createAccount(
          Account(
            username: username,
            password: password,
            host: normalizedHost,
            isActive: true,
            serverCookie: serverCookie,
            createdAt: DateTime.now(),
            lastUsedAt: DateTime.now(),
          ),
        );
        LogService.instance.debug('[Auth] Registered account saved to database', tag: 'Network');
      } catch (e) {
        LogService.instance.error('[Auth] Failed to save registered account to database: $e', tag: 'Network');
      }

      state = state.copyWith(
        currentUser: authenticatedUser,
        token: token,
        host: normalizedHost,
        isLoading: false,
        isLoggedIn: true,
      );

      return true;
    } catch (e) {
      String errorMessage = 'Registration failed: ${e.toString()}';

      if (e is KikoeruApiException && e.originalError is DioException) {
        final dioError = e.originalError as DioException;
        if (dioError.response != null && dioError.response?.statusCode == 403) {
          final data = dioError.response?.data;
          if (data is Map && data['error'] != null) {
            errorMessage = data['error'];
          } else if (data is String) {
            try {
              final json = jsonDecode(data);
              if (json is Map && json['error'] != null) {
                errorMessage = json['error'];
              }
            } catch (_) {
              // Ignore json decode error
            }
          }
        }
      }

      state = state.copyWith(
        isLoading: false,
        error: errorMessage,
      );
      return false;
    }
  }

  Future<void> _refreshUserInfo() async {
    try {
      final userInfo = await _apiService.getUserInfo();
      final user = User.fromJson(userInfo);

      // For official servers, verify the loggedIn field
      // For self-hosted servers, skip this check as they may not return this field
      if (ServerUtils.isOfficialServer(state.host) && !user.loggedIn) {
        throw Exception('User not logged in');
      }

      await StorageService.setMap('current_user', user.toJson());

      state = state.copyWith(currentUser: user);
    } catch (e) {
      LogService.instance.error('[Auth] Failed to refresh user info: $e', tag: 'Network');
      // Rethrow the exception so caller can handle it
      rethrow;
    }
  }

  Future<void> updateHost(String host) async {
    if (state.token != null) {
      // Normalize host URL to include protocol
      String normalizedHost;
      if (host.startsWith('http://') || host.startsWith('https://')) {
        normalizedHost = host;
      } else {
        // For remote hosts, use HTTPS; for localhost, use HTTP
        if (host.contains('localhost') ||
            host.startsWith('127.0.0.1') ||
            host.startsWith('192.168.')) {
          normalizedHost = 'http://$host';
        } else {
          normalizedHost = 'https://$host';
        }
      }

      // 更新host时同步serverCookie配置
      final cookie = state.currentUser?.serverCookie;
      if (cookie != null && cookie.isNotEmpty) {
        await StorageService.setString('server_cookie', cookie);
      } else {
        await StorageService.remove('server_cookie');
      }

      _apiService.init(state.token!, normalizedHost);
      await StorageService.setString('server_host', normalizedHost);
      state = state.copyWith(host: normalizedHost);
    }
  }

  Future<void> logout() async {
    try {
      await StorageService.remove('auth_token');
      await StorageService.remove('server_host');
      await StorageService.remove('current_user');
      await StorageService.remove('server_cookie');
    } catch (e) {
      LogService.instance.error('[Auth] Failed to clear storage: $e', tag: 'Network');
    }

    state = const AuthState();
  }

  Future<void> switchUser(User user) async {
    final token = user.token;
    final host = user.host;
    final serverCookie = user.serverCookie;

    if (token != null && host != null) {
      LogService.instance.debug('[Auth] Switching user - username: ${user.name}, host: $host', tag: 'Network');

      if (serverCookie != null && serverCookie.isNotEmpty) {
        await StorageService.setString('server_cookie', serverCookie);
      } else {
        await StorageService.remove('server_cookie');
      }

      _apiService.init(token, host);
      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', host);
      await StorageService.setMap('current_user', user.toJson());

      state = state.copyWith(
        currentUser: user,
        token: token,
        host: host,
        isLoggedIn: true,
      );

      LogService.instance.debug('[Auth] User switched successfully', tag: 'Network');
    } else {
      throw Exception('Invalid user data: missing token or host');
    }
  }

  Future<List<User>> getSavedUsers() async {
    final userKeys = StorageService.getAllUserKeys();
    final users = <User>[];

    for (final key in userKeys) {
      if (key != 'current_user' &&
          key != 'auth_token' &&
          key != 'server_host') {
        final userData = StorageService.getUser<Map<String, dynamic>>(key);
        if (userData != null) {
          try {
            users.add(User.fromJson(userData));
          } catch (e) {
            // Invalid user data, remove it
            await StorageService.removeUser(key);
          }
        }
      }
    }

    return users;
  }

  Future<void> saveUser(User user) async {
    final key = 'user_${user.name}_${user.host}';
    await StorageService.setUser(key, user.toJson());
  }

  Future<void> removeUser(User user) async {
    final key = 'user_${user.name}_${user.host}';
    await StorageService.removeUser(key);

    // If removing current user, logout
    if (state.currentUser == user) {
      await logout();
    }
  }

  /// 重新尝试连接（用于从离线模式恢复）
  Future<void> retryConnection() async {
    LogService.instance.debug('[Auth] Retrying connection...', tag: 'Network');
    await _loadCurrentUser();
  }

  void clearError() {
    state = state.copyWith(error: null);
  }
}

// Providers
final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  return AuthNotifier(apiService);
});

// Convenience providers
final isLoggedInProvider = Provider<bool>((ref) {
  return ref.watch(authProvider).isLoggedIn;
});

final currentUserProvider = Provider<User?>((ref) {
  return ref.watch(authProvider).currentUser;
});

final authTokenProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).token;
});

final serverHostProvider = Provider<String?>((ref) {
  return ref.watch(authProvider).host;
});
