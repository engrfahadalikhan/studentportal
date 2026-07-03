import 'fyp_group_models.dart';
import 'fyp_models.dart';

/// JSON encode/decode for the FYP models so the whole workspace persists on
/// disk (and survives app restarts). Enums are stored by name.

T _enum<T extends Enum>(List<T> values, Object? name, T fallback) {
  for (final v in values) {
    if (v.name == name) return v;
  }
  return fallback;
}

DateTime _date(Object? v) =>
    DateTime.tryParse((v ?? '').toString()) ?? DateTime.now();

DateTime? _dateOrNull(Object? v) => DateTime.tryParse((v ?? '').toString());

List<FypMember> _members(Object? v) => [
  for (final m in (v as List? ?? const []))
    if (m is Map) fypMemberFromMap(m),
];

List<Map<String, Object?>> _memberMaps(List<FypMember> members) => [
  for (final m in members) fypMemberToMap(m),
];

// ---------------------------------------------------------------- submission
Map<String, Object?> submissionToMap(FypSubmission s) => {
  'id': s.id,
  'qrCode': s.qrCode,
  'phase': s.phase.name,
  'program': s.program.name,
  'term': s.term,
  'members': _memberMaps(s.members),
  'preferredSupervisor': s.preferredSupervisor,
  'preferredCoSupervisor': s.preferredCoSupervisor,
  'joinedWhatsApp': s.joinedWhatsApp,
  'joinedGoogleClassroom': s.joinedGoogleClassroom,
  'submittedAt': s.submittedAt.toIso8601String(),
  'supervisorStatus': s.supervisorStatus.name,
  'interestedSupervisorName': s.interestedSupervisorName,
};

FypSubmission submissionFromMap(Map<dynamic, dynamic> m) => FypSubmission(
  id: (m['id'] ?? '').toString(),
  qrCode: (m['qrCode'] ?? '').toString(),
  phase: _enum(FypPhase.values, m['phase'], FypPhase.fyp1),
  program: _enum(FypProgram.values, m['program'], FypProgram.bscs),
  term: (m['term'] ?? '').toString(),
  members: _members(m['members']),
  preferredSupervisor: (m['preferredSupervisor'] ?? '').toString(),
  preferredCoSupervisor: (m['preferredCoSupervisor'] ?? '').toString(),
  joinedWhatsApp: m['joinedWhatsApp'] == true,
  joinedGoogleClassroom: m['joinedGoogleClassroom'] == true,
  submittedAt: _date(m['submittedAt']),
  supervisorStatus: _enum(
    FypSupervisorStatus.values,
    m['supervisorStatus'],
    FypSupervisorStatus.pending,
  ),
  interestedSupervisorName: (m['interestedSupervisorName'] ?? '').toString(),
);

// ---------------------------------------------------------------------- idea
Map<String, Object?> ideaToMap(FypIdea i) => {
  'id': i.id,
  'facultyName': i.facultyName,
  'facultyEmail': i.facultyEmail,
  'supervisor': i.supervisor,
  'coSupervisor': i.coSupervisor,
  'title': i.title,
  'projectDomain': i.projectDomain,
  'description': i.description,
  'tools': i.tools,
  'additionalInfo': i.additionalInfo,
  'term': i.term,
  'submittedAt': i.submittedAt.toIso8601String(),
  'takenByGroupId': i.takenByGroupId,
};

FypIdea ideaFromMap(Map<dynamic, dynamic> m) => FypIdea(
  id: (m['id'] ?? '').toString(),
  facultyName: (m['facultyName'] ?? '').toString(),
  facultyEmail: (m['facultyEmail'] ?? '').toString(),
  supervisor: (m['supervisor'] ?? '').toString(),
  coSupervisor: (m['coSupervisor'] ?? '').toString(),
  title: (m['title'] ?? '').toString(),
  projectDomain: (m['projectDomain'] ?? '').toString(),
  description: (m['description'] ?? '').toString(),
  tools: (m['tools'] ?? '').toString(),
  additionalInfo: (m['additionalInfo'] ?? '').toString(),
  term: (m['term'] ?? '').toString(),
  submittedAt: _date(m['submittedAt']),
  takenByGroupId: (m['takenByGroupId'] ?? '').toString(),
);

// ---------------------------------------------------------------- allocation
Map<String, Object?> allocationToMap(FypAllocation a) => {
  'id': a.id,
  'qrCode': a.qrCode,
  'term': a.term,
  'projectTitle': a.projectTitle,
  'expectedOutcome': a.expectedOutcome,
  'members': _memberMaps(a.members),
  'supervisorName': a.supervisorName,
  'supervisorEmail': a.supervisorEmail,
  'coSupervisorName': a.coSupervisorName,
  'coSupervisorEmail': a.coSupervisorEmail,
  'submittedAt': a.submittedAt.toIso8601String(),
  'status': a.status.name,
  'supervisorApprovedAt': a.supervisorApprovedAt?.toIso8601String(),
  'coSupervisorApprovedAt': a.coSupervisorApprovedAt?.toIso8601String(),
};

