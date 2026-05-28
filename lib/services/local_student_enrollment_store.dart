import '../data/local_student_enrollments.dart';
import '../models/student_directory_summary.dart';
import '../models/student_record.dart';

class LocalStudentEnrollmentStore {
  Future<StudentRecord?> findStudentByRollNo(String rollNo) async {
    final normalizedRollNo = rollNo.trim();
    final rows = _rowsForRollNo(normalizedRollNo);
    if (rows.isEmpty) {
      return null;
    }
    return StudentRecord.fromRows(rows);
  }

  Future<StudentDirectorySummary> loadSummary() async {
    final uniqueRolls = <String>{};
    for (final row in localStudentEnrollmentRows) {
      final rollNo = row[_rollNoIndex].trim();
      if (rollNo.isNotEmpty) {
        uniqueRolls.add(rollNo);
      }
    }

    return StudentDirectorySummary(
      studentCount: uniqueRolls.length,
      courseRegistrationCount: localStudentEnrollmentRows.length,
      matchedPath: 'local students enrollment.xls',
    );
  }

  Future<List<StudentRecord>> searchStudents(
    String query, {
    int limit = 25,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    final groupedRows = <String, List<Map<String, dynamic>>>{};
    for (final row in localStudentEnrollmentRows) {
      final rollNo = row[_rollNoIndex].trim();
      if (groupedRows.length >= limit && !groupedRows.containsKey(rollNo)) {
        break;
      }

      final name = row[_studentNameIndex].trim();
      final matchesRoll = rollNo.toLowerCase() == normalizedQuery;
      final matchesName = name.toLowerCase().contains(normalizedQuery);

      if (!matchesRoll && !matchesName) {
        continue;
      }

      groupedRows
          .putIfAbsent(rollNo, () => <Map<String, dynamic>>[])
          .add(_toStudentRow(row));
    }

    return groupedRows.values
        .take(limit)
        .map(StudentRecord.fromRows)
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _rowsForRollNo(String rollNo) {
    return localStudentEnrollmentRows
        .where((row) => row[_rollNoIndex].trim() == rollNo)
        .map(_toStudentRow)
        .toList(growable: false);
  }

  Map<String, dynamic> _toStudentRow(List<String> row) {
    return <String, dynamic>{
      'Roll no': row[_rollNoIndex],
      'Student_name': row[_studentNameIndex],
      'program': row[_programIndex],
      'semester': row[_semesterIndex],
      'section': row[_sectionIndex],
      'session_enrolled': row[_sessionEnrolledIndex],
      'Session': row[_sessionIndex],
      'CC': row[_courseCodeIndex],
      'Course_name': row[_courseNameIndex],
      'Instructor': row[_instructorIndex],
      'Cr_Hrs': row[_creditsIndex],
    };
  }

  static const int _rollNoIndex = 0;
  static const int _studentNameIndex = 1;
  static const int _programIndex = 2;
  static const int _semesterIndex = 3;
  static const int _sectionIndex = 4;
  static const int _sessionEnrolledIndex = 5;
  static const int _sessionIndex = 6;
  static const int _courseCodeIndex = 7;
  static const int _courseNameIndex = 8;
  static const int _instructorIndex = 9;
  static const int _creditsIndex = 10;
}
