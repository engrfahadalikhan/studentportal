import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assessment/registration_course_data.dart' as registration;
import '../data/local_student_enrollments.dart';
import '../models/student_record.dart';
import '../services/cloud_sync_service.dart';
import '../services/login_store.dart';
import '../ui/student_portal_shell.dart';
import 'fyp_group_models.dart';
import 'fyp_models.dart';
import 'fyp_repository.dart';

const _green = Color(0xFF047857);
const _red = Color(0xFFB91C1C);
const _amber = Color(0xFFB45309);

Color _statusColor(FypGroupStatus s) => switch (s) {
  FypGroupStatus.approved => _green,
  FypGroupStatus.rejected => _red,
  _ => _amber,
};

String _fmt(DateTime? d) =>
    d == null ? '' : DateFormat('dd MMM, hh:mm a').format(d);

// ============================================================================
// TEACHER TAB — create groups, approve as supervisor, coordinator panel,
// examiner assignments + duties
// ============================================================================
class FypTeacherGroupsTab extends StatelessWidget {
  const FypTeacherGroupsTab({
    super.key,
    required this.teacherName,
    required this.teacherNames,
  });

  final String teacherName;
  final List<String> teacherNames;

  FypRepository get _repo => FypRepository.instance;

  @override
  Widget build(BuildContext context) {
    final isCoordinator = _repo.isCoordinator(teacherName);
    final mineToApprove = _repo.groups
        .where(
          (g) =>
              g.status == FypGroupStatus.pendingSupervisor &&
              g.supervisorName.trim().toLowerCase() ==
                  teacherName.trim().toLowerCase(),
        )
        .toList();
    final coordinatorQueue = _repo.groups
        .where(
          (g) =>
              g.status == FypGroupStatus.pendingCoordinator ||
              g.status == FypGroupStatus.pendingSupervisor,
        )
        .toList();
    final examinerDuties = _repo.groupsWhereExaminer(teacherName);
    final meetings = _repo.meetingsForTeacher(teacherName);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _coordinatorBanner(context, isCoordinator),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: () => _createGroupSheet(context, isCoordinator),
                icon: const Icon(Icons.group_add_rounded),
                label: Text(
                  isCoordinator ? 'Create / allot group' : 'Create group',
                ),
              ),
            ),
          ],
        ),
        if (meetings.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('FYP meetings'),
          for (final m in meetings) fypMeetingNotice(m, forTeacher: true),
        ],
        if (mineToApprove.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('Waiting for YOUR approval (as supervisor)'),
          for (final g in mineToApprove)
            _GroupCard(
              group: g,
              trailing: _approveRejectRow(
                context,
                onApprove: () => _repo.supervisorDecision(
                  groupId: g.id,
                  approve: true,
                  byName: teacherName,
                ),
                onReject: (reason) => _repo.supervisorDecision(
                  groupId: g.id,
                  approve: false,
                  byName: teacherName,
                  reason: reason,
                ),
              ),
            ),
        ],
        if (isCoordinator && coordinatorQueue.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('Coordinator queue'),
          for (final g in coordinatorQueue)
            _GroupCard(
              group: g,
              trailing: _approveRejectRow(
                context,
                approveLabel: g.status == FypGroupStatus.pendingSupervisor
                    ? 'Allot directly'
                    : 'Approve / allot',
                onApprove: () => _repo.coordinatorDecision(
                  groupId: g.id,
                  approve: true,
                  byName: teacherName,
                ),
                onReject: (reason) => _repo.coordinatorDecision(
                  groupId: g.id,
                  approve: false,
                  byName: teacherName,
                  reason: reason,
                ),
              ),
            ),
        ],
        if (examinerDuties.isNotEmpty) ...[
          const SizedBox(height: 16),
          _sectionTitle('My examiner duties'),
          for (final g in examinerDuties)
            _GroupCard(
              group: g,
              footer:
                  'You are an examiner of this group — enter its marks in the '
                  'Evaluations tab.',
            ),
        ],
        const SizedBox(height: 16),
        _sectionTitle('All groups (${_repo.groups.length})'),
        if (_repo.groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No groups yet. Teachers or students create them; the '
              'coordinator allots.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final g in _repo.groups)
          _GroupCard(
            group: g,
            trailing: isCoordinator && g.status == FypGroupStatus.approved
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: OutlinedButton.icon(
                      onPressed: () => _assignExaminers(context, g),
                      icon: const Icon(Icons.gavel_rounded, size: 18),
                      label: Text(
                        g.examiners.isEmpty
                            ? 'Assign examiners'
                            : 'Examiners (${g.examiners.length})',
                      ),
                    ),
                  )
                : null,
          ),
      ],
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    ),
  );

  Widget _coordinatorBanner(BuildContext context, bool isCoordinator) {
    final names = _repo.coordinatorNames;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  names.isEmpty
                      ? 'FYP Coordinators: not set'
                      : 'FYP Coordinators: ${names.join(', ')}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                if (isCoordinator)
                  const Text(
                    'That is you — you can allot any group.',
                    style: TextStyle(color: Colors.white70, fontSize: 12),
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => _setCoordinator(context),
            child: const Text(
              'Change',
              style: TextStyle(color: Color(0xFFE7C955)),
            ),
          ),
        ],
      ),
    );
  }

  /// Changing the coordinator needs the ADMIN password (offline gate).
  Future<void> _setCoordinator(BuildContext context) async {
    final passCtrl = TextEditingController();
    final picked = _repo.coordinatorNames.toSet();
    String? err;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Set FYP coordinators'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                width: double.maxFinite,
                height: 260,
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final t in teacherNames)
                      CheckboxListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        value: picked.contains(t),
                        title: Text(t),
                        onChanged: (v) => setLocal(() {
                          if (v == true) {
                            picked.add(t);
                          } else {
                            picked.remove(t);
                          }
                        }),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: passCtrl,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Admin password',
                  prefixIcon: Icon(Icons.lock_outline),
                ),
              ),
              if (err != null) ...[
                const SizedBox(height: 8),
                Text(err!, style: const TextStyle(color: _red, fontSize: 12)),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                if (picked.isEmpty) {
                  setLocal(() => err = 'Select at least one coordinator.');
                  return;
                }
                final expected =
                    LoginStore.instance.passwordOverride('admin') ??
                    'pdfpakistan123#';
                if (passCtrl.text.trim() != expected) {
                  setLocal(() => err = 'Admin password is wrong.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    passCtrl.dispose();
    if (ok == true && picked.isNotEmpty) {
      _repo.setCoordinators(picked);
      await CloudSyncService.instance.pushFypCoordinators(picked);
    }
  }

  Widget _approveRejectRow(
    BuildContext context, {
    String approveLabel = 'Approve',
    required VoidCallback onApprove,
    required void Function(String reason) onReject,
  }) {
    return Wrap(
      spacing: 8,
      children: [
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: _green),
          onPressed: onApprove,
          icon: const Icon(Icons.check_rounded, size: 18),
          label: Text(approveLabel),
        ),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(foregroundColor: _red),
          onPressed: () async {
            final ctrl = TextEditingController();
            final go = await showDialog<bool>(
              context: context,
              builder: (c) => AlertDialog(
                title: const Text('Reject group'),
                content: TextField(
                  controller: ctrl,
                  decoration: const InputDecoration(
                    labelText: 'Reason (shown to the group)',
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(c, false),
                    child: const Text('Cancel'),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(c, true),
                    child: const Text('Reject'),
                  ),
                ],
              ),
            );
            final reason = ctrl.text.trim();
            ctrl.dispose();
            if (go == true) onReject(reason);
          },
          icon: const Icon(Icons.close_rounded, size: 18),
          label: const Text('Reject'),
        ),
      ],
    );
  }

  Future<void> _assignExaminers(BuildContext context, FypGroup g) async {
    final picked = {...g.examiners};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text('Examiners — ${g.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in teacherNames)
                  CheckboxListTile(
                    dense: true,
                    value: picked.contains(t),
                    title: Text(t),
                    subtitle:
                        t.trim().toLowerCase() ==
                            g.supervisorName.trim().toLowerCase()
                        ? const Text(
                            'Supervisor of this group',
                            style: TextStyle(fontSize: 11, color: _amber),
                          )
                        : null,
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        picked.add(t);
                      } else {
                        picked.remove(t);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _repo.setGroupExaminers(groupId: g.id, examiners: picked.toList());
    }
  }

  Future<void> _createGroupSheet(
    BuildContext context,
    bool isCoordinator,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _GroupForm(
        teacherNames: teacherNames,
        defaultSupervisor: teacherName,
        creatorRole: 'teacher',
        creatorName: teacherName,
        allowDirectAllot: isCoordinator,
      ),
    );
  }
}

