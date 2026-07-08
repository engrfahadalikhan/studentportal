import 'dart:async';

import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/app_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/device_binding_service.dart';
import '../services/firebase_paths.dart';
import '../services/login_store.dart';
import 'shared_widgets.dart';
import 'student_portal_shell.dart';

/// Shown on the login card so it's obvious which build is installed.
const String kAppVersionLabel = kAustPortalVersionLabel;

class AuthLandingPage extends StatefulWidget {
  const AuthLandingPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<AuthLandingPage> createState() => _AuthLandingPageState();
}

class _AuthLandingPageState extends State<AuthLandingPage> {
  final _formKey = GlobalKey<FormState>();
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _customNameController = TextEditingController();

  AppRole _selectedRole = AppRole.student;

  /// Faculty selection: a seed teacher's email, `custom:<name>`, or `__other__`.
  static const _kOther = '__other__';
  String? _teacherSelection;
  bool _loginInProgress = false;
  bool _obscurePassword = true;
  bool _savePassword = false;

  /// The two named admins (both use the admin password). The picked name is
  /// stamped on anything this admin shares.
  static const List<String> _adminNames = [
    'Ms. Mah e Noor',
    'Mr. Fahad Ali Khan',
  ];
  String _adminName = _adminNames.last;

  /// Roles offered on this device. Once the device is claimed by a student or
  /// teacher, only that role (plus Admin, the override) is selectable.
  List<AppRole> get _allowedRoles {
    final b = DeviceBindingService.instance;
    if (b.allowAll || !b.isBound) {
      return const [AppRole.student, AppRole.faculty, AppRole.admin];
    }
    final roles = <AppRole>[];
    if (b.boundRoles.contains('student')) roles.add(AppRole.student);
    if (b.boundRoles.contains('faculty')) roles.add(AppRole.faculty);
    roles.add(AppRole.admin);
    return roles;
  }

  @override
  void initState() {
    super.initState();
    final store = LoginStore.instance;
    _savePassword = store.autoSave;
    switch (store.lastRole) {
      case 'faculty':
        _selectedRole = AppRole.faculty;
        break;
      case 'admin':
        _selectedRole = AppRole.admin;
        break;
      default:
        _selectedRole = AppRole.student;
    }
    // A claimed device forces its own identity (Admin stays available).
    if (!_allowedRoles.contains(_selectedRole)) {
      _selectedRole = _allowedRoles.first;
    }
    _applySavedForRole(_selectedRole);
  }

  /// Pre-fills the username + password (and teacher selection) for [role] from
  /// the saved login, so the user can just tap Login.
  void _applySavedForRole(AppRole role) {
    final store = LoginStore.instance;
    final b = DeviceBindingService.instance;
    if (role == AppRole.faculty) {
      // Lock to the assigned teacher only when exactly ONE teacher is bound.
      _teacherSelection = b.singleKeyOf('faculty') ?? store.lastTeacher;
      _usernameController.clear();
      _passwordController.text = store.savedPassword('faculty');
    } else if (role == AppRole.admin) {
      // Admin logs in with the fixed username "admin"; the picked NAME is a
      // separate identity used to stamp shared data. Password is never saved.
      _usernameController.text = 'admin';
      _passwordController.clear();
      final saved = store.currentUserName.trim();
      if (_adminNames.contains(saved)) _adminName = saved;
    } else {
      // Lock the roll only when exactly ONE student is bound; otherwise the
      // person types their own roll (validated against the assigned list).
      _usernameController.text =
          b.singleKeyOf('student') ?? store.savedUsername(role.name);
      _passwordController.text = store.savedPassword(role.name);
    }
  }

  bool get _studentRollLocked =>
      _selectedRole == AppRole.student &&
      DeviceBindingService.instance.singleKeyOf('student') != null;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _customNameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final wide = width >= 1060;
    final pagePadding = width < 420 ? 12.0 : 20.0;
    final maxCardWidth = wide ? 1100.0 : 640.0;

