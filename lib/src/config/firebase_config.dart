import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

import '../../firebase_options.dart' show DefaultFirebaseOptions;

class FirebaseConfig {
  FirebaseConfig._();

  static FirebaseOptions get _options {
    final current = DefaultFirebaseOptions.currentPlatform;
    if (!_isPlaceholder(current)) return current;

    const candidates = [
      DefaultFirebaseOptions.android,
      DefaultFirebaseOptions.ios,
      DefaultFirebaseOptions.macos,
      DefaultFirebaseOptions.windows,
      DefaultFirebaseOptions.web,
      DefaultFirebaseOptions.linux,
    ];
    for (final candidate in candidates) {
      if (!_isPlaceholder(candidate)) return candidate;
    }
    return current;
  }

  static bool _isPlaceholder(FirebaseOptions options) =>
      options.projectId.startsWith('YOUR_') ||
      options.apiKey.startsWith('YOUR_') ||
      options.appId.startsWith('YOUR_');

  static String get projectId => _options.projectId;

  static String get apiKey => _options.apiKey;

  static String get appId => _options.appId;

  static const String informationPopupParam = 'information_popup';

  static bool get isConfigured => !_isPlaceholder(_options);
}
