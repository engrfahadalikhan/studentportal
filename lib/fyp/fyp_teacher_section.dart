import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';

import '../assessment/assessment_models.dart';
import '../assessment/registration_course_data.dart' as registration;
import '../services/cloud_sync_service.dart';
import '../services/login_store.dart';
import '../ui/student_portal_shell.dart';
import 'fyp_allocation_pdf.dart';
import 'fyp_groups_tabs.dart';
import 'fyp_consent_pdf.dart';
import 'fyp_evaluation_pdf.dart';
import 'fyp_group_models.dart';
import 'fyp_idea_pdf.dart';
import 'fyp_meeting_pdf.dart';
import 'fyp_models.dart';
import 'fyp_repository.dart';
import 'fyp_viva_page.dart';

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
    _tabController = TabController(length: 8, vsync: this);
    unawaited(_refreshFyp(force: false));
  }

  Future<void> _refreshFyp({bool force = true}) {
    return CloudSyncService.instance.pullFypWorkspace(force: force);
  }

  /// Every known teacher name (registration seed + custom logins + me) for
  /// the supervisor / coordinator / examiner dropdowns.
  List<String> _allTeacherNames() {
    final names = <String>{
      for (final t in registration.registrationTeachers) t.name,
      for (final c in LoginStore.instance.customTeachers()) c.name,
      widget.teacher.name,
    }..removeWhere((e) => e.trim().isEmpty);
    final list = names.toList()..sort();
    return list;
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
        final isCoordinator = _repo.isCoordinator(widget.teacher.name);
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('FYP Workspace'),
            actions: [
              IconButton(
                tooltip: 'Refresh FYP',
                onPressed: () => unawaited(_refreshFyp()),
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: PortalColors.brandBlue,
              unselectedLabelColor: PortalColors.subtleText,
              indicatorColor: PortalColors.brandBlue,
              tabs: const [
                Tab(text: 'Groups'),
                Tab(text: 'My FYP Students'),
                Tab(text: 'Examination'),
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
              isCoordinator
                  ? FypAdminGroupsPage(
                      title: 'FYP Groups (coordinator)',
                      actorName: widget.teacher.name,
                      allowCoordinatorAppointment: false,
                      embedInParent: true,
                    )
                  : FypTeacherGroupsTab(
                      teacherName: widget.teacher.name,
                      teacherNames: _allTeacherNames(),
                    ),
              _MyFypStudentsTab(teacher: widget.teacher, repo: _repo),
              _ExaminationTab(teacher: widget.teacher, repo: _repo),
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
// Tab 1 — My FYP students
// ============================================================================
class _MyFypStudentsTab extends StatelessWidget {
  const _MyFypStudentsTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final groups = repo.groupsForTeacher(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.school_outlined,
          color: const Color(0xFF047857),
          title: 'My FYP Students',
          message:
              'Students from the FYP groups where you are supervisor, co-supervisor, or examiner are listed here.',
        ),
        const SizedBox(height: 14),
        _ListHeading('Assigned FYP groups (${groups.length})'),
        if (groups.isEmpty)
          const _EmptyHint(text: 'No FYP students are assigned to you yet.')
        else
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MyFypStudentsCard(
                group: group,
                teacherName: teacher.name,
                evaluations: repo.evaluationsForGroup(group.id),
              ),
            ),
      ],
    );
  }
}

class _MyFypStudentsCard extends StatelessWidget {
  const _MyFypStudentsCard({
    required this.group,
    required this.teacherName,
    required this.evaluations,
  });

  final FypGroup group;
  final String teacherName;
  final List<FypEvaluation> evaluations;

  bool _sameTeacher(String a, String b) =>
      a.trim().toLowerCase() == b.trim().toLowerCase();

