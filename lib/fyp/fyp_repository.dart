import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'fyp_codec.dart';
import 'fyp_group_models.dart';
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
  final List<FypGroup> _groups = [];
  final List<String> _coordinators = [];
  final List<FypPanel> _panels = [];
  final List<FypMeeting> _meetings = [];

  // -------- read-only accessors -------------------------------------------
  List<FypSubmission> get submissions => List.unmodifiable(_submissions);
  List<FypIdea> get ideas => List.unmodifiable(_ideas);
  List<FypAllocation> get allocations => List.unmodifiable(_allocations);
  List<FypProposal> get proposals => List.unmodifiable(_proposals);
  List<FypEvaluation> get evaluations => List.unmodifiable(_evaluations);
  List<FypMeetingLog> get meetingLogs => List.unmodifiable(_meetingLogs);
  List<FypEvaluationConsent> get consents => List.unmodifiable(_consents);
  List<FypSrs> get srsDocuments => List.unmodifiable(_srsDocuments);
  List<FypGroup> get groups => List.unmodifiable(_groups);
  List<FypPanel> get panels => List.unmodifiable(_panels);
  List<FypMeeting> get meetings => List.unmodifiable(_meetings);

  /// The designated FYP coordinator teacher names. Empty = not set.
  List<String> get coordinatorNames => List.unmodifiable(_coordinators);

  /// Backward-compatible display string used by older sync/UI code.
  String get coordinatorName => _coordinators.join(', ');

  /// Fired after any group change so the cloud sync can push it.
  void Function()? onGroupsChanged;

  // -------- persistence -----------------------------------------------------
  // The whole workspace is saved to one JSON file so NOTHING is lost when the
  // app closes (it previously lived only in memory).
  bool _loaded = false;
  Timer? _saveTimer;

  Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/fyp_store.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final file = await _storeFile();
      if (!await file.exists()) return;
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map) return;
      List<T> readList<T>(String key, T Function(Map<dynamic, dynamic>) f) => [
        for (final e in (decoded[key] as List? ?? const []))
          if (e is Map) f(e),
      ];
      _submissions
        ..clear()
        ..addAll(readList('submissions', submissionFromMap));
      _ideas
        ..clear()
        ..addAll(readList('ideas', ideaFromMap));
      _allocations
        ..clear()
        ..addAll(readList('allocations', allocationFromMap));
      _proposals
        ..clear()
        ..addAll(readList('proposals', proposalFromMap));
      _evaluations
        ..clear()
        ..addAll(readList('evaluations', evaluationFromMap));
      _meetingLogs
        ..clear()
        ..addAll(readList('meetingLogs', meetingLogFromMap));
      _consents
        ..clear()
        ..addAll(readList('consents', consentFromMap));
      _srsDocuments
        ..clear()
        ..addAll(readList('srs', srsFromMap));
      _groups
        ..clear()
        ..addAll(readList('groups', FypGroup.fromJson));
      _panels
        ..clear()
        ..addAll(readList('panels', FypPanel.fromJson));
      _meetings
        ..clear()
        ..addAll(readList('meetings', FypMeeting.fromJson));
      _coordinators
        ..clear()
        ..addAll(_parseCoordinatorNames(decoded));
      notifyListeners();
    } catch (e) {
      // A corrupt store must never block startup.
      debugPrint('FYP store load failed: $e');
    }
  }

  Future<void> _persist() async {
    try {
      final file = await _storeFile();
      final payload = <String, Object?>{
        'v': 1,
        'coordinator': coordinatorName,
        'coordinators': _coordinators,
        'submissions': [for (final s in _submissions) submissionToMap(s)],
        'ideas': [for (final i in _ideas) ideaToMap(i)],
        'allocations': [for (final a in _allocations) allocationToMap(a)],
        'proposals': [for (final p in _proposals) proposalToMap(p)],
        'evaluations': [for (final e in _evaluations) evaluationToMap(e)],
        'meetingLogs': [for (final l in _meetingLogs) meetingLogToMap(l)],
        'consents': [for (final c in _consents) consentToMap(c)],
        'srs': [for (final s in _srsDocuments) srsToMap(s)],
        'groups': [for (final g in _groups) g.toJson()],
        'panels': [for (final p in _panels) p.toJson()],
        'meetings': [for (final m in _meetings) m.toJson()],
      };
      await file.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint('FYP store save failed: $e');
    }
  }

  /// Every notify also schedules a debounced save, so ALL existing mutators
  /// persist without touching each one.
  @override
  void notifyListeners() {
    super.notifyListeners();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persist());
    });
  }

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
    final index = _submissions.indexWhere(
      (submission) => submission.id == submissionId,
    );
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
    final index = _allocations.indexWhere(
      (allocation) => allocation.id == allocationId,
    );
    if (index == -1) {
      return;
    }
    final current = _allocations[index];
    final isSupervisor = _matchesTeacher(current.supervisorName, approverName);
    final isCoSupervisor = _matchesTeacher(
      current.coSupervisorName,
      approverName,
    );
    if (!isSupervisor && !isCoSupervisor) {
      return;
    }

    final now = DateTime.now();
    final supervisorApprovedAt = isSupervisor
        ? now
        : current.supervisorApprovedAt;
    final coSupervisorApprovedAt = isCoSupervisor
        ? now
        : current.coSupervisorApprovedAt;

    final hasSupervisor = supervisorApprovedAt != null;
    final hasCoSupervisor =
        current.coSupervisorName.trim().isEmpty ||
        coSupervisorApprovedAt != null;
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

  List<FypEvaluation> evaluationsForGroup(String groupId) {
    final id = groupId.trim();
    if (id.isEmpty) return const [];
    return _evaluations
        .where((evaluation) => evaluation.groupId.trim() == id)
        .toList(growable: false);
  }

  FypEvaluation createEvaluation({
    required FypEvaluationKind kind,
    String groupId = '',
    required String term,
    required String projectTitle,
    required String supervisorName,
    required String examinerName,
    required List<FypMember> members,
    required List<FypRubricRow> rubric,
    String remarks = '',
    FypPresentationDecision presentationDecision =
        FypPresentationDecision.completed,
  }) {
    final id = _newId(
      kind == FypEvaluationKind.proposal ? 'PEVAL' : 'SEVAL',
      _evaluations.length,
    );
    final evaluation = FypEvaluation(
      id: id,
      kind: kind,
      groupId: groupId.trim(),
      term: term,
      projectTitle: projectTitle,
      supervisorName: supervisorName,
      examinerName: examinerName,
      members: List.unmodifiable(members),
      rubric: List.unmodifiable(rubric),
      remarks: remarks.trim(),
      presentationDecision: presentationDecision,
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
          (consent) => _matchesTeacher(consent.supervisorName, teacherName),
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

  // ========================================================================
  // FYP Groups — allotment workflow (teacher/student create, coordinator
  // allots; examiners assigned per group)
  // ========================================================================
  bool isCoordinator(String name) {
    final n = name.trim().toLowerCase();
    return n.isNotEmpty &&
        _coordinators.any((c) => c.trim().toLowerCase() == n);
  }

  void setCoordinator(String name) {
    setCoordinators([name]);
  }

  void setCoordinators(Iterable<String> names) {
    _coordinators
      ..clear()
      ..addAll(_uniqueNames(names));
    notifyListeners();
    onGroupsChanged?.call();
  }

  FypGroup? groupForRollNo(String rollNo) {
    for (final g in _groups) {
      if (_matchesRollNo(g.members, rollNo) &&
          g.status != FypGroupStatus.rejected) {
        return g;
      }
    }
    for (final g in _groups) {
      if (_matchesRollNo(g.members, rollNo)) return g;
    }
    return null;
  }

  List<FypGroup> groupsForSupervisor(String teacherName) => _groups
      .where(
        (g) =>
            _matchesTeacher(g.supervisorName, teacherName) ||
            _matchesTeacher(g.coSupervisorName, teacherName),
      )
      .toList(growable: false);

  List<FypGroup> groupsForTeacher(String teacherName) => _groups
      .where(
        (g) =>
            g.status != FypGroupStatus.rejected &&
            (_matchesTeacher(g.supervisorName, teacherName) ||
                _matchesTeacher(g.coSupervisorName, teacherName) ||
                g.examiners.any((e) => _matchesTeacher(e, teacherName))),
      )
      .toList(growable: false);

  List<FypGroup> groupsWhereExaminer(String teacherName) => _groups
      .where(
        (g) =>
            g.status != FypGroupStatus.rejected &&
            g.examiners.any((e) => _matchesTeacher(e, teacherName)),
      )
      .toList(growable: false);

  FypGroup createGroup({
    required String title,
    required FypPhase phase,
    required FypProgram program,
    required String term,
    required List<FypMember> members,
    required String supervisorName,
    String coSupervisorName = '',
    required String createdByRole, // 'teacher' | 'student' | 'coordinator'
    required String createdByName,
  }) {
    final now = DateTime.now();
    // Cross-device-safe id (device time + count), unlike the count-only ids.
    final id = 'G${now.millisecondsSinceEpoch}';
    final FypGroupStatus status;
    String coordinatorBy = '';
    DateTime? coordinatorAt;
    String supervisorBy = '';
    DateTime? supervisorAt;
    switch (createdByRole) {
      case 'coordinator':
        // Coordinator allots directly.
        status = FypGroupStatus.approved;
        coordinatorBy = createdByName;
        coordinatorAt = now;
        supervisorBy = supervisorName;
        supervisorAt = now;
      case 'teacher':
        // Teacher creating implies supervisor consent → coordinator next.
        status = FypGroupStatus.pendingCoordinator;
        supervisorBy = createdByName;
        supervisorAt = now;
      default: // student
        status = FypGroupStatus.pendingSupervisor;
    }
    final group = FypGroup(
      id: id,
      title: title.trim(),
      phase: phase,
      program: program,
      term: term.trim(),
      members: List.unmodifiable(members),
      supervisorName: supervisorName.trim(),
      coSupervisorName: coSupervisorName.trim(),
      createdByRole: createdByRole,
      createdByName: createdByName.trim(),
      status: status,
      supervisorActionBy: supervisorBy,
      supervisorActionAt: supervisorAt,
      coordinatorActionBy: coordinatorBy,
      coordinatorActionAt: coordinatorAt,
      createdAt: now,
      updatedAt: now,
    );
    _groups.insert(0, group);
    notifyListeners();
    onGroupsChanged?.call();
    return group;
  }

  void _updateGroup(String groupId, FypGroup Function(FypGroup) change) {
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i == -1) return;
    _groups[i] = change(_groups[i]).copyWith(updatedAt: DateTime.now());
    notifyListeners();
    onGroupsChanged?.call();
  }

  /// Supervisor's decision on a student-created group.
  void supervisorDecision({
    required String groupId,
    required bool approve,
    required String byName,
    String reason = '',
  }) {
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        status: approve
            ? FypGroupStatus.pendingCoordinator
            : FypGroupStatus.rejected,
        supervisorActionBy: byName,
        supervisorActionAt: DateTime.now(),
        rejectedReason: approve ? '' : reason,
      ),
    );
  }

  /// Coordinator's decision — allots (or rejects) a group from ANY pending
  /// state, including skipping a missing supervisor approval.
  void coordinatorDecision({
    required String groupId,
    required bool approve,
    required String byName,
    String reason = '',
  }) {
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        status: approve ? FypGroupStatus.approved : FypGroupStatus.rejected,
        coordinatorActionBy: byName,
        coordinatorActionAt: DateTime.now(),
        rejectedReason: approve ? '' : reason,
      ),
    );
  }

  /// Admin/coordinator edit of a group's core details.
  void editGroup({
    required String groupId,
    String? title,
    String? term,
    String? supervisorName,
    String? coSupervisorName,
    FypPhase? phase,
    FypProgram? program,
  }) {
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        title: title,
        term: term,
        supervisorName: supervisorName,
        coSupervisorName: coSupervisorName,
        phase: phase,
        program: program,
      ),
    );
  }

  /// Student edit of their OWN group (allowed only before approval). Replaces
  /// all editable fields incl. members. Changing the supervisor resets the
  /// approval to "waiting for supervisor".
  void editGroupFull({
    required String groupId,
    required String title,
    required FypPhase phase,
    required FypProgram program,
    required String term,
    required List<FypMember> members,
    required String supervisorName,
    required String coSupervisorName,
  }) {
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        title: title,
        phase: phase,
        program: program,
        term: term,
        members: List.unmodifiable(members),
        supervisorName: supervisorName,
        coSupervisorName: coSupervisorName,
        status: FypGroupStatus.pendingSupervisor,
        supervisorActionBy: '',
        coordinatorActionBy: '',
        rejectedReason: '',
      ),
    );
  }

  /// Coordinator assigns the examiner teachers for a group.
  void setGroupExaminers({
    required String groupId,
    required List<String> examiners,
  }) {
    _updateGroup(
      groupId,
      (g) => g.copyWith(
        examiners: [
          for (final e in examiners)
            if (e.trim().isNotEmpty) e.trim(),
        ],
      ),
    );
  }

  void deleteGroup(String groupId) {
    _groups.removeWhere((g) => g.id == groupId);
    notifyListeners();
    onGroupsChanged?.call();
  }

  /// Cloud pull: merge groups keep-newest by updatedAt (id = identity), and
  /// adopt coordinator names from the cloud metadata.
  void applyCloudGroups(List<FypGroup> incoming, {String? coordinator}) {
    var changed = false;
    for (final g in incoming) {
      if (g.id.isEmpty) continue;
      final i = _groups.indexWhere((e) => e.id == g.id);
      if (i == -1) {
        _groups.insert(0, g);
        changed = true;
      } else if (g.updatedAt.isAfter(_groups[i].updatedAt)) {
        _groups[i] = g;
        changed = true;
      }
    }
    if (coordinator != null && coordinator.trim().isNotEmpty) {
      final incomingCoordinators = _uniqueNames(coordinator.split(','));
      if (!_sameCoordinatorList(_coordinators, incomingCoordinators)) {
        _coordinators
          ..clear()
          ..addAll(incomingCoordinators);
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  List<String> _parseCoordinatorNames(Map<dynamic, dynamic> decoded) {
    final rawList = decoded['coordinators'];
    if (rawList is List) {
      return _uniqueNames(rawList.map((e) => e.toString()));
    }
    return _uniqueNames((decoded['coordinator'] ?? '').toString().split(','));
  }

  List<String> _uniqueNames(Iterable<String> names) {
    final seen = <String>{};
    final result = <String>[];
    for (final raw in names) {
      final name = raw.trim();
      if (name.isEmpty) continue;
      final key = name.toLowerCase();
      if (seen.add(key)) result.add(name);
    }
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  bool _sameCoordinatorList(List<String> a, List<String> b) {
    if (a.length != b.length) return false;
    final left = _uniqueNames(a);
    final right = _uniqueNames(b);
    for (var i = 0; i < left.length; i++) {
      if (left[i].toLowerCase() != right[i].toLowerCase()) return false;
    }
    return true;
  }

  // ========================================================================
  // Serials, phase filtering, ungrouped students
  // ========================================================================
  /// Groups of a phase, oldest first (so serials are stable).
  List<FypGroup> groupsForPhase(FypPhase phase) {
    final list = _groups.where((g) => g.phase == phase).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return list;
  }

  /// 1-based serial of a group within its phase (stable by creation order).
  int serialOf(FypGroup group) {
    final list = groupsForPhase(group.phase);
    final i = list.indexWhere((g) => g.id == group.id);
    return i < 0 ? 0 : i + 1;
  }

  /// Rolls that are already in a non-rejected group.
  Set<String> groupedRolls() {
    final out = <String>{};
    for (final g in _groups) {
      if (g.status == FypGroupStatus.rejected) continue;
      for (final m in g.members) {
        final r = m.rollNo.trim().toLowerCase();
        if (r.isNotEmpty) out.add(r);
      }
    }
    return out;
  }

  /// Change a group's phase (fixes a student who picked the wrong FYP phase).
  void changeGroupPhase(String groupId, FypPhase phase) {
    _updateGroup(groupId, (g) => g.copyWith(phase: phase));
  }

  // ========================================================================
  // Examiner panels (reusable teacher sets) — item 2
  // ========================================================================
  FypPanel createPanel({required String name, required List<String> members}) {
    final now = DateTime.now();
    final panel = FypPanel(
      id: 'P${now.millisecondsSinceEpoch}',
      name: name.trim(),
      members: [
        for (final m in members)
          if (m.trim().isNotEmpty) m.trim(),
      ],
      createdAt: now,
      updatedAt: now,
    );
    _panels.insert(0, panel);
    notifyListeners();
    onPanelsChanged?.call();
    return panel;
  }

  void editPanel({
    required String panelId,
    String? name,
    List<String>? members,
  }) {
    final i = _panels.indexWhere((p) => p.id == panelId);
    if (i == -1) return;
    _panels[i] = _panels[i].copyWith(
      name: name,
      members: members == null
          ? null
          : [
              for (final m in members)
                if (m.trim().isNotEmpty) m.trim(),
            ],
    );
    notifyListeners();
    onPanelsChanged?.call();
  }

  void deletePanel(String panelId) {
    _panels.removeWhere((p) => p.id == panelId);
    notifyListeners();
    onPanelsChanged?.call();
  }

  /// Assigns a whole panel's teachers as the group's examiners in one tap.
  void assignPanelToGroup({required String groupId, required String panelId}) {
    final panel = _panels.where((p) => p.id == panelId).firstOrNull;
    if (panel == null) return;
    setGroupExaminers(groupId: groupId, examiners: panel.members);
  }

  void Function()? onPanelsChanged;

  void applyCloudPanels(List<FypPanel> incoming) {
    var changed = false;
    for (final p in incoming) {
      if (p.id.isEmpty) continue;
      final i = _panels.indexWhere((e) => e.id == p.id);
      if (i == -1) {
        _panels.insert(0, p);
        changed = true;
      } else if (p.updatedAt.isAfter(_panels[i].updatedAt)) {
        _panels[i] = p;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  // ========================================================================
  // Meetings (coordinator schedules → notification) — item 8
  // ========================================================================
  void Function()? onMeetingsChanged;

  FypMeeting createMeeting({
    required String title,
    required String date,
    FypPhase? phase,
    String groupId = '',
    String note = '',
    bool formRequired = false,
    String formName = '',
    required String createdBy,
  }) {
    final now = DateTime.now();
    final meeting = FypMeeting(
      id: 'MTG${now.millisecondsSinceEpoch}',
      title: title.trim(),
      date: date.trim(),
      phase: phase,
      groupId: groupId,
      note: note.trim(),
      formRequired: formRequired,
      formName: formName.trim(),
      createdBy: createdBy.trim(),
      createdAt: now,
      updatedAt: now,
    );
    _meetings.insert(0, meeting);
    notifyListeners();
    onMeetingsChanged?.call();
    return meeting;
  }

  void deleteMeeting(String meetingId) {
    _meetings.removeWhere((m) => m.id == meetingId);
    notifyListeners();
    onMeetingsChanged?.call();
  }

  void applyCloudMeetings(List<FypMeeting> incoming) {
    var changed = false;
    for (final m in incoming) {
      if (m.id.isEmpty) continue;
      final i = _meetings.indexWhere((e) => e.id == m.id);
      if (i == -1) {
        _meetings.insert(0, m);
        changed = true;
      } else if (m.updatedAt.isAfter(_meetings[i].updatedAt)) {
        _meetings[i] = m;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// Meetings that concern a student (their group's phase/group, or all).
  List<FypMeeting> meetingsForGroup(FypGroup? group) {
    return _meetings.where((m) {
      if (m.groupId.isNotEmpty) return group != null && m.groupId == group.id;
      if (m.phase != null) return group != null && m.phase == group.phase;
      return true; // all
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  /// Meetings a teacher should see (they supervise/examine a targeted group,
  /// or the meeting targets everyone).
  List<FypMeeting> meetingsForTeacher(String teacherName) {
    return _meetings.where((m) {
      if (m.groupId.isEmpty && m.phase == null) return true;
      final targets = _groups.where((g) {
        if (m.groupId.isNotEmpty) return g.id == m.groupId;
        return m.phase == null || g.phase == m.phase;
      });
      return targets.any(
        (g) =>
            _matchesTeacher(g.supervisorName, teacherName) ||
            _matchesTeacher(g.coSupervisorName, teacherName) ||
            g.examiners.any((e) => _matchesTeacher(e, teacherName)),
      );
    }).toList()..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
