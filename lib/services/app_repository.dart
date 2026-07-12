import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../assessment/assessment_mock_data.dart' as mock;
import '../assessment/assessment_models.dart';
import '../assessment/registration_course_data.dart' as registration;
import '../models/app_role.dart';
import '../models/portal_session.dart';
import '../models/seating_plan_entry.dart';
import '../models/student_directory_summary.dart';
import '../models/student_record.dart';
import '../models/verification_officer.dart';
import '../ui/shared_widgets.dart';
import 'cloud_sync_service.dart';
import 'device_binding_service.dart';
import 'local_student_enrollment_store.dart';
import 'login_store.dart';
import 'seating_plan_service.dart';
import 'student_directory_service.dart';
import 'teacher_dashboard_database.dart';

class AppRepository extends ChangeNotifier {
  AppRepository({
    bool useFirebase = false,
    LocalStudentEnrollmentStore? localStudentStore,
    StudentDirectoryService? studentDirectory,
    SeatingPlanService? seatingPlanService,
  }) : _useFirebase = useFirebase,
       _localStudentStore = localStudentStore ?? LocalStudentEnrollmentStore(),
       _studentDirectory = useFirebase
           ? studentDirectory ?? StudentDirectoryService()
           : studentDirectory,
       _seatingPlanService = useFirebase
           ? seatingPlanService ?? SeatingPlanService()
           : seatingPlanService {
    _bootstrapDemoWorkspace();
  }

  final bool _useFirebase;
  final LocalStudentEnrollmentStore _localStudentStore;
  final StudentDirectoryService? _studentDirectory;
  final SeatingPlanService? _seatingPlanService;

  final List<AssessmentTeacher> _teachers = List.of(
    registration.registrationTeachers,
  );
  final List<AssessmentCourse> _assessmentCourses = List.of(
    registration.registrationCourses,
  );
  final List<AssessmentStudent> _assessmentStudents = List.of(
    mock.assessmentStudents,
  );
  final List<Assessment> _assessments = List.of(mock.mockAssessments);
  final List<AssessmentSubmission> _submissions = List.of(mock.mockSubmissions);
  final List<VerificationRequest> _verificationRequests = [];
  final List<VerificationOfficer> _verificationOfficers = [
    const VerificationOfficer(
      id: 'VO001',
      name: 'Class Representative',
      rollNo: 'CR-001',
      accessLevel: 'Student verification',
    ),
  ];
  final Map<String, String> _teacherPasswords = {};
  final Map<String, String> _teacherSetupCodes = {};
  final Random _random = Random.secure();

  PortalSession? _currentSession;

  PortalSession? get currentSession => _currentSession;
  List<AssessmentTeacher> get teachers => List.unmodifiable(_teachers);
  List<AssessmentCourse> get assessmentCourses =>
      List.unmodifiable(_assessmentCourses);
  List<AssessmentStudent> get assessmentStudents =>
      List.unmodifiable(_assessmentStudents);
  List<Assessment> get assessments => List.unmodifiable(_assessments);
  List<AssessmentSubmission> get submissions => List.unmodifiable(_submissions);

  // Teacher-given assignments and student-completed submissions are stored in
  // TWO SEPARATE database tables (`teacher_assignments`, `student_submissions`)
  // owned by [TeacherDashboardDatabase]. These keys are only read once to
  // migrate any data left over from the earlier SharedPreferences store.
  static const String _kSubmissionsKey = 'student_submissions_v1';
  static const String _kAssessmentsKey = 'teacher_assessments_v1';

  final TeacherDashboardDatabase _dataDb = TeacherDashboardDatabase.instance;

  /// Restores student submissions from the `student_submissions` table (one-time
  /// migration from the legacy prefs store). UPSERTs onto the seeded list.
  Future<void> loadPersistedSubmissions() async {
    try {
      var rows = await _dataDb.loadStudentSubmissions();
      if (rows.isEmpty) {
        rows = await _migrateLegacyList(_kSubmissionsKey);
      }
      for (final j in rows) {
        final s = AssessmentSubmission.fromJson(j);
        if (s.id.isEmpty) continue;
        final i = _submissions.indexWhere(
          (e) => e.assessmentId == s.assessmentId && e.studentId == s.studentId,
        );
        if (i == -1) {
          _submissions.add(s);
        } else {
          _submissions[i] = s;
        }
      }
      notifyListeners();
      unawaited(_persistSubmissions()); // seed the table after a migration
    } catch (_) {
      // Corrupt/absent store — keep the seeded list, never crash startup.
    }
  }

