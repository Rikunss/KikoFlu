import 'dart:async';
import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:equatable/equatable.dart';

import '../models/user.dart';
import '../models/account.dart';
import '../services/kikoeru_api_service.dart';
import '../services/storage_service.dart';
import '../services/cookie_service.dart';
import '../services/account_database.dart';
import '../services/log_service.dart';
import '../utils/server_utils.dart';

class AuthState extends Equatable {
  final User? currentUser;
  final String? token;
  final String? host;
  final bool isLoading;
  final String? error;
  final bool isLoggedIn;

  /// Set to true when a 401/403 response is received during an API call.
  /// The UI shows a "Session Expired" dialog and navigates to LoginScreen.
  final bool sessionExpired;

  const AuthState({
    this.currentUser,
    this.token,
    this.host,
    this.isLoading = false,
    this.error,
    this.isLoggedIn = false,
    this.sessionExpired = false,
  });

  AuthState copyWith({
    User? currentUser,
    String? token,
    String? host,
    bool? isLoading,
    String? error,
    bool? isLoggedIn,
    bool? sessionExpired,
  }) {
    return AuthState(
      currentUser: currentUser ?? this.currentUser,
      token: token ?? this.token,
      host: host ?? this.host,
      isLoading: isLoading ?? this.isLoading,
      error: error,
      isLoggedIn: isLoggedIn ?? this.isLoggedIn,
      sessionExpired: sessionExpired ?? this.sessionExpired,
    );
  }

  @override
  List<Object?> get props =>
      [currentUser, token, host, isLoading, error, isLoggedIn, sessionExpired];
}

class AuthNotifier extends StateNotifier<AuthState> {
  final KikoeruApiService _apiService;

  /// Guard flag: prevents multiple concurrent unauthorized handlers from
  /// triggering cascading logouts when 401/403 fires on parallel API calls.
  bool _isHandlingUnauthorized = false;

  /// Periodic timer that retries connection when in offline mode.
  Timer? _offlineRetryTimer;

  AuthNotifier(this._apiService) : super(const AuthState()) {
    _apiService.onUnauthorized = _handleUnauthorized;
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    await Future<void>.delayed(Duration.zero);

    try {
      LogService.instance.debug('[Auth] Loading current user...', tag: 'Network');

      final token = await StorageService.getStringAsync('auth_token');
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

        try {
          LogService.instance.debug('[Auth] Validating token...', tag: 'Network');
          await _refreshUserInfo();
          LogService.instance.debug('[Auth] Token is valid, user logged in successfully', tag: 'Network');
          return;
        } catch (e) {
          LogService.instance.warning('[Auth] Token validation failed: $e', tag: 'Network');
        }
      }

      LogService.instance.debug('[Auth] Checking database for active account...', tag: 'Network');
      final activeAccount = await AccountDatabase.instance.getActiveAccount();

      if (activeAccount != null) {
        LogService.instance.debug(
            '[Auth] Found active account in database: ${activeAccount.username}', tag: 'Network');
        LogService.instance.debug('[Auth] Re-logging in with saved account...', tag: 'Network');

        _apiService.init('', activeAccount.host);

        final success = await login(
          activeAccount.username,
          activeAccount.password,
          activeAccount.host,
          activeAccount.serverCookie,
          silent: true,
        );

        if (success) {
          LogService.instance.debug('[Auth] Re-login successful', tag: 'Network');
          _stopOfflineRetryTimer();
          return;
        } else {
          LogService.instance.warning('[Auth] Re-login failed due to network or server issue', tag: 'Network');
          LogService.instance.warning('[Auth] Entering offline mode with cached account', tag: 'Network');

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

          LogService.instance.debug('[Auth] Offline mode activated', tag: 'Network');
          _startOfflineRetryTimer();
          return;
        }
      } else {
        LogService.instance.debug('[Auth] No active account found in database', tag: 'Network');
      }

      LogService.instance.debug('[Auth] No valid authentication found, logging out', tag: 'Network');
      await logout();
    } catch (e) {
      LogService.instance.error('[Auth] Failed to load saved auth: $e', tag: 'Network');

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
            isLoggedIn: false,              error: '网络连接失败，以离线模式启动',
          );

          _startOfflineRetryTimer();
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
    if (state.sessionExpired) {
      state = state.copyWith(sessionExpired: false);
    }

    if (!silent) {
      state = state.copyWith(isLoading: true, error: null);
    }

    await CookieService.setCookie(serverCookie);

