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
}

class AssessmentQuestion {
  const AssessmentQuestion({
    required this.id,
    required this.type,
    required this.question,
    required this.marks,
    this.options = const [],
    this.correctAnswer,
    this.timeMinutes = 0,
  });

  final String id;
  final QuestionType type;
  final String question;
  final int marks;
  final List<String> options;
  final String? correctAnswer;
  final int timeMinutes;
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
    this.startedAt,
    this.submittedAt,
    this.marks,
    this.lastActivity,
  });

  final String id;
  final String assessmentId;
  final String studentId;
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
    String? studentId,
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
      studentId: studentId ?? this.studentId,
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
