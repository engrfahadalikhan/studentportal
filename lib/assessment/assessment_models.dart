enum AssessmentType { quiz, assignment, examPaper }

extension AssessmentTypeX on AssessmentType {
  String get label {
    switch (this) {
      case AssessmentType.quiz:
        return 'Quiz';
      case AssessmentType.assignment:
        return 'Assignment';
      case AssessmentType.examPaper:
        return 'Exam Paper';
    }
  }
}

enum QuestionType { mcq, trueFalse, shortAnswer, longAnswer, fileUpload }

extension QuestionTypeX on QuestionType {
  String get label {
    switch (this) {
      case QuestionType.mcq:
        return 'MCQ';
      case QuestionType.trueFalse:
        return 'True/False';
      case QuestionType.shortAnswer:
        return 'Short Answer';
      case QuestionType.longAnswer:
        return 'Long Answer';
      case QuestionType.fileUpload:
        return 'File Upload';
    }
  }
}

enum AssessmentStatus { draft, active, completed }

extension AssessmentStatusX on AssessmentStatus {
  String get label {
    switch (this) {
      case AssessmentStatus.draft:
        return 'Draft';
      case AssessmentStatus.active:
        return 'Active';
      case AssessmentStatus.completed:
        return 'Completed';
    }
  }
}

enum AttemptStatus {
  notStarted,
  inProgress,
  submitted,
  flagged,
  autoLocked,
  quit,
}

extension AttemptStatusX on AttemptStatus {
  String get label {
    switch (this) {
      case AttemptStatus.notStarted:
        return 'Not Started';
      case AttemptStatus.inProgress:
        return 'In Progress';
      case AttemptStatus.submitted:
        return 'Submitted';
      case AttemptStatus.flagged:
        return 'Flagged';
      case AttemptStatus.autoLocked:
        return 'Auto Locked';
      case AttemptStatus.quit:
        return 'Quit';
    }
  }
}

class AssessmentCourse {
  const AssessmentCourse({
    required this.id,
    required this.courseName,
    required this.courseCode,
    required this.credits,
    required this.semester,
    required this.section,
    required this.enrolledStudents,
    required this.program,
    required this.session,
    required this.instructor,
  });

  final String id;
  final String courseName;
  final String courseCode;
  final int credits;
  final String semester;
  final String section;
  final int enrolledStudents;
  final String program;
  final String session;
  final String instructor;
}

class AssessmentTeacher {
  const AssessmentTeacher({
    required this.id,
    required this.name,
    required this.email,
    required this.password,
    required this.courseIds,
  });

  final String id;
  final String name;
  final String email;
  final String password;
  final List<String> courseIds;
}

class AssessmentStudent {
  const AssessmentStudent({
    required this.id,
    required this.name,
    required this.studentId,
    required this.program,
    required this.session,
    required this.semester,
    required this.section,
    required this.email,
  });

  final String id;
  final String name;
  final String studentId;
  final String program;
  final String session;
  final String semester;
  final String section;
  final String email;
}

class AssessmentSettings {
  const AssessmentSettings({
    required this.randomizeQuestions,
    required this.randomizeOptions,
    required this.oneAttemptOnly,
    required this.autoSubmit,
    required this.showResultAfterSubmission,
    required this.manualGrading,
  });

  final bool randomizeQuestions;
  final bool randomizeOptions;
  final bool oneAttemptOnly;
  final bool autoSubmit;
  final bool showResultAfterSubmission;
  final bool manualGrading;

  Map<String, Object?> toJson() => {
    'randomizeQuestions': randomizeQuestions,
    'randomizeOptions': randomizeOptions,
    'oneAttemptOnly': oneAttemptOnly,
    'autoSubmit': autoSubmit,
    'showResultAfterSubmission': showResultAfterSubmission,
    'manualGrading': manualGrading,
  };