    return Scaffold(
      body: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFBF6EA), Color(0xFFFFFFFF), Color(0xFFF6ECCF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: _TopAccentBand(),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: EdgeInsets.all(pagePadding),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxCardWidth),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.94),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: const Color(0xDDE6EAF2)),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x221F2A44),
                            blurRadius: 36,
                            offset: Offset(0, 22),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: wide
                          ? Row(
                              children: [
                                Expanded(
                                  child: _BrandPanel(role: _selectedRole),
                                ),
                                Expanded(child: _loginFormCard()),
                              ],
                            )
                          : Column(
                              children: [
                                _BrandPanel(role: _selectedRole, compact: true),
                                _loginFormCard(),
                              ],
                            ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loginFormCard() {
    final theme = Theme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 380;
        return Padding(
          padding: EdgeInsets.all(compact ? 18 : 28),
          child: _LoginFieldTheme(
            child: Form(
              key: _formKey,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Sign in',
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w900,
                      color: PortalColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Abbottabad University of Science and Technology  â€¢  $kAppVersionLabel',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: PortalColors.subtleText,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 24),
                  _RoleDropdown(
                    selectedRole: _selectedRole,
                    roles: _allowedRoles,
                    onChanged: (role) {
                      setState(() {
                        _selectedRole = role;
                        _obscurePassword = true;
                        _usernameController.clear();
                        _passwordController.clear();
                        _applySavedForRole(role);
                      });
                    },
                  ),
                  if (DeviceBindingService.instance.isBound) ...[
                    const SizedBox(height: 12),
                    _DeviceBoundBanner(
                      label: DeviceBindingService.instance.summaryLabel,
                    ),
                  ],
                  const SizedBox(height: 16),
                  if (_selectedRole == AppRole.faculty)
                    _teacherAccountPanel()
                  else
                    Column(
                      children: [
                        if (_selectedRole == AppRole.admin)
                          _adminNamePicker()
                        else
                          TextFormField(
                            controller: _usernameController,
                            keyboardType: TextInputType.text,
                            readOnly: _studentRollLocked,
                            decoration: InputDecoration(
                              labelText: _usernameLabel,
                              prefixIcon: Icon(_usernameIcon),
                              suffixIcon: _studentRollLocked
                                  ? const Icon(Icons.lock_outline, size: 18)
                                  : null,
                              helperText: _studentRollLocked
                                  ? 'This device is locked to this roll number.'
                                  : null,
                            ),
                            validator: (value) {
                              if (value == null || value.trim().isEmpty) {
                                return 'Enter $_usernameLabel.';
                              }
                              return null;
                            },
                          ),
                        const SizedBox(height: 16),
                        _PasswordField(
                          controller: _passwordController,
                          label: 'Password',
                          obscurePassword: _obscurePassword,
                          onToggleVisibility: _togglePasswordVisibility,
                          // Open device: admin may enter any teacher/student
                          // account by leaving the password empty.
                          allowEmpty:
                              _selectedRole != AppRole.admin &&
                              DeviceBindingService.instance.allowAll,
                        ),
                        const SizedBox(height: 12),
                        // Admin password is never saved, so hide the toggle.
                        if (_selectedRole != AppRole.admin)
                          _SavePasswordTile(
                            value: _savePassword,
                            onChanged: (v) => setState(() => _savePassword = v),
                          ),
                        const SizedBox(height: 12),
                        _CredentialHint(role: _selectedRole),
                        const SizedBox(height: 24),
                        _GradientActionButton(
                          icon: _roleIcon(_selectedRole),
                          label: _loginInProgress
                              ? 'Logging in...'
                              : 'Login as ${_selectedRole.label}',
                          onPressed: _loginInProgress
                              ? null
                              : () => _signIn(context),
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
  }

  Widget _teacherAccountPanel() {
    final store = LoginStore.instance;
    final seedTeachers = widget.repository.teachers;
    final customs = store.customTeachers();

    final items = <DropdownMenuItem<String>>[
      for (final t in seedTeachers)
        DropdownMenuItem(
          value: t.email,
          child: Text(t.name, overflow: TextOverflow.ellipsis),
        ),
      for (final c in customs)
        DropdownMenuItem(
          value: 'custom:${c.name.toLowerCase()}',
          child: Text('${c.name}  (added)', overflow: TextOverflow.ellipsis),
        ),
      const DropdownMenuItem(
        value: _kOther,
        child: Text('âž•  Other â€” add new teacher'),
      ),
    ];
    final validValues = {for (final i in items) i.value};
    final selection =
        (_teacherSelection != null && validValues.contains(_teacherSelection))
        ? _teacherSelection!
        : (seedTeachers.isNotEmpty ? seedTeachers.first.email : _kOther);
    final b = DeviceBindingService.instance;
    final locked = b.singleKeyOf('faculty') != null;
    final isOther = !locked && selection == _kOther;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (locked)
          InputDecorator(
            decoration: const InputDecoration(
              labelText: 'Teacher (locked to this device)',
              prefixIcon: Icon(Icons.co_present_outlined),
              suffixIcon: Icon(Icons.lock_outline, size: 18),
            ),
            child: Text(
              b.singleLabelOf('faculty') ?? b.singleKeyOf('faculty') ?? '',
              style: const TextStyle(fontWeight: FontWeight.w700),
            ),
          )
        else
          DropdownButtonFormField<String>(
            initialValue: selection,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Teacher name',
              prefixIcon: Icon(Icons.co_present_outlined),
            ),
            items: items,
            onChanged: (value) {
              setState(() {
                _teacherSelection = value;
                _obscurePassword = true;
                _passwordController.text = (value == _kOther)
                    ? ''
                    : store.savedPassword('faculty');
              });
            },
          ),
        const SizedBox(height: 14),
        if (isOther) ...[
          TextFormField(
            controller: _customNameController,
            decoration: const InputDecoration(
              labelText: 'New teacher name',
              prefixIcon: Icon(Icons.person_add_alt_1_outlined),
            ),
            validator: (value) {
              if (isOther && (value == null || value.trim().isEmpty)) {
                return 'Enter the teacher name.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
        ],
        _PasswordField(
          controller: _passwordController,
          label: 'Password',
          obscurePassword: _obscurePassword,
          onToggleVisibility: _togglePasswordVisibility,
        ),
        const SizedBox(height: 12),
        _SavePasswordTile(
          value: _savePassword,
          onChanged: (v) => setState(() => _savePassword = v),
        ),
        const SizedBox(height: 24),
        _GradientActionButton(
          icon: Icons.login_rounded,
          label: _loginInProgress ? 'Logging in...' : 'Login as Teacher',
          onPressed: _loginInProgress ? null : () => _signIn(context),
        ),
      ],
    );
  }

  /// The faculty username for sign-in: seed email, custom teacher name, or the
  /// newly-typed "Other" name.
  String _facultyUsername() {
    final sel = _teacherSelection;
    if (sel == _kOther) return _customNameController.text.trim();
    if (sel != null && sel.startsWith('custom:')) {
      final key = sel.substring('custom:'.length);
      for (final c in LoginStore.instance.customTeachers()) {
        if (c.name.toLowerCase() == key) return c.name;
      }
      return '';
    }
    // seed teacher: value is the email
    return sel ??
        (widget.repository.teachers.isEmpty
            ? ''
            : widget.repository.teachers.first.email);
  }

  /// The human-readable name of the person logging in: a teacher's real name
  /// (resolved from the seed email or custom entry), "Admin", or the roll.
  String _collectorDisplayName(String username) {
    switch (_selectedRole) {
      case AppRole.faculty:
        final sel = _teacherSelection;
        if (sel != null && sel != _kOther && !sel.startsWith('custom:')) {
          for (final t in widget.repository.teachers) {
            if (t.email == sel) return t.name;
          }
        }
        return _facultyUsername(); // custom / "Other" is already a name
      case AppRole.admin:
        return _adminName;
      case AppRole.student:
        return username;
    }
  }

  Widget _adminNamePicker() {
    return DropdownButtonFormField<String>(
      initialValue: _adminName,
      decoration: const InputDecoration(
        labelText: 'Admin name',
        prefixIcon: Icon(Icons.admin_panel_settings_outlined),
      ),
      items: [
        for (final n in _adminNames) DropdownMenuItem(value: n, child: Text(n)),
      ],
      onChanged: (v) => setState(() => _adminName = v ?? _adminName),
    );
  }

  void _togglePasswordVisibility() {
    setState(() {
      _obscurePassword = !_obscurePassword;
    });
  }

  String get _usernameLabel {
    switch (_selectedRole) {
      case AppRole.faculty:
        return 'Teacher email';
      case AppRole.admin:
        return 'Admin username';
      case AppRole.student:
        return 'Roll number';
    }
  }

  IconData get _usernameIcon {
    switch (_selectedRole) {
      case AppRole.faculty:
        return Icons.alternate_email_rounded;
      case AppRole.admin:
        return Icons.admin_panel_settings_outlined;
      case AppRole.student:
        return Icons.badge_outlined;
    }
  }

  /// If this teacher/student is still on the shared DEFAULT password
  /// (`aust12345` / `1234`), forces them to set their own — the dialog cannot
  /// be dismissed without saving. Returns the password now in effect.
  /// Custom "Other" teachers already chose a personal password, so they skip.
  Future<String> _forcePasswordChangeIfDefault({
    required AppRole role,
    required String username,
    required String typedPassword,
  }) async {
    String? key;
    String defaultPassword = '';
    if (role == AppRole.faculty) {
      final t = widget.repository.teacherByEmail(username);
      if (t == null) return typedPassword; // custom teacher — own password
      key = 'teacher:${t.email.toLowerCase()}';
      defaultPassword = 'aust12345';
    } else if (role == AppRole.student) {
      key = 'student:${username.toLowerCase()}';
      defaultPassword = '1234';
    } else {
      return typedPassword; // admin has its own policy
    }
    final store = LoginStore.instance;
    if (store.passwordOverride(key) != null ||
        typedPassword != defaultPassword) {
      return typedPassword; // already personalised
    }
    if (!mounted) return typedPassword;

    final newCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    String? err;
    final newPass = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (c) => PopScope(
        canPop: false,
        child: StatefulBuilder(
          builder: (c, setLocal) => AlertDialog(
            title: const Text('Set your own password'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'This is your first login. For security you must replace '
                  'the default password with your own before continuing.',
                  style: TextStyle(fontSize: 12.5),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: newCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'New password',
                    prefixIcon: Icon(Icons.lock_outline),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Confirm new password',
                    prefixIcon: Icon(Icons.lock_reset_rounded),
                  ),
                ),
                if (err != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    err!,
                    style: const TextStyle(
                      color: Color(0xFFB91C1C),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
            actions: [
              FilledButton(
                onPressed: () {
                  final a = newCtrl.text.trim();
                  final b = confirmCtrl.text.trim();
                  if (a.length < 4) {
                    setLocal(() => err = 'At least 4 characters.');
                    return;
                  }
                  if (a == defaultPassword) {
                    setLocal(
                      () => err = 'Pick a DIFFERENT password than the default.',
                    );
                    return;
                  }
                  if (a != b) {
                    setLocal(() => err = 'The two passwords do not match.');
                    return;
                  }
                  Navigator.pop(c, a);
                },
                child: const Text('Save & continue'),
              ),
            ],
          ),
        ),
      ),
    );
    newCtrl.dispose();
    confirmCtrl.dispose();
    if (newPass == null || newPass.isEmpty) return typedPassword;
    await store.setPasswordOverride(key, newPass);
    return newPass;
  }

  Future<void> _signIn(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loginInProgress = true;
    });

    final store = LoginStore.instance;
    final role = _selectedRole;
    final password = _passwordController.text.trim();
    String username;
    String? teacherKey;

    try {
      if (role == AppRole.faculty) {
        username = _facultyUsername();
        if (_teacherSelection == _kOther) {
          // Create / update this custom teacher so sign-in can find it.
          await store.addCustomTeacher(username, password);
          teacherKey = 'custom:${username.toLowerCase()}';
        } else if ((_teacherSelection ?? '').startsWith('custom:')) {
          teacherKey = _teacherSelection;
        } else {
          teacherKey = _teacherSelection ?? username;
        }
      } else {
        username = _usernameController.text.trim();
      }

      // One device = one person. Block any identity other than the one this
      // device is bound to (Admin is always allowed and can release it).
      final binding = DeviceBindingService.instance;
      final bindKey = role == AppRole.faculty
          ? (teacherKey ?? username)
          : username;
      if (!binding.allows(role: role.name, key: bindKey)) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'This device is assigned to ${binding.summaryLabel}. '
                'An admin must release it before someone else can log in '
                '(Admin â†’ Release this device).',
              ),
            ),
          );
        }
        return;
      }

      await widget.repository.signIn(
        role: role,
        username: username,
        password: password,
      );

      // FIRST-LOGIN RULE: anyone still on the shared default password must
      // set their own before entering the portal (change is saved per person).
      final effectivePassword = await _forcePasswordChangeIfDefault(
        role: role,
        username: username,
        typedPassword: password,
      );

      // Login worked â†’ remember role + (optionally) the password for next time.
      // The ADMIN password is never persisted, regardless of the toggle.
      await store.recordLogin(
        role: role.name,
        username: username,
        password: effectivePassword,
        save: _savePassword && role != AppRole.admin,
        teacherKey: teacherKey,
      );

      // Remember the human-readable name of whoever just logged in, so any
      // attendance they collect is stamped with their name automatically.
      await store.setCurrentUserName(_collectorDisplayName(username));

      // Teachers/admins: switch on cloud auto-sync — this device's data goes
      // up to Firebase and everyone else's comes down (needs internet; safely
      // queues offline otherwise). Students don't sync.
      if (role != AppRole.student) {
        unawaited(
          CloudSyncService.instance.start(repository: widget.repository),
        );
      } else {
        // Students sync ONLY the FYP groups, so their group request reaches
        // the supervisor/coordinator and approvals come back.
        unawaited(CloudSyncService.instance.startFypOnly());
      }

      // First student/teacher to log in CLAIMS this device.
      await binding.bindIfUnclaimed(
        role: role.name,
        key: bindKey,
        label: role == AppRole.faculty ? _facultyUsername() : bindKey,
      );
    } catch (error) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
      }
    } finally {
      if (mounted) {
        setState(() {
          _loginInProgress = false;
        });
      }
    }
  }
}

