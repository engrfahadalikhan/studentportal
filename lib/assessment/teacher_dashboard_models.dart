enum TeacherAssessmentKind {
  quiz('quiz', 'Quiz'),
  assignment('assignment', 'Assignment'),
  others('others', 'Others');

  const TeacherAssessmentKind(this.key, this.label);

  final String key;
  final String label;

  static TeacherAssessmentKind fromKey(String value) {
    return TeacherAssessmentKind.values.firstWhere(
      (kind) => kind.key == value,
      orElse: () => TeacherAssessmentKind.others,
    );
  }
}

class TeacherDashboardHomeData {
  const TeacherDashboardHomeData({
    required this.teacherId,
    required this.teacherName,
    required this.courses,
    this.unreadNotifications = 0,
    this.attendanceSheets = 0,
    this.sharedAttendanceSheets = 0,
    this.acceptedAttendanceSheets = 0,
  });

  final String teacherId;
  final String teacherName;
  final List<TeacherCourseSummary> courses;
  final int unreadNotifications;
  final int attendanceSheets;
  final int sharedAttendanceSheets;
  final int acceptedAttendanceSheets;

  int get totalCourses => courses.length;
  int get totalStudents =>
      courses.fold(0, (sum, course) => sum + course.totalStudents);
  int get totalAssessments =>
      courses.fold(0, (sum, course) => sum + course.totalAssessments);

  TeacherCourseSummary? courseById(String id) {
    for (final course in courses) {
      if (course.id == id) {
        return course;
      }
    }
    return null;
  }
}

class TeacherCourseSummary {
  const TeacherCourseSummary({
    required this.id,
    required this.teacherId,
    required this.courseName,
    required this.courseCode,
    required this.totalStudents,
    required this.totalAssessments,
    required this.program,
    required this.semester,
    required this.section,
  });

  final String id;
  final String teacherId;
  final String courseName;
  final String courseCode;
  final int totalStudents;
  final int totalAssessments;
  final String program;
  final String semester;
  final String section;
}

class TeacherCourseDetailData {
  const TeacherCourseDetailData({
    required this.course,
    required this.assessments,
  });

  final TeacherCourseSummary course;
  final List<CourseAssessmentSummary> assessments;
}

class CourseAssessmentSummary {
  const CourseAssessmentSummary({
    required this.id,
    required this.courseId,
    required this.title,
    required this.type,
    required this.totalMarks,
    required this.dueDate,
    required this.instructions,
    required this.submittedCount,
    required this.notSubmittedCount,
  });

  final String id;
  final String courseId;
  final String title;
  final TeacherAssessmentKind type;
  final int totalMarks;
  final DateTime dueDate;
  final String instructions;
  final int submittedCount;
  final int notSubmittedCount;
}

class AssessmentDetailData {
  const AssessmentDetailData({
    required this.course,
    required this.assessment,
    required this.submittedStudents,
    required this.notSubmittedStudents,
  });

  final TeacherCourseSummary course;
  final CourseAssessmentSummary assessment;
  final List<StudentSubmissionSummary> submittedStudents;
  final List<StudentSubmissionSummary> notSubmittedStudents;
}

class StudentSubmissionSummary {
  const StudentSubmissionSummary({
    required this.studentId,
    required this.studentName,
    required this.rollNo,
    required this.status,
    this.marks,
  });

  final String studentId;
  final String studentName;
  final String rollNo;
  final String status;
  final int? marks;
}

class NewTeacherAssessmentInput {
  const NewTeacherAssessmentInput({
    required this.courseId,
    required this.title,
    required this.type,
    required this.totalMarks,
    required this.dueDate,
    required this.instructions,
  });

  final String courseId;
  final String title;
  final TeacherAssessmentKind type;
  final int totalMarks;
  final DateTime dueDate;
  final String instructions;
}

enum TeacherNotificationCategory {
  courses('courses', 'Courses'),
  assessments('assessments', 'Assessments'),
  examAttendance('exam_attendance', 'Exam attendance'),
  sharedAttendance('shared_attendance', 'Shared attendance'),
  acceptedAttendance('accepted_attendance', 'Accepted attendance');

  const TeacherNotificationCategory(this.key, this.label);

  final String key;
  final String label;

  static TeacherNotificationCategory fromKey(String value) {
    return TeacherNotificationCategory.values.firstWhere(
      (category) => category.key == value,
      orElse: () => TeacherNotificationCategory.courses,
    );
  }
}

class TeacherNotification {
  const TeacherNotification({
    required this.id,
    required this.teacherId,
    required this.category,
    required this.title,
    required this.message,
    required this.createdAt,
    required this.isRead,
  });

  final String id;
  final String teacherId;
  final TeacherNotificationCategory category;
  final String title;
  final String message;
  final DateTime createdAt;
  final bool isRead;
}

class ExamAttendanceDashboardData {
  const ExamAttendanceDashboardData({
    required this.totalSheets,
    required this.sharedSheets,
    required this.acceptedSheets,
  });

