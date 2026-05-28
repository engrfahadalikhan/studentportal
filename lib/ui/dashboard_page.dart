import 'package:flutter/material.dart';

import '../assessment/assessment_models.dart';
import '../features/admin_feature_controls_page.dart';
import '../models/portal_session.dart';
import '../models/student_directory_summary.dart';
import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../theme/app_colors.dart';
import 'shared_widgets.dart';

Future<void> _confirmLogout(BuildContext context, AppRepository repository) async {
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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
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
  }
}

class _AdminDashboard extends StatefulWidget {
  const _AdminDashboard({required this.repository});

  final AppRepository repository;

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
            _AdminHeroCard(
              studentCount: summary?.studentCount,
              enrollmentCount: summary?.courseRegistrationCount,
              teacherCount: teachers.length,
              activeAssessments: activeAssessments.length,
            ),
            const SizedBox(height: 18),
            _QuickActionsRow(
              onOpenFeatureControls: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const AdminFeatureControlsPage(),
                ),
              ),
            ),
            const SizedBox(height: 22),
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
                        value:
                            summary == null ? 'â€¦' : '${summary.studentCount}',
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
                            ? 'â€¦'
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
                      'Admin login is username admin and password 1234. Student login is roll number and password 1234.',
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
                        final fields = [
                          Expanded(
                            child: TextField(
                              controller: _officerNameController,
                              decoration: const InputDecoration(
                                labelText: 'Name',
                                prefixIcon: Icon(Icons.person_outline),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12, height: 12),
                          Expanded(
                            child: TextField(
                              controller: _officerRollController,
                              decoration: const InputDecoration(
                                labelText: 'Roll no / ID',
                                prefixIcon: Icon(Icons.badge_outlined),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12, height: 12),
                          FilledButton.icon(
                            onPressed: _grantAccess,
                            icon: const Icon(Icons.add_moderator_outlined),
                            label: const Text('Grant access'),
                          ),
                        ];
                        if (wide) {
                          return Row(children: fields);
                        }
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: fields,
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
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
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
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w800,
            ),
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
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: Icon(icon, color: color),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              value,
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w900,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              title,
              style: Theme.of(context)
                  .textTheme
                  .titleSmall
                  ?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
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
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            scheme.primary.withValues(alpha: 0.88),
            scheme.secondary,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: 0.25),
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
                      'AUST â€¢ Department of Computer Science',
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
                  value: studentCount == null ? 'â€¦' : '$studentCount',
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
  const _QuickActionsRow({required this.onOpenFeatureControls});
  final VoidCallback onOpenFeatureControls;

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
                title: 'Manage Verifiers',
                icon: Icons.verified_user_outlined,
                color: AppColors.teal600,
                onTap: () {},
              ),
              _QuickActionData(
                title: 'Enrollment Sync',
                icon: Icons.refresh_rounded,
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