FypAllocation allocationFromMap(Map<dynamic, dynamic> m) => FypAllocation(
  id: (m['id'] ?? '').toString(),
  qrCode: (m['qrCode'] ?? '').toString(),
  term: (m['term'] ?? '').toString(),
  projectTitle: (m['projectTitle'] ?? '').toString(),
  expectedOutcome: (m['expectedOutcome'] ?? '').toString(),
  members: _members(m['members']),
  supervisorName: (m['supervisorName'] ?? '').toString(),
  supervisorEmail: (m['supervisorEmail'] ?? '').toString(),
  coSupervisorName: (m['coSupervisorName'] ?? '').toString(),
  coSupervisorEmail: (m['coSupervisorEmail'] ?? '').toString(),
  submittedAt: _date(m['submittedAt']),
  status: _enum(
    FypAllocationStatus.values,
    m['status'],
    FypAllocationStatus.pending,
  ),
  supervisorApprovedAt: _dateOrNull(m['supervisorApprovedAt']),
  coSupervisorApprovedAt: _dateOrNull(m['coSupervisorApprovedAt']),
);

// ------------------------------------------------------------------ proposal
Map<String, Object?> proposalToMap(FypProposal p) => {
  'id': p.id,
  'qrCode': p.qrCode,
  'term': p.term,
  'projectId': p.projectId,
  'projectType': p.projectType.name,
  'areaOfSpecialization': p.areaOfSpecialization,
  'title': p.title,
  'members': _memberMaps(p.members),
  'supervisorName': p.supervisorName,
  'supervisorDesignation': p.supervisorDesignation,
  'coSupervisorName': p.coSupervisorName,
  'coSupervisorDesignation': p.coSupervisorDesignation,
  'similarityIndex': p.similarityIndex,
  'submittedAt': p.submittedAt.toIso8601String(),
};

FypProposal proposalFromMap(Map<dynamic, dynamic> m) => FypProposal(
  id: (m['id'] ?? '').toString(),
  qrCode: (m['qrCode'] ?? '').toString(),
  term: (m['term'] ?? '').toString(),
  projectId: (m['projectId'] ?? '').toString(),
  projectType: _enum(
    FypProjectType.values,
    m['projectType'],
    FypProjectType.development,
  ),
  areaOfSpecialization: (m['areaOfSpecialization'] ?? '').toString(),
  title: (m['title'] ?? '').toString(),
  members: _members(m['members']),
  supervisorName: (m['supervisorName'] ?? '').toString(),
  supervisorDesignation: (m['supervisorDesignation'] ?? '').toString(),
  coSupervisorName: (m['coSupervisorName'] ?? '').toString(),
  coSupervisorDesignation: (m['coSupervisorDesignation'] ?? '').toString(),
  similarityIndex: (m['similarityIndex'] ?? '').toString(),
  submittedAt: _date(m['submittedAt']),
);

// ---------------------------------------------------------------- evaluation
Map<String, Object?> evaluationToMap(FypEvaluation e) => {
  'id': e.id,
  'kind': e.kind.name,
  'term': e.term,
  'projectTitle': e.projectTitle,
  'supervisorName': e.supervisorName,
  'examinerName': e.examinerName,
  'members': _memberMaps(e.members),
  'rubric': [
    for (final r in e.rubric)
      {'label': r.label, 'maxMarks': r.maxMarks, 'score': r.score},
  ],
  'submittedAt': e.submittedAt.toIso8601String(),
};

FypEvaluation evaluationFromMap(Map<dynamic, dynamic> m) => FypEvaluation(
  id: (m['id'] ?? '').toString(),
  kind: _enum(FypEvaluationKind.values, m['kind'], FypEvaluationKind.proposal),
  term: (m['term'] ?? '').toString(),
  projectTitle: (m['projectTitle'] ?? '').toString(),
  supervisorName: (m['supervisorName'] ?? '').toString(),
  examinerName: (m['examinerName'] ?? '').toString(),
  members: _members(m['members']),
  rubric: [
    for (final r in (m['rubric'] as List? ?? const []))
      if (r is Map)
        FypRubricRow(
          label: (r['label'] ?? '').toString(),
          maxMarks: int.tryParse('${r['maxMarks'] ?? 0}') ?? 0,
          score: int.tryParse('${r['score'] ?? 0}') ?? 0,
        ),
  ],
  submittedAt: _date(m['submittedAt']),
);