  final int totalSheets;
  final int sharedSheets;
  final int acceptedSheets;
}

/// One class/section sharing an exam hall (from the seating-plan HALL QR's
/// `groups`). The live skeleton draws a colour-coded block of [count] seats
/// per group so two classes in the same hall are visually distinct.
class ExamClassGroup {
  const ExamClassGroup({
    required this.program,
    required this.subject,
    required this.faculty,
    required this.count,
  });

  final String program;
  final String subject;
  final String faculty;
  final int count;

  /// The leading program code of the roll/program (e.g. "BSCS" from
  /// "BSCS 2A"), used to colour a scanned student by their class.
  String get code {
    final match = RegExp(r'^[A-Za-z]+').firstMatch(program.trim());
    return (match?.group(0) ?? program.trim()).toUpperCase();
  }
}

class ExamHallStats {
  const ExamHallStats({
    required this.sheetId,
    required this.hallId,
    required this.hallName,
    required this.courseId,
    required this.courseName,
    required this.examDateTime,
    required this.totalStudents,
    required this.presentStudents,
    required this.absentStudents,
    required this.status,
    required this.seatInfo,
    this.classGroups = const [],
  });

  final String sheetId;
  final String hallId;
  final String hallName;
  final String courseId;
  final String courseName;
  final DateTime examDateTime;
  final int totalStudents;
  final int presentStudents;
  final int absentStudents;
  final String status;
  final String seatInfo;

  /// The classes/sections sharing this hall (for the colour-coded skeleton).
  /// Empty for halls opened from a single seat token (no group breakdown).
  final List<ExamClassGroup> classGroups;

  double get attendancePercentage {
    if (totalStudents == 0) {
      return 0;
    }
    return (presentStudents / totalStudents) * 100;
  }

  ExamHallStats copyWith({
    int? totalStudents,
    int? presentStudents,
    int? absentStudents,
    List<ExamClassGroup>? classGroups,
  }) {
    return ExamHallStats(
      sheetId: sheetId,
      hallId: hallId,
      hallName: hallName,
      courseId: courseId,
      courseName: courseName,
      examDateTime: examDateTime,
      totalStudents: totalStudents ?? this.totalStudents,
      presentStudents: presentStudents ?? this.presentStudents,
      absentStudents: absentStudents ?? this.absentStudents,
      status: status,
      seatInfo: seatInfo,
      classGroups: classGroups ?? this.classGroups,
    );
  }
}

class ExamAttendanceStudent {
  const ExamAttendanceStudent({
    required this.studentId,
    required this.studentName,
    required this.rollNo,
    required this.status,
    this.seatLabel = '',
    this.colNo = 0,
    this.chairNo = 0,
    this.classGroup = '',
    this.flag = '',
  });

  final String studentId;
  final String studentName;
  final String rollNo;
  final String status;

  /// Extra note on a PRESENT student: '' (none), 'qr_problem' (the printed QR
  /// wouldn't scan, marked present by hand) or 'paper_not_returned' (present
  /// but did not hand back the question paper).
  final String flag;

  /// Real seat from the seating plan (e.g. "Hall G10 | Col 4 | Chair 7").
  /// Empty when the sheet was built from course enrollment instead of a
  /// seating-plan QR.
  final String seatLabel;
  final int colNo;
  final int chairNo;

  /// The class/section this student was marked under (e.g. "BSCS 2A"), set when
  /// attendance is taken one class at a time. Empty for whole-hall sheets.
  final String classGroup;

  bool get hasSeat => colNo > 0 && chairNo > 0;

  ExamAttendanceStudent copyWith({String? status, String? flag}) {
    return ExamAttendanceStudent(
      studentId: studentId,
      studentName: studentName,
      rollNo: rollNo,
      status: status ?? this.status,
      seatLabel: seatLabel,
      colNo: colNo,
      chairNo: chairNo,
      classGroup: classGroup,
      flag: flag ?? this.flag,
    );
  }

  /// Short human label for the flag (empty when none).
  String get flagLabel {
    switch (flag) {
      case 'qr_problem':
        return 'QR problem';
      case 'paper_not_returned':
        return 'Paper not returned';
      default:
        return '';
    }
  }
}

class ExamAttendanceSheetSummary {
  const ExamAttendanceSheetSummary({
    required this.sheetId,
    required this.courseName,
    required this.hallName,
    required this.examDateTime,
    required this.totalStudents,
    required this.presentCount,
    required this.absentCount,
    required this.lastUpdatedAt,
    required this.status,
  });

  final String sheetId;
  final String courseName;
  final String hallName;
  final DateTime examDateTime;
  final int totalStudents;
  final int presentCount;
  final int absentCount;
  final DateTime lastUpdatedAt;
  final String status;

  double get attendancePercentage {
    if (totalStudents == 0) {
      return 0;
    }
    return (presentCount / totalStudents) * 100;
  }
}

