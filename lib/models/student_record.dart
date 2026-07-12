class StudentCourse {
  const StudentCourse({
    required this.code,
    required this.name,
    required this.instructor,
    required this.session,
  });

  final String code;
  final String name;
  final String instructor;
  final String session;
}

class StudentRecord {
  const StudentRecord({
    required this.rollNo,
    required this.studentName,
    required this.program,
    required this.semester,
    required this.section,
    required this.sessionEnrolled,
    required this.currentSession,
    required this.courses,
  });

  final String rollNo;
  final String studentName;
  final String program;
  final String semester;
  final String section;
  final String sessionEnrolled;
  final String currentSession;
  final List<StudentCourse> courses;

  factory StudentRecord.fromRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) {
      throw ArgumentError('Student rows cannot be empty.');
    }

    final first = rows.first;
    final uniqueCourses = <String, StudentCourse>{};

    // A student can carry retake subjects from LOWER semesters, so the first
    // row's semester can be e.g. 3 while the student is really in 8. Their
    // standing is the HIGHEST semester across all their enrolled rows — this
    // is what decides FYP eligibility (7/8).
    var maxSemester = 0;
    var maxSemesterStr = _stringValue(first, const ['semester', 'Semester']);
    for (final row in rows) {
      final code = _stringValue(row, const ['CC', 'course_code']);
      final semStr = _stringValue(row, const ['semester', 'Semester']);
      final semNum = int.tryParse(semStr);
      if (semNum != null && semNum > maxSemester) {
        maxSemester = semNum;
        maxSemesterStr = semStr;
      }
      if (code.isEmpty) {
        continue;
      }

      uniqueCourses.putIfAbsent(
        code,
        () => StudentCourse(
          code: code,
          name: _stringValue(row, const ['Course_name', 'course_name']),
          instructor: _stringValue(row, const ['Instructor', 'instructor']),
          session: _stringValue(row, const ['Session', 'session']),
        ),
      );
    }

    return StudentRecord(
      rollNo: _stringValue(first, const ['Roll no', 'roll_no', 'rollNo']),
      studentName: _stringValue(first, const [
        'Student_name',
        'student_name',
        'name',
      ]),
      program: _stringValue(first, const ['program', 'Program']),
      semester: maxSemester > 0
          ? maxSemesterStr
          : _stringValue(first, const ['semester', 'Semester']),
      section: _stringValue(first, const ['section', 'Section']),
      sessionEnrolled: _stringValue(first, const [
        'session_enrolled',
        'sessionEnrolled',
      ]),
      currentSession: _stringValue(first, const ['Session', 'session']),
      courses: uniqueCourses.values.toList(),
    );
  }

  static String _stringValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }
}
