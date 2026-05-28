import 'package:flutter/foundation.dart';

import 'fyp_models.dart';

class FypRepository extends ChangeNotifier {
  FypRepository._();

  static final FypRepository instance = FypRepository._();

  // -------- storage --------------------------------------------------------
  final List<FypSubmission> _submissions = [];
  final List<FypIdea> _ideas = [];
  final List<FypAllocation> _allocations = [];
  final List<FypProposal> _proposals = [];
  final List<FypEvaluation> _evaluations = [];
  final List<FypMeetingLog> _meetingLogs = [];
  final List<FypEvaluationConsent> _consents = [];
  final List<FypSrs> _srsDocuments = [];

  // -------- read-only accessors -------------------------------------------
  List<FypSubmission> get submissions => List.unmodifiable(_submissions);
  List<FypIdea> get ideas => List.unmodifiable(_ideas);
  List<FypAllocation> get allocations => List.unmodifiable(_allocations);
  List<FypProposal> get proposals => List.unmodifiable(_proposals);
  List<FypEvaluation> get evaluations => List.unmodifiable(_evaluations);
  List<FypMeetingLog> get meetingLogs => List.unmodifiable(_meetingLogs);
  List<FypEvaluationConsent> get consents => List.unmodifiable(_consents);
  List<FypSrs> get srsDocuments => List.unmodifiable(_srsDocuments);

  // -------- helpers --------------------------------------------------------
  String _newId(String prefix, int currentCount) {
    return '$prefix-${DateTime.now().year}-'
        '${(currentCount + 1).toString().padLeft(3, '0')}';
  }

  bool _matchesRollNo(List<FypMember> members, String rollNo) {
    final normalized = rollNo.trim().toLowerCase();
    if (normalized.isEmpty) {
      return false;
    }
    return members.any(
      (member) => member.rollNo.trim().toLowerCase() == normalized,
    );
  }

  bool _matchesTeacher(String name, String teacherName) {
    final left = name.trim().toLowerCase();
    final right = teacherName.trim().toLowerCase();
    if (left.isEmpty || right.isEmpty) {
      return false;
    }
    return left == right;
  }

  // ========================================================================
  // FYP Submission (Form #1)
  // ========================================================================
  List<FypSubmission> submissionsForRollNo(String rollNo) {
    return _submissions
        .where((submission) => _matchesRollNo(submission.members, rollNo))
        .toList(growable: false);
  }

  FypSubmission? submissionByCode(String qrCode) {
    final lower = qrCode.trim().toLowerCase();
    for (final submission in _submissions) {
      if (submission.qrCode.toLowerCase() == lower) {
        return submission;
      }
    }
    return null;
  }

  FypSubmission createSubmission({
    required FypPhase phase,
    required FypProgram program,
    required String term,
    required List<FypMember> members,
    required String preferredSupervisor,
    required String preferredCoSupervisor,
    required bool joinedWhatsApp,
    required bool joinedGoogleClassroom,
  }) {
    final id = _newId('FYP', _submissions.length);
    final qrCode = 'FYP_${phase.label.replaceAll('-', '')}_$id';
    final submission = FypSubmission(
      id: id,
      qrCode: qrCode,
      phase: phase,
      program: program,
      term: term,
      members: List.unmodifiable(members),
      preferredSupervisor: preferredSupervisor,
      preferredCoSupervisor: preferredCoSupervisor,
      joinedWhatsApp: joinedWhatsApp,
      joinedGoogleClassroom: joinedGoogleClassroom,
      submittedAt: DateTime.now(),
    );
    _submissions.insert(0, submission);
    notifyListeners();
    return submission;
  }

  void markSupervisorInterest({
    required String submissionId,
    required FypSupervisorStatus status,
    required String supervisorName,
  }) {
    final index =
        _submissions.indexWhere((submission) => submission.id == submissionId);
    if (index == -1) {
      return;
    }
    _submissions[index] = _submissions[index].copyWith(
      supervisorStatus: status,
      interestedSupervisorName: supervisorName,
    );
    notifyListeners();
  }

