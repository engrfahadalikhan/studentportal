import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../attendance/qr_attendance_section.dart';
import '../features/feature_catalog.dart';
import '../features/feature_visibility_service.dart';
import '../fyp/fyp_teacher_section.dart';
import '../models/app_role.dart';
import '../modules/module_router.dart';
import '../modules/modules_common.dart';
import '../services/app_repository.dart';
import '../services/teacher_dashboard_database.dart';
import '../ui/student_portal_shell.dart';
import 'assessment_models.dart';
import 'paper_generator_screen.dart';
import 'teacher_dashboard_models.dart';
import 'teacher_dashboard_theme.dart';
import 'teacher_dashboard_views.dart';

enum _TeacherSection {
  dashboard,
  courses,
  courseDetail,
  newAssessment,
  assessmentDetail,
  notifications,
  examAttendance,
  examScan,
  hallStats,
  takeExamAttendance,
  attendanceSheets,
  shareAttendance,
  attendanceSharing,
  builder,
  qr,
  attendance,
  live,
  results,
  fyp,
}

class TeacherAssessmentShell extends StatefulWidget {
  const TeacherAssessmentShell({
    super.key,
    required this.repository,
    required this.teacher,
  });

  final AppRepository repository;
  final AssessmentTeacher teacher;

  @override
  State<TeacherAssessmentShell> createState() => _TeacherAssessmentShellState();
}

class _TeacherAssessmentShellState extends State<TeacherAssessmentShell> {
  _TeacherSection _section = _TeacherSection.dashboard;
  AssessmentCourse? _selectedCourse;
  Assessment? _selectedAssessment;
  late final TeacherDashboardDatabase _dashboardDatabase;
  Future<TeacherDashboardHomeData>? _teacherHomeFuture;
  String? _selectedDbCourseId;
  String? _selectedDbAssessmentId;
  String? _selectedAttendanceSheetId;
  ExamHallStats? _selectedHallStats;
  String? _qrScanError;
  _TeacherSection _attendanceEditorBackSection = _TeacherSection.examAttendance;

  @override
  void initState() {
    super.initState();
    _dashboardDatabase = TeacherDashboardDatabase.instance;
    _reloadTeacherHome();
    widget.repository.ensureTeacherWorkspace(widget.teacher);
  }

