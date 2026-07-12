import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/login_store.dart';
import '../ui/student_portal_shell.dart';

/// Admin tool: reset any teacher's or student's password. The new password is
/// stored as an override (the same mechanism a user's own "Change password"
/// uses) and is pushed to Firebase automatically, so the person can then log in
/// with it on any device.
class AdminPasswordManagerPage extends StatefulWidget {
  const AdminPasswordManagerPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<AdminPasswordManagerPage> createState() =>
      _AdminPasswordManagerPageState();
}

enum _Target { teacher, student }

class _AdminPasswordManagerPageState extends State<AdminPasswordManagerPage> {
  _Target _target = _Target.teacher;

  // Teacher mode.
  String? _teacherKey; // 'teacher:<email>' or 'teacher:custom:<name>'
  final _teacherSearch = TextEditingController();

  // Student mode.
  final _roll = TextEditingController();

  final _next = TextEditingController();
  final _confirm = TextEditingController();

  String? _message;
  bool _ok = true;

  @override
  void dispose() {
    _teacherSearch.dispose();
    _roll.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  /// All selectable teachers: seed teachers + custom "Other" teachers.
  List<_TeacherEntry> _teacherEntries() {
    final store = LoginStore.instance;
    final out = <_TeacherEntry>[];
    for (final t in widget.repository.teachers) {
      final key = 'teacher:${t.email.toLowerCase()}';
      out.add(
        _TeacherEntry(
          key: key,
          label: t.name,
          current: store.passwordOverride(key) ?? 'aust12345',
        ),
      );
    }
    for (final c in store.customTeachers()) {
      final key = 'teacher:custom:${c.name.toLowerCase()}';
      out.add(
        _TeacherEntry(
          key: key,
          label: '${c.name} (added)',
          current: store.passwordOverride(key) ?? c.password,
          customName: c.name,
        ),
      );
    }
    out.sort((a, b) => a.label.toLowerCase().compareTo(b.label.toLowerCase()));
    return out;
  }

  _TeacherEntry? _entryByKey(List<_TeacherEntry> entries, String? key) {
    for (final e in entries) {
      if (e.key == key) return e;
    }
    return null;
  }

  Future<void> _save() async {
    final store = LoginStore.instance;
    final newPass = _next.text.trim();
    if (newPass.length < 4) {
      setState(() {
        _ok = false;
        _message = 'New password must be at least 4 characters.';
      });
      return;
    }
    if (newPass != _confirm.text.trim()) {
      setState(() {
        _ok = false;
        _message = 'The two passwords do not match.';
      });
      return;
    }

    String key;
    String who;
    String? customName;
    if (_target == _Target.teacher) {
      final entries = _teacherEntries();
      final entry = _entryByKey(entries, _teacherKey);
      if (entry == null) {
        setState(() {
          _ok = false;
          _message = 'Pick a teacher first.';
        });
        return;
      }
      key = entry.key;
      who = entry.label;
      customName = entry.customName;
    } else {
      final roll = _roll.text.trim();
      if (roll.isEmpty) {
        setState(() {
          _ok = false;
          _message = 'Enter the student roll number.';
        });
        return;
      }
      key = 'student:${roll.toLowerCase()}';
      who = roll;
    }

    await store.setPasswordOverride(key, newPass);
    if (customName != null) {
      await store.updateCustomTeacherPassword(customName, newPass);
    }
    if (!mounted) return;
    setState(() {
      _ok = true;
      _message =
          'Password for $who set to "$newPass". It is synced to Firebase — '
          'they can log in with it on any device.';
      _next.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = widget.repository.currentSession?.isAdmin ?? false;
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Manage Passwords')),
      body: !isAdmin
          ? const Center(child: Text('Admins only.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                _banner(),
                const SizedBox(height: 16),
                SegmentedButton<_Target>(
                  segments: const [
                    ButtonSegment(
                      value: _Target.teacher,
                      label: Text('Teacher'),
                      icon: Icon(Icons.co_present_rounded),
                    ),
                    ButtonSegment(
                      value: _Target.student,
                      label: Text('Student'),
                      icon: Icon(Icons.badge_outlined),
                    ),
                  ],
                  selected: {_target},
                  onSelectionChanged: (s) => setState(() {
                    _target = s.first;
                    _message = null;
                  }),
                ),
                const SizedBox(height: 18),
                if (_target == _Target.teacher)
                  _teacherPicker()
                else
                  _studentPicker(),
                const SizedBox(height: 14),
                TextField(
                  controller: _next,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: _confirm,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: Icon(Icons.key_outlined),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check_rounded),
                    label: const Text('Set password'),
                  ),
                ),
                if (_message != null) ...[
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _ok
                          ? const Color(0xFFD1FAE5)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _message!,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: _ok
                            ? const Color(0xFF047857)
                            : const Color(0xFFB91C1C),
                      ),
                    ),
                  ),
                ],
              ],
            ),
    );
  }

  Widget _banner() => Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: PortalColors.softBlue,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: PortalColors.blueBorder),
    ),
    child: Row(
      children: [
        Icon(Icons.shield_outlined, color: PortalColors.brandBlue),
        const SizedBox(width: 10),
        const Expanded(
          child: Text(
            'As admin you can reset any teacher or student password. The change '
            'syncs to Firebase and takes effect on their next login.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: PortalColors.textPrimary,
              fontSize: 12.5,
            ),
          ),
        ),
      ],
    ),
  );

  Widget _teacherPicker() {
    final all = _teacherEntries();
    final q = _teacherSearch.text.trim().toLowerCase();
    final entries = q.isEmpty
        ? all
        : all.where((e) => e.label.toLowerCase().contains(q)).toList();
    final selected = _entryByKey(all, _teacherKey);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: _teacherSearch,
          decoration: InputDecoration(
            labelText: 'Search teacher (${all.length})',
            prefixIcon: const Icon(Icons.person_search_rounded),
            suffixIcon: q.isEmpty
                ? null
                : IconButton(
                    tooltip: 'Clear',
                    icon: const Icon(Icons.clear_rounded),
                    onPressed: () => setState(() => _teacherSearch.clear()),
                  ),
          ),
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 8),
        Container(
          constraints: const BoxConstraints(maxHeight: 240),
          decoration: BoxDecoration(
            border: Border.all(color: PortalColors.cardBorder),
            borderRadius: BorderRadius.circular(12),
          ),
          child: entries.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'No teacher matches your search.',
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  itemCount: entries.length,
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final sel = e.key == _teacherKey;
                    return ListTile(
                      dense: true,
                      selected: sel,
                      selectedTileColor: PortalColors.softBlue,
                      leading: Icon(
                        sel
                            ? Icons.check_circle_rounded
                            : Icons.person_outline_rounded,
                        color: sel
                            ? PortalColors.brandBlue
                            : PortalColors.subtleText,
                        size: 20,
                      ),
                      title: Text(
                        e.label,
                        style: const TextStyle(fontSize: 13.5),
                      ),
                      onTap: () => setState(() {
                        _teacherKey = e.key;
                        _message = null;
                      }),
                    );
                  },
                ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 6),
          Text(
            'Selected: ${selected.label}  •  Current password: '
            '${selected.current}',
            style: const TextStyle(
              fontSize: 12,
              color: PortalColors.subtleText,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ],
    );
  }

  Widget _studentPicker() => TextField(
    controller: _roll,
    textCapitalization: TextCapitalization.characters,
    decoration: const InputDecoration(
      labelText: 'Student roll number',
      hintText: 'e.g. 21B-001-CS',
      prefixIcon: Icon(Icons.numbers_rounded),
    ),
    onChanged: (_) => setState(() => _message = null),
  );
}

class _TeacherEntry {
  const _TeacherEntry({
    required this.key,
    required this.label,
    required this.current,
    this.customName,
  });

  final String key;
  final String label;
  final String current;
  final String? customName;
}