// --------------------------------------------------------------- meeting log
Map<String, Object?> meetingLogToMap(FypMeetingLog l) => {
  'id': l.id,
  'term': l.term,
  'projectTitle': l.projectTitle,
  'supervisorName': l.supervisorName,
  'program': l.program.name,
  'members': _memberMaps(l.members),
  'meetingDate': l.meetingDate,
  'previousMeetingDate': l.previousMeetingDate,
  'workDoneSinceLastMeeting': l.workDoneSinceLastMeeting,
  'issuesToDiscuss': l.issuesToDiscuss,
  'studentSubmittedAt': l.studentSubmittedAt.toIso8601String(),
  'tasksAssigned': l.tasksAssigned,
  'nextMeetingDate': l.nextMeetingDate,
  'supervisorSignedAt': l.supervisorSignedAt?.toIso8601String(),
};

FypMeetingLog meetingLogFromMap(Map<dynamic, dynamic> m) => FypMeetingLog(
  id: (m['id'] ?? '').toString(),
  term: (m['term'] ?? '').toString(),
  projectTitle: (m['projectTitle'] ?? '').toString(),
  supervisorName: (m['supervisorName'] ?? '').toString(),
  program: _enum(FypProgram.values, m['program'], FypProgram.bscs),
  members: _members(m['members']),
  meetingDate: (m['meetingDate'] ?? '').toString(),
  previousMeetingDate: (m['previousMeetingDate'] ?? '').toString(),
  workDoneSinceLastMeeting: (m['workDoneSinceLastMeeting'] ?? '').toString(),
  issuesToDiscuss: (m['issuesToDiscuss'] ?? '').toString(),
  studentSubmittedAt: _date(m['studentSubmittedAt']),
  tasksAssigned: (m['tasksAssigned'] ?? '').toString(),
  nextMeetingDate: (m['nextMeetingDate'] ?? '').toString(),
  supervisorSignedAt: _dateOrNull(m['supervisorSignedAt']),
);

// ------------------------------------------------------------------- consent
Map<String, Object?> consentToMap(FypEvaluationConsent c) => {
  'id': c.id,
  'qrCode': c.qrCode,
  'term': c.term,
  'fypTitle': c.fypTitle,
  'program': c.program.name,
  'supervisorName': c.supervisorName,
  'members': _memberMaps(c.members),
  'approvedEvaluations': [for (final e in c.approvedEvaluations) e.name],
  'signedAt': c.signedAt.toIso8601String(),
};

FypEvaluationConsent consentFromMap(Map<dynamic, dynamic> m) =>
    FypEvaluationConsent(
      id: (m['id'] ?? '').toString(),
      qrCode: (m['qrCode'] ?? '').toString(),
      term: (m['term'] ?? '').toString(),
      fypTitle: (m['fypTitle'] ?? '').toString(),
      program: _enum(FypProgram.values, m['program'], FypProgram.bscs),
      supervisorName: (m['supervisorName'] ?? '').toString(),
      members: _members(m['members']),
      approvedEvaluations: [
        for (final e in (m['approvedEvaluations'] as List? ?? const []))
          _enum(
            FypEvaluationType.values,
            e,
            FypEvaluationType.proposalDefense,
          ),
      ],
      signedAt: _date(m['signedAt']),
    );

// ----------------------------------------------------------------------- srs
Map<String, Object?> srsToMap(FypSrs s) => {
  'id': s.id,
  'qrCode': s.qrCode,
  'term': s.term,
  'title': s.title,
  'members': _memberMaps(s.members),
  'supervisorName': s.supervisorName,
  'coSupervisorName': s.coSupervisorName,
  'overallDescription': s.overallDescription,
  'externalInterfaces': s.externalInterfaces,
  'functionalRequirements': s.functionalRequirements,
  'nonFunctionalRequirements': s.nonFunctionalRequirements,
  'interfaceRequirements': s.interfaceRequirements,
  'useCases': s.useCases,
  'umlDiagramsNotes': s.umlDiagramsNotes,
  'submittedAt': s.submittedAt.toIso8601String(),
};

FypSrs srsFromMap(Map<dynamic, dynamic> m) => FypSrs(
  id: (m['id'] ?? '').toString(),
  qrCode: (m['qrCode'] ?? '').toString(),
  term: (m['term'] ?? '').toString(),
  title: (m['title'] ?? '').toString(),
  members: _members(m['members']),
  supervisorName: (m['supervisorName'] ?? '').toString(),
  coSupervisorName: (m['coSupervisorName'] ?? '').toString(),
  overallDescription: (m['overallDescription'] ?? '').toString(),
  externalInterfaces: (m['externalInterfaces'] ?? '').toString(),
  functionalRequirements: (m['functionalRequirements'] ?? '').toString(),
  nonFunctionalRequirements: (m['nonFunctionalRequirements'] ?? '').toString(),
  interfaceRequirements: (m['interfaceRequirements'] ?? '').toString(),
  useCases: (m['useCases'] ?? '').toString(),
  umlDiagramsNotes: (m['umlDiagramsNotes'] ?? '').toString(),
  submittedAt: _date(m['submittedAt']),
);
