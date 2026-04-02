import '../models/student.dart';

class MockData {
  static Student studentInfo = Student(
    name: "Sarah Johnson",
    rollNo: "2021-CS-123",
    program: "BS Computer Science",
    programCode: 6,
    section: "A",
    email: "sarah.johnson@university.edu",
    phone: "+1 (555) 123-4567",
    cgpa: 3.78,
    semester: 6,
  );

  static List<Course> courses = [
    Course(
      id: "CS301",
      code: "CS-301",
      title: "Database Systems",
      instructor: "Dr. Michael Chen",
      credits: 3,
      attendance: 85,
      syllabus: "Introduction to database concepts, ER modeling, SQL, normalization, transactions, and database design.",
    ),
    Course(
      id: "CS302",
      code: "CS-302",
      title: "Software Engineering",
      instructor: "Prof. Emily Roberts",
      credits: 3,
      attendance: 92,
      syllabus: "Software development lifecycle, requirements engineering, design patterns, testing, and project management.",
    ),
    Course(
      id: "CS303",
      code: "CS-303",
      title: "Computer Networks",
      instructor: "Dr. James Wilson",
      credits: 4,
      attendance: 88,
      syllabus: "Network protocols, TCP/IP, routing, switching, network security, and wireless communications.",
    ),
    Course(
      id: "CS304",
      code: "CS-304",
      title: "Operating Systems",
      instructor: "Dr. Lisa Anderson",
      credits: 3,
      attendance: 90,
      syllabus: "Process management, memory management, file systems, synchronization, and deadlock handling.",
    ),
    Course(
      id: "CS305",
      code: "CS-305",
      title: "Web Development",
      instructor: "Prof. David Martinez",
      credits: 3,
      attendance: 95,
      syllabus: "HTML, CSS, JavaScript, React, Node.js, databases, and full-stack development.",
    ),
  ];

  static List<ExamSchedule> examSchedule = [
    ExamSchedule(
      id: 1,
      courseCode: "CS-301",
      courseTitle: "Database Systems",
      date: "2026-04-15",
      time: "09:00 AM - 12:00 PM",
      hall: "Main Hall A",
      seatNo: "A-42",
      type: "Final",
    ),
    ExamSchedule(
      id: 2,
      courseCode: "CS-302",
      courseTitle: "Software Engineering",
      date: "2026-04-18",
      time: "02:00 PM - 05:00 PM",
      hall: "Main Hall B",
      seatNo: "B-28",
      type: "Final",
    ),
    ExamSchedule(
      id: 3,
      courseCode: "CS-303",
      courseTitle: "Computer Networks",
      date: "2026-04-22",
      time: "09:00 AM - 12:00 PM",
      hall: "IT Block Hall 1",
      seatNo: "C-15",
      type: "Final",
    ),
    ExamSchedule(
      id: 4,
      courseCode: "CS-304",
      courseTitle: "Operating Systems",
      date: "2026-04-25",
      time: "02:00 PM - 05:00 PM",
      hall: "Main Hall A",
      seatNo: "A-42",
      type: "Final",
    ),
    ExamSchedule(
      id: 5,
      courseCode: "CS-305",
      courseTitle: "Web Development",
      date: "2026-04-28",
      time: "09:00 AM - 12:00 PM",
      hall: "IT Block Hall 2",
      seatNo: "D-33",
      type: "Final",
    ),
  ];

  static Map<String, int> cases = {
    'ufm': 0,
    'discipline': 0,
  };

  static List<RequestType> requestTypes = [
    RequestType(
      id: 'special-exam',
      label: 'Special Exam Request',
      description: 'Request for special exam due to emergency',
    ),
    RequestType(
      id: 'midterm-exam',
      label: 'Midterm Exam Request',
      description: 'Request for midterm examination',
    ),
    RequestType(
      id: 'final-exam',
      label: 'Final Term Exam Request',
      description: 'Request for final term examination',
    ),
    RequestType(
      id: 'condensed',
      label: 'Condensed Semester Enrollment',
      description: 'Apply for condensed semester',
    ),
  ];

  static List<RequestType> fypRequestTypes = [
    RequestType(
      id: 'fyp-1',
      label: 'Final Year Project I',
      description: 'Register for FYP Phase I',
    ),
    RequestType(
      id: 'fyp-2',
      label: 'Final Year Project II',
      description: 'Register for FYP Phase II',
    ),
    RequestType(
      id: 'fyp-3',
      label: 'Final Year Project III',
      description: 'Register for FYP Phase III',
    ),
  ];

  static List<Request> userRequests = [
    Request(
      id: "REQ001",
      type: "special-exam",
      title: "Special Exam Request - CS301",
      date: "2026-03-15",
      status: RequestStatus.approved,
      description: "Medical emergency - Doctor's note attached",
    ),
    Request(
      id: "REQ002",
      type: "condensed",
      title: "Condensed Semester Enrollment",
      date: "2026-03-20",
      status: RequestStatus.pending,
      description: "Request for summer condensed semester",
    ),
  ];
}