  String get _myRole {
    final roles = <String>[];
    if (_sameTeacher(group.supervisorName, teacherName)) {
      roles.add('Supervisor');
    }
    if (_sameTeacher(group.coSupervisorName, teacherName)) {
      roles.add('Co-supervisor');
    }
    if (group.examiners.any((e) => _sameTeacher(e, teacherName))) {
      roles.add('Examiner');
    }
    return roles.isEmpty ? 'Teacher' : roles.join(' / ');
  }

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFA7F3D0),
      header: Row(
        children: [
          _Pill(
            label: group.phase.label,
            bg: const Color(0xFFD1FAE5),
            fg: const Color(0xFF047857),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group.title.isEmpty ? '(untitled group)' : group.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(label: _myRole),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.program.label} - ${group.term} - ${group.status.label}',
            style: const TextStyle(
              fontSize: 12.5,
              color: PortalColors.subtleText,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Supervisor: ${group.supervisorName.isEmpty ? 'Not set' : group.supervisorName}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (group.coSupervisorName.isNotEmpty)
            Text(
              'Co-supervisor: ${group.coSupervisorName}',
              style: const TextStyle(fontSize: 12.5),
            ),
          if (group.examiners.isNotEmpty)
            Text(
              'Examiners: ${group.examiners.join(', ')}',
              style: const TextStyle(fontSize: 12.5),
            ),
          const SizedBox(height: 8),
          const Text(
            'Students',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          for (final member in group.members)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${member.serialNo}. ${member.rollNo}  ${member.name}',
                style: const TextStyle(fontSize: 12.5),
              ),
            ),
          if (evaluations.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Evaluation marks',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
            const SizedBox(height: 4),
            for (final evaluation in evaluations)
              Text(
                '${evaluation.kind.label}: ${evaluation.marksObtained}/${evaluation.marksMax} by ${evaluation.examinerName}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
          if (group.examiners.any((e) => e.trim().isNotEmpty)) ...[
            const SizedBox(height: 6),
            Builder(
              builder: (_) {
                final assigned = [
                  for (final e in group.examiners)
                    if (e.trim().isNotEmpty) e.trim(),
                ];
                final marked = {
                  for (final e in evaluations)
                    e.examinerName.trim().toLowerCase(),
                };
                final pending = [
                  for (final a in assigned)
                    if (!marked.contains(a.toLowerCase())) a,
                ];
                return Text(
                  'Examiners marked: ${assigned.length - pending.length} of '
                  '${assigned.length}'
                  '${pending.isEmpty ? '' : '  •  Pending: ${pending.join(', ')}'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PortalColors.subtleText,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ],
        ],
      ),
      actions: const [],
    );
  }
}

// ============================================================================
// Tab — Examination (panels the teacher examines + their students + viva queue)
// ============================================================================
class _ExaminationTab extends StatelessWidget {
  const _ExaminationTab({required this.teacher, required this.repo});

  final AssessmentTeacher teacher;
  final FypRepository repo;

  @override
  Widget build(BuildContext context) {
    final groups = repo.groupsWhereExaminer(teacher.name);
    final liveViva = repo.runningVivaInvolvingExaminer(teacher.name);
    final students = <String>{
      for (final g in groups)
        for (final m in g.members) m.rollNo.trim().toLowerCase(),
    }..removeWhere((e) => e.isEmpty);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.gavel_rounded,
          color: const Color(0xFFB45309),
          title: 'Examination',
          message:
              'The groups you sit on as an examiner (panel), and their '
              'students. Run the viva turn queue and enter marks from here.',
        ),
        const SizedBox(height: 14),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: liveViva != null
                  ? const Color(0xFF047857)
                  : const Color(0xFFB45309),
            ),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => FypVivaPage(examinerName: teacher.name),
              ),
            ),
            icon: const Icon(Icons.record_voice_over_rounded),
            label: Text(
              liveViva != null
                  ? 'Viva LIVE — open turn queue'
                  : 'Set up / start viva turn queue',
            ),
          ),
        ),
        const SizedBox(height: 16),
        _ListHeading(
          'My examiner panels (${groups.length} groups · ${students.length} students)',
        ),
        if (groups.isEmpty)
          const _EmptyHint(
            text:
                'You are not on any examiner panel yet. The FYP coordinator '
                'assigns examiners / panels from the Groups workspace.',
          )
        else
          for (final group in groups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExaminationGroupCard(
                group: group,
                teacher: teacher,
                repo: repo,
                isCurrentViva: liveViva?.currentGroupId == group.id,
              ),
            ),
      ],
    );
  }
}

class _ExaminationGroupCard extends StatelessWidget {
  const _ExaminationGroupCard({
    required this.group,
    required this.teacher,
    required this.repo,
    required this.isCurrentViva,
  });

  final FypGroup group;
  final AssessmentTeacher teacher;
  final FypRepository repo;
  final bool isCurrentViva;

