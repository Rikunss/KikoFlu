import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/auth_provider.dart';
import '../services/kikoeru_api_service.dart';
import '../utils/server_utils.dart';
import '../utils/snackbar_util.dart';
import '../../l10n/app_localizations.dart';
import '../widgets/scrollable_appbar.dart';
import 'main_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  final bool isAddingAccount; // true when adding from account management

  const LoginScreen({
    super.key,
    this.isAddingAccount = false,
  });

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

enum _LatencyState { idle, testing, success, failure }

class _LatencyResult {
  const _LatencyResult(
    this.state, {
    this.latencyMs,
    this.statusCode,
    this.error,
  });

  final _LatencyState state;
  final int? latencyMs;
  final int? statusCode;
  final String? error;
}

String _normalizedHostString(String host) {
  var value = host.trim();
  if (value.isEmpty) {
    return '';
  }

  if (value.startsWith('http://')) {
    value = value.substring(7);
  } else if (value.startsWith('https://')) {
    value = value.substring(8);
  }

  while (value.endsWith('/')) {
    value = value.substring(0, value.length - 1);
  }

  return value;
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverCookieController = TextEditingController();

  bool _isLogin = true; // true for login, false for register
  bool _obscurePassword = true;
  bool _isLoading = false;
  late final List<String> _hostOptions;
  String _hostValue = '';
  final Map<String, _LatencyResult> _latencyResults = {};

  @override
  void initState() {
    super.initState();
    _initializeHostOptions();

    final defaultHost = _normalizedHostString(KikoeruApiService.remoteHost);
    _hostValue = defaultHost;
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverCookieController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _hostValue.trim();
    final serverCookie = _serverCookieController.text.trim();

    if (!_isLogin) {
      if (username.length < 5) {
        SnackBarUtil.showError(context, S.of(context).usernameMinLength);
        setState(() => _isLoading = false);
        return;
      }
      if (password.length < 5) {
        SnackBarUtil.showError(context, S.of(context).passwordMinLength);
        setState(() => _isLoading = false);
        return;
      }
    }

    try {
      bool success;
      if (_isLogin) {
        success = await ref
            .read(authProvider.notifier)
            .login(username, password, host, serverCookie);
      } else {
        success = await ref
            .read(authProvider.notifier)
            .register(username, password, host, serverCookie);
      }

      if (success && mounted) {
        if (widget.isAddingAccount) {
          // Adding account mode - just go back
          Navigator.pop(context, true);
          SnackBarUtil.showSuccess(
              context, S.of(context).accountAdded(username));
        } else {
          // Normal login - go to main screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false, // Remove all previous routes
          );
        }
      } else if (mounted) {
        final error = ref.read(authProvider).error;
        SnackBarUtil.showError(
          context,
          error ??
              (_isLogin
                  ? S.of(context).loginFailed
                  : S.of(context).registerFailed),
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(
          context,
          _isLogin ? S.of(context).loginFailed : S.of(context).registerFailed,
        );
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  // 游客登录
  Future<void> _loginAsGuest() async {
    // 验证服务器地址
    if (_hostValue.trim().isEmpty) {
      SnackBarUtil.showError(context, S.of(context).pleaseEnterServerAddress);
      return;
    }

    // 显示二次确认对话框
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).guestModeTitle),
          content: Text(
            S.of(context).guestModeMessage,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(S.of(context).cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(S.of(context).continueGuestMode),
            ),
          ],
        );
      },
    );

    // 用户取消了操作
    if (confirmed != true) {
      return;
    }

    setState(() => _isLoading = true);

    final host = _hostValue.trim();
    const guestUsername = 'guest';
    const guestPassword = 'guest';
    final serverCookie = _serverCookieController.text.trim();

    try {
      final success = await ref
          .read(authProvider.notifier)
          .login(guestUsername, guestPassword, host, serverCookie);

      if (success && mounted) {
        if (widget.isAddingAccount) {
          // Adding account mode - just go back
          Navigator.pop(context, true);
          SnackBarUtil.showSuccess(context, S.of(context).guestAccountAdded);
        } else {
          // Normal login - go to main screen
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
          );
        }
      } else if (mounted) {
        final error = ref.read(authProvider).error;
        SnackBarUtil.showError(
          context,
          error ?? S.of(context).guestLoginFailed,
        );
      }
    } catch (e) {
      if (mounted) {
        SnackBarUtil.showError(context, S.of(context).guestLoginFailed);
      }
    }

    if (mounted) {
      setState(() => _isLoading = false);
    }
  }

  void _toggleMode() {
    setState(() {
      _isLogin = !_isLogin;
    });
    ref.read(authProvider.notifier).clearError();
  }

  void _initializeHostOptions() {
    final options = <String>[];

    void addOption(String host) {
      final normalized = _normalizedHostString(host);
      if (normalized.isEmpty) {
        return;
      }
      if (!options.contains(normalized)) {
        options.add(normalized);
      }
    }

    const preferredHosts = ServerUtils.preferredHosts;

    for (final host in preferredHosts) {
      addOption(host);
    }

    final defaultHost = _normalizedHostString(KikoeruApiService.remoteHost);
    if (defaultHost.isNotEmpty) {
      options.remove(defaultHost);
      options.insert(0, defaultHost);
    }

    _hostOptions = options;
  }

  Widget _buildHostLatencyActions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final normalized = _normalizedHostString(_hostValue);
    final serverCookie = _serverCookieController.text.trim();
    final result = normalized.isEmpty ? null : _latencyResults[normalized];
    final isTesting = result?.state == _LatencyState.testing;
    final statusText = normalized.isEmpty
        ? S.of(context).enterServerAddressToTest
        : _describeLatencyResult(result, includePlaceholder: true);
    final color = normalized.isEmpty
        ? cs.onSurfaceVariant
        : _latencyColorForResult(context, result);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: const Size(0, 36),
          ),
          onPressed: normalized.isEmpty || isTesting
              ? null
              : () => _testLatencyForHost(_hostValue, serverCookie),
          icon: isTesting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.network_ping_outlined),
          label: Text(
              isTesting ? S.of(context).testing : S.of(context).testConnection),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            statusText,
            style:
                tt.bodySmall?.copyWith(color: color),
            textAlign: TextAlign.right,
          ),
        ),
      ],
    );
  }

  Future<void> _testLatencyForHost(String host, [String? serverCookie]) async {
    final normalized = _normalizedHostString(host);
    if (normalized.isEmpty) {
      return;
    }

    setState(() {
      _latencyResults[normalized] = const _LatencyResult(_LatencyState.testing);
    });

    final stopwatch = Stopwatch()..start();

    try {
      final dio = Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
          sendTimeout: const Duration(seconds: 5),
        ),
      );

      final trimmedHost = host.trim();
      String baseUrl;
      if (trimmedHost.startsWith('http://') ||
          trimmedHost.startsWith('https://')) {
        baseUrl = trimmedHost;
      } else {
        if (normalized.contains('localhost') ||
            normalized.startsWith('127.0.0.1') ||
            normalized.startsWith('192.168.')) {
          baseUrl = 'http://$normalized';
        } else {
          baseUrl = 'https://$normalized';
        }
      }

      final response = await dio.get(
        '$baseUrl/api/health',
        options: Options(
          validateStatus: (status) => status != null && status < 500,
          headers: (serverCookie != null && serverCookie.isNotEmpty)
              ? {'Cookie': serverCookie}
              : null,
        ),
      );

      stopwatch.stop();

      if (!mounted) {
        return;
      }

      final statusCode = response.statusCode;
      final latency = stopwatch.elapsedMilliseconds;
      final success =
          statusCode != null && statusCode >= 200 && statusCode < 300;

      setState(() {
        _latencyResults[normalized] = _LatencyResult(
          success ? _LatencyState.success : _LatencyState.failure,
          latencyMs: latency,
          statusCode: statusCode,
          error: success ? null : 'HTTP ${statusCode ?? '-'}',
        );
      });
    } catch (e) {
      stopwatch.stop();

      if (!mounted) {
        return;
      }

      final statusCode = e is DioException ? e.response?.statusCode : null;
      final message = e is DioException
          ? (e.message ?? e.error?.toString() ?? 'Unknown error')
          : e.toString();

      setState(() {
        _latencyResults[normalized] = _LatencyResult(
          _LatencyState.failure,
          statusCode: statusCode,
          error: _shortenMessage(message),
        );
      });
    }
  }

  String _describeLatencyResult(_LatencyResult? result,
      {bool includePlaceholder = false}) {
    final s = S.of(context);
    if (result == null) {
      return includePlaceholder ? s.notTestedYet : '';
    }

    switch (result.state) {
      case _LatencyState.idle:
        return includePlaceholder ? s.notTestedYet : '';
      case _LatencyState.testing:
        return s.testing;
      case _LatencyState.success:
        final latency = result.latencyMs;
        final statusCode = result.statusCode;
        final latencyText = latency != null ? '$latency ms' : '- ms';
        final statusText = statusCode != null ? 'HTTP $statusCode' : 'HTTP -';
        return s.latencyResultDetail(latencyText, statusText);
      case _LatencyState.failure:
        final statusCode = result.statusCode;
        final error = result.error;
        final statusSuffix = statusCode != null ? ' (HTTP $statusCode)' : '';
        if (error != null && error.isNotEmpty) {
          return s.connectionFailedWithDetail(_shortenMessage(error));
        }
        return '${s.connectionFailed}$statusSuffix';
    }
  }

  Color _latencyColorForResult(BuildContext context, _LatencyResult? result) {
    final scheme = Theme.of(context).colorScheme;

    if (result == null || result.state == _LatencyState.idle) {
      return scheme.onSurfaceVariant;
    }

    switch (result.state) {
      case _LatencyState.idle:
        return scheme.onSurfaceVariant;
      case _LatencyState.testing:
        return scheme.primary;
      case _LatencyState.success:
        return scheme.secondary;
      case _LatencyState.failure:
        return scheme.error;
    }
  }

  String _shortenMessage(String message, {int maxLength = 60}) {
    if (message.length <= maxLength) {
      return message;
    }
    return '${message.substring(0, maxLength)}...';
  }

  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    return Scaffold(
      appBar: ScrollableAppBar(
        title: Text(widget.isAddingAccount
            ? (_isLogin
                ? S.of(context).addAccount
                : S.of(context).registerAccount)
            : (_isLogin ? S.of(context).login : S.of(context).register)),
        centerTitle: true,
        // Show back button in adding account mode
        automaticallyImplyLeading: widget.isAddingAccount,
      ),
      body: SafeArea(
        child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
      ),
    );
  }

  // 竖屏布局
  Widget _buildPortraitLayout() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Logo/Header
              Container(
                height: 120,
                margin: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: cs.primaryContainer.withValues(alpha: 0.3),
                        shape: BoxShape.circle,
                      ),
                      child: ClipOval(
                        child: Image.asset(
                          'assets/icons/app_icon_login.png',
                          width: 64,
                          height: 64,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.audiotrack,
                              size: 36,
                              color: cs.primary,
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'KikoFlu',
                      style:
                          tt.headlineMedium?.copyWith(
                                color: cs.primary,
                                fontWeight: FontWeight.bold,
                              ),
                    ),
                  ],
                ),
              ),
              // Form Card
              AnimatedOpacity(
                opacity: _isLoading ? 0.55 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Card(
                  elevation: 0,
                  color: cs.surfaceContainerLow,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  margin: EdgeInsets.zero,
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _buildFormFields(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 横屏布局
  Widget _buildLandscapeLayout() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Row(
        children: [
          // 左侧：Logo区域
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 96,
                    height: 96,
                    decoration: BoxDecoration(
                      color: cs.primaryContainer.withValues(alpha: 0.3),
                      shape: BoxShape.circle,
                    ),
                    child: ClipOval(
                      child: Image.asset(
                        'assets/icons/app_icon_login.png',
                        width: 80,
                        height: 80,
                        errorBuilder: (context, error, stackTrace) {
                          return Icon(
                            Icons.audiotrack,
                            size: 44,
                            color: cs.primary,
                          );
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'KikoFlu',
                    style: tt.headlineLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ],
              ),
            ),
          ),
          // 右侧：表单区域
          Expanded(
            flex: 3,
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
              child: Form(
                key: _formKey,
                child: AnimatedOpacity(
                  opacity: _isLoading ? 0.55 : 1.0,
                  duration: const Duration(milliseconds: 200),
                  child: Card(
                    elevation: 0,
                    color: cs.surfaceContainerLow,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                    ),
                    margin: EdgeInsets.zero,
                    child: Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: _buildFormFields(),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 表单字段列表
  List<Widget> _buildFormFields() {
    final cs = Theme.of(context).colorScheme;
    return [
      // Username field
      TextFormField(
        controller: _usernameController,
        autofillHints: const [AutofillHints.username],
        decoration: InputDecoration(
          labelText: S.of(context).username,
          prefixIcon: const Icon(Icons.person),
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.trim().isEmpty) {
            return S.of(context).pleaseEnterUsername;
          }
          if (!_isLogin && value.trim().length < 5) {
            return S.of(context).usernameMinLength;
          }
          return null;
        },
        textInputAction: TextInputAction.next,
      ),

      const SizedBox(height: 16),

      // Password field
      TextFormField(
        controller: _passwordController,
        autofillHints: const [AutofillHints.password],
        obscureText: _obscurePassword,
        decoration: InputDecoration(
          labelText: S.of(context).password,
          prefixIcon: const Icon(Icons.lock),
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility : Icons.visibility_off,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
          border: const OutlineInputBorder(),
        ),
        validator: (value) {
          if (value == null || value.isEmpty) {
            return S.of(context).pleaseEnterPassword;
          }
          if (!_isLogin && value.length < 5) {
            return S.of(context).passwordMinLength;
          }
          return null;
        },
        textInputAction: TextInputAction.next,
      ),

      const SizedBox(height: 16),

      // Host field with dropdown/autocomplete
      Autocomplete<String>(
        initialValue: TextEditingValue(text: _hostValue),
        optionsBuilder: (textEditingValue) {
          // 始终显示所有推荐选项
          return _hostOptions;
        },
        fieldViewBuilder: (
          context,
          textEditingController,
          focusNode,
          onFieldSubmitted,
        ) {
          return TextFormField(
            controller: textEditingController,
            focusNode: focusNode,
            decoration: InputDecoration(
              labelText: S.of(context).serverAddress,
              prefixIcon: const Icon(Icons.dns),
              border: const OutlineInputBorder(),
            ),
            keyboardType: TextInputType.url,
            onChanged: (value) {
              setState(() {
                _hostValue = value;
              });
            },
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return S.of(context).pleaseEnterServerAddress;
              }
              return null;
            },
            textInputAction: TextInputAction.next,
            onFieldSubmitted: (_) => _submit(),
          );
        },
        onSelected: (selection) {
          setState(() {
            _hostValue = selection;
          });
        },
      ),

      const SizedBox(height: 8),
      _buildHostLatencyActions(context),

      const SizedBox(height: 15),

      // Cookie field (collapsible)
      Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
        ),
        child: ExpansionTile(
          title: Row(
            children: [
              Icon(Icons.security,
                  size: 18,
                  color: cs.primary),
              const SizedBox(width: 8),
              const Text('Cookie'),
            ],
          ),
          iconColor: cs.primary,
          collapsedIconColor: cs.onSurfaceVariant,
          tilePadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          collapsedShape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          children: [
            TextFormField(
              controller: _serverCookieController,
              decoration: InputDecoration(
                labelText: S.of(context).serverCookie,
                prefixIcon: const Icon(Icons.security),
                border: const OutlineInputBorder(),
                helperText: 'Server Cookie',
              ),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),

      // Submit button
      FilledButton(
        onPressed: _isLoading
            ? null
            : () {
                HapticFeedback.lightImpact();
                _submit();
              },
        child: _isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Text(_isLogin ? S.of(context).login : S.of(context).register),
      ),

      const SizedBox(height: 12),

      // Guest login button (only show in login mode)
      if (_isLogin)
        OutlinedButton.icon(
          onPressed: _isLoading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  _loginAsGuest();
                },
          icon: const Icon(Icons.person_outline),
          label: Text(S.of(context).guestMode),
          style: OutlinedButton.styleFrom(
            foregroundColor: cs.secondary,
          ),
        ),

      const SizedBox(height: 16),

      // Toggle mode button
      TextButton(
        onPressed: _toggleMode,
        child: Text(
          _isLogin
              ? S.of(context).noAccountTapToRegister
              : S.of(context).haveAccountTapToLogin,
          style: TextStyle(
            color: cs.primary,
          ),
        ),
      ),
    ];
  }
}