  Future<void> _persistSubmissions() async {
    try {
      await _dataDb.saveStudentSubmissions([
        for (final s in _submissions) s.toJson(),
      ]);
    } catch (_) {
      // Best-effort; an unsaved submission is still re-sharable this session.
    }
  }

  /// Restores teacher-created assignments from the `teacher_assignments` table
  /// (one-time migration from the legacy prefs store). UPSERTs by id.
  Future<void> loadPersistedAssessments() async {
    try {
      var rows = await _dataDb.loadTeacherAssignments();
      if (rows.isEmpty) {
        rows = await _migrateLegacyList(_kAssessmentsKey);
      }
      for (final j in rows) {
        final a = Assessment.fromJson(j);
        if (a.id.isEmpty) continue;
        final i = _assessments.indexWhere((e) => e.id == a.id);
        if (i == -1) {
          _assessments.insert(0, a);
        } else {
          _assessments[i] = a;
        }
      }
      notifyListeners();
      unawaited(_persistAssessments()); // seed the table after a migration
    } catch (_) {
      // Corrupt/absent store — keep the seeded list, never crash startup.
    }
  }

  Future<void> _persistAssessments() async {
    try {
      await _dataDb.saveTeacherAssignments([
        for (final a in _assessments) a.toJson(),
      ]);
    } catch (_) {
      // Best-effort.
    }
  }

