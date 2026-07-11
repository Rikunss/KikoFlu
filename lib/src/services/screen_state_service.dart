import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'app_lock_service.dart';

/// Bridges Android screen-off events to [AppLockService] for auto-relock.
///
/// When the screen turns off while audio is playing with a foreground
/// notification, the app lifecycle may stay in [AppLifecycleState.resumed]
/// and our [WidgetsBindingObserver] won't detect the screen-off. This
/// service listens to a native BroadcastReceiver via MethodChannel to
/// reliably catch screen off and start the auto-relock timer.
///
/// The actual relock + UI rebuild is handled by the existing
/// [WidgetsBindingObserver.didChangeAppLifecycleState] handler in
/// `main.dart` which processes [AppLifecycleState.resumed] and calls
/// [setState] to force a widget tree rebuild with the new lock generation.
class ScreenStateService {
  ScreenStateService._();
  static final ScreenStateService instance = ScreenStateService._();

  static const _channelName = 'com.kikoeru.flutter/screen_state';
  static const _methodScreenOff = 'screenOff';

  final MethodChannel _channel = const MethodChannel(_channelName);
  bool _initialized = false;

  /// Start listening for screen state changes.
  ///
  /// Safe to call multiple times — only registers once.
  void initialize() {
    if (_initialized) return;
    if (!Platform.isAndroid) return;

    _initialized = true;
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  Future<void> _handleMethodCall(MethodCall call) async {
    if (!AppLockService.instance.isEnabled) return;

    if (call.method == _methodScreenOff) {
      AppLockService.instance.notifyAppBackgrounded();
    }
  }
}