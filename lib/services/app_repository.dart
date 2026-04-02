import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/app_role.dart';
import '../models/app_user_profile.dart';
import '../models/feature_visibility.dart';

class AppRepository {
  AppRepository({FirebaseAuth? auth, FirebaseFirestore? firestore})
    : _auth = auth ?? FirebaseAuth.instance,
      _firestore = firestore ?? FirebaseFirestore.instance;

  final FirebaseAuth _auth;
  final FirebaseFirestore _firestore;

  CollectionReference<Map<String, dynamic>> get _users =>
      _firestore.collection('users');

  DocumentReference<Map<String, dynamic>> get _featureVisibilityDoc =>
      _firestore.collection('app_settings').doc('feature_visibility');

  Stream<User?> authStateChanges() => _auth.authStateChanges();

  Future<void> signIn({required String email, required String password}) async {
    await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  Future<void> register({
    required String name,
    required String email,
    required String password,
    required AppRole requestedRole,
  }) async {
    final credential = await _auth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );

    final user = credential.user;
    if (user == null) {
      throw FirebaseAuthException(
        code: 'user-not-created',
        message: 'Unable to create your account right now.',
      );
    }

    await user.updateDisplayName(name.trim());
    await ensureUserProfile(
      user,
      requestedRole: requestedRole,
      preferredName: name.trim(),
    );
  }

  Future<void> signOut() => _auth.signOut();

  Future<AppUserProfile> ensureUserProfile(
    User user, {
    AppRole? requestedRole,
    String? preferredName,
  }) async {
    await ensureFeatureVisibilityExists();

    final existing = await _users.doc(user.uid).get();
    if (existing.exists && existing.data() != null) {
      await _users.doc(user.uid).set({
        'lastLoginAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      final refreshed = await _users.doc(user.uid).get();
      return AppUserProfile.fromMap(user.uid, refreshed.data()!);
    }

    final adminExists = await _users
        .where('role', isEqualTo: AppRole.admin.key)
        .limit(1)
        .get();

    final assignedRole = adminExists.docs.isEmpty
        ? AppRole.admin
        : requestedRole ?? AppRole.student;

    final trimmedName = preferredName?.trim();
    final fallbackName = user.displayName?.trim();
    final resolvedName =
        (trimmedName?.isNotEmpty == true
            ? trimmedName
            : fallbackName?.isNotEmpty == true
            ? fallbackName
            : null) ??
        _nameFromEmail(user.email);

    await _users.doc(user.uid).set({
      'uid': user.uid,
      'name': resolvedName,
      'email': user.email,
      'role': assignedRole.key,
      'createdAt': FieldValue.serverTimestamp(),
      'lastLoginAt': FieldValue.serverTimestamp(),
    });

    final created = await _users.doc(user.uid).get();
    return AppUserProfile.fromMap(user.uid, created.data()!);
  }

  Stream<AppUserProfile?> watchUserProfile(String uid) {
    return _users.doc(uid).snapshots().map((snapshot) {
      final data = snapshot.data();
      if (!snapshot.exists || data == null) {
        return null;
      }

      return AppUserProfile.fromMap(snapshot.id, data);
    });
  }

  Stream<FeatureVisibility> watchFeatureVisibility() {
    return _featureVisibilityDoc.snapshots().map((snapshot) {
      return FeatureVisibility.fromMap(snapshot.data());
    });
  }

  Stream<List<AppUserProfile>> watchAllUsers() {
    return _users.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => AppUserProfile.fromMap(doc.id, doc.data()))
          .toList();
    });
  }

  Future<void> updateRoleFeature({
    required AppRole role,
    required String featureKey,
    required bool enabled,
  }) async {
    await _featureVisibilityDoc.set({
      'roles': {
        role.key: {featureKey: enabled},
      },
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> ensureFeatureVisibilityExists() async {
    final snapshot = await _featureVisibilityDoc.get();
    if (!snapshot.exists) {
      await _featureVisibilityDoc.set({
        ...FeatureVisibility(roles: FeatureVisibility.defaultRoles()).toMap(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    }
  }

  String _nameFromEmail(String? email) {
    if (email == null || email.trim().isEmpty) {
      return 'Portal User';
    }

    final localPart = email.split('@').first.trim();
    if (localPart.isEmpty) {
      return 'Portal User';
    }

    final normalized = localPart.replaceAll(RegExp(r'[._-]+'), ' ');
    return normalized
        .split(' ')
        .where((part) => part.isNotEmpty)
        .map((part) => '${part[0].toUpperCase()}${part.substring(1)}')
        .join(' ');
  }
}
