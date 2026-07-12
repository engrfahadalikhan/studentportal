import 'package:cloud_firestore/cloud_firestore.dart';

const int kAustPortalBuildNumber = 117;
const String kAustPortalVersionName = '2.13.9';
const String kAustPortalVersionLabel = 'v$kAustPortalVersionName';

const String kFirestoreNamespaceCollection = 'aust_portal_v2';
const String kFirestoreNamespaceDocument = 'data';
const String kAppControlCollection = 'app_control';
const String kAppControlDocument = 'aust_portal';

class FirebasePaths {
  const FirebasePaths._();

  static DocumentReference<Map<String, dynamic>> get appControlDoc =>
      FirebaseFirestore.instance
          .collection(kAppControlCollection)
          .doc(kAppControlDocument);

  static CollectionReference<Map<String, dynamic>> collection(String name) =>
      FirebaseFirestore.instance
          .collection(kFirestoreNamespaceCollection)
          .doc(kFirestoreNamespaceDocument)
          .collection(name);

  static DocumentReference<Map<String, dynamic>> doc(
    String collection,
    String id,
  ) => FirebasePaths.collection(collection).doc(id);

  static Map<String, Object?> clientWriteMeta() => const {
    'client_build': kAustPortalBuildNumber,
    'client_version': kAustPortalVersionName,
    'client_namespace':
        '$kFirestoreNamespaceCollection/$kFirestoreNamespaceDocument',
  };
}
