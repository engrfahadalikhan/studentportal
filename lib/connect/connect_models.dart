// AUST Connect data models — a self-contained module (complaints + file
// tracking). Deliberately isolated: nothing here touches FYP/attendance data.
import 'dart:convert';

/// Who is using AUST Connect right now (passed in from each home screen).
class ConnectIdentity {
  const ConnectIdentity({
    required this.name,
    required this.role, // 'student' | 'teacher' | 'admin'
    required this.id, // roll no / teacher name / 'admin'
  });

  final String name;
  final String role;
  final String id;

  bool get isStaff => role == 'teacher' || role == 'admin';
  bool get isAdmin => role == 'admin';

  /// Stable key notifications are addressed to.
  String get userKey => '$role:${id.trim().toLowerCase()}';
}

// ---------------------------------------------------------------- complaints
const complaintStatuses = ['new', 'read', 'under_process', 'done'];

String complaintStatusLabel(String s) {
  switch (s) {
    case 'read':
      return 'Read';
    case 'under_process':
      return 'Under Process';
    case 'done':
      return 'Done';
    default:
      return 'New';
  }
}

class ComplaintRecord {
  ComplaintRecord({
    required this.id,
    required this.trackingId,
    required this.category,
    required this.subject,
    required this.body,
    required this.byName,
    required this.byRole,
    required this.byId,
    required this.isAnon,
    required this.status,
    required this.handledBy,
    required this.createdAt,
    required this.updatedAt,
    this.doneAt,
    this.deleted = false,
  });

  final String id;
  final String trackingId;
  final String category;
  final String subject;
  final String body;
  final String byName;
  final String byRole;
  final String byId;
  final bool isAnon;
  String status;
  String handledBy;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? doneAt;
  bool deleted;

  /// Hidden from the main dashboard 3 days after being marked Done.
  bool get expiredFromDashboard =>
      status == 'done' &&
      doneAt != null &&
      DateTime.now().difference(doneAt!).inDays >= 3;

  Map<String, Object?> toJson() => {
    'id': id,
    'tracking_id': trackingId,
    'category': category,
    'subject': subject,
    'body': body,
    'by_name': byName,
    'by_role': byRole,
    'by_id': byId,
    'is_anon': isAnon ? 1 : 0,
    'status': status,
    'handled_by': handledBy,
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'done_at': doneAt?.toIso8601String(),
    'deleted': deleted ? 1 : 0,
  };

  static ComplaintRecord fromJson(Map<dynamic, dynamic> m) => ComplaintRecord(
    id: (m['id'] ?? '').toString(),
    trackingId: (m['tracking_id'] ?? '').toString(),
    category: (m['category'] ?? '').toString(),
    subject: (m['subject'] ?? '').toString(),
    body: (m['body'] ?? '').toString(),
    byName: (m['by_name'] ?? '').toString(),
    byRole: (m['by_role'] ?? '').toString(),
    byId: (m['by_id'] ?? '').toString(),
    isAnon: '${m['is_anon'] ?? 1}' == '1' || m['is_anon'] == true,
    status: (m['status'] ?? 'new').toString(),
    handledBy: (m['handled_by'] ?? '').toString(),
    createdAt:
        DateTime.tryParse((m['created_at'] ?? '').toString()) ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse((m['updated_at'] ?? '').toString()) ?? DateTime.now(),
    doneAt: DateTime.tryParse((m['done_at'] ?? '').toString()),
    deleted: '${m['deleted'] ?? 0}' == '1' || m['deleted'] == true,
  );
}

// --------------------------------------------------------------- departments
class ConnectDepartment {
  ConnectDepartment({
    required this.id,
    required this.name,
    required this.seq,
    required this.staff,
    required this.updatedAt,
    this.deleted = false,
  });

  final String id;
  String name;
  int seq;
  List<String> staff; // staff names/ids allowed to advance this dept's step
  DateTime updatedAt;
  bool deleted;

  bool allows(ConnectIdentity who) {
    if (who.isAdmin) return true;
    if (staff.isEmpty) return who.isStaff; // no owner set -> any staff
    final n = who.name.trim().toLowerCase();
    final i = who.id.trim().toLowerCase();
    return staff.any((s) {
      final v = s.trim().toLowerCase();
      return v == n || v == i;
    });
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'seq': seq,
    'staff': staff,
    'updated_at': updatedAt.toIso8601String(),
    'deleted': deleted ? 1 : 0,
  };

