import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/device_binding_service.dart';
import '../services/login_store.dart';
import '../ui/student_portal_shell.dart';

/// Lets the currently logged-in user (admin / teacher / student) change their
/// password. The new password is stored as an override that sign-in honors over
/// the built-in default (pdfpakistan / aust12345 / 1234).
class ChangePasswordPage extends StatefulWidget {
  const ChangePasswordPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<ChangePasswordPage> createState() => _ChangePasswordPageState();
}

class _ChangePasswordPageState extends State<ChangePasswordPage> {
  final _formKey = GlobalKey<FormState>();
  final _current = TextEditingController();
  final _next = TextEditingController();
  final _confirm = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = true;

  late final String _key;
  late final String _currentPassword;
  late final String _who;
  bool _custom = false;
  String _customName = '';

  /// On an admin-blessed OPEN device, a teacher/student portal was opened
  /// without their password, so the admin can reset it here WITHOUT typing the
  /// old one. The admin's own password is never bypassed.
  bool _directReset = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  void _resolve() {
    final s = widget.repository.currentSession;
    final store = LoginStore.instance;
    if (s == null) {
      _key = '';
      _currentPassword = '';
      _who = '';
      return;
    }
    _directReset = DeviceBindingService.instance.allowAll && !s.isAdmin;
    if (s.isAdmin) {
      _key = 'admin';
      _currentPassword = store.passwordOverride(_key) ?? 'pdfpakistan123#';
      _who = 'Admin';
    } else if (s.isTeacher) {
      final t = s.teacher!;
      _who = t.name;
      if (t.id.startsWith('custom:')) {
        _custom = true;
        _customName = t.name;
        _key = 'teacher:${t.id}';
        final c = store.customTeacherByName(t.name);
        _currentPassword =
            store.passwordOverride(_key) ?? (c?.password ?? t.password);
      } else {
        _key = 'teacher:${t.email.toLowerCase()}';
        _currentPassword = store.passwordOverride(_key) ?? 'aust12345';
      }
    } else {
      final roll = s.student!.rollNo;
      _who = roll;
      _key = 'student:${roll.toLowerCase()}';
      _currentPassword = store.passwordOverride(_key) ?? '1234';
    }
  }

  @override
  void dispose() {
    _current.dispose();
    _next.dispose();
    _confirm.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_directReset && _current.text.trim() != _currentPassword) {
      setState(() {
        _ok = false;
        _message = 'Current password is wrong.';
      });
      return;
    }
    setState(() => _busy = true);
    final store = LoginStore.instance;
    await store.setPasswordOverride(_key, _next.text.trim());
    if (_custom) {
      await store.updateCustomTeacherPassword(_customName, _next.text.trim());
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _ok = true;
      _message = 'Password changed. Use the new password next time.';
      _current.clear();
      _next.clear();
      _confirm.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final noSession = widget.repository.currentSession == null;
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Change Password')),
      body: noSession
          ? const Center(child: Text('Please sign in first.'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
              children: [
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: PortalColors.softBlue,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: PortalColors.blueBorder),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.person_outline_rounded,
                          color: PortalColors.brandBlue),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          _directReset
                              ? 'Admin device — set a new password for $_who '
                                    '(no current password needed).'
                              : 'Changing password for: $_who',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: PortalColors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      if (!_directReset) ...[
                        TextFormField(
                          controller: _current,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: 'Current password',
                            prefixIcon: Icon(Icons.lock_outline_rounded),
                          ),
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter current password.'
                              : null,
                        ),
                        const SizedBox(height: 14),
                      ],
                      TextFormField(
                        controller: _next,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'New password',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        validator: (v) {
                          if (v == null || v.trim().length < 4) {
                            return 'New password must be at least 4 characters.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _confirm,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Confirm new password',
                          prefixIcon: Icon(Icons.key_outlined),
                        ),
                        validator: (v) => (v != _next.text)
                            ? 'Passwords do not match.'
                            : null,
                      ),
                      const SizedBox(height: 20),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: _busy ? null : _save,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(_busy ? 'Saving...' : 'Change password'),
                        ),
                      ),
                      if (_message != null) ...[
                        const SizedBox(height: 14),
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
                ),
              ],
            ),
    );
  }
}