class _TopAccentBand extends StatelessWidget {
  const _TopAccentBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: BoxDecoration(gradient: PortalColors.heroGradient),
    );
  }
}

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({required this.role, this.compact = false});

  final AppRole role;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(minHeight: compact ? 210 : 520),
      padding: EdgeInsets.all(compact ? 24 : 34),
      decoration: BoxDecoration(gradient: PortalColors.heroGradient),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Container(
                width: 54,
                height: 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white24),
                ),
                child: Icon(_roleIcon(role), color: Colors.white, size: 30),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Text(
                  'Assessment Portal',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 24,
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
          if (!compact) const Spacer(),
          Padding(
            padding: EdgeInsets.only(top: compact ? 26 : 0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  role.headline,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  _roleLine(role),
                  style: const TextStyle(
                    color: Color(0xFFF3E9CC),
                    fontSize: 16,
                    height: 1.45,
                  ),
                ),
              ],
            ),
          ),
          if (!compact) ...[const SizedBox(height: 30), const _MiniStatsRow()],
        ],
      ),
    );
  }
}

class _MiniStatsRow extends StatelessWidget {
  const _MiniStatsRow();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: const [
        Expanded(
          child: _MiniStat(value: 'BSCS', label: 'Program'),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _MiniStat(value: 'BSSE', label: 'Program'),
        ),
        SizedBox(width: 10),
        Expanded(
          child: _MiniStat(value: 'S26', label: 'Session'),
        ),
      ],
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFFF3E9CC))),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({
    required this.selectedRole,
    required this.onChanged,
    required this.roles,
  });

  final AppRole selectedRole;
  final ValueChanged<AppRole> onChanged;
  final List<AppRole> roles;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<AppRole>(
      initialValue: selectedRole,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Login role',
        prefixIcon: Icon(Icons.manage_accounts_outlined),
      ),
      items: roles.map((role) {
        return DropdownMenuItem<AppRole>(
          value: role,
          child: Row(
            children: [
              Icon(_roleIcon(role), size: 20, color: PortalColors.brandBlue),
              const SizedBox(width: 10),
              Expanded(
                child: Text(role.label, overflow: TextOverflow.ellipsis),
              ),
            ],
          ),
        );
      }).toList(),
      onChanged: (role) {
        if (role != null) {
          onChanged(role);
        }
      },
    );
  }
}