// ============================================================================
// STUDENT TAB — create own group (supervisor from dropdown) + status timeline
// ============================================================================
class FypStudentGroupTab extends StatelessWidget {
  const FypStudentGroupTab({
    super.key,
    required this.student,
    required this.teacherNames,
    required this.studentChoices,
  });

  final StudentRecord student;
  final List<String> teacherNames;
  final List<StudentRecord> studentChoices;

  FypRepository get _repo => FypRepository.instance;

  @override
  Widget build(BuildContext context) {
    final mine = _repo.groupForRollNo(student.rollNo);
    final meetings = _repo.meetingsForGroup(mine);
    if (mine == null) {
      return ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            'You are not in any FYP group yet. Create yours — pick your '
            'supervisor, then wait for the supervisor and coordinator '
            'approvals.',
            style: TextStyle(color: PortalColors.subtleText),
          ),
          if (meetings.isNotEmpty) ...[
            const SizedBox(height: 16),
            fypSectionTitle('FYP meetings'),
            for (final m in meetings) fypMeetingNotice(m, forTeacher: false),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _GroupForm(
                teacherNames: teacherNames,
                defaultSupervisor: null,
                creatorRole: 'student',
                creatorName: student.rollNo,
                allowDirectAllot: false,
                studentChoices: studentChoices,
                firstMember: FypMember(
                  serialNo: 1,
                  rollNo: student.rollNo,
                  name: student.studentName,
                  email: '${student.rollNo}@student.local',
                ),
              ),
            ),
            icon: const Icon(Icons.group_add_rounded),
            label: const Text('Create my group'),
          ),
        ],
      );
    }

    // Before the supervisor has approved, the student may still edit or redo.
    final canEdit = mine.status == FypGroupStatus.pendingSupervisor;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _GroupCard(group: mine, showTimeline: true),
        if (meetings.isNotEmpty) ...[
          const SizedBox(height: 16),
          fypSectionTitle('FYP meetings'),
          for (final m in meetings) fypMeetingNotice(m, forTeacher: false),
        ],
        if (canEdit) ...[
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: () => showModalBottomSheet<void>(
              context: context,
              isScrollControlled: true,
              builder: (_) => _GroupForm(
                teacherNames: teacherNames,
                defaultSupervisor: mine.supervisorName,
                creatorRole: 'student',
                creatorName: student.rollNo,
                allowDirectAllot: false,
                studentChoices: studentChoices,
                existing: mine,
              ),
            ),
            icon: const Icon(Icons.edit_outlined),
            label: const Text('Edit my group'),
          ),
          const SizedBox(height: 6),
          const Text(
            'You can change the title, members or supervisor until the '
            'supervisor approves. Changing the supervisor restarts the '
            'approval.',
            style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
          ),
        ],
        if (mine.status == FypGroupStatus.rejected) ...[
          const SizedBox(height: 10),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(foregroundColor: _red),
            onPressed: () async {
              final go = await showDialog<bool>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const Text('Delete rejected group?'),
                  content: const Text(
                    'Your group was rejected. Delete it to create a new one.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(c, true),
                      child: const Text('Delete'),
                    ),
                  ],
                ),
              );
              if (go == true) _repo.deleteGroup(mine.id);
            },
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete & start again'),
          ),
        ],
      ],
    );
  }
}