  static AssessmentSettings fromJson(Map<String, Object?> j) {
    bool b(String k) => j[k] == true;
    return AssessmentSettings(
      randomizeQuestions: b('randomizeQuestions'),
      randomizeOptions: b('randomizeOptions'),
      oneAttemptOnly: b('oneAttemptOnly'),
      autoSubmit: b('autoSubmit'),
      showResultAfterSubmission: b('showResultAfterSubmission'),
      manualGrading: b('manualGrading'),
    );
  }
}

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.marks,
    this.options = const [],
    this.correctAnswer,
    this.optionMarks = const {},
    this.timeMinutes = 0,
  });

  final String id;
  final QuestionType type;
  final String question;
  final int marks;
  final List<String> options;
  final String? correctAnswer;

  /// Per-option partial credit set by the teacher at scan time: option text →
  /// marks. When non-empty the student earns the marks of the option they
  /// picked (0 if blank). NEVER put in the student QR — it is the answer key.
  final Map<String, int> optionMarks;
  final int timeMinutes;

  AssessmentQuestion copyWith({
    String? correctAnswer,
    int? marks,
    Map<String, int>? optionMarks,
  }) {
    return AssessmentQuestion(
      id: id,
      type: type,
      question: question,
      marks: marks ?? this.marks,
      options: options,
      correctAnswer: correctAnswer ?? this.correctAnswer,
      optionMarks: optionMarks ?? this.optionMarks,
      timeMinutes: timeMinutes,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'type': type.index,
    'question': question,
    'marks': marks,
    'options': options,
    'correctAnswer': correctAnswer,
    'optionMarks': optionMarks,
    'timeMinutes': timeMinutes,
  };

  static AssessmentQuestion fromJson(Map<String, Object?> j) {
    final ti = (j['type'] as num?)?.toInt() ?? 0;
    return AssessmentQuestion(
      id: (j['id'] ?? '').toString(),
      type: (ti >= 0 && ti < QuestionType.values.length)
          ? QuestionType.values[ti]
          : QuestionType.mcq,
      question: (j['question'] ?? '').toString(),
      marks: (j['marks'] as num?)?.toInt() ?? 0,
      options: [
        for (final o in (j['options'] as List?) ?? const []) o.toString(),
      ],
      correctAnswer: j['correctAnswer']?.toString(),
      optionMarks: {
        for (final e in ((j['optionMarks'] as Map?) ?? const {}).entries)
          e.key.toString(): (e.value as num?)?.toInt() ?? 0,
      },
      timeMinutes: (j['timeMinutes'] as num?)?.toInt() ?? 0,
    );
  }
}

class Assessment {
  const Assessment({
    required this.id,
    required this.title,
    required this.type,
    required this.courseId,
    required this.program,
    required this.semester,
    required this.section,
    required this.durationMinutes,
    required this.totalMarks,
    required this.startTime,
    required this.endTime,
    required this.instructions,
    required this.questions,
    required this.settings,
    required this.status,
    required this.qrCode,
    this.expectedStudents = 0,
  });

  final String id;
  final String title;
  final AssessmentType type;
  final String courseId;
  final String program;
  final String semester;
  final String section;
  final int durationMinutes;
  final int totalMarks;
  final DateTime startTime;
  final DateTime endTime;
  final String instructions;
  final List<AssessmentQuestion> questions;
  final AssessmentSettings settings;
  final AssessmentStatus status;
  final String qrCode;

  /// Total students expected to attempt this paper (sum of the selected
  /// courses' enrolment) — used for the teacher's submitted/absent stats.
  /// Teacher-side only; never travels in the student QR.
  final int expectedStudents;