  Future<void> _openForm(BuildContext context, FypEvaluationKind kind) {
    return Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _EvaluationFormPage(
          kind: kind,
          teacher: teacher,
          repo: repo,
          initialGroup: group,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mine = repo
        .evaluationsForGroup(group.id)
        .where(
          (e) =>
              e.examinerName.trim().toLowerCase() ==
              teacher.name.trim().toLowerCase(),
        )
        .toList(growable: false);
    final evaluated = mine.isNotEmpty;
    return _RecordCard(
      borderColor: isCurrentViva
          ? const Color(0xFF6EE7B7)
          : const Color(0xFFFCD9A5),
      header: Row(
        children: [
          _Pill(
            label: group.phase.label,
            bg: const Color(0xFFFEF3C7),
            fg: const Color(0xFFB45309),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group.title.isEmpty ? '(untitled group)' : group.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          if (isCurrentViva)
            const _StatusChip(label: 'ON THE FLOOR')
          else if (evaluated)
            const _StatusChip(label: 'Marked')
          else
            _StatusChip(label: '${group.members.length} students'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.program.label}'
            '${group.term.isEmpty ? '' : ' · ${group.term}'} · '
            'Supervisor: ${group.supervisorName.isEmpty ? '—' : group.supervisorName}',
            style: const TextStyle(
              fontSize: 12.5,
              color: PortalColors.subtleText,
            ),
          ),
          if (group.examiners.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Panel: ${group.examiners.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: Color(0xFFB45309),
              ),
            ),
          ],
          const SizedBox(height: 8),
          const Text(
            'Students',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
          ),
          for (final m in group.members)
            Text(
              '•  ${m.rollNo}  ${m.name}',
              style: const TextStyle(fontSize: 12.5),
            ),
          if (mine.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'My marks',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
            for (final e in mine)
              Text(
                '${e.kind.label}: ${e.marksObtained}/${e.marksMax} · ${e.presentationDecision.label}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => _openForm(context, FypEvaluationKind.proposal),
          icon: const Icon(Icons.assignment_outlined, size: 18),
          label: const Text('Proposal marks'),
        ),
        FilledButton.icon(
          onPressed: () => _openForm(context, FypEvaluationKind.srs),
          icon: const Icon(Icons.description_outlined, size: 18),
          label: const Text('SRS marks'),
        ),
      ],
    );
  }
}

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
          _StatusChip(label: idea.takenByGroupId.isEmpty ? 'Open' : 'Claimed'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Domain: ${idea.projectDomain}',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            idea.description,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (idea.tools.isNotEmpty)
            Text(
              'Tools: ${idea.tools}',
              style: const TextStyle(fontSize: 12.5),
            ),
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
            await Printing.sharePdf(bytes: bytes, filename: '${idea.id}.pdf');
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
                    decoration: const InputDecoration(labelText: 'Description'),
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
            'Role: ${_imSupervisor
                ? 'Main Supervisor'
                : _imCoSupervisor
                ? 'Co-Supervisor'
                : '—'}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 4),
          Text(
            'Members: ${allocation.members.map((m) => '${m.rollNo} ${m.name}').join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (allocation.expectedOutcome.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Expected outcome: ${allocation.expectedOutcome}',
              style: const TextStyle(fontSize: 12.5),
            ),
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
            label: log.isSupervisorFilled ? 'Closed' : 'Section 2 pending',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Members: ${log.members.map((m) => '${m.rollNo} ${m.name}').join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (log.workDoneSinceLastMeeting.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Work done: ${log.workDoneSinceLastMeeting}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
          if (log.issuesToDiscuss.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Issues / tasks: ${log.issuesToDiscuss}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
          if (log.tasksAssigned.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Tasks assigned: ${log.tasksAssigned}',
              style: const TextStyle(fontSize: 12.5),
            ),
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
    final nextController = TextEditingController(text: log.nextMeetingDate);
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
                    style: Theme.of(sheetContext).textTheme.titleLarge
                        ?.copyWith(fontWeight: FontWeight.w800),
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
                          onPressed: () => Navigator.of(sheetContext).pop(true),
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
    final examinerGroups = repo.groupsWhereExaminer(teacher.name);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.grade_outlined,
          color: const Color(0xFFB91C1C),
          title: 'Examiner evaluations',
          message:
              'Select one of your assigned examiner groups, enter marks and remarks, then close the presentation or request a re-presentation.',
        ),
        const SizedBox(height: 14),
        _ListHeading('My examiner groups (${examinerGroups.length})'),
        if (examinerGroups.isEmpty)
          const _EmptyHint(
            text:
                'No examiner groups are assigned to you yet. The FYP coordinator can assign examiners from the Groups workspace.',
          )
        else
          for (final group in examinerGroups)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ExaminerGroupEvaluationCard(
                group: group,
                teacher: teacher,
                repo: repo,
                onEvaluate: (kind) => _openForm(context, kind, group),
              ),
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
    FypGroup group,
  ) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _EvaluationFormPage(
          kind: kind,
          teacher: teacher,
          repo: repo,
          initialGroup: group,
        ),
      ),
    );
  }
}

