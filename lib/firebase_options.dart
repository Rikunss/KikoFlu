import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDSqfJA--FBjWoHh6QjHNOj8er_yOFb_us',
    appId: '1:99849637607:android:2231dd02c3f6bbf8ef1c42',
    messagingSenderId: '99849637607',
    projectId: 'kikofluedge',
    storageBucket: 'kikofluedge.firebasestorage.app',
  );
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyDgBVIyffWYNgeXuUrgJYRFYcv6nfIm9hU',
    appId: '1:99849637607:ios:491a22dffa9adf73ef1c42',
    messagingSenderId: '99849637607',
    projectId: 'kikofluedge',
    storageBucket: 'kikofluedge.firebasestorage.app',
    iosBundleId: 'com.kikoflu.edge',
  );
  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'AIzaSyDgBVIyffWYNgeXuUrgJYRFYcv6nfIm9hU',
    appId: '1:99849637607:ios:491a22dffa9adf73ef1c42',
    messagingSenderId: '99849637607',
    projectId: 'kikofluedge',
    storageBucket: 'kikofluedge.firebasestorage.app',
    iosBundleId: 'com.kikoflu.edge',
  );
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions windows = FirebaseOptions(
    apiKey: 'AIzaSyAFyrlAddidnZW4aAjHyITD0FVdg_hrwYk',
    appId: '1:99849637607:web:bd437e3fa22d4b65ef1c42',
    messagingSenderId: '99849637607',
    projectId: 'kikofluedge',
    authDomain: 'kikofluedge.firebaseapp.com',
    storageBucket: 'kikofluedge.firebasestorage.app',
  );
  static const FirebaseOptions linux = FirebaseOptions(
    apiKey: 'YOUR_API_KEY',
    appId: 'YOUR_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      return web;
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      case TargetPlatform.macOS:
        return macos;
      case TargetPlatform.windows:
        return windows;
      case TargetPlatform.linux:
        return linux;
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not configured for this platform.',
        );
    }
  }
}
