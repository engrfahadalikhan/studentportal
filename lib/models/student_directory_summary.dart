class StudentDirectorySummary {
  const StudentDirectorySummary({
    required this.studentCount,
    required this.courseRegistrationCount,
    required this.matchedPath,
  });

  final int studentCount;
  final int courseRegistrationCount;
  final String matchedPath;
}