  // ========================================================================
  // FYP Idea (Form #2) — teacher publishes, students browse
  // ========================================================================
  List<FypIdea> ideasForFaculty(String facultyName) {
    return _ideas
        .where((idea) => _matchesTeacher(idea.facultyName, facultyName))
        .toList(growable: false);
  }

  List<FypIdea> availableIdeas() {
    return _ideas
        .where((idea) => idea.takenByGroupId.isEmpty)
        .toList(growable: false);
  }

  FypIdea createIdea({
    required String facultyName,
    required String facultyEmail,
    required String supervisor,
    required String coSupervisor,
    required String title,
    required String projectDomain,
    required String description,
    required String tools,
    required String additionalInfo,
    required String term,
  }) {
    final id = _newId('IDEA', _ideas.length);
    final idea = FypIdea(
      id: id,
      facultyName: facultyName,
      facultyEmail: facultyEmail,
      supervisor: supervisor,
      coSupervisor: coSupervisor,
      title: title,
      projectDomain: projectDomain,
      description: description,
      tools: tools,
      additionalInfo: additionalInfo,
      term: term,
      submittedAt: DateTime.now(),
    );
    _ideas.insert(0, idea);
    notifyListeners();
    return idea;
  }

  void claimIdea({required String ideaId, required String groupId}) {
    final index = _ideas.indexWhere((idea) => idea.id == ideaId);
    if (index == -1) {
      return;
    }
    _ideas[index] = _ideas[index].copyWith(takenByGroupId: groupId);
    notifyListeners();
  }

  // ========================================================================
  // FYP Allocation (Form #3)
  // ========================================================================
  List<FypAllocation> allocationsForRollNo(String rollNo) {
    return _allocations
        .where((allocation) => _matchesRollNo(allocation.members, rollNo))
        .toList(growable: false);
  }

  List<FypAllocation> allocationsForSupervisor(String teacherName) {
    return _allocations
        .where(
          (allocation) =>
              _matchesTeacher(allocation.supervisorName, teacherName) ||
              _matchesTeacher(allocation.coSupervisorName, teacherName),
        )
        .toList(growable: false);
  }

  FypAllocation createAllocation({
    required String term,
    required String projectTitle,
    required String expectedOutcome,
    required List<FypMember> members,
    required String supervisorName,
    required String supervisorEmail,
    required String coSupervisorName,
    required String coSupervisorEmail,
  }) {
    final id = _newId('ALLOC', _allocations.length);
    final qrCode = 'FYP_ALLOC_$id';
    final allocation = FypAllocation(
      id: id,
      qrCode: qrCode,
      term: term,
      projectTitle: projectTitle,
      expectedOutcome: expectedOutcome,
      members: List.unmodifiable(members),
      supervisorName: supervisorName,
      supervisorEmail: supervisorEmail,
      coSupervisorName: coSupervisorName,
      coSupervisorEmail: coSupervisorEmail,
      submittedAt: DateTime.now(),
    );
    _allocations.insert(0, allocation);
    notifyListeners();
    return allocation;
  }

  void approveAllocationAsSupervisor({
    required String allocationId,
    required String approverName,
  }) {
    final index =
        _allocations.indexWhere((allocation) => allocation.id == allocationId);
    if (index == -1) {
      return;
    }
    final current = _allocations[index];
    final isSupervisor = _matchesTeacher(current.supervisorName, approverName);
    final isCoSupervisor =
        _matchesTeacher(current.coSupervisorName, approverName);
    if (!isSupervisor && !isCoSupervisor) {
      return;
    }

    final now = DateTime.now();
    final supervisorApprovedAt =
        isSupervisor ? now : current.supervisorApprovedAt;
    final coSupervisorApprovedAt =
        isCoSupervisor ? now : current.coSupervisorApprovedAt;

    final hasSupervisor = supervisorApprovedAt != null;
    final hasCoSupervisor =
        current.coSupervisorName.trim().isEmpty || coSupervisorApprovedAt != null;
    final status = hasSupervisor && hasCoSupervisor
        ? FypAllocationStatus.fullyApproved
        : FypAllocationStatus.supervisorApproved;

    _allocations[index] = current.copyWith(
      status: status,
      supervisorApprovedAt: supervisorApprovedAt,
      coSupervisorApprovedAt: coSupervisorApprovedAt,
    );
    notifyListeners();
  }

