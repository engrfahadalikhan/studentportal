import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teacher_student_assessment_app/assessment/teacher_assessment_shell.dart';
import 'package:teacher_student_assessment_app/models/app_role.dart';
import 'package:teacher_student_assessment_app/services/app_repository.dart';
import 'package:teacher_student_assessment_app/services/teacher_dashboard_database.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('admin and teacher dashboards have local database data', () async {
    final repository = AppRepository();

    expect(repository.teachers, isNotEmpty);
    expect(repository.assessmentCourses, isNotEmpty);
    expect(repository.assessments, isNotEmpty);
    expect(repository.verificationOfficers, isNotEmpty);

    final summary = await repository.loadAdminSummary();
    expect(summary.studentCount, greaterThan(0));
    expect(summary.courseRegistrationCount, greaterThan(0));

    final teacher = repository.teachers.first;
    await repository.signIn(
      role: AppRole.faculty,
      username: teacher.email,
      password: '',
    );

    expect(repository.coursesForTeacher(teacher), isNotEmpty);
    expect(repository.assessmentsForTeacher(teacher), isNotEmpty);

    final home = await TeacherDashboardDatabase.instance.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );
    expect(home.courses, isNotEmpty);
    expect(home.totalCourses, greaterThan(0));

    final asim = repository.teachers.firstWhere(
      (teacher) => teacher.name == 'DR. ASIM SHAHZAD',
    );
    final asimHome = await TeacherDashboardDatabase.instance.loadTeacherHome(
      teacherId: asim.id,
      teacherName: asim.name,
    );
    expect(asimHome.courses, isNotEmpty);
  });

  testWidgets('teacher dashboard renders database course cards', (
    tester,
  ) async {
    final repository = AppRepository();
    final teacher = repository.teachers.firstWhere(
      (teacher) => teacher.name == 'DR. ASIM SHAHZAD',
      orElse: () => repository.teachers.first,
    );
    await tester.runAsync(() async {
      await TeacherDashboardDatabase.instance.loadTeacherHome(
        teacherId: teacher.id,
        teacherName: teacher.name,
      );
    });

    for (final size in const [Size(1400, 1000), Size(582, 760)]) {
      await tester.binding.setSurfaceSize(size);
      await tester.pumpWidget(
        MaterialApp(
          home: TeacherAssessmentShell(
            repository: repository,
            teacher: teacher,
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 500));
      });
      await tester.pump(const Duration(seconds: 5));

      expect(find.text('Home'), findsOneWidget);
      expect(find.text('Assessment Generator'), findsOneWidget);
      expect(find.text('Exam Attendance'), findsAtLeastNWidgets(1));
      expect(
        find.text('Welcome, Teacher ${teacher.name}'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('Registered courses'), findsAtLeastNWidgets(1));
    }
  });

  test('exam attendance scan save and share flow uses sqflite', () async {
    final repository = AppRepository();
    final teacher = repository.teachers.firstWhere(
      (teacher) => teacher.name == 'DR. ASIM SHAHZAD',
      orElse: () => repository.teachers.first,
    );
    final database = TeacherDashboardDatabase.instance;
    final home = await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );
    final course = home.courses.first;
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'hallId': 'AUST-H1',
        'hallName': 'Hall H1',
        'courseId': course.id,
        'courseName': course.courseName,
        'examDateTime': '2026-05-23T09:00:00',
        'totalExpectedStudents': course.totalStudents,
      }),
    );

    expect(stats.courseId, course.id);
    expect(stats.totalStudents, greaterThan(0));

    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students, isNotEmpty);

    await database.saveAttendanceStatuses(
      sheetId: stats.sheetId,
      statusesByStudentId: {students.first.studentId: 'present'},
    );
    final detail = await database.loadAttendanceSheetDetail(stats.sheetId);
    expect(detail.stats.presentStudents, 1);

    final payload = await database.shareAttendanceSheet(
      teacherId: teacher.id,
      sheetId: stats.sheetId,
      sharedWith: 'Admin',
    );
    expect(payload, contains('Course: ${course.courseName}'));

    final sharing = await database.loadAttendanceSharing(teacher.id);
    expect(sharing.sharedSheets, isNotEmpty);

    final notifications = await database.loadNotifications(teacher.id);
    expect(notifications, isNotEmpty);
  });
}