// ============================================================================
// Shared widgets
// ============================================================================
class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    this.trailing,
    this.footer,
    this.showTimeline = false,
    this.serial = 0,
  });

  final FypGroup group;
  final Widget? trailing;
  final String? footer;
  final bool showTimeline;

  /// 1-based serial shown as a "#n" badge; 0 hides it.
  final int serial;

  @override
  Widget build(BuildContext context) {
    final g = group;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (serial > 0) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    '#$serial',
                    style: const TextStyle(
                      color: Color(0xFFE7C955),
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: Text(
                  g.title.isEmpty ? '(no title)' : g.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(g.status).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  g.status.label,
                  style: TextStyle(
                    color: _statusColor(g.status),
                    fontWeight: FontWeight.w800,
                    fontSize: 11,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '${g.phase.label} · ${g.program.label}'
            '${g.term.isEmpty ? '' : ' · ${g.term}'} · '
            'Supervisor: ${g.supervisorName.isEmpty ? '—' : g.supervisorName}'
            '${g.coSupervisorName.isEmpty ? '' : ' · Co: ${g.coSupervisorName}'}',
            style: const TextStyle(
              color: PortalColors.subtleText,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 6),
          for (final m in g.members)
            Text(
              '•  ${m.rollNo}  ${m.name}',
              style: const TextStyle(fontSize: 12.5),
            ),
          if (g.examiners.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Examiners: ${g.examiners.join(', ')}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _amber,
              ),
            ),
          ],
          if (g.status == FypGroupStatus.rejected &&
              g.rejectedReason.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Rejected: ${g.rejectedReason}',
              style: const TextStyle(color: _red, fontSize: 12),
            ),
          ],
          if (showTimeline) ...[
            const Divider(height: 18),
            _timelineRow(
              'Created by ${g.createdByName}',
              true,
              _fmt(g.createdAt),
            ),
            _timelineRow(
              g.supervisorActionAt == null
                  ? 'Supervisor approval (${g.supervisorName})'
                  : 'Supervisor: ${g.supervisorActionBy}',
              g.supervisorActionAt != null &&
                  g.status != FypGroupStatus.pendingSupervisor,
              _fmt(g.supervisorActionAt),
            ),
            _timelineRow(
              g.coordinatorActionAt == null
                  ? 'Coordinator approval'
                  : 'Coordinator: ${g.coordinatorActionBy}',
              g.status == FypGroupStatus.approved,
              _fmt(g.coordinatorActionAt),
            ),
          ],
          if (trailing != null) ...[const SizedBox(height: 10), trailing!],
          if (footer != null) ...[
            const SizedBox(height: 8),
            Text(
              footer!,
              style: const TextStyle(fontSize: 11.5, color: _amber),
            ),
          ],
        ],
      ),
    );
  }

  Widget _timelineRow(String label, bool done, String when) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(
            done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
            size: 16,
            color: done ? _green : PortalColors.subtleText,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(label, style: const TextStyle(fontSize: 12.5))),
          if (when.isNotEmpty)
            Text(
              when,
              style: const TextStyle(
                fontSize: 10.5,
                color: PortalColors.subtleText,
              ),
            ),
        ],
      ),
    );
  }
}

/// Bottom-sheet form used by both teacher and student group creation.
class _GroupForm extends StatefulWidget {
  const _GroupForm({
    required this.teacherNames,
    required this.defaultSupervisor,
    required this.creatorRole,
    required this.creatorName,
    required this.allowDirectAllot,
    this.studentChoices = const [],
    this.firstMember,
    this.existing,
    this.defaultPhase,
  });

  final List<String> teacherNames;
  final String? defaultSupervisor;
  final String creatorRole;
  final String creatorName;
  final bool allowDirectAllot;
  final List<StudentRecord> studentChoices;
  final FypMember? firstMember;

  /// Pre-selects the phase for a fresh group (e.g. creating from a phase tab).
  final FypPhase? defaultPhase;

  /// When set, the form EDITS this existing group instead of creating one.
  final FypGroup? existing;

  @override
  State<_GroupForm> createState() => _GroupFormState();
}

class _GroupFormState extends State<_GroupForm> {
  final _title = TextEditingController();
  final _term = TextEditingController(text: 'Fall 2026');
  final _rolls = <TextEditingController>[];
  final _names = <TextEditingController>[];
  FypPhase _phase = FypPhase.fyp1;
  FypProgram _program = FypProgram.bscs;
  String? _supervisor;
  String _coSupervisor = '';
  bool _directAllot = false;
  String? _err;

  @override
  void initState() {
    super.initState();
    _supervisor = widget.defaultSupervisor;
    if (widget.defaultPhase != null) _phase = widget.defaultPhase!;
    for (var i = 0; i < 4; i++) {
      _rolls.add(TextEditingController());
      _names.add(TextEditingController());
    }
    final fm = widget.firstMember;
    if (fm != null) {
      _rolls[0].text = fm.rollNo;
      _names[0].text = fm.name;
    }
    final ex = widget.existing;
    if (ex != null) {
      _title.text = ex.title;
      _term.text = ex.term;
      _phase = ex.phase;
      _program = ex.program;
      _supervisor = ex.supervisorName;
      _coSupervisor = ex.coSupervisorName;
      for (var i = 0; i < ex.members.length && i < _rolls.length; i++) {
        _rolls[i].text = ex.members[i].rollNo;
        _names[i].text = ex.members[i].name;
      }
    }
  }

