import 'package:flutter/material.dart';

import '../assessment/teacher_assessment_shell.dart';
import '../services/app_repository.dart';
import 'auth_landing_page.dart';
import 'dashboard_page.dart';
import 'student_portal_shell.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final session = repository.currentSession;
        if (session == null) {
          return AuthLandingPage(repository: repository);
        }

        if (session.isStudent && session.student != null) {
          return StudentPortalShell(
            repository: repository,
            student: session.student!,
          );
        }

        if (session.isTeacher && session.teacher != null) {
          return TeacherAssessmentShell(
            repository: repository,
            teacher: session.teacher!,
          );
        }

        return DashboardPage(repository: repository, session: session);
      },
    );
  }
}
