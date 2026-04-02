import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/app_repository.dart';
import 'shared_widgets.dart';

class AuthLandingPage extends StatefulWidget {
  const AuthLandingPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<AuthLandingPage> createState() => _AuthLandingPageState();
}

class _AuthLandingPageState extends State<AuthLandingPage> {
  final _loginFormKey = GlobalKey<FormState>();
  final _registerFormKey = GlobalKey<FormState>();

  final _loginEmailController = TextEditingController();
  final _loginPasswordController = TextEditingController();
  final _registerNameController = TextEditingController();
  final _registerEmailController = TextEditingController();
  final _registerPasswordController = TextEditingController();

  bool _loginInProgress = false;
  bool _registerInProgress = false;
  AppRole _selectedRole = AppRole.student;

  @override
  void dispose() {
    _loginEmailController.dispose();
    _loginPasswordController.dispose();
    _registerNameController.dispose();
    _registerEmailController.dispose();
    _registerPasswordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFF4F8F8), Color(0xFFE6F0EE), Color(0xFFF8F1DE)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Stack(
          children: [
            const Positioned(
              top: -80,
              right: -30,
              child: _GlowOrb(size: 230, color: Color(0x3318A0A0)),
            ),
            const Positioned(
              bottom: -70,
              left: -20,
              child: _GlowOrb(size: 250, color: Color(0x33DAA520)),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 1180),
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final useVertical = constraints.maxWidth < 920;

                        return Flex(
                          direction: useVertical
                              ? Axis.vertical
                              : Axis.horizontal,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(
                                  right: useVertical ? 0 : 20,
                                  bottom: useVertical ? 20 : 0,
                                ),
                                child: _LandingShowcase(theme: theme),
                              ),
                            ),
                            SizedBox(
                              width: useVertical ? double.infinity : 430,
                              child: _AuthCard(
                                loginForm: _buildLoginForm(context),
                                registerForm: _buildRegisterForm(context),
                              ),
                            ),
                          ],
                        );
                      },
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

  Widget _buildLoginForm(BuildContext context) {
    return Form(
      key: _loginFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _loginEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.alternate_email_rounded),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _loginPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.lock_outline_rounded),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _loginInProgress ? null : () => _signIn(context),
            child: Text(_loginInProgress ? 'Signing in...' : 'Login'),
          ),
          const SizedBox(height: 12),
          Text(
            'Use your registered email and password to access the portal.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildRegisterForm(BuildContext context) {
    return Form(
      key: _registerFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextFormField(
            controller: _registerNameController,
            decoration: const InputDecoration(
              labelText: 'Full name',
              prefixIcon: Icon(Icons.person_outline_rounded),
            ),
            validator: (value) {
              if (value == null || value.trim().length < 3) {
                return 'Enter your full name.';
              }
              return null;
            },
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerEmailController,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(
              labelText: 'Email address',
              prefixIcon: Icon(Icons.email_outlined),
            ),
            validator: _validateEmail,
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _registerPasswordController,
            obscureText: true,
            decoration: const InputDecoration(
              labelText: 'Password',
              prefixIcon: Icon(Icons.password_rounded),
            ),
            validator: _validatePassword,
          ),
          const SizedBox(height: 18),
          Text(
            'Choose account type',
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SegmentedButton<AppRole>(
            segments: const [
              ButtonSegment<AppRole>(
                value: AppRole.student,
                label: Text('Student'),
                icon: Icon(Icons.school_rounded),
              ),
              ButtonSegment<AppRole>(
                value: AppRole.faculty,
                label: Text('Faculty'),
                icon: Icon(Icons.co_present_rounded),
              ),
            ],
            selected: {_selectedRole},
            onSelectionChanged: (selection) {
              setState(() {
                _selectedRole = selection.first;
              });
            },
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF5FAFA),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0xFFD9E8E6)),
            ),
            child: const Text(
              'The very first account created becomes Admin automatically so you can manage feature access for faculty and students.',
            ),
          ),
          const SizedBox(height: 18),
          FilledButton(
            onPressed: _registerInProgress ? null : () => _register(context),
            child: Text(
              _registerInProgress ? 'Creating account...' : 'Create account',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signIn(BuildContext context) async {
    if (!_loginFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _loginInProgress = true;
    });

    try {
      await widget.repository.signIn(
        email: _loginEmailController.text.trim(),
        password: _loginPasswordController.text.trim(),
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _loginInProgress = false;
        });
      }
    }
  }

  Future<void> _register(BuildContext context) async {
    if (!_registerFormKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _registerInProgress = true;
    });

    try {
      await widget.repository.register(
        name: _registerNameController.text.trim(),
        email: _registerEmailController.text.trim(),
        password: _registerPasswordController.text.trim(),
        requestedRole: _selectedRole,
      );
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    } finally {
      if (mounted) {
        setState(() {
          _registerInProgress = false;
        });
      }
    }
  }

  String? _validateEmail(String? value) {
    if (value == null || value.trim().isEmpty || !value.contains('@')) {
      return 'Enter a valid email address.';
    }
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.trim().length < 6) {
      return 'Password must be at least 6 characters.';
    }
    return null;
  }
}

