import 'package:flutter/material.dart';

import '../assessment/assessment_models.dart';
import '../connect/connect_home_page.dart';
import '../connect/event_home_page.dart';
import '../connect/connect_models.dart';
import '../features/admin_feature_controls_page.dart';
import '../features/admin_data_sync_page.dart';
import '../features/admin_password_manager_page.dart';
import '../features/answer_sheet_tracker_page.dart';
import '../fyp/fyp_groups_tabs.dart';
import '../features/assessment_access_page.dart';
import '../features/change_password_page.dart';
import '../features/slot_collection_page.dart';
import '../models/portal_session.dart';
import '../models/student_directory_summary.dart';
import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../services/device_binding_service.dart';
import '../services/login_store.dart';
import '../theme/app_colors.dart';
import '../theme/theme_controller.dart';
import '../theme/theme_picker.dart';
import 'shared_widgets.dart';
import 'student_portal_shell.dart';

Future<void> _confirmLogout(
  BuildContext context,
  AppRepository repository,
) async {
  final shouldLogout = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Logout'),
      content: const Text('Are you sure you want to logout?'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Logout'),
        ),
      ],
    ),
  );
  if (shouldLogout == true) {
    repository.signOut();
  }
}

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.session,
  });

  final AppRepository repository;
  final PortalSession session;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (session.isAdmin && constraints.maxWidth >= 1050) {
          return _AdminDesktopShell(repository: repository, session: session);
        }

        return Scaffold(
          appBar: AppBar(
            title: const Text('AUST Student Portal'),
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Chip(
                  avatar: Icon(
                    session.isAdmin
                        ? Icons.admin_panel_settings_rounded
                        : Icons.school_rounded,
                    size: 18,
                  ),
                  label: Text(session.isAdmin ? 'Admin' : 'Student'),
                ),
              ),
              const AppearanceButton(),
              IconButton(
                tooltip: 'Logout',
                onPressed: () => _confirmLogout(context, repository),
                icon: const Icon(Icons.logout_rounded),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1100),
                child: session.isAdmin
                    ? _AdminDashboard(repository: repository)
                    : _StudentDashboard(student: session.student!),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminDesktopShell extends StatefulWidget {
  const _AdminDesktopShell({required this.repository, required this.session});

  final AppRepository repository;
  final PortalSession session;

  @override
  State<_AdminDesktopShell> createState() => _AdminDesktopShellState();
}

class _AdminDesktopShellState extends State<_AdminDesktopShell> {
  final ScrollController _scrollController = ScrollController();
  int _selectedSection = 0;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollTo(int section, double offset) {
    setState(() => _selectedSection = section);
    _scrollController.animateTo(
      offset,
      duration: const Duration(milliseconds: 420),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark
        ? Theme.of(context).colorScheme.surface
        : const Color(0xFFEAF5FF);

    return Scaffold(
      backgroundColor: background,
      body: Row(
        children: [
          SizedBox(
            width: 286,
            child: _AdminSidebar(
              username: widget.session.username,
              selectedIndex: _selectedSection,
              onDashboard: () => _scrollTo(0, 0),
              onAssessments: () => _scrollTo(1, 620),
              onVerification: () => _scrollTo(2, 1350),
              onFeatureControls: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminFeatureControlsPage(),
                ),
              ),
              onAnswerSheets: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AnswerSheetTrackerPage(),
                ),
              ),
              onSlotCollection: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const SlotCollectionPage(),
                ),
              ),
              onAssessmentAccess: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      AssessmentAccessPage(repository: widget.repository),
                ),
              ),
              onChangePassword: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) =>
                      ChangePasswordPage(repository: widget.repository),
                ),
              ),
              onAppearance: () => showAppearanceSheet(context),
              onLogout: () => _confirmLogout(context, widget.repository),
            ),
          ),
          Expanded(
            child: Stack(
              children: [
                Positioned(
                  top: -170,
                  right: -110,
                  child: _AmbientCircle(
                    size: 420,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.06),
                  ),
                ),
                Positioned(
                  bottom: -220,
                  left: 120,
                  child: _AmbientCircle(
                    size: 520,
                    color: Theme.of(
                      context,
                    ).colorScheme.secondary.withValues(alpha: 0.05),
                  ),
                ),
                SafeArea(
                  child: SingleChildScrollView(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(40, 34, 40, 48),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1480),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Dashboard',
                                        style: Theme.of(context)
                                            .textTheme
                                            .displayMedium
                                            ?.copyWith(
                                              fontSize: 36,
                                              fontWeight: FontWeight.w800,
                                              letterSpacing: -0.8,
                                            ),
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        'Welcome to your student portal command center.',
                                        style: Theme.of(context)
                                            .textTheme
                                            .titleMedium
                                            ?.copyWith(
                                              color: Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                              fontWeight: FontWeight.w500,
                                            ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 20),
                                const _DesktopThemePill(),
                              ],
                            ),
                            const SizedBox(height: 34),
                            _AdminDashboard(
                              repository: widget.repository,
                              desktop: true,
                              showHero: false,
                            ),
                          ],
                        ),
                      ),
                    ),
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

