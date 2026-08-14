import 'dart:io';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../firebase_options.dart';
import 'log_service.dart';

/// Thin wrapper around Firebase Analytics.
///
/// The official Firebase Analytics SDK only supports Android, iOS, macOS and
/// Web — Windows and Linux desktop are skipped. All failures are logged and
/// never crash the app, so analytics is purely additive.
class AnalyticsService {
  AnalyticsService._();
  static final AnalyticsService instance = AnalyticsService._();

  final _log = LogService.instance;
  FirebaseAnalytics? _analytics;

  /// Whether Analytics is available on the current platform.
  static bool get isSupported =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  Future<void> initialize() async {
    if (!isSupported) return;
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
      _analytics = FirebaseAnalytics.instance;
      _log.info('[Analytics] Initialized', tag: 'Analytics');
    } catch (e) {
      _log.warning('[Analytics] Init failed: $e', tag: 'Analytics');
    }
  }

  Future<void> logEvent(String name, {Map<String, Object>? parameters}) async {
    final analytics = _analytics;
    if (analytics == null) return;
    try {
      await analytics.logEvent(name: name, parameters: parameters);
    } catch (e) {
      _log.debug('[Analytics] logEvent($name) failed: $e', tag: 'Analytics');
    }
  }
}