class _ExaminerGroupEvaluationCard extends StatelessWidget {
  const _ExaminerGroupEvaluationCard({
    required this.group,
    required this.teacher,
    required this.repo,
    required this.onEvaluate,
  });

  final FypGroup group;
  final AssessmentTeacher teacher;
  final FypRepository repo;
  final ValueChanged<FypEvaluationKind> onEvaluate;

  @override
  Widget build(BuildContext context) {
    final existing = repo
        .evaluationsForGroup(group.id)
        .where(
          (evaluation) =>
              evaluation.examinerName.trim().toLowerCase() ==
              teacher.name.trim().toLowerCase(),
        )
        .toList(growable: false);
    return _RecordCard(
      borderColor: const Color(0xFFFCA5A5),
      header: Row(
        children: [
          _Pill(
            label: group.phase.label,
            bg: const Color(0xFFFEE2E2),
            fg: const Color(0xFFB91C1C),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              group.title.isEmpty ? '(untitled group)' : group.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(label: '${group.members.length} students'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${group.program.label} - ${group.term}',
            style: const TextStyle(
              fontSize: 12.5,
              color: PortalColors.subtleText,
            ),
          ),
          Text(
            'Supervisor: ${group.supervisorName}',
            style: const TextStyle(fontSize: 12.5),
          ),
          const SizedBox(height: 6),
          for (final member in group.members)
            Text(
              '${member.rollNo}  ${member.name}',
              style: const TextStyle(fontSize: 12.5),
            ),
          if (existing.isNotEmpty) ...[
            const SizedBox(height: 8),
            const Text(
              'Already recorded',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 12.5),
            ),
            for (final evaluation in existing)
              Text(
                '${evaluation.kind.label}: ${evaluation.marksObtained}/${evaluation.marksMax} - ${evaluation.presentationDecision.label}',
                style: const TextStyle(fontSize: 12),
              ),
          ],
        ],
      ),
      actions: [
        FilledButton.icon(
          onPressed: () => onEvaluate(FypEvaluationKind.proposal),
          icon: const Icon(Icons.assignment_outlined),
          label: const Text('Proposal marks'),
        ),
        FilledButton.icon(
          onPressed: () => onEvaluate(FypEvaluationKind.srs),
          icon: const Icon(Icons.description_outlined),
          label: const Text('SRS marks'),
        ),
      ],
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
            label: '${evaluation.marksObtained}/${evaluation.marksMax}',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supervisor: ${evaluation.supervisorName}',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            'Submitted: ${DateFormat('dd MMM yyyy').format(evaluation.submittedAt)}',
            style: const TextStyle(fontSize: 12.5),
          ),
          Text(
            'Presentation: ${evaluation.presentationDecision.label}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (evaluation.remarks.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Remarks: ${evaluation.remarks}',
              style: const TextStyle(fontSize: 12.5, height: 1.35),
            ),
          ],
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
    required this.initialGroup,
  });

  final FypEvaluationKind kind;
  final AssessmentTeacher teacher;
  final FypRepository repo;
  final FypGroup initialGroup;

  @override
  State<_EvaluationFormPage> createState() => _EvaluationFormPageState();
}