  @override
  void didUpdateWidget(covariant TeacherAssessmentShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teacher.email != widget.teacher.email) {
      widget.repository.ensureTeacherWorkspace(widget.teacher);
      _reloadTeacherHome();
      _selectedCourse = null;
      _selectedAssessment = null;
      _selectedDbCourseId = null;
      _selectedDbAssessmentId = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        final courses = widget.repository.coursesForTeacher(widget.teacher);
        final assessments = widget.repository.assessmentsForTeacher(
          widget.teacher,
        );
        _selectedCourse ??= courses.isEmpty ? null : courses.first;
        _selectedAssessment ??= assessments.isEmpty ? null : assessments.first;

        return FutureBuilder<TeacherDashboardHomeData>(
          future: _teacherHomeFuture,
          builder: (context, snapshot) {
            final home = snapshot.data;

            return Scaffold(
              backgroundColor: PortalColors.pageBackground,
              bottomNavigationBar: _TeacherBottomNav(
                section: _section,
                onChanged: _go,
                onLogout: _confirmLogout,
              ),
              body: SafeArea(
                child: _buildSection(
                  courses,
                  assessments,
                  home,
                  snapshot.connectionState,
                  snapshot.error,
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSection(
    List<AssessmentCourse> courses,
    List<Assessment> assessments,
    TeacherDashboardHomeData? home,
    ConnectionState dbState,
    Object? dbError,
  ) {
    switch (_section) {
      case _TeacherSection.dashboard:
        if (dbError != null) {
          return _DatabaseMessage(message: dbError.toString());
        }
        if (home == null || dbState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return TeacherDashboardHomeView(
          data: home,
          onOpenCourse: _openDbCourse,
          onOpenNotifications: _openNotifications,
          onOpenExamAttendance: _openExamAttendance,
          onOpenFyp: () => _go(_TeacherSection.fyp),
          trailing: _TeacherModulesPanel(
            repository: widget.repository,
            teacher: widget.teacher,
          ),
        );
      case _TeacherSection.courses:
        if (home == null || dbState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator());
        }
        return RegisteredCoursesView(
          courses: home.courses,
          onOpenCourse: _openDbCourse,
        );
      case _TeacherSection.courseDetail:
        final courseId = _selectedDbCourseId;
        if (courseId == null) {
          return RegisteredCoursesView(
            courses: home?.courses ?? const [],
            onOpenCourse: _openDbCourse,
          );
        }
        return FutureBuilder<TeacherCourseDetailData>(
          future: _dashboardDatabase.loadCourseDetail(courseId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return CourseDetailView(
              data: snapshot.data!,
              onBack: () => _go(_TeacherSection.courses),
              onNewAssessment: () => _go(_TeacherSection.newAssessment),
              onOpenAssessment: _openDbAssessment,
            );
          },
        );
      case _TeacherSection.newAssessment:
        final courseId = _selectedDbCourseId;
        final course = courseId == null ? null : home?.courseById(courseId);
        if (course == null) {
          return RegisteredCoursesView(
            courses: home?.courses ?? const [],
            onOpenCourse: _openDbCourse,
          );
        }
        // The new-assessment flow now reuses the full Assessment Generator
        // so per-question time and possible answers can be configured.
        return PaperGeneratorScreen(
          repository: widget.repository,
          teacher: widget.teacher,
          initialCourseId: _resolveInitialCourseId(course.id),
          onAssessmentCreated: (assessment) {
            setState(() {
              _selectedAssessment = assessment;
              _section = _TeacherSection.qr;
            });
          },
        );
      case _TeacherSection.assessmentDetail:
        final assessmentId = _selectedDbAssessmentId;
        if (assessmentId == null) {
          return RegisteredCoursesView(
            courses: home?.courses ?? const [],
            onOpenCourse: _openDbCourse,
          );
        }
        return FutureBuilder<AssessmentDetailData>(
          future: _dashboardDatabase.loadAssessmentDetail(assessmentId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return AssessmentDetailView(
              data: snapshot.data!,
              onBack: () => _go(_TeacherSection.courseDetail),
            );
          },
        );
      case _TeacherSection.notifications:
        return FutureBuilder<List<TeacherNotification>>(
          future: _dashboardDatabase.loadNotifications(widget.teacher.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return NotificationsView(
              notifications: snapshot.data!,
              onBack: () => _go(_TeacherSection.dashboard),
              onMarkRead: _markNotificationRead,
            );
          },
        );
      case _TeacherSection.examAttendance:
        return FutureBuilder<ExamAttendanceDashboardData>(
          future: _dashboardDatabase.loadExamAttendanceDashboard(
            widget.teacher.id,
          ),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ExamAttendanceHomeView(
              data: snapshot.data!,
              onBack: () => _go(_TeacherSection.dashboard),
              onScan: _openExamScan,
              onViewAttendance: () => _go(_TeacherSection.attendanceSheets),
              onShareAttendance: () => _go(_TeacherSection.shareAttendance),
              onSharingStats: () => _go(_TeacherSection.attendanceSharing),
            );
          },
        );
      case _TeacherSection.examScan:
        return ExamQrScanView(
          onBack: () => _go(_TeacherSection.examAttendance),
          onQrDetected: _fetchHallStatsFromQr,
          errorMessage: _qrScanError,
        );
      case _TeacherSection.hallStats:
        final stats = _selectedHallStats;
        if (stats == null) {
          return _DatabaseMessage(
            message: _qrScanError ?? 'Hall data not found.',
          );
        }
        return HallStatsView(
          stats: stats,
          onBack: () => _go(_TeacherSection.examAttendance),
          onTakeAttendance: _openTakeAttendanceFromHall,
        );
      case _TeacherSection.takeExamAttendance:
        final sheetId = _selectedAttendanceSheetId;
        if (sheetId == null) {
          return const _DatabaseMessage(message: 'Hall data not found.');
        }
        return FutureBuilder<ExamAttendanceSheetDetail>(
          future: _dashboardDatabase.loadAttendanceSheetDetail(sheetId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return TakeExamAttendanceView(
              detail: snapshot.data!,
              onBack: () => _go(_attendanceEditorBackSection),
              onSave: _saveAttendanceStatuses,
            );
          },
        );
      case _TeacherSection.attendanceSheets:
        return FutureBuilder<List<ExamAttendanceSheetSummary>>(
          future: _dashboardDatabase.loadAttendanceSheets(widget.teacher.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return AttendanceSheetsView(
              sheets: snapshot.data!,
              onBack: () => _go(_TeacherSection.examAttendance),
              onOpenSheet: _openAttendanceSheet,
            );
          },
        );
      case _TeacherSection.shareAttendance:
        return FutureBuilder<List<ExamAttendanceSheetSummary>>(
          future: _dashboardDatabase.loadAttendanceSheets(widget.teacher.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return ShareAttendanceView(
              sheets: snapshot.data!,
              onBack: () => _go(_TeacherSection.examAttendance),
              onShare: _shareAttendanceSheet,
            );
          },
        );
      case _TeacherSection.attendanceSharing:
        return FutureBuilder<AttendanceSharingData>(
          future: _dashboardDatabase.loadAttendanceSharing(widget.teacher.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return AttendanceSharingView(
              data: snapshot.data!,
              onBack: () => _go(_TeacherSection.examAttendance),
            );
          },
        );
      case _TeacherSection.builder:
        return PaperGeneratorScreen(
          repository: widget.repository,
          teacher: widget.teacher,
          onAssessmentCreated: (assessment) {
            setState(() {
              _selectedAssessment = assessment;
              _section = _TeacherSection.qr;
            });
          },
        );
      case _TeacherSection.qr:
        return _QrShareScreen(
          assessment: _selectedAssessment,
          repository: widget.repository,
          onOpenLive: () => _go(_TeacherSection.live),
          onOpenResults: () => _go(_TeacherSection.results),
        );
      case _TeacherSection.attendance:
        return const QrAttendanceSection();
      case _TeacherSection.live:
        return _LiveMonitoringScreen(
          assessment: _selectedAssessment,
          repository: widget.repository,
        );
      case _TeacherSection.results:
        return _ResultsScreen(
          assessment: _selectedAssessment,
          repository: widget.repository,
        );
      case _TeacherSection.fyp:
        return FypTeacherSection(teacher: widget.teacher);
    }
  }

  void _go(_TeacherSection section) {
    setState(() => _section = section);
  }

  String? _resolveInitialCourseId(String dashboardCourseId) {
    final repoCourses = widget.repository.coursesForTeacher(widget.teacher);
    if (repoCourses.any((c) => c.id == dashboardCourseId)) {
      return dashboardCourseId;
    }
    // Dashboard DB and repository ids can differ; try to match by code.
    final normalized = dashboardCourseId.toLowerCase();
    for (final course in repoCourses) {
      if (course.courseCode.toLowerCase() == normalized ||
          course.id.toLowerCase() == normalized) {
        return course.id;
      }
    }
    return null;
  }

  Future<void> _confirmLogout() async {
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
      widget.repository.signOut();
    }
  }

  void _reloadTeacherHome() {
    _teacherHomeFuture = _dashboardDatabase.loadTeacherHome(
      teacherId: widget.teacher.id,
      teacherName: widget.teacher.name,
    );
  }

  void _openDbCourse(TeacherCourseSummary course) {
    setState(() {
      _selectedDbCourseId = course.id;
      _selectedDbAssessmentId = null;
      _section = _TeacherSection.courseDetail;
    });
  }

  void _openDbAssessment(CourseAssessmentSummary assessment) {
    setState(() {
      _selectedDbCourseId = assessment.courseId;
      _selectedDbAssessmentId = assessment.id;
      _section = _TeacherSection.assessmentDetail;
    });
  }

  void _openNotifications() {
    setState(() => _section = _TeacherSection.notifications);
  }

  void _openExamAttendance() {
    setState(() => _section = _TeacherSection.examAttendance);
  }

  void _openExamScan() {
    setState(() {
      _qrScanError = null;
      _section = _TeacherSection.examScan;
    });
  }

  Future<void> _markNotificationRead(TeacherNotification notification) async {
    await _dashboardDatabase.markNotificationRead(notification.id);
    setState(() {
      _reloadTeacherHome();
      _section = _TeacherSection.notifications;
    });
  }

  Future<void> _fetchHallStatsFromQr(String rawPayload) async {
    setState(() => _qrScanError = null);
    try {
      final stats = await _dashboardDatabase.fetchExamHallStatsFromQr(
        teacherId: widget.teacher.id,
        rawPayload: rawPayload,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _selectedHallStats = stats;
        _selectedAttendanceSheetId = stats.sheetId;
        _attendanceEditorBackSection = _TeacherSection.hallStats;
        _reloadTeacherHome();
        _section = _TeacherSection.hallStats;
      });
    } on FormatException {
      if (!mounted) {
        return;
      }
      setState(() {
        _qrScanError = 'Invalid QR code.';
        _section = _TeacherSection.examScan;
      });
    } catch (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _qrScanError = 'Hall data not found.';
        _section = _TeacherSection.examScan;
      });
    }
  }

  void _openTakeAttendanceFromHall() {
    setState(() {
      _attendanceEditorBackSection = _TeacherSection.hallStats;
      _section = _TeacherSection.takeExamAttendance;
    });
  }

  void _openAttendanceSheet(ExamAttendanceSheetSummary sheet) {
    setState(() {
      _selectedAttendanceSheetId = sheet.sheetId;
      _selectedHallStats = null;
      _attendanceEditorBackSection = _TeacherSection.attendanceSheets;
      _section = _TeacherSection.takeExamAttendance;
    });
  }

  Future<void> _saveAttendanceStatuses(
    Map<String, String> statusesByStudentId,
  ) async {
    final sheetId = _selectedAttendanceSheetId;
    if (sheetId == null) {
      return;
    }
    await _dashboardDatabase.saveAttendanceStatuses(
      sheetId: sheetId,
      statusesByStudentId: statusesByStudentId,
    );
    final stats = await _dashboardDatabase.loadExamHallStats(sheetId);
    if (!mounted) {
      return;
    }
    setState(() {
      _selectedHallStats = stats;
      _reloadTeacherHome();
      _section =
          _attendanceEditorBackSection == _TeacherSection.attendanceSheets
          ? _TeacherSection.attendanceSheets
          : _TeacherSection.hallStats;
    });
  }

  Future<void> _shareAttendanceSheet(ExamAttendanceSheetSummary sheet) async {
    final sharedWith = await _askSharedWith();
    if (sharedWith == null) {
      return;
    }
    final payload = await _dashboardDatabase.shareAttendanceSheet(
      teacherId: widget.teacher.id,
      sheetId: sheet.sheetId,
      sharedWith: sharedWith,
    );
    await Clipboard.setData(ClipboardData(text: payload));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Attendance stats copied.')));
    setState(() {
      _reloadTeacherHome();
      _section = _TeacherSection.attendanceSharing;
    });
  }

  Future<String?> _askSharedWith() async {
    final controller = TextEditingController(text: 'Admin');
    final value = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Share with'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Name'),
            autofocus: true,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, controller.text.trim()),
              child: const Text('Share'),
            ),
          ],
        );
      },
    );
    controller.dispose();
    return value;
  }
}

