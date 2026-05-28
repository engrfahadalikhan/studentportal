import '../assessment/assessment_models.dart';
import 'app_role.dart';
import 'student_record.dart';

class PortalSession {
  const PortalSession._({
    required this.role,
    required this.username,
    this.student,
    this.teacher,
  });

  factory PortalSession.admin() {
    return const PortalSession._(role: AppRole.admin, username: 'admin');
  }

  factory PortalSession.student(StudentRecord student) {
    return PortalSession._(
      role: AppRole.student,
      username: student.rollNo,
      student: student,
    );
  }

  factory PortalSession.teacher(AssessmentTeacher teacher) {
    return PortalSession._(
      role: AppRole.faculty,
      username: teacher.email,
      teacher: teacher,
    );
  }

  final AppRole role;
  final String username;
  final StudentRecord? student;
  final AssessmentTeacher? teacher;

  bool get isAdmin => role == AppRole.admin;
  bool get isTeacher => role == AppRole.faculty;
  bool get isStudent => role == AppRole.student;
}
