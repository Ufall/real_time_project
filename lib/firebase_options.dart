import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

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
      // case TargetPlatform.macOS:
      //   return macOS;
      case TargetPlatform.windows:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for windows - '
              'you can reconfigure this by manually updating firebase_options.dart.',
        );
      case TargetPlatform.linux:
        throw UnsupportedError(
          'DefaultFirebaseOptions have not been configured for linux - '
              'you can reconfigure this by manually updating firebase_options.dart.',
        );
      default:
        throw UnsupportedError(
          'DefaultFirebaseOptions are not supported for this platform.',
        );
    }
  }

  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'YOUR_WEB_API_KEY_HERE',  // From Console: Project Settings > General > Web API Key
    appId: 'YOUR_WEB_APP_ID_HERE',    // If adding web app
    messagingSenderId: 'YOUR_SENDER_ID',  // Project Settings > Cloud Messaging > Sender ID
    projectId: 'YOUR_PROJECT_ID',     // Project Settings > General > Project ID
    authDomain: 'YOUR_PROJECT_ID.firebaseapp.com',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',  // If using Storage
    measurementId: 'YOUR_MEASUREMENT_ID',  // If using Analytics
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'YOUR_ANDROID_API_KEY',   // Console: Project Settings > General > Android apps > Your app > API Key
    appId: 'YOUR_ANDROID_APP_ID',     // e.g., '1:1234567890:android:abcdef123456'
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
  );

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'YOUR_IOS_API_KEY',       // Console: Project Settings > General > iOS apps > Your app > iOS API Key
    appId: 'YOUR_IOS_APP_ID',         // e.g., '1:1234567890:ios:abcdef123456'
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'YOUR_IOS_BUNDLE_ID',  // e.g., 'com.example.busTrackerApp'
  );

  static const FirebaseOptions macos = FirebaseOptions(
    apiKey: 'YOUR_MACOS_API_KEY',
    appId: 'YOUR_MACOS_APP_ID',
    messagingSenderId: 'YOUR_SENDER_ID',
    projectId: 'YOUR_PROJECT_ID',
    storageBucket: 'YOUR_PROJECT_ID.appspot.com',
    iosBundleId: 'YOUR_MACOS_BUNDLE_ID',
  );
}