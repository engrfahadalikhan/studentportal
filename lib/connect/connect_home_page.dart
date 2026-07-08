import 'package:flutter/material.dart';

import '../ui/student_portal_shell.dart' show PortalColors;
import 'connect_models.dart';
import 'connect_repository.dart';
import 'profanity_filter.dart';

/// AUST Connect — self-contained module (Complaints + File Tracking) shared by
/// students, teachers and admin. Reached from a tile on every home screen.
class ConnectHomePage extends StatefulWidget {
  const ConnectHomePage({super.key, required this.identity});

  final ConnectIdentity identity;

  @override
  State<ConnectHomePage> createState() => _ConnectHomePageState();
}

class _ConnectHomePageState extends State<ConnectHomePage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs;
  ConnectRepository get _repo => ConnectRepository.instance;
  ConnectIdentity get _me => widget.identity;

  @override
  void initState() {
    super.initState();
    _tabs = TabController(length: _me.isAdmin ? 4 : 3, vsync: this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _repo.sync(_me));
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _repo,
      builder: (context, _) {
        final unread = _repo.unreadFor(_me);
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('AUST Connect'),
            actions: [
              if (_repo.syncing)
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  ),
                )
              else
                IconButton(
                  tooltip: 'Refresh',
                  onPressed: () => _repo.sync(_me),
                  icon: const Icon(Icons.refresh_rounded),
                ),
            ],
            bottom: TabBar(
              controller: _tabs,
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              tabs: [
                const Tab(text: 'Complaints'),
                const Tab(text: 'File Tracking'),
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Notifications'),
                      if (unread > 0) ...[
                        const SizedBox(width: 6),
                        _badge(unread),
                      ],
                    ],
                  ),
                ),
                if (_me.isAdmin) const Tab(text: 'Admin'),
              ],
            ),
          ),
          body: TabBarView(
            controller: _tabs,
            children: [
              _ComplaintsTab(me: _me),
              _FilesTab(me: _me),
              _NotificationsTab(me: _me),
              if (_me.isAdmin) _AdminTab(me: _me),
            ],
          ),
        );
      },
    );
  }

  Widget _badge(int n) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
    decoration: BoxDecoration(
      color: const Color(0xFFB91C1C),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      '$n',
      style: const TextStyle(
        color: Colors.white,
        fontSize: 11,
        fontWeight: FontWeight.w800,
      ),
    ),
  );
}

const _green = Color(0xFF047857);
const _amber = Color(0xFFB45309);
const _red = Color(0xFFB91C1C);
const _blue = Color(0xFF1D4ED8);

Color _complaintColor(String s) => switch (s) {
  'done' => _green,
  'under_process' => _amber,
  'read' => _blue,
  _ => _red,
};

// ============================================================ COMPLAINTS
class _ComplaintsTab extends StatelessWidget {
  const _ComplaintsTab({required this.me});
  final ConnectIdentity me;

  ConnectRepository get _repo => ConnectRepository.instance;

