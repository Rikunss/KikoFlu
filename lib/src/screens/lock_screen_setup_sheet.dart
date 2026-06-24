import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../l10n/app_localizations.dart';
import '../services/app_lock_service.dart';
import '../services/log_service.dart';

/// Bottom sheet for setting up or changing the app lock PIN.
///
/// Guides the user through:
/// 1. Choose PIN (4 or 6 digits)
/// 2. Confirm PIN
/// 3. Optionally enable biometric
/// 4. Enable app lock
class LockScreenSetupSheet extends StatefulWidget {
  /// If true, the user is changing an existing PIN (no biometric toggle).
  final bool changePin;

  const LockScreenSetupSheet({super.key, this.changePin = false});

  @override
  State<LockScreenSetupSheet> createState() => _LockScreenSetupSheetState();
}

class _LockScreenSetupSheetState extends State<LockScreenSetupSheet> {
  final List<TextEditingController> _pinControllers = [];
  final List<FocusNode> _pinFocusNodes = [];
  final List<String> _pinDigits = [];
  final List<TextEditingController> _confirmControllers = [];
  final List<FocusNode> _confirmFocusNodes = [];
  final List<String> _confirmDigits = [];

  int _pinLength = 4;
  bool _isConfirming = false;
  bool _useBiometric = true;
  bool _canUseBiometric = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _initPinFields();
    _checkBiometric();
  }

  Future<void> _checkBiometric() async {
    final canBio = await AppLockService.instance.canUseBiometric();
    if (mounted) {
      setState(() => _canUseBiometric = canBio);
    }
  }

  void _initPinFields() {
    for (var i = 0; i < 6; i++) {
      _pinControllers.add(TextEditingController());
      _pinFocusNodes.add(FocusNode());
      _pinDigits.add('');
      _confirmControllers.add(TextEditingController());
      _confirmFocusNodes.add(FocusNode());
      _confirmDigits.add('');
    }
  }

  @override
  void dispose() {
    for (var i = 0; i < 6; i++) {
      _pinControllers[i].dispose();
      _pinFocusNodes[i].dispose();
      _confirmControllers[i].dispose();
      _confirmFocusNodes[i].dispose();
    }
    super.dispose();
  }

  void _onDigitChange(
      List<String> digits, List<TextEditingController> controllers,
      List<FocusNode> focusNodes, int index, String value) {
    if (value.length > 1) {
      final allDigits =
          value.replaceAll(RegExp(r'\D'), '').split('').take(_pinLength).toList();
      for (var i = 0; i < _pinLength; i++) {
        if (i < allDigits.length) {
          digits[i] = allDigits[i];
          controllers[i].text = allDigits[i];
        } else {
          digits[i] = '';
          controllers[i].text = '';
        }
      }
      if (allDigits.length >= _pinLength && index == 0) {
        if (_isConfirming) {
          _verifyConfirm();
        } else {
          _onPinComplete();
        }
      } else if (allDigits.isNotEmpty) {
        focusNodes[allDigits.length].requestFocus();
      }
      return;
    }

    value = value.replaceAll(RegExp(r'\D'), '');
    if (value.isEmpty && index > 0) {
      digits[index] = '';
      controllers[index].text = '';
      focusNodes[index - 1].requestFocus();
      return;
    }

    digits[index] = value;
    controllers[index].text = value;
    setState(() => _error = null);

    if (index < _pinLength - 1 && value.isNotEmpty) {
      focusNodes[index + 1].requestFocus();
    }

    if (index == _pinLength - 1 && value.isNotEmpty) {
      if (_isConfirming) {
        _verifyConfirm();
      } else {
        _onPinComplete();
      }
    }
  }

  void _onPinComplete() {
    final pin = _pinDigits.take(_pinLength).join();
    if (pin.length < _pinLength) return;

    setState(() {
      _isConfirming = true;
    });
    // Use addPostFrameCallback so FocusNode's TextField is guaranteed built
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _confirmFocusNodes[0].requestFocus();
      }
    });
  }

  void _verifyConfirm() {
    final pin = _pinDigits.take(_pinLength).join();
    final confirm = _confirmDigits.take(_pinLength).join();
    if (confirm.length < _pinLength) return;

    if (pin != confirm) {
      HapticFeedback.heavyImpact();
      setState(() {
        _error = S.of(context).appLockPinMismatch;
      });
      for (var i = 0; i < _pinLength; i++) {
        _confirmDigits[i] = '';
        _confirmControllers[i].text = '';
      }
      _confirmFocusNodes[0].requestFocus();
      return;
    }

    // PINs match — save and enable
    _saveAndFinish(pin);
  }

  Future<void> _saveAndFinish(String pin) async {
    try {
      final service = AppLockService.instance;
      if (widget.changePin) {
        await service.setPin(pin);
      } else {
        await service.enable(
          biometric: _canUseBiometric && _useBiometric,
          pin: pin,
        );
      }
      if (mounted) {
        HapticFeedback.lightImpact();
        Navigator.pop(context, true);
      }
    } catch (e, stack) {
      LogService.instance.error('[AppLockService] _saveAndFinish ERROR: $e\n$stack', tag: 'AppLock');
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  Widget _buildPinFields(
    List<String> digits,
    List<TextEditingController> controllers,
    List<FocusNode> focusNodes,
    bool isConfirm,
  ) {
    final cs = Theme.of(context).colorScheme;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        _pinLength,
        (i) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: SizedBox(
            width: 44,
            height: 52,
            child: TextField(
              controller: controllers[i],
              focusNode: focusNodes[i],
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: i == 0 ? _pinLength : 1,
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: cs.onSurface,
              ),
              decoration: InputDecoration(
                counterText: '',
                filled: true,
                fillColor: isConfirm && i == 0 && digits[i].isNotEmpty
                    ? cs.primary.withValues(alpha: 0.08)
                    : cs.surfaceContainerHighest.withValues(alpha: 0.4),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: cs.primary, width: 2),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(
                    color: digits[i].isNotEmpty
                        ? cs.primary.withValues(alpha: 0.4)
                        : cs.outline.withValues(alpha: 0.3),
                  ),
                ),
              ),
              onChanged: (value) => _onDigitChange(
                  digits, controllers, focusNodes, i, value),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final s = S.of(context);

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Drag handle
              Container(
                width: 32,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: cs.onSurfaceVariant.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),

              // Icon
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  color: cs.primaryContainer.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  widget.changePin ? Icons.password_rounded : Icons.lock_outline_rounded,
                  size: 32,
                  color: cs.primary,
                ),
              ),
              const SizedBox(height: 16),

              // Title
              Text(
                widget.changePin ? s.appLockChangePin : s.appLockSetupTitle,
                style: tt.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 4),

              // Subtitle
              Text(
                widget.changePin
                    ? s.appLockChangePinSubtitle
                    : (!_isConfirming
                        ? s.appLockSetupPinSubtitle
                        : s.appLockSetupConfirmSubtitle),
                style: tt.bodyMedium?.copyWith(
                  color: cs.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 28),

              // PIN length selector (only at setup, not confirm)
              if (!_isConfirming && !widget.changePin)
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _buildPinLengthChip(4, s),
                    const SizedBox(width: 12),
                    _buildPinLengthChip(6, s),
                  ],
                ),

              if (!_isConfirming && !widget.changePin)
                const SizedBox(height: 20),

              // Error
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: cs.error.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.error_outline, size: 16, color: cs.error),
                        const SizedBox(width: 6),
                        Text(
                          _error!,
                          style: TextStyle(color: cs.error, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ),

              // PIN fields
              _buildPinFields(
                _isConfirming ? _confirmDigits : _pinDigits,
                _isConfirming ? _confirmControllers : _pinControllers,
                _isConfirming ? _confirmFocusNodes : _pinFocusNodes,
                _isConfirming,
              ),

              // Biometric toggle (only on initial setup)
              if (!widget.changePin && !_isConfirming && _canUseBiometric)
                Padding(
                  padding: const EdgeInsets.only(top: 24),
                  child: SwitchListTile(
                    title: Text(s.appLockUseBiometric),
                    subtitle: Text(
                      s.appLockBiometricSubtitle,
                      style: tt.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    value: _useBiometric,
                    onChanged: (v) => setState(() => _useBiometric = v),
                    secondary: Icon(
                      Icons.fingerprint,
                      color: cs.primary,
                    ),
                  ),
                ),

              // Back / Confirm / Cancel buttons
              Padding(
                padding: const EdgeInsets.only(top: 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    if (_isConfirming)
                      TextButton(
                        onPressed: () {
                          setState(() {
                            _isConfirming = false;
                            for (var i = 0; i < _pinLength; i++) {
                              _confirmDigits[i] = '';
                              _confirmControllers[i].text = '';
                            }
                          });
                        },
                        child: Text(s.back),
                      ),
                    if (_isConfirming) const SizedBox(width: 12),
                    if (_isConfirming)
                      FilledButton(
                        onPressed: _confirmDigits.take(_pinLength).join().length == _pinLength
                            ? () => _verifyConfirm()
                            : null,
                        child: Text(s.confirm),
                      ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text(s.cancel),
                    ),
                  ],
                ),
              ),

              SizedBox(height: MediaQuery.of(context).padding.bottom),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPinLengthChip(int length, S s) {
    final cs = Theme.of(context).colorScheme;
    final selected = _pinLength == length;

    return GestureDetector(
      onTap: () {
        setState(() {
          _pinLength = length;
          // Clear current digits
          for (var i = 0; i < 6; i++) {
            _pinDigits[i] = '';
            _pinControllers[i].text = '';
          }
          _pinFocusNodes[0].requestFocus();
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? cs.primary.withValues(alpha: 0.12)
              : cs.surfaceContainerHighest.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected
                ? cs.primary
                : cs.outline.withValues(alpha: 0.2),
            width: selected ? 2 : 1,
          ),
        ),
        child: Text(
          '$length ${s.appLockDigits}',
          style: TextStyle(
            color: selected ? cs.primary : cs.onSurfaceVariant,
            fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
          ),
        ),
      ),
    );
  }
}
