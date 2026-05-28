import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:printing/printing.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../ui/student_portal_shell.dart';
import 'fyp_allocation_pdf.dart';
import 'fyp_meeting_pdf.dart';
import 'fyp_models.dart';
import 'fyp_pdf_service.dart';
import 'fyp_proposal_pdf.dart';
import 'fyp_proposal_slides_pdf.dart';
import 'fyp_repository.dart';
import 'fyp_srs_pdf.dart';

/// Student-side FYP hub. Six tabs cover the full student workflow:
///
/// 1. Group Submission (form #1)  — student creates, supervisor confirms
/// 2. Browse Ideas    (form #2)   — read-only list of faculty-published ideas
/// 3. Allocation      (form #3)   — student fills, faculty signs in teacher app
/// 4. Proposal        (form #5)   — proposal cover sheet metadata + QR
/// 5. Meeting Log     (form #14)  — students fill Section 1, supervisor fills 2
/// 6. Evaluations     (forms #8 + #11) — read-only marks once examiners enter
class FypSection extends StatefulWidget {
  const FypSection({
    super.key,
    required this.repository,
    required this.student,
    required this.initialPhase,
  });

  final AppRepository repository;
  final StudentRecord student;
  final FypPhase initialPhase;

  @override
  State<FypSection> createState() => _FypSectionState();
}

class _FypSectionState extends State<FypSection>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  final FypRepository _fypRepository = FypRepository.instance;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _fypRepository,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('Final Year Project'),
            bottom: TabBar(
              controller: _tabController,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: PortalColors.brandBlue,
              unselectedLabelColor: PortalColors.subtleText,
              indicatorColor: PortalColors.brandBlue,
              tabs: const [
                Tab(text: 'Group Form'),
                Tab(text: 'Browse Ideas'),
                Tab(text: 'Allocation'),
                Tab(text: 'Proposal'),
                Tab(text: 'Meeting Log'),
                Tab(text: 'Evaluations'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabController,
            children: [
              _GroupSubmissionTab(
                student: widget.student,
                teacherNames: _teacherNames(),
                fypRepository: _fypRepository,
                initialPhase: widget.initialPhase,
              ),
              _BrowseIdeasTab(fypRepository: _fypRepository),
              _AllocationTab(
                student: widget.student,
                teacherNames: _teacherNames(),
                fypRepository: _fypRepository,
              ),
              _ProposalTab(
                student: widget.student,
                teacherNames: _teacherNames(),
                fypRepository: _fypRepository,
              ),
              _MeetingLogTab(
                student: widget.student,
                teacherNames: _teacherNames(),
                fypRepository: _fypRepository,
              ),
              _EvaluationsTab(
                student: widget.student,
                fypRepository: _fypRepository,
              ),
            ],
          ),
        );
      },
    );
  }

  List<String> _teacherNames() {
    final names = widget.repository.teachers.map((t) => t.name).toSet().toList()
      ..sort();
    return names;
  }
}

// ============================================================================
// Tab 1 — Group submission (the original FYP proforma)
// ============================================================================
class _GroupSubmissionTab extends StatelessWidget {
  const _GroupSubmissionTab({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
    required this.initialPhase,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;
  final FypPhase initialPhase;

  @override
  Widget build(BuildContext context) {
    final mySubmissions = fypRepository.submissionsForRollNo(student.rollNo);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.group_add_outlined,
          color: const Color(0xFF6E27C5),
          title: 'FYP group submission',
          message:
              'Form your two-person FYP group. After submitting, show the QR to a faculty member so they can mark themselves as interested supervisor.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final phase in FypPhase.values)
              FilledButton.icon(
                onPressed: () => _openForm(context, phase),
                icon: const Icon(Icons.note_add_outlined),
                label: Text(phase.longLabel),
                style: FilledButton.styleFrom(
                  backgroundColor: phase == initialPhase
                      ? PortalColors.brandBlue
                      : const Color(0xFF6E27C5),
                ),
              ),
          ],
        ),
        const SizedBox(height: 18),
        _ListHeading('My group submissions'),
        if (mySubmissions.isEmpty)
          const _EmptyHint(text: 'No FYP group submissions yet.')
        else
          for (final submission in mySubmissions)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SubmissionCard(submission: submission),
            ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context, FypPhase phase) async {
    final created = await Navigator.of(context).push<FypSubmission>(
      MaterialPageRoute(
        builder: (_) => _FypGroupFormPage(
          phase: phase,
          student: student,
          teacherNames: teacherNames,
          fypRepository: fypRepository,
        ),
      ),
    );
    if (context.mounted && created != null) {
      await _showQrSheet(context, created.qrCode,
          title: '${created.phase.label} — ${created.id}');
    }
  }
}

class _SubmissionCard extends StatelessWidget {
  const _SubmissionCard({required this.submission});

  final FypSubmission submission;

