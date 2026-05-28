import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../assessment/assessment_models.dart';
import '../ui/student_portal_shell.dart';
import 'fyp_allocation_pdf.dart';
import 'fyp_consent_pdf.dart';
import 'fyp_evaluation_pdf.dart';
import 'fyp_idea_pdf.dart';
import 'fyp_meeting_pdf.dart';
import 'fyp_models.dart';
import 'fyp_repository.dart';

/// Teacher-side FYP hub. Four tabs mirror the teacher actions:
///
/// 1. My Ideas         (form #2)  — publish project ideas, generate idea PDFs
/// 2. Allocations      (form #3)  — review allocations naming this faculty,
///                                  approve as supervisor or co-supervisor
/// 3. Meeting Logs     (form #14) — student-submitted Section 1's; supervisor
///                                  fills Section 2 inline
/// 4. Evaluations      (forms #8, #11) — record marks for proposal / SRS
class FypTeacherSection extends StatefulWidget {
  const FypTeacherSection({super.key, required this.teacher});

  final AssessmentTeacher teacher;

  @override
  State<FypTeacherSection> createState() => _FypTeacherSectionState();
}

class _FypTeacherSectionState extends State<FypTeacherSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FypRepository _repo = FypRepository.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('FYP Workspace'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: PortalColors.brandBlue,
              unselectedLabelColor: PortalColors.subtleText,
              indicatorColor: PortalColors.brandBlue,
              tabs: const [
                Tab(text: 'My Ideas'),
                Tab(text: 'Allocations'),
                Tab(text: 'Meeting Logs'),
                Tab(text: 'Evaluations'),
                Tab(text: 'Consent Forms'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _MyIdeasTab(teacher: widget.teacher, repo: _repo),
              _AllocationsReviewTab(teacher: widget.teacher, repo: _repo),
              _MeetingLogsReviewTab(teacher: widget.teacher, repo: _repo),
              _EvaluationsEntryTab(teacher: widget.teacher, repo: _repo),
              _ConsentFormsTab(teacher: widget.teacher, repo: _repo),
            ],
          ),
        );
      },
    );
  }
}

// ============================================================================
// Tab 1 — Faculty publishes FYP ideas
// ============================================================================
class _MyIdeasTab extends StatelessWidget {
  const _MyIdeasTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final myIdeas = repo.ideasForFaculty(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.lightbulb_outline_rounded,
          color: const Color(0xFFB45309),
          title: 'Publish FYP ideas',
          message:
              'Students browse your published ideas inside the student app. When a group picks one, they submit the allocation form naming you as supervisor.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.add_rounded),
          label: const Text('Publish new idea'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFFB45309),
          ),
        ),
        const SizedBox(height: 18),
        _ListHeading('My published ideas'),
        if (myIdeas.isEmpty)
          const _EmptyHint(text: 'No ideas published yet.')
        else
          for (final idea in myIdeas)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _IdeaCard(idea: idea),
            ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _IdeaFormPage(teacher: teacher, repo: repo),
      ),
    );
  }
}

class _IdeaCard extends StatelessWidget {
  const _IdeaCard({required this.idea});

