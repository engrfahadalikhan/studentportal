import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../assessment/assessment_mock_data.dart' as mock;
import '../assessment/assessment_models.dart';
import '../assessment/registration_course_data.dart' as registration;
import '../assessment/teacher_dashboard_models.dart';
import '../data/local_student_enrollments.dart';

class TeacherDashboardDatabase {
  TeacherDashboardDatabase._();

  static final TeacherDashboardDatabase instance = TeacherDashboardDatabase._();
  static const String _importVersion = '2026-05-23-teacher-dashboard-v3';

  Database? _db;

  Future<Database> get database async {
    final existing = _db;
    if (existing != null) {
      return existing;
    }

    final root = await getDatabasesPath();
    final db = await openDatabase(
      p.join(root, 'teacher_dashboard.sqlite'),
      version: 1,
      onCreate: (db, version) async {
        await _createTables(db);
      },
      onOpen: (db) async {
        await _createTables(db);
      },
    );
    _db = db;
    await _seedProvidedDataIfNeeded(db);
    return db;
  }

  Future<TeacherDashboardHomeData> loadTeacherHome({
    required String teacherId,
    required String teacherName,
  }) async {
    final db = await database;
    final courses = await _loadCourseSummaries(db, teacherId: teacherId);
    final unreadNotifications = await _countWhere(
      db,
      'notifications',
      'teacher_id = ? AND is_read = 0',
      [teacherId],
    );
    final attendanceSheets = await _countWhere(
      db,
      'exam_attendance_sheets',
      'teacher_id = ?',
      [teacherId],
    );
    final sharedAttendanceSheets = await _countWhere(
      db,
      'shared_attendance_sheets',
      'teacher_id = ?',
      [teacherId],
    );
    final acceptedAttendanceSheets = await _countWhere(
      db,
      'accepted_attendance_sheets',
      'teacher_id = ?',
      [teacherId],
    );
    return TeacherDashboardHomeData(
      teacherId: teacherId,
      teacherName: teacherName,
      courses: courses,
      unreadNotifications: unreadNotifications,
      attendanceSheets: attendanceSheets,
      sharedAttendanceSheets: sharedAttendanceSheets,
      acceptedAttendanceSheets: acceptedAttendanceSheets,
    );
  }

  Future<List<TeacherCourseSummary>> loadRegisteredCourses(
    String teacherId,
  ) async {
    final db = await database;
    return _loadCourseSummaries(db, teacherId: teacherId);
  }

  Future<TeacherCourseDetailData> loadCourseDetail(String courseId) async {
    final db = await database;
    final course = await _loadCourseSummary(db, courseId);
    final assessments = await _loadAssessments(db, courseId);
    return TeacherCourseDetailData(course: course, assessments: assessments);
  }