    try {
      LogService.instance.debug(
          '[Auth] Login attempt - username: $username, host: $host, silent: $silent', tag: 'Network');

      if (host.endsWith("/")) {
        host = host.substring(0, host.length - 1);
      }

      _apiService.init('', host);

      final response = await _apiService.login(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      LogService.instance.debug('[Auth] Login successful, received token', tag: 'Network');

      final normalizedHost = ServerUtils.normalizeHost(host);

      LogService.instance.debug('[Auth] Normalized host: $normalizedHost', tag: 'Network');

      _apiService.init(token, normalizedHost);

      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        userInfo = response;
      } else {
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      if (ServerUtils.isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Login failed: User not logged in');
      }

      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        serverCookie: serverCookie,
        lastUpdateTime: DateTime.now(),
      );

      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

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
          await AccountDatabase.instance.updateAccount(
            existingAccount.copyWith(
              password: password,
              isActive: true,
              serverCookie: serverCookie,
              lastUsedAt: DateTime.now(),
            ),
          );
        } else {
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

    await CookieService.setCookie(serverCookie);

    try {
      _apiService.init('', host);

      final response = await _apiService.register(username, password, host);

      final token = response['token'] as String?;
      if (token == null) {
        throw Exception('No token received from server');
      }

      final normalizedHost = ServerUtils.normalizeHost(host);

      _apiService.init(token, normalizedHost);

      Map<String, dynamic> userInfo;
      if (response['user'] != null) {
        userInfo = response;
      } else {
        userInfo = await _apiService.getUserInfo();
      }

      final user = User.fromJson(userInfo);

      if (ServerUtils.isOfficialServer(normalizedHost) && !user.loggedIn) {
        throw Exception('Registration failed: User not logged in');
      }

      final authenticatedUser = user.copyWith(
        password: password,
        host: normalizedHost,
        token: token,
        serverCookie: serverCookie,
        lastUpdateTime: DateTime.now(),
      );

      await StorageService.setString('auth_token', token);
      await StorageService.setString('server_host', normalizedHost);
      await StorageService.setMap('current_user', authenticatedUser.toJson());

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

      if (ServerUtils.isOfficialServer(state.host) && !user.loggedIn) {
        throw Exception('User not logged in');
      }

      await StorageService.setMap('current_user', user.toJson());

      state = state.copyWith(currentUser: user);
    } catch (e) {
      LogService.instance.error('[Auth] Failed to refresh user info: $e', tag: 'Network');
      rethrow;
    }
  }

  Future<void> updateHost(String host) async {
    if (state.token != null) {
      final normalizedHost = ServerUtils.normalizeHost(host);

      final cookie = state.currentUser?.serverCookie;
      await CookieService.setCookie(cookie);

      _apiService.init(state.token!, normalizedHost);
      await StorageService.setString('server_host', normalizedHost);
      state = state.copyWith(host: normalizedHost);
    }
  }

  /// Called by the global Dio interceptor when a 401/403 is received.
  /// Uses [Future.microtask] to decouple from the interceptor call chain.
  void _handleUnauthorized() {
    if (_isHandlingUnauthorized) return;
    _isHandlingUnauthorized = true;

    Future.microtask(() async {
      try {
        LogService.instance.warning('[Auth] Session expired (401/403), logging out', tag: 'Network');

        state = state.copyWith(sessionExpired: true);

        await logout();
      } finally {
        _isHandlingUnauthorized = false;
      }
    });
  }

  Future<void> logout() async {
    _stopOfflineRetryTimer();

    try {
      await StorageService.remove('auth_token');
      await StorageService.remove('server_host');
      await StorageService.remove('current_user');
      await CookieService.clearCookie();
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

      await CookieService.setCookie(serverCookie);

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

    if (state.currentUser == user) {
      await logout();
    }
  }

  /// 重新尝试连接（用于从离线模式恢复）
  Future<void> retryConnection() async {
    LogService.instance.debug('[Auth] Retrying connection...', tag: 'Network');
    _stopOfflineRetryTimer();
    await _loadCurrentUser();
  }

  /// Start a periodic timer that retries connection when the app is in
  /// offline mode. Checks every 30 seconds.
  void _startOfflineRetryTimer() {
    _stopOfflineRetryTimer();
    _offlineRetryTimer = Timer.periodic(
      const Duration(seconds: 30),
      (_) async {
        try {
          if (state.currentUser != null && !state.isLoggedIn && !state.isLoading) {
            LogService.instance.debug('[Auth] Offline retry: checking connection...', tag: 'Network');
            await retryConnection();
          } else {
            _stopOfflineRetryTimer();
          }
        } catch (e) {
          LogService.instance.error('[Auth] Offline retry failed: $e', tag: 'Network');
        }
      },
    );
  }

  void _stopOfflineRetryTimer() {
    _offlineRetryTimer?.cancel();
    _offlineRetryTimer = null;
  }

  @override
  void dispose() {
    _stopOfflineRetryTimer();
    _apiService.onUnauthorized = null;
    super.dispose();
  }

  void clearError() {
    state = state.copyWith(error: null, sessionExpired: false);
  }
}

final authProvider = StateNotifierProvider<AuthNotifier, AuthState>((ref) {
  final apiService = ref.watch(kikoeruApiServiceProvider);
  return AuthNotifier(apiService);
});

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