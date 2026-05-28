class SeatingPlanEntry {
  const SeatingPlanEntry({
    required this.rollNo,
    required this.examDate,
    required this.shift,
    required this.chairNo,
    required this.column,
    required this.studentName,
    required this.program,
    required this.subject,
    required this.faculty,
  });

  final String rollNo;
  final String examDate;
  final String shift;
  final String chairNo;
  final String column;
  final String studentName;
  final String program;
  final String subject;
  final String faculty;

  factory SeatingPlanEntry.fromMap(Map<String, dynamic> map) {
    return SeatingPlanEntry(
      rollNo: _value(map, const ['RollNo', 'rollNo', 'Roll no']),
      examDate: _value(map, const ['ExamDate', 'exam_date']),
      shift: _value(map, const ['Shift', 'shift']),
      chairNo: _value(map, const ['ChairNo', 'chair_no']),
      column: _value(map, const ['Column', 'column']),
      studentName: _value(map, const ['StudentName', 'student_name']),
      program: _value(map, const ['Program', 'program']),
      subject: _value(map, const ['Subject', 'subject']),
      faculty: _value(map, const ['Faculty', 'faculty']),
    );
  }

  static String _value(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
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
