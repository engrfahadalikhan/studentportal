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

  double get attendancePercentage {
    if (totalStudents == 0) {
      return 0;
    }
    return (presentStudents / totalStudents) * 100;
  }
}

class ExamAttendanceStudent {
  const ExamAttendanceStudent({
    required this.studentId,
    required this.studentName,
    required this.rollNo,
    required this.status,
  });

  final String studentId;
  final String studentName;
  final String rollNo;
  final String status;

  ExamAttendanceStudent copyWith({String? status}) {
    return ExamAttendanceStudent(
      studentId: studentId,
      studentName: studentName,
      rollNo: rollNo,
      status: status ?? this.status,
    );
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

class SharedAttendanceSheetSummary {
  const SharedAttendanceSheetSummary({
    required this.id,
    required this.courseName,
    required this.hallName,
    required this.examDateTime,
    required this.sharedWith,
    required this.sharedAt,
    required this.status,
  });

  final String id;
  final String courseName;
  final String hallName;
  final DateTime examDateTime;
  final String sharedWith;
  final DateTime sharedAt;
  final String status;
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