  // ========================================================================
  // FYP Proposal (Form #5) — student-side metadata capture
  // ========================================================================
  List<FypProposal> proposalsForRollNo(String rollNo) {
    return _proposals
        .where((proposal) => _matchesRollNo(proposal.members, rollNo))
        .toList(growable: false);
  }

  List<FypProposal> proposalsForSupervisor(String teacherName) {
    return _proposals
        .where(
          (proposal) =>
              _matchesTeacher(proposal.supervisorName, teacherName) ||
              _matchesTeacher(proposal.coSupervisorName, teacherName),
        )
        .toList(growable: false);
  }

  FypProposal createProposal({
    required String term,
    required String projectId,
    required FypProjectType projectType,
    required String areaOfSpecialization,
    required String title,
    required List<FypMember> members,
    required String supervisorName,
    required String supervisorDesignation,
    required String coSupervisorName,
    required String coSupervisorDesignation,
    required String similarityIndex,
  }) {
    final id = _newId('PROP', _proposals.length);
    final qrCode = 'FYP_PROP_$id';
    final proposal = FypProposal(
      id: id,
      qrCode: qrCode,
      term: term,
      projectId: projectId,
      projectType: projectType,
      areaOfSpecialization: areaOfSpecialization,
      title: title,
      members: List.unmodifiable(members),
      supervisorName: supervisorName,
      supervisorDesignation: supervisorDesignation,
      coSupervisorName: coSupervisorName,
      coSupervisorDesignation: coSupervisorDesignation,
      similarityIndex: similarityIndex,
      submittedAt: DateTime.now(),
    );
    _proposals.insert(0, proposal);
    notifyListeners();
    return proposal;
  }

  // ========================================================================
  // Evaluation (Forms #8 + #11)
  // ========================================================================
  List<FypEvaluation> evaluationsForRollNo(String rollNo) {
    return _evaluations
        .where((evaluation) => _matchesRollNo(evaluation.members, rollNo))
        .toList(growable: false);
  }

  List<FypEvaluation> evaluationsByExaminer(String examinerName) {
    return _evaluations
        .where(
          (evaluation) =>
              _matchesTeacher(evaluation.examinerName, examinerName),
        )
        .toList(growable: false);
  }

  FypEvaluation createEvaluation({
    required FypEvaluationKind kind,
    required String term,
    required String projectTitle,
    required String supervisorName,
    required String examinerName,
    required List<FypMember> members,
    required List<FypRubricRow> rubric,
  }) {
    final id = _newId(
      kind == FypEvaluationKind.proposal ? 'PEVAL' : 'SEVAL',
      _evaluations.length,
    );
    final evaluation = FypEvaluation(
      id: id,
      kind: kind,
      term: term,
      projectTitle: projectTitle,
      supervisorName: supervisorName,
      examinerName: examinerName,
      members: List.unmodifiable(members),
      rubric: List.unmodifiable(rubric),
      submittedAt: DateTime.now(),
    );
    _evaluations.insert(0, evaluation);
    notifyListeners();
    return evaluation;
  }

  // ========================================================================
  // Meeting Log (Form #14)
  // ========================================================================
  List<FypMeetingLog> meetingLogsForRollNo(String rollNo) {
    return _meetingLogs
        .where((log) => _matchesRollNo(log.members, rollNo))
        .toList(growable: false);
  }

  List<FypMeetingLog> meetingLogsForSupervisor(String teacherName) {
    return _meetingLogs
        .where((log) => _matchesTeacher(log.supervisorName, teacherName))
        .toList(growable: false);
  }

