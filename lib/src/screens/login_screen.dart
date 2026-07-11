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
  final bool isAddingAccount;

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

class _LoginScreenState extends ConsumerState<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _serverCookieController = TextEditingController();

  bool _isLogin = true;
  bool _obscurePassword = true;
  bool _isLoading = false;
  late final List<String> _hostOptions;
  String _hostValue = '';
  final Map<String, _LatencyResult> _latencyResults = {};

  String? _usernameError;
  String? _passwordError;
  String? _hostError;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _initializeHostOptions();

    final defaultHost = _normalizedHostString(KikoeruApiService.remoteHost);
    _hostValue = defaultHost;

    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _serverCookieController.dispose();
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _validateUsername(String value) {
    final s = S.of(context);
    if (value.trim().isEmpty) {
      setState(() => _usernameError = s.pleaseEnterUsername);
    } else if (!_isLogin && value.trim().length < 5) {
      setState(() => _usernameError = s.usernameMinLength);
    } else {
      setState(() => _usernameError = null);
    }
  }

  void _validatePassword(String value) {
    final s = S.of(context);
    if (value.isEmpty) {
      setState(() => _passwordError = s.pleaseEnterPassword);
    } else if (!_isLogin && value.length < 5) {
      setState(() => _passwordError = s.passwordMinLength);
    } else {
      setState(() => _passwordError = null);
    }
  }

  void _validateHost(String value) {
    final s = S.of(context);
    if (value.trim().isEmpty) {
      setState(() => _hostError = s.pleaseEnterServerAddress);
    } else {
      setState(() => _hostError = null);
    }
  }

  bool _validateAll() {
    _validateUsername(_usernameController.text);
    _validatePassword(_passwordController.text);
    _validateHost(_hostValue);
    return _usernameError == null && _passwordError == null && _hostError == null;
  }

  Future<void> _submit() async {
    if (!_validateAll()) return;

    setState(() => _isLoading = true);

    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    final host = _hostValue.trim();
    final serverCookie = _serverCookieController.text.trim();

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
          Navigator.pop(context, true);
          SnackBarUtil.showSuccess(
              context, S.of(context).accountAdded(username));
        } else {
          Navigator.of(context).pushAndRemoveUntil(
            MaterialPageRoute(builder: (context) => const MainScreen()),
            (route) => false,
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

  Future<void> _loginAsGuest() async {
    if (_hostValue.trim().isEmpty) {
      SnackBarUtil.showError(context, S.of(context).pleaseEnterServerAddress);
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(S.of(context).guestModeTitle),
          content: Text(S.of(context).guestModeMessage),
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
          Navigator.pop(context, true);
          SnackBarUtil.showSuccess(context, S.of(context).guestAccountAdded);
        } else {
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
      _usernameError = null;
      _passwordError = null;
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
        _buildConnectionStatusChip(result, cs, tt),
      ],
    );
  }

  Widget _buildConnectionStatusChip(_LatencyResult? result, ColorScheme cs, TextTheme tt) {
    if (result == null || result.state == _LatencyState.idle) {
      return const SizedBox.shrink();
    }

    final (IconData icon, Color color, String label) = switch (result.state) {
      _LatencyState.testing => (Icons.hourglass_top, cs.primary, S.of(context).testing),
      _LatencyState.success => (Icons.check_circle, cs.primary, '${result.latencyMs ?? '-'} ms'),
      _LatencyState.failure => (Icons.error_outline, cs.error, S.of(context).connectionFailed),
      _LatencyState.idle => (Icons.help_outline, cs.onSurfaceVariant, ''),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 6),
          Text(
            label,
            style: tt.bodySmall?.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
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

  String _shortenMessage(String message, {int maxLength = 60}) {
    if (message.length <= maxLength) {
      return message;
    }
    return '${message.substring(0, maxLength)}...';
  }

  Widget _buildInlineError(String? error) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeInOut,
      alignment: Alignment.topCenter,
      child: error != null && error.isNotEmpty
          ? Padding(
              padding: const EdgeInsets.only(top: 6, left: 12),
              child: Row(
                children: [
                  Icon(Icons.error_outline, size: 14,
                      color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Flexible(
                    child: Text(
                      error,
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildDecorativeCircles(ColorScheme cs) {
    return Stack(
      children: [
        Positioned(
          top: -100,
          right: -80,
          child: Container(
            width: 280,
            height: 280,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.primary.withValues(alpha: 0.04),
            ),
          ),
        ),
        Positioned(
          bottom: -60,
          left: -60,
          child: Container(
            width: 200,
            height: 200,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.tertiary.withValues(alpha: 0.04),
            ),
          ),
        ),
        Positioned(
          top: MediaQuery.of(context).size.height * 0.4,
          right: -30,
          child: Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: cs.secondary.withValues(alpha: 0.03),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLogo(ColorScheme cs, {double size = 120}) {
    return AnimatedBuilder(
      animation: _pulseCtrl,
      builder: (context, child) {
        final scale = 1.0 + (_pulseCtrl.value * 0.04);
        final glowOpacity = 0.15 + (_pulseCtrl.value * 0.12);
        return Transform.scale(
          scale: scale,
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(size * 0.24),
              boxShadow: [
                BoxShadow(
                  color: cs.primary.withValues(alpha: glowOpacity),
                  blurRadius: 24 + (_pulseCtrl.value * 16),
                  spreadRadius: 2 + (_pulseCtrl.value * 4),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(size * 0.24),
              child: Image.asset(
                'assets/icons/app_icon_login.png',
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  child: Icon(
                    Icons.audiotrack,
                    size: size * 0.5,
                    color: cs.primary,
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
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
        automaticallyImplyLeading: widget.isAddingAccount,
      ),
      body: SafeArea(
        child: isLandscape ? _buildLandscapeLayout() : _buildPortraitLayout(),
      ),
    );
  }

  Widget _buildPortraitLayout() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerLow.withValues(alpha: 0.5),
              cs.surface,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildDecorativeCircles(cs),

            SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Form(
                key: _formKey,
                child: Column(
                  children: [
                    const SizedBox(height: 16),

                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      child: _buildLogo(cs),
                    ),

                    Text(
                      'KikoFlu',
                      style: tt.headlineMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Kikoeru Client',
                      style: tt.bodyMedium?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),

                    const SizedBox(height: 28),

                    AnimatedOpacity(
                      opacity: _isLoading ? 0.6 : 1.0,
                      duration: const Duration(milliseconds: 200),
                      child: Card(
                        elevation: 0,
                        color: cs.surfaceContainerLow,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        margin: EdgeInsets.zero,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: _buildFormContent(),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLandscapeLayout() {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              cs.surface,
              cs.surfaceContainerLow.withValues(alpha: 0.5),
              cs.surface,
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Stack(
          children: [
            _buildDecorativeCircles(cs),

            Row(
              children: [
                Expanded(
                  flex: 2,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _buildLogo(cs, size: 96),
                      const SizedBox(height: 16),
                      Text(
                        'KikoFlu',
                        style: tt.headlineLarge?.copyWith(
                          color: cs.primary,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Kikoeru Client',
                        style: tt.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),

                Expanded(
                  flex: 3,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 32, vertical: 24),
                    child: Form(
                      key: _formKey,
                      child: AnimatedOpacity(
                        opacity: _isLoading ? 0.6 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: Card(
                          elevation: 0,
                          color: cs.surfaceContainerLow,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                          ),
                          margin: EdgeInsets.zero,
                          child: Padding(
                            padding: const EdgeInsets.all(20),
                            child: _buildFormContent(),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFormContent() {
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildField(
          controller: _usernameController,
          label: S.of(context).username,
          icon: Icons.person_outline,
          obscure: false,
          error: _usernameError,
          autofillHints: const [AutofillHints.username],
          onChanged: _validateUsername,
        ),

        const SizedBox(height: 16),

        _buildField(
          controller: _passwordController,
          label: S.of(context).password,
          icon: Icons.lock_outline,
          obscure: _obscurePassword,
          error: _passwordError,
          autofillHints: const [AutofillHints.password],
          onChanged: _validatePassword,
          suffixIcon: IconButton(
            icon: Icon(
              _obscurePassword ? Icons.visibility_outlined : Icons.visibility_off_outlined,
              size: 20,
            ),
            onPressed: () {
              setState(() {
                _obscurePassword = !_obscurePassword;
              });
            },
          ),
        ),

        const SizedBox(height: 16),

        _buildServerAddressField(cs),

        const SizedBox(height: 8),
        _buildHostLatencyActions(context),

        const SizedBox(height: 16),

        _buildCookieSection(cs),

        const SizedBox(height: 20),

        FilledButton(
          onPressed: _isLoading
              ? null
              : () {
                  HapticFeedback.lightImpact();
                  _submit();
                },
          style: FilledButton.styleFrom(
            minimumSize: const Size(double.infinity, 48),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(
                  _isLogin ? S.of(context).login : S.of(context).register,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                ),
        ),

        const SizedBox(height: 12),

        if (_isLogin)
          OutlinedButton.icon(
            onPressed: _isLoading
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    _loginAsGuest();
                  },
            icon: const Icon(Icons.person_outline, size: 20),
            label: Text(S.of(context).guestMode),
            style: OutlinedButton.styleFrom(
              foregroundColor: cs.secondary,
              minimumSize: const Size(double.infinity, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              side: BorderSide(color: cs.secondary.withValues(alpha: 0.4)),
            ),
          ),

        const SizedBox(height: 12),

        TextButton(
          onPressed: _toggleMode,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 250),
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.1, 0.0),
                    end: Offset.zero,
                  ).animate(animation),
                  child: child,
                ),
              );
            },
            child: Text(
              key: ValueKey(_isLogin),
              _isLogin
                  ? S.of(context).noAccountTapToRegister
                  : S.of(context).haveAccountTapToLogin,
              style: TextStyle(
                color: cs.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    required bool obscure,
    required String? error,
    Iterable<String>? autofillHints,
    ValueChanged<String>? onChanged,
    Widget? suffixIcon,
  }) {
    final cs = Theme.of(context).colorScheme;
    final hasError = error != null && error.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextFormField(
          controller: controller,
          autofillHints: autofillHints,
          obscureText: obscure,
          decoration: InputDecoration(
            labelText: label,
            prefixIcon: Icon(icon, size: 20),
            suffixIcon: suffixIcon,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasError
                    ? cs.error
                    : cs.outline.withValues(alpha: 0.5),
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(
                color: hasError ? cs.error : cs.primary,
                width: 2,
              ),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: cs.error),
            ),
            filled: true,
            fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
          ),
          onChanged: onChanged,
          validator: null,
          textInputAction: TextInputAction.next,
        ),
        _buildInlineError(error),
      ],
    );
  }

  Widget _buildServerAddressField(ColorScheme cs) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Autocomplete<String>(
          initialValue: TextEditingValue(text: _hostValue),
          optionsBuilder: (textEditingValue) {
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
                prefixIcon: const Icon(Icons.dns_outlined, size: 20),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _hostError != null
                        ? cs.error
                        : cs.outline.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(
                    color: _hostError != null ? cs.error : cs.primary,
                    width: 2,
                  ),
                ),
                filled: true,
                fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
              keyboardType: TextInputType.url,
              onChanged: (value) {
                setState(() {
                  _hostValue = value;
                });
                _validateHost(value);
              },
              validator: null,
              textInputAction: TextInputAction.next,
              onFieldSubmitted: (_) => _submit(),
            );
          },
          onSelected: (selection) {
            setState(() {
              _hostValue = selection;
            });
            _validateHost(selection);
          },
        ),
        _buildInlineError(_hostError),
      ],
    );
  }

  Widget _buildCookieSection(ColorScheme cs) {
    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(14),
      ),
      child: ExpansionTile(
        title: Row(
          children: [
            Icon(Icons.security, size: 18, color: cs.primary),
            const SizedBox(width: 8),
            const Text('Cookie'),
          ],
        ),
        iconColor: cs.primary,
        collapsedIconColor: cs.onSurfaceVariant,
        tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        collapsedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        children: [
          TextFormField(
            controller: _serverCookieController,
            decoration: InputDecoration(
              labelText: S.of(context).serverCookie,
              prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              helperText: 'Server Cookie',
              filled: true,
              fillColor: cs.surfaceContainerHighest.withValues(alpha: 0.3),
            ),
            textInputAction: TextInputAction.done,
          ),
        ],
      ),
    );
  }
}