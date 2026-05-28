import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';
import 'feature_catalog.dart';

/// Tracks which features are visible to which non-admin roles.
/// Admins always see everything (they need to be able to toggle modules).
///
/// Persisted to SharedPreferences so admin toggles survive a restart even
/// before the firebase/hostinger sync layer is wired in.
class FeatureVisibilityService extends ChangeNotifier {
  FeatureVisibilityService._();
  static final FeatureVisibilityService instance =
      FeatureVisibilityService._();

  static const String _prefsKey = 'feature_visibility_v1';

  /// Default = a friendly subset on so the app isn't empty on first launch.
  static final Map<FeatureKey, _RoleFlags> _defaults = {
    for (final meta in featureCatalog)
      meta.key: _RoleFlags(
        student: _defaultOnForStudent(meta),
        teacher: _defaultOnForTeacher(meta),
      ),
  };

  static bool _defaultOnForStudent(FeatureMeta meta) {
    if (meta.audience == FeatureAudience.teacher) return false;
    // Tier 1 + FYP + Internships on by default for students.
    return meta.tier <= 1 || meta.key == FeatureKey.internships;
  }

  static bool _defaultOnForTeacher(FeatureMeta meta) {
    if (meta.audience == FeatureAudience.student) return false;
    return meta.tier <= 1;
  }

  final Map<FeatureKey, _RoleFlags> _flags = {
    for (final entry in _defaults.entries)
      entry.key: _RoleFlags(
        student: entry.value.student,
        teacher: entry.value.teacher,
      ),
  };

  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_prefsKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          for (final entry in decoded.entries) {
            final feature = FeatureKeyX.fromStorageKey(entry.key);
            if (feature == null) continue;
            final value = entry.value;
            if (value is Map<String, dynamic>) {
              _flags[feature] = _RoleFlags(
                student: value['student'] == true,
                teacher: value['teacher'] == true,
              );
            }
          }
        }
      } catch (_) {
        // Bad JSON — silently fall back to defaults.
      }
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    final encoded = jsonEncode({
      for (final entry in _flags.entries)
        entry.key.storageKey: {
          'student': entry.value.student,
          'teacher': entry.value.teacher,
        },
    });
    await prefs.setString(_prefsKey, encoded);
  }

  /// Is [feature] visible to a user of [role]?
  bool isVisible(AppRole role, FeatureKey feature) {
    if (role == AppRole.admin) return true;
    final flags = _flags[feature];
    if (flags == null) return false;
    final meta = featureMetaOf(feature);
    if (role == AppRole.student) {
      if (meta.audience == FeatureAudience.teacher) return false;
      return flags.student;
    }
    if (role == AppRole.faculty) {
      if (meta.audience == FeatureAudience.student) return false;
      return flags.teacher;
    }
    return false;
  }

  /// All features visible to [role], in catalog order.
  List<FeatureMeta> visibleFor(AppRole role) {
    return [
      for (final meta in featureCatalog)
        if (isVisible(role, meta.key)) meta,
    ];
  }

  bool studentFlag(FeatureKey feature) => _flags[feature]?.student ?? false;
  bool teacherFlag(FeatureKey feature) => _flags[feature]?.teacher ?? false;

  Future<void> setVisibility({
    required FeatureKey feature,
    required AppRole role,
    required bool visible,
  }) async {
    if (role == AppRole.admin) return; // admin is always-visible.
    final current = _flags[feature] ??
        const _RoleFlags(student: false, teacher: false);
    _flags[feature] = _RoleFlags(
      student: role == AppRole.student ? visible : current.student,
      teacher: role == AppRole.faculty ? visible : current.teacher,
    );
    notifyListeners();
    await _persist();
  }

  Future<void> resetToDefaults() async {
    _flags.clear();
    for (final entry in _defaults.entries) {
      _flags[entry.key] = _RoleFlags(
        student: entry.value.student,
        teacher: entry.value.teacher,
      );
    }
    notifyListeners();
    await _persist();
  }
}

class _RoleFlags {
  const _RoleFlags({required this.student, required this.teacher});
  final bool student;
  final bool teacher;
}
