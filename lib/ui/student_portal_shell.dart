import 'package:flutter/material.dart';

import '../assessment/student_assessment_flow.dart';
import '../features/feature_catalog.dart';
import '../features/feature_visibility_service.dart';
import '../fyp/fyp_models.dart';
import '../fyp/fyp_section.dart';
import '../internships/internships_section.dart';
import '../models/app_role.dart';
import '../models/seating_plan_entry.dart';
import '../models/student_record.dart';
import '../modules/module_router.dart';
import '../modules/modules_common.dart';
import '../services/app_repository.dart';
import '../theme/theme_controller.dart';

// Legacy color tokens — kept so existing widgets keep compiling. Values now
// reference the new indigo + teal palette defined in `lib/theme/app_colors.dart`.
class PortalColors {
  static const Color brandBlue = Color(0xFF4F46E5); // indigo-600
  static const Color avatarBlue = Color(0xFF6366F1); // indigo-500
  static const Color avatarTeal = Color(0xFF14B8A6); // teal-500
  static const Color pageBackground = Color(0xFFF8FAFC); // slate-50
  static const Color textPrimary = Color(0xFF0F172A); // slate-900
  static const Color subtleText = Color(0xFF64748B); // slate-500
  static const Color navUnselected = Color(0xFF94A3B8); // slate-400
  static const Color blueBorder = Color(0xFFE0E7FF); // indigo-100
  static const Color mintBorder = Color(0xFFCCFBF1); // teal-100
  static const Color purpleBorder = Color(0xFFEDE9FE); // violet-100
  static const Color cardBorder = Color(0xFFE2E8F0); // slate-200
  static const Color softBlue = Color(0xFFEEF2FF); // indigo-50
  static const Color shadow = Color(0xFF0F172A); // slate-900 (use w/ low alpha)
}

class StudentPortalShell extends StatefulWidget {
  const StudentPortalShell({
    super.key,
    required this.repository,
    required this.student,
  });

  final AppRepository repository;
  final StudentRecord student;

  @override
  State<StudentPortalShell> createState() => _StudentPortalShellState();
}

class _StudentPortalShellState extends State<StudentPortalShell> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      _DashboardTab(
        student: widget.student,
        onOpenCourses: () => _setTab(1),
        onOpenExams: () => _setTab(2),
        onOpenRequests: () => _setTab(3),
        onOpenAssessments: () => _setTab(4),
      ),
      _CoursesTab(student: widget.student),
      _ExamsTab(repository: widget.repository, student: widget.student),
      const _RequestsTab(),
      StudentAssessmentFlow(
        repository: widget.repository,
        student: widget.student,
      ),
      _ProfileTab(
        student: widget.student,
        onLogout: () => _confirmLogout(context),
      ),
    ];

    return AppRepositoryAccess(
      repository: widget.repository,
      child: Scaffold(
        backgroundColor: PortalColors.pageBackground,
        body: SafeArea(
          child: Column(
            children: [
              _PortalTopBar(initials: portalInitials(widget.student.studentName)),
              Expanded(
                child: IndexedStack(index: _currentIndex, children: pages),
              ),
              _PortalBottomNav(currentIndex: _currentIndex, onTap: _setTab),
            ],
          ),
        ),
      ),
    );
  }

  void _setTab(int index) {
    setState(() => _currentIndex = index);
  }

  Future<void> _confirmLogout(BuildContext context) async {
    final shouldLogout = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Logout'),
          content: const Text('Do you want to logout from Students Portal?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Logout'),
            ),
          ],
        );
      },
    );

    if (shouldLogout == true) {
      widget.repository.signOut();
    }
  }
}

class _PortalTopBar extends StatelessWidget {
  const _PortalTopBar({required this.initials});

