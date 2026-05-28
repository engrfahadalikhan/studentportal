// ============================================================================
// FYP module shared types
// ============================================================================

enum FypPhase { fyp1, fyp2, fyp3 }

extension FypPhaseX on FypPhase {
  String get label {
    switch (this) {
      case FypPhase.fyp1:
        return 'FYP-I';
      case FypPhase.fyp2:
        return 'FYP-II';
      case FypPhase.fyp3:
        return 'FYP-III';
    }
  }

  String get longLabel {
    switch (this) {
      case FypPhase.fyp1:
        return 'Final Year Project I';
      case FypPhase.fyp2:
        return 'Final Year Project II';
      case FypPhase.fyp3:
        return 'Final Year Project III';
    }
  }
}

enum FypProgram { bscs, bsse }

extension FypProgramX on FypProgram {
  String get label {
    switch (this) {
      case FypProgram.bscs:
        return 'BSCS';
      case FypProgram.bsse:
        return 'BSSE';
    }
  }
}

enum FypProjectType { development, research, randd }

extension FypProjectTypeX on FypProjectType {
  String get label {
    switch (this) {
      case FypProjectType.development:
        return 'Development';
      case FypProjectType.research:
        return 'Research';
      case FypProjectType.randd:
        return 'R&D';
    }
  }
}

class FypMember {
  const FypMember({
    required this.serialNo,
    required this.rollNo,
    required this.name,
    required this.email,
    this.cgpa = '',
    this.phone = '',
  });

  final int serialNo;
  final String rollNo;
  final String name;
  final String email;
  final String cgpa;
  final String phone;
}

// ============================================================================
// Form #1: Group submission (student → teacher) — original
// ============================================================================

enum FypSupervisorStatus { pending, interested, declined }

extension FypSupervisorStatusX on FypSupervisorStatus {
  String get label {
    switch (this) {
      case FypSupervisorStatus.pending:
        return 'Pending';
      case FypSupervisorStatus.interested:
        return 'Interested';
      case FypSupervisorStatus.declined:
        return 'Declined';
    }
  }
}

class FypSubmission {
  const FypSubmission({
    required this.id,
    required this.qrCode,
    required this.phase,
    required this.program,
    required this.term,
    required this.members,
    required this.preferredSupervisor,
    required this.preferredCoSupervisor,
    required this.joinedWhatsApp,
    required this.joinedGoogleClassroom,
    required this.submittedAt,
    this.supervisorStatus = FypSupervisorStatus.pending,
    this.interestedSupervisorName = '',
  });

  final String id;
  final String qrCode;
  final FypPhase phase;
  final FypProgram program;
  final String term;
  final List<FypMember> members;
  final String preferredSupervisor;
  final String preferredCoSupervisor;
  final bool joinedWhatsApp;
  final bool joinedGoogleClassroom;
  final DateTime submittedAt;
  final FypSupervisorStatus supervisorStatus;
  final String interestedSupervisorName;

  FypSubmission copyWith({
    FypSupervisorStatus? supervisorStatus,
    String? interestedSupervisorName,
  }) {
    return FypSubmission(
      id: id,
      qrCode: qrCode,
      phase: phase,
      program: program,
      term: term,
      members: members,
      preferredSupervisor: preferredSupervisor,
      preferredCoSupervisor: preferredCoSupervisor,
      joinedWhatsApp: joinedWhatsApp,
      joinedGoogleClassroom: joinedGoogleClassroom,
      submittedAt: submittedAt,
      supervisorStatus: supervisorStatus ?? this.supervisorStatus,
      interestedSupervisorName:
          interestedSupervisorName ?? this.interestedSupervisorName,
    );
  }
}

// ============================================================================
// Form #2: FYP Idea (teacher → student catalog)
// ============================================================================

class FypIdea {
  const FypIdea({
    required this.id,
    required this.facultyName,
    required this.facultyEmail,
    required this.supervisor,
    required this.coSupervisor,
    required this.title,
    required this.projectDomain,
    required this.description,
    required this.tools,
    required this.additionalInfo,
    required this.term,
    required this.submittedAt,
    this.takenByGroupId = '',
  });

