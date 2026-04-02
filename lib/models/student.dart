class Student {
  final String name;
  final String rollNo;
  final String program;
  final int programCode;
  final String section;
  final String email;
  final String phone;
  final double cgpa;
  final int semester;

  Student({
    required this.name,
    required this.rollNo,
    required this.program,
    required this.programCode,
    required this.section,
    required this.email,
    required this.phone,
    required this.cgpa,
    required this.semester,
  });
}

class Course {
  final String id;
  final String code;
  final String title;
  final String instructor;
  final int credits;
  final int attendance;
  final String syllabus;

  Course({
    required this.id,
    required this.code,
    required this.title,
    required this.instructor,
    required this.credits,
    required this.attendance,
    required this.syllabus,
  });
}

class ExamSchedule {
  final int id;
  final String courseCode;
  final String courseTitle;
  final String date;
  final String time;
  final String hall;
  final String seatNo;
  final String type;

  ExamSchedule({
    required this.id,
    required this.courseCode,
    required this.courseTitle,
    required this.date,
    required this.time,
    required this.hall,
    required this.seatNo,
    required this.type,
  });
}

enum RequestStatus { pending, approved, rejected }

class Request {
  final String id;
  final String type;
  final String title;
  final String date;
  final RequestStatus status;
  final String description;

  Request({
    required this.id,
    required this.type,
    required this.title,
    required this.date,
    required this.status,
    required this.description,
  });
}

class RequestType {
  final String id;
  final String label;
  final String description;

  RequestType({
    required this.id,
    required this.label,
    required this.description,
  });
}