  FypMeetingLog createMeetingLog({
    required String term,
    required String projectTitle,
    required String supervisorName,
    required FypProgram program,
    required List<FypMember> members,
    required String meetingDate,
    required String previousMeetingDate,
    required String workDoneSinceLastMeeting,
    required String issuesToDiscuss,
  }) {
    final id = _newId('MEET', _meetingLogs.length);
    final log = FypMeetingLog(
      id: id,
      term: term,
      projectTitle: projectTitle,
      supervisorName: supervisorName,
      program: program,
      members: List.unmodifiable(members),
      meetingDate: meetingDate,
      previousMeetingDate: previousMeetingDate,
      workDoneSinceLastMeeting: workDoneSinceLastMeeting,
      issuesToDiscuss: issuesToDiscuss,
      studentSubmittedAt: DateTime.now(),
    );
    _meetingLogs.insert(0, log);
    notifyListeners();
    return log;
  }

  void completeMeetingLog({
    required String logId,
    required String tasksAssigned,
    required String nextMeetingDate,
  }) {
    final index = _meetingLogs.indexWhere((log) => log.id == logId);
    if (index == -1) {
      return;
    }
    _meetingLogs[index] = _meetingLogs[index].copyWith(
      tasksAssigned: tasksAssigned,
      nextMeetingDate: nextMeetingDate,
      supervisorSignedAt: DateTime.now(),
    );
    notifyListeners();
  }

  // ========================================================================
  // Supervisor Consent Form (Form #7)
  // ========================================================================
  List<FypEvaluationConsent> consentsForRollNo(String rollNo) {
    return _consents
        .where((consent) => _matchesRollNo(consent.members, rollNo))
        .toList(growable: false);
  }

  List<FypEvaluationConsent> consentsForSupervisor(String teacherName) {
    return _consents
        .where(
          (consent) =>
              _matchesTeacher(consent.supervisorName, teacherName),
        )
        .toList(growable: false);
  }

  FypEvaluationConsent createConsent({
    required String term,
    required String fypTitle,
    required FypProgram program,
    required String supervisorName,
    required List<FypMember> members,
    required List<FypEvaluationType> approvedEvaluations,
  }) {
    final id = _newId('CONSENT', _consents.length);
    final qrCode = 'FYP_CONSENT_$id';
    final consent = FypEvaluationConsent(
      id: id,
      qrCode: qrCode,
      term: term,
      fypTitle: fypTitle,
      program: program,
      supervisorName: supervisorName,
      members: List.unmodifiable(members),
      approvedEvaluations: List.unmodifiable(approvedEvaluations),
      signedAt: DateTime.now(),
    );
    _consents.insert(0, consent);
    notifyListeners();
    return consent;
  }

  // ========================================================================
  // SRS Document (Form #10)
  // ========================================================================
  List<FypSrs> srsForRollNo(String rollNo) {
    return _srsDocuments
        .where((srs) => _matchesRollNo(srs.members, rollNo))
        .toList(growable: false);
  }

  List<FypSrs> srsForSupervisor(String teacherName) {
    return _srsDocuments
        .where(
          (srs) =>
              _matchesTeacher(srs.supervisorName, teacherName) ||
              _matchesTeacher(srs.coSupervisorName, teacherName),
        )
        .toList(growable: false);
  }

  FypSrs createSrs({
    required String term,
    required String title,
    required List<FypMember> members,
    required String supervisorName,
    required String coSupervisorName,
    required String overallDescription,
    required String externalInterfaces,
    required String functionalRequirements,
    required String nonFunctionalRequirements,
    required String interfaceRequirements,
    required String useCases,
    required String umlDiagramsNotes,
  }) {
    final id = _newId('SRS', _srsDocuments.length);
    final qrCode = 'FYP_SRS_$id';
    final srs = FypSrs(
      id: id,
      qrCode: qrCode,
      term: term,
      title: title,
      members: List.unmodifiable(members),
      supervisorName: supervisorName,
      coSupervisorName: coSupervisorName,
      overallDescription: overallDescription,
      externalInterfaces: externalInterfaces,
      functionalRequirements: functionalRequirements,
      nonFunctionalRequirements: nonFunctionalRequirements,
      interfaceRequirements: interfaceRequirements,
      useCases: useCases,
      umlDiagramsNotes: umlDiagramsNotes,
      submittedAt: DateTime.now(),
    );
    _srsDocuments.insert(0, srs);
    notifyListeners();
    return srs;
  }
}