class _DatabaseMessage extends StatelessWidget {
  const _DatabaseMessage({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}

class _TeacherBottomNav extends StatelessWidget {
  const _TeacherBottomNav({
    required this.section,
    required this.onChanged,
    required this.onLogout,
  });

  final _TeacherSection section;
  final ValueChanged<_TeacherSection> onChanged;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    final items =
        <
          ({
            String label,
            IconData icon,
            _TeacherSection? section,
            VoidCallback? action,
          })
        >[
          (
            label: 'Home',
            icon: Icons.home_outlined,
            section: _TeacherSection.dashboard,
            action: null,
          ),
          (
            label: 'Courses',
            icon: Icons.class_outlined,
            section: _TeacherSection.courses,
            action: null,
          ),
          (
            label: 'Assessment Generator',
            icon: Icons.edit_note_outlined,
            section: _TeacherSection.builder,
            action: null,
          ),
          (
            label: 'Exam Attendance',
            icon: Icons.fact_check_outlined,
            section: _TeacherSection.examAttendance,
            action: null,
          ),
          (
            label: 'QR',
            icon: Icons.qr_code_2_outlined,
            section: _TeacherSection.qr,
            action: null,
          ),
          (
            label: 'Live',
            icon: Icons.monitor_heart_outlined,
            section: _TeacherSection.live,
            action: null,
          ),
          (
            label: 'Results',
            icon: Icons.grade_outlined,
            section: _TeacherSection.results,
            action: null,
          ),
          (
            label: 'Logout',
            icon: Icons.logout_rounded,
            section: null,
            action: onLogout,
          ),
        ];

    return Container(
      constraints: const BoxConstraints(
        minHeight: TeacherDashboardTheme.bottomNavHeight,
      ),
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFE6E9F4))),
      ),
      child: Row(
        children: items.map((item) {
          final selected =
              item.section != null && _isActive(section, item.section!);
          return Expanded(
            child: GestureDetector(
              onTap: () {
                final target = item.section;
                if (target == null) {
                  item.action?.call();
                  return;
                }
                onChanged(target);
              },
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                decoration: BoxDecoration(
                  color: selected
                      ? const Color(0xFFE8EDFF)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      item.icon,
                      color: selected
                          ? PortalColors.brandBlue
                          : PortalColors.navUnselected,
                      size: 22,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      item.label,
                      textAlign: TextAlign.center,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 9,
                        height: 1.05,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                        color: selected
                            ? PortalColors.brandBlue
                            : PortalColors.navUnselected,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  bool _isActive(_TeacherSection current, _TeacherSection target) {
    switch (target) {
      case _TeacherSection.dashboard:
        return current == _TeacherSection.dashboard ||
            current == _TeacherSection.notifications ||
            current == _TeacherSection.fyp;
      case _TeacherSection.courses:
        return current == _TeacherSection.courses ||
            current == _TeacherSection.courseDetail ||
            current == _TeacherSection.assessmentDetail;
      case _TeacherSection.builder:
        return current == _TeacherSection.builder ||
            current == _TeacherSection.newAssessment;
      case _TeacherSection.examAttendance:
        return current == _TeacherSection.examAttendance ||
            current == _TeacherSection.examScan ||
            current == _TeacherSection.hallStats ||
            current == _TeacherSection.takeExamAttendance ||
            current == _TeacherSection.attendanceSheets ||
            current == _TeacherSection.shareAttendance ||
            current == _TeacherSection.attendanceSharing ||
            current == _TeacherSection.attendance;
      case _TeacherSection.qr:
      case _TeacherSection.live:
      case _TeacherSection.results:
        return current == target;
      case _TeacherSection.courseDetail:
      case _TeacherSection.newAssessment:
      case _TeacherSection.assessmentDetail:
      case _TeacherSection.notifications:
      case _TeacherSection.examScan:
      case _TeacherSection.hallStats:
      case _TeacherSection.takeExamAttendance:
      case _TeacherSection.attendanceSheets:
      case _TeacherSection.shareAttendance:
      case _TeacherSection.attendanceSharing:
      case _TeacherSection.attendance:
      case _TeacherSection.fyp:
        return false;
    }
  }
}

class _QrShareScreen extends StatelessWidget {
  const _QrShareScreen({
    required this.assessment,
    required this.repository,
    required this.onOpenLive,
    required this.onOpenResults,
  });

  final Assessment? assessment;
  final AppRepository repository;
  final VoidCallback onOpenLive;
  final VoidCallback onOpenResults;

  @override
  Widget build(BuildContext context) {
    if (assessment == null) {
      return const _MissingSelection(
        message: 'Select or create an assessment.',
      );
    }
    final current = repository.assessmentById(assessment!.id) ?? assessment!;
    final course = repository.courseById(current.courseId);
    final isLive = current.status == AssessmentStatus.active;

    return _TeacherScroll(
      children: [
        _HeaderCard(
          title: 'QR code share',
          subtitle:
              'Students can enter this code in the student app. The visible QR is a frontend placeholder for now.',
          icon: Icons.qr_code_2_outlined,
        ),
        const SizedBox(height: 16),
        _Panel(
          title: current.title,
          action: Wrap(
            spacing: 8,
            children: [
              if (!isLive)
                FilledButton.icon(
                  onPressed: () => repository.publishAssessment(current.id),
                  icon: const Icon(Icons.play_circle_outline),
                  label: const Text('Make Live'),
                ),
              OutlinedButton.icon(
                onPressed: onOpenResults,
                icon: const Icon(Icons.grade_outlined),
                label: const Text('Results'),
              ),
              FilledButton.icon(
                onPressed: onOpenLive,
                icon: const Icon(Icons.monitor_heart_outlined),
                label: const Text('Live'),
              ),
            ],
          ),
          child: Column(
            children: [
              _QrVisual(code: current.qrCode),
              const SizedBox(height: 18),
              SelectableText(
                current.qrCode,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: PortalColors.brandBlue,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoPill('Status', isLive ? 'Live' : current.status.label),
                  _InfoPill('Course', course?.courseCode ?? current.courseId),
                  _InfoPill('Program', current.program),
                  _InfoPill('Section', current.section),
                  _InfoPill('Duration', '${current.durationMinutes} min'),
                  _InfoPill('Marks', '${current.totalMarks}'),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'One QR is shared in class. Each logged-in student sees the paper under their own name after scanning this code.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PortalColors.subtleText),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LiveMonitoringScreen extends StatelessWidget {
  const _LiveMonitoringScreen({
    required this.assessment,
    required this.repository,
  });

  final Assessment? assessment;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    if (assessment == null) {
      return const _MissingSelection(message: 'Select an assessment first.');
    }
    final submissions = repository.submissionsForAssessment(assessment!.id);
    final statuses = _monitorRows(submissions);
    final submitted = statuses
        .where((row) => row.status == AttemptStatus.submitted)
        .length;
    final flagged = statuses
        .where(
          (row) =>
              row.status == AttemptStatus.flagged ||
              row.status == AttemptStatus.autoLocked,
        )
        .length;

    return _TeacherScroll(
      children: [
        _HeaderCard(
          title: 'Live assessment monitoring',
          subtitle: assessment!.title,
          icon: Icons.monitor_heart_outlined,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Students',
              value: '${statuses.length}',
              icon: Icons.groups_outlined,
            ),
            _MetricCard(
              label: 'Submitted',
              value: '$submitted',
              icon: Icons.check_circle_outline,
            ),
            _MetricCard(
              label: 'Flagged',
              value: '$flagged',
              icon: Icons.warning_amber_outlined,
            ),
            _MetricCard(
              label: 'Warnings',
              value:
                  '${statuses.fold<int>(0, (sum, row) => sum + row.warningCount)}',
              icon: Icons.report_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Student status',
          child: Column(
            children: statuses.map((row) {
              return _ListTileCard(
                icon: _statusIcon(row.status),
                title: row.studentName,
                subtitle:
                    '${row.status.label} - ${row.progress}% complete - warnings ${row.warningCount}',
                trailing: row.flags.isEmpty
                    ? const _Badge(label: 'Clear', color: Color(0xFF0F766E))
                    : Wrap(
                        spacing: 6,
                        children: row.flags
                            .map(
                              (flag) => _Badge(
                                label: flag,
                                color: const Color(0xFFB45309),
                              ),
                            )
                            .toList(),
                      ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  List<_MonitorRow> _monitorRows(List<AssessmentSubmission> submissions) {
    return submissions.map((submission) {
      final student = repository.assessmentStudents
          .where((student) => student.id == submission.studentId)
          .firstOrNull;
      return _MonitorRow(
        studentName: student?.name ?? submission.studentId,
        status: submission.status,
        warningCount: submission.warningCount,
        flags: submission.flags,
        progress: submission.progress,
      );
    }).toList();
  }

  IconData _statusIcon(AttemptStatus status) {
    switch (status) {
      case AttemptStatus.notStarted:
        return Icons.hourglass_empty_rounded;
      case AttemptStatus.inProgress:
        return Icons.play_circle_outline_rounded;
      case AttemptStatus.submitted:
        return Icons.check_circle_outline_rounded;
      case AttemptStatus.flagged:
        return Icons.flag_outlined;
      case AttemptStatus.autoLocked:
        return Icons.lock_outline_rounded;
      case AttemptStatus.quit:
        return Icons.logout_rounded;
    }
  }
}

class _ResultsScreen extends StatelessWidget {
  const _ResultsScreen({required this.assessment, required this.repository});

  final Assessment? assessment;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    if (assessment == null) {
      return const _MissingSelection(message: 'Select an assessment first.');
    }
    final submissions = repository.submissionsForAssessment(assessment!.id);
    final graded = submissions.where((submission) => submission.marks != null);
    final average = graded.isEmpty
        ? 0
        : graded.fold<int>(0, (sum, submission) => sum + submission.marks!) /
              graded.length;

    return _TeacherScroll(
      children: [
        _HeaderCard(
          title: 'Results and grading',
          subtitle: assessment!.title,
          icon: Icons.grade_outlined,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MetricCard(
              label: 'Submissions',
              value: '${submissions.length}',
              icon: Icons.inbox_outlined,
            ),
            _MetricCard(
              label: 'Average',
              value: average.toStringAsFixed(1),
              icon: Icons.analytics_outlined,
            ),
            _MetricCard(
              label: 'Total marks',
              value: '${assessment!.totalMarks}',
              icon: Icons.score_outlined,
            ),
          ],
        ),
        const SizedBox(height: 16),
        _Panel(
          title: 'Submission list',
          child: Column(
            children: submissions.isEmpty
                ? [const _EmptyText('No submissions yet.')]
                : submissions.map((submission) {
                    final student = repository.assessmentStudents
                        .where((student) => student.id == submission.studentId)
                        .firstOrNull;
                    return _ListTileCard(
                      icon: Icons.assignment_turned_in_outlined,
                      title: student?.name ?? submission.studentId,
                      subtitle:
                          '${submission.status.label} - ${submission.progress}% complete - warnings ${submission.warningCount}',
                      trailing: _Badge(
                        label: submission.marks == null
                            ? 'Manual review'
                            : '${submission.marks}/${assessment!.totalMarks}',
                        color: PortalColors.brandBlue,
                      ),
                    );
                  }).toList(),
          ),
        ),
      ],
    );
  }
}

class _TeacherScroll extends StatelessWidget {
  const _TeacherScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 28),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1100),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ),
      ],
    );
  }
}

class _HeaderCard extends StatelessWidget {
  const _HeaderCard({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 520;
        final iconBox = Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: PortalColors.softBlue,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: PortalColors.brandBlue),
        );
        final textBlock = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
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

        return Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [iconBox, const SizedBox(height: 14), textBlock],
                )
              : Row(
                  children: [
                    iconBox,
                    const SizedBox(width: 16),
                    Expanded(child: textBlock),
                  ],
                ),
        );
      },
    );
  }
}

class _Panel extends StatelessWidget {
  const _Panel({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxWidth < 520;
                final titleText = Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                );
                if (action == null) {
                  return titleText;
                }
                if (compact) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [titleText, const SizedBox(height: 10), action!],
                  );
                }
                return Row(
                  children: [
                    Expanded(child: titleText),
                    action!,
                  ],
                );
              },
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.label,
    required this.value,
    required this.icon,
  });

  final String label;
  final String value;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(18),
          child: Row(
            children: [
              Icon(icon, color: PortalColors.brandBlue),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: const TextStyle(color: PortalColors.subtleText),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      value,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
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

class _ListTileCard extends StatelessWidget {
  const _ListTileCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 560;
        final titleBlock = Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: PortalColors.brandBlue),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PortalColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: const TextStyle(color: PortalColors.subtleText),
                  ),
                ],
              ),
            ),
          ],
        );

        final content = Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: compact
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    titleBlock,
                    const SizedBox(height: 12),
                    Align(alignment: Alignment.centerLeft, child: trailing),
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: titleBlock),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: trailing,
                      ),
                    ),
                  ],
                ),
        );
        return content;
      },
    );
  }
}