  @override
  void dispose() {
    _title.dispose();
    _term.dispose();
    for (final c in [..._rolls, ..._names]) {
      c.dispose();
    }
    super.dispose();
  }

  void _submit() {
    final members = <FypMember>[];
    for (var i = 0; i < _rolls.length; i++) {
      final roll = _rolls[i].text.trim();
      final name = _names[i].text.trim();
      if (roll.isEmpty) continue;
      members.add(
        FypMember(
          serialNo: members.length + 1,
          rollNo: roll,
          name: name.isEmpty ? roll : name,
          email: '$roll@student.local',
        ),
      );
    }
    if (_title.text.trim().isEmpty) {
      setState(() => _err = 'Give the project a title.');
      return;
    }
    if (members.isEmpty) {
      setState(() => _err = 'Add at least one member (roll number).');
      return;
    }
    if ((_supervisor ?? '').trim().isEmpty) {
      setState(() => _err = 'Pick a supervisor.');
      return;
    }
    // A student can only be in ONE active group (ignore the group being edited).
    for (final m in members) {
      final other = FypRepository.instance.groupForRollNo(m.rollNo);
      if (other != null &&
          other.status != FypGroupStatus.rejected &&
          other.id != widget.existing?.id) {
        setState(
          () => _err =
              '${m.rollNo} is already in group "${other.title}" '
              '(${other.status.label}).',
        );
        return;
      }
    }
    if (widget.existing != null) {
      FypRepository.instance.editGroupFull(
        groupId: widget.existing!.id,
        title: _title.text,
        phase: _phase,
        program: _program,
        term: _term.text,
        members: members,
        supervisorName: _supervisor!,
        coSupervisorName: _coSupervisor,
      );
      Navigator.pop(context);
      return;
    }
    FypRepository.instance.createGroup(
      title: _title.text,
      phase: _phase,
      program: _program,
      term: _term.text,
      members: members,
      supervisorName: _supervisor!,
      coSupervisorName: _coSupervisor,
      createdByRole: _directAllot ? 'coordinator' : widget.creatorRole,
      createdByName: widget.creatorName,
    );
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          const Text(
            'New FYP group',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Project title *',
              prefixIcon: Icon(Icons.title_rounded),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<FypPhase>(
                  initialValue: _phase,
                  decoration: const InputDecoration(labelText: 'Phase'),
                  items: [
                    for (final p in FypPhase.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => setState(() => _phase = v ?? _phase),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButtonFormField<FypProgram>(
                  initialValue: _program,
                  decoration: const InputDecoration(labelText: 'Program'),
                  items: [
                    for (final p in FypProgram.values)
                      DropdownMenuItem(value: p, child: Text(p.label)),
                  ],
                  onChanged: (v) => setState(() => _program = v ?? _program),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _term,
            decoration: const InputDecoration(
              labelText: 'Term',
              prefixIcon: Icon(Icons.calendar_month_outlined),
            ),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue:
                (_supervisor != null &&
                    widget.teacherNames.contains(_supervisor))
                ? _supervisor
                : null,
            decoration: const InputDecoration(
              labelText: 'Supervisor *',
              prefixIcon: Icon(Icons.co_present_outlined),
            ),
            items: [
              for (final t in widget.teacherNames)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _supervisor = v),
          ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue: null,
            decoration: const InputDecoration(
              labelText: 'Co-supervisor (optional)',
              prefixIcon: Icon(Icons.person_add_alt_outlined),
            ),
            items: [
              const DropdownMenuItem(value: '', child: Text('— none —')),
              for (final t in widget.teacherNames)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _coSupervisor = v ?? ''),
          ),
          const SizedBox(height: 14),
          const Text(
            'Members (select students, up to 4)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < _rolls.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  if (widget.studentChoices.isEmpty) ...[
                    Expanded(
                      flex: 2,
                      child: TextField(
                        controller: _rolls[i],
                        decoration: InputDecoration(
                          labelText: 'Roll ${i + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 3,
                      child: TextField(
                        controller: _names[i],
                        decoration: InputDecoration(
                          labelText: 'Name ${i + 1}',
                          isDense: true,
                        ),
                      ),
                    ),
                  ] else
                    Expanded(
                      child: _StudentMemberDropdown(
                        index: i,
                        rollController: _rolls[i],
                        nameController: _names[i],
                        choices: widget.studentChoices,
                        locked: i == 0 && widget.creatorRole == 'student',
                      ),
                    ),
                ],
              ),
            ),
          if (widget.allowDirectAllot)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: _directAllot,
              onChanged: (v) => setState(() => _directAllot = v ?? false),
              title: const Text('Allot directly (as coordinator)'),
              subtitle: const Text(
                'Skips approvals — the group is approved immediately.',
                style: TextStyle(fontSize: 11),
              ),
            ),
          if (_err != null) ...[
            const SizedBox(height: 6),
            Text(_err!, style: const TextStyle(color: _red, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
            label: Text(
              widget.creatorRole == 'student'
                  ? 'Submit for supervisor approval'
                  : (_directAllot ? 'Create & allot' : 'Create group'),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ADMIN PAGE — full control over FYP groups: allot/reject anything, edit
// details, assign examiners, delete, and appoint the coordinator.
// ============================================================================
class _StudentMemberDropdown extends StatelessWidget {
  const _StudentMemberDropdown({
    required this.index,
    required this.rollController,
    required this.nameController,
    required this.choices,
    required this.locked,
  });

  final int index;
  final TextEditingController rollController;
  final TextEditingController nameController;
  final List<StudentRecord> choices;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final current = rollController.text.trim();
    final knownRolls = {for (final student in choices) student.rollNo};
    final allChoices = [
      ...choices,
      if (current.isNotEmpty && !knownRolls.contains(current))
        StudentRecord(
          rollNo: current,
          studentName: nameController.text.trim(),
          program: '',
          semester: '',
          section: '',
          sessionEnrolled: '',
          currentSession: '',
          courses: const [],
        ),
    ];

    return DropdownButtonFormField<String>(
      initialValue: current.isEmpty ? '' : current,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: 'Student ${index + 1}',
        isDense: true,
      ),
      items: [
        if (!locked || current.isEmpty)
          const DropdownMenuItem<String>(
            value: '',
            child: Text('Not selected'),
          ),
        for (final student in allChoices)
          DropdownMenuItem<String>(
            value: student.rollNo,
            child: Text(
              '${student.rollNo} - ${student.studentName}',
              overflow: TextOverflow.ellipsis,
            ),
          ),
      ],
      onChanged: locked
          ? null
          : (rollNo) {
              final selected = allChoices.firstWhere(
                (student) => student.rollNo == rollNo,
                orElse: () => const StudentRecord(
                  rollNo: '',
                  studentName: '',
                  program: '',
                  semester: '',
                  section: '',
                  sessionEnrolled: '',
                  currentSession: '',
                  courses: [],
                ),
              );
              rollController.text = selected.rollNo;
              nameController.text = selected.studentName;
            },
    );
  }
}

class FypAdminGroupsPage extends StatefulWidget {
  const FypAdminGroupsPage({
    super.key,
    this.title = 'FYP Groups (admin)',
    this.actorName,
    this.allowCoordinatorAppointment = true,
    this.embedInParent = false,
  });

  final String title;
  final String? actorName;
  final bool allowCoordinatorAppointment;
  final bool embedInParent;

  @override
  State<FypAdminGroupsPage> createState() => _FypAdminGroupsPageState();
}

class _FypAdminGroupsPageState extends State<FypAdminGroupsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: 5, vsync: this);
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  FypRepository get _repo => FypRepository.instance;

  String get _actorName {
    final actor = widget.actorName?.trim() ?? '';
    if (actor.isNotEmpty) return actor;
    final n = LoginStore.instance.currentUserName.trim();
    return n.isEmpty ? 'Admin' : n;
  }

  List<String> _teacherNames() {
    final names = <String>{
      for (final t in registration.registrationTeachers) t.name,
      for (final c in LoginStore.instance.customTeachers()) c.name,
      if (_actorName != 'Admin') _actorName,
    }..removeWhere((e) => e.trim().isEmpty);
    final list = names.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.embedInParent) {
      return Column(
        children: [
          Material(color: Colors.white, child: _phaseTabBar()),
          Expanded(child: _content()),
        ],
      );
    }

    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: Text(widget.title), bottom: _phaseTabBar()),
      body: _content(),
    );
  }

  TabBar _phaseTabBar() {
    return TabBar(
      controller: _tabs,
      isScrollable: true,
      tabAlignment: TabAlignment.start,
      tabs: const [
        Tab(text: 'FYP-I'),
        Tab(text: 'FYP-II'),
        Tab(text: 'FYP-III'),
        Tab(text: 'Panels'),
        Tab(text: 'Meetings'),
      ],
    );
  }

  Widget _content() {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: _banner(context),
            ),
            Expanded(
              child: TabBarView(
                controller: _tabs,
                children: [
                  _phaseTab(context, FypPhase.fyp1),
                  _phaseTab(context, FypPhase.fyp2),
                  _phaseTab(context, FypPhase.fyp3),
                  _panelsTab(context),
                  _meetingsTab(context),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ------------------------------------------------------------------ phase tab
  Widget _phaseTab(BuildContext context, FypPhase phase) {
    final groups = _repo.groupsForPhase(phase);
    final pending = groups
        .where(
          (g) =>
              g.status == FypGroupStatus.pendingSupervisor ||
              g.status == FypGroupStatus.pendingCoordinator,
        )
        .toList();
    final grouped = _repo.groupedRolls();
    final ungrouped = fypEligibleStudents()
        .where((s) => !grouped.contains(s.rollNo.trim().toLowerCase()))
        .toList();
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                '${phase.label} groups (${groups.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _openCreateForm(context, phase: phase),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Create'),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (pending.isNotEmpty) ...[
          const Text(
            'Pending approval',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
          ),
          const SizedBox(height: 6),
          for (final g in pending) _adminCard(context, g),
          const SizedBox(height: 8),
        ],
        if (groups.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No groups in this phase yet.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final g in groups) _adminCard(context, g),
        const SizedBox(height: 16),
        Row(
          children: [
            const Icon(Icons.person_off_outlined, size: 18, color: _amber),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                'Students without a group (${ungrouped.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'Final-year students (semester 7–8) not yet in any group.',
          style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
        ),
        const SizedBox(height: 8),
        if (ungrouped.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'Every eligible student is already in a group.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final s in ungrouped) _ungroupedTile(context, s, phase),
        const SizedBox(height: 24),
      ],
    );
  }

  Widget _ungroupedTile(BuildContext context, StudentRecord s, FypPhase phase) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  s.studentName.isEmpty ? s.rollNo : s.studentName,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                ),
                Text(
                  '${s.rollNo} · ${s.program} · Sem ${s.semester}'
                  '${s.section.isEmpty ? '' : ' · ${s.section}'}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PortalColors.subtleText,
                  ),
                ),
              ],
            ),
          ),
          TextButton.icon(
            onPressed: () => _openCreateForm(
              context,
              phase: phase,
              firstMember: FypMember(
                serialNo: 1,
                rollNo: s.rollNo,
                name: s.studentName.isEmpty ? s.rollNo : s.studentName,
                email: '${s.rollNo}@student.local',
              ),
            ),
            icon: const Icon(Icons.group_add_outlined, size: 18),
            label: const Text('Group'),
          ),
        ],
      ),
    );
  }

  void _openCreateForm(
    BuildContext context, {
    FypPhase? phase,
    FypMember? firstMember,
  }) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _GroupForm(
        teacherNames: _teacherNames(),
        defaultSupervisor: null,
        creatorRole: 'coordinator',
        creatorName: _actorName,
        allowDirectAllot: true,
        studentChoices: fypEligibleStudents(),
        firstMember: firstMember,
        defaultPhase: phase,
      ),
    );
  }

  // --------------------------------------------------------------- panels tab
  Widget _panelsTab(BuildContext context) {
    final panels = _repo.panels;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Examiner panels (${panels.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _panelDialog(context, null),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('New panel'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'A panel is a reusable set of examiner teachers. Assign a whole '
          'panel to a group in one tap from its card.',
          style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
        ),
        const SizedBox(height: 10),
        if (panels.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No panels yet. Create one, then assign it to groups.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final p in panels)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        p.name.isEmpty ? '(unnamed panel)' : p.name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _panelDialog(context, p),
                      icon: const Icon(Icons.edit_outlined, size: 18),
                      label: const Text('Edit'),
                    ),
                    IconButton(
                      tooltip: 'Delete panel',
                      onPressed: () => _repo.deletePanel(p.id),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: _red,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  p.members.isEmpty ? 'No members' : p.members.join(', '),
                  style: const TextStyle(fontSize: 12.5),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> _panelDialog(BuildContext context, FypPanel? existing) async {
    final names = _teacherNames();
    final nameCtrl = TextEditingController(text: existing?.name ?? '');
    final picked = {...?existing?.members};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text(existing == null ? 'New panel' : 'Edit panel'),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Panel name (e.g. Panel A)',
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 280,
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final t in names)
                        CheckboxListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          value: picked.contains(t),
                          title: Text(t),
                          onChanged: (v) => setLocal(() {
                            if (v == true) {
                              picked.add(t);
                            } else {
                              picked.remove(t);
                            }
                          }),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final name = nameCtrl.text.trim();
    nameCtrl.dispose();
    if (ok == true) {
      if (existing == null) {
        _repo.createPanel(name: name, members: picked.toList());
      } else {
        _repo.editPanel(
          panelId: existing.id,
          name: name,
          members: picked.toList(),
        );
      }
    }
  }

  // ------------------------------------------------------------- meetings tab
  Widget _meetingsTab(BuildContext context) {
    final meetings = _repo.meetings;
    return ListView(
      padding: const EdgeInsets.all(14),
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Scheduled meetings (${meetings.length})',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _meetingDialog(context),
              icon: const Icon(Icons.event_rounded, size: 18),
              label: const Text('Schedule'),
            ),
          ],
        ),
        const SizedBox(height: 4),
        const Text(
          'A scheduled meeting notifies the targeted students and their '
          'teachers. Mark a form required and the teacher is told to bring it.',
          style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
        ),
        const SizedBox(height: 10),
        if (meetings.isEmpty)
          const Padding(
            padding: EdgeInsets.all(18),
            child: Text(
              'No meetings scheduled.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final m in meetings)
          Container(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.title.isEmpty ? '(untitled meeting)' : m.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 14.5,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete meeting',
                      onPressed: () => _repo.deleteMeeting(m.id),
                      icon: const Icon(
                        Icons.delete_outline_rounded,
                        color: _red,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${m.date.isEmpty ? 'Date TBD' : m.date} · ${_meetingTarget(m)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: PortalColors.subtleText,
                  ),
                ),
                if (m.note.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(m.note, style: const TextStyle(fontSize: 12.5)),
                ],
                if (m.formRequired) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _amber.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      m.formName.isEmpty
                          ? 'Form required'
                          : 'Form: ${m.formName}',
                      style: const TextStyle(
                        color: _amber,
                        fontWeight: FontWeight.w800,
                        fontSize: 11,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
      ],
    );
  }

  String _meetingTarget(FypMeeting m) {
    if (m.groupId.isNotEmpty) {
      final matches = _repo.groups.where((e) => e.id == m.groupId).toList();
      final title = matches.isEmpty ? '' : matches.first.title;
      return 'Group: ${title.isEmpty ? m.groupId : title}';
    }
    if (m.phase != null) return m.phase!.label;
    return 'All FYP students';
  }

  Future<void> _meetingDialog(BuildContext context) async {
    final titleCtrl = TextEditingController();
    final dateCtrl = TextEditingController();
    final noteCtrl = TextEditingController();
    final formCtrl = TextEditingController();
    FypPhase? phase; // null = all
    String groupId = ''; // '' = whole phase / all
    bool formRequired = false;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) {
          final groupChoices = phase == null
              ? _repo.groups
              : _repo.groupsForPhase(phase!);
          return AlertDialog(
            title: const Text('Schedule meeting'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: titleCtrl,
                      decoration: const InputDecoration(labelText: 'Title *'),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: dateCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Date / time (e.g. 12 Jul, 10 AM)',
                      ),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<FypPhase?>(
                      initialValue: phase,
                      decoration: const InputDecoration(labelText: 'Phase'),
                      items: [
                        const DropdownMenuItem<FypPhase?>(
                          value: null,
                          child: Text('All phases'),
                        ),
                        for (final p in FypPhase.values)
                          DropdownMenuItem<FypPhase?>(
                            value: p,
                            child: Text(p.label),
                          ),
                      ],
                      onChanged: (v) => setLocal(() {
                        phase = v;
                        groupId = '';
                      }),
                    ),
                    const SizedBox(height: 8),
                    DropdownButtonFormField<String>(
                      initialValue: groupId,
                      decoration: const InputDecoration(
                        labelText: 'Target group',
                      ),
                      items: [
                        const DropdownMenuItem(
                          value: '',
                          child: Text('Whole phase / all'),
                        ),
                        for (final g in groupChoices)
                          DropdownMenuItem(
                            value: g.id,
                            child: Text(
                              g.title.isEmpty ? '(no title)' : g.title,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (v) => setLocal(() => groupId = v ?? ''),
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: noteCtrl,
                      decoration: const InputDecoration(labelText: 'Note'),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 4),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      value: formRequired,
                      onChanged: (v) => setLocal(() => formRequired = v),
                      title: const Text('A form must be submitted'),
                    ),
                    if (formRequired)
                      TextField(
                        controller: formCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Form name (shown to teachers)',
                        ),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(c, false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(c, true),
                child: const Text('Schedule'),
              ),
            ],
          );
        },
      ),
    );
    final title = titleCtrl.text.trim();
    final date = dateCtrl.text.trim();
    final note = noteCtrl.text.trim();
    final formName = formCtrl.text.trim();
    titleCtrl.dispose();
    dateCtrl.dispose();
    noteCtrl.dispose();
    formCtrl.dispose();
    if (ok == true && title.isNotEmpty) {
      _repo.createMeeting(
        title: title,
        date: date,
        phase: phase,
        groupId: groupId,
        note: note,
        formRequired: formRequired,
        formName: formName,
        createdBy: _actorName,
      );
    }
  }

  Widget _banner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          const Icon(Icons.admin_panel_settings_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _repo.coordinatorNames.isEmpty
                  ? 'FYP Coordinators: not set'
                  : 'FYP Coordinators: ${_repo.coordinatorNames.join(', ')}',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          if (widget.allowCoordinatorAppointment)
            TextButton(
              onPressed: () => _pickCoordinator(context),
              child: const Text(
                'Appoint',
                style: TextStyle(color: Color(0xFFE7C955)),
              ),
            )
          else
            const Padding(
              padding: EdgeInsets.only(left: 8),
              child: Text(
                'Coordinator view',
                style: TextStyle(
                  color: Color(0xFFE7C955),
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
        ],
      ),
    );
  }

  /// Admin appoints the coordinator directly (already authenticated as admin).
  Future<void> _pickCoordinator(BuildContext context) async {
    final names = _teacherNames();
    final picked = _repo.coordinatorNames.toSet();
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Appoint FYP coordinators'),
          content: SizedBox(
            width: double.maxFinite,
            height: 320,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in names)
                  CheckboxListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    value: picked.contains(t),
                    title: Text(t),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        picked.add(t);
                      } else {
                        picked.remove(t);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: picked.isEmpty ? null : () => Navigator.pop(c, true),
              child: const Text('Appoint'),
            ),
          ],
        ),
      ),
    );
    if (ok == true && picked.isNotEmpty) {
      _repo.setCoordinators(picked);
      await CloudSyncService.instance.pushFypCoordinators(picked);
    }
  }

  Widget _adminCard(BuildContext context, FypGroup g) {
    final isPending =
        g.status == FypGroupStatus.pendingSupervisor ||
        g.status == FypGroupStatus.pendingCoordinator;
    return _GroupCard(
      group: g,
      serial: _repo.serialOf(g),
      trailing: Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          if (isPending)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: _green),
              onPressed: () => _repo.coordinatorDecision(
                groupId: g.id,
                approve: true,
                byName: _actorName,
              ),
              icon: const Icon(Icons.check_rounded, size: 18),
              label: const Text('Allot'),
            ),
          if (isPending)
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(foregroundColor: _red),
              onPressed: () => _rejectDialog(context, g),
              icon: const Icon(Icons.close_rounded, size: 18),
              label: const Text('Reject'),
            ),
          if (g.status == FypGroupStatus.approved)
            OutlinedButton.icon(
              onPressed: () => _examinersDialog(context, g),
              icon: const Icon(Icons.gavel_rounded, size: 18),
              label: Text(
                g.examiners.isEmpty
                    ? 'Assign examiners'
                    : 'Examiners (${g.examiners.length})',
              ),
            ),
          if (g.status == FypGroupStatus.approved && _repo.panels.isNotEmpty)
            OutlinedButton.icon(
              onPressed: () => _assignPanelDialog(context, g),
              icon: const Icon(Icons.groups_2_outlined, size: 18),
              label: const Text('Assign panel'),
            ),
          OutlinedButton.icon(
            onPressed: () => _editDialog(context, g),
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('Edit'),
          ),
          IconButton(
            tooltip: 'Delete group',
            onPressed: () => _deleteDialog(context, g),
            icon: const Icon(Icons.delete_outline_rounded, color: _red),
          ),
        ],
      ),
    );
  }

  Future<void> _rejectDialog(BuildContext context, FypGroup g) async {
    final ctrl = TextEditingController();
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Reject "${g.title}"?'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'Reason (shown to the group)',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Reject'),
          ),
        ],
      ),
    );
    final reason = ctrl.text.trim();
    ctrl.dispose();
    if (go == true) {
      _repo.coordinatorDecision(
        groupId: g.id,
        approve: false,
        byName: _actorName,
        reason: reason,
      );
    }
  }

  Future<void> _deleteDialog(BuildContext context, FypGroup g) async {
    final go = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('Delete "${g.title}"?'),
        content: const Text(
          'The group is removed for everyone. Members can create a new one.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (go == true) _repo.deleteGroup(g.id);
  }

  Future<void> _examinersDialog(BuildContext context, FypGroup g) async {
    final names = _teacherNames();
    final picked = {...g.examiners};
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: Text('Examiners — ${g.title}'),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final t in names)
                  CheckboxListTile(
                    dense: true,
                    value: picked.contains(t),
                    title: Text(t),
                    onChanged: (v) => setLocal(() {
                      if (v == true) {
                        picked.add(t);
                      } else {
                        picked.remove(t);
                      }
                    }),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    if (ok == true) {
      _repo.setGroupExaminers(groupId: g.id, examiners: picked.toList());
    }
  }

  Future<void> _assignPanelDialog(BuildContext context, FypGroup g) async {
    final panelId = await showDialog<String>(
      context: context,
      builder: (c) => SimpleDialog(
        title: Text('Assign panel — ${g.title}'),
        children: [
          for (final p in _repo.panels)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(c, p.id),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      p.name.isEmpty ? '(unnamed panel)' : p.name,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                    Text(
                      p.members.isEmpty ? 'No members' : p.members.join(', '),
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: PortalColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
    if (panelId != null) {
      _repo.assignPanelToGroup(groupId: g.id, panelId: panelId);
    }
  }

  Future<void> _editDialog(BuildContext context, FypGroup g) async {
    final names = _teacherNames();
    final title = TextEditingController(text: g.title);
    final term = TextEditingController(text: g.term);
    var supervisor = g.supervisorName;
    var coSupervisor = g.coSupervisorName;
    var phase = g.phase;
    var program = g.program;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Edit group'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: title,
                  decoration: const InputDecoration(labelText: 'Project title'),
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<FypPhase>(
                        initialValue: phase,
                        decoration: const InputDecoration(labelText: 'Phase'),
                        items: [
                          for (final p in FypPhase.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (v) => setLocal(() => phase = v ?? phase),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<FypProgram>(
                        initialValue: program,
                        decoration: const InputDecoration(labelText: 'Program'),
                        items: [
                          for (final p in FypProgram.values)
                            DropdownMenuItem(value: p, child: Text(p.label)),
                        ],
                        onChanged: (v) =>
                            setLocal(() => program = v ?? program),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: term,
                  decoration: const InputDecoration(labelText: 'Term'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: names.contains(supervisor) ? supervisor : null,
                  decoration: const InputDecoration(labelText: 'Supervisor'),
                  items: [
                    for (final t in names)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) =>
                      setLocal(() => supervisor = v ?? supervisor),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: names.contains(coSupervisor)
                      ? coSupervisor
                      : '',
                  decoration: const InputDecoration(labelText: 'Co-supervisor'),
                  items: [
                    const DropdownMenuItem(value: '', child: Text('— none —')),
                    for (final t in names)
                      DropdownMenuItem(value: t, child: Text(t)),
                  ],
                  onChanged: (v) =>
                      setLocal(() => coSupervisor = v ?? coSupervisor),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, true),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
    final newTitle = title.text.trim();
    final newTerm = term.text.trim();
    title.dispose();
    term.dispose();
    if (ok == true) {
      _repo.editGroup(
        groupId: g.id,
        title: newTitle.isEmpty ? null : newTitle,
        term: newTerm,
        supervisorName: supervisor,
        coSupervisorName: coSupervisor,
        phase: phase,
        program: program,
      );
    }
  }
}

// ============================================================================
// Eligible-students helper — final-year students (max semester 7 or 8) built
// from the bundled enrollment data, distinct by roll, sorted by roll number.
// Used for the admin "students without a group" list and member pickers.
// ============================================================================
List<StudentRecord> fypEligibleStudents() {
  final byRoll = <String, List<Map<String, dynamic>>>{};
  for (final row in localStudentEnrollmentRows) {
    if (row.length <= 4) continue;
    final roll = row[0].trim();
    if (roll.isEmpty) continue;
    byRoll.putIfAbsent(roll, () => []).add({
      'Roll no': roll,
      'Student_name': row[1].trim(),
      'program': row[2].trim(),
      'semester': row[3].trim(),
      'section': row[4].trim(),
    });
  }
  final out = <StudentRecord>[];
  byRoll.forEach((roll, rows) {
    final rec = StudentRecord.fromRows(rows);
    final sem = int.tryParse(rec.semester) ?? 0;
    if (sem >= 7) out.add(rec);
  });
  out.sort((a, b) => a.rollNo.compareTo(b.rollNo));
  return out;
}

// ============================================================================
// Meeting notice — shown to students and teachers so a coordinator-scheduled
// meeting reaches both sides. Teachers additionally see the form requirement.
// ============================================================================
Widget fypSectionTitle(String t) => Padding(
  padding: const EdgeInsets.only(bottom: 8),
  child: Text(
    t,
    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
  ),
);

Widget fypMeetingNotice(FypMeeting m, {required bool forTeacher}) {
  return Container(
    margin: const EdgeInsets.only(bottom: 10),
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: const Color(0xFFFFFBEB),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: _amber.withValues(alpha: 0.35)),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.event_available_rounded, size: 18, color: _amber),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                m.title.isEmpty ? 'FYP meeting' : m.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 14,
                ),
              ),
            ),
            if (m.date.isNotEmpty)
              Text(
                m.date,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: _amber,
                ),
              ),
          ],
        ),
        if (m.note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(m.note, style: const TextStyle(fontSize: 12.5)),
        ],
        if (m.formRequired) ...[
          const SizedBox(height: 8),
          Row(
            children: [
              const Icon(Icons.description_outlined, size: 16, color: _red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  forTeacher
                      ? 'Bring the form${m.formName.isEmpty ? '' : ': ${m.formName}'} to this meeting.'
                      : 'A form${m.formName.isEmpty ? '' : ' (${m.formName})'} must be submitted at this meeting.',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: _red,
                  ),
                ),
              ),
            ],
          ),
        ],
      ],
    ),
  );
}