  /// Reads (and clears) a legacy SharedPreferences JSON-list store for one-time
  /// migration into the database tables.
  Future<List<Map<String, Object?>>> _migrateLegacyList(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      if (raw == null || raw.isEmpty) return const [];
      final decoded = jsonDecode(raw);
      await prefs.remove(key);
      if (decoded is! List) return const [];
      return [
        for (final e in decoded)
          if (e is Map) e.cast<String, Object?>(),
      ];
    } catch (_) {
      return const [];
    }
  }

  List<VerificationRequest> get verificationRequests =>
      List.unmodifiable(_verificationRequests);
  List<VerificationOfficer> get verificationOfficers =>
      List.unmodifiable(_verificationOfficers);

  bool isTeacherAccountReady(String teacherEmail) {
    return _teacherPasswords.containsKey(teacherEmail.toLowerCase());
  }

  String? teacherSetupCode(String teacherEmail) {
    return _teacherSetupCodes[teacherEmail.toLowerCase()];
  }

  String generateTeacherSetupCode(String teacherEmail) {
    final teacher = teacherByEmail(teacherEmail);
    if (teacher == null) {
      throw const PortalAuthException('Select a valid teacher first.');
    }

    final code =
        '${_random.nextInt(900000) + 100000}-${teacher.id.substring(1)}';
    _teacherSetupCodes[teacher.email.toLowerCase()] = code;
    notifyListeners();
    return code;
  }

  Future<void> createTeacherPassword({
    required String teacherEmail,
    required String setupCode,
    required String password,
  }) async {
    final teacher = teacherByEmail(teacherEmail);
    if (teacher == null) {
      throw const PortalAuthException('Select a valid teacher first.');
    }

    final normalizedEmail = teacher.email.toLowerCase();
    final expectedCode = _teacherSetupCodes[normalizedEmail];
    if (expectedCode == null) {
      throw const PortalAuthException('Generate the teacher QR code first.');
    }
    if (setupCode.trim() != expectedCode) {
      throw const PortalAuthException('Teacher setup QR code is not valid.');
    }
    if (password.trim().length < 4) {
      throw const PortalAuthException(
        'Create a password with at least 4 characters.',
      );
    }

    _teacherPasswords[normalizedEmail] = password.trim();
    _teacherSetupCodes.remove(normalizedEmail);
    notifyListeners();
  }

  Future<void> signIn({
    required AppRole role,
    required String username,
    required String password,
  }) async {
    final normalizedUsername = username.trim();
    final normalizedPassword = password.trim();

    if (normalizedUsername.isEmpty) {
      throw const PortalAuthException('Enter username first.');
    }

    // Pull ONLY this person's cloud password before validating (1-2 doc
    // reads, not the whole collection) — so a password changed on another
    // phone immediately invalidates the default here. FYP itself is pulled
    // only when the FYP screen opens, to protect the free Firebase quota.
    await CloudSyncService.instance.bootstrapLoginData(
      credentialKeys: [
        if (role == AppRole.student)
          'student:${normalizedUsername.toLowerCase()}',
        if (role == AppRole.faculty) ...[
          'teacher:${normalizedUsername.toLowerCase()}',
          'teacher:custom:${normalizedUsername.toLowerCase()}',
        ],
      ],
      includeFypWorkspace: false,
    );

    if (role == AppRole.admin) {
      final expected =
          LoginStore.instance.passwordOverride('admin') ?? 'pdfpakistan123#';
      if (normalizedUsername.toLowerCase() != 'admin' ||
          normalizedPassword != expected) {
        throw const PortalAuthException('Admin username or password is wrong.');
      }
      _currentSession = PortalSession.admin();
      notifyListeners();
      return;
    }

    // Admin-blessed OPEN device ("Allowed for ALL"): leaving the password
    // EMPTY signs into any teacher/student account without their password.
    // Only the admin can turn that switch on, so the device itself is the
    // authorization. A typed (non-empty) password is still validated normally.
    final adminOpenDevice =
        DeviceBindingService.instance.allowAll && normalizedPassword.isEmpty;

    if (role == AppRole.faculty) {
      if (normalizedPassword.isEmpty && !adminOpenDevice) {
        throw const PortalAuthException('Enter the teacher password.');
      }

      // Custom "Other" teacher (added from the login screen)?
      final custom = LoginStore.instance.customTeacherByName(
        normalizedUsername,
      );
      if (custom != null) {
        final key = 'teacher:custom:${custom.name.toLowerCase()}';
        final expected =
            LoginStore.instance.passwordOverride(key) ?? custom.password;
        if (!adminOpenDevice && normalizedPassword != expected) {
          throw const PortalAuthException('Teacher password is wrong.');
        }
        _currentSession = PortalSession.teacher(
          AssessmentTeacher(
            id: 'custom:${custom.name.toLowerCase()}',
            name: custom.name,
            email: custom.name,
            password: expected,
            courseIds: const [],
          ),
        );
        notifyListeners();
        return;
      }

      final teacher = teacherByEmail(normalizedUsername);
      if (teacher == null) {
        throw const PortalAuthException('Select a valid teacher first.');
      }
      // Shared default "aust12345", unless the teacher changed it.
      final expected =
          LoginStore.instance.passwordOverride(
            'teacher:${teacher.email.toLowerCase()}',
          ) ??
          'aust12345';
      if (!adminOpenDevice && normalizedPassword != expected) {
        throw const PortalAuthException('Teacher password is wrong.');
      }

      _ensureTeacherSeedAssessments(teacher);
      _currentSession = PortalSession.teacher(teacher);
      notifyListeners();
      return;
    }

    if (normalizedPassword.isEmpty && !adminOpenDevice) {
      throw const PortalAuthException('Enter password first.');
    }

    final studentExpected =
        LoginStore.instance.passwordOverride(
          'student:${normalizedUsername.toLowerCase()}',
        ) ??
        '1234';
    if (!adminOpenDevice && normalizedPassword != studentExpected) {
      throw const PortalAuthException('Password is incorrect.');
    }

    final student = _useFirebase
        ? await _studentDirectory!.findStudentByRollNo(normalizedUsername)
        : await _localStudentStore.findStudentByRollNo(normalizedUsername);
    if (student == null) {
      throw const PortalAuthException(
        'Roll number was not found in the local enrollment data.',
      );
    }

    _currentSession = PortalSession.student(student);
    notifyListeners();
  }

  void signOut() {
    _currentSession = null;
    notifyListeners();
  }

  Future<StudentDirectorySummary> loadAdminSummary() {
    return _useFirebase
        ? _studentDirectory!.loadSummary()
        : _localStudentStore.loadSummary();
  }

  Future<List<SeatingPlanEntry>> loadSeatingPlan(String rollNo) {
    return _useFirebase
        ? _seatingPlanService!.findByRollNo(rollNo)
        : Future.value(const <SeatingPlanEntry>[]);
  }

  Future<List<StudentRecord>> searchStudents(String query) {
    return _useFirebase
        ? _studentDirectory!.searchStudents(query)
        : _localStudentStore.searchStudents(query);
  }

  Future<List<StudentRecord>> classmatesFor(StudentRecord student) {
    return _useFirebase
        ? _studentDirectory!.classmatesFor(student)
        : _localStudentStore.classmatesFor(student);
  }

  void grantVerificationAccess({
    required String name,
    required String rollNo,
    String accessLevel = 'Student verification',
  }) {
    final cleanName = name.trim();
    final cleanRollNo = rollNo.trim();
    if (cleanName.isEmpty || cleanRollNo.isEmpty) {
      throw const PortalAuthException('Enter name and roll number first.');
    }
    final existingIndex = _verificationOfficers.indexWhere(
      (officer) => officer.rollNo.toLowerCase() == cleanRollNo.toLowerCase(),
    );
    final officer = VerificationOfficer(
      id: existingIndex == -1
          ? 'VO${(_verificationOfficers.length + 1).toString().padLeft(3, '0')}'
          : _verificationOfficers[existingIndex].id,
      name: cleanName,
      rollNo: cleanRollNo,
      accessLevel: accessLevel,
    );
    if (existingIndex == -1) {
      _verificationOfficers.add(officer);
    } else {
      _verificationOfficers[existingIndex] = officer;
    }
    notifyListeners();
  }

  void revokeVerificationAccess(String officerId) {
    _verificationOfficers.removeWhere((officer) => officer.id == officerId);
    notifyListeners();
  }

  List<AssessmentCourse> coursesForTeacher(AssessmentTeacher teacher) {
    final allowed = teacher.courseIds.toSet();
    return _assessmentCourses
        .where((course) => allowed.contains(course.id))
        .toList(growable: false);
  }

  List<Assessment> assessmentsForTeacher(AssessmentTeacher teacher) {
    final allowed = teacher.courseIds.toSet();
    return _assessments
        .where((assessment) => allowed.contains(assessment.courseId))
        .toList(growable: false);
  }

  void ensureTeacherWorkspace(AssessmentTeacher teacher) {
    _ensureTeacherSeedAssessments(teacher);
  }

  void _bootstrapDemoWorkspace() {
    for (final assessment in List<Assessment>.of(_assessments)) {
      _seedSubmissionsForAssessment(assessment);
    }

    for (final teacher in _teachers.take(8)) {
      _ensureTeacherSeedAssessments(teacher);
    }

    _seedVerificationRequests();
  }

  void _ensureTeacherSeedAssessments(AssessmentTeacher teacher) {
    final allowedCourseIds = teacher.courseIds.toSet();
    final hasTeacherAssessment = _assessments.any(
      (assessment) => allowedCourseIds.contains(assessment.courseId),
    );
    if (hasTeacherAssessment) {
      return;
    }

    final teacherCourses = coursesForTeacher(teacher).take(3).toList();
    if (teacherCourses.isEmpty) {
      return;
    }

    final generated = <Assessment>[];
    for (var index = 0; index < teacherCourses.length; index++) {
      final course = teacherCourses[index];
      final id =
          'A${(_assessments.length + index + 1).toString().padLeft(3, '0')}';
      final type = switch (index) {
        0 => AssessmentType.quiz,
        1 => AssessmentType.assignment,
        _ => AssessmentType.examPaper,
      };
      final status = switch (index) {
        0 => AssessmentStatus.active,
        1 => AssessmentStatus.draft,
        _ => AssessmentStatus.completed,
      };
      final duration = switch (type) {
        AssessmentType.quiz => 30,
        AssessmentType.assignment => 60,
        AssessmentType.examPaper => 90,
      };
      final questions = _seedQuestionsForCourse(course, type);
      final totalMarks = questions.fold<int>(
        0,
        (sum, question) => sum + question.marks,
      );
      final startTime = DateTime.now().add(Duration(minutes: 10 + index * 30));

      generated.add(
        Assessment(
          id: id,
          title: '${course.courseName} - ${type.label}',
          type: type,
          courseId: course.id,
          program: course.program,
          semester: course.semester,
          section: course.section,
          durationMinutes: duration,
          totalMarks: totalMarks,
          startTime: startTime,
          endTime: startTime.add(Duration(minutes: duration)),
          instructions:
              'Attempt all questions. Locked assessment warnings are simulated in the student app for now.',
          questions: questions,
          settings: mock.assessmentSettings,
          status: status,
          qrCode:
              'ASSESS_${id}_${course.courseCode}_${course.session}_${course.semester}${course.section}',
        ),
      );
    }

    _assessments.insertAll(0, generated);
    for (final assessment in generated) {
      _seedSubmissionsForAssessment(assessment);
    }
  }

  void _seedVerificationRequests() {
    if (_verificationRequests.isNotEmpty ||
        _assessmentStudents.isEmpty ||
        _assessments.isEmpty) {
      return;
    }

    final activeAssessment = _assessments.firstWhere(
      (assessment) => assessment.status == AssessmentStatus.active,
      orElse: () => _assessments.first,
    );
    final students = studentsForAssessment(activeAssessment).isEmpty
        ? _assessmentStudents.take(2).toList()
        : studentsForAssessment(activeAssessment).take(2).toList();

    for (var index = 0; index < students.length; index++) {
      _verificationRequests.add(
        VerificationRequest(
          id: 'VR-DEMO-${index + 1}',
          student: students[index],
          assessmentId: activeAssessment.id,
          requestedAt: DateTime.now().subtract(Duration(minutes: 18 - index)),
          status: index == 0
              ? VerificationStatus.pending
              : VerificationStatus.approved,
        ),
      );
    }
  }

  List<AssessmentQuestion> _seedQuestionsForCourse(
    AssessmentCourse course,
    AssessmentType type,
  ) {
    return <AssessmentQuestion>[
      AssessmentQuestion(
        id: 'Q001',
        type: QuestionType.mcq,
        question: 'Which topic best matches ${course.courseName}?',
        options: const ['Core concept', 'Attendance', 'Fee challan', 'Library'],
        correctAnswer: 'Core concept',
        marks: 2,
      ),
      const AssessmentQuestion(
        id: 'Q002',
        type: QuestionType.trueFalse,
        question: 'Students must submit before the timer reaches zero.',
        options: ['True', 'False'],
        correctAnswer: 'True',
        marks: 2,
      ),
      AssessmentQuestion(
        id: 'Q003',
        type: QuestionType.shortAnswer,
        question: 'Write one short note from ${course.courseCode}.',
        marks: type == AssessmentType.quiz ? 4 : 6,
      ),
      AssessmentQuestion(
        id: 'Q004',
        type: QuestionType.longAnswer,
        question:
            'Explain an important ${course.courseName} concept with an example.',
        marks: type == AssessmentType.examPaper ? 12 : 8,
      ),
      if (type == AssessmentType.assignment)
        const AssessmentQuestion(
          id: 'Q005',
          type: QuestionType.fileUpload,
          question: 'Upload placeholder for assignment work.',
          marks: 5,
        ),
    ];
  }

  void _seedSubmissionsForAssessment(Assessment assessment) {
    // Real teacher-created papers (expectedStudents set from enrolment) must
    // NOT get demo submissions — that would corrupt the present/absent stats.
    // Only the bootstrap mock assessments (expectedStudents == 0) are seeded.
    if (assessment.expectedStudents > 0) {
      return;
    }
    if (_submissions.any(
      (submission) => submission.assessmentId == assessment.id,
    )) {
      return;
    }

    final seedStudents = _assessmentStudents.take(3).toList();
    if (seedStudents.isEmpty || assessment.status == AssessmentStatus.draft) {
      return;
    }

    final statuses = assessment.status == AssessmentStatus.completed
        ? const [
            AttemptStatus.submitted,
            AttemptStatus.submitted,
            AttemptStatus.flagged,
          ]
        : const [
            AttemptStatus.inProgress,
            AttemptStatus.submitted,
            AttemptStatus.flagged,
          ];

    for (var index = 0; index < seedStudents.length; index++) {
      final status = statuses[index % statuses.length];
      final warningCount = status == AttemptStatus.flagged ? 2 : index;
      final progress = status == AttemptStatus.submitted
          ? 100
          : status == AttemptStatus.inProgress
          ? 65
          : 45;
      _submissions.add(
        AssessmentSubmission(
          id: 'SUB${(_submissions.length + 1).toString().padLeft(3, '0')}',
          assessmentId: assessment.id,
          studentId: seedStudents[index].id,
          status: status,
          startedAt: DateTime.now().subtract(Duration(minutes: 24 - index * 3)),
          submittedAt: status == AttemptStatus.submitted
              ? DateTime.now().subtract(Duration(minutes: 6 + index))
              : null,
          answers: const {},
          marks: status == AttemptStatus.submitted
              ? assessment.totalMarks - index - 1
              : null,
          warningCount: warningCount,
          flags: status == AttemptStatus.flagged
              ? const ['App switch detected', 'Screenshot attempt']
              : const [],
          progress: progress,
          lastActivity: DateTime.now().subtract(Duration(minutes: index + 1)),
        ),
      );
    }
  }

  List<Assessment> assessmentsForCourse(String courseId) {
    return _assessments
        .where((assessment) => assessment.courseId == courseId)
        .toList(growable: false);
  }

  AssessmentCourse? courseById(String id) {
    return _firstWhereOrNull(_assessmentCourses, (course) => course.id == id);
  }

  AssessmentTeacher? teacherByEmail(String email) {
    final normalized = email.trim().toLowerCase();
    return _firstWhereOrNull(
      _teachers,
      (teacher) => teacher.email.toLowerCase() == normalized,
    );
  }

  Assessment? assessmentById(String id) {
    return _firstWhereOrNull(_assessments, (assessment) => assessment.id == id);
  }

  Assessment? assessmentByCode(String code) {
    final normalized = code.trim().toUpperCase();
    return _firstWhereOrNull(
      _assessments,
      (assessment) => assessment.qrCode.toUpperCase() == normalized,
    );
  }

  /// Inserts a paper received offline (decoded from a scanned QR) into the
  /// in-memory store so the attempt flow, Live, and Results can reference it.
  /// If a paper with the same id already exists it is returned unchanged.
  Assessment importSharedAssessment(Assessment assessment) {
    final existing = assessmentById(assessment.id);
    if (existing != null) {
      return existing;
    }
    _assessments.insert(0, assessment);
    notifyListeners();
    unawaited(_persistAssessments());
    return assessment;
  }

  List<AssessmentStudent> studentsForAssessment(Assessment assessment) {
    // An assessment can target several sections/semesters/programs at once
    // (stored comma-separated, e.g. "A,B,C"). Match a student if they fall in
    // ANY of the assessment's tokens.
    List<String> toks(String s) => s
        .split(',')
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toList();
    final programs = toks(assessment.program);
    final semesters = toks(assessment.semester);
    final sections = toks(assessment.section);
    bool inAny(List<String> tokens, String value) {
      if (tokens.isEmpty) return true;
      final v = value.trim().toLowerCase();
      return tokens.any((t) => v == t || v.contains(t) || t.contains(v));
    }

    return _assessmentStudents
        .where(
          (student) =>
              inAny(programs, student.program) &&
              student.session == 'S26' &&
              inAny(semesters, student.semester) &&
              inAny(sections, student.section),
        )
        .toList(growable: false);
  }

  Assessment createAssessment({
    required String title,
    required AssessmentType type,
    required AssessmentCourse course,
    required int durationMinutes,
    required String instructions,
    required List<AssessmentQuestion> questions,
    String? program,
    String? semester,
    String? section,
    int expectedStudents = 0,
  }) {
    // Unique across app sessions so a freshly created paper never collides
    // with a persisted/seeded id after a restart.
    final id = 'A${DateTime.now().millisecondsSinceEpoch}';
    final totalMarks = questions.fold<int>(
      0,
      (sum, question) => sum + question.marks,
    );
    final startTime = DateTime.now().add(const Duration(minutes: 10));
    final assessment = Assessment(
      id: id,
      title: title,
      type: type,
      courseId: course.id,
      program: program ?? course.program,
      semester: (semester != null && semester.isNotEmpty)
          ? semester
          : course.semester,
      section: (section != null && section.isNotEmpty)
          ? section
          : course.section,
      durationMinutes: durationMinutes,
      totalMarks: totalMarks,
      startTime: startTime,
      endTime: startTime.add(Duration(minutes: durationMinutes)),
      instructions: instructions,
      questions: questions,
      settings: mock.assessmentSettings,
      status: AssessmentStatus.draft,
      qrCode:
          'ASSESS_${id}_${course.id}_${course.session}_${course.semester}${course.section}',
      expectedStudents: expectedStudents,
    );

    _assessments.insert(0, assessment);
    notifyListeners();
    unawaited(_persistAssessments());
    return assessment;
  }

  void publishAssessment(String assessmentId) {
    final index = _assessments.indexWhere(
      (assessment) => assessment.id == assessmentId,
    );
    if (index == -1) {
      return;
    }
    _assessments[index] = _assessments[index].copyWith(
      status: AssessmentStatus.active,
      startTime: DateTime.now(),
      endTime: DateTime.now().add(
        Duration(minutes: _assessments[index].durationMinutes),
      ),
    );
    _seedSubmissionsForAssessment(_assessments[index]);
    notifyListeners();
    unawaited(_persistAssessments());
  }

  /// Permanently removes a teacher-created assessment and all its submissions.
  void deleteAssessment(String assessmentId) {
    // Collect ids BEFORE removal so the deletion can propagate to the cloud
    // (otherwise the synced copy would re-appear on every device).
    final subIds = [
      for (final s in _submissions)
        if (s.assessmentId == assessmentId) s.id,
    ];
    _assessments.removeWhere((a) => a.id == assessmentId);
    _submissions.removeWhere((s) => s.assessmentId == assessmentId);
    notifyListeners();
    unawaited(_persistAssessments());
    unawaited(_persistSubmissions());
    CloudSyncService.instance.pushDeletions([
      ('teacher_assignments', assessmentId),
      for (final id in subIds) ('student_submissions', id),
    ]);
  }

  /// Applies a deletion that arrived from the cloud (tombstone): removes the
  /// row from the in-memory lists WITHOUT pushing a new deletion (no echo).
  void applyCloudRemoval(String table, String id) {
    var changed = false;
    if (table == 'teacher_assignments') {
      final before = _assessments.length;
      _assessments.removeWhere((a) => a.id == id);
      _submissions.removeWhere((s) => s.assessmentId == id);
      changed = _assessments.length != before;
    } else if (table == 'student_submissions') {
      final before = _submissions.length;
      _submissions.removeWhere((s) => s.id == id);
      changed = _submissions.length != before;
    }
    if (changed) {
      notifyListeners();
      unawaited(_persistAssessments());
      unawaited(_persistSubmissions());
    }
  }

  List<AssessmentSubmission> submissionsForAssessment(String assessmentId) {
    return _submissions
        .where((submission) => submission.assessmentId == assessmentId)
        .toList(growable: false);
  }

  /// Submissions tied to a student roll number — used by the Grades module.
  /// Matches against the assessment-student id (which is seeded as the roll
  /// number) so it works for both real and mock submissions.
  List<AssessmentSubmission> submissionsForStudentRoll(String rollNo) {
    final normalized = rollNo.trim().toLowerCase();
    if (normalized.isEmpty) {
      return const [];
    }
    return _submissions
        .where((submission) => submission.studentId.toLowerCase() == normalized)
        .toList(growable: false);
  }

  VerificationRequest? latestVerificationFor({
    required String assessmentId,
    required String studentId,
  }) {
    final matches = _verificationRequests.where(
      (request) =>
          request.assessmentId == assessmentId &&
          request.student.studentId == studentId,
    );
    return matches.isEmpty ? null : matches.last;
  }

  VerificationRequest requestVerification({
    required AssessmentStudent student,
    required String assessmentId,
  }) {
    final request = VerificationRequest(
      id: 'VR-${DateTime.now().millisecondsSinceEpoch}',
      student: student,
      assessmentId: assessmentId,
      requestedAt: DateTime.now(),
      status: VerificationStatus.pending,
    );
    _verificationRequests.add(request);
    notifyListeners();
    return request;
  }

  void updateVerification(String requestId, VerificationStatus status) {
    final index = _verificationRequests.indexWhere(
      (request) => request.id == requestId,
    );
    if (index == -1) {
      return;
    }

    _verificationRequests[index] = _verificationRequests[index].copyWith(
      status: status,
    );
    notifyListeners();
  }

  void submitAssessment({
    required Assessment assessment,
    required AssessmentStudent student,
    required Map<String, String> answers,
    required int warningCount,
    required List<String> flags,
    required AttemptStatus status,
  }) {
    final existingIndex = _submissions.indexWhere(
      (submission) =>
          submission.assessmentId == assessment.id &&
          submission.studentId == student.id,
    );
    final progress = assessment.questions.isEmpty
        ? 0
        : ((answers.length / assessment.questions.length) * 100).round();
    final submission = AssessmentSubmission(
      id: existingIndex == -1
          ? 'SUB${(_submissions.length + 1).toString().padLeft(3, '0')}'
          : _submissions[existingIndex].id,
      assessmentId: assessment.id,
      assessmentTitle: assessment.title,
      studentId: student.id,
      studentName: student.name,
      studentProgram: student.program,
      studentSemester: student.semester,
      studentSection: student.section,
      status: status,
      startedAt: existingIndex == -1
          ? DateTime.now()
          : _submissions[existingIndex].startedAt,
      submittedAt: DateTime.now(),
      answers: answers,
      // Marks are NOT computed here. The student's device has no answer key
      // (the QR is answer-safe), so grading happens at the teacher's end via
      // [objectiveAutoMarks] / [gradeSubmission]. A fresh submission starts
      // ungraded.
      marks: null,
      warningCount: warningCount,
      flags: flags,
      progress: progress,
      lastActivity: DateTime.now(),
    );

    if (existingIndex == -1) {
      _submissions.add(submission);
    } else {
      _submissions[existingIndex] = submission;
    }
    notifyListeners();
    unawaited(_persistSubmissions());
  }

  /// Computes the objective score for [answers] against the answer key in
  /// [authoritative] (the teacher's own copy of the assessment — the only copy
  /// that holds correct answers). Returns the summed marks, or null when the
  /// paper has no auto-gradable questions (e.g. an assignment) — meaning it
  /// needs fully manual grading.
  ///
  /// This runs at the teacher's end (Results / grade sheet), never on the
  /// student device, because the student's scanned copy is answer-free.
  int? objectiveAutoMarks(
    Assessment authoritative,
    Map<String, String> answers,
  ) {
    var hasGradable = false;
    var earned = 0;
    for (final question in authoritative.questions) {
      final given = (answers[question.id] ?? '').trim();
      if (question.optionMarks.isNotEmpty) {
        // Per-option partial credit: the student earns the marks of the option
        // they picked (0 if blank / unrecognised).
        hasGradable = true;
        if (given.isNotEmpty) {
          for (final e in question.optionMarks.entries) {
            if (e.key.trim().toLowerCase() == given.toLowerCase()) {
              earned += e.value;
              break;
            }
          }
        }
      } else {
        final correct = question.correctAnswer?.trim() ?? '';
        if (correct.isEmpty) continue;
        hasGradable = true;
        if (given.isNotEmpty && given.toLowerCase() == correct.toLowerCase()) {
          earned += question.marks;
        }
      }
    }
    return hasGradable ? earned : null;
  }

  /// Imports a submission received via a scanned QR code (offline two-phone
  /// return path). If a submission for the same assessment+student already
  /// exists it is replaced, so rescans are idempotent.
  AssessmentSubmission importSubmission(AssessmentSubmission submission) {
    final authoritative = assessmentById(submission.assessmentId);
    final autoMarks = authoritative == null
        ? null
        : objectiveAutoMarks(authoritative, submission.answers);
    final imported = autoMarks == null
        ? submission
        : submission.copyWith(marks: autoMarks);
    final existing = _submissions.indexWhere(
      (s) =>
          s.assessmentId == imported.assessmentId &&
          s.studentId == imported.studentId,
    );
    if (existing == -1) {
      _submissions.add(imported);
    } else {
      // Keep the id stable so existing grade references survive.
      _submissions[existing] = imported.copyWith(id: _submissions[existing].id);
    }
    notifyListeners();
    unawaited(_persistSubmissions());
    return existing == -1 ? imported : _submissions[existing];
  }

  /// Manually sets the marks for a submission (used to grade assignments and
  /// long-answer questions the teacher reviews by hand).
  void gradeSubmission({
    required String assessmentId,
    required String studentId,
    required int marks,
  }) {
    final index = _submissions.indexWhere(
      (submission) =>
          submission.assessmentId == assessmentId &&
          submission.studentId == studentId,
    );
    if (index == -1) {
      return;
    }
    _submissions[index] = _submissions[index].copyWith(marks: marks);
    notifyListeners();
    unawaited(_persistSubmissions());
  }

  /// Sets the per-option marking scheme for an assessment ON THE TEACHER DEVICE
  /// (never goes into a student QR). [scheme] maps questionId → (option text →
  /// marks). For each scored question the question's total marks become the
  /// highest option mark, the best option is recorded as the correct answer
  /// (for display), and any already-scanned submissions are re-graded.
  void setAssessmentMarkingScheme(
    String assessmentId,
    Map<String, Map<String, int>> scheme,
  ) {
    final i = _assessments.indexWhere((a) => a.id == assessmentId);
    if (i == -1) return;
    final a = _assessments[i];
    final newQuestions = <AssessmentQuestion>[];
    for (final q in a.questions) {
      final om = scheme[q.id];
      if (om == null || om.isEmpty) {
        newQuestions.add(q);
        continue;
      }
      var maxMark = 0;
      String? best;
      om.forEach((opt, mark) {
        if (mark > maxMark) {
          maxMark = mark;
          best = opt;
        }
      });
      newQuestions.add(
        q.copyWith(
          optionMarks: Map<String, int>.from(om),
          marks: maxMark > 0 ? maxMark : q.marks,
          correctAnswer: best ?? q.correctAnswer,
        ),
      );
    }
    final newTotal = newQuestions.fold<int>(0, (s, q) => s + q.marks);
    final updated = a.copyWith(questions: newQuestions, totalMarks: newTotal);
    _assessments[i] = updated;
    // Re-grade everything already collected for this paper.
    for (var j = 0; j < _submissions.length; j++) {
      if (_submissions[j].assessmentId == assessmentId) {
        final m = objectiveAutoMarks(updated, _submissions[j].answers);
        if (m != null) _submissions[j] = _submissions[j].copyWith(marks: m);
      }
    }
    notifyListeners();
    unawaited(_persistAssessments());
    unawaited(_persistSubmissions());
  }

  /// True when an objective (MCQ / true-false) question still has no per-option
  /// marks set — used to prompt the teacher for the marking scheme before
  /// scanning.
  bool assessmentNeedsAnswerKey(String assessmentId) {
    final a = _firstWhereOrNull(_assessments, (e) => e.id == assessmentId);
    if (a == null) return false;
    return a.questions.any(
      (q) =>
          (q.type == QuestionType.mcq || q.type == QuestionType.trueFalse) &&
          q.optionMarks.isEmpty,
    );
  }

  T? _firstWhereOrNull<T>(Iterable<T> values, bool Function(T value) test) {
    for (final value in values) {
      if (test(value)) {
        return value;
      }
    }
    return null;
  }
}