  Assessment copyWith({
    String? id,
    String? title,
    AssessmentType? type,
    String? courseId,
    String? program,
    String? semester,
    String? section,
    int? durationMinutes,
    int? totalMarks,
    DateTime? startTime,
    DateTime? endTime,
    String? instructions,
    List<AssessmentQuestion>? questions,
    AssessmentSettings? settings,
    AssessmentStatus? status,
    String? qrCode,
    int? expectedStudents,
  }) {
    return Assessment(
      id: id ?? this.id,
      title: title ?? this.title,
      type: type ?? this.type,
      courseId: courseId ?? this.courseId,
      program: program ?? this.program,
      semester: semester ?? this.semester,
      section: section ?? this.section,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      totalMarks: totalMarks ?? this.totalMarks,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      instructions: instructions ?? this.instructions,
      questions: questions ?? this.questions,
      settings: settings ?? this.settings,
      status: status ?? this.status,
      qrCode: qrCode ?? this.qrCode,
      expectedStudents: expectedStudents ?? this.expectedStudents,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'type': type.index,
    'courseId': courseId,
    'program': program,
    'semester': semester,
    'section': section,
    'durationMinutes': durationMinutes,
    'totalMarks': totalMarks,
    'startTime': startTime.toIso8601String(),
    'endTime': endTime.toIso8601String(),
    'instructions': instructions,
    'questions': [for (final q in questions) q.toJson()],
    'settings': settings.toJson(),
    'status': status.index,
    'qrCode': qrCode,
    'expectedStudents': expectedStudents,
  };

  static Assessment fromJson(Map<String, Object?> j) {
    final ti = (j['type'] as num?)?.toInt() ?? 0;
    final si = (j['status'] as num?)?.toInt() ?? 0;
    DateTime dt(Object? v) =>
        DateTime.tryParse(v?.toString() ?? '') ?? DateTime.now();
    return Assessment(
      id: (j['id'] ?? '').toString(),
      title: (j['title'] ?? '').toString(),
      type: (ti >= 0 && ti < AssessmentType.values.length)
          ? AssessmentType.values[ti]
          : AssessmentType.quiz,
      courseId: (j['courseId'] ?? '').toString(),
      program: (j['program'] ?? '').toString(),
      semester: (j['semester'] ?? '').toString(),
      section: (j['section'] ?? '').toString(),
      durationMinutes: (j['durationMinutes'] as num?)?.toInt() ?? 0,
      totalMarks: (j['totalMarks'] as num?)?.toInt() ?? 0,
      startTime: dt(j['startTime']),
      endTime: dt(j['endTime']),
      instructions: (j['instructions'] ?? '').toString(),
      questions: [
        for (final q in (j['questions'] as List?) ?? const [])
          if (q is Map) AssessmentQuestion.fromJson(q.cast<String, Object?>()),
      ],
      settings: j['settings'] is Map
          ? AssessmentSettings.fromJson(
              (j['settings'] as Map).cast<String, Object?>(),
            )
          : const AssessmentSettings(
              randomizeQuestions: true,
              randomizeOptions: true,
              oneAttemptOnly: true,
              autoSubmit: true,
              showResultAfterSubmission: false,
              manualGrading: false,
            ),
      status: (si >= 0 && si < AssessmentStatus.values.length)
          ? AssessmentStatus.values[si]
          : AssessmentStatus.draft,
      qrCode: (j['qrCode'] ?? '').toString(),
      expectedStudents: (j['expectedStudents'] as num?)?.toInt() ?? 0,
    );
  }
}

class AssessmentSubmission {
  const AssessmentSubmission({
    required this.id,
    required this.assessmentId,
    required this.studentId,
    required this.status,
    required this.answers,
    required this.warningCount,
    required this.flags,
    required this.progress,
    this.assessmentTitle = '',
    this.studentName = '',
    this.studentProgram = '',
    this.studentSemester = '',
    this.studentSection = '',
    this.startedAt,
    this.submittedAt,
    this.marks,
    this.lastActivity,
  });

  final String id;
  final String assessmentId;

  /// Snapshot of the assessment title at submit time — kept locally so the
  /// student's "My submissions" history can show a readable name (and re-share
  /// the QR) even after the original paper is gone. Never sent in the QR.
  final String assessmentTitle;
  final String studentId;

  /// Student identity carried WITH the submission (and its QR) so the teacher
  /// can build class-wise marks lists (BSCS 2A …) without a separate roster.
  final String studentName;
  final String studentProgram;
  final String studentSemester;
  final String studentSection;
  final AttemptStatus status;
  final DateTime? startedAt;
  final DateTime? submittedAt;
  final Map<String, String> answers;
  final int? marks;
  final int warningCount;
  final List<String> flags;
  final int progress;
  final DateTime? lastActivity;