  @override
  Widget build(BuildContext context) {
    final complaints = _repo.dashboardComplaints;
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openSubmit(context),
        icon: const Icon(Icons.add_rounded),
        label: const Text('New complaint'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _repo.sync(me),
        child: complaints.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 120),
                  Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No complaints on the board.\nTap "New complaint" to '
                        'raise one — it stays visible to everyone until 3 days '
                        'after it is marked Done.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: PortalColors.subtleText),
                      ),
                    ),
                  ),
                ],
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
                children: [for (final c in complaints) _card(context, c)],
              ),
      ),
    );
  }

  Widget _card(BuildContext context, ComplaintRecord c) {
    // Anonymous to everyone; the real name shows only to Admin (or if the
    // submitter chose to reveal it).
    final showName = me.isAdmin || !c.isAnon;
    final who = showName
        ? '${c.byName} (${c.byRole})'
        : 'Anonymous ${c.byRole}';
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
              Expanded(
                child: Text(
                  c.subject.isEmpty ? '(no subject)' : c.subject,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              _statusChip(c.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${c.trackingId}'
            '${c.category.isEmpty ? '' : ' · ${c.category}'} · $who',
            style: const TextStyle(
              fontSize: 11.5,
              color: PortalColors.subtleText,
            ),
          ),
          const SizedBox(height: 8),
          Text(c.body, style: const TextStyle(fontSize: 13)),
          if (c.handledBy.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(
              'Handled by ${c.handledBy}',
              style: const TextStyle(fontSize: 11.5, color: _amber),
            ),
          ],
          if (me.isStaff) ...[
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _statusBtn(context, c, 'read', 'Mark Read'),
                _statusBtn(context, c, 'under_process', 'Under Process'),
                _statusBtn(context, c, 'done', 'Done'),
                if (me.isAdmin)
                  IconButton(
                    tooltip: 'Delete',
                    onPressed: () => _repo.deleteComplaint(c),
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      color: _red,
                      size: 20,
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBtn(
    BuildContext context,
    ComplaintRecord c,
    String status,
    String label,
  ) {
    final active = c.status == status;
    return OutlinedButton(
      style: OutlinedButton.styleFrom(
        backgroundColor: active
            ? _complaintColor(status).withValues(alpha: 0.12)
            : null,
        foregroundColor: _complaintColor(status),
        side: BorderSide(
          color: _complaintColor(status).withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      ),
      onPressed: active ? null : () => _repo.setComplaintStatus(c, status, me),
      child: Text(label, style: const TextStyle(fontSize: 12.5)),
    );
  }

  Widget _statusChip(String s) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    decoration: BoxDecoration(
      color: _complaintColor(s).withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      complaintStatusLabel(s),
      style: TextStyle(
        color: _complaintColor(s),
        fontWeight: FontWeight.w800,
        fontSize: 11,
      ),
    ),
  );

  Future<void> _openSubmit(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ComplaintForm(me: me),
    );
  }
}

class _ComplaintForm extends StatefulWidget {
  const _ComplaintForm({required this.me});
  final ConnectIdentity me;

  @override
  State<_ComplaintForm> createState() => _ComplaintFormState();
}

class _ComplaintFormState extends State<_ComplaintForm> {
  final _subject = TextEditingController();
  final _body = TextEditingController();
  String _category = 'Staff';
  bool _anonymous = true;
  String? _err;
  bool _busy = false;

  static const _categories = [
    'Staff',
    'Facility',
    'Academics',
    'Hostel',
    'Transport',
    'Other',
  ];

  @override
  void dispose() {
    _subject.dispose();
    _body.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final subject = _subject.text.trim();
    final body = _body.text.trim();
    if (subject.isEmpty || body.isEmpty) {
      setState(() => _err = 'Add a subject and describe the complaint.');
      return;
    }
    final bad = ProfanityFilter.firstMatch('$subject $body');
    if (bad != null) {
      setState(
        () => _err =
            'Inappropriate language is not allowed — please reword and try '
            'again.',
      );
      return;
    }
    setState(() {
      _busy = true;
      _err = null;
    });
    final rec = await ConnectRepository.instance.submitComplaint(
      who: widget.me,
      category: _category,
      subject: subject,
      body: body,
      anonymous: _anonymous,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Complaint submitted — ${rec.trackingId}')),
    );
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
            'New complaint',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _category,
            decoration: const InputDecoration(labelText: 'Category'),
            items: [
              for (final c in _categories)
                DropdownMenuItem(value: c, child: Text(c)),
            ],
            onChanged: (v) => setState(() => _category = v ?? _category),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _subject,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'Subject *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _body,
            maxLines: 4,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(
              labelText: 'Describe the complaint *',
            ),
          ),
          const SizedBox(height: 4),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: _anonymous,
            onChanged: (v) => setState(() => _anonymous = v),
            title: const Text('Post anonymously'),
            subtitle: const Text(
              'ON: your name is hidden from everyone (Admin can still see it). '
              'OFF: your name shows on the board.',
              style: TextStyle(fontSize: 11.5),
            ),
          ),
          if (_err != null) ...[
            const SizedBox(height: 6),
            Text(_err!, style: const TextStyle(color: _red, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Submit complaint'),
          ),
        ],
      ),
    );
  }
}