class _DeviceBoundBanner extends StatelessWidget {
  const _DeviceBoundBanner({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0x1A8A6E16),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0x338A6E16)),
      ),
      child: Row(
        children: [
          const Icon(Icons.lock_person_outlined, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'This device is assigned to $label. Only this account (or Admin) '
              'can sign in.',
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PasswordField extends StatelessWidget {
  // ignore: unused_element_parameter
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscurePassword,
    required this.onToggleVisibility,
    this.allowEmpty = false,
  });

  final TextEditingController controller;
  final String label;
  final bool obscurePassword;
  final VoidCallback onToggleVisibility;

  /// Open ("Allowed for ALL") device: an empty password is a valid admin
  /// bypass into any teacher/student account, so don't block the form.
  final bool allowEmpty;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscurePassword,
      decoration: InputDecoration(
        labelText: label,
        helperText: allowEmpty
            ? 'Open device: leave empty to enter without a password.'
            : null,
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: obscurePassword ? 'Show password' : 'Hide password',
          onPressed: onToggleVisibility,
          icon: Icon(
            obscurePassword
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined,
          ),
        ),
      ),
      validator: (value) {
        if (allowEmpty) return null;
        if (value == null || value.trim().isEmpty) {
          return 'Enter password.';
        }
        return null;
      },
    );
  }
}