class _AmbientCircle extends StatelessWidget {
  const _AmbientCircle({required this.size, required this.color});

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

class _DesktopThemePill extends StatelessWidget {
  const _DesktopThemePill();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final controller = ThemeController.instance;
        return Material(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          elevation: 0,
          child: InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => showAppearanceSheet(context),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Theme.of(context).dividerColor),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 22,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.palette_rounded,
                    size: 20,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  const Text(
                    'Themes',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    controller.palette.label,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdminSidebar extends StatelessWidget {
  const _AdminSidebar({
    required this.username,
    required this.selectedIndex,
    required this.onDashboard,
    required this.onAssessments,
    required this.onVerification,
    required this.onFeatureControls,
    required this.onAnswerSheets,
    required this.onSlotCollection,
    required this.onAssessmentAccess,
    required this.onChangePassword,
    required this.onAppearance,
    required this.onLogout,
  });

  final String username;
  final int selectedIndex;
  final VoidCallback onDashboard;
  final VoidCallback onAssessments;
  final VoidCallback onVerification;
  final VoidCallback onFeatureControls;
  final VoidCallback onAnswerSheets;
  final VoidCallback onSlotCollection;
  final VoidCallback onAssessmentAccess;
  final VoidCallback onChangePassword;
  final VoidCallback onAppearance;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final items = [
      ('Dashboard', Icons.dashboard_rounded, onDashboard, 0),
      ('Assessments', Icons.assignment_rounded, onAssessments, 1),
      ('Verification Access', Icons.verified_user_rounded, onVerification, 2),
      ('Feature Controls', Icons.tune_rounded, onFeatureControls, -1),
      ('Answer Sheets', Icons.assignment_returned_rounded, onAnswerSheets, -1),
      ('Per-Slot Collection', Icons.fact_check_rounded, onSlotCollection, -1),
      ('Teacher Access', Icons.assignment_ind_rounded, onAssessmentAccess, -1),
      ('Change Password', Icons.password_rounded, onChangePassword, -1),
      ('Themes', Icons.palette_rounded, onAppearance, -1),
    ];

    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF173F68), Color(0xFF2E6FA4)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 24, 12, 18),
          child: Column(
            children: [
              Container(
                width: 82,
                height: 82,
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.24),
                  ),
                ),
                child: ClipOval(
                  child: Image.asset('assets/cs_logo.jpeg', fit: BoxFit.cover),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'AUST Portal',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Academic control center',
                style: TextStyle(
                  color: Color(0xFFCCE5FA),
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 24),
              Expanded(
                child: ListView.separated(
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    final selected = item.$4 == selectedIndex;
                    return _SidebarItem(
                      label: item.$1,
                      icon: item.$2,
                      selected: selected,
                      onTap: item.$3,
                    );
                  },
                ),
              ),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    const CircleAvatar(
                      radius: 22,
                      backgroundColor: Color(0xFF67D5EE),
                      child: Icon(Icons.person_rounded, color: Colors.white),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            username,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const Text(
                            'Administrator',
                            style: TextStyle(
                              color: Color(0xFFCCE5FA),
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Logout',
                      onPressed: onLogout,
                      icon: const Icon(Icons.logout_rounded),
                      color: Colors.white,
                    ),
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

class _SidebarItem extends StatelessWidget {
  const _SidebarItem({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected
          ? Colors.white.withValues(alpha: 0.20)
          : Colors.transparent,
      borderRadius: BorderRadius.circular(15),
      child: InkWell(
        borderRadius: BorderRadius.circular(15),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            border: selected
                ? Border.all(color: Colors.white.withValues(alpha: 0.28))
                : null,
          ),
          child: Row(
            children: [
              Icon(icon, color: Colors.white, size: 21),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard({
    required this.repository,
    this.desktop = false,
    this.showHero = true,
  });

  final AppRepository repository;
  final bool desktop;
  final bool showHero;

  @override
  State<_AdminDashboard> createState() => _AdminDashboardState();
}

class _AdminDashboardState extends State<_AdminDashboard> {
  final _officerNameController = TextEditingController();
  final _officerRollController = TextEditingController();
  late final Future<StudentDirectorySummary> _summaryFuture;

  @override
  void initState() {
    super.initState();
    _summaryFuture = widget.repository.loadAdminSummary();
  }

  @override
  void dispose() {
    _officerNameController.dispose();
    _officerRollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StudentDirectorySummary>(
      future: _summaryFuture,
      builder: (context, snapshot) {
        final summary = snapshot.data;
        final officers = widget.repository.verificationOfficers;
        final teachers = widget.repository.teachers;
        final courses = widget.repository.assessmentCourses;
        final assessments = widget.repository.assessments;
        final activeAssessments = assessments
            .where((assessment) => assessment.status == AssessmentStatus.active)
            .toList();
        final pendingRequests = widget.repository.verificationRequests
            .where((request) => request.status == VerificationStatus.pending)
            .toList();

        final scheme = Theme.of(context).colorScheme;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.showHero) ...[
              _AdminHeroCard(
                studentCount: summary?.studentCount,
                enrollmentCount: summary?.courseRegistrationCount,
                teacherCount: teachers.length,
                activeAssessments: activeAssessments.length,
              ),
              const SizedBox(height: 18),
              _QuickActionsRow(
                repository: widget.repository,
                onOpenFeatureControls: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminFeatureControlsPage(),
                  ),
                ),
              ),
              const SizedBox(height: 22),
            ],
            Text(
              'OVERVIEW',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
                letterSpacing: 1.2,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 10),
            LayoutBuilder(
              builder: (context, constraints) {
                final crossCount = constraints.maxWidth > 900
                    ? 4
                    : constraints.maxWidth > 600
                    ? 3
                    : 2;
                final spacing = 12.0;
                final tileWidth =
                    (constraints.maxWidth - spacing * (crossCount - 1)) /
                    crossCount;
                return Wrap(
                  spacing: spacing,
                  runSpacing: spacing,
                  children: [
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Students',
                        value: summary == null
                            ? '…'
                            : '${summary.studentCount}',
                        subtitle: 'Unique rolls in DB',
                        color: AppColors.indigo600,
                        icon: Icons.groups_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Enrollments',
                        value: summary == null
                            ? '…'
                            : '${summary.courseRegistrationCount}',
                        subtitle: 'Course rows',
                        color: AppColors.teal600,
                        icon: Icons.dataset_linked_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Teachers',
                        value: '${teachers.length}',
                        subtitle: 'Faculty accounts',
                        color: AppColors.violet600,
                        icon: Icons.co_present_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Courses',
                        value: '${courses.length}',
                        subtitle: 'Sections',
                        color: AppColors.amber600,
                        icon: Icons.class_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Assessments',
                        value: '${assessments.length}',
                        subtitle: '${activeAssessments.length} live',
                        color: AppColors.teal700,
                        icon: Icons.assignment_turned_in_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Verifiers',
                        value: '${officers.length}',
                        subtitle: 'Fast-track access',
                        color: AppColors.indigo500,
                        icon: Icons.verified_user_rounded,
                      ),
                    ),
                    SizedBox(
                      width: tileWidth,
                      child: _StatCard(
                        title: 'Pending',
                        value: '${pendingRequests.length}',
                        subtitle: 'Identity checks',
                        color: AppColors.danger600,
                        icon: Icons.person_search_rounded,
                      ),
                    ),
                  ],
                );
              },
            ),
            if (widget.desktop) ...[
              const SizedBox(height: 24),
              _QuickActionsRow(
                repository: widget.repository,
                onOpenFeatureControls: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AdminFeatureControlsPage(),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Assessment workspace',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Teacher dashboard, course selection, PDF paper generation, live QR sharing, locked student attempt flow, and QR attendance are enabled in the local app.',
                    ),
                    const SizedBox(height: 18),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 820;
                        final assessmentPanel = _AdminListPanel(
                          title: 'Recent assessments',
                          icon: Icons.assignment_outlined,
                          children: assessments.take(5).map((assessment) {
                            return _AdminMiniRow(
                              title: assessment.title,
                              subtitle:
                                  '${assessment.type.label} - ${assessment.status.label} - ${assessment.totalMarks} marks',
                            );
                          }).toList(),
                        );
                        final facultyPanel = _AdminListPanel(
                          title: 'Faculty coverage',
                          icon: Icons.groups_2_outlined,
                          children: teachers.take(5).map((teacher) {
                            return _AdminMiniRow(
                              title: teacher.name,
                              subtitle:
                                  '${teacher.courseIds.length} course sections assigned',
                            );
                          }).toList(),
                        );

                        if (wide) {
                          return Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: assessmentPanel),
                              const SizedBox(width: 14),
                              Expanded(child: facultyPanel),
                            ],
                          );
                        }
                        return Column(
                          children: [
                            assessmentPanel,
                            const SizedBox(height: 14),
                            facultyPanel,
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Database connection details',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      summary == null
                          ? 'Reading local enrollment records...'
                          : 'Matched data path: ${summary.matchedPath}',
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      'Admin login is username admin (the admin password is set '
                      'by you and is not saved on the device). Student login is '
                      'roll number and password 1234.',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            const _DeviceAssignmentCard(),
            const SizedBox(height: 24),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Verification access',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Admin can assign class representatives or sub-admins so many students can be verified faster.',
                    ),
                    const SizedBox(height: 16),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final wide = constraints.maxWidth >= 720;
                        final nameField = TextField(
                          controller: _officerNameController,
                          decoration: const InputDecoration(
                            labelText: 'Name',
                            prefixIcon: Icon(Icons.person_outline),
                          ),
                        );
                        final rollField = TextField(
                          controller: _officerRollController,
                          decoration: const InputDecoration(
                            labelText: 'Roll no / ID',
                            prefixIcon: Icon(Icons.badge_outlined),
                          ),
                        );
                        final grantButton = FilledButton.icon(
                          onPressed: _grantAccess,
                          icon: const Icon(Icons.add_moderator_outlined),
                          label: const Text('Grant access'),
                        );
                        // Narrow (phone): stack vertically — NO Expanded inside
                        // a Column in a scroll view (that throws an unbounded
                        // height error and blanks the whole dashboard).
                        if (wide) {
                          return Row(
                            children: [
                              Expanded(child: nameField),
                              const SizedBox(width: 12),
                              Expanded(child: rollField),
                              const SizedBox(width: 12),
                              grantButton,
                            ],
                          );
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            nameField,
                            const SizedBox(height: 12),
                            rollField,
                            const SizedBox(height: 12),
                            grantButton,
                          ],
                        );
                      },
                    ),
                    const SizedBox(height: 16),
                    if (officers.isEmpty)
                      const Text('No verifier access assigned yet.')
                    else
                      Column(
                        children: officers.map((officer) {
                          final scheme = Theme.of(context).colorScheme;
                          return Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: Theme.of(context).dividerColor,
                              ),
                            ),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.verified_user_outlined,
                                  color: scheme.primary,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        officer.name,
                                        style: const TextStyle(
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      Text(
                                        '${officer.rollNo} - ${officer.accessLevel}',
                                      ),
                                    ],
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'Revoke access',
                                  onPressed: () {
                                    setState(() {
                                      widget.repository
                                          .revokeVerificationAccess(officer.id);
                                    });
                                  },
                                  icon: const Icon(Icons.delete_outline),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                      ),
                  ],
                ),
              ),
            ),
            if (snapshot.hasError) ...[
              const SizedBox(height: 16),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB8860B),
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Text(friendlyError(snapshot.error))),
                    ],
                  ),
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  void _grantAccess() {
    try {
      setState(() {
        widget.repository.grantVerificationAccess(
          name: _officerNameController.text,
          rollNo: _officerRollController.text,
        );
      });
      _officerNameController.clear();
      _officerRollController.clear();
    } catch (error) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(friendlyError(error))));
    }
  }
}