  @override
  Widget build(BuildContext context) {
    final dateLabel =
        DateFormat('dd MMM yyyy HH:mm').format(submission.submittedAt);
    return _RecordCard(
      borderColor: PortalColors.purpleBorder,
      header: Row(
        children: [
          _Pill(
            label: submission.phase.label,
            bg: const Color(0xFFEDE2FF),
            fg: const Color(0xFF6E27C5),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              submission.id,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
          _StatusChip(label: submission.supervisorStatus.label),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Submitted: $dateLabel',
            style: const TextStyle(
              color: PortalColors.subtleText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Members: ${submission.members.map((m) => m.rollNo).join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (submission.preferredSupervisor.isNotEmpty)
            Text('Preferred supervisor: ${submission.preferredSupervisor}',
                style: const TextStyle(fontSize: 12.5)),
          if (submission.preferredCoSupervisor.isNotEmpty)
            Text(
                'Preferred co-supervisor: ${submission.preferredCoSupervisor}',
                style: const TextStyle(fontSize: 12.5)),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () =>
              _showQrSheet(context, submission.qrCode, title: submission.id),
          icon: const Icon(Icons.qr_code_2_outlined),
          label: const Text('Show QR'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypProformaPdf(submission);
            await Printing.layoutPdf(
              name: '${submission.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypProformaPdf(submission);
            await Printing.sharePdf(
              bytes: bytes,
              filename: '${submission.id}.pdf',
            );
          },
          icon: const Icon(Icons.share_rounded),
          label: const Text('Share'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 2 — Browse faculty-published FYP ideas
// ============================================================================
class _BrowseIdeasTab extends StatelessWidget {
  const _BrowseIdeasTab({required this.fypRepository});

  final FypRepository fypRepository;

  @override
  Widget build(BuildContext context) {
    final ideas = fypRepository.availableIdeas();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.lightbulb_outline_rounded,
          color: const Color(0xFFB45309),
          title: 'Faculty project ideas',
          message:
              'Browse FYP ideas published by faculty. To pursue one, submit the supervisor allocation form naming the faculty as your main supervisor.',
        ),
        const SizedBox(height: 14),
        if (ideas.isEmpty)
          const _EmptyHint(
            text:
                'No faculty FYP ideas have been published yet. Check back after the call for ideas opens.',
          )
        else
          for (final idea in ideas)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _IdeaCard(idea: idea),
            ),
      ],
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
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Supervisor: ${idea.supervisor}',
            style: const TextStyle(fontSize: 12.5),
          ),
          if (idea.coSupervisor.isNotEmpty)
            Text(
              'Co-supervisor: ${idea.coSupervisor}',
              style: const TextStyle(fontSize: 12.5),
            ),
          if (idea.projectDomain.isNotEmpty)
            Text(
              'Domain: ${idea.projectDomain}',
              style: const TextStyle(fontSize: 12.5),
            ),
          const SizedBox(height: 6),
          Text(
            idea.description,
            style: const TextStyle(fontSize: 12.5, height: 1.4),
          ),
          if (idea.tools.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Tools: ${idea.tools}',
              style: const TextStyle(fontSize: 12.5),
            ),
          ],
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showQrSheet(context, idea.id, title: idea.title),
          icon: const Icon(Icons.qr_code_2_outlined),
          label: const Text('Show idea QR'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 3 — Supervisor allocation form
// ============================================================================
class _AllocationTab extends StatelessWidget {
  const _AllocationTab({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  Widget build(BuildContext context) {
    final mine = fypRepository.allocationsForRollNo(student.rollNo);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.assignment_ind_outlined,
          color: const Color(0xFF0F766E),
          title: 'Supervisor Allocation',
          message:
              'Fill the allocation form after a supervisor has agreed to take you. They (and the co-supervisor) approve it by scanning the QR in the teacher app.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('New allocation submission'),
          style: FilledButton.styleFrom(
            backgroundColor: const Color(0xFF0F766E),
          ),
        ),
        const SizedBox(height: 18),
        _ListHeading('My allocation submissions'),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No allocation forms submitted yet.')
        else
          for (final allocation in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _AllocationCard(allocation: allocation),
            ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context) async {
    final created = await Navigator.of(context).push<FypAllocation>(
      MaterialPageRoute(
        builder: (_) => _AllocationFormPage(
          student: student,
          teacherNames: teacherNames,
          fypRepository: fypRepository,
        ),
      ),
    );
    if (context.mounted && created != null) {
      await _showQrSheet(context, created.qrCode,
          title: 'Allocation ${created.id}');
    }
  }
}

class _AllocationCard extends StatelessWidget {
  const _AllocationCard({required this.allocation});

  final FypAllocation allocation;

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
          Text('Supervisor: ${allocation.supervisorName}',
              style: const TextStyle(fontSize: 12.5)),
          if (allocation.coSupervisorName.isNotEmpty)
            Text('Co-supervisor: ${allocation.coSupervisorName}',
                style: const TextStyle(fontSize: 12.5)),
          Text(
            'Members: ${allocation.members.map((m) => m.rollNo).join(', ')}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () => _showQrSheet(context, allocation.qrCode,
              title: allocation.id),
          icon: const Icon(Icons.qr_code_2_outlined),
          label: const Text('Show QR'),
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
          label: const Text('Download'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 4 — Proposal cover sheet
// ============================================================================
class _ProposalTab extends StatelessWidget {
  const _ProposalTab({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  Widget build(BuildContext context) {
    final mine = fypRepository.proposalsForRollNo(student.rollNo);
    final mySrs = fypRepository.srsForRollNo(student.rollNo);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.description_outlined,
          color: const Color(0xFF2948B7),
          title: 'Proposal cover sheet & SRS',
          message:
              'The proposal cover sheet captures project registration + plagiarism declaration. The SRS captures functional and non-functional requirements following the IEEE template.',
        ),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            FilledButton.icon(
              onPressed: () => _openProposalForm(context),
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('New proposal cover sheet'),
            ),
            FilledButton.icon(
              onPressed: () => _openSrsForm(context),
              icon: const Icon(Icons.article_outlined),
              label: const Text('Write SRS document'),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0F766E),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        _ListHeading('My proposals'),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No proposals submitted yet.')
        else
          for (final proposal in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _ProposalCard(proposal: proposal),
            ),
        const SizedBox(height: 18),
        _ListHeading('My SRS documents'),
        if (mySrs.isEmpty)
          const _EmptyHint(text: 'No SRS documents written yet.')
        else
          for (final srs in mySrs)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SrsCard(srs: srs),
            ),
      ],
    );
  }

  Future<void> _openProposalForm(BuildContext context) async {
    final created = await Navigator.of(context).push<FypProposal>(
      MaterialPageRoute(
        builder: (_) => _ProposalFormPage(
          student: student,
          teacherNames: teacherNames,
          fypRepository: fypRepository,
        ),
      ),
    );
    if (context.mounted && created != null) {
      await _showQrSheet(context, created.qrCode,
          title: 'Proposal ${created.id}');
    }
  }

  Future<void> _openSrsForm(BuildContext context) async {
    final created = await Navigator.of(context).push<FypSrs>(
      MaterialPageRoute(
        builder: (_) => _SrsFormPage(
          student: student,
          teacherNames: teacherNames,
          fypRepository: fypRepository,
        ),
      ),
    );
    if (context.mounted && created != null) {
      await _showQrSheet(context, created.qrCode,
          title: 'SRS ${created.id}');
    }
  }
}

class _SrsCard extends StatelessWidget {
  const _SrsCard({required this.srs});

  final FypSrs srs;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: const Color(0xFFA7F3D0),
      header: Row(
        children: [
          const _Pill(
            label: 'SRS',
            bg: Color(0xFFD1FAE5),
            fg: Color(0xFF0F766E),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              srs.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Supervisor: ${srs.supervisorName}',
              style: const TextStyle(fontSize: 12.5)),
          Text(
            'Sections written: ${srs.sections.where((s) => s.body.trim().isNotEmpty).length} / ${srs.sections.length}',
            style: const TextStyle(fontSize: 12.5),
          ),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypSrsPdf(srs);
            await Printing.layoutPdf(
              name: '${srs.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download SRS PDF'),
        ),
      ],
    );
  }
}

class _ProposalCard extends StatelessWidget {
  const _ProposalCard({required this.proposal});

  final FypProposal proposal;

  @override
  Widget build(BuildContext context) {
    return _RecordCard(
      borderColor: PortalColors.blueBorder,
      header: Row(
        children: [
          const _Pill(
            label: 'PROP',
            bg: Color(0xFFE8EDFF),
            fg: PortalColors.brandBlue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              proposal.title,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Type: ${proposal.projectType.label}',
              style: const TextStyle(fontSize: 12.5)),
          Text('Area: ${proposal.areaOfSpecialization}',
              style: const TextStyle(fontSize: 12.5)),
          Text('Supervisor: ${proposal.supervisorName}',
              style: const TextStyle(fontSize: 12.5)),
          if (proposal.similarityIndex.isNotEmpty)
            Text('Similarity index: ${proposal.similarityIndex}%',
                style: const TextStyle(fontSize: 12.5)),
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypProposalPdf(proposal);
            await Printing.layoutPdf(
              name: '${proposal.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Cover sheet PDF'),
        ),
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypProposalSlidesPdf(proposal);
            await Printing.layoutPdf(
              name: '${proposal.id}-slides.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.slideshow_outlined),
          label: const Text('Presentation slides'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 5 — Supervisor meeting log
// ============================================================================
class _MeetingLogTab extends StatelessWidget {
  const _MeetingLogTab({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  Widget build(BuildContext context) {
    final mine = fypRepository.meetingLogsForRollNo(student.rollNo);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.event_note_outlined,
          color: const Color(0xFFB45309),
          title: 'Supervisor meeting log',
          message:
              'Fill Section 1 BEFORE the meeting. The supervisor fills Section 2 (tasks assigned, next meeting date) in the teacher app.',
        ),
        const SizedBox(height: 14),
        FilledButton.icon(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.note_add_outlined),
          label: const Text('Log a new meeting'),
        ),
        const SizedBox(height: 18),
        _ListHeading('My meetings'),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No meetings logged yet.')
        else
          for (final log in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _MeetingCard(log: log),
            ),
      ],
    );
  }

  Future<void> _openForm(BuildContext context) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _MeetingLogFormPage(
          student: student,
          teacherNames: teacherNames,
          fypRepository: fypRepository,
        ),
      ),
    );
  }
}

class _MeetingCard extends StatelessWidget {
  const _MeetingCard({required this.log});

  final FypMeetingLog log;

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
            label: log.isSupervisorFilled ? 'Completed' : 'Awaiting supervisor',
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (log.workDoneSinceLastMeeting.isNotEmpty)
            Text('Work done: ${log.workDoneSinceLastMeeting}',
                style: const TextStyle(fontSize: 12.5)),
          if (log.tasksAssigned.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Tasks assigned: ${log.tasksAssigned}',
                style: const TextStyle(fontSize: 12.5)),
          ],
          if (log.nextMeetingDate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('Next meeting: ${log.nextMeetingDate}',
                style: const TextStyle(fontSize: 12.5)),
          ],
        ],
      ),
      actions: [
        OutlinedButton.icon(
          onPressed: () async {
            final bytes = await buildFypMeetingLogPdf(log);
            await Printing.layoutPdf(
              name: '${log.id}.pdf',
              onLayout: (_) async => bytes,
            );
          },
          icon: const Icon(Icons.download_rounded),
          label: const Text('Download'),
        ),
      ],
    );
  }
}

// ============================================================================
// Tab 6 — Evaluations (read-only marks set by examiners)
// ============================================================================
class _EvaluationsTab extends StatelessWidget {
  const _EvaluationsTab({
    required this.student,
    required this.fypRepository,
  });

  final StudentRecord student;
  final FypRepository fypRepository;

  @override
  Widget build(BuildContext context) {
    final mine = fypRepository.evaluationsForRollNo(student.rollNo);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        _IntroCard(
          icon: Icons.grade_outlined,
          color: const Color(0xFFB91C1C),
          title: 'Evaluations',
          message:
              'Marks entered by your evaluation panel appear here once they finish. Both Proposal and SRS evaluations are listed.',
        ),
        const SizedBox(height: 14),
        if (mine.isEmpty)
          const _EmptyHint(text: 'No evaluations have been recorded yet.')
        else
          for (final evaluation in mine)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _EvaluationCard(evaluation: evaluation),
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
              label: '${evaluation.marksObtained}/${evaluation.marksMax}'),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Examiner: ${evaluation.examinerName}',
              style: const TextStyle(fontSize: 12.5)),
          Text('Supervised by: ${evaluation.supervisorName}',
              style: const TextStyle(fontSize: 12.5)),
          const SizedBox(height: 6),
          for (final row in evaluation.rubric)
            Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                '${row.label}  —  ${row.score}/${row.maxMarks}',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      actions: const [],
    );
  }
}

// ============================================================================
// Shared widgets (cards, pills, headings, hints)
// ============================================================================
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

// ============================================================================
// Group submission form page (preserved from the original implementation)
// ============================================================================
class _FypGroupFormPage extends StatefulWidget {
  const _FypGroupFormPage({
    required this.phase,
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final FypPhase phase;
  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  State<_FypGroupFormPage> createState() => _FypGroupFormPageState();
}

class _FypGroupFormPageState extends State<_FypGroupFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final List<_MemberInputs> _members;
  late final TextEditingController _termController;
  FypProgram _program = FypProgram.bscs;
  String? _supervisor;
  String? _coSupervisor;
  bool _joinedWhatsApp = false;
  bool _joinedGoogleClassroom = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _program = widget.student.program.toLowerCase().contains('se')
        ? FypProgram.bsse
        : FypProgram.bscs;
    _termController = TextEditingController(text: _defaultTerm());
    _members = [
      _MemberInputs.seeded(
        rollNo: widget.student.rollNo,
        name: widget.student.studentName,
      ),
      _MemberInputs.seeded(),
    ];
  }

