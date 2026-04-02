import 'package:cloud_firestore/cloud_firestore.dart';

import 'app_role.dart';

class AppUserProfile {
  const AppUserProfile({
    required this.uid,
    required this.name,
    required this.email,
    required this.role,
    this.createdAt,
    this.lastLoginAt,
  });

  final String uid;
  final String name;
  final String email;
  final AppRole role;
  final DateTime? createdAt;
  final DateTime? lastLoginAt;

  factory AppUserProfile.fromMap(String uid, Map<String, dynamic> map) {
    return AppUserProfile(
      uid: uid,
      name: (map['name'] as String?)?.trim().isNotEmpty == true
          ? (map['name'] as String).trim()
          : 'Portal User',
      email: (map['email'] as String?)?.trim() ?? '',
      role: AppRoleX.fromString(map['role'] as String?),
      createdAt: _toDateTime(map['createdAt']),
      lastLoginAt: _toDateTime(map['lastLoginAt']),
    );
  }

  static DateTime? _toDateTime(dynamic value) {
    if (value is Timestamp) {
      return value.toDate();
    }

    return null;
  }
}