class _EvaluationFormPageState extends State<_EvaluationFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _supervisor = TextEditingController();
  final _remarks = TextEditingController();
  late final List<TextEditingController> _memberRolls;
  late final List<TextEditingController> _memberNames;
  late final TextEditingController _term;
  late final List<FypGroup> _examinerGroups;
  String _selectedGroupId = '';
  FypPresentationDecision _presentationDecision =
      FypPresentationDecision.completed;
  late List<FypRubricRow> _rubric;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: _defaultTerm());
    _memberRolls = [TextEditingController(), TextEditingController()];
    _memberNames = [TextEditingController(), TextEditingController()];
    _examinerGroups = widget.repo.groupsWhereExaminer(widget.teacher.name);
    _rubric = widget.kind == FypEvaluationKind.proposal
        ? defaultProposalRubric()
        : defaultSrsRubric();
    _applyGroup(widget.initialGroup);
  }

  @override
  void dispose() {
    _title.dispose();
    _supervisor.dispose();
    _remarks.dispose();
    for (final controller in _memberRolls) {
      controller.dispose();
    }
    for (final controller in _memberNames) {
      controller.dispose();
    }
    _term.dispose();
    super.dispose();
  }

  FypGroup? get _selectedGroup {
    for (final group in _examinerGroups) {
      if (group.id == _selectedGroupId) return group;
    }
    return null;
  }

  void _ensureMemberControllers(int count) {
    while (_memberRolls.length < count) {
      _memberRolls.add(TextEditingController());
      _memberNames.add(TextEditingController());
    }
  }

  void _applyGroup(FypGroup group) {
    _selectedGroupId = group.id;
    _title.text = group.title;
    _supervisor.text = group.supervisorName;
    _term.text = group.term.isEmpty ? _defaultTerm() : group.term;
    _ensureMemberControllers(group.members.length);
    for (var i = 0; i < _memberRolls.length; i++) {
      if (i < group.members.length) {
        _memberRolls[i].text = group.members[i].rollNo;
        _memberNames[i].text = group.members[i].name;
      } else {
        _memberRolls[i].clear();
        _memberNames[i].clear();
      }
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final group = _selectedGroup;
    if (group == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select an assigned FYP group first.')),
      );
      return;
    }
    widget.repo.createEvaluation(
      kind: widget.kind,
      groupId: group.id,
      term: _term.text.trim(),
      projectTitle: _title.text.trim(),
      supervisorName: _supervisor.text.trim(),
      examinerName: widget.teacher.name,
      members: group.members,
      rubric: _rubric,
      remarks: _remarks.text,
      presentationDecision: _presentationDecision,
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final formTitle = '${widget.kind.label} Evaluation';
    final selectedGroup = _selectedGroup;
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
                  DropdownButtonFormField<String>(
                    initialValue: _selectedGroupId,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Assigned FYP group',
                      prefixIcon: Icon(Icons.groups_outlined),
                    ),
                    items: [
                      for (final group in _examinerGroups)
                        DropdownMenuItem(
                          value: group.id,
                          child: Text(
                            group.title.isEmpty
                                ? '(untitled group)'
                                : group.title,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                    ],
                    onChanged: (groupId) {
                      FypGroup? group;
                      for (final candidate in _examinerGroups) {
                        if (candidate.id == groupId) {
                          group = candidate;
                          break;
                        }
                      }
                      final selected = group;
                      if (selected == null) return;
                      setState(() => _applyGroup(selected));
                    },
                    validator: (value) =>
                        value == null || value.isEmpty ? 'Required' : null,
                  ),
                  const SizedBox(height: 10),
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (selectedGroup == null)
                    const Text(
                      'Select an assigned group to load its students.',
                      style: TextStyle(color: PortalColors.subtleText),
                    )
                  else
                    for (final member in selectedGroup.members)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Container(
                              width: 28,
                              height: 28,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: const Color(0xFFFEE2E2),
                                borderRadius: BorderRadius.circular(999),
                              ),
                              child: Text(
                                '${member.serialNo}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFFB91C1C),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${member.rollNo}  ${member.name}',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                            ),
                          ],
                        ),
                      ),
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
            const SizedBox(height: 12),
            _FormCard(
              title: 'Examiner decision',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFormField(
                    controller: _remarks,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Examiner remarks',
                      prefixIcon: Icon(Icons.rate_review_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      ChoiceChip(
                        label: const Text('Presentation completed'),
                        selected:
                            _presentationDecision ==
                            FypPresentationDecision.completed,
                        onSelected: (_) => setState(
                          () => _presentationDecision =
                              FypPresentationDecision.completed,
                        ),
                      ),
                      ChoiceChip(
                        label: const Text('Re-presentation required'),
                        selected:
                            _presentationDecision ==
                            FypPresentationDecision.repeatRequired,
                        onSelected: (_) => setState(
                          () => _presentationDecision =
                              FypPresentationDecision.repeatRequired,
                        ),
                      ),
                    ],
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
            label: DateFormat('dd MMM yyyy').format(consent.signedAt),
          ),
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
          content: Text('Select at least one evaluation to approve.'),
        ),
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
                          onSelected: (_) => setState(() => _program = program),
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
