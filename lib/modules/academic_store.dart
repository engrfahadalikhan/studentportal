import 'package:flutter/foundation.dart';

/// Shared in-memory store for the Tier-1 modules (Time Table, Class Attendance,
/// Course Materials, Announcements). Swap to firebase later by replacing the
/// list-backed implementation with an async data source — the signatures stay
/// the same so the UI doesn't change.
class AcademicStore extends ChangeNotifier {
  AcademicStore._() {
    _seedDemoData();
  }
  static final AcademicStore instance = AcademicStore._();

  // ----- Time table --------------------------------------------------------
  // Map<courseId, List<TimeSlot>>
  final Map<String, List<TimeSlot>> _slotsByCourse = {};

  List<TimeSlot> slotsForCourse(String courseId) =>
      List.unmodifiable(_slotsByCourse[courseId] ?? const []);

  void setSlotsForCourse(String courseId, List<TimeSlot> slots) {
    _slotsByCourse[courseId] = List.of(slots);
    notifyListeners();
  }

  // ----- Class attendance --------------------------------------------------
  // Map<courseId, List<AttendanceRecord>>
  final Map<String, List<AttendanceRecord>> _attendanceByCourse = {};

  List<AttendanceRecord> attendanceForCourse(String courseId) =>
      List.unmodifiable(_attendanceByCourse[courseId] ?? const []);

  List<AttendanceRecord> attendanceForStudent(String rollNo) {
    final normalized = rollNo.trim().toLowerCase();
    final out = <AttendanceRecord>[];
    for (final list in _attendanceByCourse.values) {
      for (final record in list) {
        if (record.rollNo.toLowerCase() == normalized) {
          out.add(record);
        }
      }
    }
    return out;
  }

  void markAttendance({
    required String courseId,
    required String rollNo,
    required DateTime date,
    required bool present,
  }) {
    final list = _attendanceByCourse.putIfAbsent(courseId, () => []);
    final iso = _dateOnly(date);
    final existing = list.indexWhere(
      (r) => r.rollNo == rollNo && _dateOnly(r.date) == iso,
    );
    final record = AttendanceRecord(
      courseId: courseId,
      rollNo: rollNo,
      date: date,
      present: present,
    );
    if (existing == -1) {
      list.add(record);
    } else {
      list[existing] = record;
    }
    notifyListeners();
  }

  String _dateOnly(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  // ----- Course materials --------------------------------------------------
  // Map<courseId, List<CourseMaterial>>
  final Map<String, List<CourseMaterial>> _materialsByCourse = {};

  List<CourseMaterial> materialsForCourse(String courseId) =>
      List.unmodifiable(_materialsByCourse[courseId] ?? const []);

  CourseMaterial addMaterial({
    required String courseId,
    required String title,
    required MaterialKind kind,
    required String reference,
    required String teacherName,
  }) {
    final list = _materialsByCourse.putIfAbsent(courseId, () => []);
    final material = CourseMaterial(
      id: 'MAT-${DateTime.now().millisecondsSinceEpoch}',
      courseId: courseId,
      title: title,
      kind: kind,
      reference: reference,
      teacherName: teacherName,
      uploadedAt: DateTime.now(),
    );
    list.insert(0, material);
    notifyListeners();
    return material;
  }

  void removeMaterial(String materialId) {
    for (final list in _materialsByCourse.values) {
      list.removeWhere((m) => m.id == materialId);
    }
    notifyListeners();
  }

  // ----- Announcements -----------------------------------------------------
  final List<Announcement> _announcements = [];

  List<Announcement> get announcements => List.unmodifiable(_announcements);

  Announcement post({
    required String title,
    required String body,
    required String author,
    bool pinned = false,
  }) {
    final ann = Announcement(
      id: 'ANN-${DateTime.now().millisecondsSinceEpoch}',
      title: title,
      body: body,
      author: author,
      postedAt: DateTime.now(),
      pinned: pinned,
    );
    _announcements.insert(0, ann);
    notifyListeners();
    return ann;
  }

  void deleteAnnouncement(String id) {
    _announcements.removeWhere((a) => a.id == id);
    notifyListeners();
  }

  // ----- Seed demo data ----------------------------------------------------
  void _seedDemoData() {
    _announcements.addAll([
      Announcement(
        id: 'ANN-seed-1',
        title: 'FYP-I proposal defense — Week 14',
        body:
            'All FYP-I groups must submit the proposal cover sheet and SRS document by end of Week 13. Proposal defenses run Mon–Wed of Week 14.',
        author: 'FYP Coordinator',
        postedAt: DateTime.now().subtract(const Duration(days: 2)),
        pinned: true,
      ),
      Announcement(
        id: 'ANN-seed-2',
        title: 'Library — extended hours during midterms',
        body: 'Library will stay open until 11pm from 1st to 15th of next month.',
        author: 'Library Office',
        postedAt: DateTime.now().subtract(const Duration(days: 4)),
        pinned: false,
      ),
    ]);
  }
}

class TimeSlot {
  const TimeSlot({
    required this.day,
    required this.startHour,
    required this.startMinute,
    required this.durationMinutes,
    required this.room,
  });

  /// 1 = Mon … 7 = Sun.
  final int day;
  final int startHour;
  final int startMinute;
  final int durationMinutes;
  final String room;

  String get startLabel =>
      '${startHour.toString().padLeft(2, '0')}:${startMinute.toString().padLeft(2, '0')}';
}

class AttendanceRecord {
  const AttendanceRecord({
    required this.courseId,
    required this.rollNo,
    required this.date,
    required this.present,
  });

  final String courseId;
  final String rollNo;
  final DateTime date;
  final bool present;
}

enum MaterialKind { slides, pdf, link, note }

extension MaterialKindX on MaterialKind {
  String get label {
    switch (this) {
      case MaterialKind.slides:
        return 'Slides';
      case MaterialKind.pdf:
        return 'PDF';
      case MaterialKind.link:
        return 'Link';
      case MaterialKind.note:
        return 'Note';
    }
  }
}

class CourseMaterial {
  const CourseMaterial({
    required this.id,
    required this.courseId,
    required this.title,
    required this.kind,
    required this.reference,
    required this.teacherName,
    required this.uploadedAt,
  });

  final String id;
  final String courseId;
  final String title;
  final MaterialKind kind;

  /// For `link`/`pdf` this is a URL; for `note` it's plain text body.
  final String reference;
  final String teacherName;
  final DateTime uploadedAt;
}

class Announcement {
  const Announcement({
    required this.id,
    required this.title,
    required this.body,
    required this.author,
    required this.postedAt,
    required this.pinned,
  });

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime postedAt;
  final bool pinned;
}
