import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../l10n/app_localizations.dart';
import '../services/app_lock_service.dart';

/// Lock screen shown at app launch when App Lock is enabled.
///
/// Features:
/// - Auto-prompt biometric (Face ID / fingerprint) on first show
/// - PIN entry fallback (4-6 digits)
/// - Switch between biometric and PIN
/// - Same visual style as the redesigned login screen
class LockScreen extends ConsumerStatefulWidget {
  /// Called after successful authentication.
  final VoidCallback onUnlocked;

  const LockScreen({super.key, required this.onUnlocked});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen>
    with SingleTickerProviderStateMixin {
  final _pinControllers = List.generate(6, (_) => TextEditingController());
  final _pinFocusNodes = List.generate(6, (_) => FocusNode());
  final List<String> _pinDigits = List.filled(6, '');

  bool _isPinMode = false;
  bool _isLoading = true;
  bool _showError = false;
  String _errorMessage = '';
  final int _pinLength = 4;

  late final AnimationController _pulseCtrl;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat(reverse: true);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryBiometric();
    });
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    for (final c in _pinControllers) {
      c.dispose();
    }
    for (final f in _pinFocusNodes) {
      f.dispose();
    }
    super.dispose();
  }

  Future<void> _tryBiometric() async {
    final service = AppLockService.instance;
    final s = S.of(context);

    if (!service.isBiometricEnabled) {
      setState(() {
        _isPinMode = true;
        _isLoading = false;
      });
      return;
    }

    final canBio = await service.canUseBiometric();
    if (!canBio) {
      setState(() {
        _isPinMode = true;
        _isLoading = false;
      });
      return;
    }

    final success = await service.authenticateBiometric(
      reason: s.appLockBiometricReason,
    );

    if (success && mounted) {
      widget.onUnlocked();
      return;
    }

    if (mounted) {
      setState(() {
        _isPinMode = true;
        _isLoading = false;
      });
    }
  }

  void _onPinDigitChanged(int index, String value) {
    if (value.length > 1) {
      final digits = value.replaceAll(RegExp(r'\D'), '').split('').take(_pinLength).toList();
      for (var i = 0; i < _pinLength; i++) {
        if (i < digits.length) {
          _pinDigits[i] = digits[i];
          _pinControllers[i].text = digits[i];
        } else {
          _pinDigits[i] = '';
          _pinControllers[i].text = '';
        }
      }
      setState(() => _showError = false);

      if (digits.length >= _pinLength) {
        _verifyPin();
      } else {
        _pinFocusNodes[digits.length].requestFocus();
      }
      return;
    }

    value = value.replaceAll(RegExp(r'\D'), '');
    if (value.isEmpty && index > 0) {
      _pinDigits[index] = '';
      _pinControllers[index].text = '';
      setState(() => _showError = false);
      _pinFocusNodes[index - 1].requestFocus();
      return;
    }

    _pinDigits[index] = value;
    _pinControllers[index].text = value;
    setState(() => _showError = false);

    if (index < _pinLength - 1 && value.isNotEmpty) {
      _pinFocusNodes[index + 1].requestFocus();
    }

    if (index == _pinLength - 1 && value.isNotEmpty) {
      _verifyPin();
    }
  }

  void _verifyPin() {
    final pin = _pinDigits.take(_pinLength).join();
    if (pin.length < _pinLength) return;

    final valid = AppLockService.instance.verifyPin(pin);
    if (valid && mounted) {
      HapticFeedback.lightImpact();
      widget.onUnlocked();
      return;
    }

    HapticFeedback.heavyImpact();
    setState(() {
      _showError = true;
      _errorMessage = S.of(context).appLockWrongPin;
    });

    Future.delayed(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      for (var i = 0; i < _pinLength; i++) {
        _pinDigits[i] = '';
        _pinControllers[i].text = '';
      }
      _pinFocusNodes[0].requestFocus();
    });
  }

  void _switchToBiometric() async {
    setState(() => _isLoading = true);
    await _tryBiometric();
  }

  Widget _buildLogo(ColorScheme cs, {double size = 100}) {
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
                    Icons.lock_outline,
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
      ],
    );
  }

  Widget _buildPinDigitField(int index) {
    final cs = Theme.of(context).colorScheme;
    final hasError = _showError;

    return SizedBox(
      width: 48,
      height: 56,
      child: TextField(
        controller: _pinControllers[index],
        focusNode: _pinFocusNodes[index],
        keyboardType: TextInputType.number,
        textAlign: TextAlign.center,
        maxLength: index == 0 ? _pinLength : 1,
        style: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.bold,
          color: cs.onSurface,
          letterSpacing: 2,
        ),
        decoration: InputDecoration(
          counterText: '',
          filled: true,
          fillColor: hasError
              ? cs.error.withValues(alpha: 0.08)
              : cs.surfaceContainerHighest.withValues(alpha: 0.4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasError ? cs.error : cs.primary,
              width: 2,
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(
              color: hasError
                  ? cs.error.withValues(alpha: 0.5)
                  : _pinDigits[index].isNotEmpty
                      ? cs.primary.withValues(alpha: 0.5)
                      : cs.outline.withValues(alpha: 0.3),
            ),
          ),
        ),
        onChanged: (value) => _onPinDigitChanged(index, value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = S.of(context);

    return Scaffold(
      backgroundColor: cs.surface,
      body: GestureDetector(
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

              SafeArea(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 40),

                        _buildLogo(cs),

                        const SizedBox(height: 24),

                        Text(
                          s.appLockTitle,
                          style: tt.headlineMedium?.copyWith(
                            color: cs.primary,
                            fontWeight: FontWeight.bold,
                            letterSpacing: -0.5,
                          ),
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _isPinMode
                              ? s.appLockEnterPin
                              : s.appLockAuthenticating,
                          style: tt.bodyMedium?.copyWith(
                            color: cs.onSurfaceVariant,
                          ),
                        ),

                        const SizedBox(height: 40),

                        if (_isLoading)
                          const CircularProgressIndicator(),

                        if (!_isLoading && _isPinMode) ...[
                          if (_showError)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                decoration: BoxDecoration(
                                  color: cs.error.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.error_outline,
                                        size: 16, color: cs.error),
                                    const SizedBox(width: 8),
                                    Text(
                                      _errorMessage,
                                      style: TextStyle(
                                        color: cs.error,
                                        fontSize: 13,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: List.generate(
                              _pinLength,
                              (i) => Padding(
                                padding:
                                    const EdgeInsets.symmetric(horizontal: 5),
                                child: _buildPinDigitField(i),
                              ),
                            ),
                          ),

                          const SizedBox(height: 32),

                          _buildNumpad(cs, s),

                          const SizedBox(height: 24),

                          FutureBuilder<bool>(
                            future: AppLockService.instance.canUseBiometric(),
                            builder: (context, snapshot) {
                              if (snapshot.data != true) {
                                return const SizedBox.shrink();
                              }
                              return TextButton.icon(
                                onPressed: _switchToBiometric,
                                icon: Icon(
                                  Icons.fingerprint,
                                  color: cs.primary,
                                ),
                                label: Text(
                                  s.appLockUseBiometric,
                                  style: TextStyle(color: cs.primary),
                                ),
                              );
                            },
                          ),
                        ],

                        SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                      ],
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

  Widget _buildNumpad(ColorScheme cs, S s) {
    final keys = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['', '0', '⌫'],
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: keys.map((row) {
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: row.map((key) {
              if (key.isEmpty) {
                return const SizedBox(width: 72, height: 56);
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: SizedBox(
                  width: 72,
                  height: 56,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: () {
                        HapticFeedback.selectionClick();
                        if (key == '⌫') {
                          _onBackspace();
                        } else {
                          _onNumpadTap(key);
                        }
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Center(
                          child: key == '⌫'
                              ? Icon(Icons.backspace_outlined,
                                  color: cs.onSurfaceVariant, size: 24)
                              : Text(
                                  key,
                                  style: TextStyle(
                                    fontSize: 24,
                                    fontWeight: FontWeight.w500,
                                    color: cs.onSurface,
                                  ),
                                ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        );
      }).toList(),
    );
  }

  void _onNumpadTap(String digit) {
    for (var i = 0; i < _pinLength; i++) {
      if (_pinDigits[i].isEmpty) {
        _pinDigits[i] = digit;
        _pinControllers[i].text = digit;
        setState(() => _showError = false);

        if (i < _pinLength - 1) {
          _pinFocusNodes[i + 1].requestFocus();
        }

        if (i == _pinLength - 1) {
          _verifyPin();
        }
        return;
      }
    }
  }

  void _onBackspace() {
    for (var i = _pinLength - 1; i >= 0; i--) {
      if (_pinDigits[i].isNotEmpty) {
        _pinDigits[i] = '';
        _pinControllers[i].text = '';
        setState(() => _showError = false);
        _pinFocusNodes[i].requestFocus();
        return;
      }
    }
  }
}