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
      default:
        return web;
    }
  }

  // Web config from Firebase Console
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyDGKYlgbZHcNJvnUi_oNBMkDkCugvFaSyo',
    authDomain: 'abor-day-pay-calculator.firebaseapp.com',
    projectId: 'abor-day-pay-calculator',
    storageBucket: 'abor-day-pay-calculator.firebasestorage.app',
    messagingSenderId: '888275904157',
    appId: '1:888275904157:web:4f87d615c3bd2fd8bb5674',
  );

  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyDZK0UYA8jxEbT0QI9s7x3b7zG7nHrochY',
    appId: '1:888275904157:android:d3849e1b026450d1bb5674',
    messagingSenderId: '888275904157',
    projectId: 'abor-day-pay-calculator',
    storageBucket: 'abor-day-pay-calculator.firebasestorage.app',
  );

  // TODO: Add iOS config when ready to publish
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'TODO',
    appId: 'TODO',
    messagingSenderId: '888275904157',
    projectId: 'abor-day-pay-calculator',
    storageBucket: 'abor-day-pay-calculator.firebasestorage.app',
    iosBundleId: 'com.example.laborDayPayCalculator',
  );
}
