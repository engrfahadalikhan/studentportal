enum AppRole { admin, faculty, student }

extension AppRoleX on AppRole {
  String get key => name;

  String get label {
    switch (this) {
      case AppRole.admin:
        return 'Admin';
      case AppRole.faculty:
        return 'Faculty';
      case AppRole.student:
        return 'Student';
    }
  }

  String get headline {
    switch (this) {
      case AppRole.admin:
        return 'Control Center';
      case AppRole.faculty:
        return 'Faculty Workspace';
      case AppRole.student:
        return 'Student Hub';
    }
  }

  static AppRole fromString(String? value) {
    switch (value) {
      case 'admin':
        return AppRole.admin;
      case 'faculty':
        return AppRole.faculty;
      case 'student':
      default:
        return AppRole.student;
    }
  }
}