  static ConnectDepartment fromJson(Map<dynamic, dynamic> m) {
    final rawStaff = m['staff'];
    List<String> staff;
    if (rawStaff is List) {
      staff = [for (final e in rawStaff) e.toString()];
    } else if (rawStaff is String && rawStaff.trim().isNotEmpty) {
      // MySQL stores it as a JSON string.
      try {
        final d = rawStaff.trim();
        staff = d.startsWith('[')
            ? [
                for (final e
                    in (d.substring(1, d.length - 1).split(',')))
                  e.replaceAll('"', '').trim(),
              ].where((e) => e.isNotEmpty).toList()
            : <String>[];
      } catch (_) {
        staff = <String>[];
      }
    } else {
      staff = <String>[];
    }
    return ConnectDepartment(
      id: (m['id'] ?? '').toString(),
      name: (m['name'] ?? '').toString(),
      seq: int.tryParse('${m['seq'] ?? 0}') ?? 0,
      staff: staff,
      updatedAt:
          DateTime.tryParse((m['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      deleted: '${m['deleted'] ?? 0}' == '1' || m['deleted'] == true,
    );
  }
}

// -------------------------------------------------------------- file tracking
class FileStep {
  FileStep({
    required this.deptId,
    required this.deptName,
    required this.seq,
    this.status = 'pending', // pending | under_process | done
    this.by = '',
    this.at = '',
    this.note = '',
  });

  final String deptId;
  final String deptName;
  final int seq;
  String status;
  String by;
  String at;
  String note;

  Map<String, Object?> toJson() => {
    'dept_id': deptId,
    'dept_name': deptName,
    'seq': seq,
    'status': status,
    'by': by,
    'at': at,
    'note': note,
  };

  static FileStep fromJson(Map<dynamic, dynamic> m) => FileStep(
    deptId: (m['dept_id'] ?? '').toString(),
    deptName: (m['dept_name'] ?? '').toString(),
    seq: int.tryParse('${m['seq'] ?? 0}') ?? 0,
    status: (m['status'] ?? 'pending').toString(),
    by: (m['by'] ?? '').toString(),
    at: (m['at'] ?? '').toString(),
    note: (m['note'] ?? '').toString(),
  );
}

class FileRecord {
  FileRecord({
    required this.id,
    required this.trackingId,
    required this.title,
    required this.description,
    required this.byName,
    required this.byRole,
    required this.byId,
    required this.currentSeq,
    required this.status, // submitted | in_progress | completed
    required this.steps,
    required this.createdAt,
    required this.updatedAt,
    this.completedAt,
    this.deleted = false,
  });

  final String id;
  final String trackingId;
  final String title;
  final String description;
  final String byName;
  final String byRole;
  final String byId;
  int currentSeq;
  String status;
  List<FileStep> steps;
  final DateTime createdAt;
  DateTime updatedAt;
  DateTime? completedAt;
  bool deleted;

  FileStep? get currentStep {
    for (final s in steps) {
      if (s.seq == currentSeq) return s;
    }
    return steps.isEmpty ? null : steps.first;
  }

  int get doneCount => steps.where((s) => s.status == 'done').length;

  Map<String, Object?> toJson() => {
    'id': id,
    'tracking_id': trackingId,
    'title': title,
    'description': description,
    'by_name': byName,
    'by_role': byRole,
    'by_id': byId,
    'current_seq': currentSeq,
    'status': status,
    'steps': [for (final s in steps) s.toJson()],
    'created_at': createdAt.toIso8601String(),
    'updated_at': updatedAt.toIso8601String(),
    'completed_at': completedAt?.toIso8601String(),
    'deleted': deleted ? 1 : 0,
  };

  static FileRecord fromJson(Map<dynamic, dynamic> m) {
    // steps arrive either as a list (local) or a JSON string (MySQL steps_json).
    List<FileStep> steps = [];
    final raw = m['steps'] ?? m['steps_json'];
    if (raw is List) {
      steps = [
        for (final e in raw)
          if (e is Map) FileStep.fromJson(e),
      ];
    } else if (raw is String && raw.trim().isNotEmpty) {
      steps = _stepsFromJsonString(raw);
    }
    steps.sort((a, b) => a.seq.compareTo(b.seq));
    return FileRecord(
      id: (m['id'] ?? '').toString(),
      trackingId: (m['tracking_id'] ?? '').toString(),
      title: (m['title'] ?? '').toString(),
      description: (m['description'] ?? '').toString(),
      byName: (m['by_name'] ?? '').toString(),
      byRole: (m['by_role'] ?? '').toString(),
      byId: (m['by_id'] ?? '').toString(),
      currentSeq: int.tryParse('${m['current_seq'] ?? 0}') ?? 0,
      status: (m['status'] ?? 'submitted').toString(),
      steps: steps,
      createdAt:
          DateTime.tryParse((m['created_at'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((m['updated_at'] ?? '').toString()) ??
          DateTime.now(),
      completedAt: DateTime.tryParse((m['completed_at'] ?? '').toString()),
      deleted: '${m['deleted'] ?? 0}' == '1' || m['deleted'] == true,
    );
  }
}

List<FileStep> _stepsFromJsonString(String raw) {
  try {
    final decoded = jsonDecode(raw);
    if (decoded is List) {
      return [
        for (final e in decoded)
          if (e is Map) FileStep.fromJson(e),
      ];
    }
  } catch (_) {}
  return [];
}

// --------------------------------------------------------------- notifications
class ConnectNotification {
  ConnectNotification({
    required this.id,
    required this.userKey,
    required this.title,
    required this.body,
    required this.refType,
    required this.refId,
    required this.createdAt,
    this.readAt,
  });

  final String id;
  final String userKey;
  final String title;
  final String body;
  final String refType;
  final String refId;
  final DateTime createdAt;
  DateTime? readAt;

  bool get unread => readAt == null;

  Map<String, Object?> toJson() => {
    'id': id,
    'user_key': userKey,
    'title': title,
    'body': body,
    'ref_type': refType,
    'ref_id': refId,
    'created_at': createdAt.toIso8601String(),
    'read_at': readAt?.toIso8601String(),
  };

  static ConnectNotification fromJson(Map<dynamic, dynamic> m) =>
      ConnectNotification(
        id: (m['id'] ?? '').toString(),
        userKey: (m['user_key'] ?? '').toString(),
        title: (m['title'] ?? '').toString(),
        body: (m['body'] ?? '').toString(),
        refType: (m['ref_type'] ?? '').toString(),
        refId: (m['ref_id'] ?? '').toString(),
        createdAt:
            DateTime.tryParse((m['created_at'] ?? '').toString()) ??
            DateTime.now(),
        readAt: DateTime.tryParse((m['read_at'] ?? '').toString()),
      );
}
