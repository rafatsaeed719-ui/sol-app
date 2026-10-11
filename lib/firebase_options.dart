import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

// بيانات مشروع Firebase (sol-app-9ebbe)
const FirebaseOptions _android = FirebaseOptions(
  apiKey: 'AIzaSyBDXIM56gTqtRt550_sKRWKdd9R37k3nJE',
  appId: '1:436099253442:android:83773f9b0933355011e75b',
  messagingSenderId: '436099253442',
  projectId: 'sol-app-9ebbe',
  storageBucket: 'sol-app-9ebbe.firebasestorage.app',
);

// نسخة الويب (WEB_API_KEY / WEB_APP_ID بتتملى من إعدادات Firebase للويب)
const FirebaseOptions _web = FirebaseOptions(
  apiKey: 'WEB_API_KEY',
  appId: 'WEB_APP_ID',
  messagingSenderId: '436099253442',
  projectId: 'sol-app-9ebbe',
  authDomain: 'sol-app-9ebbe.firebaseapp.com',
  storageBucket: 'sol-app-9ebbe.firebasestorage.app',
);

FirebaseOptions get solFirebaseOptions => kIsWeb ? _web : _android;