  Future<AssessmentDetailData> loadAssessmentDetail(String assessmentId) async {
    final db = await database;
    final assessment = await _loadAssessment(db, assessmentId);
    final course = await _loadCourseSummary(db, assessment.courseId);
    final students = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.roll_no, COALESCE(sub.status, 'not_submitted') AS status,
             sub.marks
      FROM course_students cs
      JOIN students s ON s.id = cs.student_id
      LEFT JOIN assessment_submissions sub
        ON sub.student_id = s.id AND sub.assessment_id = ?
      WHERE cs.course_id = ?
      ORDER BY s.name
      ''',
      [assessmentId, assessment.courseId],
    );

    final submitted = <StudentSubmissionSummary>[];
    final notSubmitted = <StudentSubmissionSummary>[];
    for (final row in students) {
      final item = StudentSubmissionSummary(
        studentId: row['id'].toString(),
        studentName: row['name'].toString(),
        rollNo: row['roll_no'].toString(),
        status: row['status'].toString(),
        marks: row['marks'] == null ? null : row['marks'] as int,
      );
      if (item.status == 'submitted') {
        submitted.add(item);
      } else {
        notSubmitted.add(item);
      }
    }

    return AssessmentDetailData(
      course: course,
      assessment: assessment,
      submittedStudents: submitted,
      notSubmittedStudents: notSubmitted,
    );
  }

  Future<CourseAssessmentSummary> insertAssessment(
    NewTeacherAssessmentInput input,
  ) async {
    final db = await database;
    final id = 'ASM${DateTime.now().millisecondsSinceEpoch}';
    await db.transaction((txn) async {
      await txn.insert('assessments', {
        'id': id,
        'course_id': input.courseId,
        'title': input.title,
        'type': input.type.key,
        'total_marks': input.totalMarks,
        'due_date': input.dueDate.toIso8601String(),
        'instructions': input.instructions,
        'created_at': DateTime.now().toIso8601String(),
      });

      final students = await txn.query(
        'course_students',
        columns: ['student_id'],
        where: 'course_id = ?',
        whereArgs: [input.courseId],
      );
      for (final student in students) {
        await txn.insert('assessment_submissions', {
          'id': 'SUB_${id}_${student['student_id']}',
          'assessment_id': id,
          'student_id': student['student_id'],
          'status': 'not_submitted',
          'marks': null,
          'submitted_at': null,
        });
      }
    });
    return _loadAssessment(db, id);
  }

  Future<void> updateAssessment(
    NewTeacherAssessmentInput input,
    String id,
  ) async {
    final db = await database;
    await db.update(
      'assessments',
      {
        'title': input.title,
        'type': input.type.key,
        'total_marks': input.totalMarks,
        'due_date': input.dueDate.toIso8601String(),
        'instructions': input.instructions,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteAssessment(String id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete(
        'assessment_submissions',
        where: 'assessment_id = ?',
        whereArgs: [id],
      );
      await txn.delete('assessments', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<void> insertTeacher(Map<String, Object?> values) async {
    final db = await database;
    await db.insert(
      'teachers',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateTeacher(String id, Map<String, Object?> values) async {
    final db = await database;
    await db.update('teachers', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteTeacher(String id) async {
    final db = await database;
    await db.delete('teachers', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertCourse(Map<String, Object?> values) async {
    final db = await database;
    await db.insert(
      'courses',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateCourse(String id, Map<String, Object?> values) async {
    final db = await database;
    await db.update('courses', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteCourse(String id) async {
    final db = await database;
    await db.delete('courses', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertStudent(Map<String, Object?> values) async {
    final db = await database;
    await db.insert(
      'students',
      values,
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> updateStudent(String id, Map<String, Object?> values) async {
    final db = await database;
    await db.update('students', values, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteStudent(String id) async {
    final db = await database;
    await db.delete('students', where: 'id = ?', whereArgs: [id]);
  }

  Future<List<TeacherNotification>> loadNotifications(String teacherId) async {
    final db = await database;
    final rows = await db.query(
      'notifications',
      where: 'teacher_id = ?',
      whereArgs: [teacherId],
      orderBy: 'created_at DESC',
    );
    return rows.map(_notificationFromRow).toList(growable: false);
  }

  Future<void> markNotificationRead(String notificationId) async {
    final db = await database;
    await db.update(
      'notifications',
      {'is_read': 1},
      where: 'id = ?',
      whereArgs: [notificationId],
    );
  }

  Future<ExamAttendanceDashboardData> loadExamAttendanceDashboard(
    String teacherId,
  ) async {
    final db = await database;
    return ExamAttendanceDashboardData(
      totalSheets: await _countWhere(
        db,
        'exam_attendance_sheets',
        'teacher_id = ?',
        [teacherId],
      ),
      sharedSheets: await _countWhere(
        db,
        'shared_attendance_sheets',
        'teacher_id = ?',
        [teacherId],
      ),
      acceptedSheets: await _countWhere(
        db,
        'accepted_attendance_sheets',
        'teacher_id = ?',
        [teacherId],
      ),
    );
  }

  Future<ExamHallStats> fetchExamHallStatsFromQr({
    required String teacherId,
    required String rawPayload,
  }) async {
    final db = await database;
    final parsed = await _parseHallQr(db, teacherId, rawPayload);
    if (!parsed.isValid) {
      throw const FormatException('Invalid QR code.');
    }
    if (parsed.courseId.isEmpty) {
      throw StateError('Hall data not found.');
    }

    final now = DateTime.now();
    final hallId = parsed.hallId.isEmpty
        ? 'HALL${_stableHash(parsed.rawPayload)}'
        : 'HALL${_stableHash('${parsed.hallId}|${parsed.courseId}|${parsed.examDateTime.toIso8601String()}')}';
    final sheetId =
        'EAS${_stableHash('$teacherId|$hallId|${parsed.courseId}|${parsed.examDateTime.toIso8601String()}')}';

    await db.transaction((txn) async {
      await txn.insert('exam_halls', {
        'id': hallId,
        'name': parsed.hallName.isEmpty ? hallId : parsed.hallName,
        'course_id': parsed.courseId,
        'exam_date_time': parsed.examDateTime.toIso8601String(),
        'expected_students': parsed.expectedStudents,
        'seat_info': parsed.seatInfo,
        'qr_payload': parsed.rawPayload,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('exam_attendance_sheets', {
        'id': sheetId,
        'teacher_id': teacherId,
        'course_id': parsed.courseId,
        'hall_id': hallId,
        'exam_date_time': parsed.examDateTime.toIso8601String(),
        'status': 'fetched',
        'created_at': now.toIso8601String(),
        'last_updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await _ensureAttendanceRecords(
        txn,
        sheetId: sheetId,
        courseId: parsed.courseId,
      );
    });

    return loadExamHallStats(sheetId);
  }

  Future<ExamHallStats> loadExamHallStats(String sheetId) async {
    final db = await database;
    return _loadExamHallStats(db, sheetId);
  }

  Future<List<ExamAttendanceStudent>> loadAttendanceStudents(
    String sheetId,
  ) async {
    final db = await database;
    final sheetRows = await db.query(
      'exam_attendance_sheets',
      columns: ['course_id'],
      where: 'id = ?',
      whereArgs: [sheetId],
      limit: 1,
    );
    if (sheetRows.isEmpty) {
      throw StateError('Hall data not found.');
    }
    await db.transaction((txn) async {
      await _ensureAttendanceRecords(
        txn,
        sheetId: sheetId,
        courseId: sheetRows.first['course_id'].toString(),
      );
    });
    return _loadAttendanceStudents(db, sheetId);
  }

  Future<ExamAttendanceSheetDetail> loadAttendanceSheetDetail(
    String sheetId,
  ) async {
    final stats = await loadExamHallStats(sheetId);
    final students = await loadAttendanceStudents(sheetId);
    return ExamAttendanceSheetDetail(stats: stats, students: students);
  }

  Future<void> saveAttendanceStatuses({
    required String sheetId,
    required Map<String, String> statusesByStudentId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      final batch = txn.batch();
      for (final entry in statusesByStudentId.entries) {
        batch.update(
          'exam_attendance_records',
          {'status': entry.value, 'marked_at': now},
          where: 'sheet_id = ? AND student_id = ?',
          whereArgs: [sheetId, entry.key],
        );
      }
      batch.update(
        'exam_attendance_sheets',
        {'status': 'saved', 'last_updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
      await batch.commit(noResult: true);
    });
  }

  Future<List<ExamAttendanceSheetSummary>> loadAttendanceSheets(
    String teacherId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT sh.id AS sheet_id, c.course_name, h.name AS hall_name,
             sh.exam_date_time, sh.status, sh.last_updated_at,
             COUNT(r.student_id) AS total_students,
             SUM(CASE WHEN r.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             SUM(CASE WHEN r.status = 'absent' THEN 1 ELSE 0 END) AS absent_count
      FROM exam_attendance_sheets sh
      JOIN courses c ON c.id = sh.course_id
      JOIN exam_halls h ON h.id = sh.hall_id
      LEFT JOIN exam_attendance_records r ON r.sheet_id = sh.id
      WHERE sh.teacher_id = ?
      GROUP BY sh.id
      ORDER BY sh.last_updated_at DESC
      ''',
      [teacherId],
    );
    return rows.map(_attendanceSheetFromRow).toList(growable: false);
  }

  Future<String> shareAttendanceSheet({
    required String teacherId,
    required String sheetId,
    required String sharedWith,
  }) async {
    final db = await database;
    final detail = await loadAttendanceSheetDetail(sheetId);
    final now = DateTime.now();
    final payload = _attendanceShareText(detail.stats);
    final id = 'SHR${DateTime.now().millisecondsSinceEpoch}';
    await db.insert('shared_attendance_sheets', {
      'id': id,
      'sheet_id': sheetId,
      'teacher_id': teacherId,
      'shared_with': sharedWith.trim().isEmpty ? 'Admin' : sharedWith.trim(),
      'shared_at': now.toIso8601String(),
      'status': 'Shared',
      'payload': payload,
    });
    await _insertNotification(
      db,
      teacherId: teacherId,
      category: TeacherNotificationCategory.sharedAttendance,
      title: 'Attendance shared',
      message: detail.stats.courseName,
    );
    return payload;
  }

  Future<AttendanceSharingData> loadAttendanceSharing(String teacherId) async {
    final db = await database;
    final sharedRows = await db.rawQuery(
      '''
      SELECT s.id, c.course_name, h.name AS hall_name, sh.exam_date_time,
             s.shared_with, s.shared_at, s.status
      FROM shared_attendance_sheets s
      JOIN exam_attendance_sheets sh ON sh.id = s.sheet_id
      JOIN courses c ON c.id = sh.course_id
      JOIN exam_halls h ON h.id = sh.hall_id
      WHERE s.teacher_id = ?
      ORDER BY s.shared_at DESC
      ''',
      [teacherId],
    );
    final acceptedRows = await db.query(
      'accepted_attendance_sheets',
      where: 'teacher_id = ?',
      whereArgs: [teacherId],
      orderBy: 'accepted_at DESC',
    );
    return AttendanceSharingData(
      sharedSheets: sharedRows.map(_sharedSheetFromRow).toList(growable: false),
      acceptedSheets: acceptedRows
          .map(_acceptedSheetFromRow)
          .toList(growable: false),
    );
  }

  Future<void> _createTables(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teachers(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        email TEXT NOT NULL UNIQUE,
        password TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS courses(
        id TEXT PRIMARY KEY,
        teacher_id TEXT NOT NULL,
        course_name TEXT NOT NULL,
        course_code TEXT,
        credits INTEGER,
        semester TEXT,
        section TEXT,
        enrolled_students INTEGER NOT NULL DEFAULT 0,
        program TEXT,
        session TEXT,
        instructor TEXT,
        FOREIGN KEY(teacher_id) REFERENCES teachers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS students(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        roll_no TEXT NOT NULL UNIQUE,
        program TEXT,
        session TEXT,
        semester TEXT,
        section TEXT,
        email TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS course_students(
        course_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        PRIMARY KEY(course_id, student_id),
        FOREIGN KEY(course_id) REFERENCES courses(id),
        FOREIGN KEY(student_id) REFERENCES students(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessments(
        id TEXT PRIMARY KEY,
        course_id TEXT NOT NULL,
        title TEXT NOT NULL,
        type TEXT NOT NULL,
        total_marks INTEGER NOT NULL,
        due_date TEXT NOT NULL,
        instructions TEXT,
        created_at TEXT NOT NULL,
        FOREIGN KEY(course_id) REFERENCES courses(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS assessment_submissions(
        id TEXT PRIMARY KEY,
        assessment_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL,
        marks INTEGER,
        submitted_at TEXT,
        FOREIGN KEY(assessment_id) REFERENCES assessments(id),
        FOREIGN KEY(student_id) REFERENCES students(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS notifications(
        id TEXT PRIMARY KEY,
        teacher_id TEXT NOT NULL,
        category TEXT NOT NULL,
        title TEXT NOT NULL,
        message TEXT NOT NULL,
        created_at TEXT NOT NULL,
        is_read INTEGER NOT NULL DEFAULT 0,
        FOREIGN KEY(teacher_id) REFERENCES teachers(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_notifications_teacher ON notifications(teacher_id, is_read)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_halls(
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        course_id TEXT NOT NULL,
        exam_date_time TEXT NOT NULL,
        expected_students INTEGER NOT NULL DEFAULT 0,
        seat_info TEXT,
        qr_payload TEXT,
        FOREIGN KEY(course_id) REFERENCES courses(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_attendance_sheets(
        id TEXT PRIMARY KEY,
        teacher_id TEXT NOT NULL,
        course_id TEXT NOT NULL,
        hall_id TEXT NOT NULL,
        exam_date_time TEXT NOT NULL,
        status TEXT NOT NULL,
        created_at TEXT NOT NULL,
        last_updated_at TEXT NOT NULL,
        FOREIGN KEY(teacher_id) REFERENCES teachers(id),
        FOREIGN KEY(course_id) REFERENCES courses(id),
        FOREIGN KEY(hall_id) REFERENCES exam_halls(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exam_attendance_teacher ON exam_attendance_sheets(teacher_id, last_updated_at)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS exam_attendance_records(
        id TEXT PRIMARY KEY,
        sheet_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        status TEXT NOT NULL,
        marked_at TEXT,
        UNIQUE(sheet_id, student_id),
        FOREIGN KEY(sheet_id) REFERENCES exam_attendance_sheets(id),
        FOREIGN KEY(student_id) REFERENCES students(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exam_attendance_records_sheet ON exam_attendance_records(sheet_id, status)',
    );
    await db.execute('''
      CREATE TABLE IF NOT EXISTS shared_attendance_sheets(
        id TEXT PRIMARY KEY,
        sheet_id TEXT NOT NULL,
        teacher_id TEXT NOT NULL,
        shared_with TEXT NOT NULL,
        shared_at TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        FOREIGN KEY(sheet_id) REFERENCES exam_attendance_sheets(id),
        FOREIGN KEY(teacher_id) REFERENCES teachers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS accepted_attendance_sheets(
        id TEXT PRIMARY KEY,
        teacher_id TEXT NOT NULL,
        course_name TEXT NOT NULL,
        hall_name TEXT NOT NULL,
        exam_date_time TEXT NOT NULL,
        received_from TEXT NOT NULL,
        accepted_at TEXT NOT NULL,
        status TEXT NOT NULL,
        payload TEXT NOT NULL,
        FOREIGN KEY(teacher_id) REFERENCES teachers(id)
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS meta(
        key TEXT PRIMARY KEY,
        value TEXT NOT NULL
      )
    ''');
  }

  Future<void> _seedProvidedDataIfNeeded(Database db) async {
    final versionRows = await db.query(
      'meta',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: ['teacher_dashboard_import_version'],
      limit: 1,
    );
    final storedVersion = versionRows.isEmpty
        ? null
        : versionRows.first['value']?.toString();
    if (storedVersion == _importVersion) {
      return;
    }

    final teacherIdByCourseId = <String, String>{};
    final teacherByName = {
      for (final teacher in registration.registrationTeachers)
        teacher.name: teacher,
    };
    for (final teacher in registration.registrationTeachers) {
      for (final courseId in teacher.courseIds) {
        teacherIdByCourseId[courseId] = teacher.id;
      }
    }

    final courseByExactKey = <String, String>{};
    final courseByLooseKey = <String, String>{};
    final courseIds = <String>{};
    for (final course in registration.registrationCourses) {
      courseIds.add(course.id);
      courseByExactKey[_courseKey(
            code: course.courseCode,
            program: course.program,
            semester: course.semester,
            section: course.section,
            instructor: course.instructor,
          )] =
          course.id;
      courseByLooseKey[_looseCourseKey(
            code: course.courseCode,
            program: course.program,
            semester: course.semester,
            section: course.section,
          )] =
          course.id;
    }

    final studentsById = <String, Map<String, Object?>>{};
    final courseStudentPairs = <String, Map<String, Object?>>{};
    for (final row in localStudentEnrollmentRows) {
      final rollNo = row[_rollNoIndex].trim();
      if (rollNo.isEmpty) {
        continue;
      }
      final studentId = 'STU$rollNo';
      studentsById.putIfAbsent(
        studentId,
        () => {
          'id': studentId,
          'name': row[_studentNameIndex].trim(),
          'roll_no': rollNo,
          'program': row[_programIndex].trim(),
          'session': row[_sessionIndex].trim(),
          'semester': row[_semesterIndex].trim(),
          'section': row[_sectionIndex].trim(),
          'email': '',
        },
      );

      final exactKey = _courseKey(
        code: row[_courseCodeIndex],
        program: row[_programIndex],
        semester: row[_semesterIndex],
        section: row[_sectionIndex],
        instructor: row[_instructorIndex],
      );
      final looseKey = _looseCourseKey(
        code: row[_courseCodeIndex],
        program: row[_programIndex],
        semester: row[_semesterIndex],
        section: row[_sectionIndex],
      );
      final courseId = courseByExactKey[exactKey] ?? courseByLooseKey[looseKey];
      if (courseId == null) {
        continue;
      }
      courseStudentPairs['$courseId|$studentId'] = {
        'course_id': courseId,
        'student_id': studentId,
      };
    }

    await db.transaction((txn) async {
      await txn.delete('assessment_submissions');
      await txn.delete('assessments');
      await txn.delete('course_students');
      await txn.delete('students');
      await txn.delete('courses');
      await txn.delete('teachers');

      final batch = txn.batch();
      for (final teacher in registration.registrationTeachers) {
        batch.insert('teachers', {
          'id': teacher.id,
          'name': teacher.name,
          'email': teacher.email,
          'password': teacher.password,
        });
      }

      for (final course in registration.registrationCourses) {
        batch.insert('courses', {
          'id': course.id,
          'teacher_id':
              teacherIdByCourseId[course.id] ??
              teacherByName[course.instructor]?.id ??
              '',
          'course_name': course.courseName,
          'course_code': course.courseCode,
          'credits': course.credits,
          'semester': course.semester,
          'section': course.section,
          'enrolled_students': course.enrolledStudents,
          'program': course.program,
          'session': course.session,
          'instructor': course.instructor,
        });
      }

      for (final student in studentsById.values) {
        batch.insert(
          'students',
          student,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      for (final pair in courseStudentPairs.values) {
        batch.insert(
          'course_students',
          pair,
          conflictAlgorithm: ConflictAlgorithm.ignore,
        );
      }

      for (final assessment in mock.mockAssessments) {
        if (!courseIds.contains(assessment.courseId)) {
          continue;
        }
        batch.insert('assessments', {
          'id': assessment.id,
          'course_id': assessment.courseId,
          'title': assessment.title,
          'type': _kindKeyFromLegacyType(assessment.type),
          'total_marks': assessment.totalMarks,
          'due_date': assessment.endTime.toIso8601String(),
          'instructions': assessment.instructions,
          'created_at': assessment.startTime.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      for (final submission in mock.mockSubmissions) {
        batch.insert('assessment_submissions', {
          'id': submission.id,
          'assessment_id': submission.assessmentId,
          'student_id': submission.studentId,
          'status': submission.status.name == 'submitted'
              ? 'submitted'
              : 'not_submitted',
          'marks': submission.marks,
          'submitted_at': submission.submittedAt?.toIso8601String(),
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }

      batch.insert('meta', {
        'key': 'teacher_dashboard_import_version',
        'value': _importVersion,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await batch.commit(noResult: true);
    });
  }

  Future<List<TeacherCourseSummary>> _loadCourseSummaries(
    Database db, {
    required String teacherId,
  }) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.*,
             COUNT(DISTINCT cs.student_id) AS related_students,
             COUNT(DISTINCT a.id) AS assessment_count
      FROM courses c
      LEFT JOIN course_students cs ON cs.course_id = c.id
      LEFT JOIN assessments a ON a.course_id = c.id
      WHERE c.teacher_id = ?
      GROUP BY c.id
      ORDER BY c.course_name, c.section
      ''',
      [teacherId],
    );
    return rows.map(_courseSummaryFromRow).toList(growable: false);
  }

  Future<TeacherCourseSummary> _loadCourseSummary(
    Database db,
    String courseId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT c.*,
             COUNT(DISTINCT cs.student_id) AS related_students,
             COUNT(DISTINCT a.id) AS assessment_count
      FROM courses c
      LEFT JOIN course_students cs ON cs.course_id = c.id
      LEFT JOIN assessments a ON a.course_id = c.id
      WHERE c.id = ?
      GROUP BY c.id
      ''',
      [courseId],
    );
    if (rows.isEmpty) {
      throw StateError('Course not found.');
    }
    return _courseSummaryFromRow(rows.first);
  }

  Future<List<CourseAssessmentSummary>> _loadAssessments(
    Database db,
    String courseId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT a.*,
             SUM(CASE WHEN sub.status = 'submitted' THEN 1 ELSE 0 END) AS submitted_count,
             SUM(CASE WHEN sub.status = 'submitted' THEN 0 ELSE 1 END) AS not_submitted_count
      FROM assessments a
      LEFT JOIN course_students cs ON cs.course_id = a.course_id
      LEFT JOIN assessment_submissions sub
        ON sub.assessment_id = a.id AND sub.student_id = cs.student_id
      WHERE a.course_id = ?
      GROUP BY a.id
      ORDER BY a.due_date DESC
      ''',
      [courseId],
    );
    return rows.map(_assessmentFromRow).toList(growable: false);
  }

  Future<CourseAssessmentSummary> _loadAssessment(
    Database db,
    String assessmentId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT a.*,
             SUM(CASE WHEN sub.status = 'submitted' THEN 1 ELSE 0 END) AS submitted_count,
             SUM(CASE WHEN sub.status = 'submitted' THEN 0 ELSE 1 END) AS not_submitted_count
      FROM assessments a
      LEFT JOIN course_students cs ON cs.course_id = a.course_id
      LEFT JOIN assessment_submissions sub
        ON sub.assessment_id = a.id AND sub.student_id = cs.student_id
      WHERE a.id = ?
      GROUP BY a.id
      ''',
      [assessmentId],
    );
    if (rows.isEmpty) {
      throw StateError('Assessment not found.');
    }
    return _assessmentFromRow(rows.first);
  }

  TeacherCourseSummary _courseSummaryFromRow(Map<String, Object?> row) {
    final relatedStudents = (row['related_students'] as int?) ?? 0;
    final enrolledStudents = (row['enrolled_students'] as int?) ?? 0;
    return TeacherCourseSummary(
      id: row['id'].toString(),
      teacherId: row['teacher_id'].toString(),
      courseName: row['course_name'].toString(),
      courseCode: row['course_code']?.toString() ?? '',
      totalStudents: relatedStudents == 0 ? enrolledStudents : relatedStudents,
      totalAssessments: (row['assessment_count'] as int?) ?? 0,
      program: row['program']?.toString() ?? '',
      semester: row['semester']?.toString() ?? '',
      section: row['section']?.toString() ?? '',
    );
  }

  CourseAssessmentSummary _assessmentFromRow(Map<String, Object?> row) {
    return CourseAssessmentSummary(
      id: row['id'].toString(),
      courseId: row['course_id'].toString(),
      title: row['title'].toString(),
      type: TeacherAssessmentKind.fromKey(row['type'].toString()),
      totalMarks: _intValue(row['total_marks']),
      dueDate:
          DateTime.tryParse(row['due_date']?.toString() ?? '') ??
          DateTime.now(),
      instructions: row['instructions']?.toString() ?? '',
      submittedCount: _intValue(row['submitted_count']),
      notSubmittedCount: _intValue(row['not_submitted_count']),
    );
  }

  TeacherNotification _notificationFromRow(Map<String, Object?> row) {
    return TeacherNotification(
      id: row['id'].toString(),
      teacherId: row['teacher_id'].toString(),
      category: TeacherNotificationCategory.fromKey(row['category'].toString()),
      title: row['title'].toString(),
      message: row['message'].toString(),
      createdAt:
          DateTime.tryParse(row['created_at']?.toString() ?? '') ??
          DateTime.now(),
      isRead: _intValue(row['is_read']) == 1,
    );
  }

  ExamAttendanceSheetSummary _attendanceSheetFromRow(Map<String, Object?> row) {
    return ExamAttendanceSheetSummary(
      sheetId: row['sheet_id'].toString(),
      courseName: row['course_name'].toString(),
      hallName: row['hall_name'].toString(),
      examDateTime:
          DateTime.tryParse(row['exam_date_time']?.toString() ?? '') ??
          DateTime.now(),
      totalStudents: _intValue(row['total_students']),
      presentCount: _intValue(row['present_count']),
      absentCount: _intValue(row['absent_count']),
      lastUpdatedAt:
          DateTime.tryParse(row['last_updated_at']?.toString() ?? '') ??
          DateTime.now(),
      status: row['status'].toString(),
    );
  }

  SharedAttendanceSheetSummary _sharedSheetFromRow(Map<String, Object?> row) {
    return SharedAttendanceSheetSummary(
      id: row['id'].toString(),
      courseName: row['course_name'].toString(),
      hallName: row['hall_name'].toString(),
      examDateTime:
          DateTime.tryParse(row['exam_date_time']?.toString() ?? '') ??
          DateTime.now(),
      sharedWith: row['shared_with'].toString(),
      sharedAt:
          DateTime.tryParse(row['shared_at']?.toString() ?? '') ??
          DateTime.now(),
      status: row['status'].toString(),
    );
  }

  AcceptedAttendanceSheetSummary _acceptedSheetFromRow(
    Map<String, Object?> row,
  ) {
    return AcceptedAttendanceSheetSummary(
      id: row['id'].toString(),
      courseName: row['course_name'].toString(),
      hallName: row['hall_name'].toString(),
      examDateTime:
          DateTime.tryParse(row['exam_date_time']?.toString() ?? '') ??
          DateTime.now(),
      receivedFrom: row['received_from'].toString(),
      acceptedAt:
          DateTime.tryParse(row['accepted_at']?.toString() ?? '') ??
          DateTime.now(),
      status: row['status'].toString(),
    );
  }

  Future<int> _countWhere(
    Database db,
    String table,
    String where,
    List<Object?> whereArgs,
  ) async {
    final rows = await db.rawQuery(
      'SELECT COUNT(*) AS count FROM $table WHERE $where',
      whereArgs,
    );
    return _intValue(rows.first['count']);
  }

  Future<void> _insertNotification(
    Database db, {
    required String teacherId,
    required TeacherNotificationCategory category,
    required String title,
    required String message,
  }) async {
    await db.insert('notifications', {
      'id': 'NTF${DateTime.now().microsecondsSinceEpoch}',
      'teacher_id': teacherId,
      'category': category.key,
      'title': title,
      'message': message,
      'created_at': DateTime.now().toIso8601String(),
      'is_read': 0,
    });
  }

  Future<void> _ensureAttendanceRecords(
    DatabaseExecutor executor, {
    required String sheetId,
    required String courseId,
  }) async {
    final existing =
        Sqflite.firstIntValue(
          await executor.rawQuery(
            'SELECT COUNT(*) FROM exam_attendance_records WHERE sheet_id = ?',
            [sheetId],
          ),
        ) ??
        0;
    if (existing > 0) {
      return;
    }
    final students = await executor.query(
      'course_students',
      columns: ['student_id'],
      where: 'course_id = ?',
      whereArgs: [courseId],
    );
    final now = DateTime.now().toIso8601String();
    final batch = executor.batch();
    for (final student in students) {
      final studentId = student['student_id'].toString();
      batch.insert('exam_attendance_records', {
        'id': 'EAR${_stableHash('$sheetId|$studentId')}',
        'sheet_id': sheetId,
        'student_id': studentId,
        'status': 'absent',
        'marked_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<ExamHallStats> _loadExamHallStats(Database db, String sheetId) async {
    final rows = await db.rawQuery(
      '''
      SELECT sh.id AS sheet_id, h.id AS hall_id, h.name AS hall_name,
             h.expected_students, h.seat_info, c.id AS course_id,
             c.course_name, sh.exam_date_time, sh.status,
             COUNT(r.student_id) AS record_count,
             SUM(CASE WHEN r.status = 'present' THEN 1 ELSE 0 END) AS present_count,
             SUM(CASE WHEN r.status = 'absent' THEN 1 ELSE 0 END) AS absent_count
      FROM exam_attendance_sheets sh
      JOIN exam_halls h ON h.id = sh.hall_id
      JOIN courses c ON c.id = sh.course_id
      LEFT JOIN exam_attendance_records r ON r.sheet_id = sh.id
      WHERE sh.id = ?
      GROUP BY sh.id
      ''',
      [sheetId],
    );
    if (rows.isEmpty) {
      throw StateError('Hall data not found.');
    }
    final row = rows.first;
    final expected = _intValue(row['expected_students']);
    final recordCount = _intValue(row['record_count']);
    final totalStudents = recordCount == 0 ? expected : recordCount;
    return ExamHallStats(
      sheetId: row['sheet_id'].toString(),
      hallId: row['hall_id'].toString(),
      hallName: row['hall_name'].toString(),
      courseId: row['course_id'].toString(),
      courseName: row['course_name'].toString(),
      examDateTime:
          DateTime.tryParse(row['exam_date_time']?.toString() ?? '') ??
          DateTime.now(),
      totalStudents: totalStudents,
      presentStudents: _intValue(row['present_count']),
      absentStudents: recordCount == 0
          ? totalStudents
          : _intValue(row['absent_count']),
      status: row['status'].toString(),
      seatInfo: row['seat_info']?.toString() ?? '',
    );
  }

  Future<List<ExamAttendanceStudent>> _loadAttendanceStudents(
    Database db,
    String sheetId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.roll_no, r.status
      FROM exam_attendance_records r
      JOIN students s ON s.id = r.student_id
      WHERE r.sheet_id = ?
      ORDER BY s.roll_no, s.name
      ''',
      [sheetId],
    );
    return rows
        .map(
          (row) => ExamAttendanceStudent(
            studentId: row['id'].toString(),
            studentName: row['name'].toString(),
            rollNo: row['roll_no'].toString(),
            status: row['status'].toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<_ParsedHallQr> _parseHallQr(
    Database db,
    String teacherId,
    String rawPayload,
  ) async {
    final raw = rawPayload.trim();
    if (raw.isEmpty) {
      return _ParsedHallQr.invalid(raw);
    }

    final decoded = _tryDecodeJson(raw);
    if (decoded is Map) {
      final courseId = await _resolveCourseId(
        db,
        teacherId: teacherId,
        courseId: _jsonString(decoded, 'courseId', 'course_id'),
        courseCode: _jsonString(decoded, 'courseCode', 'course_code'),
        courseName: _jsonString(decoded, 'courseName', 'course_name'),
      );
      return _ParsedHallQr(
        rawPayload: raw,
        hallId: _jsonString(decoded, 'hallId', 'exam_hall_id'),
        hallName: _jsonString(decoded, 'hallName', 'exam_hall_name'),
        courseId: courseId,
        courseName: _jsonString(decoded, 'courseName', 'course_name'),
        examDateTime:
            DateTime.tryParse(
              _jsonString(decoded, 'examDateTime', 'exam_date_time'),
            ) ??
            DateTime.now(),
        expectedStudents:
            int.tryParse(
              _jsonString(decoded, 'totalExpectedStudents', 'total_students'),
            ) ??
            0,
        seatInfo: _jsonString(decoded, 'seatInfo', 'seat_info'),
      );
    }

    final parts = raw.split('|').map((part) => part.trim()).toList();
    if (parts.length < 10 ||
        parts[0].toUpperCase() != 'CSEXAM' ||
        parts[1].toUpperCase() != 'QPATT') {
      return _ParsedHallQr.invalid(raw);
    }
    final token = parts[3].toUpperCase();
    final seedRows = await _loadQrSeedRows();
    final seed = seedRows.cast<Map<String, Object?>>().firstWhere(
      (row) =>
          row['token']?.toString().toUpperCase() == token ||
          row['roll_no']?.toString().toUpperCase() == parts[7].toUpperCase(),
      orElse: () => const <String, Object?>{},
    );
    final examDate = seed['exam_date']?.toString() ?? parts[4];
    final shift = seed['shift']?.toString() ?? parts[5];
    final hallCode = seed['hall_code']?.toString() ?? parts[6];
    final courseName = seed['subject']?.toString() ?? '';
    final courseCode = seed['course_code']?.toString() ?? '';
    final matchingSeeds = seedRows
        .where((row) {
          return (row['exam_date']?.toString() ?? '') == examDate &&
              (row['shift']?.toString() ?? '') == shift &&
              (row['hall_code']?.toString() ?? '') == hallCode &&
              (courseName.isEmpty ||
                  (row['subject']?.toString() ?? '') == courseName);
        })
        .toList(growable: false);
    final courseId = await _resolveCourseId(
      db,
      teacherId: teacherId,
      courseId: '',
      courseCode: courseCode,
      courseName: courseName,
    );
    return _ParsedHallQr(
      rawPayload: raw,
      hallId: 'HALL_${_normalize(hallCode)}',
      hallName: hallCode.isEmpty ? 'Exam Hall' : hallCode,
      courseId: courseId,
      courseName: courseName,
      examDateTime: _parseExamDate(examDate, shift),
      expectedStudents: matchingSeeds.isEmpty ? 0 : matchingSeeds.length,
      seatInfo: seed['seat_label']?.toString() ?? '',
    );
  }

  Future<String> _resolveCourseId(
    Database db, {
    required String teacherId,
    required String courseId,
    required String courseCode,
    required String courseName,
  }) async {
    if (courseId.trim().isNotEmpty) {
      final rows = await db.query(
        'courses',
        columns: ['id'],
        where: 'id = ? AND teacher_id = ?',
        whereArgs: [courseId.trim(), teacherId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['id'].toString();
      }
    }
    if (courseCode.trim().isNotEmpty) {
      final rows = await db.query(
        'courses',
        columns: ['id'],
        where: 'UPPER(course_code) = ? AND teacher_id = ?',
        whereArgs: [courseCode.trim().toUpperCase(), teacherId],
        limit: 1,
      );
      if (rows.isNotEmpty) {
        return rows.first['id'].toString();
      }
    }
    if (courseName.trim().isNotEmpty) {
      final normalized = _normalize(courseName);
      final rows = await db.query(
        'courses',
        columns: ['id', 'course_name'],
        where: 'teacher_id = ?',
        whereArgs: [teacherId],
      );
      for (final row in rows) {
        if (_normalize(row['course_name'].toString()) == normalized) {
          return row['id'].toString();
        }
      }
    }
    return '';
  }

  Future<List<Map<String, Object?>>> _loadQrSeedRows() async {
    try {
      final rawJson = await rootBundle.loadString('assets/qr_seed.json');
      final decoded = jsonDecode(rawJson);
      if (decoded is! Map || decoded['tokens'] is! List) {
        return const [];
      }
      return (decoded['tokens'] as List)
          .whereType<Map>()
          .map((row) => row.cast<String, Object?>())
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  String _attendanceShareText(ExamHallStats stats) {
    return [
      'Course: ${stats.courseName}',
      'Exam hall: ${stats.hallName}',
      'Date/time: ${stats.examDateTime.toIso8601String()}',
      'Total students: ${stats.totalStudents}',
      'Present students: ${stats.presentStudents}',
      'Absent students: ${stats.absentStudents}',
      'Attendance: ${stats.attendancePercentage.toStringAsFixed(1)}%',
    ].join('\n');
  }

  Object? _tryDecodeJson(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  String _jsonString(Map<dynamic, dynamic> map, String key, String fallback) {
    return (map[key] ?? map[fallback] ?? '').toString().trim();
  }

  DateTime _parseExamDate(String date, String shift) {
    final iso = DateTime.tryParse(date);
    if (iso != null) {
      return iso;
    }
    final parts = date.split('-');
    if (parts.length >= 3) {
      final day = int.tryParse(parts[0]) ?? DateTime.now().day;
      final month = _monthNumber(parts[1]);
      var year = int.tryParse(parts[2]) ?? DateTime.now().year;
      if (year < 100) {
        year += 2000;
      }
      final hour = shift.toLowerCase().contains('2') ? 14 : 9;
      return DateTime(year, month, day, hour);
    }
    return DateTime.now();
  }

  int _monthNumber(String value) {
    final key = value.trim().toLowerCase();
    if (key.length < 3) {
      return 1;
    }
    const months = {
      'jan': 1,
      'feb': 2,
      'mar': 3,
      'apr': 4,
      'may': 5,
      'jun': 6,
      'jul': 7,
      'aug': 8,
      'sep': 9,
      'oct': 10,
      'nov': 11,
      'dec': 12,
    };
    return months[key.substring(0, 3)] ?? 1;
  }

  String _stableHash(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  int _intValue(Object? value) {
    if (value is int) {
      return value;
    }
    if (value is num) {
      return value.toInt();
    }
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  String _courseKey({
    required String code,
    required String program,
    required String semester,
    required String section,
    required String instructor,
  }) {
    return [
      _normalize(code),
      program.trim().toUpperCase(),
      semester.trim(),
      section.trim().toUpperCase(),
      _normalize(instructor),
    ].join('|');
  }

  String _looseCourseKey({
    required String code,
    required String program,
    required String semester,
    required String section,
  }) {
    return [
      _normalize(code),
      program.trim().toUpperCase(),
      semester.trim(),
      section.trim().toUpperCase(),
    ].join('|');
  }

  String _normalize(String value) {
    return value.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]+'), '');
  }

  String _kindKeyFromLegacyType(AssessmentType type) {
    return switch (type) {
      AssessmentType.quiz => TeacherAssessmentKind.quiz.key,
      AssessmentType.assignment => TeacherAssessmentKind.assignment.key,
      AssessmentType.examPaper => TeacherAssessmentKind.others.key,
    };
  }

  static const int _rollNoIndex = 0;
  static const int _studentNameIndex = 1;
  static const int _programIndex = 2;
  static const int _semesterIndex = 3;
  static const int _sectionIndex = 4;
  static const int _sessionIndex = 6;
  static const int _courseCodeIndex = 7;
  static const int _instructorIndex = 9;
}

class _ParsedHallQr {
  const _ParsedHallQr({
    required this.rawPayload,
    required this.hallId,
    required this.hallName,
    required this.courseId,
    required this.courseName,
    required this.examDateTime,
    required this.expectedStudents,
    required this.seatInfo,
    this.valid = true,
  });

  factory _ParsedHallQr.invalid(String rawPayload) {
    return _ParsedHallQr(
      rawPayload: rawPayload,
      hallId: '',
      hallName: '',
      courseId: '',
      courseName: '',
      examDateTime: DateTime.now(),
      expectedStudents: 0,
      seatInfo: '',
      valid: false,
    );
  }

  final String rawPayload;
  final String hallId;
  final String hallName;
  final String courseId;
  final String courseName;
  final DateTime examDateTime;
  final int expectedStudents;
  final String seatInfo;
  final bool valid;

  bool get isValid => valid;
}
