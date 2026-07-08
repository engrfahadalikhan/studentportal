import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../assessment/assessment_mock_data.dart' as mock;
import '../assessment/assessment_models.dart';
import '../assessment/registration_course_data.dart' as registration;
import '../assessment/teacher_dashboard_models.dart';
import '../data/local_student_enrollments.dart';
import 'admin_data_bundle.dart';
import 'cloud_sync_service.dart';
import 'login_store.dart';

class TeacherDashboardDatabase {
  TeacherDashboardDatabase._();

  static final TeacherDashboardDatabase instance = TeacherDashboardDatabase._();
  static const String _importVersion = '2026-05-23-teacher-dashboard-v3';

  Database? _db;

  /// Called after any exam-attendance write (mark / add / remove / accept), so
  /// the cloud sync can push the change. Set by CloudSyncService.
  void Function()? onExamDataChanged;

  /// Called with (table, id) pairs when rows are DELETED locally, so the cloud
  /// sync can delete them everywhere (tombstones). Set by CloudSyncService.
  void Function(List<(String, String)> items)? onExamDataRemoved;

  /// The logged-in teacher/invigilator's name, stamped on records they scan.
  String get _collectorName => LoginStore.instance.currentUserName.trim();

  /// Deletes one row by primary key — used when a cloud tombstone arrives.
  /// [table] is whitelisted to the synced exam/module tables.
  Future<void> deleteRowById(String table, String id) async {
    const allowed = {
      'exam_attendance_records',
      'exam_ufm_cases',
      'exam_attendance_sheets',
      'teacher_assignments',
      'student_submissions',
    };
    if (!allowed.contains(table) || id.isEmpty) return;
    final db = await database;
    await db.delete(table, where: 'id = ?', whereArgs: [id]);
  }

  /// Merges cloud rows into [table] keep-newest by [tsCol] (insert-only when
  /// [tsCol] is null). Used by the cloud pull so an older cloud copy never
  /// overwrites a newer local edit.
  Future<void> mergeCloudRows(
    String table,
    List<Map<String, Object?>> rows, {
    String? tsCol,
  }) async {
    final db = await database;
    await TableSync.merge(
      db,
      table,
      rows,
      tsOf: tsCol == null ? null : (r) => TableSync.ts(r, tsCol),
    );
  }

  // Cached seating-plan seed, keyed by QR token and by roll number, so the
  // live hall-scan screen can resolve a scanned seat QR to the student's real
  // name + seat without re-reading the asset on every scan.
  Map<String, SeedStudentInfo>? _seedByToken;
  Map<String, SeedStudentInfo>? _seedByRoll;

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
    // Show ALL attendance held on this device (own + accepted + imported/shared
    // from the other admin), so a consolidated set is fully visible.
    final attendanceSheets = await _countWhere(
      db,
      'exam_attendance_sheets',
      '1 = 1',
      const [],
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
        '1 = 1',
        const [],
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
      // Surface what was actually scanned so an unexpected QR format can be
      // diagnosed instead of a blank "invalid" message.
      final snippet = rawPayload.trim();
      final shown = snippet.length > 120
          ? '${snippet.substring(0, 120)}…'
          : snippet;
      throw FormatException(
        snippet.isEmpty
            ? 'No QR detected. Hold the HALL QR steady inside the white box.'
            : 'This QR is not a hall/seating QR.\nScanned: $shown',
      );
    }

