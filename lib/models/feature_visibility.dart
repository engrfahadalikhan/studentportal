import 'app_role.dart';

class FeatureVisibility {
  const FeatureVisibility({required this.roles});

  final Map<String, Map<String, bool>> roles;

  static Map<String, Map<String, bool>> defaultRoles() {
    return {
      AppRole.admin.key: {
        'user_management': true,
        'feature_controls': true,
        'analytics': true,
      },
      AppRole.faculty.key: {
        'course_manager': true,
        'attendance_entry': true,
        'grading_tools': true,
        'materials_center': true,
        'schedule_board': true,
      },
      AppRole.student.key: {
        'announcements': true,
        'assignments': true,
        'attendance_view': true,
        'results': true,
        'schedule_board': true,
      },
    };
  }

  factory FeatureVisibility.fromMap(Map<String, dynamic>? map) {
    final source = map?['roles'];
    final roles = defaultRoles();

    if (source is Map<String, dynamic>) {
      for (final entry in source.entries) {
        if (entry.value is Map<String, dynamic>) {
          final merged = <String, bool>{...roles[entry.key] ?? const {}};
          for (final featureEntry
              in (entry.value as Map<String, dynamic>).entries) {
            final value = featureEntry.value;
            if (value is bool) {
              merged[featureEntry.key] = value;
            }
          }
          roles[entry.key] = merged;
        }
      }
    }

    return FeatureVisibility(roles: roles);
  }

  Map<String, dynamic> toMap() {
    return {
      'roles': roles.map(
        (key, value) => MapEntry(key, value.map((k, v) => MapEntry(k, v))),
      ),
    };
  }

  Map<String, bool> forRole(AppRole role) {
    return roles[role.key] ?? const {};
  }

  bool isEnabled(AppRole role, String featureKey) {
    return forRole(role)[featureKey] ?? false;
  }
}
