// Firebase Options for BizPOS Sales app
// Using same Firebase backend as bizpos-clone project

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
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
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for macos.',
        );
      case TargetPlatform.windows:
        return android;
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCJkt-vet9FodlKezPhFr3ujgZIzOvIOhQ',
    appId: '1:259223330355:android:ed7bb40c9e62c9c0dbcd46',
    messagingSenderId: '259223330355',
    projectId: 'bizpos-clone',
    storageBucket: 'bizpos-clone.firebasestorage.app',
  );

  // Web config — uses same project, register a web app if needed
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyAQ4ZosJ8RdK0K5kQ7IRQFyb2DjaK3iwM4',
    appId: '1:259223330355:web:1941d2534f55a267dbcd46',
    messagingSenderId: '259223330355',
    projectId: 'bizpos-clone',
    authDomain: 'bizpos-clone.firebaseapp.com',
    storageBucket: 'bizpos-clone.firebasestorage.app',
  );

  // iOS config — register an iOS app in Firebase Console when needed
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyCJkt-vet9FodlKezPhFr3ujgZIzOvIOhQ',
    appId: '1:259223330355:ios:placeholder_sales',
    messagingSenderId: '259223330355',
    projectId: 'bizpos-clone',
    storageBucket: 'bizpos-clone.firebasestorage.app',
    iosBundleId: 'com.bizpos.sales',
  );
}