  AssessmentSubmission copyWith({
    String? id,
    String? assessmentId,
    String? assessmentTitle,
    String? studentId,
    String? studentName,
    String? studentProgram,
    String? studentSemester,
    String? studentSection,
    AttemptStatus? status,
    DateTime? startedAt,
    DateTime? submittedAt,
    Map<String, String>? answers,
    int? marks,
    int? warningCount,
    List<String>? flags,
    int? progress,
    DateTime? lastActivity,
  }) {
    return AssessmentSubmission(
      id: id ?? this.id,
      assessmentId: assessmentId ?? this.assessmentId,
      assessmentTitle: assessmentTitle ?? this.assessmentTitle,
      studentId: studentId ?? this.studentId,
      studentName: studentName ?? this.studentName,
      studentProgram: studentProgram ?? this.studentProgram,
      studentSemester: studentSemester ?? this.studentSemester,
      studentSection: studentSection ?? this.studentSection,
      status: status ?? this.status,
      startedAt: startedAt ?? this.startedAt,
      submittedAt: submittedAt ?? this.submittedAt,
      answers: answers ?? this.answers,
      marks: marks ?? this.marks,
      warningCount: warningCount ?? this.warningCount,
      flags: flags ?? this.flags,
      progress: progress ?? this.progress,
      lastActivity: lastActivity ?? this.lastActivity,
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'assessmentId': assessmentId,
    'assessmentTitle': assessmentTitle,
    'studentId': studentId,
    'studentName': studentName,
    'studentProgram': studentProgram,
    'studentSemester': studentSemester,
    'studentSection': studentSection,
    'status': status.index,
    'startedAt': startedAt?.toIso8601String(),
    'submittedAt': submittedAt?.toIso8601String(),
    'answers': answers,
    'marks': marks,
    'warningCount': warningCount,
    'flags': flags,
    'progress': progress,
    'lastActivity': lastActivity?.toIso8601String(),
  };

  static AssessmentSubmission fromJson(Map<String, Object?> json) {
    final statusIndex = (json['status'] as num?)?.toInt() ?? 0;
    DateTime? parse(Object? v) =>
        v == null ? null : DateTime.tryParse(v.toString());
    return AssessmentSubmission(
      id: (json['id'] ?? '').toString(),
      assessmentId: (json['assessmentId'] ?? '').toString(),
      assessmentTitle: (json['assessmentTitle'] ?? '').toString(),
      studentId: (json['studentId'] ?? '').toString(),
      studentName: (json['studentName'] ?? '').toString(),
      studentProgram: (json['studentProgram'] ?? '').toString(),
      studentSemester: (json['studentSemester'] ?? '').toString(),
      studentSection: (json['studentSection'] ?? '').toString(),
      status:
          (statusIndex >= 0 && statusIndex < AttemptStatus.values.length)
          ? AttemptStatus.values[statusIndex]
          : AttemptStatus.submitted,
      startedAt: parse(json['startedAt']),
      submittedAt: parse(json['submittedAt']),
      answers: {
        for (final e in ((json['answers'] as Map?) ?? const {}).entries)
          e.key.toString(): e.value.toString(),
      },
      marks: (json['marks'] as num?)?.toInt(),
      warningCount: (json['warningCount'] as num?)?.toInt() ?? 0,
      flags: [
        for (final f in (json['flags'] as List?) ?? const []) f.toString(),
      ],
      progress: (json['progress'] as num?)?.toInt() ?? 0,
      lastActivity: parse(json['lastActivity']),
    );
  }
}

class VerificationRequest {
  const VerificationRequest({
    required this.id,
    required this.student,
    required this.assessmentId,
    required this.requestedAt,
    required this.status,
  });

  final String id;
  final AssessmentStudent student;
  final String assessmentId;
  final DateTime requestedAt;
  final VerificationStatus status;

  VerificationRequest copyWith({VerificationStatus? status}) {
    return VerificationRequest(
      id: id,
      student: student,
      assessmentId: assessmentId,
      requestedAt: requestedAt,
      status: status ?? this.status,
    );
  }
}

enum VerificationStatus { pending, approved, rejected }

extension VerificationStatusX on VerificationStatus {
  String get label {
    switch (this) {
      case VerificationStatus.pending:
        return 'Pending';
      case VerificationStatus.approved:
        return 'Approved';
      case VerificationStatus.rejected:
        return 'Rejected';
    }
  }
}