  final String id;
  final String facultyName;
  final String facultyEmail;
  final String supervisor;
  final String coSupervisor;
  final String title;
  final String projectDomain;
  final String description;
  final String tools;
  final String additionalInfo;
  final String term;
  final DateTime submittedAt;
  final String takenByGroupId;

  FypIdea copyWith({String? takenByGroupId}) {
    return FypIdea(
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
      submittedAt: submittedAt,
      takenByGroupId: takenByGroupId ?? this.takenByGroupId,
    );
  }
}

// ============================================================================
// Form #3: Supervisor Allocation (student fills, supervisor + co-sup sign)
// ============================================================================

enum FypAllocationStatus {
  pending,
  supervisorApproved,
  fullyApproved,
  rejected,
}

extension FypAllocationStatusX on FypAllocationStatus {
  String get label {
    switch (this) {
      case FypAllocationStatus.pending:
        return 'Pending';
      case FypAllocationStatus.supervisorApproved:
        return 'Supervisor approved';
      case FypAllocationStatus.fullyApproved:
        return 'Fully approved';
      case FypAllocationStatus.rejected:
        return 'Rejected';
    }
  }
}

class FypAllocation {
  const FypAllocation({
    required this.id,
    required this.qrCode,
    required this.term,
    required this.projectTitle,
    required this.expectedOutcome,
    required this.members,
    required this.supervisorName,
    required this.supervisorEmail,
    required this.coSupervisorName,
    required this.coSupervisorEmail,
    required this.submittedAt,
    this.status = FypAllocationStatus.pending,
    this.supervisorApprovedAt,
    this.coSupervisorApprovedAt,
  });

  final String id;
  final String qrCode;
  final String term;
  final String projectTitle;
  final String expectedOutcome;
  final List<FypMember> members;
  final String supervisorName;
  final String supervisorEmail;
  final String coSupervisorName;
  final String coSupervisorEmail;
  final DateTime submittedAt;
  final FypAllocationStatus status;
  final DateTime? supervisorApprovedAt;
  final DateTime? coSupervisorApprovedAt;

  FypAllocation copyWith({
    FypAllocationStatus? status,
    DateTime? supervisorApprovedAt,
    DateTime? coSupervisorApprovedAt,
  }) {
    return FypAllocation(
      id: id,
      qrCode: qrCode,
      term: term,
      projectTitle: projectTitle,
      expectedOutcome: expectedOutcome,
      members: members,
      supervisorName: supervisorName,
      supervisorEmail: supervisorEmail,
      coSupervisorName: coSupervisorName,
      coSupervisorEmail: coSupervisorEmail,
      submittedAt: submittedAt,
      status: status ?? this.status,
      supervisorApprovedAt: supervisorApprovedAt ?? this.supervisorApprovedAt,
      coSupervisorApprovedAt:
          coSupervisorApprovedAt ?? this.coSupervisorApprovedAt,
    );
  }
}

// ============================================================================
// Form #5: FYP Proposal (student-side metadata capture)
// ============================================================================

class FypProposal {
  const FypProposal({
    required this.id,
    required this.qrCode,
    required this.term,
    required this.projectId,
    required this.projectType,
    required this.areaOfSpecialization,
    required this.title,
    required this.members,
    required this.supervisorName,
    required this.supervisorDesignation,
    required this.coSupervisorName,
    required this.coSupervisorDesignation,
    required this.similarityIndex,
    required this.submittedAt,
  });

  final String id;
  final String qrCode;
  final String term;
  final String projectId;
  final FypProjectType projectType;
  final String areaOfSpecialization;
  final String title;
  final List<FypMember> members;
  final String supervisorName;
  final String supervisorDesignation;
  final String coSupervisorName;
  final String coSupervisorDesignation;
  final String similarityIndex;
  final DateTime submittedAt;
}

// ============================================================================
// Forms #8 + #11: Evaluation (Proposal / SRS) — shared rubric model
// ============================================================================

enum FypEvaluationKind { proposal, srs }

extension FypEvaluationKindX on FypEvaluationKind {
  String get label {
    switch (this) {
      case FypEvaluationKind.proposal:
        return 'Proposal';
      case FypEvaluationKind.srs:
        return 'SRS';
    }
  }
}

/// Each rubric dimension is scored 1–5.
class FypRubricRow {
  const FypRubricRow({
    required this.label,
    required this.maxMarks,
    this.score = 0,
  });

