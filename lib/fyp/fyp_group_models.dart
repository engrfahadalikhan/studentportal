import 'fyp_models.dart';

// ============================================================================
// FYP Examiner Panel — a reusable named set of examiner teachers that the
// coordinator can assign to a group in one tap (fills the group's examiners).
// ============================================================================
class FypPanel {
  const FypPanel({
    required this.id,
    required this.name,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final List<String> members; // examiner teacher names
  final DateTime createdAt;
  final DateTime updatedAt;

  FypPanel copyWith({String? name, List<String>? members}) => FypPanel(
    id: id,
    name: name ?? this.name,
    members: members ?? this.members,
    createdAt: createdAt,
    updatedAt: DateTime.now(),
  );

  Map<String, Object?> toJson() => {
    'id': id,
    'name': name,
    'members': members,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static FypPanel fromJson(Map<dynamic, dynamic> m) => FypPanel(
    id: (m['id'] ?? '').toString(),
    name: (m['name'] ?? '').toString(),
    members: [for (final e in (m['members'] as List? ?? const [])) e.toString()],
    createdAt:
        DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse((m['updatedAt'] ?? '').toString()) ?? DateTime.now(),
  );
}

// ============================================================================
// FYP Meeting — the coordinator schedules a meeting on a date; it notifies the
// targeted students AND their supervisor/examiners. If a form must be brought,
// the teacher side shows the form requirement too.
// ============================================================================
class FypMeeting {
  const FypMeeting({
    required this.id,
    required this.title,
    required this.date,
    required this.phase, // null = all phases
    required this.groupId, // '' = whole phase / all
    required this.note,
    required this.formRequired,
    required this.formName,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final String date; // free-text or ISO date
  final FypPhase? phase;
  final String groupId;
  final String note;
  final bool formRequired;
  final String formName;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'date': date,
    'phase': phase?.name,
    'groupId': groupId,
    'note': note,
    'formRequired': formRequired,
    'formName': formName,
    'createdBy': createdBy,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static FypMeeting fromJson(Map<dynamic, dynamic> m) => FypMeeting(
    id: (m['id'] ?? '').toString(),
    title: (m['title'] ?? '').toString(),
    date: (m['date'] ?? '').toString(),
    phase: FypPhase.values
        .where((e) => e.name == m['phase'])
        .cast<FypPhase?>()
        .firstWhere((_) => true, orElse: () => null),
    groupId: (m['groupId'] ?? '').toString(),
    note: (m['note'] ?? '').toString(),
    formRequired: m['formRequired'] == true,
    formName: (m['formName'] ?? '').toString(),
    createdBy: (m['createdBy'] ?? '').toString(),
    createdAt:
        DateTime.tryParse((m['createdAt'] ?? '').toString()) ?? DateTime.now(),
    updatedAt:
        DateTime.tryParse((m['updatedAt'] ?? '').toString()) ?? DateTime.now(),
  );
}

// ============================================================================
// FYP Group — the allotment workflow record
//
// Creation paths and their approval chains:
//   teacher creates      → pendingCoordinator → approved
//   student creates      → pendingSupervisor → pendingCoordinator → approved
//   coordinator creates  → approved (direct allot)
// The coordinator can approve (allot) ANY pending group directly, and assigns
// examiner teachers to approved groups.
// ============================================================================

enum FypGroupStatus { pendingSupervisor, pendingCoordinator, approved, rejected }

extension FypGroupStatusX on FypGroupStatus {
  String get label {
    switch (this) {
      case FypGroupStatus.pendingSupervisor:
        return 'Waiting for supervisor';
      case FypGroupStatus.pendingCoordinator:
        return 'Waiting for coordinator';
      case FypGroupStatus.approved:
        return 'Approved / allotted';
      case FypGroupStatus.rejected:
        return 'Rejected';
    }
  }
}

Map<String, Object?> fypMemberToMap(FypMember m) => {
  'serialNo': m.serialNo,
  'rollNo': m.rollNo,
  'name': m.name,
  'email': m.email,
  'cgpa': m.cgpa,
  'phone': m.phone,
};

FypMember fypMemberFromMap(Map<dynamic, dynamic> map) => FypMember(
  serialNo: int.tryParse('${map['serialNo'] ?? 0}') ?? 0,
  rollNo: (map['rollNo'] ?? '').toString(),
  name: (map['name'] ?? '').toString(),
  email: (map['email'] ?? '').toString(),
  cgpa: (map['cgpa'] ?? '').toString(),
  phone: (map['phone'] ?? '').toString(),
);

class FypGroup {
  const FypGroup({
    required this.id,
    required this.title,
    required this.phase,
    required this.program,
    required this.term,
    required this.members,
    required this.supervisorName,
    this.coSupervisorName = '',
    required this.createdByRole, // 'teacher' | 'student' | 'coordinator'
    required this.createdByName,
    required this.status,
    this.supervisorActionBy = '',
    this.supervisorActionAt,
    this.coordinatorActionBy = '',
    this.coordinatorActionAt,
    this.rejectedReason = '',
    this.examiners = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String title;
  final FypPhase phase;
  final FypProgram program;
  final String term;
  final List<FypMember> members;
  final String supervisorName;
  final String coSupervisorName;
  final String createdByRole;
  final String createdByName;
  final FypGroupStatus status;
  final String supervisorActionBy;
  final DateTime? supervisorActionAt;
  final String coordinatorActionBy;
  final DateTime? coordinatorActionAt;
  final String rejectedReason;

  /// Teacher names assigned by the coordinator to examine this group.
  final List<String> examiners;
  final DateTime createdAt;
  final DateTime updatedAt;

  FypGroup copyWith({
    String? title,
    FypPhase? phase,
    FypProgram? program,
    String? term,
    List<FypMember>? members,
    String? supervisorName,
    String? coSupervisorName,
    FypGroupStatus? status,
    String? supervisorActionBy,
    DateTime? supervisorActionAt,
    String? coordinatorActionBy,
    DateTime? coordinatorActionAt,
    String? rejectedReason,
    List<String>? examiners,
    DateTime? updatedAt,
  }) {
    return FypGroup(
      id: id,
      title: title ?? this.title,
      phase: phase ?? this.phase,
      program: program ?? this.program,
      term: term ?? this.term,
      members: members ?? this.members,
      supervisorName: supervisorName ?? this.supervisorName,
      coSupervisorName: coSupervisorName ?? this.coSupervisorName,
      createdByRole: createdByRole,
      createdByName: createdByName,
      status: status ?? this.status,
      supervisorActionBy: supervisorActionBy ?? this.supervisorActionBy,
      supervisorActionAt: supervisorActionAt ?? this.supervisorActionAt,
      coordinatorActionBy: coordinatorActionBy ?? this.coordinatorActionBy,
      coordinatorActionAt: coordinatorActionAt ?? this.coordinatorActionAt,
      rejectedReason: rejectedReason ?? this.rejectedReason,
      examiners: examiners ?? this.examiners,
      createdAt: createdAt,
      updatedAt: updatedAt ?? DateTime.now(),
    );
  }

  Map<String, Object?> toJson() => {
    'id': id,
    'title': title,
    'phase': phase.name,
    'program': program.name,
    'term': term,
    'members': [for (final m in members) fypMemberToMap(m)],
    'supervisorName': supervisorName,
    'coSupervisorName': coSupervisorName,
    'createdByRole': createdByRole,
    'createdByName': createdByName,
    'status': status.name,
    'supervisorActionBy': supervisorActionBy,
    'supervisorActionAt': supervisorActionAt?.toIso8601String(),
    'coordinatorActionBy': coordinatorActionBy,
    'coordinatorActionAt': coordinatorActionAt?.toIso8601String(),
    'rejectedReason': rejectedReason,
    'examiners': examiners,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };

  static FypGroup fromJson(Map<dynamic, dynamic> map) {
    FypPhase phase = FypPhase.values.firstWhere(
      (e) => e.name == map['phase'],
      orElse: () => FypPhase.fyp1,
    );
    FypProgram program = FypProgram.values.firstWhere(
      (e) => e.name == map['program'],
      orElse: () => FypProgram.bscs,
    );
    FypGroupStatus status = FypGroupStatus.values.firstWhere(
      (e) => e.name == map['status'],
      orElse: () => FypGroupStatus.pendingCoordinator,
    );
    return FypGroup(
      id: (map['id'] ?? '').toString(),
      title: (map['title'] ?? '').toString(),
      phase: phase,
      program: program,
      term: (map['term'] ?? '').toString(),
      members: [
        for (final m in (map['members'] as List? ?? const []))
          if (m is Map) fypMemberFromMap(m),
      ],
      supervisorName: (map['supervisorName'] ?? '').toString(),
      coSupervisorName: (map['coSupervisorName'] ?? '').toString(),
      createdByRole: (map['createdByRole'] ?? '').toString(),
      createdByName: (map['createdByName'] ?? '').toString(),
      status: status,
      supervisorActionBy: (map['supervisorActionBy'] ?? '').toString(),
      supervisorActionAt: DateTime.tryParse(
        (map['supervisorActionAt'] ?? '').toString(),
      ),
      coordinatorActionBy: (map['coordinatorActionBy'] ?? '').toString(),
      coordinatorActionAt: DateTime.tryParse(
        (map['coordinatorActionAt'] ?? '').toString(),
      ),
      rejectedReason: (map['rejectedReason'] ?? '').toString(),
      examiners: [
        for (final e in (map['examiners'] as List? ?? const [])) e.toString(),
      ],
      createdAt:
          DateTime.tryParse((map['createdAt'] ?? '').toString()) ??
          DateTime.now(),
      updatedAt:
          DateTime.tryParse((map['updatedAt'] ?? '').toString()) ??
          DateTime.now(),
    );
  }
}