  final FypIdea idea;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFFEC97A),
      header: Row(
        children: [
          const _Pill(
            label: 'IDEA',
            bg: Color(0xFFFFE8C8),
            fg: Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              idea.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(
            label: idea.takenByGroupId.isEmpty ? 'Open' : 'Claimed',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Domain: ${idea.projectDomain}',
              style: const TextStyle(fontSize: 12.5)),
          Text(
            idea.description,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (idea.tools.isNotEmpty)
            Text('Tools: ${idea.tools}',
                style: const TextStyle(fontSize: 12.5)),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypIdeaPdf(idea);
            await Printing.layoutPdf(
              name: '${idea.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypIdeaPdf(idea);
            await Printing.sharePdf(
              bytes: bytes,
              filename: '${idea.id}.pdf',
            );
          },
          icon: const Icon(Icons.share_rounded),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

class _IdeaFormPage extends StatefulWidget {
  const _IdeaFormPage({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  State<_IdeaFormPage> createState() => _IdeaFormPageState();
}

class _IdeaFormPageState extends State<_IdeaFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _domain = TextEditingController();
  final _description = TextEditingController();
  final _tools = TextEditingController();
  final _additionalInfo = TextEditingController();
  final _coSupervisor = TextEditingController();
  late final TextEditingController _term;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: _defaultTerm());
  }

  @override
  void dispose() {
    _title.dispose();
    _domain.dispose();
    _description.dispose();
    _tools.dispose();
    _additionalInfo.dispose();
    _coSupervisor.dispose();
    _term.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.repo.createIdea(
      facultyName: widget.teacher.name,
      facultyEmail: widget.teacher.email,
      supervisor: widget.teacher.name,
      coSupervisor: _coSupervisor.text.trim(),
      title: _title.text.trim(),
      projectDomain: _domain.text.trim(),
      description: _description.text.trim(),
      tools: _tools.text.trim(),
      additionalInfo: _additionalInfo.text.trim(),
      term: _term.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('New FYP Idea')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _FormCard(
              title: 'Project',
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'Title',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _domain,
                    decoration: const InputDecoration(
                      labelText: 'Project domain',
                      prefixIcon: Icon(Icons.category_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _description,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Description',
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _tools,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Tools and technologies',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _additionalInfo,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Additional information',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Supervisors',
              child: Column(
                children: [
                  TextFormField(
                    initialValue: widget.teacher.name,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor (you)',
                      prefixIcon: Icon(Icons.co_present_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _coSupervisor,
                    decoration: const InputDecoration(
                      labelText: 'Co-supervisor (optional)',
                      prefixIcon: Icon(Icons.groups_2_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Term',
              child: TextFormField(
                controller: _term,
                decoration: const InputDecoration(
                  labelText: 'Term',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.publish_rounded),
              label: const Text('Publish idea'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Tab 2 — Allocations naming this teacher (approve as supervisor / co-sup)
// ============================================================================
class _AllocationsReviewTab extends StatelessWidget {
  const _AllocationsReviewTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final mine = repo.allocationsForSupervisor(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.assignment_ind_outlined,
          color: const Color(0xFF0F766E),
          title: 'Allocation requests',
          message:
              'Allocation forms naming you as supervisor or co-supervisor are listed here. Approve to formalize the supervision.',
        ),
        const SizedBox(height: 14),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No allocation requests yet.')
        else
          for (final allocation in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AllocationReviewCard(
                allocation: allocation,
                teacher: teacher,
                onApprove: () => repo.approveAllocationAsSupervisor(
                  allocationId: allocation.id,
                  approverName: teacher.name,
                ),
              ),
            ),
      ],
    );
  }
}

class _AllocationReviewCard extends StatelessWidget {
  const _AllocationReviewCard({
    required this.allocation,
    required this.teacher,
    required this.onApprove,
  });

  final FypAllocation allocation;
  final AssessmentTeacher teacher;
  final VoidCallback onApprove;

  bool get _imSupervisor =>
      allocation.supervisorName.toLowerCase() == teacher.name.toLowerCase();
  bool get _imCoSupervisor =>
      allocation.coSupervisorName.toLowerCase() == teacher.name.toLowerCase();
  bool get _alreadyApproved {
    if (_imSupervisor && allocation.supervisorApprovedAt != null) return true;
    if (_imCoSupervisor && allocation.coSupervisorApprovedAt != null) {
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFA7F3D0),
      header: Row(
        children: [
          const _Pill(
            label: 'ALLOC',
            bg: Color(0xFFD1FAE5),
            fg: Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              allocation.projectTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(label: allocation.status.label),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Role: ${_imSupervisor ? 'Main Supervisor' : _imCoSupervisor ? 'Co-Supervisor' : '—'}',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 4),
          Text(
            'Members: ${allocation.members.map((m) => '${m.rollNo} ${m.name}').join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (allocation.expectedOutcome.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Expected outcome: ${allocation.expectedOutcome}',
                style: const TextStyle(fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        if (!_alreadyApproved)
          FilledButton.icon(
            onPressed: onApprove,
            icon: const Icon(Icons.verified_outlined),
            label: const Text('I agree to supervise'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypAllocationPdf(allocation);
            await Printing.layoutPdf(
              name: '${allocation.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('View PDF'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 3 — Meeting logs naming this teacher (fill Section 2)
// ============================================================================
class _MeetingLogsReviewTab extends StatelessWidget {
  const _MeetingLogsReviewTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final logs = repo.meetingLogsForSupervisor(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.event_note_outlined,
          color: const Color(0xFFB45309),
          title: 'Meeting log Section 2',
          message:
              'Students submit Section 1 before each meeting. Fill Section 2 (tasks assigned, next meeting date) to close the loop.',
        ),
        const SizedBox(height: 14),
        if (logs.isEmpty)
          const _EmptyHint(text: 'No meeting logs submitted yet.')
        else
          for (final log in logs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MeetingLogReviewCard(log: log, repo: repo),
            ),
      ],
    );
  }
}

class _MeetingLogReviewCard extends StatelessWidget {
  const _MeetingLogReviewCard({required this.log, required this.repo});

  final FypMeetingLog log;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFFFCF80),
      header: Row(
        children: [
          const _Pill(
            label: 'MEET',
            bg: Color(0xFFFEF3C7),
            fg: Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${log.projectTitle}  •  ${log.meetingDate}',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(
              label: log.isSupervisorFilled ? 'Closed' : 'Section 2 pending'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
              'Members: ${log.members.map((m) => '${m.rollNo} ${m.name}').join(', ')}',
              style: const TextStyle(fontSize: 12.5)),
          if (log.workDoneSinceLastMeeting.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Work done: ${log.workDoneSinceLastMeeting}',
                style: const TextStyle(fontSize: 12.5)),
          ],
          if (log.issuesToDiscuss.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Issues / tasks: ${log.issuesToDiscuss}',
                style: const TextStyle(fontSize: 12.5)),
          ],
          if (log.tasksAssigned.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Tasks assigned: ${log.tasksAssigned}',
                style: const TextStyle(fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        if (!log.isSupervisorFilled)
          FilledButton.icon(
            onPressed: () => _openSection2(context, log, repo),
            icon: const Icon(Icons.edit_note_rounded),
            label: const Text('Fill Section 2'),
          ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypMeetingLogPdf(log);
            await Printing.layoutPdf(
              name: '${log.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('View PDF'),
        ),
      ],
    );
  }

  Future<void> _openSection2(
    BuildContext context,
    FypMeetingLog log,
    FypRepository repo,
  ) async {
    final tasksController = TextEditingController(text: log.tasksAssigned);
    final nextController =
        TextEditingController(text: log.nextMeetingDate);
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Section 2 — Supervisor',
                    style: Theme.of(sheetContext).textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: tasksController,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Tasks assigned to students',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: nextController,
                    decoration: const InputDecoration(
                      labelText: 'Date of next meeting',
                    ),
                  ),
                  const SizedBox(height: 14),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(false),
                          child: const Text('Cancel'),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () =>
                              Navigator.of(sheetContext).pop(true),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Save'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
    if (saved == true) {
      repo.completeMeetingLog(
        logId: log.id,
        tasksAssigned: tasksController.text.trim(),
        nextMeetingDate: nextController.text.trim(),
      );
    }
    tasksController.dispose();
    nextController.dispose();
  }
}

// ============================================================================
// Tab 4 — Evaluations entry (Proposal #8 / SRS #11)
// ============================================================================
class _EvaluationsEntryTab extends StatelessWidget {
  const _EvaluationsEntryTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final entered = repo.evaluationsByExaminer(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.grade_outlined,
          color: const Color(0xFFB91C1C),
          title: 'Examiner evaluations',
          message:
              'Enter rubric scores for Proposal and SRS evaluations you examine. Students see the marks in their FYP tab immediately.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () =>
                  _openForm(context, FypEvaluationKind.proposal),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New Proposal Evaluation'),
            ),
            FilledButton.icon(
              onPressed: () => _openForm(context, FypEvaluationKind.srs),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New SRS Evaluation'),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ListHeading('My evaluations'),
        if (entered.isEmpty)
          const _EmptyHint(text: 'No evaluations recorded yet.')
        else
          for (final evaluation in entered)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EvaluationCard(evaluation: evaluation),
            ),
      ],
    );
  }

  Future<void> _openForm(
    BuildContext context,
    FypEvaluationKind kind,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EvaluationFormPage(
          kind: kind,
          teacher: teacher,
          repo: repo,
        ),
      ),
    );
  }
}

class _EvaluationCard extends StatelessWidget {
  const _EvaluationCard({required this.evaluation});

  final FypEvaluation evaluation;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFFCA5A5),
      header: Row(
        children: [
          _Pill(
            label: evaluation.kind.label.toUpperCase(),
            bg: const Color(0xFFFEE2E2),
            fg: const Color(0xFFB91C1C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              evaluation.projectTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(
              label: '${evaluation.marksObtained}/${evaluation.marksMax}'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supervisor: ${evaluation.supervisorName}',
              style: const TextStyle(fontSize: 12.5)),
          Text(
            'Submitted: ${DateFormat('dd MMM yyyy').format(evaluation.submittedAt)}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypEvaluationPdf(evaluation);
            await Printing.layoutPdf(
              name: '${evaluation.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download PDF'),
        ),
      ],
    );
  }
}

class _EvaluationFormPage extends StatefulWidget {
  const _EvaluationFormPage({
    required this.kind,
    required this.teacher,
    required this.repo,
  });

  final FypEvaluationKind kind;
  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  State<_EvaluationFormPage> createState() => _EvaluationFormPageState();
}

class _EvaluationFormPageState extends State<_EvaluationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _supervisor = TextEditingController();
  late final List<TextEditingController> _memberRolls;
  late final List<TextEditingController> _memberNames;
  late final TextEditingController _term;
  late List<FypRubricRow> _rubric;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: _defaultTerm());
    _memberRolls = [TextEditingController(), TextEditingController()];
    _memberNames = [TextEditingController(), TextEditingController()];
    _rubric = widget.kind == FypEvaluationKind.proposal
        ? defaultProposalRubric()
        : defaultSrsRubric();
  }

  @override
  void dispose() {
    _title.dispose();
    _supervisor.dispose();
    for (final controller in _memberRolls) {
      controller.dispose();
    }
    for (final controller in _memberNames) {
      controller.dispose();
    }
    _term.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.repo.createEvaluation(
      kind: widget.kind,
      term: _term.text.trim(),
      projectTitle: _title.text.trim(),
      supervisorName: _supervisor.text.trim(),
      examinerName: widget.teacher.name,
      members: [
        for (var i = 0; i < _memberRolls.length; i++)
          if (_memberRolls[i].text.trim().isNotEmpty)
            FypMember(
              serialNo: i + 1,
              rollNo: _memberRolls[i].text.trim(),
              name: _memberNames[i].text.trim(),
              email: '',
            ),
      ],
      rubric: _rubric,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final formTitle = '${widget.kind.label} Evaluation';
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: Text(formTitle)),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _FormCard(
              title: 'Project details',
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'FYP Title',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _supervisor,
                    decoration: const InputDecoration(
                      labelText: 'Supervised by',
                      prefixIcon: Icon(Icons.co_present_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _term,
                    decoration: const InputDecoration(
                      labelText: 'Term',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Group members',
              child: Column(
                children: [
                  for (var i = 0; i < _memberRolls.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _memberRolls[i],
                            decoration: InputDecoration(
                              labelText: 'Member ${i + 1} roll',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _memberNames[i],
                            decoration: InputDecoration(
                              labelText: 'Member ${i + 1} name',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Rubric scores (1–5)',
              child: Column(
                children: [
                  for (var i = 0; i < _rubric.length; i++)
                    _RubricRowEditor(
                      row: _rubric[i],
                      onScoreChanged: (score) {
                        setState(() {
                          _rubric = [..._rubric];
                          _rubric[i] = _rubric[i].copyWith(score: score);
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save evaluation'),
            ),
          ],
        ),
      ),
    );
  }
}

class _RubricRowEditor extends StatelessWidget {
  const _RubricRowEditor({required this.row, required this.onScoreChanged});

  final FypRubricRow row;
  final ValueChanged<int> onScoreChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${row.label}  (max ${row.maxMarks})',
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 6,
            children: [
              for (var i = 1; i <= 5; i++)
                ChoiceChip(
                  label: Text('$i'),
                  selected: row.score == i,
                  onSelected: (_) => onScoreChanged(i),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Tab 5 — Supervisor Consent Forms (Form #7)
// ============================================================================
class _ConsentFormsTab extends StatelessWidget {
  const _ConsentFormsTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final mine = repo.consentsForSupervisor(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF0F766E),
          title: 'Supervisor consent forms',
          message:
              'Sign a consent so your group can appear for an evaluation (Proposal Defense, SRS, SDS, Progress, Internal, External). The signed PDF is shared with the evaluation panel.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New consent form'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(height: 18),
        _ListHeading('Signed consents'),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No consents signed yet.')
        else
          for (final consent in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ConsentCard(consent: consent),
            ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _ConsentFormPage(teacher: teacher, repo: repo),
      ),
    );
  }
}

class _ConsentCard extends StatelessWidget {
  const _ConsentCard({required this.consent});

  final FypEvaluationConsent consent;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFA7F3D0),
      header: Row(
        children: [
          const _Pill(
            label: 'CONSENT',
            bg: Color(0xFFD1FAE5),
            fg: Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              consent.fypTitle,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(
              label: DateFormat('dd MMM yyyy').format(consent.signedAt)),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members: ${consent.members.map((m) => '${m.rollNo} ${m.name}').join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Program: ${consent.program.label}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final type in consent.approvedEvaluations)
                _Pill(
                  label: type.label,
                  bg: const Color(0xFFD1FAE5),
                  fg: const Color(0xFF0F766E),
                ),
            ],
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypConsentPdf(consent);
            await Printing.layoutPdf(
              name: '${consent.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypConsentPdf(consent);
            await Printing.sharePdf(
              bytes: bytes,
              filename: '${consent.id}.pdf',
            );
          },
          icon: const Icon(Icons.share_rounded),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

class _ConsentFormPage extends StatefulWidget {
  const _ConsentFormPage({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  State<_ConsentFormPage> createState() => _ConsentFormPageState();
}

class _ConsentFormPageState extends State<_ConsentFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  late final TextEditingController _term;
  final List<TextEditingController> _memberRolls = [
    TextEditingController(),
    TextEditingController(),
  ];
  final List<TextEditingController> _memberNames = [
    TextEditingController(),
    TextEditingController(),
  ];
  FypProgram _program = FypProgram.bscs;
  final Set<FypEvaluationType> _approved = {};

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: _defaultTerm());
  }

  @override
  void dispose() {
    _title.dispose();
    _term.dispose();
    for (final c in _memberRolls) {
      c.dispose();
    }
    for (final c in _memberNames) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_approved.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Select at least one evaluation to approve.')),
      );
      return;
    }
    widget.repo.createConsent(
      term: _term.text.trim(),
      fypTitle: _title.text.trim(),
      program: _program,
      supervisorName: widget.teacher.name,
      members: [
        for (var i = 0; i < _memberRolls.length; i++)
          if (_memberRolls[i].text.trim().isNotEmpty)
            FypMember(
              serialNo: i + 1,
              rollNo: _memberRolls[i].text.trim(),
              name: _memberNames[i].text.trim(),
              email: '',
            ),
      ],
      approvedEvaluations: _approved.toList(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Supervisor Consent Form')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _FormCard(
              title: 'Project',
              child: Column(
                children: [
                  TextFormField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'FYP Title',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _term,
                    decoration: const InputDecoration(
                      labelText: 'Term',
                      prefixIcon: Icon(Icons.calendar_today_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 12,
                    children: [
                      for (final program in FypProgram.values)
                        ChoiceChip(
                          label: Text(program.label),
                          selected: _program == program,
                          onSelected: (_) =>
                              setState(() => _program = program),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Group members',
              child: Column(
                children: [
                  for (var i = 0; i < _memberRolls.length; i++) ...[
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _memberRolls[i],
                            decoration: InputDecoration(
                              labelText: 'Member ${i + 1} roll',
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 2,
                          child: TextFormField(
                            controller: _memberNames[i],
                            decoration: InputDecoration(
                              labelText: 'Member ${i + 1} name',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Approve evaluations',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final type in FypEvaluationType.values)
                    FilterChip(
                      label: Text(type.label),
                      selected: _approved.contains(type),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _approved.add(type);
                          } else {
                            _approved.remove(type);
                          }
                        });
                      },
                    ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.draw_outlined),
              label: const Text('Sign consent & generate PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Shared widgets (mirror student-side helpers)
// ============================================================================
String _defaultTerm() {
  final now = DateTime.now();
  final season = now.month >= 1 && now.month <= 6 ? 'Spring' : 'Fall';
  return '$season ${now.year}';
}

String? _required(String? value) =>
    (value == null || value.trim().isEmpty) ? 'Required' : null;

class _IntroCard extends StatelessWidget {
  const _IntroCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color color;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color, color.withValues(alpha: 0.65)],
        ),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  message,
                  style: const TextStyle(
                    color: Color(0xFFEFF6FF),
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ListHeading extends StatelessWidget {
  const _ListHeading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
              color: PortalColors.textPrimary,
            ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label, required this.bg, required this.fg});

  final String label;
  final Color bg;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 11),
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          color: PortalColors.textPrimary,
        ),
      ),
    );
  }
}

class _RecordCard extends StatelessWidget {
  const _RecordCard({
    required this.borderColor,
    required this.header,
    required this.body,
    required this.actions,
  });

  final Color borderColor;
  final Widget header;
  final Widget body;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          header,
          const SizedBox(height: 10),
          body,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: actions),
          ],
        ],
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF6FF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.purpleBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: Color(0xFF6E27C5)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: PortalColors.subtleText),
            ),
          ),
        ],
      ),
    );
  }
}

class _FormCard extends StatelessWidget {
  const _FormCard({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: PortalColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
