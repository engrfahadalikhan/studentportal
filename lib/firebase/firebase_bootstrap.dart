import 'package:firebase_core/firebase_core.dart';

import '../firebase_options.dart';

class FirebaseBootstrap {
  static FirebaseConnectionStatus _status = const FirebaseConnectionStatus(
    projectId: 'Unknown',
    appId: 'Unknown',
    isInitialized: false,
    errorMessage: null,
  );

  static FirebaseConnectionStatus get connectionSummary => _status;

  static Future<void> initialize() async {
    try {
      FirebaseApp app;

      if (Firebase.apps.isNotEmpty) {
        app = Firebase.app();
      } else {
        try {
          app = await Firebase.initializeApp(
            options: DefaultFirebaseOptions.currentPlatform,
          );
        } on FirebaseException catch (error) {
          if (error.code != 'duplicate-app') {
            rethrow;
          }

          app = Firebase.app();
        }
      }

      _status = FirebaseConnectionStatus(
        projectId: app.options.projectId,
        appId: app.options.appId,
        isInitialized: true,
        errorMessage: null,
      );
    } catch (error) {
      _status = FirebaseConnectionStatus(
        projectId: 'Unavailable',
        appId: 'Unavailable',
        isInitialized: false,
        errorMessage: error.toString(),
      );
    }
  }
}

class FirebaseConnectionStatus {
  const FirebaseConnectionStatus({
    required this.projectId,
    required this.appId,
    required this.isInitialized,
    required this.errorMessage,
  });

  final String projectId;
  final String appId;
  final bool isInitialized;
  final String? errorMessage;
}