class _SavePasswordTile extends StatelessWidget {
  const _SavePasswordTile({required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Checkbox(value: value, onChanged: (v) => onChanged(v ?? false)),
            const Expanded(
              child: Text(
                'Save password (auto-fill next time â€” just tap Login)',
                style: TextStyle(
                  color: PortalColors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GradientActionButton extends StatelessWidget {
  const _GradientActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: PortalColors.brandGradient,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: PortalColors.brandBlue.withValues(alpha: 0.30),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: FilledButton.icon(
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
        ),
        icon: Icon(icon),
        label: Text(label),
      ),
    );
  }
}

class _CredentialHint extends StatelessWidget {
  const _CredentialHint({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final text = switch (role) {
      AppRole.faculty =>
        'Teacher can login without password for now. Select teacher name only.',
      AppRole.admin =>
        'Admin login: username admin. Enter the admin password every time '
            '(not saved on this device).',
      AppRole.student =>
        'Student password is 1234 with a valid roll number from the enrollment sheet.',
    };

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline_rounded,
            color: PortalColors.brandBlue,
            size: 19,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PortalColors.subtleText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Wraps the login fields in a dark "black + gold" input theme so the form
/// matches the brand screenshot (dark fields, gold borders + icons, cream text)
/// while the rest of the app keeps its light fields.
class _LoginFieldTheme extends StatelessWidget {
  const _LoginFieldTheme({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context);
    const fill = Color(0xFF17150F); // near-black field
    const popup = Color(0xFF221E15); // dropdown popup bg
    const gold = Color(0xFFC9A227);
    const goldBright = Color(0xFFE7C955);
    const cream = Color(0xFFF3E9CC);
    OutlineInputBorder border(Color c, double w) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: c, width: w),
    );
    return Theme(
      data: base.copyWith(
        canvasColor: popup,
        iconTheme: base.iconTheme.copyWith(color: gold),
        textTheme: base.textTheme.apply(bodyColor: cream, displayColor: cream),
        iconButtonTheme: IconButtonThemeData(
          style: IconButton.styleFrom(foregroundColor: gold),
        ),
        inputDecorationTheme: base.inputDecorationTheme.copyWith(
          filled: true,
          fillColor: fill,
          prefixIconColor: gold,
          suffixIconColor: gold,
          labelStyle: const TextStyle(color: cream),
          floatingLabelStyle: const TextStyle(
            color: goldBright,
            fontWeight: FontWeight.w700,
          ),
          hintStyle: const TextStyle(color: Color(0xFF9C8A4E)),
          enabledBorder: border(gold, 1.4),
          border: border(gold, 1.4),
          focusedBorder: border(goldBright, 1.8),
        ),
      ),
      child: child,
    );
  }
}

IconData _roleIcon(AppRole role) {
  switch (role) {
    case AppRole.faculty:
      return Icons.co_present_outlined;
    case AppRole.admin:
      return Icons.admin_panel_settings_outlined;
    case AppRole.student:
      return Icons.school_outlined;
  }
}

String _roleLine(AppRole role) {
  switch (role) {
    case AppRole.faculty:
      return 'Create papers, generate QR codes, and monitor classroom attempts.';
    case AppRole.admin:
      return 'Manage portal access and inspect local enrollment-sheet data.';
    case AppRole.student:
      return 'Access courses, seating plans, requests, and assessment attempts.';
  }
}