// ============================================================ FILE TRACKING
class _FilesTab extends StatelessWidget {
  const _FilesTab({required this.me});
  final ConnectIdentity me;

  ConnectRepository get _repo => ConnectRepository.instance;

  @override
  Widget build(BuildContext context) {
    final all = _repo.files;
    // Students see their own files; staff see files whose current department is
    // one they own (their queue) PLUS everything for context.
    final mine = all.where((f) => f.byId == me.id).toList();
    final queue = all
        .where((f) => f.status != 'completed' && _ownsCurrent(f))
        .toList();

    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _repo.departments.isEmpty
            ? null
            : () => _openSubmit(context),
        icon: const Icon(Icons.upload_file_rounded),
        label: const Text('Submit file'),
      ),
      body: RefreshIndicator(
        onRefresh: () => _repo.sync(me),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 90),
          children: [
            if (_repo.departments.isEmpty)
              _hint(
                'No departments yet. Admin adds the department route from the '
                'Admin tab before files can be submitted.',
              ),
            if (me.isStaff && queue.isNotEmpty) ...[
              _sectionTitle('My department queue (${queue.length})'),
              for (final f in queue) _fileCard(context, f, actionable: true),
              const SizedBox(height: 8),
            ],
            _sectionTitle(
              me.isStaff ? 'All files (${all.length})' : 'My files (${mine.length})',
            ),
            for (final f in (me.isStaff ? all : mine))
              _fileCard(context, f, actionable: me.isStaff && _ownsCurrent(f)),
            if ((me.isStaff ? all : mine).isEmpty)
              _hint('No files yet.'),
          ],
        ),
      ),
    );
  }

  bool _ownsCurrent(FileRecord f) {
    final step = f.currentStep;
    if (step == null) return false;
    ConnectDepartment? dept;
    for (final d in _repo.departments) {
      if (d.id == step.deptId) {
        dept = d;
        break;
      }
    }
    return dept?.allows(me) ?? me.isAdmin;
  }

  Widget _fileCard(BuildContext context, FileRecord f, {required bool actionable}) {
    final step = f.currentStep;
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
              Expanded(
                child: Text(
                  f.title.isEmpty ? '(untitled file)' : f.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 14.5,
                  ),
                ),
              ),
              _fileStatusChip(f.status),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${f.trackingId} · by ${f.byName}'
            '${f.byRole == 'student' ? '' : ' (${f.byRole})'}',
            style: const TextStyle(
              fontSize: 11.5,
              color: PortalColors.subtleText,
            ),
          ),
          if (f.description.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(f.description, style: const TextStyle(fontSize: 12.5)),
          ],
          const SizedBox(height: 10),
          _timeline(f),
          if (f.status != 'completed') ...[
            const SizedBox(height: 8),
            Text(
              step == null
                  ? ''
                  : 'Current: ${step.deptName} · ${_stepLabel(step.status)}'
                        '${_nextName(f).isEmpty ? '' : '   →   Next: ${_nextName(f)}'}',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: _blue,
              ),
            ),
          ],
          if (actionable && step != null && f.status != 'completed') ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                if (step.status != 'under_process')
                  FilledButton.tonal(
                    onPressed: () =>
                        _repo.advanceFile(f, 'under_process', me),
                    child: const Text('Start (Under Process)'),
                  ),
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: _green),
                  onPressed: () => _repo.advanceFile(f, 'done', me),
                  child: Text(
                    _isLast(f) ? 'Mark Done · Complete' : 'Done · Send next',
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _timeline(FileRecord f) {
    return Column(
      children: [
        for (final s in f.steps)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Icon(
                  s.status == 'done'
                      ? Icons.check_circle_rounded
                      : s.seq == f.currentSeq
                      ? Icons.radio_button_checked_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: s.status == 'done'
                      ? _green
                      : s.seq == f.currentSeq
                      ? _blue
                      : PortalColors.subtleText,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${s.deptName}  ·  ${_stepLabel(s.status)}',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: s.seq == f.currentSeq
                          ? FontWeight.w800
                          : FontWeight.w500,
                    ),
                  ),
                ),
                if (s.by.isNotEmpty)
                  Text(
                    s.by,
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: PortalColors.subtleText,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  bool _isLast(FileRecord f) => f.currentSeq >= f.steps.length - 1;
  String _nextName(FileRecord f) {
    final n = f.currentSeq + 1;
    return n < f.steps.length ? f.steps[n].deptName : '';
  }

  String _stepLabel(String s) => switch (s) {
    'done' => 'Done',
    'under_process' => 'Under Process',
    _ => 'Pending',
  };

  Widget _fileStatusChip(String s) {
    final color = switch (s) {
      'completed' => _green,
      'in_progress' => _amber,
      _ => _blue,
    };
    final label = switch (s) {
      'completed' => 'Completed',
      'in_progress' => 'In Progress',
      _ => 'Submitted',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 11,
        ),
      ),
    );
  }

  Future<void> _openSubmit(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _FileForm(me: me),
    );
  }

  Widget _sectionTitle(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 8, top: 4),
    child: Text(
      t,
      style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
    ),
  );

  Widget _hint(String t) => Padding(
    padding: const EdgeInsets.all(16),
    child: Text(t, style: const TextStyle(color: PortalColors.subtleText)),
  );
}