class ExamAttendanceSheetDetail {
  const ExamAttendanceSheetDetail({
    required this.stats,
    required this.students,
  });

  final ExamHallStats stats;
  final List<ExamAttendanceStudent> students;
}

/// A ready-to-share attendance summary for one scope (whole hall or a single
/// class). Carries both the human-readable [text] and the scannable [qrPayload]
/// (`CSEXAM|QATTN|1|...`) so it can be sent by text or by QR.
class AttendanceShareData {
  const AttendanceShareData({
    required this.scopeLabel,
    required this.classGroup,
    required this.text,
    required this.qrPayload,
    required this.total,
    required this.present,
    required this.absent,
  });

  /// Human label of the scope, e.g. "Whole hall (SS1)" or "BSCS 2A".
  final String scopeLabel;

  /// The class program this share is limited to, or empty for the whole hall.
  final String classGroup;

  final String text;
  final String qrPayload;
  final int total;
  final int present;
  final int absent;
}

/// Allegation options offered when recording a UFM (Unfair Means) case.
/// 'Other' asks for free-text details.
const List<String> ufmAllegationOptions = [
  'Mobile phone',
  'Cheating material',
  'Talking / signals',
  'Impersonation',
  'Other',
];

/// One recorded Unfair-Means case against a student in an exam sheet.
/// Cases are entered one at a time from the live attendance screen.
class UfmCase {
  const UfmCase({
    required this.id,
    required this.sheetId,
    required this.studentId,
    required this.studentName,
    required this.rollNo,
    required this.allegation,
    required this.details,
    required this.createdAt,
  });

  final String id;
  final String sheetId;
  final String studentId;
  final String studentName;
  final String rollNo;
  final String allegation;
  final String details;
  final DateTime createdAt;
}

class SharedAttendanceSheetSummary {
  const SharedAttendanceSheetSummary({
    required this.id,
    required this.courseName,
    required this.hallName,
    required this.examDateTime,
    required this.sharedWith,
    required this.sharedAt,
    required this.status,
    this.payload = '',
  });

  final String id;
  final String courseName;
  final String hallName;
  final DateTime examDateTime;
  final String sharedWith;
  final DateTime sharedAt;
  final String status;

  /// Full shared text: present/absent rolls, seats and UFM cases.
  final String payload;
}

class AcceptedAttendanceSheetSummary {
  const AcceptedAttendanceSheetSummary({
    required this.id,
    required this.courseName,
    required this.hallName,
    required this.examDateTime,
    required this.receivedFrom,
    required this.acceptedAt,
    required this.status,
  });

  final String id;
  final String courseName;
  final String hallName;
  final DateTime examDateTime;
  final String receivedFrom;
  final DateTime acceptedAt;
  final String status;
}

class AttendanceSharingData {
  const AttendanceSharingData({
    required this.sharedSheets,
    required this.acceptedSheets,
  });

  final List<SharedAttendanceSheetSummary> sharedSheets;
  final List<AcceptedAttendanceSheetSummary> acceptedSheets;
}

/// One attendance record flattened for the end-of-exam summary (slot / program
/// / hall drill-down). Sourced from every sheet the teacher holds — their own
/// scans plus everything accepted/merged from other invigilators.
class AttendanceSummaryRow {
  const AttendanceSummaryRow({
    required this.dateTime,
    required this.hall,
    required this.program,
    required this.status,
    required this.flag,
    required this.rollNo,
    required this.studentName,
    this.collectedBy = '',
  });

  final DateTime dateTime;
  final String hall;
  final String program;
  final String status; // 'present' | 'absent'
  final String flag; // '' | 'qr_problem' | 'paper_not_returned'
  final String rollNo;
  final String studentName;

  /// Name of the teacher/invigilator who scanned this student.
  final String collectedBy;

  bool get isPresent => status == 'present';

  /// Slot label: 1st shift (morning) vs 2nd shift (afternoon).
  String get shift => dateTime.hour >= 12 ? '2nd' : '1st';
}

/// One unfair-means case, with enough context for a teacher-wide UFM report.
class UfmSummaryRow {
  const UfmSummaryRow({
    required this.dateTime,
    required this.hall,
    required this.program,
    required this.rollNo,
    required this.studentName,
    required this.allegation,
    required this.details,
    this.collectedBy = '',
  });

  final DateTime dateTime;
  final String hall;
  final String program;
  final String rollNo;
  final String studentName;
  final String allegation;
  final String details;

  /// Name of the invigilator who recorded this UFM case.
  final String collectedBy;

  String get shift => dateTime.hour >= 12 ? '2nd' : '1st';
}

/// Result of importing an `attendance_export` file from another phone.
class AttendanceImportSummary {
  const AttendanceImportSummary({
    required this.sessions,
    required this.present,
    required this.absent,
    required this.ufm,
  });

  final int sessions;
  final int present;
  final int absent;
  final int ufm;
}
