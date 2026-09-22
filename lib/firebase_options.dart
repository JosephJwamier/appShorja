import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart'
    show defaultTargetPlatform, kIsWeb, TargetPlatform;

class DefaultFirebaseOptions {
  static FirebaseOptions get currentPlatform {
    if (kIsWeb) {
      throw UnsupportedError(
        'Firebase Web is not configured. Run the app on Android or iOS.',
      );
    }
    switch (defaultTargetPlatform) {
      case TargetPlatform.android:
        return android;
      case TargetPlatform.iOS:
        return ios;
      default:
        throw UnsupportedError(
          'Unsupported platform: $defaultTargetPlatform',
        );
    }
  }

  // Values extracted from google-services.json
  static const FirebaseOptions android = FirebaseOptions(
    apiKey: 'AIzaSyCtFH_IZ_EfFIj9zrr8bs8oFbn12GTKotA',
    appId: '1:78176989926:android:ea5a5f9512e0c21036c127',
    messagingSenderId: '78176989926',
    projectId: 'balla-c917b',
    storageBucket: 'balla-c917b.firebasestorage.app',
  );

  // Values extracted from ios/Runner/GoogleService-Info.plist
  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'AIzaSyB4gmFuALNxhtjKH7okVRqRN6iHuzw8qWM',
    appId: '1:78176989926:ios:f1626065c448288036c127',
    messagingSenderId: '78176989926',
    projectId: 'balla-c917b',
    storageBucket: 'balla-c917b.firebasestorage.app',
    iosBundleId: 'com.balla.balla',
    iosClientId:
        '78176989926-9bo83u0cjuv3jilhhpbohs4kq997q7hv.apps.googleusercontent.com',
  );
}
