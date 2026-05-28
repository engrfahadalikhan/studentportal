import 'package:flutter/material.dart';

import '../assessment/assessment_models.dart';
import '../models/app_role.dart';
import '../services/app_repository.dart';
import 'shared_widgets.dart';
import 'student_portal_shell.dart';

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

  AppRole _selectedRole = AppRole.student;
  String? _selectedTeacherEmail;
  bool _loginInProgress = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
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
            colors: [Color(0xFFEAF2FF), Color(0xFFF7FBFF), Color(0xFFFFFAEC)],
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
                  'Abbottabad University of Science and Technology',
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: PortalColors.subtleText,
                    height: 1.35,
                  ),
                ),
                const SizedBox(height: 24),
                _RoleDropdown(
                  selectedRole: _selectedRole,
                  onChanged: (role) {
                    setState(() {
                      _selectedRole = role;
                      _usernameController.clear();
                      _selectedTeacherEmail = null;
                      _passwordController.clear();
                      _obscurePassword = true;
                      if (role == AppRole.faculty) {
                        _selectedTeacherEmail =
                            widget.repository.teachers.isEmpty
                            ? null
                            : widget.repository.teachers.first.email;
                      }
                    });
                  },
                ),
                const SizedBox(height: 16),
                if (_selectedRole == AppRole.faculty)
                  _teacherAccountPanel()
                else
                  Column(
                    children: [
                      TextFormField(
                        controller: _usernameController,
                        keyboardType: TextInputType.text,
                        decoration: InputDecoration(
                          labelText: _usernameLabel,
                          prefixIcon: Icon(_usernameIcon),
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
                      ),
                      const SizedBox(height: 14),
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
        );
      },
    );
  }

  Widget _teacherAccountPanel() {
    final selectedEmail =
        _selectedTeacherEmail ??
        (widget.repository.teachers.isEmpty
            ? null
            : widget.repository.teachers.first.email);
    final selectedTeacher = selectedEmail == null
        ? null
        : widget.repository.teacherByEmail(selectedEmail);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _TeacherNameDropdown(
          teachers: widget.repository.teachers,
          selectedEmail: selectedEmail,
          onChanged: (email) {
            setState(() {
              _selectedTeacherEmail = email;
              _passwordController.clear();
              _obscurePassword = true;
            });
          },
        ),
        const SizedBox(height: 14),
        _TeacherAccountStatus(teacher: selectedTeacher),
        const SizedBox(height: 16),
        const _TeacherSetupHint(
          text:
              'Temporary mode: select teacher name and login directly. Password is not required right now.',
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

  Future<void> _signIn(BuildContext context) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loginInProgress = true;
    });

    try {
      await widget.repository.signIn(
        role: _selectedRole,
        username: _loginUsername,
        password: _passwordController.text.trim(),
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

  String get _loginUsername {
    if (_selectedRole == AppRole.faculty) {
      return _selectedTeacherEmail ?? '';
    }

    return _usernameController.text.trim();
  }
}

class _TopAccentBand extends StatelessWidget {
  const _TopAccentBand();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 160,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF2948B7), Color(0xFF10B7C4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
      ),
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
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF12343B), Color(0xFF2948B7), Color(0xFF10B7C4)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
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
                    color: Color(0xFFEAF6FF),
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
          Text(label, style: const TextStyle(color: Color(0xFFEAF6FF))),
        ],
      ),
    );
  }
}

class _RoleDropdown extends StatelessWidget {
  const _RoleDropdown({required this.selectedRole, required this.onChanged});

  final AppRole selectedRole;
  final ValueChanged<AppRole> onChanged;

  @override
  Widget build(BuildContext context) {
    const roles = [AppRole.student, AppRole.faculty, AppRole.admin];

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

class _TeacherNameDropdown extends StatelessWidget {
  const _TeacherNameDropdown({
    required this.teachers,
    required this.selectedEmail,
    required this.onChanged,
  });

  final List<AssessmentTeacher> teachers;
  final String? selectedEmail;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveEmail =
        selectedEmail ?? (teachers.isEmpty ? null : teachers.first.email);

    return DropdownButtonFormField<String>(
      initialValue: effectiveEmail,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Teacher name',
        prefixIcon: Icon(Icons.co_present_outlined),
      ),
      items: teachers.map((teacher) {
        return DropdownMenuItem<String>(
          value: teacher.email,
          child: Text(teacher.name, overflow: TextOverflow.ellipsis),
        );
      }).toList(),
      onChanged: onChanged,
      validator: (value) {
        if (value == null || value.isEmpty) {
          return 'Select teacher name.';
        }
        return null;
      },
    );
  }
}

class _PasswordField extends StatelessWidget {
  const _PasswordField({
    required this.controller,
    required this.label,
    required this.obscurePassword,
    required this.onToggleVisibility,
  });

  final TextEditingController controller;
  final String label;
  final bool obscurePassword;
  final VoidCallback onToggleVisibility;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: obscurePassword,
      decoration: InputDecoration(
        labelText: label,
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
        if (value == null || value.trim().isEmpty) {
          return 'Enter password.';
        }
        return null;
      },
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
        gradient: const LinearGradient(
          colors: [Color(0xFF2948B7), Color(0xFF10B7C4)],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x332948B7),
            blurRadius: 18,
            offset: Offset(0, 10),
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

class _TeacherAccountStatus extends StatelessWidget {
  const _TeacherAccountStatus({required this.teacher});

  final AssessmentTeacher? teacher;

  @override
  Widget build(BuildContext context) {
    final courseCount = teacher?.courseIds.length ?? 0;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFECFDF3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFB7E4C7)),
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_user_outlined, color: Color(0xFF16803C)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '${teacher?.name ?? 'Teacher'} selected. $courseCount courses assigned.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: PortalColors.textPrimary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TeacherSetupHint extends StatelessWidget {
  const _TeacherSetupHint({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
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
          const Icon(
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

class _CredentialHint extends StatelessWidget {
  const _CredentialHint({required this.role});

  final AppRole role;

  @override
  Widget build(BuildContext context) {
    final text = switch (role) {
      AppRole.faculty =>
        'Teacher can login without password for now. Select teacher name only.',
      AppRole.admin => 'Admin demo: admin / 1234',
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
          const Icon(
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