class _LandingShowcase extends StatelessWidget {
  const _LandingShowcase({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'A refined student portal powered by Firebase',
          style: theme.textTheme.displaySmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF12343B),
            height: 1.1,
          ),
        ),
        const SizedBox(height: 18),
        Text(
          'Manage student and faculty access with a clean sign-in flow, role-based dashboards, and admin feature controls built for daily use.',
          style: theme.textTheme.titleMedium?.copyWith(
            color: const Color(0xFF36575E),
            height: 1.5,
          ),
        ),
        const SizedBox(height: 28),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: const [
            _Pill(label: 'Firebase Auth'),
            _Pill(label: 'Firestore Roles'),
            _Pill(label: 'Admin Controls'),
            _Pill(label: 'Faculty + Student Views'),
          ],
        ),
        const SizedBox(height: 28),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                _ShowcaseRow(
                  icon: Icons.shield_rounded,
                  title: 'Admin control',
                  subtitle:
                      'The first registered account becomes admin and can manage what other roles can see.',
                ),
                SizedBox(height: 16),
                _ShowcaseRow(
                  icon: Icons.groups_rounded,
                  title: 'Role-aware access',
                  subtitle:
                      'Faculty and student dashboards only show the modules enabled for their role.',
                ),
                SizedBox(height: 16),
                _ShowcaseRow(
                  icon: Icons.palette_outlined,
                  title: 'Polished experience',
                  subtitle:
                      'The landing page is rebuilt with softer gradients, stronger hierarchy, and cleaner cards.',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _AuthCard extends StatelessWidget {
  const _AuthCard({required this.loginForm, required this.registerForm});

  final Widget loginForm;
  final Widget registerForm;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Welcome back',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in or create a portal account.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              Container(
                decoration: BoxDecoration(
                  color: const Color(0xFFF5F8F8),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const TabBar(
                  dividerColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: Color(0xFF0D5C63),
                    borderRadius: BorderRadius.all(Radius.circular(18)),
                  ),
                  labelColor: Colors.white,
                  unselectedLabelColor: Color(0xFF36575E),
                  tabs: [
                    Tab(text: 'Login'),
                    Tab(text: 'Register'),
                  ],
                ),
              ),
              const SizedBox(height: 22),
              SizedBox(
                height: 510,
                child: TabBarView(
                  children: [
                    SingleChildScrollView(child: loginForm),
                    SingleChildScrollView(child: registerForm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.75),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: const Color(0xFFD5E0E4)),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF12343B),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _ShowcaseRow extends StatelessWidget {
  const _ShowcaseRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF3F4),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: const Color(0xFF0D5C63)),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(subtitle),
            ],
          ),
        ),
      ],
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(colors: [color, color.withValues(alpha: 0)]),
      ),
    );
  }
}