  final String initials;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          bottom: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
              boxShadow: [
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.25),
                  blurRadius: 16,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            alignment: Alignment.center,
            child: const Icon(
              Icons.school_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'AUST Student Portal',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                Text(
                  'Department of Computer Science',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Notifications',
            onPressed: () {
              showModalBottomSheet<void>(
                context: context,
                builder: (context) => SafeArea(
                  child: Padding(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Notifications',
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                        const SizedBox(height: 12),
                        const Text('No new notifications right now.'),
                      ],
                    ),
                  ),
                ),
              );
            },
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_none_rounded, size: 26),
                Positioned(
                  top: -1,
                  right: -1,
                  child: Container(
                    width: 9,
                    height: 9,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      shape: BoxShape.circle,
                      border: Border.all(color: scheme.surface, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.secondary],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              initials,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PortalBottomNav extends StatelessWidget {
  const _PortalBottomNav({required this.currentIndex, required this.onTap});

  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Dashboard',
      'Courses',
      'Exams',
      'Requests',
      'Assess',
      'Profile',
    ];
    const icons = [
      Icons.home_outlined,
      Icons.menu_book_outlined,
      Icons.calendar_today_outlined,
      Icons.description_outlined,
      Icons.assignment_outlined,
      Icons.person_outline_rounded,
    ];

    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 12),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Row(
        children: List.generate(labels.length, (index) {
          final selected = currentIndex == index;
          return Expanded(
            child: GestureDetector(
              onTap: () => onTap(index),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                margin: const EdgeInsets.symmetric(horizontal: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? scheme.primaryContainer
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      icons[index],
                      color: selected
                          ? scheme.primary
                          : (isDark
                              ? scheme.onSurfaceVariant
                              : PortalColors.navUnselected),
                      size: 24,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      labels[index],
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: selected
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: selected
                            ? scheme.primary
                            : (isDark
                                ? scheme.onSurfaceVariant
                                : PortalColors.navUnselected),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({
    required this.student,
    required this.onOpenCourses,
    required this.onOpenExams,
    required this.onOpenRequests,
    required this.onOpenAssessments,
  });

  final StudentRecord student;
  final VoidCallback onOpenCourses;
  final VoidCallback onOpenExams;
  final VoidCallback onOpenRequests;
  final VoidCallback onOpenAssessments;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        children: [
          _SectionCard(
            borderColor: PortalColors.blueBorder,
            child: Row(
              children: [
                const _StudentAvatar(),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student.studentName,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(
                              fontWeight: FontWeight.w800,
                              color: PortalColors.textPrimary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      _DetailLine(label: 'Roll No:', value: student.rollNo),
                      const SizedBox(height: 4),
                      _DetailLine(label: 'Program:', value: student.program),
                      const SizedBox(height: 4),
                      _DetailLine(label: 'Semester:', value: student.semester),
                      const SizedBox(height: 4),
                      _DetailLine(label: 'Section:', value: student.section),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _SectionCard(
            borderColor: PortalColors.mintBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeading(
                  icon: Icons.menu_book_outlined,
                  title: 'Academic Information',
                ),
                const SizedBox(height: 18),
                InkWell(
                  onTap: onOpenCourses,
                  borderRadius: BorderRadius.circular(16),
                  child: Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFF6FAFF), Color(0xFFEEFDFD)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: const Color(0xFFE7EEF8)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Courses Registered',
                                style: Theme.of(context).textTheme.titleMedium
                                    ?.copyWith(
                                      fontWeight: FontWeight.w800,
                                      color: PortalColors.textPrimary,
                                    ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '${student.courses.length} courses this semester',
                                style: Theme.of(context).textTheme.bodyLarge
                                    ?.copyWith(color: PortalColors.subtleText),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          'View',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                color: PortalColors.brandBlue,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.chevron_right_rounded,
                          color: PortalColors.brandBlue,
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.place_outlined,
                        label: 'Seating Plan',
                        onTap: onOpenExams,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _QuickActionCard(
                        icon: Icons.calendar_month_outlined,
                        label: 'Date Sheet',
                        onTap: onOpenExams,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                _QuickActionCard(
                  icon: Icons.assignment_outlined,
                  label: 'Assessment QR',
                  onTap: onOpenAssessments,
                ),
                const SizedBox(height: 12),
                const Row(
                  children: [
                    Expanded(
                      child: _CaseStatusCard(
                        label: 'UFM Cases',
                        status: 'Clear',
                      ),
                    ),
                    SizedBox(width: 12),
                    Expanded(
                      child: _CaseStatusCard(
                        label: 'Discipline Cases',
                        status: 'Clear',
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 18),
          _ModulesSection(student: student),
          if (_shouldShowFyp(student.program, student.semester)) ...[
            const SizedBox(height: 18),
            _SectionCard(
              borderColor: PortalColors.purpleBorder,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FINAL YEAR PROJECTS',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF5A5E72),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _FypItem(
                    title: 'Final Year Project I',
                    subtitle: 'Submit FYP-I group form and generate QR',
                    onTap: () => _openFyp(context, FypPhase.fyp1),
                  ),
                  _FypItem(
                    title: 'Final Year Project II',
                    subtitle: 'Submit FYP-II proforma',
                    onTap: () => _openFyp(context, FypPhase.fyp2),
                  ),
                  _FypItem(
                    title: 'Final Year Project III',
                    subtitle: 'Submit FYP-III proforma',
                    onTap: () => _openFyp(context, FypPhase.fyp3),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 18),
          _SectionCard(
            borderColor: PortalColors.cardBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'INTERNSHIPS',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: const Color(0xFF5A5E72),
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.8,
                  ),
                ),
                const SizedBox(height: 10),
                _FypItem(
                  title: 'Internships',
                  subtitle: 'Coming soon — opportunities and applications',
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const InternshipsSection(),
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

  void _openFyp(BuildContext context, FypPhase phase) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FypSection(
          repository: AppRepositoryAccess.of(context),
          student: student,
          initialPhase: phase,
        ),
      ),
    );
  }
}

/// Lightweight scoped accessor so the dashboard tab can reach the repository
/// it was constructed from without threading it through every callback.
class AppRepositoryAccess extends InheritedWidget {
  const AppRepositoryAccess({
    super.key,
    required this.repository,
    required super.child,
  });

  final AppRepository repository;

  static AppRepository of(BuildContext context) {
    final widget =
        context.dependOnInheritedWidgetOfExactType<AppRepositoryAccess>();
    assert(widget != null, 'AppRepositoryAccess not found in widget tree');
    return widget!.repository;
  }

  @override
  bool updateShouldNotify(AppRepositoryAccess oldWidget) =>
      repository != oldWidget.repository;
}

class _CoursesTab extends StatelessWidget {
  const _CoursesTab({required this.student});

  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _TabTitle(
            title: 'Courses',
            subtitle: 'Registered courses for this semester',
          ),
          const SizedBox(height: 16),
          ...student.courses.map((course) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _SectionCard(
                borderColor: PortalColors.cardBorder,
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFE8EEFF), Color(0xFFF2FCFC)],
                        ),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        course.code,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: PortalColors.brandBlue,
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            course.name,
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                  color: PortalColors.textPrimary,
                                ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            course.instructor.isEmpty
                                ? 'Instructor not assigned'
                                : course.instructor,
                            style: Theme.of(context).textTheme.bodyLarge
                                ?.copyWith(color: PortalColors.subtleText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _ExamsTab extends StatefulWidget {
  const _ExamsTab({required this.repository, required this.student});

  final AppRepository repository;
  final StudentRecord student;

  @override
  State<_ExamsTab> createState() => _ExamsTabState();
}

class _ExamsTabState extends State<_ExamsTab> {
  late Future<List<SeatingPlanEntry>> _seatingFuture;
  String? _selectedSubject;
  String? _selectedDate;

  @override
  void initState() {
    super.initState();
    _seatingFuture = widget.repository.loadSeatingPlan(widget.student.rollNo);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<SeatingPlanEntry>>(
      future: _seatingFuture,
      builder: (context, snapshot) {
        final seatingEntries = snapshot.data ?? const <SeatingPlanEntry>[];
        final dateSheetEntries = _buildDateSheetEntries(seatingEntries);
        final subjects =
            seatingEntries
                .map((entry) => entry.subject)
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        final dates =
            seatingEntries
                .map((entry) => entry.examDate)
                .where((value) => value.isNotEmpty)
                .toSet()
                .toList()
              ..sort();

        final filtered = seatingEntries.where((entry) {
          final subjectMatches =
              _selectedSubject == null || entry.subject == _selectedSubject;
          final dateMatches =
              _selectedDate == null || entry.examDate == _selectedDate;
          return subjectMatches && dateMatches;
        }).toList();

        return SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _TabTitle(
                title: 'Exams',
                subtitle: 'Select paper and date to view your seating plan',
              ),
              const SizedBox(height: 16),
              _SectionCard(
                borderColor: PortalColors.mintBorder,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seating Plan',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 14),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (snapshot.hasError)
                      Text(
                        'Unable to load seating plan right now.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      )
                    else if (seatingEntries.isEmpty)
                      Text(
                        'No seating plan found for roll number ${widget.student.rollNo}.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PortalColors.subtleText,
                        ),
                      )
                    else ...[
                      _FilterDropdown(
                        label: 'Paper',
                        value: _selectedSubject,
                        items: subjects,
                        onChanged: (value) {
                          setState(() {
                            _selectedSubject = value;
                          });
                        },
                      ),
                      const SizedBox(height: 12),
                      _FilterDropdown(
                        label: 'Date',
                        value: _selectedDate,
                        items: dates,
                        onChanged: (value) {
                          setState(() {
                            _selectedDate = value;
                          });
                        },
                      ),
                      const SizedBox(height: 16),
                      ...filtered.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _SectionCard(
                            borderColor: PortalColors.blueBorder,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  entry.subject,
                                  style: Theme.of(context).textTheme.titleMedium
                                      ?.copyWith(
                                        fontWeight: FontWeight.w800,
                                        color: PortalColors.textPrimary,
                                      ),
                                ),
                                const SizedBox(height: 10),
                                _ProfileLine(
                                  label: 'Exam Date',
                                  value: entry.examDate,
                                ),
                                const SizedBox(height: 8),
                                _ProfileLine(
                                  label: 'Shift',
                                  value: entry.shift,
                                ),
                                const SizedBox(height: 8),
                                _ProfileLine(
                                  label: 'Chair No',
                                  value: entry.chairNo,
                                ),
                                const SizedBox(height: 8),
                                _ProfileLine(
                                  label: 'Column',
                                  value: entry.column,
                                ),
                                const SizedBox(height: 8),
                                _ProfileLine(
                                  label: 'Faculty',
                                  value: entry.faculty,
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _SectionCard(
                borderColor: PortalColors.cardBorder,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Date Sheet',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (snapshot.connectionState == ConnectionState.waiting)
                      const Center(child: CircularProgressIndicator())
                    else if (snapshot.hasError)
                      Text(
                        'Unable to load date sheet right now.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.red.shade700,
                        ),
                      )
                    else if (dateSheetEntries.isEmpty)
                      Text(
                        'No date sheet found for roll number ${widget.student.rollNo}.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: PortalColors.subtleText,
                        ),
                      )
                    else
                      ...dateSheetEntries.map((entry) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _RequestItem(
                            title: entry.subject,
                            subtitle: '${entry.examDate} • ${entry.shift}',
                          ),
                        );
                      }),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  List<_DateSheetEntry> _buildDateSheetEntries(List<SeatingPlanEntry> entries) {
    final uniqueEntries = <String, _DateSheetEntry>{};
    for (final entry in entries) {
      final subject = entry.subject.trim();
      final examDate = entry.examDate.trim();
      final shift = entry.shift.trim();
      final key =
          '${subject.toLowerCase()}|${examDate.toLowerCase()}|${shift.toLowerCase()}';
      if (subject.isEmpty || examDate.isEmpty) {
        continue;
      }
      uniqueEntries.putIfAbsent(
        key,
        () => _DateSheetEntry(
          subject: subject,
          examDate: examDate,
          shift: shift.isEmpty ? 'Schedule will be announced' : shift,
        ),
      );
    }

    final list = uniqueEntries.values.toList();
    list.sort((a, b) {
      final dateCompare = a.examDate.compareTo(b.examDate);
      if (dateCompare != 0) {
        return dateCompare;
      }
      return a.subject.compareTo(b.subject);
    });
    return list;
  }
}

class _DateSheetEntry {
  const _DateSheetEntry({
    required this.subject,
    required this.examDate,
    required this.shift,
  });

  final String subject;
  final String examDate;
  final String shift;
}

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _TabTitle(
            title: 'Requests',
            subtitle: 'Submit academic requests and applications',
          ),
          SizedBox(height: 16),
          _RequestItem(
            title: 'Special Exam Request',
            subtitle: 'Request for special exam due to emergency',
          ),
          _RequestItem(
            title: 'Midterm Exam Request',
            subtitle: 'Request for midterm examination',
          ),
          _RequestItem(
            title: 'Final Term Exam Request',
            subtitle: 'Request for final term examination',
          ),
          _RequestItem(
            title: 'Condensed Semester Enrollment',
            subtitle: 'Apply for condensed semester',
          ),
        ],
      ),
    );
  }
}

class _ProfileTab extends StatelessWidget {
  const _ProfileTab({required this.student, required this.onLogout});

  final StudentRecord student;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        children: [
          _SectionCard(
            borderColor: PortalColors.blueBorder,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const _StudentAvatar(),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            student.studentName,
                            style: Theme.of(context).textTheme.headlineSmall
                                ?.copyWith(fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            student.rollNo,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: PortalColors.subtleText),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 14),
                _ProfileLine(label: 'Program', value: student.program),
                const SizedBox(height: 12),
                _ProfileLine(label: 'Semester', value: student.semester),
                const SizedBox(height: 12),
                _ProfileLine(label: 'Section', value: student.section),
                const SizedBox(height: 12),
                _ProfileLine(label: 'Session', value: student.currentSession),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const _AppearanceCard(),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onLogout,
              icon: const Icon(Icons.logout_rounded),
              label: const Text('Logout'),
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceCard extends StatelessWidget {
  const _AppearanceCard();

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        final current = ThemeController.instance.mode;
        return _SectionCard(
          borderColor: PortalColors.cardBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    ThemeController.instance.icon,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Appearance',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Choose how the app looks. System default follows your phone setting.',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: PortalColors.subtleText,
                    ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mode in ThemeMode.values)
                    ChoiceChip(
                      selected: current == mode,
                      label: Text(
                        switch (mode) {
                          ThemeMode.system => 'System',
                          ThemeMode.light => 'Light',
                          ThemeMode.dark => 'Dark',
                        },
                      ),
                      avatar: Icon(
                        switch (mode) {
                          ThemeMode.system => Icons.brightness_auto_outlined,
                          ThemeMode.light => Icons.light_mode_outlined,
                          ThemeMode.dark => Icons.dark_mode_outlined,
                        },
                        size: 18,
                      ),
                      onSelected: (_) =>
                          ThemeController.instance.setMode(mode),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, required this.borderColor});

  final Widget child;
  final Color borderColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: borderColor, width: 1.6),
        boxShadow: [
          BoxShadow(
            color: PortalColors.shadow.withValues(alpha: 0.12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _StudentAvatar extends StatelessWidget {
  const _StudentAvatar();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 74,
      height: 74,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          colors: [PortalColors.avatarBlue, PortalColors.avatarTeal],
        ),
        border: Border.all(color: const Color(0xFFEAF3FF), width: 3),
        boxShadow: [
          BoxShadow(
            color: PortalColors.avatarBlue.withValues(alpha: 0.22),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: const Icon(
        Icons.person_outline_rounded,
        color: Colors.white,
        size: 34,
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: PortalColors.brandBlue, size: 25),
        const SizedBox(width: 10),
        Text(
          title,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
            fontWeight: FontWeight.w800,
            color: PortalColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _QuickActionCard extends StatelessWidget {
  const _QuickActionCard({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PortalColors.cardBorder, width: 1.5),
        ),
        child: Column(
          children: [
            Icon(icon, color: PortalColors.brandBlue, size: 24),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: PortalColors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CaseStatusCard extends StatelessWidget {
  const _CaseStatusCard({required this.label, required this.status});

  final String label;
  final String status;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 15),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEFFCF5), Color(0xFFE8FBF1)],
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFCFF4DE), width: 1.3),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: PortalColors.subtleText,
              ),
            ),
          ),
          Text(
            status,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFFF6FFF9),
              shadows: [Shadow(color: Color(0x6650B98A), blurRadius: 10)],
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestItem extends StatelessWidget {
  const _RequestItem({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: PortalColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.description_outlined,
              color: PortalColors.subtleText,
              size: 24,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: PortalColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: PortalColors.subtleText,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(
              Icons.chevron_right_rounded,
              color: Color(0xFFACB4C7),
              size: 26,
            ),
          ],
        ),
      ),
    );
  }
}

class _FypItem extends StatelessWidget {
  const _FypItem({
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFF0FFFC), Color(0xFFE9FFFC)],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PortalColors.mintBorder, width: 1.4),
          ),
          child: Row(
            children: [
              const Icon(
                Icons.info_outline_rounded,
                color: PortalColors.avatarTeal,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: PortalColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(
                Icons.chevron_right_rounded,
                color: PortalColors.avatarTeal,
                size: 26,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProfileLine extends StatelessWidget {
  const _ProfileLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(
          context,
        ).textTheme.titleMedium?.copyWith(color: PortalColors.subtleText),
        children: [
          TextSpan(
            text: '$label: ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: PortalColors.textPrimary,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

class _FilterDropdown extends StatelessWidget {
  const _FilterDropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String label;
  final String? value;
  final List<String> items;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<String>(
      initialValue: value,
      decoration: InputDecoration(labelText: label),
      items: [
        const DropdownMenuItem<String>(value: null, child: Text('All')),
        ...items.map((item) {
          return DropdownMenuItem<String>(value: item, child: Text(item));
        }),
      ],
      onChanged: onChanged,
    );
  }
}

class _TabTitle extends StatelessWidget {
  const _TabTitle({required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.w800,
            color: PortalColors.textPrimary,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          subtitle,
          style: Theme.of(
            context,
          ).textTheme.bodyLarge?.copyWith(color: PortalColors.subtleText),
        ),
      ],
    );
  }
}

class _DetailLine extends StatelessWidget {
  const _DetailLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return RichText(
      text: TextSpan(
        style: Theme.of(context).textTheme.titleMedium?.copyWith(
          color: PortalColors.subtleText,
          height: 1.45,
        ),
        children: [
          TextSpan(
            text: '$label ',
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: PortalColors.textPrimary,
            ),
          ),
          TextSpan(text: value),
        ],
      ),
    );
  }
}

bool _shouldShowFyp(String program, String semester) {
  final semesterNumber = int.tryParse(semester);
  final normalizedProgram = program.toLowerCase();
  return semesterNumber != null &&
      semesterNumber >= 7 &&
      (normalizedProgram.contains('cs') ||
          normalizedProgram.contains('computer') ||
          normalizedProgram.contains('se') ||
          normalizedProgram.contains('software'));
}

class _ModulesSection extends StatelessWidget {
  const _ModulesSection({required this.student});
  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FeatureVisibilityService.instance,
      builder: (context, _) {
        final visible = FeatureVisibilityService.instance
            .visibleFor(AppRole.student)
            // FYP and Internships have their own dedicated cards on the
            // dashboard, so skip them in the modules grid to avoid dupes.
            .where((meta) =>
                meta.key != FeatureKey.fyp &&
                meta.key != FeatureKey.internships)
            .toList();
        if (visible.isEmpty) return const SizedBox.shrink();
        final repository = AppRepositoryAccess.of(context);
        return _SectionCard(
          borderColor: PortalColors.blueBorder,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'MODULES',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: const Color(0xFF5A5E72),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
              ),
              const SizedBox(height: 10),
              ModuleCardGrid(
                cards: [
                  for (final meta in visible)
                    ModuleCardData(
                      title: meta.label,
                      icon: meta.icon,
                      color: meta.color,
                      onTap: () => ModuleRouter.open(
                        context,
                        feature: meta.key,
                        repository: repository,
                        student: student,
                      ),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

String portalInitials(String fullName) {
  final parts = fullName
      .trim()
      .split(RegExp(r'\s+'))
      .where((part) => part.isNotEmpty)
      .toList();
  if (parts.isEmpty) {
    return 'SP';
  }
  if (parts.length == 1) {
    final only = parts.first.toUpperCase();
    return only.length >= 2 ? only.substring(0, 2) : only;
  }
  return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
}