  @override
  void dispose() {
    _termController.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _saving = true);
    final submission = widget.fypRepository.createSubmission(
      phase: widget.phase,
      program: _program,
      term: _termController.text.trim().isEmpty
          ? _defaultTerm()
          : _termController.text.trim(),
      members: [
        for (var i = 0; i < _members.length; i++)
          FypMember(
            serialNo: i + 1,
            rollNo: _members[i].rollNo.text.trim(),
            name: _members[i].name.text.trim(),
            email: _members[i].email.text.trim(),
          ),
      ],
      preferredSupervisor: _supervisor ?? '',
      preferredCoSupervisor: _coSupervisor ?? '',
      joinedWhatsApp: _joinedWhatsApp,
      joinedGoogleClassroom: _joinedGoogleClassroom,
    );
    if (mounted) Navigator.of(context).pop(submission);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: Text('${widget.phase.label} Group Submission')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          children: [
            _FormCard(
              title: 'Program',
              child: Wrap(
                spacing: 16,
                children: [
                  for (final program in FypProgram.values)
                    ChoiceChip(
                      label: Text(program.label),
                      selected: _program == program,
                      onSelected: (_) => setState(() => _program = program),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Term',
              child: TextFormField(
                controller: _termController,
                decoration: const InputDecoration(
                  labelText: 'Term',
                  prefixIcon: Icon(Icons.calendar_today_outlined),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Group members (1 or 2)',
              child: Column(
                children: [
                  for (var index = 0; index < _members.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _MemberInputCard(
                        memberIndex: index + 1,
                        inputs: _members[index],
                        requiredFirst: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Supervision preference',
              child: Column(
                children: [
                  _teacherDropdown(
                    'Preferred Supervisor',
                    _supervisor,
                    (v) => setState(() => _supervisor = v),
                  ),
                  const SizedBox(height: 10),
                  _teacherDropdown(
                    'Preferred Co-supervisor',
                    _coSupervisor,
                    (v) => setState(() => _coSupervisor = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Checklist',
              child: Column(
                children: [
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _joinedWhatsApp,
                    onChanged: (v) =>
                        setState(() => _joinedWhatsApp = v ?? false),
                    title: Text(
                      'I have joined WhatsApp group for ${widget.phase.label}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _joinedGoogleClassroom,
                    onChanged: (v) =>
                        setState(() => _joinedGoogleClassroom = v ?? false),
                    title: Text(
                      'I have joined Google Classroom for ${widget.phase.label}',
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _saving ? null : _submit,
              icon: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.qr_code_2_outlined),
              label: Text(_saving ? 'Saving...' : 'Submit & Generate QR'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teacherDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.co_present_outlined),
      ),
      items: [
        const DropdownMenuItem<String>(
            value: null, child: Text('Not selected')),
        for (final name in widget.teacherNames)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// Allocation form page
// ============================================================================
class _AllocationFormPage extends StatefulWidget {
  const _AllocationFormPage({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  State<_AllocationFormPage> createState() => _AllocationFormPageState();
}

class _AllocationFormPageState extends State<_AllocationFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _termController;
  late final TextEditingController _titleController;
  late final TextEditingController _outcomeController;
  late final TextEditingController _supEmailController;
  late final TextEditingController _coSupEmailController;
  String? _supervisor;
  String? _coSupervisor;
  late final List<_MemberInputs> _members;

  @override
  void initState() {
    super.initState();
    _termController = TextEditingController(text: _defaultTerm());
    _titleController = TextEditingController();
    _outcomeController = TextEditingController();
    _supEmailController = TextEditingController();
    _coSupEmailController = TextEditingController();
    _members = [
      _MemberInputs.seeded(
        rollNo: widget.student.rollNo,
        name: widget.student.studentName,
      ),
      _MemberInputs.seeded(),
    ];
  }

  @override
  void dispose() {
    _termController.dispose();
    _titleController.dispose();
    _outcomeController.dispose();
    _supEmailController.dispose();
    _coSupEmailController.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    if (_supervisor == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a main supervisor.')),
      );
      return;
    }
    final allocation = widget.fypRepository.createAllocation(
      term: _termController.text.trim(),
      projectTitle: _titleController.text.trim(),
      expectedOutcome: _outcomeController.text.trim(),
      members: [
        for (var i = 0; i < _members.length; i++)
          FypMember(
            serialNo: i + 1,
            rollNo: _members[i].rollNo.text.trim(),
            name: _members[i].name.text.trim(),
            email: _members[i].email.text.trim(),
            cgpa: _members[i].cgpa.text.trim(),
          ),
      ],
      supervisorName: _supervisor ?? '',
      supervisorEmail: _supEmailController.text.trim(),
      coSupervisorName: _coSupervisor ?? '',
      coSupervisorEmail: _coSupEmailController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(allocation);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Supervisor Allocation')),
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
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Project Title',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _outcomeController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText:
                          'Expected Outcome (e.g. Mobile app, Hardware...)',
                      prefixIcon: Icon(Icons.bolt_outlined),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _termController,
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
                  for (var index = 0; index < _members.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberInputCard(
                        memberIndex: index + 1,
                        inputs: _members[index],
                        showCgpa: true,
                        requiredFirst: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Main Supervisor',
              child: Column(
                children: [
                  _teacherDropdown(
                    'Supervisor name',
                    _supervisor,
                    (v) => setState(() => _supervisor = v),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _supEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Co-Supervisor (optional)',
              child: Column(
                children: [
                  _teacherDropdown(
                    'Co-supervisor name',
                    _coSupervisor,
                    (v) => setState(() => _coSupervisor = v),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _coSupEmailController,
                    decoration: const InputDecoration(
                      labelText: 'Co-supervisor email',
                      prefixIcon: Icon(Icons.alternate_email_rounded),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.qr_code_2_outlined),
              label: const Text('Submit allocation'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teacherDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.co_present_outlined),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Not selected'),
        ),
        for (final name in widget.teacherNames)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// Proposal form page (cover sheet metadata)
// ============================================================================
class _ProposalFormPage extends StatefulWidget {
  const _ProposalFormPage({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  State<_ProposalFormPage> createState() => _ProposalFormPageState();
}

class _ProposalFormPageState extends State<_ProposalFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _termController;
  late final TextEditingController _projectIdController;
  late final TextEditingController _areaController;
  late final TextEditingController _titleController;
  late final TextEditingController _supDesignationController;
  late final TextEditingController _coSupDesignationController;
  late final TextEditingController _similarityController;
  FypProjectType _projectType = FypProjectType.development;
  String? _supervisor;
  String? _coSupervisor;
  late final List<_MemberInputs> _members;

  @override
  void initState() {
    super.initState();
    _termController = TextEditingController(text: _defaultTerm());
    _projectIdController = TextEditingController();
    _areaController = TextEditingController();
    _titleController = TextEditingController();
    _supDesignationController = TextEditingController();
    _coSupDesignationController = TextEditingController();
    _similarityController = TextEditingController();
    _members = [
      _MemberInputs.seeded(
        rollNo: widget.student.rollNo,
        name: widget.student.studentName,
      ),
      _MemberInputs.seeded(),
    ];
  }

  @override
  void dispose() {
    _termController.dispose();
    _projectIdController.dispose();
    _areaController.dispose();
    _titleController.dispose();
    _supDesignationController.dispose();
    _coSupDesignationController.dispose();
    _similarityController.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final proposal = widget.fypRepository.createProposal(
      term: _termController.text.trim(),
      projectId: _projectIdController.text.trim(),
      projectType: _projectType,
      areaOfSpecialization: _areaController.text.trim(),
      title: _titleController.text.trim(),
      members: [
        for (var i = 0; i < _members.length; i++)
          FypMember(
            serialNo: i + 1,
            rollNo: _members[i].rollNo.text.trim(),
            name: _members[i].name.text.trim(),
            email: _members[i].email.text.trim(),
            cgpa: _members[i].cgpa.text.trim(),
            phone: _members[i].phone.text.trim(),
          ),
      ],
      supervisorName: _supervisor ?? '',
      supervisorDesignation: _supDesignationController.text.trim(),
      coSupervisorName: _coSupervisor ?? '',
      coSupervisorDesignation: _coSupDesignationController.text.trim(),
      similarityIndex: _similarityController.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(proposal);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Proposal Cover Sheet')),
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
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title of the Project',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _projectIdController,
                    decoration: const InputDecoration(
                      labelText: 'Project ID (office use)',
                    ),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<FypProjectType>(
                    initialValue: _projectType,
                    decoration:
                        const InputDecoration(labelText: 'Type of project'),
                    items: [
                      for (final type in FypProjectType.values)
                        DropdownMenuItem(value: type, child: Text(type.label)),
                    ],
                    onChanged: (v) =>
                        setState(() => _projectType = v ?? _projectType),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _areaController,
                    decoration: const InputDecoration(
                      labelText: 'Area of specialization',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _termController,
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
                  for (var index = 0; index < _members.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberInputCard(
                        memberIndex: index + 1,
                        inputs: _members[index],
                        showCgpa: true,
                        showPhone: true,
                        requiredFirst: true,
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
                  _teacherDropdown(
                    'Supervisor',
                    _supervisor,
                    (v) => setState(() => _supervisor = v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _supDesignationController,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor designation',
                    ),
                  ),
                  const SizedBox(height: 12),
                  _teacherDropdown(
                    'Co-supervisor',
                    _coSupervisor,
                    (v) => setState(() => _coSupervisor = v),
                  ),
                  const SizedBox(height: 8),
                  TextFormField(
                    controller: _coSupDesignationController,
                    decoration: const InputDecoration(
                      labelText: 'Co-supervisor designation',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Plagiarism check',
              child: TextFormField(
                controller: _similarityController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Similarity index (%)',
                  prefixIcon: Icon(Icons.percent_rounded),
                  helperText: 'Must be less than 20% per HEC.',
                ),
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Generate cover sheet PDF'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _teacherDropdown(
    String label,
    String? value,
    ValueChanged<String?> onChanged,
  ) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: const Icon(Icons.co_present_outlined),
      ),
      items: [
        const DropdownMenuItem<String>(
          value: null,
          child: Text('Not selected'),
        ),
        for (final name in widget.teacherNames)
          DropdownMenuItem<String>(
            value: name,
            child: Text(name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

// ============================================================================
// SRS document form page (IEEE-style sections)
// ============================================================================
class _SrsFormPage extends StatefulWidget {
  const _SrsFormPage({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  State<_SrsFormPage> createState() => _SrsFormPageState();
}

class _SrsFormPageState extends State<_SrsFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _term;
  late final TextEditingController _title;
  String? _supervisor;
  String? _coSupervisor;
  late final TextEditingController _overall;
  late final TextEditingController _external;
  late final TextEditingController _functional;
  late final TextEditingController _nonFunctional;
  late final TextEditingController _interfaceReq;
  late final TextEditingController _useCases;
  late final TextEditingController _uml;
  late final List<_MemberInputs> _members;

  @override
  void initState() {
    super.initState();
    _term = TextEditingController(text: _defaultTerm());
    _title = TextEditingController();
    _overall = TextEditingController();
    _external = TextEditingController();
    _functional = TextEditingController();
    _nonFunctional = TextEditingController();
    _interfaceReq = TextEditingController();
    _useCases = TextEditingController();
    _uml = TextEditingController();
    _members = [
      _MemberInputs.seeded(
        rollNo: widget.student.rollNo,
        name: widget.student.studentName,
      ),
      _MemberInputs.seeded(),
    ];
  }

  @override
  void dispose() {
    _term.dispose();
    _title.dispose();
    _overall.dispose();
    _external.dispose();
    _functional.dispose();
    _nonFunctional.dispose();
    _interfaceReq.dispose();
    _useCases.dispose();
    _uml.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final created = widget.fypRepository.createSrs(
      term: _term.text.trim(),
      title: _title.text.trim(),
      members: [
        for (var i = 0; i < _members.length; i++)
          FypMember(
            serialNo: i + 1,
            rollNo: _members[i].rollNo.text.trim(),
            name: _members[i].name.text.trim(),
            email: _members[i].email.text.trim(),
          ),
      ],
      supervisorName: _supervisor ?? '',
      coSupervisorName: _coSupervisor ?? '',
      overallDescription: _overall.text.trim(),
      externalInterfaces: _external.text.trim(),
      functionalRequirements: _functional.text.trim(),
      nonFunctionalRequirements: _nonFunctional.text.trim(),
      interfaceRequirements: _interfaceReq.text.trim(),
      useCases: _useCases.text.trim(),
      umlDiagramsNotes: _uml.text.trim(),
    );
    if (mounted) Navigator.of(context).pop(created);
  }

  Widget _sectionField(
    String label,
    TextEditingController controller, {
    String? helperText,
  }) {
    return TextFormField(
      controller: controller,
      minLines: 3,
      maxLines: 8,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Write SRS')),
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
                      labelText: 'Project title',
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
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Group members',
              child: Column(
                children: [
                  for (var index = 0; index < _members.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberInputCard(
                        memberIndex: index + 1,
                        inputs: _members[index],
                        requiredFirst: true,
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
                  DropdownButtonFormField<String>(
                    initialValue: _supervisor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor',
                      prefixIcon: Icon(Icons.co_present_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Not selected'),
                      ),
                      for (final name in widget.teacherNames)
                        DropdownMenuItem<String>(
                          value: name,
                          child:
                              Text(name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _supervisor = v),
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _coSupervisor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Co-supervisor (optional)',
                      prefixIcon: Icon(Icons.groups_2_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                        value: null,
                        child: Text('Not selected'),
                      ),
                      for (final name in widget.teacherNames)
                        DropdownMenuItem<String>(
                          value: name,
                          child:
                              Text(name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _coSupervisor = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'SRS sections (IEEE-style)',
              child: Column(
                children: [
                  _sectionField(
                    '1. Overall product description',
                    _overall,
                    helperText:
                        'Product perspective, product functions, user characteristics, assumptions and dependencies.',
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '2. External interface requirements',
                    _external,
                    helperText:
                        'User interfaces, hardware interfaces, software interfaces, communications interfaces.',
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '3. Functional requirements',
                    _functional,
                    helperText: 'FR-1, FR-2, … list each system function.',
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '4. Non-functional requirements',
                    _nonFunctional,
                    helperText:
                        'Performance, safety, security, usability, reliability, maintainability.',
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '5. Interface requirements',
                    _interfaceReq,
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '6. Use cases',
                    _useCases,
                    helperText: 'List actors, primary scenarios.',
                  ),
                  const SizedBox(height: 10),
                  _sectionField(
                    '7. UML diagrams (notes)',
                    _uml,
                    helperText:
                        'Briefly describe the diagrams included in the report (class, sequence, activity…).',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.picture_as_pdf_rounded),
              label: const Text('Save SRS & generate PDF'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Meeting log form page (Section 1 only — supervisor fills Section 2)
// ============================================================================
class _MeetingLogFormPage extends StatefulWidget {
  const _MeetingLogFormPage({
    required this.student,
    required this.teacherNames,
    required this.fypRepository,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final FypRepository fypRepository;

  @override
  State<_MeetingLogFormPage> createState() => _MeetingLogFormPageState();
}

class _MeetingLogFormPageState extends State<_MeetingLogFormPage> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _termController;
  late final TextEditingController _titleController;
  late final TextEditingController _meetingDate;
  late final TextEditingController _previousMeetingDate;
  late final TextEditingController _workDone;
  late final TextEditingController _issues;
  String? _supervisor;
  FypProgram _program = FypProgram.bscs;
  late final List<_MemberInputs> _members;

  @override
  void initState() {
    super.initState();
    _termController = TextEditingController(text: _defaultTerm());
    _titleController = TextEditingController();
    _meetingDate = TextEditingController(
      text: DateFormat('dd MMM yyyy').format(DateTime.now()),
    );
    _previousMeetingDate = TextEditingController();
    _workDone = TextEditingController();
    _issues = TextEditingController();
    _program = widget.student.program.toLowerCase().contains('se')
        ? FypProgram.bsse
        : FypProgram.bscs;
    _members = [
      _MemberInputs.seeded(
        rollNo: widget.student.rollNo,
        name: widget.student.studentName,
      ),
      _MemberInputs.seeded(),
    ];
  }

  @override
  void dispose() {
    _termController.dispose();
    _titleController.dispose();
    _meetingDate.dispose();
    _previousMeetingDate.dispose();
    _workDone.dispose();
    _issues.dispose();
    for (final member in _members) {
      member.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    widget.fypRepository.createMeetingLog(
      term: _termController.text.trim(),
      projectTitle: _titleController.text.trim(),
      supervisorName: _supervisor ?? '',
      program: _program,
      members: [
        for (var i = 0; i < _members.length; i++)
          FypMember(
            serialNo: i + 1,
            rollNo: _members[i].rollNo.text.trim(),
            name: _members[i].name.text.trim(),
            email: _members[i].email.text.trim(),
          ),
      ],
      meetingDate: _meetingDate.text.trim(),
      previousMeetingDate: _previousMeetingDate.text.trim(),
      workDoneSinceLastMeeting: _workDone.text.trim(),
      issuesToDiscuss: _issues.text.trim(),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Meeting Log — Section 1')),
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
                    controller: _titleController,
                    decoration: const InputDecoration(
                      labelText: 'Title of Project',
                      prefixIcon: Icon(Icons.title_outlined),
                    ),
                    validator: _required,
                  ),
                  const SizedBox(height: 10),
                  DropdownButtonFormField<String>(
                    initialValue: _supervisor,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Supervisor Name',
                      prefixIcon: Icon(Icons.co_present_outlined),
                    ),
                    items: [
                      const DropdownMenuItem<String>(
                          value: null, child: Text('Not selected')),
                      for (final name in widget.teacherNames)
                        DropdownMenuItem<String>(
                          value: name,
                          child:
                              Text(name, overflow: TextOverflow.ellipsis),
                        ),
                    ],
                    onChanged: (v) => setState(() => _supervisor = v),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: TextFormField(
                          controller: _meetingDate,
                          decoration: const InputDecoration(
                            labelText: 'Meeting date',
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: TextFormField(
                          controller: _previousMeetingDate,
                          decoration: const InputDecoration(
                            labelText: 'Previous meeting',
                          ),
                        ),
                      ),
                    ],
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
              title: 'Members',
              child: Column(
                children: [
                  for (var index = 0; index < _members.length; index++)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _MemberInputCard(
                        memberIndex: index + 1,
                        inputs: _members[index],
                        requiredFirst: true,
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _FormCard(
              title: 'Section 1',
              child: Column(
                children: [
                  TextFormField(
                    controller: _workDone,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Work done since last meeting',
                    ),
                  ),
                  const SizedBox(height: 10),
                  TextFormField(
                    controller: _issues,
                    minLines: 3,
                    maxLines: 6,
                    decoration: const InputDecoration(
                      labelText: 'Issues / tasks to be discussed',
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.save_outlined),
              label: const Text('Save meeting'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// Shared form helpers
// ============================================================================
String _defaultTerm() {
  final now = DateTime.now();
  final season = now.month >= 1 && now.month <= 6 ? 'Spring' : 'Fall';
  return '$season ${now.year}';
}

String? _required(String? value) =>
    (value == null || value.trim().isEmpty) ? 'Required' : null;

class _MemberInputs {
  _MemberInputs({
    required this.rollNo,
    required this.name,
    required this.email,
    required this.cgpa,
    required this.phone,
  });

  factory _MemberInputs.seeded({String rollNo = '', String name = ''}) {
    return _MemberInputs(
      rollNo: TextEditingController(text: rollNo),
      name: TextEditingController(text: name),
      email: TextEditingController(),
      cgpa: TextEditingController(),
      phone: TextEditingController(),
    );
  }

  final TextEditingController rollNo;
  final TextEditingController name;
  final TextEditingController email;
  final TextEditingController cgpa;
  final TextEditingController phone;

  void dispose() {
    rollNo.dispose();
    name.dispose();
    email.dispose();
    cgpa.dispose();
    phone.dispose();
  }
}

class _MemberInputCard extends StatelessWidget {
  const _MemberInputCard({
    required this.memberIndex,
    required this.inputs,
    this.showCgpa = false,
    this.showPhone = false,
    this.requiredFirst = false,
  });

  final int memberIndex;
  final _MemberInputs inputs;
  final bool showCgpa;
  final bool showPhone;
  final bool requiredFirst;

  @override
  Widget build(BuildContext context) {
    String? Function(String?)? validator() =>
        memberIndex == 1 && requiredFirst ? _required : null;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Member $memberIndex',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: inputs.rollNo,
            decoration: const InputDecoration(
              labelText: 'Roll No',
              prefixIcon: Icon(Icons.badge_outlined),
            ),
            validator: validator(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: inputs.name,
            decoration: const InputDecoration(
              labelText: 'Name',
              prefixIcon: Icon(Icons.person_outline),
            ),
            validator: validator(),
          ),
          const SizedBox(height: 8),
          TextFormField(
            controller: inputs.email,
            decoration: const InputDecoration(
              labelText: 'Email',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
          ),
          if (showCgpa) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: inputs.cgpa,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'CGPA',
                prefixIcon: Icon(Icons.grade_outlined),
              ),
            ),
          ],
          if (showPhone) ...[
            const SizedBox(height: 8),
            TextFormField(
              controller: inputs.phone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(
                labelText: 'Phone',
                prefixIcon: Icon(Icons.phone_outlined),
              ),
            ),
          ],
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

Future<void> _showQrSheet(
  BuildContext context,
  String code, {
  required String title,
}) async {
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (context) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: PortalColors.cardBorder),
              ),
              child: QrImageView(
                data: code,
                version: QrVersions.auto,
                size: 220,
              ),
            ),
            const SizedBox(height: 12),
            SelectableText(
              code,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                color: PortalColors.brandBlue,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.check_rounded),
              label: const Text('Close'),
            ),
          ],
        ),
      ),
    ),
  );
}
