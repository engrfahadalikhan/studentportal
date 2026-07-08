// AUST Event data models — a campus events board (post -> pending -> approved
// -> shows in the feed for everyone). Self-contained; shares only the identity
// and notification types from connect_models.dart.

/// Departments an event can be filed under (AUST department list).
const eventDepartments = <String>[
  'Computer Science',
  'Software Engineering',
  'Management Sciences',
  'Physics',
  'Chemistry',
  'MLT',
  'Material Engineering',
  'Pak Studies',
  'Mathematics',
  'General / All',
];

/// How many built-in poster styles a poster can pick from. Posters are drawn
/// locally (gradient + title) so there is no network image dependency — the
/// feed always renders, even offline.
const int kEventPosterCount = 6;

const eventStatuses = ['pending', 'approved', 'rejected'];

String eventStatusLabel(String s) {
  switch (s) {
    case 'approved':
      return 'Approved';
    case 'rejected':
      return 'Rejected';
    default:
      return 'Pending';
  }
}

class CampusEvent {
  CampusEvent({
    required this.id,
    required this.title,
    required this.caption,
    required this.date,
    required this.minuteOfDay,
    required this.location,
    required this.poster,
    required this.department,
    required this.byName,
    required this.byRole,
    required this.byId,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    this.approvedAt,
    this.deleted = false,
  });

  final String id;
  final String title;
  final String caption;
  final DateTime date;

  /// Time of day stored as minutes since midnight (JSON-friendly).
  final int minuteOfDay;
  final String location;
  final int poster;
  final String department;
  final String byName;
  final String byRole;
  final String byId;
  String status;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? approvedAt;
  bool deleted;

  int get hour => minuteOfDay ~/ 60;
  int get minute => minuteOfDay % 60;

  String get timeLabel {
    final h12 = hour % 12 == 0 ? 12 : hour % 12;
    final mm = minute.toString().padLeft(2, '0');
    final ap = hour < 12 ? 'AM' : 'PM';
    return '$h12:$mm $ap';
  }

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  String get dateLabel => '${date.day} ${_months[date.month - 1]} ${date.year}';

  bool get isPast {
    final now = DateTime.now();
    final end = DateTime(date.year, date.month, date.day, hour, minute);
    return end.isBefore(DateTime(now.year, now.month, now.day));
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'caption': caption,
    'date': date.toIso8601String(),
    'minute_of_day': minuteOfDay,
    'location': location,
    'poster': poster,
    'department': department,
    'by_name': byName,
    'by_role': byRole,
    'by_id': byId,
    'status': status,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'approved_at': approvedAt?.toIso8601String(),
    'deleted': deleted ? 1 : 0,
  };

  static CampusEvent fromJson(Map<dynamic, dynamic> m) => CampusEvent(
    id: (m['id'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    caption: (m['caption'] ?? '').toString(),
    date: DateTime.tryParse((m['date'] ?? '').toString()) ?? DateTime.now(),
    minuteOfDay: int.tryParse('${m['minute_of_day'] ?? 540}') ?? 540,
    location: (m['location'] ?? '').toString(),
    poster: (int.tryParse('${m['poster'] ?? 0}') ?? 0) % kEventPosterCount,
    department: (m['department'] ?? '').toString(),
    byName: (m['by_name'] ?? '').toString(),
    byRole: (m['by_role'] ?? '').toString(),
    byId: (m['by_id'] ?? '').toString(),
    status: (m['status'] ?? 'pending').toString(),
    createdAt:
        DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse((m['updated_at'] ?? '').toString()) ?? DateTime.now(),
    approvedAt: DateTime.tryParse((m['approved_at'] ?? '').toString()),
    deleted: '${m['deleted'] ?? 0}' == '1' || m['deleted'] == true,
  );
}