class _AdminListPanel extends StatelessWidget {
  const _AdminListPanel({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).dividerColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (children.isEmpty)
            const Text('No records available yet.')
          else
            ...children,
        ],
      ),
    );
  }
}

class _AdminMiniRow extends StatelessWidget {
  const _AdminMiniRow({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.secondary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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

class _StudentDashboard extends StatelessWidget {
  const _StudentDashboard({required this.student});

  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Welcome ${student.studentName}',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Roll No',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  student.rollNo,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Wrap(
              spacing: 24,
              runSpacing: 20,
              children: [
                _InfoBlock(label: 'Program', value: student.program),
                _InfoBlock(label: 'Semester', value: student.semester),
                _InfoBlock(label: 'Section', value: student.section),
              ],
            ),
          ),
        ),
        const SizedBox(height: 24),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Registered courses',
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 14),
                if (student.courses.isEmpty)
                  const Text(
                    'No course information was found for this roll number.',
                  )
                else
                  Column(
                    children: student.courses.map((course) {
                      final scheme = Theme.of(context).colorScheme;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: scheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: Theme.of(context).dividerColor,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  color: scheme.primaryContainer,
                                  borderRadius: BorderRadius.circular(14),
                                ),
                                child: Icon(
                                  Icons.menu_book_rounded,
                                  color: scheme.primary,
                                ),
                              ),
                              const SizedBox(width: 14),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${course.code} - ${course.name}',
                                      style: Theme.of(context)
                                          .textTheme
                                          .titleMedium
                                          ?.copyWith(
                                            fontWeight: FontWeight.w700,
                                          ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      course.instructor.isEmpty
                                          ? 'Instructor not assigned yet'
                                          : 'Instructor: ${course.instructor}',
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _InfoBlock extends StatelessWidget {
  const _InfoBlock({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 220,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            value.isEmpty ? '-' : value,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 158),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Theme.of(context).dividerColor),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF16456E).withValues(alpha: 0.07),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  value,
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.8,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [color.withValues(alpha: 0.72), color],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(icon, color: Colors.white, size: 27),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// New admin hero & quick actions widgets
// ============================================================================
class _AdminHeroCard extends StatelessWidget {
  const _AdminHeroCard({
    required this.studentCount,
    required this.enrollmentCount,
    required this.teacherCount,
    required this.activeAssessments,
  });

  final int? studentCount;
  final int? enrollmentCount;
  final int teacherCount;
  final int activeAssessments;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                  ),
                ),
                child: const Icon(
                  Icons.admin_panel_settings_rounded,
                  color: Colors.white,
                ),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Admin Control Room',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 19,
                      ),
                    ),
                    Text(
                      'AUST • Department of Computer Science',
                      style: TextStyle(
                        color: Color(0xFFEFF6FF),
                        fontWeight: FontWeight.w600,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _HeroStat(
                  label: 'Students',
                  value: studentCount == null ? '…' : '$studentCount',
                  icon: Icons.groups_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: 'Teachers',
                  value: '$teacherCount',
                  icon: Icons.co_present_rounded,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _HeroStat(
                  label: 'Live exams',
                  value: '$activeAssessments',
                  icon: Icons.assignment_turned_in_rounded,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _HeroStat extends StatelessWidget {
  const _HeroStat({
    required this.label,
    required this.value,
    required this.icon,
  });
  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFFEFF6FF),
              fontWeight: FontWeight.w600,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionsRow extends StatelessWidget {
  const _QuickActionsRow({
    required this.onOpenFeatureControls,
    required this.repository,
  });
  final VoidCallback onOpenFeatureControls;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'QUICK ACTIONS',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
            color: scheme.onSurfaceVariant,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 10),
        LayoutBuilder(
          builder: (context, constraints) {
            final crossCount = constraints.maxWidth > 700 ? 4 : 2;
            const spacing = 10.0;
            final tileWidth =
                (constraints.maxWidth - spacing * (crossCount - 1)) /
                crossCount;
            final tiles = <_QuickActionData>[
              _QuickActionData(
                title: 'Feature Controls',
                icon: Icons.tune_rounded,
                color: AppColors.indigo600,
                onTap: onOpenFeatureControls,
              ),
              _QuickActionData(
                title: 'Data Share',
                icon: Icons.sync_alt_rounded,
                color: AppColors.amber600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => AdminDataSyncPage(repository: repository),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'FYP Groups',
                icon: Icons.school_outlined,
                color: AppColors.violet600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const FypAdminGroupsPage(),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'AUST Connect',
                icon: Icons.forum_outlined,
                color: AppColors.teal600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ConnectHomePage(
                      identity: ConnectIdentity(
                        name: LoginStore.instance.currentUserName.trim().isEmpty
                            ? 'Admin'
                            : LoginStore.instance.currentUserName.trim(),
                        role: 'admin',
                        id: 'admin',
                      ),
                    ),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'AUST Event',
                icon: Icons.celebration_outlined,
                color: AppColors.violet600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => EventHomePage(
                      identity: ConnectIdentity(
                        name: LoginStore.instance.currentUserName.trim().isEmpty
                            ? 'Admin'
                            : LoginStore.instance.currentUserName.trim(),
                        role: 'admin',
                        id: 'admin',
                      ),
                    ),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Answer Sheets',
                icon: Icons.assignment_returned_outlined,
                color: AppColors.teal600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnswerSheetTrackerPage(),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Per-Slot Collection',
                icon: Icons.fact_check_outlined,
                color: AppColors.indigo600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const SlotCollectionPage(),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Teacher Access',
                icon: Icons.assignment_ind_outlined,
                color: AppColors.violet600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AssessmentAccessPage(repository: repository),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Change Password',
                icon: Icons.password_outlined,
                color: AppColors.teal600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ChangePasswordPage(repository: repository),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Manage Passwords',
                icon: Icons.lock_reset_rounded,
                color: AppColors.teal600,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        AdminPasswordManagerPage(repository: repository),
                  ),
                ),
              ),
              _QuickActionData(
                title: 'Manage Verifiers',
                icon: Icons.verified_user_outlined,
                color: AppColors.amber600,
                onTap: () {},
              ),
              _QuickActionData(
                title: 'Reports',
                icon: Icons.insert_chart_outlined_rounded,
                color: AppColors.violet600,
                onTap: () {},
              ),
            ];
            return Wrap(
              spacing: spacing,
              runSpacing: spacing,
              children: [
                for (final tile in tiles)
                  SizedBox(
                    width: tileWidth,
                    child: _QuickActionCard(data: tile),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _QuickActionData {
  const _QuickActionData({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({required this.data});
  final _QuickActionData data;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: data.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Theme.of(context).dividerColor),
          ),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: data.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(data.icon, color: data.color, size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  data.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Admin control: assign this device to one or more people, change or remove an
/// assignment, or release it entirely.
class _DeviceAssignmentCard extends StatelessWidget {
  const _DeviceAssignmentCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: DeviceBindingService.instance,
      builder: (context, _) {
        final b = DeviceBindingService.instance;
        final entries = b.entries;
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(22),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Device assignment',
                        style: Theme.of(context).textTheme.titleLarge
                            ?.copyWith(fontWeight: FontWeight.w800),
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed: () => _addPerson(context),
                      icon: const Icon(Icons.person_add_alt_1_outlined),
                      label: const Text('Add person'),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  value: b.allowAll,
                  onChanged: (v) =>
                      DeviceBindingService.instance.setAllowAll(v),
                  title: const Text(
                    'Allowed for ALL (students + teachers + admin)',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: const Text(
                    'Open device: anyone can sign in and the first login never '
                    'claims it. Turn off to use the assignments below.',
                    style: TextStyle(fontSize: 12),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  b.allowAll
                      ? 'Everyone can sign in on this device. Assignments '
                            'below are kept but not enforced while this is on.'
                      : entries.isEmpty
                      ? 'Not assigned yet. The first student or teacher who logs '
                            'in will claim this device — or add people below to '
                            'allow several.'
                      : 'Only these people (and Admin) can sign in on this '
                            'device:',
                ),
                const SizedBox(height: 6),
                for (final e in entries)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    leading: Icon(
                      e.role == 'faculty'
                          ? Icons.co_present_outlined
                          : Icons.school_outlined,
                    ),
                    title: Text(
                      e.label,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(
                      '${e.role == 'faculty' ? 'Teacher' : 'Student'}  •  ${e.key}',
                    ),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Remove',
                      onPressed: () =>
                          DeviceBindingService.instance.removePerson(e.key),
                    ),
                  ),
                if (entries.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  TextButton.icon(
                    onPressed: () async {
                      final ok = await _confirm(
                        context,
                        'Release this device?',
                        'All assignments are cleared. The next student or '
                            'teacher to log in will claim it.',
                      );
                      if (ok) await DeviceBindingService.instance.release();
                    },
                    icon: const Icon(Icons.lock_open_outlined),
                    label: const Text('Release (clear all)'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _addPerson(BuildContext context) async {
    var role = 'student';
    final keyCtrl = TextEditingController();
    final labelCtrl = TextEditingController();
    final add = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Assign a person'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<String>(
                initialValue: role,
                decoration: const InputDecoration(labelText: 'Role'),
                items: const [
                  DropdownMenuItem(value: 'student', child: Text('Student')),
                  DropdownMenuItem(value: 'faculty', child: Text('Teacher')),
                ],
                onChanged: (v) => setLocal(() => role = v ?? 'student'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: keyCtrl,
                decoration: InputDecoration(
                  labelText: role == 'faculty'
                      ? 'Teacher email / id'
                      : 'Roll number',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: labelCtrl,
                decoration: const InputDecoration(
                  labelText: 'Display name (optional)',
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
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
    if (add == true) {
      final ok = await DeviceBindingService.instance.addPerson(
        role: role,
        key: keyCtrl.text,
        label: labelCtrl.text,
      );
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              ok
                  ? 'Person assigned to this device.'
                  : 'Enter a valid roll/id (or it is already assigned).',
            ),
          ),
        );
      }
    }
  }

  Future<bool> _confirm(
    BuildContext context,
    String title,
    String body,
  ) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    return ok ?? false;
  }
}
