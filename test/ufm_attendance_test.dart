import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teacher_student_assessment_app/services/app_repository.dart';
import 'package:teacher_student_assessment_app/services/teacher_dashboard_database.dart';

/// Mirrors csexam's `buildCsexamHallQrV2` (qr_pdf_service.dart) so the test
/// exercises the exact payload the printed "HALL ATTENDANCE QR" page carries.
String buildCsexamHallQrV2(Map<String, Object?> data) {
  final jsonBytes = utf8.encode(jsonEncode(data));
  final compressed = GZipEncoder().encode(jsonBytes);
  return 'CSEXAM|QHALL|2|${base64Url.encode(compressed)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('hall scan works from the printed HALL QR (JSON, seeded exam)',
      () async {
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    final database = TeacherDashboardDatabase.instance;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    // Exact payload format printed by csexam seating plans (HALL QR badge).
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'v': 1,
        'type': 'hall_seating_stats',
        'action': 'open_hall_attendance',
        'date': '29-May-26',
        'shift': '1st',
        'hall': 'G10',
        'students': 0,
        'groups': [
          ['BSCS 2D', 'MATHEMATICS-II', 'MS. ROMANA', 0],
        ],
      }),
    );
    expect(stats.hallName, 'G10');
    expect(stats.totalStudents, greaterThan(0));
    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students.any((s) => s.hasSeat), isTrue);
  });

  test('hall QR of a NEW exam (not in seed) starts a dynamic sheet', () async {
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    final database = TeacherDashboardDatabase.instance;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    // Unique hall per run — the test DB persists across runs and sheet ids
    // are stable hashes.
    final hall = 'SS${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final roll = 'BSSE-T${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'v': 1,
        'type': 'hall_seating_stats',
        'action': 'open_hall_attendance',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'students': 27,
        'groups': [
          ['BSCS 2A', 'EXPOSITORY WRITING', 'MS. A', 9],
          ['BSCS 7A', 'WIRELESS NETWORK SECURITY', 'MR. B', 9],
          ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. A', 9],
        ],
      }),
    );
    expect(stats.hallName, hall);
    expect(stats.totalStudents, 27);
    expect(stats.presentStudents, 0);
    expect(stats.absentStudents, 27);

    // The class breakdown comes through for the colour-coded skeleton: three
    // classes, each with its program label and seat count.
    expect(stats.classGroups, hasLength(3));
    expect(stats.classGroups[0].program, 'BSCS 2A');
    expect(stats.classGroups[0].count, 9);
    expect(stats.classGroups[2].program, 'BSSE 2A');
    expect(stats.classGroups.map((g) => g.count).reduce((a, b) => a + b), 27);
    // Program code drives the per-class colour (BSCS vs BSSE).
    expect(stats.classGroups[0].code, 'BSCS');
    expect(stats.classGroups[2].code, 'BSSE');

    // Students join live as their seat QRs are scanned.
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: roll,
      status: 'present',
      colNo: 2,
      chairNo: 5,
      seatLabel: 'Hall $hall | Col 2 | Chair 5',
    );
    final after = await database.loadExamHallStats(stats.sheetId);
    expect(after.totalStudents, 27);
    expect(after.presentStudents, 1);
    expect(after.absentStudents, 26);
    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students, hasLength(1));
    expect(students.first.hasSeat, isTrue);
  });

  test('hall scan works from a real seating-plan QR (invigilator flow)',
      () async {
    final repository = AppRepository();
    // Deliberately use a teacher who does NOT teach MATHEMATICS-II — the
    // invigilator case that used to fail with "Hall data not found".
    final teacher = repository.teachers.first;
    final database = TeacherDashboardDatabase.instance;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    // Actual payload format produced by the csexam seating-plan app and
    // present in assets/qr_seed.json.
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload:
          'CSEXAM|QPATT|1|3720AFB713BB6D8A50A5152A|29-May-26|1st|G10|BSCS-F25-259|4|7',
    );

    expect(stats.hallName, 'G10');
    expect(stats.totalStudents, greaterThan(0));

    // Students carry their real seats for the live skeleton.
    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students, isNotEmpty);
    expect(students.any((s) => s.hasSeat), isTrue);
    expect(
      students.any((s) => s.rollNo.toUpperCase() == 'BSCS-F25-259'),
      isTrue,
    );

    // Share payload contains full details: present/absent lists + UFM.
    final first = students.first;
    await database.markAttendanceStatus(
      sheetId: stats.sheetId,
      studentId: first.studentId,
      status: 'present',
    );
    await database.addUfmCase(
      sheetId: stats.sheetId,
      studentId: first.studentId,
      allegation: 'Cheating material',
      details: 'Slip found',
    );
    final payload = await database.shareAttendanceSheet(
      teacherId: teacher.id,
      sheetId: stats.sheetId,
      sharedWith: 'Admin',
    );
    // Counts accumulate across reruns (the test DB persists), so assert the
    // sections + content rather than exact counts.
    expect(payload, contains('PRESENT ('));
    expect(payload, contains('ABSENT ('));
    expect(payload, contains('UFM CASES ('));
    expect(payload, contains(first.rollNo));
    expect(payload, contains('Cheating material'));
  });

  test(
      'full-detail HALL ATTENDANCE QR (v2): hall opens pre-seeded with every '
      'seat, name and class', () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final suffix = DateTime.now().millisecondsSinceEpoch % 1000000;
    final hall = 'V2H$suffix';
    final payload = buildCsexamHallQrV2({
      't': 'hall_seating_stats',
      'd': '30-Jun-26',
      's': '2nd',
      'h': hall,
      'n': 5,
      'g': [
        ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 3],
        ['BSCS 7A', 'WIRELESS NETWORK SECURITY', 'SYEDA KINZA NAQVI', 2],
      ],
      'm': [
        // Same "BSCS" prefix on both classes — the group index (not the roll
        // prefix) must drive the class attribution.
        ['BSCS-F25-101', 1, 1, 0],
        ['BSCS-F25-102', 1, 2, 0],
        ['CS-251101', 1, 3, 0],
        ['BSCS-F22-301', 2, 1, 1],
        ['BSCS-F22-302', 2, 2, 1],
      ],
    });

    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: payload,
    );
    expect(stats.hallName, hall);
    expect(stats.totalStudents, 5);
    expect(stats.presentStudents, 0);
    expect(stats.classGroups, hasLength(2));
    expect(stats.classGroups[0].program, 'BSCS 2A');
    expect(stats.classGroups[1].program, 'BSCS 7A');

    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students, hasLength(5));
    // Everyone has a real seat — the live screen draws the exact skeleton.
    expect(students.every((s) => s.hasSeat), isTrue);
    // Class attribution comes from the seat map's group index.
    final senior = students.firstWhere((s) => s.rollNo == 'BSCS-F22-301');
    expect(senior.classGroup, 'BSCS 7A');
    final junior = students.firstWhere((s) => s.rollNo == 'CS-251101');
    expect(junior.classGroup, 'BSCS 2A');
    expect(junior.colNo, 1);
    expect(junior.chairNo, 3);
    // All seeded absent until scanned.
    expect(students.every((s) => s.status == 'absent'), isTrue);
  });

  test('hall QR with no total count still opens (sized from class counts)',
      () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final hall = 'NT${DateTime.now().millisecondsSinceEpoch % 1000000}';
    // Note: no top-level "students" field at all — must fall back to the sum
    // of the per-class counts instead of throwing "Hall data not found".
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'type': 'hall_seating_stats',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'groups': [
          ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 58],
          ['BSCS 7A', 'WIRELESS NETWORK SECURITY', 'MS. KINZA', 2],
          ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. IQRA', 48],
        ],
      }),
    );
    expect(stats.hallName, hall);
    expect(stats.totalStudents, 108);
    expect(stats.classGroups, hasLength(3));
  });

  test('per-class attendance: a scan is attributed to the chosen class',
      () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final hall = 'PC${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'type': 'hall_seating_stats',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'students': 4,
        'groups': [
          ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 2],
          ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. IQRA MAHEEN', 2],
        ],
      }),
    );
    expect(stats.classGroups, hasLength(2));

    // Take "BSCS 2A" attendance: the scan is tagged with that class.
    final roll = 'BSCS-PC${DateTime.now().millisecondsSinceEpoch % 100000}';
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: roll,
      status: 'present',
      classGroup: 'BSCS 2A',
    );
    final students = await database.loadAttendanceStudents(stats.sheetId);
    final added = students.firstWhere((s) => s.rollNo == roll);
    expect(added.classGroup, 'BSCS 2A');
    expect(added.status, 'present');
  });

  test('a wrongly-scanned student can be deleted from the sheet', () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final hall = 'DEL${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'type': 'hall_seating_stats',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'students': 10,
        'groups': [
          ['BSSE 4B', 'INFORMATION SECURITY', 'MR. X', 10],
        ],
      }),
    );
    final roll = 'WRONG-${DateTime.now().millisecondsSinceEpoch % 100000}';
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: roll,
      status: 'present',
      classGroup: 'BSSE 4B',
    );
    var students = await database.loadAttendanceStudents(stats.sheetId);
    final added = students.firstWhere((s) => s.rollNo == roll);
    expect(added.status, 'present');

    // Delete the mistaken scan → it disappears from the sheet entirely.
    await database.removeAttendanceRecord(
      sheetId: stats.sheetId,
      studentId: added.studentId,
    );
    students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students.any((s) => s.rollNo == roll), isFalse);
    final after = await database.loadExamHallStats(stats.sheetId);
    expect(after.presentStudents, 0);
  });

  test('share is programwise + hallwise, and accept round-trips the QR',
      () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final hall = 'SH${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'type': 'hall_seating_stats',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'students': 4,
        'groups': [
          ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 2],
          ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. IQRA MAHEEN', 2],
        ],
      }),
    );

    final bscsRoll = 'BSCS-SH${DateTime.now().millisecondsSinceEpoch % 100000}';
    final bsseRoll = 'BSSE-SH${DateTime.now().millisecondsSinceEpoch % 100000}';
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: bscsRoll,
      status: 'present',
      classGroup: 'BSCS 2A',
    );
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: bsseRoll,
      status: 'present',
      classGroup: 'BSSE 2A',
    );

    // Programwise: only BSCS 2A's student appears.
    final classShare = await database.loadAttendanceShare(
      sheetId: stats.sheetId,
      classGroup: 'BSCS 2A',
    );
    expect(classShare.classGroup, 'BSCS 2A');
    expect(classShare.present, 1);
    expect(classShare.total, 2);
    expect(classShare.text, contains(bscsRoll));
    expect(classShare.text, isNot(contains(bsseRoll)));
    expect(classShare.qrPayload, startsWith('CSEXAM|QATTN|1|'));

    // Hallwise: both students appear.
    final hallShare = await database.loadAttendanceShare(
      sheetId: stats.sheetId,
    );
    expect(hallShare.classGroup, isEmpty);
    expect(hallShare.present, 2);
    expect(hallShare.text, contains(bscsRoll));
    expect(hallShare.text, contains(bsseRoll));

    // Accept the programwise QR on a "different" device → stored + summarised.
    final accepted = await database.acceptAttendanceQr(
      teacherId: teacher.id,
      rawPayload: classShare.qrPayload,
    );
    expect(accepted.hallName, hall);
    expect(accepted.courseName, 'BSCS 2A');

    // A non-attendance QR is rejected clearly.
    expect(
      () => database.acceptAttendanceQr(
        teacherId: teacher.id,
        rawPayload: 'not a qr',
      ),
      throwsA(isA<FormatException>()),
    );
  });

  test('export JSON carries date/shift/hall/program + students for csexam',
      () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    final hall = 'EX${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final s = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'type': 'hall_seating_stats',
        'date': '30-Jun-26',
        'shift': '2nd',
        'hall': hall,
        'students': 2,
        'groups': [
          ['BSCS 2A', 'EXPOSITORY WRITING', 'MR A', 2],
        ],
      }),
    );
    final roll = 'BSCS-EX${DateTime.now().millisecondsSinceEpoch % 100000}';
    await database.addAttendanceRecord(
      sheetId: s.sheetId, rollNo: roll, status: 'present', classGroup: 'BSCS 2A');

    final json = await database.exportAttendanceJson(
      teacherId: teacher.id, exportedBy: teacher.name);
    final decoded = jsonDecode(json) as Map;
    expect(decoded['type'], 'attendance_export');
    final sessions = (decoded['sessions'] as List).cast<Map>();
    final sess = sessions.firstWhere((e) => e['hall'] == hall);
    expect(sess['shift'], '2nd'); // 2nd shift → 2pm → "2nd"
    expect((sess['date'] as String).contains('Jun'), isTrue);
    expect((sess['present'] as int), greaterThanOrEqualTo(1));
    expect((sess['classes'] as List), isNotEmpty);
    final students = (sess['students'] as List).cast<Map>();
    expect(
      students.any((m) => m['roll'] == roll && m['status'] == 'present'),
      isTrue,
    );
  });

  test('shake-of-hands: accept MERGES halls + present wins (collection team)',
      () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    String qrFor(String hall, String teacherId) => jsonEncode({
      'app': 'CSEXAM',
      'type': 'hall_seating_stats',
      'date': '30-Jun-26',
      'shift': '2nd',
      'hall': hall,
      'students': 3,
      'groups': [
        ['BSCS 2A', 'EXPOSITORY WRITING', 'MR A', 2],
        ['BSSE 2A', 'EXPOSITORY WRITING', 'MS B', 1],
      ],
    });

    final stamp = DateTime.now().millisecondsSinceEpoch % 1000000;
    final hall = 'MH$stamp';
    final rollA = 'BSCS-A$stamp';
    final rollB = 'BSSE-B$stamp';
    final rollC = 'BSCS-C$stamp';

    // Invigilator 1 opens the hall and marks 2 students present (2 programs).
    final s1 = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: qrFor(hall, teacher.id),
    );
    await database.addAttendanceRecord(
      sheetId: s1.sheetId, rollNo: rollA, status: 'present', classGroup: 'BSCS 2A');
    await database.addAttendanceRecord(
      sheetId: s1.sheetId, rollNo: rollB, status: 'present', classGroup: 'BSSE 2A');
    final shareAll = await database.loadAttendanceShare(sheetId: s1.sheetId);
    expect(shareAll.present, 2);

    // Paper-collection team (separate device) accepts → a received hall sheet
    // is created and the 2 present students merge in.
    final collector = 'COLLECT$stamp';
    final accepted = await database.acceptAttendanceQr(
      teacherId: collector, rawPayload: shareAll.qrPayload);
    expect(accepted.hallName, hall);
    var collectorSheets = await database.loadAttendanceSheets(collector);
    final cs = collectorSheets.firstWhere((s) => s.hallName == hall);
    expect(cs.presentCount, 2);

    // A second invigilator's transfer for the SAME hall: rollA ABSENT, rollC
    // present. After merge into the collector: rollA STAYS present (present
    // wins) and rollC is added → 3 present total.
    final t2 = 'T2_$stamp';
    final s2 = await database.fetchExamHallStatsFromQr(
      teacherId: t2, rawPayload: qrFor(hall, t2));
    await database.addAttendanceRecord(
      sheetId: s2.sheetId, rollNo: rollA, status: 'absent', classGroup: 'BSCS 2A');
    await database.addAttendanceRecord(
      sheetId: s2.sheetId, rollNo: rollC, status: 'present', classGroup: 'BSCS 2A');
    final share2 = await database.loadAttendanceShare(sheetId: s2.sheetId);
    await database.acceptAttendanceQr(
      teacherId: collector, rawPayload: share2.qrPayload);

    collectorSheets = await database.loadAttendanceSheets(collector);
    final cs2 = collectorSheets.firstWhere((s) => s.hallName == hall);
    expect(cs2.presentCount, 3); // rollA (kept) + rollB + rollC
  });

  test('lookupSeedStudent resolves a seat token / roll to the student',
      () async {
    final database = TeacherDashboardDatabase.instance;

    // By QR token — the combined live screen uses this to name a student
    // scanned into a dynamic-roster hall (works like the QR attendance scanner).
    final byToken = await database.lookupSeedStudent(
      token: '3720AFB713BB6D8A50A5152A',
    );
    expect(byToken, isNotNull);
    expect(byToken!.rollNo.toUpperCase(), 'BSCS-F25-259');
    expect(byToken.name, isNotEmpty);
    expect(byToken.hall, 'G10');
    expect(byToken.colNo, 4);
    expect(byToken.chairNo, 7);

    // By roll number (e.g. a student ID card QR that renders only the roll).
    final byRoll = await database.lookupSeedStudent(rollNo: 'BSCS-F25-259');
    expect(byRoll, isNotNull);
    expect(byRoll!.name, byToken.name);

    // Unknown rolls resolve to null so the screen can warn the invigilator.
    final miss = await database.lookupSeedStudent(rollNo: 'NOT-A-REAL-ROLL');
    expect(miss, isNull);
  });

  test(
      'combined scan: a real seat token added to a dynamic hall keeps the '
      'seed name + seat', () async {
    final database = TeacherDashboardDatabase.instance;
    final repository = AppRepository();
    final teacher = repository.teachers.first;
    await database.loadTeacherHome(
      teacherId: teacher.id,
      teacherName: teacher.name,
    );

    // Open a fresh dynamic hall (unique name; the test DB persists across runs).
    final hall = 'G10X${DateTime.now().millisecondsSinceEpoch % 1000000}';
    final stats = await database.fetchExamHallStatsFromQr(
      teacherId: teacher.id,
      rawPayload: jsonEncode({
        'app': 'CSEXAM',
        'v': 1,
        'type': 'hall_seating_stats',
        'date': '29-May-26',
        'shift': '1st',
        'hall': hall,
        'students': 3,
        'groups': [
          ['BSCS 2D', 'MATHEMATICS-II', 'MS. ROMANA', 3],
        ],
      }),
    );
    expect(stats.presentStudents, 0);

    // Simulate the live screen resolving a scanned seat token via the seed and
    // adding the student present.
    final seed = await database.lookupSeedStudent(
      token: '3720AFB713BB6D8A50A5152A',
    );
    await database.addAttendanceRecord(
      sheetId: stats.sheetId,
      rollNo: seed!.rollNo,
      studentName: seed.name,
      status: 'present',
      colNo: seed.colNo,
      chairNo: seed.chairNo,
      seatLabel: seed.seatLabel,
    );

    final after = await database.loadExamHallStats(stats.sheetId);
    expect(after.presentStudents, 1);
    final students = await database.loadAttendanceStudents(stats.sheetId);
    final added = students.firstWhere(
      (s) => s.rollNo.toUpperCase() == 'BSCS-F25-259',
    );
    expect(added.studentName, seed.name);
    expect(added.hasSeat, isTrue);
    expect(added.status, 'present');
  });

  test('live attendance: incremental present + UFM cases round-trip', () async {
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
        'hallId': 'AUST-UFM-H1',
        'hallName': 'Hall UFM',
        'courseId': course.id,
        'courseName': course.courseName,
        'examDateTime': '2026-06-12T09:00:00',
        'totalExpectedStudents': course.totalStudents,
      }),
    );

    final students = await database.loadAttendanceStudents(stats.sheetId);
    expect(students, isNotEmpty);
    final first = students.first;

    // Incremental scan-save: one student marked present immediately.
    await database.markAttendanceStatus(
      sheetId: stats.sheetId,
      studentId: first.studentId,
      status: 'present',
    );
    final afterScan = await database.loadExamHallStats(stats.sheetId);
    expect(afterScan.presentStudents, 1);

    // UFM: add one case, read it back with student info, then remove it.
    await database.addUfmCase(
      sheetId: stats.sheetId,
      studentId: first.studentId,
      allegation: 'Mobile phone',
      details: 'Phone found in pocket',
    );
    var cases = await database.loadUfmCases(stats.sheetId);
    expect(cases, hasLength(1));
    expect(cases.first.rollNo, first.rollNo);
    expect(cases.first.allegation, 'Mobile phone');
    expect(cases.first.details, 'Phone found in pocket');

    await database.deleteUfmCase(cases.first.id);
    cases = await database.loadUfmCases(stats.sheetId);
    expect(cases, isEmpty);
  });
}
