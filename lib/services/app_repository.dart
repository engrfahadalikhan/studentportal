import 'dart:math';

import 'package:flutter/foundation.dart';

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
import 'local_student_enrollment_store.dart';
import 'seating_plan_service.dart';
import 'student_directory_service.dart';

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

    if (role == AppRole.admin) {
      if (normalizedUsername.toLowerCase() != 'admin' ||
          normalizedPassword != '1234') {
        throw const PortalAuthException('Admin username or password is wrong.');
      }
      _currentSession = PortalSession.admin();
      notifyListeners();
      return;
    }

    if (role == AppRole.faculty) {
      final teacher = teacherByEmail(normalizedUsername);
      if (teacher == null) {
        throw const PortalAuthException('Select a valid teacher first.');
      }

      final storedPassword = _teacherPasswords[teacher.email.toLowerCase()];
      if (storedPassword != null &&
          normalizedPassword.isNotEmpty &&
          storedPassword != normalizedPassword) {
        throw const PortalAuthException('Teacher password is wrong.');
      }

      _ensureTeacherSeedAssessments(teacher);
      _currentSession = PortalSession.teacher(teacher);
      notifyListeners();
      return;
    }

    if (normalizedPassword.isEmpty) {
      throw const PortalAuthException('Enter password first.');
    }

    if (normalizedPassword != '1234') {
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

  List<AssessmentStudent> studentsForAssessment(Assessment assessment) {
    return _assessmentStudents
        .where(
          (student) =>
              student.program == assessment.program &&
              student.session == 'S26' &&
              student.semester == assessment.semester &&
              student.section == assessment.section,
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
  }) {
    final id = 'A${(_assessments.length + 1).toString().padLeft(3, '0')}';
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
      semester: course.semester,
      section: course.section,
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
    );

    _assessments.insert(0, assessment);
    notifyListeners();
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
        .where(
          (submission) => submission.studentId.toLowerCase() == normalized,
        )
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
      studentId: student.id,
      status: status,
      startedAt: existingIndex == -1
          ? DateTime.now()
          : _submissions[existingIndex].startedAt,
      submittedAt: DateTime.now(),
      answers: answers,
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