class _FileForm extends StatefulWidget {
  const _FileForm({required this.me});
  final ConnectIdentity me;

  @override
  State<_FileForm> createState() => _FileFormState();
}

class _FileFormState extends State<_FileForm> {
  final _title = TextEditingController();
  final _desc = TextEditingController();
  late List<ConnectDepartment> _route;
  String? _err;

  @override
  void initState() {
    super.initState();
    // Default route = all departments in their configured order.
    _route = [...ConnectRepository.instance.departments];
  }

  @override
  void dispose() {
    _title.dispose();
    _desc.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _err = 'Give the file a title.');
      return;
    }
    if (_route.isEmpty) {
      setState(() => _err = 'Pick at least one department in the route.');
      return;
    }
    final bad = ProfanityFilter.firstMatch('$title ${_desc.text}');
    if (bad != null) {
      setState(() => _err = 'Inappropriate language is not allowed.');
      return;
    }
    final rec = await ConnectRepository.instance.submitFile(
      who: widget.me,
      title: title,
      description: _desc.text.trim(),
      route: _route,
    );
    if (!mounted) return;
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('File submitted — ${rec.trackingId}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final allDepts = ConnectRepository.instance.departments;
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
            'Submit a file for processing',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _title,
            textCapitalization: TextCapitalization.sentences,
            decoration: const InputDecoration(labelText: 'File title *'),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: _desc,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Description'),
          ),
          const SizedBox(height: 14),
          const Text(
            'Route (departments in order)',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 13),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tick the departments this file must pass through. It moves in this '
            'order.',
            style: TextStyle(fontSize: 11.5, color: PortalColors.subtleText),
          ),
          for (final d in allDepts)
            CheckboxListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              value: _route.any((r) => r.id == d.id),
              title: Text('${d.seq + 1}. ${d.name}'),
              onChanged: (v) => setState(() {
                if (v == true) {
                  if (!_route.any((r) => r.id == d.id)) _route.add(d);
                } else {
                  _route.removeWhere((r) => r.id == d.id);
                }
                _route.sort((a, b) => a.seq.compareTo(b.seq));
              }),
            ),
          if (_err != null) ...[
            const SizedBox(height: 6),
            Text(_err!, style: const TextStyle(color: _red, fontSize: 12.5)),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.upload_file_rounded),
            label: const Text('Submit file'),
          ),
        ],
      ),
    );
  }
}