class _InfoPill extends StatelessWidget {
  const _InfoPill(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text('$label: $value'),
      backgroundColor: const Color(0xFFF8FAFC),
      side: const BorderSide(color: PortalColors.cardBorder),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(color: color, fontWeight: FontWeight.w800),
      ),
    );
  }
}

class _EmptyText extends StatelessWidget {
  const _EmptyText(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Text(text, style: const TextStyle(color: PortalColors.subtleText)),
    );
  }
}

class _MissingSelection extends StatelessWidget {
  const _MissingSelection({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(child: _EmptyText(message));
  }
}

class _QrVisual extends StatelessWidget {
  const _QrVisual({required this.code});

  final String code;

  @override
  Widget build(BuildContext context) {
    final hash = code.codeUnits.fold<int>(0, (sum, unit) => sum + unit);
    return Container(
      width: 220,
      height: 220,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: GridView.builder(
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 11,
          mainAxisSpacing: 3,
          crossAxisSpacing: 3,
        ),
        itemCount: 121,
        itemBuilder: (context, index) {
          final finder =
              (index < 25 && index % 11 < 5) ||
              (index < 55 && index % 11 > 5 && index < 11) ||
              (index > 76 && index % 11 < 5);
          final filled = finder || ((index * 31 + hash) % 5 < 2);
          return DecoratedBox(
            decoration: BoxDecoration(
              color: filled
                  ? PortalColors.textPrimary
                  : const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(2),
            ),
          );
        },
      ),
    );
  }
}

class _MonitorRow {
  const _MonitorRow({
    required this.studentName,
    required this.status,
    required this.warningCount,
    required this.flags,
    required this.progress,
  });

  final String studentName;
  final AttemptStatus status;
  final int warningCount;
  final List<String> flags;
  final int progress;
}

extension _FirstOrNull<T> on Iterable<T> {
  T? get firstOrNull {
    for (final item in this) {
      return item;
    }
    return null;
  }
}

/// Modules grid panel injected at the bottom of the teacher dashboard. The
/// admin Feature Controls page decides which modules appear here.
class _TeacherModulesPanel extends StatelessWidget {
  const _TeacherModulesPanel({required this.repository, required this.teacher});

  final AppRepository repository;
  final AssessmentTeacher teacher;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: FeatureVisibilityService.instance,
      builder: (context, _) {
        final visible = FeatureVisibilityService.instance
            .visibleFor(AppRole.faculty)
            // FYP has its own bottom-nav slot for teachers.
            .where((meta) => meta.key != FeatureKey.fyp)
            .toList();
        if (visible.isEmpty) {
          return const SizedBox.shrink();
        }
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PortalColors.cardBorder),
          ),
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
                        teacher: teacher,
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