  final String label;
  final int maxMarks;
  final int score; // 1..5 inclusive once filled

  FypRubricRow copyWith({int? score}) {
    return FypRubricRow(
      label: label,
      maxMarks: maxMarks,
      score: score ?? this.score,
    );
  }
}

class FypEvaluation {
  const FypEvaluation({
    required this.id,
    required this.kind,
    required this.term,
    required this.projectTitle,
    required this.supervisorName,
    required this.examinerName,
    required this.members,
    required this.rubric,
    required this.submittedAt,
  });

  final String id;
  final FypEvaluationKind kind;
  final String term;
  final String projectTitle;
  final String supervisorName;
  final String examinerName;
  final List<FypMember> members;
  final List<FypRubricRow> rubric;
  final DateTime submittedAt;

  int get marksObtained =>
      rubric.fold<int>(0, (sum, row) => sum + row.score);

  int get marksMax => rubric.fold<int>(0, (sum, row) => sum + row.maxMarks);
}

/// Default rubric rows for Proposal Evaluation (Form #8).
List<FypRubricRow> defaultProposalRubric() {
  return const [
    FypRubricRow(label: 'Objective', maxMarks: 5),
    FypRubricRow(label: 'Problem Statement', maxMarks: 5),
    FypRubricRow(label: 'Related Work / Literature Survey', maxMarks: 10),
    FypRubricRow(label: 'Subject Knowledge', maxMarks: 5),
    FypRubricRow(label: 'Scope', maxMarks: 10),
    FypRubricRow(label: 'Modules and Functionalities', maxMarks: 5),
    FypRubricRow(label: 'Organization and Content of Presentation', maxMarks: 5),
    FypRubricRow(
        label: 'Technical Implementation (knowledge of required tools)',
        maxMarks: 5),
    FypRubricRow(label: 'Project Overview, Methodology', maxMarks: 5),
    FypRubricRow(label: 'Presentation skills', maxMarks: 5),
    FypRubricRow(
        label: 'Problem solving skills (Questions and Answers)', maxMarks: 5),
  ];
}

/// Default rubric rows for SRS Evaluation (Form #11).
List<FypRubricRow> defaultSrsRubric() {
  return const [
    FypRubricRow(label: 'Overall Product Description', maxMarks: 5),
    FypRubricRow(label: 'External Interface Requirements', maxMarks: 5),
    FypRubricRow(label: 'Functional Requirements', maxMarks: 5),
    FypRubricRow(label: 'Non-Functional Requirements', maxMarks: 5),
    FypRubricRow(label: 'Interface', maxMarks: 5),
    FypRubricRow(label: 'Use Cases', maxMarks: 5),
    FypRubricRow(label: 'UML Diagrams', maxMarks: 5),
    FypRubricRow(label: 'Presentation skills', maxMarks: 5),
    FypRubricRow(
        label: 'Problem solving skills (Questions and Answers)', maxMarks: 5),
  ];
}

// ============================================================================
// Form #7: Supervisor Consent Form (teacher fills, students see read-only)
// ============================================================================

enum FypEvaluationType {
  proposalDefense,
  srsEvaluation,
  sdsEvaluation,
  progressEvaluation,
  internalFinalEvaluation,
  externalEvaluation,
}

extension FypEvaluationTypeX on FypEvaluationType {
  String get label {
    switch (this) {
      case FypEvaluationType.proposalDefense:
        return 'Proposal Defense';
      case FypEvaluationType.srsEvaluation:
        return 'SRS evaluation';
      case FypEvaluationType.sdsEvaluation:
        return 'SDS evaluation';
      case FypEvaluationType.progressEvaluation:
        return 'Progress evaluation';
      case FypEvaluationType.internalFinalEvaluation:
        return 'Internal final evaluation';
      case FypEvaluationType.externalEvaluation:
        return 'External evaluation';
    }
  }
}

class FypEvaluationConsent {
  const FypEvaluationConsent({
    required this.id,
    required this.qrCode,
    required this.term,
    required this.fypTitle,
    required this.program,
    required this.supervisorName,
    required this.members,
    required this.approvedEvaluations,
    required this.signedAt,
  });

