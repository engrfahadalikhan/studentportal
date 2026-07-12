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
  final List<FypVivaSession> _vivaSessions = [];

  // Tombstones: id → deletedAt (ISO). A delete must REACH other devices, not
  // just vanish locally — without these, every other phone kept re-pushing the
  // deleted record back into the cloud forever (the "old group still shows"
  // bug). Persisted with the store and pushed to Firestore as `deleted` docs.
  final Map<String, String> _deletedGroups = {};
  final Map<String, String> _deletedPanels = {};
  final Map<String, String> _deletedMeetings = {};
  final Map<String, String> _deletedViva = {};

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
  List<FypVivaSession> get vivaSessions => List.unmodifiable(_vivaSessions);
  Map<String, String> get deletedGroupTombstones =>
      Map.unmodifiable(_deletedGroups);
  Map<String, String> get deletedPanelTombstones =>
      Map.unmodifiable(_deletedPanels);
  Map<String, String> get deletedVivaTombstones =>
      Map.unmodifiable(_deletedViva);
  Map<String, String> get deletedMeetingTombstones =>
      Map.unmodifiable(_deletedMeetings);

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
        ..addAll(
          // Self-heal groups saved with duplicate members by old versions.
          readList('groups', FypGroup.fromJson).map(_dedupGroup),
        );
      _panels
        ..clear()
        ..addAll(readList('panels', FypPanel.fromJson));
      _meetings
        ..clear()
        ..addAll(readList('meetings', FypMeeting.fromJson));
      _vivaSessions
        ..clear()
        ..addAll(readList('viva', FypVivaSession.fromJson));
      _coordinators
        ..clear()
        ..addAll(_parseCoordinatorNames(decoded));
      final deleted = decoded['deleted'];
      if (deleted is Map) {
        void readTombs(String key, Map<String, String> into) {
          final m = deleted[key];
          if (m is! Map) return;
          m.forEach((k, v) {
            final id = k.toString().trim();
            if (id.isNotEmpty) into[id] = v.toString();
          });
        }

        readTombs('groups', _deletedGroups);
        readTombs('panels', _deletedPanels);
        readTombs('meetings', _deletedMeetings);
        readTombs('viva', _deletedViva);
        // A tombstone must win over a record the store still carries.
        _groups.removeWhere(
          (g) => _tombstoneWins(_deletedGroups[g.id], g.updatedAt),
        );
        _panels.removeWhere(
          (p) => _tombstoneWins(_deletedPanels[p.id], p.updatedAt),
        );
        _meetings.removeWhere(
          (m) => _tombstoneWins(_deletedMeetings[m.id], m.updatedAt),
        );
        _vivaSessions.removeWhere(
          (v) => _tombstoneWins(_deletedViva[v.id], v.updatedAt),
        );
      }
      _migrateLegacyArtifactIds();
      _purgeKnownBadGroups();
      _purgeDuplicateMemberGroups();
      notifyListeners();
    } catch (e) {
      // A corrupt store must never block startup.
      debugPrint('FYP store load failed: $e');
    }
  }

  /// IDs of specific bad groups that leaked before the tombstone system
  /// existed and can't be cleaned from the cloud right now (Firestore quota).
  /// "Vision Gaurd" (G1783166042476) was deleted on an OLD app version, so no
  /// tombstone was ever created and every phone kept re-pulling it. Planting
  /// the tombstone on load removes it on every updated device at launch, and it
  /// is pushed to the cloud on the next sync. Tombstoning an id that no longer
  /// exists is a harmless no-op — safe even if the group is already gone.
  static const List<String> _knownBadGroupIds = ['G1783166042476'];

  void _purgeKnownBadGroups() {
    for (final id in _knownBadGroupIds) {
      _deletedGroups.putIfAbsent(id, () => DateTime.now().toIso8601String());
    }
    _groups.removeWhere((g) => _knownBadGroupIds.contains(g.id));
  }

  String _memberSetKey(FypGroup group) {
    final rolls = [
      for (final member in group.members)
        if (member.rollNo.trim().isNotEmpty) member.rollNo.trim().toLowerCase(),
    ]..sort();
    return rolls.join('|');
  }

  bool _purgeDuplicateMemberGroups() {
    final newestByMembers = <String, FypGroup>{};
    final duplicateIds = <String>{};
    for (final group in _groups) {
      if (group.status == FypGroupStatus.rejected) continue;
      final key = _memberSetKey(group);
      if (key.isEmpty) continue;
      final existing = newestByMembers[key];
      if (existing == null) {
        newestByMembers[key] = group;
        continue;
      }
      final groupWins =
          group.updatedAt.isAfter(existing.updatedAt) ||
          (group.updatedAt.isAtSameMomentAs(existing.updatedAt) &&
              group.createdAt.isAfter(existing.createdAt));
      if (groupWins) {
        duplicateIds.add(existing.id);
        newestByMembers[key] = group;
      } else {
        duplicateIds.add(group.id);
      }
    }
    if (duplicateIds.isEmpty) return false;
    final now = DateTime.now().toIso8601String();
    for (final id in duplicateIds) {
      _deletedGroups.putIfAbsent(id, () => now);
    }
    _groups.removeWhere((group) => duplicateIds.contains(group.id));
    return true;
  }

  /// One-time repair: legacy ids (PREFIX-2026-001, year+count) collide across
  /// devices. Records that never left this phone are safely renamed to a
  /// unique id so cloud sync can never merge two people's records into one.
  var _migSeq = 0;
  void _migrateLegacyArtifactIds() {
    final legacy = RegExp(r'^[A-Z]+-\d{4}-\d{3}$');
    String fresh(String id) =>
        '$id-${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}'
        '${_migSeq++}';
    List<T> fix<T>(
      List<T> list,
      String Function(T) idOf,
      Map<String, Object?> Function(T) toMap,
      T Function(Map<dynamic, dynamic>) fromMap,
    ) => [
      for (final e in list)
        legacy.hasMatch(idOf(e))
            ? fromMap(toMap(e)..['id'] = fresh(idOf(e)))
            : e,
    ];
    _submissions.setAll(
      0,
      fix(_submissions, (e) => e.id, submissionToMap, submissionFromMap),
    );
    _ideas.setAll(0, fix(_ideas, (e) => e.id, ideaToMap, ideaFromMap));
    _allocations.setAll(
      0,
      fix(_allocations, (e) => e.id, allocationToMap, allocationFromMap),
    );
    _proposals.setAll(
      0,
      fix(_proposals, (e) => e.id, proposalToMap, proposalFromMap),
    );
    _evaluations.setAll(
      0,
      fix(_evaluations, (e) => e.id, evaluationToMap, evaluationFromMap),
    );
    _meetingLogs.setAll(
      0,
      fix(_meetingLogs, (e) => e.id, meetingLogToMap, meetingLogFromMap),
    );
    _consents.setAll(
      0,
      fix(_consents, (e) => e.id, consentToMap, consentFromMap),
    );
    _srsDocuments.setAll(
      0,
      fix(_srsDocuments, (e) => e.id, srsToMap, srsFromMap),
    );
  }

  // -------- generic FYP artifact sync (submissions/ideas/allocations/
  // proposals/meeting logs/consents/SRS) ------------------------------------
  static const List<String> artifactKinds = [
    'submissions',
    'ideas',
    'allocations',
    'proposals',
    'meetinglogs',
    'consents',
    'srs',
  ];

  /// Fired after any artifact create/update so the cloud sync pushes it.
  /// (Wired through the notifyListeners override — spurious fires cost
  /// nothing because unchanged rows are filtered by the push cache.)
  void Function()? onArtifactsChanged;

  /// Rows for the cloud push (doc id = record id; content-hashed upstream).
  List<Map<String, Object?>> artifactRows(String kind) {
    List<Map<String, Object?>> pack<T>(
      List<T> list,
      String Function(T) idOf,
      Map<String, Object?> Function(T) toMap,
    ) => [
      for (final e in list)
        {'id': idOf(e), 'data': jsonEncode(toMap(e)), 'deleted': false},
    ];
    switch (kind) {
      case 'submissions':
        return pack(_submissions, (e) => e.id, submissionToMap);
      case 'ideas':
        return pack(_ideas, (e) => e.id, ideaToMap);
      case 'allocations':
        return pack(_allocations, (e) => e.id, allocationToMap);
      case 'proposals':
        return pack(_proposals, (e) => e.id, proposalToMap);
      case 'meetinglogs':
        return pack(_meetingLogs, (e) => e.id, meetingLogToMap);
      case 'consents':
        return pack(_consents, (e) => e.id, consentToMap);
      case 'srs':
        return pack(_srsDocuments, (e) => e.id, srsToMap);
    }
    return const [];
  }

  /// Cloud pull: add-if-missing by id; replace when the content differs (these
  /// records are edited in place by signing flows — last writer wins, and a
  /// device's own echo compares equal so nothing loops).
  void applyCloudArtifactMaps(String kind, List<Map<dynamic, dynamic>> maps) {
    var changed = false;
    void merge<T>(
      List<T> list,
      T Function(Map<dynamic, dynamic>) fromMap,
      Map<String, Object?> Function(T) toMap,
      String Function(T) idOf,
    ) {
      for (final m in maps) {
        final rec = fromMap(m);
        final id = idOf(rec);
        if (id.isEmpty) continue;
        final i = list.indexWhere((e) => idOf(e) == id);
        if (i == -1) {
          list.insert(0, rec);
          changed = true;
        } else if (jsonEncode(toMap(list[i])) != jsonEncode(toMap(rec))) {
          list[i] = rec;
          changed = true;
        }
      }
    }

    switch (kind) {
      case 'submissions':
        merge(_submissions, submissionFromMap, submissionToMap, (e) => e.id);
      case 'ideas':
        merge(_ideas, ideaFromMap, ideaToMap, (e) => e.id);
      case 'allocations':
        merge(_allocations, allocationFromMap, allocationToMap, (e) => e.id);
      case 'proposals':
        merge(_proposals, proposalFromMap, proposalToMap, (e) => e.id);
      case 'meetinglogs':
        merge(_meetingLogs, meetingLogFromMap, meetingLogToMap, (e) => e.id);
      case 'consents':
        merge(_consents, consentFromMap, consentToMap, (e) => e.id);
      case 'srs':
        merge(_srsDocuments, srsFromMap, srsToMap, (e) => e.id);
    }
    if (_purgeDuplicateMemberGroups()) changed = true;
    if (changed) notifyListeners();
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
        'viva': [for (final v in _vivaSessions) v.toJson()],
        'deleted': {
          'groups': _deletedGroups,
          'panels': _deletedPanels,
          'meetings': _deletedMeetings,
          'viva': _deletedViva,
        },
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
    onArtifactsChanged?.call();
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), () {
      unawaited(_persist());
    });
  }

  // -------- helpers --------------------------------------------------------
  String _newId(String prefix, int currentCount) {
    // Cross-device-safe: the old year+count form collided across phones
    // (every device's first record was e.g. FYP-2026-001), which would merge
    // DIFFERENT people's records once these sync through the cloud.
    return '$prefix-${DateTime.now().year}-'
        '${(currentCount + 1).toString().padLeft(3, '0')}-'
        '${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
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
    onEvaluationsChanged?.call();
    // Marks entered for the current group move the viva queue forward.
    _autoAdvanceVivaOnMarks(examinerName, groupId);
    return evaluation;
  }

  /// Fired after a new evaluation so the cloud sync pushes it (marks must
  /// reach the coordinator/admin phones and the students' read-only tab).
  void Function()? onEvaluationsChanged;

  /// Cloud pull: evaluations are insert-only (stable id, never edited), so the
  /// merge is simply add-if-missing.
  void applyCloudEvaluations(List<FypEvaluation> incoming) {
    var changed = false;
    for (final e in incoming) {
      if (e.id.isEmpty) continue;
      if (_evaluations.any((x) => x.id == e.id)) continue;
      _evaluations.insert(0, e);
      changed = true;
    }
    if (changed) notifyListeners();
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
    // Prefer the NEWEST matching group — after a delete + re-create, a device
    // that still carries the stale old group must show the new one.
    FypGroup? best;
    FypGroup? bestRejected;
    for (final g in _groups) {
      if (!_matchesRollNo(g.members, rollNo)) continue;
      if (g.status != FypGroupStatus.rejected) {
        if (best == null || g.updatedAt.isAfter(best.updatedAt)) best = g;
      } else {
        if (bestRejected == null ||
            g.updatedAt.isAfter(bestRejected.updatedAt)) {
          bestRejected = g;
        }
      }
    }
    return best ?? bestRejected;
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
      members: List.unmodifiable(_dedupMembers(members)),
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

  /// One student can never fill two member slots of the same group (a student
  /// once picked himself twice in the dropdown). Keeps the first occurrence
  /// per roll and re-numbers the serials.
  List<FypMember> _dedupMembers(List<FypMember> members) {
    final seen = <String>{};
    final out = <FypMember>[];
    for (final m in members) {
      final key = m.rollNo.trim().toLowerCase();
      if (key.isNotEmpty && !seen.add(key)) continue;
      out.add(
        FypMember(
          serialNo: out.length + 1,
          rollNo: m.rollNo,
          name: m.name,
          email: m.email,
          cgpa: m.cgpa,
          phone: m.phone,
        ),
      );
    }
    return out;
  }

  /// Returns the group with duplicate members removed, or the group untouched
  /// when it is already clean (so keep-newest timestamps stay meaningful).
  FypGroup _dedupGroup(FypGroup g) {
    final deduped = _dedupMembers(g.members);
    if (deduped.length == g.members.length) return g;
    return g.copyWith(members: List.unmodifiable(deduped));
  }

  void _updateGroup(String groupId, FypGroup Function(FypGroup) change) {
    final i = _groups.indexWhere((g) => g.id == groupId);
    if (i == -1) return;
    _groups[i] = _dedupGroup(
      change(_groups[i]).copyWith(updatedAt: DateTime.now()),
    );
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

  /// Full edit of a group's editable fields incl. members.
  ///
  /// A student editing their OWN group (before approval) resets the approval to
  /// "waiting for supervisor". The coordinator, who edits from the teacher tab,
  /// passes [keepApprovalIfSameSupervisor] so fixing a member on an already
  /// approved group does NOT force the whole approval to restart — the status is
  /// only reset when the supervisor actually changes (the new supervisor must
  /// then approve).
  void editGroupFull({
    required String groupId,
    required String title,
    required FypPhase phase,
    required FypProgram program,
    required String term,
    required List<FypMember> members,
    required String supervisorName,
    required String coSupervisorName,
    bool keepApprovalIfSameSupervisor = false,
  }) {
    _updateGroup(groupId, (g) {
      final supervisorChanged =
          g.supervisorName.trim().toLowerCase() !=
          supervisorName.trim().toLowerCase();
      final keepStatus = keepApprovalIfSameSupervisor && !supervisorChanged;
      final base = g.copyWith(
        title: title,
        phase: phase,
        program: program,
        term: term,
        members: List.unmodifiable(members),
        supervisorName: supervisorName,
        coSupervisorName: coSupervisorName,
      );
      if (keepStatus) return base;
      return base.copyWith(
        status: FypGroupStatus.pendingSupervisor,
        supervisorActionBy: '',
        coordinatorActionBy: '',
        rejectedReason: '',
      );
    });
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
    _deletedGroups[groupId] = DateTime.now().toIso8601String();
    _groups.removeWhere((g) => g.id == groupId);
    notifyListeners();
    onGroupsChanged?.call();
  }

  /// True when a tombstone timestamp exists and is not older than the
  /// record's own updatedAt (ties go to the tombstone — deletes must stick).
  bool _tombstoneWins(String? tombstoneTs, DateTime recordUpdatedAt) {
    if (tombstoneTs == null) return false;
    final ts = DateTime.tryParse(tombstoneTs);
    if (ts == null) return true;
    return !recordUpdatedAt.isAfter(ts);
  }

  /// Cloud pull of delete markers: records the tombstones and removes any
  /// matching local records (unless the record was re-created NEWER than the
  /// delete). This is what finally makes a delete reach every device.
  void applyCloudTombstones({
    Map<String, String> groups = const {},
    Map<String, String> panels = const {},
    Map<String, String> meetings = const {},
    Map<String, String> viva = const {},
  }) {
    var changed = false;
    void take(Map<String, String> incoming, Map<String, String> into) {
      incoming.forEach((id, ts) {
        if (id.isEmpty) return;
        final cur = into[id];
        if (cur == null || cur.compareTo(ts) < 0) {
          into[id] = ts;
          changed = true;
        }
      });
    }

    take(groups, _deletedGroups);
    take(panels, _deletedPanels);
    take(meetings, _deletedMeetings);
    take(viva, _deletedViva);
    final beforeCounts =
        _groups.length +
        _panels.length +
        _meetings.length +
        _vivaSessions.length;
    _groups.removeWhere(
      (g) => _tombstoneWins(_deletedGroups[g.id], g.updatedAt),
    );
    _panels.removeWhere(
      (p) => _tombstoneWins(_deletedPanels[p.id], p.updatedAt),
    );
    _meetings.removeWhere(
      (m) => _tombstoneWins(_deletedMeetings[m.id], m.updatedAt),
    );
    _vivaSessions.removeWhere(
      (v) => _tombstoneWins(_deletedViva[v.id], v.updatedAt),
    );
    if (beforeCounts !=
        _groups.length +
            _panels.length +
            _meetings.length +
            _vivaSessions.length) {
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Cloud pull: merge groups keep-newest by updatedAt (id = identity), and
  /// adopt coordinator names from the cloud metadata.
  void applyCloudGroups(List<FypGroup> incoming, {String? coordinator}) {
    var changed = false;
    for (final raw in incoming) {
      // Old app versions can push duplicate-member groups — clean on arrival.
      final g = _dedupGroup(raw);
      if (g.id.isEmpty) continue;
      // Never resurrect a deleted group from a stale device's re-push.
      if (_tombstoneWins(_deletedGroups[g.id], g.updatedAt)) continue;
      if (_deletedGroups.remove(g.id) != null) changed = true;
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
    _deletedPanels[panelId] = DateTime.now().toIso8601String();
    _panels.removeWhere((p) => p.id == panelId);
    notifyListeners();
    onPanelsChanged?.call();
  }

  /// Assigns a whole panel's teachers as the group's examiners in one tap.
  void assignPanelToGroup({required String groupId, required String panelId}) {
    assignPanelToGroups(groupIds: [groupId], panelId: panelId);
  }

  /// Assigns a whole panel to multiple groups in one save.
  void assignPanelToGroups({
    required Iterable<String> groupIds,
    required String panelId,
  }) {
    final panel = _panels.where((p) => p.id == panelId).firstOrNull;
    if (panel == null) return;
    final ids = groupIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet();
    if (ids.isEmpty) return;
    final examiners = [
      for (final member in panel.members)
        if (member.trim().isNotEmpty) member.trim(),
    ];
    var changed = false;
    final now = DateTime.now();
    for (var i = 0; i < _groups.length; i++) {
      if (!ids.contains(_groups[i].id)) continue;
      if (_sameCoordinatorList(_groups[i].examiners, examiners)) continue;
      _groups[i] = _dedupGroup(
        _groups[i].copyWith(examiners: examiners, updatedAt: now),
      );
      changed = true;
    }
    if (!changed) return;
    notifyListeners();
    onGroupsChanged?.call();
  }

  /// Groups whose examiner set matches this panel's members — i.e. the groups
  /// this panel has been assigned to examine. Sorted by phase then title.
  List<FypGroup> groupsForPanel(FypPanel panel) {
    final want = panel.members
        .map((e) => e.trim().toLowerCase())
        .where((e) => e.isNotEmpty)
        .toSet();
    if (want.isEmpty) return const [];
    final out = _groups.where((g) {
      final have = g.examiners
          .map((e) => e.trim().toLowerCase())
          .where((e) => e.isNotEmpty)
          .toSet();
      return have.length == want.length && have.containsAll(want);
    }).toList();
    out.sort((a, b) {
      final p = a.phase.index.compareTo(b.phase.index);
      return p != 0
          ? p
          : a.title.toLowerCase().compareTo(b.title.toLowerCase());
    });
    return out;
  }

  void Function()? onPanelsChanged;

  void applyCloudPanels(List<FypPanel> incoming) {
    var changed = false;
    for (final p in incoming) {
      if (p.id.isEmpty) continue;
      if (_tombstoneWins(_deletedPanels[p.id], p.updatedAt)) continue;
      if (_deletedPanels.remove(p.id) != null) changed = true;
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
    _deletedMeetings[meetingId] = DateTime.now().toIso8601String();
    _meetings.removeWhere((m) => m.id == meetingId);
    notifyListeners();
    onMeetingsChanged?.call();
  }

  void applyCloudMeetings(List<FypMeeting> incoming) {
    var changed = false;
    for (final m in incoming) {
      if (m.id.isEmpty) continue;
      if (_tombstoneWins(_deletedMeetings[m.id], m.updatedAt)) continue;
      if (_deletedMeetings.remove(m.id) != null) changed = true;
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

  // ========================================================================
  // Viva turn queue — the examiner's live calling order
  // ========================================================================
  void Function()? onVivaChanged;

  void _vivaTouched() {
    notifyListeners();
    onVivaChanged?.call();
  }

  FypVivaSession createVivaSession({
    required String examinerName,
    required String title,
    required int minutesPerGroup,
    required List<String> groupIds,
  }) {
    final now = DateTime.now();
    final session = FypVivaSession(
      id: 'VIVA${now.millisecondsSinceEpoch}',
      examinerName: examinerName.trim(),
      title: title.trim().isEmpty ? 'Viva' : title.trim(),
      minutesPerGroup: minutesPerGroup < 1 ? 15 : minutesPerGroup,
      groupIds: List.unmodifiable(groupIds),
      currentIndex: 0,
      status: 'running',
      startedAt: now,
      createdAt: now,
      updatedAt: now,
    );
    _vivaSessions.insert(0, session);
    _vivaTouched();
    return session;
  }

  void _updateViva(String id, FypVivaSession Function(FypVivaSession) change) {
    final i = _vivaSessions.indexWhere((v) => v.id == id);
    if (i == -1) return;
    _vivaSessions[i] = change(_vivaSessions[i]);
    _vivaTouched();
  }

  void updateVivaTiming({
    required String sessionId,
    int? minutesPerGroup,
    DateTime? startedAt,
    String? title,
  }) {
    _updateViva(
      sessionId,
      (v) => v.copyWith(
        title: title,
        minutesPerGroup: minutesPerGroup == null
            ? null
            : (minutesPerGroup < 1 ? 1 : minutesPerGroup),
        startedAt: startedAt,
      ),
    );
  }

  void shiftVivaStart(String sessionId, Duration delta) {
    _updateViva(
      sessionId,
      (v) => v.copyWith(startedAt: v.startedAt.add(delta)),
    );
  }

  /// Moves the queue to the next group; finishes the session after the last.
  void advanceViva(String sessionId) {
    _updateViva(sessionId, (v) {
      final next = v.currentIndex + 1;
      return next >= v.groupIds.length
          ? v.copyWith(currentIndex: next, status: 'finished')
          : v.copyWith(currentIndex: next);
    });
  }

  void finishViva(String sessionId) {
    _updateViva(sessionId, (v) => v.copyWith(status: 'finished'));
  }

  /// The current group is not ready (students late/absent): send it to the
  /// END of the queue and start the next group's turn immediately. The held
  /// group keeps its place in the session and gets a fresh estimated time.
  void holdCurrentViva(String sessionId) {
    _updateViva(sessionId, (v) {
      final ids = List<String>.of(v.groupIds);
      if (v.currentIndex >= ids.length - 1) return v; // nothing waiting after
      final held = ids.removeAt(v.currentIndex);
      ids.add(held);
      // currentIndex now points at what was the NEXT group.
      return v.copyWith(groupIds: List.unmodifiable(ids));
    });
  }

  /// Bring a WAITING group forward so it is called right after the current
  /// one (a group that arrived early / must leave soon). Done and current
  /// groups are left alone.
  void moveVivaGroupNext(String sessionId, String groupId) {
    _updateViva(sessionId, (v) {
      final ids = List<String>.of(v.groupIds);
      final from = ids.indexOf(groupId);
      if (from <= v.currentIndex) return v;
      final id = ids.removeAt(from);
      ids.insert(v.currentIndex + 1, id);
      return v.copyWith(groupIds: List.unmodifiable(ids));
    });
  }

  void moveVivaGroupEarlier(String sessionId, String groupId) {
    _updateViva(sessionId, (v) {
      final ids = List<String>.of(v.groupIds);
      final from = ids.indexOf(groupId);
      if (from <= v.currentIndex + 1) return v;
      final id = ids.removeAt(from);
      ids.insert(from - 1, id);
      return v.copyWith(groupIds: List.unmodifiable(ids));
    });
  }

  void moveVivaGroupLater(String sessionId, String groupId) {
    _updateViva(sessionId, (v) {
      final ids = List<String>.of(v.groupIds);
      final from = ids.indexOf(groupId);
      if (from <= v.currentIndex || from >= ids.length - 1) return v;
      final id = ids.removeAt(from);
      ids.insert(from + 1, id);
      return v.copyWith(groupIds: List.unmodifiable(ids));
    });
  }

  void deleteVivaSession(String sessionId) {
    _deletedViva[sessionId] = DateTime.now().toIso8601String();
    _vivaSessions.removeWhere((v) => v.id == sessionId);
    _vivaTouched();
  }

  void applyCloudVivaSessions(List<FypVivaSession> incoming) {
    var changed = false;
    for (final v in incoming) {
      if (v.id.isEmpty) continue;
      if (_tombstoneWins(_deletedViva[v.id], v.updatedAt)) continue;
      if (_deletedViva.remove(v.id) != null) changed = true;
      final i = _vivaSessions.indexWhere((e) => e.id == v.id);
      if (i == -1) {
        _vivaSessions.insert(0, v);
        changed = true;
      } else if (v.updatedAt.isAfter(_vivaSessions[i].updatedAt)) {
        _vivaSessions[i] = v;
        changed = true;
      }
    }
    if (changed) notifyListeners();
  }

  /// The examiner's most recent running session (one live queue at a time).
  FypVivaSession? runningVivaForExaminer(String examinerName) {
    for (final v in _vivaSessions) {
      if (v.isRunning && _matchesTeacher(v.examinerName, examinerName)) {
        return v;
      }
    }
    return null;
  }

  /// A running session this teacher is INVOLVED in: either they started it or
  /// they sit on the examining panel of any group in its queue. Panels examine
  /// jointly, so every member shares the same live queue.
  FypVivaSession? runningVivaInvolvingExaminer(String examinerName) {
    final own = runningVivaForExaminer(examinerName);
    if (own != null) return own;
    for (final v in _vivaSessions) {
      if (!v.isRunning) continue;
      for (final gid in v.groupIds) {
        final g = _groups.where((e) => e.id == gid).firstOrNull;
        if (g != null &&
            g.examiners.any((e) => _matchesTeacher(e, examinerName))) {
          return v;
        }
      }
    }
    return null;
  }

  /// The running queue that contains [groupId] (for the student banner),
  /// or null. Prefers the session where the group is still waiting/current.
  FypVivaSession? runningVivaForGroup(String groupId) {
    for (final v in _vivaSessions) {
      if (v.isRunning && v.groupIds.contains(groupId)) return v;
    }
    return null;
  }

  /// Marks entered for the CURRENT group of a running session auto-advance
  /// the turn — called from [createEvaluation]. Panels examine jointly, so the
  /// session OWNER or ANY examiner on the current group's panel advances the
  /// shared queue.
  void _autoAdvanceVivaOnMarks(String examinerName, String groupId) {
    final gid = groupId.trim();
    if (gid.isEmpty) return;
    for (final v in _vivaSessions) {
      if (!v.isRunning || v.currentGroupId != gid) continue;
      final g = _groups.where((e) => e.id == gid).firstOrNull;
      final onPanel =
          g != null && g.examiners.any((e) => _matchesTeacher(e, examinerName));
      if (_matchesTeacher(v.examinerName, examinerName) || onPanel) {
        advanceViva(v.id);
        return;
      }
    }
  }
}

extension _FirstOrNull<E> on Iterable<E> {
  E? get firstOrNull {
    final it = iterator;
    return it.moveNext() ? it.current : null;
  }
}