    // No portal course matched. If the seating plan gave us students, create
    // a lightweight course record from the seed info (teacher_id left empty
    // so it does NOT pollute anyone's registered-courses list). Only fail
    // when we have neither a course nor seating-plan students.
    var courseId = parsed.courseId;
    if (courseId.isEmpty) {
      if (parsed.seatStudents.isEmpty &&
          parsed.expectedStudents <= 0 &&
          parsed.classGroups.isEmpty) {
        throw StateError(
          'Hall data not found. This QR is not in the seating-plan data.',
        );
      }
      courseId =
          'CRSX${_stableHash('${parsed.courseName}|${parsed.program}')}';
      await db.insert('courses', {
        'id': courseId,
        'teacher_id': '',
        'course_name': parsed.courseName,
        'course_code': '',
        'credits': 0,
        'semester': '',
        'section': '',
        'enrolled_students': parsed.seatStudents.isEmpty
            ? parsed.expectedStudents
            : parsed.seatStudents.length,
        'program': parsed.program,
        'session': '',
        'instructor': parsed.faculty,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }

    final now = DateTime.now();
    final hallId = parsed.hallId.isEmpty
        ? 'HALL${_stableHash(parsed.rawPayload)}'
        : 'HALL${_stableHash('${parsed.hallId}|$courseId|${parsed.examDateTime.toIso8601String()}')}';
    final sheetId =
        'EAS${_stableHash('$teacherId|$hallId|$courseId|${parsed.examDateTime.toIso8601String()}')}';

    await db.transaction((txn) async {
      await txn.insert('exam_halls', {
        'id': hallId,
        'name': parsed.hallName.isEmpty ? hallId : parsed.hallName,
        'course_id': courseId,
        'exam_date_time': parsed.examDateTime.toIso8601String(),
        'expected_students': parsed.expectedStudents,
        'seat_info': parsed.seatInfo,
        'qr_payload': parsed.rawPayload,
        'class_groups': jsonEncode([
          for (final group in parsed.classGroups)
            {
              'program': group.program,
              'subject': group.subject,
              'faculty': group.faculty,
              'count': group.count,
            },
        ]),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.insert('exam_attendance_sheets', {
        'id': sheetId,
        'teacher_id': teacherId,
        'course_id': courseId,
        'hall_id': hallId,
        'exam_date_time': parsed.examDateTime.toIso8601String(),
        'status': 'fetched',
        'created_at': now.toIso8601String(),
        'last_updated_at': now.toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.ignore);

      if (parsed.seatStudents.isNotEmpty) {
        // Seating-plan flow: records come from the hall's actual seats.
        await _ensureSeatAttendanceRecords(
          txn,
          sheetId: sheetId,
          seatStudents: parsed.seatStudents,
        );
      } else if (parsed.rosterFromCourse) {
        // Legacy JSON flow: roster from course enrollment.
        await _ensureAttendanceRecords(
          txn,
          sheetId: sheetId,
          courseId: courseId,
        );
      }
      // else: dynamic roster — records are added live as seat QRs are
      // scanned (the hall hosts only a slice of each class).
    });

    return loadExamHallStats(sheetId);
  }

  /// Seeds one attendance record per seating-plan seat (and makes sure the
  /// student rows exist), keeping the real Col/Chair for the live skeleton.
  Future<void> _ensureSeatAttendanceRecords(
    DatabaseExecutor executor, {
    required String sheetId,
    required List<_SeatStudent> seatStudents,
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
    final now = DateTime.now().toIso8601String();
    final batch = executor.batch();
    for (final seat in seatStudents) {
      final studentId = 'STU${seat.rollNo}';
      batch.insert('students', {
        'id': studentId,
        'name': seat.name.isEmpty ? seat.rollNo : seat.name,
        'roll_no': seat.rollNo,
        'program': '',
        'session': '',
        'semester': '',
        'section': '',
        'email': '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      batch.insert('exam_attendance_records', {
        'id': 'EAR${_stableHash('$sheetId|$studentId')}',
        'sheet_id': sheetId,
        'student_id': studentId,
        'status': 'absent',
        'marked_at': now,
        'seat_label': seat.seatLabel,
        'col_no': seat.colNo,
        'chair_no': seat.chairNo,
        'class_group': seat.classGroup,
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
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
      GROUP BY sh.id
      ORDER BY sh.last_updated_at DESC
      ''',
    );
    return rows.map(_attendanceSheetFromRow).toList(growable: false);
  }

  /// Every attendance record this teacher holds (own scans + accepted/merged),
  /// flattened for the end-of-exam summary (slot / program / hall drill-down).
  Future<List<AttendanceSummaryRow>> loadAttendanceSummaryRows(
    String teacherId,
  ) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT sh.exam_date_time AS dt, h.name AS hall,
             r.class_group AS program, r.status AS status, r.flag AS flag,
             r.collected_by AS collected_by,
             s.roll_no AS roll, s.name AS name
      FROM exam_attendance_sheets sh
      JOIN exam_halls h ON h.id = sh.hall_id
      JOIN exam_attendance_records r ON r.sheet_id = sh.id
      JOIN students s ON s.id = r.student_id
      ''',
    );
    return rows
        .map(
          (row) => AttendanceSummaryRow(
            dateTime:
                DateTime.tryParse(row['dt']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            hall: (row['hall'] ?? '').toString(),
            program: (row['program'] ?? '').toString().trim().isEmpty
                ? 'Unspecified'
                : (row['program']).toString().trim(),
            status: (row['status'] ?? '').toString(),
            flag: (row['flag'] ?? '').toString(),
            rollNo: (row['roll'] ?? '').toString(),
            studentName: (row['name'] ?? '').toString(),
            collectedBy: (row['collected_by'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  /// Every UFM case the teacher holds (own + accepted), with hall / program /
  /// date context — feeds the teacher-wide UFM PDF.
  Future<List<UfmSummaryRow>> loadUfmSummaryRows(String teacherId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT sh.exam_date_time AS dt, h.name AS hall,
             s.roll_no AS roll, s.name AS name,
             u.allegation AS allegation, u.details AS details,
             u.collected_by AS collected_by,
             (SELECT r.class_group FROM exam_attendance_records r
                WHERE r.sheet_id = u.sheet_id AND r.student_id = u.student_id
                LIMIT 1) AS program
      FROM exam_ufm_cases u
      JOIN exam_attendance_sheets sh ON sh.id = u.sheet_id
      JOIN exam_halls h ON h.id = sh.hall_id
      JOIN students s ON s.id = u.student_id
      ORDER BY sh.exam_date_time
      ''',
    );
    return rows
        .map(
          (row) => UfmSummaryRow(
            dateTime:
                DateTime.tryParse(row['dt']?.toString() ?? '') ??
                DateTime.fromMillisecondsSinceEpoch(0),
            hall: (row['hall'] ?? '').toString(),
            program: (row['program'] ?? '').toString().trim().isEmpty
                ? 'Unspecified'
                : (row['program']).toString().trim(),
            rollNo: (row['roll'] ?? '').toString(),
            studentName: (row['name'] ?? '').toString(),
            allegation: (row['allegation'] ?? '').toString(),
            details: (row['details'] ?? '').toString(),
            collectedBy: (row['collected_by'] ?? '').toString(),
          ),
        )
        .toList(growable: false);
  }

  Future<String> shareAttendanceSheet({
    required String teacherId,
    required String sheetId,
    required String sharedWith,
  }) async {
    final db = await database;
    final detail = await loadAttendanceSheetDetail(sheetId);
    final ufmCases = await loadUfmCases(sheetId);
    final now = DateTime.now();
    final payload = _buildAttendanceShare(detail, ufmCases).text;
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

  /// Marks a single student present/absent right away (used by the live
  /// hall-scan screen so every scan is persisted immediately). Optionally
  /// records the seat when the scanned QR carries one.
  Future<void> markAttendanceStatus({
    required String sheetId,
    required String studentId,
    required String status,
    String seatLabel = '',
    int colNo = 0,
    int chairNo = 0,
    String classGroup = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      await txn.update(
        'exam_attendance_records',
        {
          'status': status,
          'marked_at': now,
          'collected_by': _collectorName,
          if (seatLabel.isNotEmpty) 'seat_label': seatLabel,
          if (colNo > 0) 'col_no': colNo,
          if (chairNo > 0) 'chair_no': chairNo,
          if (classGroup.isNotEmpty) 'class_group': classGroup,
        },
        where: 'sheet_id = ? AND student_id = ?',
        whereArgs: [sheetId, studentId],
      );
      await txn.update(
        'exam_attendance_sheets',
        {'status': 'saved', 'last_updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
    });
    onExamDataChanged?.call();
  }

  /// Adds a student to a sheet on the fly (dynamic-roster halls): used when a
  /// scanned seat QR belongs to this hall but the sheet has no record yet.
  Future<void> addAttendanceRecord({
    required String sheetId,
    required String rollNo,
    String studentName = '',
    String status = 'present',
    String seatLabel = '',
    int colNo = 0,
    int chairNo = 0,
    String classGroup = '',
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final studentId = 'STU$rollNo';
    await db.transaction((txn) async {
      await txn.insert('students', {
        'id': studentId,
        'name': studentName.isEmpty ? rollNo : studentName,
        'roll_no': rollNo,
        'program': '',
        'session': '',
        'semester': '',
        'section': '',
        'email': '',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
      await txn.insert('exam_attendance_records', {
        'id': 'EAR${_stableHash('$sheetId|$studentId')}',
        'sheet_id': sheetId,
        'student_id': studentId,
        'status': status,
        'marked_at': now,
        'collected_by': _collectorName,
        'seat_label': seatLabel,
        'col_no': colNo,
        'chair_no': chairNo,
        'class_group': classGroup,
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await txn.update(
        'exam_attendance_sheets',
        {'status': 'saved', 'last_updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
    });
    onExamDataChanged?.call();
  }

  /// Deletes one attendance record (used when a QR was scanned by mistake).
  /// Any UFM case for that student in the sheet is removed too. The deleted
  /// row ids are reported so the cloud sync can delete them everywhere.
  Future<void> removeAttendanceRecord({
    required String sheetId,
    required String studentId,
  }) async {
    final db = await database;
    final now = DateTime.now().toIso8601String();
    final removed = <(String, String)>[];
    await db.transaction((txn) async {
      // Capture ids first so the deletion can propagate to other devices.
      final recRows = await txn.query(
        'exam_attendance_records',
        columns: ['id'],
        where: 'sheet_id = ? AND student_id = ?',
        whereArgs: [sheetId, studentId],
      );
      final ufmRows = await txn.query(
        'exam_ufm_cases',
        columns: ['id'],
        where: 'sheet_id = ? AND student_id = ?',
        whereArgs: [sheetId, studentId],
      );
      for (final r in recRows) {
        removed.add(('exam_attendance_records', r['id'].toString()));
      }
      for (final u in ufmRows) {
        removed.add(('exam_ufm_cases', u['id'].toString()));
      }
      await txn.delete(
        'exam_attendance_records',
        where: 'sheet_id = ? AND student_id = ?',
        whereArgs: [sheetId, studentId],
      );
      await txn.delete(
        'exam_ufm_cases',
        where: 'sheet_id = ? AND student_id = ?',
        whereArgs: [sheetId, studentId],
      );
      await txn.update(
        'exam_attendance_sheets',
        {'status': 'saved', 'last_updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
    });
    if (removed.isNotEmpty) onExamDataRemoved?.call(removed);
    onExamDataChanged?.call();
  }

  /// Deletes a whole saved attendance sheet — its records, UFM cases and the
  /// sheet row itself. Used by "Saved Stats" delete (with a warning first).
  /// Deleted ids are reported so the deletion reaches every synced device.
  Future<void> deleteAttendanceSheet(String sheetId) async {
    final db = await database;
    final removed = <(String, String)>[];
    await db.transaction((txn) async {
      final recRows = await txn.query(
        'exam_attendance_records',
        columns: ['id'],
        where: 'sheet_id = ?',
        whereArgs: [sheetId],
      );
      final ufmRows = await txn.query(
        'exam_ufm_cases',
        columns: ['id'],
        where: 'sheet_id = ?',
        whereArgs: [sheetId],
      );
      for (final r in recRows) {
        removed.add(('exam_attendance_records', r['id'].toString()));
      }
      for (final u in ufmRows) {
        removed.add(('exam_ufm_cases', u['id'].toString()));
      }
      removed.add(('exam_attendance_sheets', sheetId));
      await txn.delete(
        'exam_attendance_records',
        where: 'sheet_id = ?',
        whereArgs: [sheetId],
      );
      await txn.delete(
        'exam_ufm_cases',
        where: 'sheet_id = ?',
        whereArgs: [sheetId],
      );
      await txn.delete(
        'exam_attendance_sheets',
        where: 'id = ?',
        whereArgs: [sheetId],
      );
    });
    onExamDataRemoved?.call(removed);
  }

  Future<List<UfmCase>> loadUfmCases(String sheetId) async {
    final db = await database;
    final rows = await db.rawQuery(
      '''
      SELECT u.id, u.sheet_id, u.student_id, u.allegation, u.details,
             u.created_at, s.name AS student_name, s.roll_no
      FROM exam_ufm_cases u
      JOIN students s ON s.id = u.student_id
      WHERE u.sheet_id = ?
      ORDER BY u.created_at DESC
      ''',
      [sheetId],
    );
    return rows
        .map(
          (row) => UfmCase(
            id: row['id'].toString(),
            sheetId: row['sheet_id'].toString(),
            studentId: row['student_id'].toString(),
            studentName: row['student_name'].toString(),
            rollNo: row['roll_no'].toString(),
            allegation: row['allegation'].toString(),
            details: row['details']?.toString() ?? '',
            createdAt:
                DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
          ),
        )
        .toList(growable: false);
  }

  /// Records one UFM case (entered one by one from the live screen).
  Future<void> addUfmCase({
    required String sheetId,
    required String studentId,
    required String allegation,
    String details = '',
  }) async {
    final db = await database;
    await db.insert('exam_ufm_cases', {
      'id': 'UFM${DateTime.now().microsecondsSinceEpoch}',
      'sheet_id': sheetId,
      'student_id': studentId,
      'allegation': allegation,
      'details': details.trim(),
      'created_at': DateTime.now().toIso8601String(),
      // Which invigilator recorded this UFM case.
      'collected_by': _collectorName,
    });
    onExamDataChanged?.call();
  }

  Future<void> deleteUfmCase(String caseId) async {
    final db = await database;
    await db.delete('exam_ufm_cases', where: 'id = ?', whereArgs: [caseId]);
    onExamDataRemoved?.call([('exam_ufm_cases', caseId)]);
  }

  Future<AttendanceSharingData> loadAttendanceSharing(String teacherId) async {
    final db = await database;
    final sharedRows = await db.rawQuery(
      '''
      SELECT s.id, c.course_name, h.name AS hall_name, sh.exam_date_time,
             s.shared_with, s.shared_at, s.status, s.payload
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

  // ---- Teacher-given assignments (separate table) -------------------------

  // ---------------------------------------------------- admin data-share
  Future<Map<String, dynamic>> exportAssessments() async {
    final db = await database;
    return {
      'teacher_assignments': await TableSync.dump(db, 'teacher_assignments'),
      'student_submissions': await TableSync.dump(db, 'student_submissions'),
    };
  }

  Future<(int, int)> importAssessments(Map<String, dynamic> data) async {
    final db = await database;
    final a = await TableSync.merge(
      db,
      'teacher_assignments',
      (data['teacher_assignments'] as List?) ?? const [],
      tsOf: (r) => TableSync.ts(r, 'updated_at'),
    );
    final b = await TableSync.merge(
      db,
      'student_submissions',
      (data['student_submissions'] as List?) ?? const [],
      tsOf: (r) => TableSync.ts(r, 'updated_at'),
    );
    return (a.$1 + b.$1, a.$2 + b.$2);
  }

  /// The exam-attendance-sheet subsystem that UFM cases hang off (students,
  /// halls, sheets, records, ufm) — dumped/merged in dependency order.
  Future<Map<String, dynamic>> exportUfm() async {
    final db = await database;
    return {
      for (final t in const [
        'students',
        'exam_halls',
        'exam_attendance_sheets',
        'exam_attendance_records',
        'exam_ufm_cases',
      ])
        t: await TableSync.dump(db, t),
    };
  }

  Future<(int, int)> importUfm(Map<String, dynamic> data) async {
    final db = await database;
    var added = 0;
    var updated = 0;
    Future<void> mrg(
      String table, {
      DateTime? Function(Map<String, Object?>)? tsOf,
    }) async {
      final res = await TableSync.merge(
        db,
        table,
        (data[table] as List?) ?? const [],
        tsOf: tsOf,
      );
      added += res.$1;
      updated += res.$2;
    }

    await mrg('students'); // reference rows — add if missing
    await mrg('exam_halls', tsOf: (r) => TableSync.ts(r, 'created_at'));
    await mrg(
      'exam_attendance_sheets',
      tsOf: (r) => TableSync.ts(r, 'last_updated_at'),
    );
    await mrg('exam_attendance_records');
    await mrg('exam_ufm_cases', tsOf: (r) => TableSync.ts(r, 'created_at'));
    return (added, updated);
  }

  // ---------------------------------------------------- cloud sync helpers
  /// Rows of [table] whose [tsCol] is greater than [sinceIso] (all rows when
  /// [sinceIso] is null/empty). ISO-8601 strings sort lexicographically.
  Future<List<Map<String, Object?>>> examRowsSince(
    String table,
    String tsCol,
    String? sinceIso,
  ) async {
    final db = await database;
    final rows = (sinceIso == null || sinceIso.isEmpty)
        ? await db.query(table)
        : await db.query(table, where: '$tsCol > ?', whereArgs: [sinceIso]);
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  /// Rows of [table] with an id in [ids] (chunked to respect SQLite limits).
  Future<List<Map<String, Object?>>> examRowsByIds(
    String table,
    Set<String> ids,
  ) async {
    if (ids.isEmpty) return const [];
    final db = await database;
    final list = ids.toList();
    final out = <Map<String, Object?>>[];
    for (var i = 0; i < list.length; i += 400) {
      final chunk = list.skip(i).take(400).toList();
      final ph = List.filled(chunk.length, '?').join(',');
      final rows = await db.query(
        table,
        where: 'id IN ($ph)',
        whereArgs: chunk,
      );
      out.addAll(rows.map((r) => Map<String, Object?>.from(r)));
    }
    return out;
  }

  /// Inserts/replaces [rows] into [table] by primary key (cloud pull).
  Future<void> upsertExamRows(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    if (rows.isEmpty) return;
    final db = await database;
    await db.transaction((txn) async {
      for (final r in rows) {
        await txn.insert(
          table,
          r,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
      }
    });
  }

  /// Replaces the whole `teacher_assignments` table with [items] (each is an
  /// Assessment.toJson map). The full paper — questions + answer key — lives in
  /// the `data` column; id/course/title/type are mirrored for querying.
  Future<void> saveTeacherAssignments(
    List<Map<String, Object?>> items,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('teacher_assignments');
      final now = DateTime.now().toIso8601String();
      for (final j in items) {
        final id = (j['id'] ?? '').toString();
        if (id.isEmpty) continue;
        await txn.insert('teacher_assignments', {
          'id': id,
          'course_id': (j['courseId'] ?? '').toString(),
          'title': (j['title'] ?? '').toString(),
          'type': '${j['type'] ?? ''}',
          'updated_at': now,
          'data': jsonEncode(j),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    CloudSyncService.instance.pushModulesSoon('assessments');
  }

  Future<List<Map<String, Object?>>> loadTeacherAssignments() async {
    final db = await database;
    final rows = await db.query('teacher_assignments');
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      try {
        final d = jsonDecode((r['data'] ?? '{}').toString());
        if (d is Map) out.add(d.cast<String, Object?>());
      } catch (_) {}
    }
    return out;
  }

  // ---- Student-completed submissions (separate table) ---------------------

  Future<void> saveStudentSubmissions(
    List<Map<String, Object?>> items,
  ) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.delete('student_submissions');
      final now = DateTime.now().toIso8601String();
      for (final j in items) {
        final id = (j['id'] ?? '').toString();
        if (id.isEmpty) continue;
        await txn.insert('student_submissions', {
          'id': id,
          'assessment_id': (j['assessmentId'] ?? '').toString(),
          'student_id': (j['studentId'] ?? '').toString(),
          'student_name': (j['studentName'] ?? '').toString(),
          'marks': j['marks'] is int
              ? j['marks']
              : int.tryParse('${j['marks']}'),
          'updated_at': now,
          'data': jsonEncode(j),
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    CloudSyncService.instance.pushModulesSoon('assessments');
  }

  Future<List<Map<String, Object?>>> loadStudentSubmissions() async {
    final db = await database;
    final rows = await db.query('student_submissions');
    final out = <Map<String, Object?>>[];
    for (final r in rows) {
      try {
        final d = jsonDecode((r['data'] ?? '{}').toString());
        if (d is Map) out.add(d.cast<String, Object?>());
      } catch (_) {}
    }
    return out;
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
    // The assignments a TEACHER gives (full paper: questions + answer key) and
    // the submissions STUDENTS complete are kept in two SEPARATE tables.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS teacher_assignments(
        id TEXT PRIMARY KEY,
        course_id TEXT,
        title TEXT,
        type TEXT,
        updated_at TEXT,
        data TEXT NOT NULL
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS student_submissions(
        id TEXT PRIMARY KEY,
        assessment_id TEXT,
        student_id TEXT,
        student_name TEXT,
        marks INTEGER,
        updated_at TEXT,
        data TEXT NOT NULL
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
    // Class/section breakdown (added for the colour-coded live skeleton) —
    // guarded ALTER so existing installs migrate in place.
    try {
      await db.execute(
        "ALTER TABLE exam_halls ADD COLUMN class_groups TEXT NOT NULL DEFAULT ''",
      );
    } catch (_) {
      // Column already exists.
    }
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
    // Seat columns (added later for the live hall skeleton) — guarded ALTERs
    // so existing installs migrate in place.
    for (final statement in const [
      "ALTER TABLE exam_attendance_records ADD COLUMN seat_label TEXT NOT NULL DEFAULT ''",
      'ALTER TABLE exam_attendance_records ADD COLUMN col_no INTEGER NOT NULL DEFAULT 0',
      'ALTER TABLE exam_attendance_records ADD COLUMN chair_no INTEGER NOT NULL DEFAULT 0',
      "ALTER TABLE exam_attendance_records ADD COLUMN class_group TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE exam_attendance_records ADD COLUMN flag TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE exam_attendance_records ADD COLUMN collected_by TEXT NOT NULL DEFAULT ''",
      "ALTER TABLE exam_ufm_cases ADD COLUMN collected_by TEXT NOT NULL DEFAULT ''",
    ]) {
      try {
        await db.execute(statement);
      } catch (_) {
        // Column already exists.
      }
    }
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
      CREATE TABLE IF NOT EXISTS exam_ufm_cases(
        id TEXT PRIMARY KEY,
        sheet_id TEXT NOT NULL,
        student_id TEXT NOT NULL,
        allegation TEXT NOT NULL,
        details TEXT NOT NULL DEFAULT '',
        created_at TEXT NOT NULL,
        FOREIGN KEY(sheet_id) REFERENCES exam_attendance_sheets(id),
        FOREIGN KEY(student_id) REFERENCES students(id)
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_exam_ufm_sheet ON exam_ufm_cases(sheet_id)',
    );
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
      payload: row['payload']?.toString() ?? '',
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
             h.expected_students, h.seat_info, h.class_groups, c.id AS course_id,
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
    final presentCount = _intValue(row['present_count']);
    // Dynamic sheets can hold fewer records than the hall expects (students
    // are added scan-by-scan), so the total is whichever is larger and the
    // unscanned remainder counts as absent.
    final totalStudents = recordCount >= expected ? recordCount : expected;
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
      presentStudents: presentCount,
      absentStudents: totalStudents - presentCount,
      status: row['status'].toString(),
      seatInfo: row['seat_info']?.toString() ?? '',
      classGroups: _decodeClassGroups(row['class_groups']),
    );
  }

  List<ExamClassGroup> _decodeClassGroups(Object? value) {
    final text = (value ?? '').toString().trim();
    if (text.isEmpty) {
      return const [];
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! List) {
        return const [];
      }
      return decoded
          .whereType<Map>()
          .map(
            (row) => ExamClassGroup(
              program: (row['program'] ?? '').toString(),
              subject: (row['subject'] ?? '').toString(),
              faculty: (row['faculty'] ?? '').toString(),
              count: _intValue(row['count']),
            ),
          )
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  Future<List<ExamAttendanceStudent>> _loadAttendanceStudents(
    Database db,
    String sheetId,
  ) async {
    final rows = await db.rawQuery(
      '''
      SELECT s.id, s.name, s.roll_no, r.status,
             r.seat_label, r.col_no, r.chair_no, r.class_group, r.flag,
             r.collected_by
      FROM exam_attendance_records r
      JOIN students s ON s.id = r.student_id
      WHERE r.sheet_id = ?
      ORDER BY CASE WHEN r.col_no > 0 THEN 0 ELSE 1 END,
               r.col_no, r.chair_no, s.roll_no, s.name
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
            seatLabel: row['seat_label']?.toString() ?? '',
            colNo: _intValue(row['col_no']),
            chairNo: _intValue(row['chair_no']),
            classGroup: row['class_group']?.toString() ?? '',
            flag: row['flag']?.toString() ?? '',
            collectedBy: row['collected_by']?.toString() ?? '',
          ),
        )
        .toList(growable: false);
  }

  /// Marks [studentId] PRESENT with an extra [flag] ('qr_problem' or
  /// 'paper_not_returned', or '' to clear). Used from the live scan screen for
  /// students whose printed QR won't scan, or who didn't return the paper.
  Future<void> setAttendanceFlag({
    required String sheetId,
    required String studentId,
    required String flag,
  }) async {
    final db = await database;
    await db.update(
      'exam_attendance_records',
      {'status': 'present', 'flag': flag, 'marked_at': DateTime.now().toIso8601String()},
      where: 'sheet_id = ? AND student_id = ?',
      whereArgs: [sheetId, studentId],
    );
  }

  /// Prefix of the compressed full-detail hall QR printed on the dedicated
  /// "HALL ATTENDANCE QR" page of csexam seating plans (v2 format).
  static const String _hallQrV2Prefix = 'CSEXAM|QHALL|2|';

  Future<_ParsedHallQr> _parseHallQr(
    Database db,
    String teacherId,
    String rawPayload,
  ) async {
    final raw = rawPayload.trim();
    if (raw.isEmpty) {
      return _ParsedHallQr.invalid(raw);
    }

    // Full-detail hall QR: base64Url(gzip(json)) with classes + seat map.
    if (raw.toUpperCase().startsWith(_hallQrV2Prefix)) {
      final body = _tryDecodeHallV2(raw.substring(_hallQrV2Prefix.length));
      if (body is Map) {
        return _parseCsexamHallV2(db, teacherId, raw, body);
      }
      return _ParsedHallQr.invalid(raw);
    }

    final decoded = _tryDecodeJson(raw);
    if (decoded is Map) {
      // The "HALL QR" printed on csexam seating plans / envelopes:
      // {"app":"CSEXAM","type":"hall_seating_stats","date":...,"shift":...,
      //  "hall":...,"students":N,"groups":[[program,subject,faculty,count],..]}
      final isCsexamHallQr =
          _jsonString(decoded, 'app', 'app').toUpperCase() == 'CSEXAM' &&
          (decoded['type'] == 'hall_seating_stats' ||
              decoded['type'] == 'envelope_summary' ||
              decoded['action'] == 'open_hall_attendance');
      if (isCsexamHallQr) {
        return _parseCsexamHallJson(db, teacherId, raw, decoded);
      }
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
    if (parts.length < 7 ||
        parts[0].toUpperCase() != 'CSEXAM' ||
        parts[1].toUpperCase() != 'QPATT') {
      return _ParsedHallQr.invalid(raw);
    }
    final token = parts[3].toUpperCase();
    final scannedRoll = parts.length > 7 ? parts[7].toUpperCase() : '';
    final seedRows = await _loadQrSeedRows();
    final seed = seedRows.cast<Map<String, Object?>>().firstWhere(
      (row) =>
          row['token']?.toString().toUpperCase() == token ||
          (scannedRoll.isNotEmpty &&
              row['roll_no']?.toString().toUpperCase() == scannedRoll),
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

    // Build the hall's student list straight from the seating plan. The
    // sheet then works for ANY invigilating teacher — no course-ownership
    // requirement (which used to make hall scans fail).
    final seenRolls = <String>{};
    final seatStudents = <_SeatStudent>[];
    for (final row in matchingSeeds) {
      final roll = (row['roll_no']?.toString() ?? '').trim();
      if (roll.isEmpty || !seenRolls.add(roll.toUpperCase())) {
        continue;
      }
      seatStudents.add(
        _SeatStudent(
          rollNo: roll,
          name: (row['student_name']?.toString() ?? '').trim(),
          colNo: _intValue(row['col_no']),
          chairNo: _intValue(row['chair_no']),
          seatLabel: (row['seat_label']?.toString() ?? '').trim(),
        ),
      );
    }

    // Newer exam that's not in the bundled seed: start the sheet with just
    // the scanned seat; the rest of the hall joins live, scan by scan.
    if (seatStudents.isEmpty && scannedRoll.isNotEmpty) {
      seatStudents.add(
        _SeatStudent(
          rollNo: parts[7],
          name: '',
          colNo: parts.length > 8 ? _intValue(parts[8]) : 0,
          chairNo: parts.length > 9 ? _intValue(parts[9]) : 0,
          seatLabel: hallCode.isEmpty
              ? ''
              : 'Hall $hallCode'
                    '${parts.length > 8 ? ' | Col ${parts[8]}' : ''}'
                    '${parts.length > 9 ? ' | Chair ${parts[9]}' : ''}',
        ),
      );
    }

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
      courseName: courseName.isEmpty ? 'Exam Hall $hallCode' : courseName,
      examDateTime: _parseExamDate(examDate, shift),
      expectedStudents: seatStudents.isEmpty
          ? matchingSeeds.length
          : seatStudents.length,
      seatInfo: seed['seat_label']?.toString() ?? '',
      program: seed['program']?.toString() ?? '',
      faculty: seed['faculty']?.toString() ?? '',
      seatStudents: seatStudents,
      rosterFromCourse: false,
    );
  }

  /// Parses the JSON "HALL QR" printed on csexam seating plans. Students come
  /// from the bundled seating-plan seed when available (full roster + real
  /// seats); otherwise the sheet starts empty with the expected count from
  /// the QR and fills dynamically as seat QRs are scanned in the live screen.
  Future<_ParsedHallQr> _parseCsexamHallJson(
    Database db,
    String teacherId,
    String raw,
    Map<dynamic, dynamic> decoded,
  ) async {
    final examDate = _jsonString(decoded, 'date', 'examDate');
    final shift = _jsonString(decoded, 'shift', 'examShift');
    final hallCode = _jsonString(decoded, 'hall', 'hallCode');
    final expected = _intValue(decoded['students']);

    final subjects = <String>{};
    final programs = <String>{};
    final faculties = <String>{};
    final classGroups = <ExamClassGroup>[];
    if (decoded['groups'] is List) {
      for (final group in decoded['groups'] as List) {
        if (group is! List) continue;
        final program = group.isNotEmpty ? group[0].toString().trim() : '';
        final subject = group.length > 1 ? group[1].toString().trim() : '';
        final faculty = group.length > 2 ? group[2].toString().trim() : '';
        final count = group.length > 3 ? _intValue(group[3]) : 0;
        if (program.isNotEmpty) programs.add(program);
        if (subject.isNotEmpty) subjects.add(subject);
        if (faculty.isNotEmpty) faculties.add(faculty);
        if (program.isNotEmpty || subject.isNotEmpty) {
          classGroups.add(
            ExamClassGroup(
              program: program,
              subject: subject,
              faculty: faculty,
              count: count,
            ),
          );
        }
      }
    }

    // Full roster (with seats) when this exam exists in the bundled seed.
    final seedRows = await _loadQrSeedRows();
    final seenRolls = <String>{};
    final seatStudents = <_SeatStudent>[];
    for (final row in seedRows) {
      if ((row['exam_date']?.toString() ?? '') != examDate ||
          (row['shift']?.toString() ?? '') != shift ||
          (row['hall_code']?.toString() ?? '') != hallCode) {
        continue;
      }
      final roll = (row['roll_no']?.toString() ?? '').trim();
      if (roll.isEmpty || !seenRolls.add(roll.toUpperCase())) {
        continue;
      }
      seatStudents.add(
        _SeatStudent(
          rollNo: roll,
          name: (row['student_name']?.toString() ?? '').trim(),
          colNo: _intValue(row['col_no']),
          chairNo: _intValue(row['chair_no']),
          seatLabel: (row['seat_label']?.toString() ?? '').trim(),
        ),
      );
    }

    // Course naming: a hall can host several papers at once.
    String courseName;
    var courseId = '';
    if (subjects.length == 1) {
      courseName = subjects.first;
      courseId = await _resolveCourseId(
        db,
        teacherId: teacherId,
        courseId: '',
        courseCode: '',
        courseName: courseName,
      );
    } else if (subjects.isEmpty) {
      courseName = 'Exam Hall ${hallCode.isEmpty ? '' : hallCode}'.trim();
    } else {
      courseName = 'Hall $hallCode — ${subjects.length} papers';
    }

    // The expected count may be missing from the QR — fall back to the sum of
    // the per-class counts so a multi-class hall still opens and the skeleton
    // can be sized.
    final groupTotal = classGroups.fold<int>(0, (sum, g) => sum + g.count);
    final effectiveExpected = expected > 0
        ? expected
        : (groupTotal > 0 ? groupTotal : seatStudents.length);

    return _ParsedHallQr(
      rawPayload: raw,
      hallId: 'HALL_${_normalize(hallCode)}',
      hallName: hallCode.isEmpty ? 'Exam Hall' : hallCode,
      courseId: courseId,
      courseName: courseName,
      examDateTime: _parseExamDate(examDate, shift),
      expectedStudents: effectiveExpected,
      seatInfo: '',
      program: programs.join(' / '),
      faculty: faculties.join(', '),
      seatStudents: seatStudents,
      classGroups: classGroups,
      rosterFromCourse: false,
    );
  }

  /// Decompresses the body of a CSEXAM|QHALL|2| payload to its JSON map.
  Object? _tryDecodeHallV2(String body) {
    try {
      var normalized = body.trim();
      final remainder = normalized.length % 4;
      if (remainder != 0) {
        normalized = normalized.padRight(
          normalized.length + 4 - remainder,
          '=',
        );
      }
      final bytes = base64Url.decode(normalized);
      return jsonDecode(utf8.decode(GZipDecoder().decodeBytes(bytes)));
    } catch (_) {
      return null;
    }
  }

  /// Parses the compressed full-detail hall QR (the big "HALL ATTENDANCE QR"
  /// page): `{'t','d','s','h','n','g':[[program,subject,faculty,count]...],
  /// 'm':[[roll,col,chair,groupIndex]...]}`. The seat map gives the complete
  /// roster with real seats AND the class of every student, so the hall opens
  /// pre-seeded — exact skeleton, per-class cards, correct absent rolls.
  Future<_ParsedHallQr> _parseCsexamHallV2(
    Database db,
    String teacherId,
    String raw,
    Map<dynamic, dynamic> decoded,
  ) async {
    final examDate = _jsonString(decoded, 'd', 'date');
    final shift = _jsonString(decoded, 's', 'shift');
    final hallCode = _jsonString(decoded, 'h', 'hall');
    final expected = _intValue(decoded['n']);

    final classGroups = <ExamClassGroup>[];
    final subjects = <String>{};
    final programs = <String>{};
    final faculties = <String>{};
    if (decoded['g'] is List) {
      for (final group in decoded['g'] as List) {
        if (group is! List) continue;
        final program = group.isNotEmpty ? group[0].toString().trim() : '';
        final subject = group.length > 1 ? group[1].toString().trim() : '';
        final faculty = group.length > 2 ? group[2].toString().trim() : '';
        final count = group.length > 3 ? _intValue(group[3]) : 0;
        if (program.isNotEmpty) programs.add(program);
        if (subject.isNotEmpty) subjects.add(subject);
        if (faculty.isNotEmpty) faculties.add(faculty);
        if (program.isNotEmpty || subject.isNotEmpty) {
          classGroups.add(
            ExamClassGroup(
              program: program,
              subject: subject,
              faculty: faculty,
              count: count,
            ),
          );
        }
      }
    }

    // Seat map → complete roster with real seats + class attribution. Student
    // names come from the bundled seed when the roll is known there.
    await _ensureSeedCache();
    final seenRolls = <String>{};
    final seatStudents = <_SeatStudent>[];
    if (decoded['m'] is List) {
      for (final entry in decoded['m'] as List) {
        if (entry is! List || entry.isEmpty) continue;
        final roll = entry[0].toString().trim();
        if (roll.isEmpty || !seenRolls.add(roll.toUpperCase())) continue;
        final col = entry.length > 1 ? _intValue(entry[1]) : 0;
        final chair = entry.length > 2 ? _intValue(entry[2]) : 0;
        final groupIndex = entry.length > 3 ? _intValue(entry[3]) : -1;
        final classGroup =
            groupIndex >= 0 && groupIndex < classGroups.length
            ? classGroups[groupIndex].program
            : '';
        seatStudents.add(
          _SeatStudent(
            rollNo: roll,
            name: _seedByRoll?[roll.toUpperCase()]?.name ?? '',
            colNo: col,
            chairNo: chair,
            seatLabel: col > 0
                ? 'Hall $hallCode | Col $col | Chair $chair'
                : '',
            classGroup: classGroup,
          ),
        );
      }
    }

    String courseName;
    var courseId = '';
    if (subjects.length == 1) {
      courseName = subjects.first;
      courseId = await _resolveCourseId(
        db,
        teacherId: teacherId,
        courseId: '',
        courseCode: '',
        courseName: courseName,
      );
    } else if (subjects.isEmpty) {
      courseName = 'Exam Hall ${hallCode.isEmpty ? '' : hallCode}'.trim();
    } else {
      courseName = 'Hall $hallCode — ${subjects.length} papers';
    }

    final groupTotal = classGroups.fold<int>(0, (sum, g) => sum + g.count);
    final effectiveExpected = expected > 0
        ? expected
        : (seatStudents.isNotEmpty ? seatStudents.length : groupTotal);

    return _ParsedHallQr(
      rawPayload: raw,
      hallId: 'HALL_${_normalize(hallCode)}',
      hallName: hallCode.isEmpty ? 'Exam Hall' : hallCode,
      courseId: courseId,
      courseName: courseName,
      examDateTime: _parseExamDate(examDate, shift),
      expectedStudents: effectiveExpected,
      seatInfo: '',
      program: programs.join(' / '),
      faculty: faculties.join(', '),
      seatStudents: seatStudents,
      classGroups: classGroups,
      rosterFromCourse: false,
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
      // Prefer the scanning teacher's own course, but fall back to ANY course
      // with this code — invigilators usually supervise other teachers' exams.
      for (final where in const [
        'UPPER(course_code) = ? AND teacher_id = ?',
        'UPPER(course_code) = ?',
      ]) {
        final rows = await db.query(
          'courses',
          columns: ['id'],
          where: where,
          whereArgs: where.contains('teacher_id')
              ? [courseCode.trim().toUpperCase(), teacherId]
              : [courseCode.trim().toUpperCase()],
          limit: 1,
        );
        if (rows.isNotEmpty) {
          return rows.first['id'].toString();
        }
      }
    }
    if (courseName.trim().isNotEmpty) {
      final normalized = _normalize(courseName);
      // Own courses first, then all courses.
      for (final restrictToTeacher in const [true, false]) {
        final rows = await db.query(
          'courses',
          columns: ['id', 'course_name'],
          where: restrictToTeacher ? 'teacher_id = ?' : null,
          whereArgs: restrictToTeacher ? [teacherId] : null,
        );
        for (final row in rows) {
          if (_normalize(row['course_name'].toString()) == normalized) {
            return row['id'].toString();
          }
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

  /// Looks up a student from the bundled seating-plan seed by QR token or roll
  /// number. The live hall-scan screen uses this so a scanned seat QR resolves
  /// to the student's real name + seat even for halls that are not pre-seeded
  /// (dynamic rosters), matching how the standalone QR attendance scanner
  /// recognises students.
  Future<SeedStudentInfo?> lookupSeedStudent({
    String token = '',
    String rollNo = '',
  }) async {
    await _ensureSeedCache();
    final normalizedToken = token.trim().toUpperCase();
    if (normalizedToken.isNotEmpty) {
      final hit = _seedByToken![normalizedToken];
      if (hit != null) {
        return hit;
      }
    }
    final normalizedRoll = rollNo.trim().toUpperCase();
    if (normalizedRoll.isNotEmpty) {
      final hit = _seedByRoll![normalizedRoll];
      if (hit != null) {
        return hit;
      }
    }
    return null;
  }

  Future<void> _ensureSeedCache() async {
    if (_seedByToken != null) {
      return;
    }
    final byToken = <String, SeedStudentInfo>{};
    final byRoll = <String, SeedStudentInfo>{};
    for (final row in await _loadQrSeedRows()) {
      final info = SeedStudentInfo(
        rollNo: (row['roll_no'] ?? '').toString().trim(),
        name: (row['student_name'] ?? '').toString().trim(),
        hall: (row['hall_code'] ?? '').toString().trim(),
        colNo: _intValue(row['col_no']),
        chairNo: _intValue(row['chair_no']),
        seatLabel: (row['seat_label'] ?? '').toString().trim(),
      );
      final token = (row['token'] ?? '').toString().trim().toUpperCase();
      if (token.isNotEmpty) {
        byToken[token] = info;
      }
      if (info.rollNo.isNotEmpty) {
        byRoll[info.rollNo.toUpperCase()] = info;
      }
    }
    _seedByToken = byToken;
    _seedByRoll = byRoll;
  }

  /// Full share text: summary plus the per-student present/absent lists
  /// (with seats when known) and every recorded UFM case.
  /// Builds a ready-to-share summary for one scope: the whole hall, or a single
  /// class when [classGroup] is set. Carries both the human-readable text and a
  /// scannable `CSEXAM|QATTN|1|...` payload.
  Future<AttendanceShareData> loadAttendanceShare({
    required String sheetId,
    String classGroup = '',
    String sharedBy = '',
  }) async {
    final detail = await loadAttendanceSheetDetail(sheetId);
    final ufmCases = await loadUfmCases(sheetId);
    return _buildAttendanceShare(
      detail,
      ufmCases,
      classGroup: classGroup,
      sharedBy: sharedBy,
    );
  }

  /// Logs a share (per scope) in shared_attendance_sheets so it shows under
  /// "Shared/Accepted Stats", and returns the share data.
  Future<AttendanceShareData> recordAttendanceShare({
    required String teacherId,
    required String sheetId,
    required String sharedWith,
    String classGroup = '',
    String sharedBy = '',
  }) async {
    final db = await database;
    final detail = await loadAttendanceSheetDetail(sheetId);
    final ufmCases = await loadUfmCases(sheetId);
    final share = _buildAttendanceShare(
      detail,
      ufmCases,
      classGroup: classGroup,
      sharedBy: sharedBy,
    );
    final id = 'SHR${DateTime.now().microsecondsSinceEpoch}';
    await db.insert('shared_attendance_sheets', {
      'id': id,
      'sheet_id': sheetId,
      'teacher_id': teacherId,
      'shared_with': sharedWith.trim().isEmpty ? 'Admin' : sharedWith.trim(),
      'shared_at': DateTime.now().toIso8601String(),
      'status': 'Shared (${share.scopeLabel})',
      'payload': share.text,
    });
    await _insertNotification(
      db,
      teacherId: teacherId,
      category: TeacherNotificationCategory.sharedAttendance,
      title: 'Attendance shared',
      message: '${detail.stats.hallName} — ${share.scopeLabel}',
    );
    return share;
  }

  /// Accepts an attendance transfer scanned/pasted as a `CSEXAM|QATTN|1|...`
  /// payload and records it under "Accepted Attendance Sheets".
  Future<AcceptedAttendanceSheetSummary> acceptAttendanceQr({
    required String teacherId,
    required String rawPayload,
  }) async {
    final decoded = _decodeAttendanceQr(rawPayload);
    if (decoded == null) {
      throw const FormatException(
        'Not an attendance transfer QR (expected CSEXAM|QATTN|1|…).',
      );
    }
    final db = await database;
    final hall = (decoded['h'] ?? '').toString();
    final date = (decoded['d'] ?? '').toString();
    final shift = (decoded['s'] ?? '').toString();
    final scope = (decoded['c'] ?? '').toString();
    final by = (decoded['by'] ?? '').toString();
    final examDateTime = _parseExamDate(date, shift);
    final examIso = examDateTime.toIso8601String();

    // MERGE the transfer into this device's hall sheet (find-or-create, keyed
    // by hall + exam date). This is the "shake of hands": two invigilators'
    // programs combine into one complete hall, and the paper-collection team
    // accumulates every hall it accepts. Present always wins (a present mark is
    // never downgraded to absent by a later merge).
    final sheetId = await _findOrCreateReceiverSheet(
      db,
      teacherId: teacherId,
      hall: hall.isEmpty ? 'Exam Hall' : hall,
      examIso: examIso,
      expected: _intValue(decoded['n']),
    );
    final mergedPresent = await _mergeTransferStudents(db, sheetId, decoded);
    final stats = await _loadExamHallStats(db, sheetId);

    final courseName = scope.isEmpty ? 'Hall $hall (all classes)' : scope;
    final text = _acceptedShareText(decoded);
    final id = 'ACC${DateTime.now().microsecondsSinceEpoch}';
    final statusLabel =
        'Merged • ${stats.presentStudents} present / ${stats.totalStudents}';
    await db.insert('accepted_attendance_sheets', {
      'id': id,
      'teacher_id': teacherId,
      'course_name': courseName,
      'hall_name': hall.isEmpty ? 'Exam Hall' : hall,
      'exam_date_time': examIso,
      'received_from': by.isEmpty ? 'Another device' : by,
      'accepted_at': DateTime.now().toIso8601String(),
      'status': statusLabel,
      'payload': text,
    });
    await _insertNotification(
      db,
      teacherId: teacherId,
      category: TeacherNotificationCategory.acceptedAttendance,
      title: 'Attendance accepted',
      message: '$courseName — $hall ($mergedPresent present merged)',
    );
    onExamDataChanged?.call();
    return AcceptedAttendanceSheetSummary(
      id: id,
      courseName: courseName,
      hallName: hall.isEmpty ? 'Exam Hall' : hall,
      examDateTime: examDateTime,
      receivedFrom: by.isEmpty ? 'Another device' : by,
      acceptedAt: DateTime.now(),
      status: statusLabel,
    );
  }

  /// Imports a whole `attendance_export` .txt (the same file csexam reads),
  /// received from ANOTHER phone. Every session merges into this teacher's
  /// Saved Stats — find-or-create per hall + date + shift, present always wins,
  /// UFM cases added, student names preserved. Returns a short summary.
  Future<AttendanceImportSummary> importAttendanceExport({
    required String teacherId,
    required String jsonText,
  }) async {
    final decoded = jsonDecode(jsonText.trim());
    if (decoded is! Map || decoded['type'] != 'attendance_export') {
      throw const FormatException(
        'Not an AUST attendance file. On the other phone use Exam Attendance '
        '→ Export for csexam → Share file, then open that .txt here.',
      );
    }
    final sessionsRaw = decoded['sessions'];
    if (sessionsRaw is! List || sessionsRaw.isEmpty) {
      throw const FormatException('The file has no attendance sessions.');
    }
    final db = await database;
    var halls = 0, present = 0, absent = 0, ufmCount = 0;
    for (final raw in sessionsRaw) {
      if (raw is! Map) continue;
      final hall = (raw['hall'] ?? '').toString().trim();
      final dateIso = (raw['dateIso'] ?? '').toString();
      final date = (raw['date'] ?? '').toString();
      final shift = (raw['shift'] ?? '').toString();
      final examIso =
          DateTime.tryParse(dateIso)?.toIso8601String() ??
          _parseExamDate(date, shift).toIso8601String();
      final students = (raw['students'] is List)
          ? raw['students'] as List
          : const [];
      final ufm = (raw['ufm'] is List) ? raw['ufm'] as List : const [];

      final sheetId = await _findOrCreateReceiverSheet(
        db,
        teacherId: teacherId,
        hall: hall.isEmpty ? 'Exam Hall' : hall,
        examIso: examIso,
        expected: students.length,
      );

      // Preserve real names: insert (ignore) then fill blank / roll-only names.
      for (final st in students) {
        if (st is! Map) continue;
        final roll = (st['roll'] ?? '').toString().trim();
        if (roll.isEmpty) continue;
        final name = (st['name'] ?? '').toString().trim();
        final id = 'STU$roll';
        await db.insert('students', {
          'id': id,
          'name': name.isEmpty ? roll : name,
          'roll_no': roll,
          'program': '',
          'session': '',
          'semester': '',
          'section': '',
          'email': '',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        if (name.isNotEmpty && name != roll) {
          await db.update(
            'students',
            {'name': name},
            where: "id = ? AND (name = '' OR name = roll_no)",
            whereArgs: [id],
          );
        }
      }

      // Reuse the QR-merge engine: build its [st]/[u] shape (present wins).
      final st = <List<Object?>>[
        for (final s in students)
          if (s is Map)
            [
              (s['roll'] ?? '').toString(),
              (s['status'] ?? '').toString().toLowerCase() == 'present'
                  ? 'P'
                  : 'A',
              (s['seat'] ?? '').toString(),
              (s['class'] ?? '').toString(),
              (s['flag'] ?? '').toString(),
            ],
      ];
      final u = <List<Object?>>[
        for (final c in ufm)
          if (c is Map)
            [
              (c['roll'] ?? '').toString(),
              (c['allegation'] ?? '').toString(),
              (c['details'] ?? '').toString(),
            ],
      ];
      present += await _mergeTransferStudents(db, sheetId, {'st': st, 'u': u});
      absent += st.where((r) => r[1] == 'A').length;
      ufmCount += u.length;
      halls += 1;
    }
    return AttendanceImportSummary(
      sessions: halls,
      present: present,
      absent: absent,
      ufm: ufmCount,
    );
  }

  /// Finds this teacher's sheet for [hall] on [examIso], or creates a fresh
  /// "received" sheet (lightweight hall + course) so accepted transfers have a
  /// place to merge into.
  Future<String> _findOrCreateReceiverSheet(
    Database db, {
    required String teacherId,
    required String hall,
    required String examIso,
    required int expected,
  }) async {
    // Match by hall + DATE + SHIFT (morning vs afternoon) so the 1st-shift and
    // 2nd-shift sittings of the same hall on the same day stay SEPARATE
    // entries, while two invigilators of the SAME hall+shift merge into one.
    final afternoon =
        DateTime.tryParse(examIso) != null && DateTime.parse(examIso).hour >= 12
        ? 1
        : 0;
    final existing = await db.rawQuery(
      '''
      SELECT sh.id AS id
      FROM exam_attendance_sheets sh
      JOIN exam_halls h ON h.id = sh.hall_id
      WHERE sh.teacher_id = ?
        AND UPPER(h.name) = UPPER(?)
        AND date(sh.exam_date_time) = date(?)
        AND (CASE WHEN cast(strftime('%H', sh.exam_date_time) AS INTEGER) >= 12
                  THEN 1 ELSE 0 END) = ?
      ORDER BY sh.last_updated_at DESC
      LIMIT 1
      ''',
      [teacherId, hall, examIso, afternoon],
    );
    if (existing.isNotEmpty) {
      return existing.first['id'].toString();
    }
    final hallId = 'HALL${_stableHash('$hall|$examIso')}';
    final courseId = 'CRSX${_stableHash('Hall $hall|$examIso')}';
    final sheetId = 'EAS${_stableHash('$teacherId|$hallId|$courseId|$examIso')}';
    final now = DateTime.now().toIso8601String();
    await db.insert('courses', {
      'id': courseId,
      'teacher_id': '',
      'course_name': 'Hall $hall',
      'course_code': '',
      'credits': 0,
      'semester': '',
      'section': '',
      'enrolled_students': expected,
      'program': '',
      'session': '',
      'instructor': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('exam_halls', {
      'id': hallId,
      'name': hall,
      'course_id': courseId,
      'exam_date_time': examIso,
      'expected_students': expected,
      'seat_info': '',
      'qr_payload': '',
      'class_groups': '',
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    await db.insert('exam_attendance_sheets', {
      'id': sheetId,
      'teacher_id': teacherId,
      'course_id': courseId,
      'hall_id': hallId,
      'exam_date_time': examIso,
      'status': 'received',
      'created_at': now,
      'last_updated_at': now,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
    return sheetId;
  }

  /// Merges the QATTN students into [sheetId]. Present wins; UFM cases are
  /// added. Returns how many present students the transfer carried.
  Future<int> _mergeTransferStudents(
    Database db,
    String sheetId,
    Map<String, Object?> decoded,
  ) async {
    final students = decoded['st'];
    if (students is! List) {
      return 0;
    }
    var present = 0;
    await db.transaction((txn) async {
      final now = DateTime.now().toIso8601String();
      for (final row in students) {
        if (row is! List || row.isEmpty) continue;
        final roll = row[0].toString().trim();
        if (roll.isEmpty) continue;
        final isPresent = row.length > 1 && row[1].toString() == 'P';
        final seat = row.length > 2 ? row[2].toString() : '';
        final cls = row.length > 3 ? row[3].toString() : '';
        final flag = row.length > 4 ? row[4].toString() : '';
        final colChair = _parseSeatColChair(seat);
        if (isPresent) present += 1;
        final studentId = 'STU$roll';
        await txn.insert('students', {
          'id': studentId,
          'name': roll,
          'roll_no': roll,
          'program': '',
          'session': '',
          'semester': '',
          'section': '',
          'email': '',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
        final existing = await txn.query(
          'exam_attendance_records',
          columns: ['status'],
          where: 'sheet_id = ? AND student_id = ?',
          whereArgs: [sheetId, studentId],
          limit: 1,
        );
        if (existing.isEmpty) {
          await txn.insert('exam_attendance_records', {
            'id': 'EAR${_stableHash('$sheetId|$studentId')}',
            'sheet_id': sheetId,
            'student_id': studentId,
            'status': isPresent ? 'present' : 'absent',
            'marked_at': now,
            'seat_label': seat,
            'col_no': colChair.$1,
            'chair_no': colChair.$2,
            'class_group': cls,
            'flag': flag,
          }, conflictAlgorithm: ConflictAlgorithm.ignore);
        } else if (isPresent && existing.first['status'].toString() != 'present') {
          // Upgrade to present (never downgrade an existing present mark).
          await txn.update(
            'exam_attendance_records',
            {
              'status': 'present',
              'marked_at': now,
              if (seat.isNotEmpty) 'seat_label': seat,
              if (colChair.$1 > 0) 'col_no': colChair.$1,
              if (colChair.$2 > 0) 'chair_no': colChair.$2,
              if (cls.isNotEmpty) 'class_group': cls,
              if (flag.isNotEmpty) 'flag': flag,
            },
            where: 'sheet_id = ? AND student_id = ?',
            whereArgs: [sheetId, studentId],
          );
        }
      }
      // Merge UFM cases (skip exact duplicates already on this sheet).
      final ufm = decoded['u'];
      if (ufm is List) {
        for (final c in ufm) {
          if (c is! List || c.isEmpty) continue;
          final roll = c[0].toString().trim();
          if (roll.isEmpty) continue;
          final allegation = c.length > 1 ? c[1].toString() : '';
          final details = c.length > 2 ? c[2].toString() : '';
          final studentId = 'STU$roll';
          final dup = await txn.query(
            'exam_ufm_cases',
            where: 'sheet_id = ? AND student_id = ? AND allegation = ?',
            whereArgs: [sheetId, studentId, allegation],
            limit: 1,
          );
          if (dup.isEmpty) {
            await txn.insert('exam_ufm_cases', {
              'id': 'UFM${DateTime.now().microsecondsSinceEpoch}$roll',
              'sheet_id': sheetId,
              'student_id': studentId,
              'allegation': allegation,
              'details': details,
              'created_at': now,
            });
          }
        }
      }
      await txn.update(
        'exam_attendance_sheets',
        {'status': 'merged', 'last_updated_at': now},
        where: 'id = ?',
        whereArgs: [sheetId],
      );
    });
    return present;
  }

  (int, int) _parseSeatColChair(String label) {
    final m = RegExp(
      r'Col\s*(\d+).*Chair\s*(\d+)',
      caseSensitive: false,
    ).firstMatch(label);
    if (m == null) return (0, 0);
    return (int.tryParse(m.group(1)!) ?? 0, int.tryParse(m.group(2)!) ?? 0);
  }

  /// Exports EVERY attendance sheet on this device as one JSON record, grouped
  /// into sessions keyed by date + shift + hall (+ a per-class breakdown). This
  /// is the file the paper-collection/admin device hands back to csexam for the
  /// master record. Structure is intentionally extensible (add fields later).
  Future<String> exportAttendanceJson({
    required String teacherId,
    String exportedBy = '',
  }) async {
    final sheets = await loadAttendanceSheets(teacherId);
    final sessions = <Map<String, Object?>>[];
    for (final sheet in sheets) {
      final detail = await loadAttendanceSheetDetail(sheet.sheetId);
      final ufm = await loadUfmCases(sheet.sheetId);
      final stats = detail.stats;
      final dt = stats.examDateTime;
      final shift = dt.hour >= 12 ? '2nd' : '1st';

      final byClass = <String, Map<String, Object?>>{};
      for (final s in detail.students) {
        final cls = s.classGroup.trim().isEmpty
            ? stats.courseName
            : s.classGroup.trim();
        final m = byClass.putIfAbsent(
          cls,
          () => {'program': cls, 'present': 0, 'absent': 0, 'total': 0},
        );
        m['total'] = (m['total'] as int) + 1;
        if (s.status == 'present') {
          m['present'] = (m['present'] as int) + 1;
        } else {
          m['absent'] = (m['absent'] as int) + 1;
        }
      }

      sessions.add({
        'date': _ddMonYyyy(dt),
        'dateIso': dt.toIso8601String(),
        'shift': shift,
        'hall': stats.hallName,
        'course': stats.courseName,
        'total': stats.totalStudents,
        'present': stats.presentStudents,
        'absent': stats.absentStudents,
        'classes': byClass.values.toList(),
        'students': [
          for (final s in detail.students)
            {
              'roll': s.rollNo,
              'name': s.studentName,
              'status': s.status == 'present' ? 'present' : 'absent',
              'seat': s.seatLabel,
              'class': s.classGroup,
              // Which teacher scanned this student — rides into csexam.
              'by': s.collectedBy,
            },
        ],
        'ufm': [
          for (final c in ufm)
            {
              'roll': c.rollNo,
              'name': c.studentName,
              'allegation': c.allegation,
              'details': c.details,
            },
        ],
      });
    }
    return jsonEncode({
      'app': 'AUST_PORTAL',
      'type': 'attendance_export',
      'version': 1,
      'exportedAt': DateTime.now().toIso8601String(),
      'exportedBy': exportedBy,
      'sessionCount': sessions.length,
      'sessions': sessions,
    });
  }

  String _ddMonYyyy(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final d = dt.day.toString().padLeft(2, '0');
    final m = months[(dt.month - 1).clamp(0, 11)];
    return '$d-$m-${dt.year}';
  }

  AttendanceShareData _buildAttendanceShare(
    ExamAttendanceSheetDetail detail,
    List<UfmCase> ufmCases, {
    String classGroup = '',
    String sharedBy = '',
  }) {
    final stats = detail.stats;
    final scope = classGroup.trim();
    bool inScope(String group) =>
        scope.isEmpty || group.trim().toLowerCase() == scope.toLowerCase();

    final students = detail.students
        .where((s) => inScope(s.classGroup))
        .toList(growable: false);
    final caseRolls = {for (final s in detail.students) s.studentId: s.classGroup};
    final cases = ufmCases
        .where((c) => inScope(caseRolls[c.studentId] ?? ''))
        .toList(growable: false);

    final present = students
        .where((student) => student.status == 'present')
        .toList(growable: false);
    final absent = students
        .where((student) => student.status != 'present')
        .toList(growable: false);
    final qrProblem = present
        .where((s) => s.flag == 'qr_problem')
        .toList(growable: false);
    final paperNotReturned = present
        .where((s) => s.flag == 'paper_not_returned')
        .toList(growable: false);

    // Scope total: the class's seat count when scoped, else the hall total.
    var total = students.length;
    if (scope.isNotEmpty) {
      for (final group in stats.classGroups) {
        if (group.program.toLowerCase() == scope.toLowerCase()) {
          total = group.count > students.length ? group.count : students.length;
          break;
        }
      }
    } else {
      total = stats.totalStudents;
    }

    final scopeLabel = scope.isEmpty ? 'Whole hall (${stats.hallName})' : scope;

    String studentLine(ExamAttendanceStudent student) {
      final seat = student.seatLabel.isEmpty ? '' : '  [${student.seatLabel}]';
      return '- ${student.rollNo}  ${student.studentName}$seat';
    }

    final percent = total == 0 ? 0.0 : present.length / total * 100;
    final lines = <String>[
      if (sharedBy.trim().isNotEmpty) 'Shared by: ${sharedBy.trim()}',
      'Course: ${stats.courseName}',
      'Scope: $scopeLabel',
      'Exam hall: ${stats.hallName}',
      'Date/time: ${stats.examDateTime.toIso8601String()}',
      'Total students: $total',
      'Present students: ${present.length}',
      'Absent students: ${total - present.length}',
      'UFM cases: ${cases.length}',
      'Attendance: ${percent.toStringAsFixed(1)}%',
      '',
      'PRESENT (${present.length}):',
      if (present.isEmpty) '- none' else ...present.map(studentLine),
      '',
      'ABSENT (${absent.length}):',
      if (absent.isEmpty) '- none' else ...absent.map(studentLine),
      '',
      'UFM CASES (${cases.length}):',
      if (cases.isEmpty)
        '- none'
      else
        ...cases.map(
          (c) =>
              '- ${c.rollNo}  ${c.studentName} — ${c.allegation}'
              '${c.details.isEmpty ? '' : ' (${c.details})'}',
        ),
      if (qrProblem.isNotEmpty) ...[
        '',
        'QR PROBLEM — present, could not scan (${qrProblem.length}):',
        ...qrProblem.map(studentLine),
      ],
      if (paperNotReturned.isNotEmpty) ...[
        '',
        'PAPER NOT RETURNED — present (${paperNotReturned.length}):',
        ...paperNotReturned.map(studentLine),
      ],
    ];

    final qrPayload = _encodeAttendanceQr(
      stats: stats,
      classGroup: scope,
      total: total,
      students: students,
      cases: cases,
      sharedBy: sharedBy,
    );

    return AttendanceShareData(
      scopeLabel: scopeLabel,
      classGroup: scope,
      text: lines.join('\n'),
      qrPayload: qrPayload,
      total: total,
      present: present.length,
      absent: total - present.length,
    );
  }

  static const String _attendanceQrPrefix = 'CSEXAM|QATTN|1|';

  String _encodeAttendanceQr({
    required ExamHallStats stats,
    required String classGroup,
    required int total,
    required List<ExamAttendanceStudent> students,
    required List<UfmCase> cases,
    String sharedBy = '',
  }) {
    final body = <String, Object?>{
      'h': stats.hallName,
      'd': stats.examDateTime.toIso8601String(),
      's': stats.seatInfo,
      'c': classGroup,
      'n': total,
      // Who shared it (invigilator name) so the receiver keeps a source log.
      if (sharedBy.trim().isNotEmpty) 'by': sharedBy.trim(),
      'st': [
        for (final s in students)
          [
            s.rollNo,
            s.status == 'present' ? 'P' : 'A',
            s.seatLabel,
            s.classGroup,
            s.flag,
          ],
      ],
      'u': [
        for (final c in cases) [c.rollNo, c.allegation, c.details],
      ],
    };
    final compressed = GZipEncoder().encode(utf8.encode(jsonEncode(body)));
    return '$_attendanceQrPrefix${base64Url.encode(compressed)}';
  }

  Map<String, Object?>? _decodeAttendanceQr(String rawPayload) {
    final raw = rawPayload.trim();
    if (!raw.startsWith(_attendanceQrPrefix)) {
      return null;
    }
    try {
      var encoded = raw.substring(_attendanceQrPrefix.length).trim();
      final mod = encoded.length % 4;
      if (mod != 0) {
        encoded = encoded.padRight(encoded.length + (4 - mod), '=');
      }
      final bytes = base64Url.decode(encoded);
      final json = utf8.decode(GZipDecoder().decodeBytes(bytes));
      final decoded = jsonDecode(json);
      return decoded is Map ? decoded.cast<String, Object?>() : null;
    } catch (_) {
      return null;
    }
  }

  String _acceptedShareText(Map<String, Object?> decoded) {
    final hall = (decoded['h'] ?? '').toString();
    final scope = (decoded['c'] ?? '').toString();
    final rows = (decoded['st'] is List) ? decoded['st'] as List : const [];
    final present = <String>[];
    final absent = <String>[];
    for (final row in rows) {
      if (row is! List || row.isEmpty) continue;
      final roll = row[0].toString();
      final status = row.length > 1 ? row[1].toString() : 'A';
      final seat = row.length > 2 ? row[2].toString() : '';
      final line = seat.isEmpty ? '- $roll' : '- $roll  [$seat]';
      (status == 'P' ? present : absent).add(line);
    }
    final cases = (decoded['u'] is List) ? decoded['u'] as List : const [];
    return [
      'Scope: ${scope.isEmpty ? 'Whole hall ($hall)' : scope}',
      'Exam hall: $hall',
      'Total: ${decoded['n'] ?? rows.length}',
      'Present: ${present.length}',
      'Absent: ${absent.length}',
      '',
      'PRESENT (${present.length}):',
      if (present.isEmpty) '- none' else ...present,
      '',
      'ABSENT (${absent.length}):',
      if (absent.isEmpty) '- none' else ...absent,
      '',
      'UFM CASES (${cases.length}):',
      if (cases.isEmpty)
        '- none'
      else
        ...cases.map((c) {
          if (c is! List || c.isEmpty) return '- ?';
          final roll = c[0].toString();
          final allegation = c.length > 1 ? c[1].toString() : '';
          final details = c.length > 2 ? c[2].toString() : '';
          return '- $roll — $allegation${details.isEmpty ? '' : ' ($details)'}';
        }),
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
    this.program = '',
    this.faculty = '',
    this.seatStudents = const [],
    this.classGroups = const [],
    this.rosterFromCourse = true,
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
  final String program;
  final String faculty;

  /// Students from the seating-plan seed (with real seats). When non-empty,
  /// the attendance sheet is built from THESE students — the scanning teacher
  /// does not need to own the course (invigilators usually don't).
  final List<_SeatStudent> seatStudents;

  /// Classes/sections sharing this hall (from the HALL QR `groups`), used to
  /// draw the colour-coded skeleton immediately on fetch.
  final List<ExamClassGroup> classGroups;

  /// When true and [seatStudents] is empty, attendance records are pre-seeded
  /// from course enrollment (legacy JSON QR flow). csexam hall/seat QRs set
  /// this to false: classes are split across halls, so the sheet starts empty
  /// and students join live as their seat QRs are scanned.
  final bool rosterFromCourse;
  final bool valid;

  bool get isValid => valid;
}

/// One seat from the seating-plan seed data or a full-detail hall QR.
class _SeatStudent {
  const _SeatStudent({
    required this.rollNo,
    required this.name,
    required this.colNo,
    required this.chairNo,
    required this.seatLabel,
    this.classGroup = '',
  });

  final String rollNo;
  final String name;
  final int colNo;
  final int chairNo;
  final String seatLabel;

  /// The class/section this seat belongs to (e.g. "BSCS 2A"), when the QR
  /// carries the breakdown. Drives per-class attendance attribution.
  final String classGroup;
}

/// A student resolved from the bundled seating-plan seed by QR token or roll
/// number (returned by [TeacherDashboardDatabase.lookupSeedStudent]).
class SeedStudentInfo {
  const SeedStudentInfo({
    required this.rollNo,
    required this.name,
    required this.hall,
    required this.colNo,
    required this.chairNo,
    required this.seatLabel,
  });

  final String rollNo;
  final String name;
  final String hall;
  final int colNo;
  final int chairNo;
  final String seatLabel;
}