  final String id;
  final String qrCode;
  final String term;
  final String fypTitle;
  final FypProgram program;
  final String supervisorName;
  final List<FypMember> members;
  final List<FypEvaluationType> approvedEvaluations;
  final DateTime signedAt;
}

// ============================================================================
// Form #10: SRS Document (student writes following IEEE-style template)
// ============================================================================

class FypSrsSection {
  const FypSrsSection({required this.heading, required this.body});

  final String heading;
  final String body;
}

class FypSrs {
  const FypSrs({
    required this.id,
    required this.qrCode,
    required this.term,
    required this.title,
    required this.members,
    required this.supervisorName,
    required this.coSupervisorName,
    required this.overallDescription,
    required this.externalInterfaces,
    required this.functionalRequirements,
    required this.nonFunctionalRequirements,
    required this.interfaceRequirements,
    required this.useCases,
    required this.umlDiagramsNotes,
    required this.submittedAt,
  });

  final String id;
  final String qrCode;
  final String term;
  final String title;
  final List<FypMember> members;
  final String supervisorName;
  final String coSupervisorName;
  final String overallDescription;
  final String externalInterfaces;
  final String functionalRequirements;
  final String nonFunctionalRequirements;
  final String interfaceRequirements;
  final String useCases;
  final String umlDiagramsNotes;
  final DateTime submittedAt;

  List<FypSrsSection> get sections => [
        FypSrsSection(
          heading: '1. Overall Product Description',
          body: overallDescription,
        ),
        FypSrsSection(
          heading: '2. External Interface Requirements',
          body: externalInterfaces,
        ),
        FypSrsSection(
          heading: '3. Functional Requirements',
          body: functionalRequirements,
        ),
        FypSrsSection(
          heading: '4. Non-Functional Requirements',
          body: nonFunctionalRequirements,
        ),
        FypSrsSection(
          heading: '5. Interface Requirements',
          body: interfaceRequirements,
        ),
        FypSrsSection(heading: '6. Use Cases', body: useCases),
        FypSrsSection(
          heading: '7. UML Diagrams (notes)',
          body: umlDiagramsNotes,
        ),
      ];
}

// ============================================================================
// Form #14: Supervisor Meeting Log (collaborative — student + teacher sections)
// ============================================================================

class FypMeetingLog {
  const FypMeetingLog({
    required this.id,
    required this.term,
    required this.projectTitle,
    required this.supervisorName,
    required this.program,
    required this.members,
    required this.meetingDate,
    required this.previousMeetingDate,
    required this.workDoneSinceLastMeeting,
    required this.issuesToDiscuss,
    required this.studentSubmittedAt,
    // Section 2 — filled by supervisor:
    this.tasksAssigned = '',
    this.nextMeetingDate = '',
    this.supervisorSignedAt,
  });

  final String id;
  final String term;
  final String projectTitle;
  final String supervisorName;
  final FypProgram program;
  final List<FypMember> members;
  final String meetingDate;
  final String previousMeetingDate;
  final String workDoneSinceLastMeeting;
  final String issuesToDiscuss;
  final DateTime studentSubmittedAt;
  // Section 2:
  final String tasksAssigned;
  final String nextMeetingDate;
  final DateTime? supervisorSignedAt;

  bool get isSupervisorFilled =>
      supervisorSignedAt != null &&
      (tasksAssigned.trim().isNotEmpty || nextMeetingDate.trim().isNotEmpty);

  FypMeetingLog copyWith({
    String? tasksAssigned,
    String? nextMeetingDate,
    DateTime? supervisorSignedAt,
  }) {
    return FypMeetingLog(
      id: id,
      term: term,
      projectTitle: projectTitle,
      supervisorName: supervisorName,
      program: program,
      members: members,
      meetingDate: meetingDate,
      previousMeetingDate: previousMeetingDate,
      workDoneSinceLastMeeting: workDoneSinceLastMeeting,
      issuesToDiscuss: issuesToDiscuss,
      studentSubmittedAt: studentSubmittedAt,
      tasksAssigned: tasksAssigned ?? this.tasksAssigned,
      nextMeetingDate: nextMeetingDate ?? this.nextMeetingDate,
      supervisorSignedAt: supervisorSignedAt ?? this.supervisorSignedAt,
    );
  }
}