// ============================================================ NOTIFICATIONS
class _NotificationsTab extends StatelessWidget {
  const _NotificationsTab({required this.me});
  final ConnectIdentity me;

  ConnectRepository get _repo => ConnectRepository.instance;

  @override
  Widget build(BuildContext context) {
    final items = _repo.notificationsFor(me);
    return RefreshIndicator(
      onRefresh: () => _repo.sync(me),
      child: items.isEmpty
          ? ListView(
              children: const [
                SizedBox(height: 140),
                Center(
                  child: Text(
                    'No notifications yet.',
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                ),
              ],
            )
          : ListView.separated(
              padding: const EdgeInsets.all(14),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final n = items[i];
                return ListTile(
                  tileColor: n.unread
                      ? const Color(0xFFFFFBEB)
                      : Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: PortalColors.cardBorder),
                  ),
                  leading: Icon(
                    n.refType == 'file'
                        ? Icons.folder_open_rounded
                        : Icons.campaign_rounded,
                    color: n.unread ? _amber : PortalColors.subtleText,
                  ),
                  title: Text(
                    n.title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(n.body),
                  trailing: n.unread
                      ? const Icon(Icons.circle, size: 10, color: _red)
                      : null,
                  onTap: () => _repo.markNotificationRead(n),
                );
              },
            ),
    );
  }
}

// ============================================================ ADMIN
class _AdminTab extends StatelessWidget {
  const _AdminTab({required this.me});
  final ConnectIdentity me;

  ConnectRepository get _repo => ConnectRepository.instance;

  @override
  Widget build(BuildContext context) {
    final depts = _repo.departments;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _serverCard(context),
        const SizedBox(height: 16),
        Row(
          children: [
            const Expanded(
              child: Text(
                'Departments (file route order)',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 15),
              ),
            ),
            FilledButton.icon(
              onPressed: () => _editDept(context, null, depts.length),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('Add'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (depts.isEmpty)
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text(
              'No departments yet. Add them in the order files should flow '
              '(Dept 1 → Dept 2 → …).',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          ),
        for (final d in depts)
          Container(
            margin: const EdgeInsets.only(bottom: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: PortalColors.pageBackground,
                child: Text('${d.seq + 1}'),
              ),
              title: Text(
                d.name,
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: Text(
                d.staff.isEmpty
                    ? 'Any staff can advance'
                    : 'Staff: ${d.staff.join(', ')}',
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    onPressed: () => _editDept(context, d, d.seq),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline_rounded,
                      size: 20,
                      color: _red,
                    ),
                    onPressed: () => _repo.deleteDepartment(d),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _serverCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(
            _repo.isConfigured ? Icons.cloud_done_outlined : Icons.cloud_off_outlined,
            color: Colors.white,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _repo.isConfigured
                  ? 'Live on Firebase — complaints and files sync across all '
                        'devices automatically.'
                  : 'Offline — this device only. Data will sync once Firebase '
                        'is reachable.',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w700,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _editDept(
    BuildContext context,
    ConnectDepartment? existing,
    int seq,
  ) async {
    final name = TextEditingController(text: existing?.name ?? '');
    final staff = TextEditingController(
      text: existing?.staff.join(', ') ?? '',
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(existing == null ? 'Add department' : 'Edit department'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              decoration: const InputDecoration(labelText: 'Department name'),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: staff,
              decoration: const InputDecoration(
                labelText: 'Staff (comma-separated names)',
                hintText: 'leave blank = any staff can advance',
              ),
            ),
          ],
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
    );
    if (ok == true && name.text.trim().isNotEmpty) {
      await _repo.upsertDepartment(
        id: existing?.id,
        name: name.text.trim(),
        seq: existing?.seq ?? seq,
        staff: [
          for (final s in staff.text.split(','))
            if (s.trim().isNotEmpty) s.trim(),
        ],
      );
    }
    name.dispose();
    staff.dispose();
  }
}
