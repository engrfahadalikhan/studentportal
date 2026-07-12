import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../attendance/qr_attendance_section.dart';
import '../features/feature_catalog.dart';
import '../features/feature_visibility_service.dart';
import '../fyp/fyp_teacher_section.dart';
import '../models/app_role.dart';
import '../modules/module_router.dart';
import '../modules/modules_common.dart';
import '../features/admin_data_sync_page.dart';
import '../features/answer_sheet_tracker_page.dart';
import '../features/change_password_page.dart';
import '../features/end_summary_page.dart';
import '../features/local_exam_host_page.dart';
import '../features/quiz_results_export.dart';
import '../features/slot_collection_page.dart';
import '../services/app_repository.dart';
import '../services/assessment_access_service.dart';
import '../services/paper_tracker_access_service.dart';
import '../services/slot_collection_access_service.dart';
import '../services/teacher_dashboard_database.dart';
import '../ui/student_portal_shell.dart';
import 'assessment_models.dart';
import 'assessment_qr_codec.dart';
import 'paper_generator_screen.dart';
import 'submission_qr_codec.dart';
import 'live_hall_attendance_view.dart';
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
  liveHallAttendance,
  takeExamAttendance,
  hallShare,
  acceptAttendance,
  attendanceSheets,
  attendanceHistory,
  exportRecord,
  importRecord,
  shareAttendance,
  attendanceSharing,
  builder,
  qr,
  attendance,
  live,
  results,
  scanSubmission,
  marksLists,
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
  final List<_TeacherSection> _sectionHistory = [];
  AssessmentCourse? _selectedCourse;
  Assessment? _selectedAssessment;
  late final TeacherDashboardDatabase _dashboardDatabase;
  Future<TeacherDashboardHomeData>? _teacherHomeFuture;
  String? _selectedDbCourseId;
  String? _selectedDbAssessmentId;
  String? _selectedAttendanceSheetId;
  ExamClassGroup? _selectedClass;
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
      animation: Listenable.merge([
        widget.repository,
        FeatureVisibilityService.instance,
        AssessmentAccessService.instance,
        PaperTrackerAccessService.instance,
        SlotCollectionAccessService.instance,
      ]),
      builder: (context, _) {
        final courses = widget.repository.coursesForTeacher(widget.teacher);
        final assessments = widget.repository.assessmentsForTeacher(
          widget.teacher,
        );
        _selectedCourse ??= courses.isEmpty ? null : courses.first;
        // Do NOT auto-select an assessment — the teacher must choose one
        // explicitly from the Assessments hub. This prevents the QR tab from
        // showing a paper that the teacher didn't intend to share.

        return FutureBuilder<TeacherDashboardHomeData>(
          future: _teacherHomeFuture,
          builder: (context, snapshot) {
            final home = snapshot.data;

            return PopScope(
              canPop:
                  _section == _TeacherSection.dashboard &&
                  _sectionHistory.isEmpty,
              onPopInvokedWithResult: (didPop, result) {
                if (didPop) return;
                _handleSystemBack();
              },
              child: Scaffold(
                backgroundColor: PortalColors.pageBackground,
                bottomNavigationBar: _TeacherBottomNav(
                  section: _section,
                  onChanged: _go,
                  onLogout: _confirmLogout,
                  canCreateAssessments: AssessmentAccessService.instance
                      .isAllowed(widget.teacher.id),
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
          onChangePassword: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => ChangePasswordPage(repository: widget.repository),
            ),
          ),
          onMarksLists: () => _go(_TeacherSection.marksLists),
          onAnswerSheets:
              PaperTrackerAccessService.instance.isAllowed(widget.teacher.id)
              ? () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AnswerSheetTrackerPage(),
                  ),
                )
              : null,
          // Per-Slot Collection + Data Share are open to all teachers (they are
          // the invigilators who collect and hand over the data).
          onSlotCollection: () => Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const SlotCollectionPage()),
          ),
          onDataShare: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => AdminDataSyncPage(repository: widget.repository),
            ),
          ),
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
          future: _loadMergedCourseDetail(courseId),
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
        if (!AssessmentAccessService.instance.isAllowed(widget.teacher.id)) {
          return const _DatabaseMessage(
            message:
                'Assessment creation is not enabled for your account.\n'
                'Ask the admin to allow it (Admin → Assessment Access).',
          );
        }
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
            _reloadTeacherHome();
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
              onHistory: () => _go(_TeacherSection.attendanceHistory),
              onExport: () => _go(_TeacherSection.exportRecord),
              onImport: () => _go(_TeacherSection.importRecord),
              onSummary: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => EndSummaryPage(teacherId: widget.teacher.id),
                ),
              ),
            );
          },
        );
      case _TeacherSection.examScan:
        return FutureBuilder<List<ExamAttendanceSheetSummary>>(
          future: _dashboardDatabase.loadAttendanceSheets(widget.teacher.id),
          builder: (context, snapshot) {
            return ExamQrScanView(
              onBack: () => _go(_TeacherSection.examAttendance),
              onQrDetected: _fetchHallStatsFromQr,
              errorMessage: _qrScanError,
              scannedHalls: snapshot.data ?? const [],
              onResumeHall: (sheet) {
                setState(() {
                  _selectedAttendanceSheetId = sheet.sheetId;
                  _selectedClass = null;
                });
                _go(_TeacherSection.hallStats);
              },
            );
          },
        );
      case _TeacherSection.hallStats:
        final hallSheetId = _selectedAttendanceSheetId;
        if (hallSheetId == null) {
          return _DatabaseMessage(
            message: _qrScanError ?? 'Hall data not found.',
          );
        }
        return FutureBuilder<ExamAttendanceSheetDetail>(
          future: _dashboardDatabase.loadAttendanceSheetDetail(hallSheetId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            final detail = snapshot.data!;
            return HallStatsView(
              stats: detail.stats,
              students: detail.students,
              onBack: () => _go(_TeacherSection.examAttendance),
              onTakeAttendance: _openTakeAttendanceFromHall,
              onLiveScan: _openLiveHallAttendance,
              onSelectClass: _openClassAttendance,
              onShare: () => _go(_TeacherSection.hallShare),
              onAccept: () => _go(_TeacherSection.acceptAttendance),
            );
          },
        );
      case _TeacherSection.hallShare:
        final shareSheetId = _selectedAttendanceSheetId;
        if (shareSheetId == null) {
          return const _DatabaseMessage(message: 'Hall data not found.');
        }
        return FutureBuilder<ExamHallStats>(
          future: _dashboardDatabase.loadExamHallStats(shareSheetId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return HallShareView(
              stats: snapshot.data!,
              onBack: () => _go(_TeacherSection.hallStats),
              onLoad: (classGroup) => _dashboardDatabase.loadAttendanceShare(
                sheetId: shareSheetId,
                classGroup: classGroup,
                sharedBy: widget.teacher.name,
              ),
              onRecordShared: (classGroup) async {
                await _dashboardDatabase.recordAttendanceShare(
                  teacherId: widget.teacher.id,
                  sheetId: shareSheetId,
                  sharedWith: 'Admin',
                  classGroup: classGroup,
                  sharedBy: widget.teacher.name,
                );
                _reloadTeacherHome();
              },
            );
          },
        );
      case _TeacherSection.acceptAttendance:
        return AcceptAttendanceView(
          onBack: () => _go(_TeacherSection.examAttendance),
          onAccept: (rawPayload) async {
            final accepted = await _dashboardDatabase.acceptAttendanceQr(
              teacherId: widget.teacher.id,
              rawPayload: rawPayload,
            );
            _reloadTeacherHome();
            return 'Accepted: ${accepted.courseName} — ${accepted.hallName}. '
                'See it under Shared/Accepted Stats.';
          },
        );
      case _TeacherSection.liveHallAttendance:
        final liveSheetId = _selectedAttendanceSheetId;
        if (liveSheetId == null) {
          return const _DatabaseMessage(message: 'Hall data not found.');
        }
        final liveClass = _selectedClass;
        return LiveHallAttendanceView(
          // Key by sheet + class so switching class rebuilds camera + grid.
          key: ValueKey('$liveSheetId|${liveClass?.program ?? 'all'}'),
          sheetId: liveSheetId,
          selectedClass: liveClass,
          onBack: () => _go(_TeacherSection.hallStats),
          onFinished: (_) {
            setState(() {
              _reloadTeacherHome();
              _section = _TeacherSection.hallStats;
            });
          },
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
      case _TeacherSection.attendanceHistory:
        return FutureBuilder<List<ExamAttendanceSheetSummary>>(
          future: _dashboardDatabase.loadAttendanceSheets(widget.teacher.id),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return _DatabaseMessage(message: snapshot.error.toString());
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return AttendanceHistoryView(
              sheets: snapshot.data!,
              onBack: () => _go(_TeacherSection.examAttendance),
              onOpenSheet: _openAttendanceHistorySheet,
              onDelete: (sheet) async {
                await _dashboardDatabase.deleteAttendanceSheet(sheet.sheetId);
                _reloadTeacherHome();
                setState(() {}); // refresh the history FutureBuilder
              },
            );
          },
        );
      case _TeacherSection.exportRecord:
        return ExportRecordView(
          onBack: () => _go(_TeacherSection.examAttendance),
          buildJson: () => _dashboardDatabase.exportAttendanceJson(
            teacherId: widget.teacher.id,
            exportedBy: widget.teacher.name,
          ),
        );
      case _TeacherSection.importRecord:
        return ImportRecordView(
          onBack: () => _go(_TeacherSection.examAttendance),
          onImport: (jsonText) => _dashboardDatabase.importAttendanceExport(
            teacherId: widget.teacher.id,
            jsonText: jsonText,
          ),
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
              onLoadShare: (sheetId) => _dashboardDatabase.loadAttendanceShare(
                sheetId: sheetId,
                classGroup: '',
                sharedBy: widget.teacher.name,
              ),
              onAccept: () => _go(_TeacherSection.acceptAttendance),
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
        if (!AssessmentAccessService.instance.isAllowed(widget.teacher.id)) {
          return const _DatabaseMessage(
            message:
                'Assessment creation is not enabled for your account.\n'
                'Ask the admin to allow it (Admin → Assessment Access).',
          );
        }
        return _TeacherAssessmentsHub(
          repository: widget.repository,
          teacher: widget.teacher,
          onCreate: _openGenerator,
          onOpenAssessment: (assessment) {
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
          onScanSubmission: () => _go(_TeacherSection.scanSubmission),
          onDelete: () => _confirmDeleteAssessment(_selectedAssessment),
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
      case _TeacherSection.scanSubmission:
        return _ScanSubmissionScreen(
          repository: widget.repository,
          assessment: _selectedAssessment,
          onDone: () => _go(_TeacherSection.marksLists),
        );
      case _TeacherSection.marksLists:
        return _MarksListsScreen(repository: widget.repository);
      case _TeacherSection.fyp:
        return FypTeacherSection(teacher: widget.teacher);
    }
  }

  Future<void> _confirmDeleteAssessment(Assessment? a) async {
    if (a == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete this assessment?'),
        content: Text(
          '"${a.title}" and its scanned submissions will be permanently '
          'removed. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    widget.repository.deleteAssessment(a.id);
    _reloadTeacherHome();
    if (mounted) {
      setState(() {
        _selectedAssessment = null;
        _section = _TeacherSection.courses;
      });
    }
  }

  void _go(_TeacherSection section) {
    if (section == _section) return;
    setState(() {
      _sectionHistory.add(_section);
      _section = section;
    });
  }

  /// Handles the Android system back / side-swipe: step back through the
  /// in-app section history instead of closing the whole app. Only when we are
  /// already on the dashboard with no history does the app actually exit.
  void _handleSystemBack() {
    setState(() {
      if (_sectionHistory.isNotEmpty) {
        _section = _sectionHistory.removeLast();
      } else if (_section != _TeacherSection.dashboard) {
        _section = _TeacherSection.dashboard;
      }
    });
  }

  /// Opens the paper generator (as a full route) preset to [type]. On save the
  /// new assessment is selected and the QR share screen is shown.
  Future<void> _openGenerator(AssessmentType type) async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (routeContext) => Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(title: Text('New ${type.label}')),
          body: PaperGeneratorScreen(
            repository: widget.repository,
            teacher: widget.teacher,
            assessmentType: type,
            onAssessmentCreated: (assessment) {
              Navigator.of(routeContext).pop();
              setState(() {
                _selectedAssessment = assessment;
                _section = _TeacherSection.qr;
              });
            },
          ),
        ),
      ),
    );
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
    _teacherHomeFuture = _loadMergedHome();
  }

  /// The course list / counts come from the sqflite dashboard DB, but the
  /// quizzes a teacher BUILDS live in AppRepository. Merge the AppRepository
  /// assessment counts into each course so created papers actually show up.
  Future<TeacherDashboardHomeData> _loadMergedHome() async {
    final base = await _dashboardDatabase.loadTeacherHome(
      teacherId: widget.teacher.id,
      teacherName: widget.teacher.name,
    );
    final mergedCourses = base.courses.map((c) {
      final repoCount = _repoAssessmentsForDashboardCourse(c.id).length;
      if (repoCount == 0) return c;
      return TeacherCourseSummary(
        id: c.id,
        teacherId: c.teacherId,
        courseName: c.courseName,
        courseCode: c.courseCode,
        totalStudents: c.totalStudents,
        totalAssessments: c.totalAssessments + repoCount,
        program: c.program,
        semester: c.semester,
        section: c.section,
      );
    }).toList();
    return TeacherDashboardHomeData(
      teacherId: base.teacherId,
      teacherName: base.teacherName,
      courses: mergedCourses,
      unreadNotifications: base.unreadNotifications,
      attendanceSheets: base.attendanceSheets,
      sharedAttendanceSheets: base.sharedAttendanceSheets,
      acceptedAttendanceSheets: base.acceptedAttendanceSheets,
    );
  }

  List<Assessment> _repoAssessmentsForDashboardCourse(String dashboardCourseId) {
    final repoCourseId = _resolveInitialCourseId(dashboardCourseId);
    if (repoCourseId == null) return const [];
    return widget.repository.assessmentsForCourse(repoCourseId);
  }

  /// AppRepository assessments for a dashboard course, as the dashboard's own
  /// summary type, so they render alongside any DB ones in the course detail.
  List<CourseAssessmentSummary> _repoAssessmentSummaries(
    String dashboardCourseId,
    Set<String> existingIds,
  ) {
    final out = <CourseAssessmentSummary>[];
    for (final a in _repoAssessmentsForDashboardCourse(dashboardCourseId)) {
      if (existingIds.contains(a.id)) continue;
      final submitted = widget.repository.submissionsForAssessment(a.id).length;
      out.add(
        CourseAssessmentSummary(
          id: a.id,
          courseId: dashboardCourseId,
          title: a.title,
          type: switch (a.type) {
            AssessmentType.assignment => TeacherAssessmentKind.assignment,
            AssessmentType.quiz => TeacherAssessmentKind.quiz,
            AssessmentType.examPaper => TeacherAssessmentKind.others,
          },
          totalMarks: a.totalMarks,
          dueDate: a.endTime,
          instructions: a.instructions,
          submittedCount: submitted,
          notSubmittedCount: a.expectedStudents > submitted
              ? a.expectedStudents - submitted
              : 0,
        ),
      );
    }
    return out;
  }

  Future<TeacherCourseDetailData> _loadMergedCourseDetail(
    String dashboardCourseId,
  ) async {
    final base = await _dashboardDatabase.loadCourseDetail(dashboardCourseId);
    final extra = _repoAssessmentSummaries(
      dashboardCourseId,
      base.assessments.map((a) => a.id).toSet(),
    );
    if (extra.isEmpty) return base;
    return TeacherCourseDetailData(
      course: base.course,
      assessments: [...extra, ...base.assessments],
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
    // A teacher-built paper lives in AppRepository — open its QR/scan screen
    // (the dashboard-DB assessment-detail screen would be empty for it).
    final repoAssessment = widget.repository.assessmentById(assessment.id);
    if (repoAssessment != null) {
      setState(() {
        _selectedAssessment = repoAssessment;
        _section = _TeacherSection.qr;
      });
      return;
    }
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
        _selectedAttendanceSheetId = stats.sheetId;
        _selectedClass = null;
        _attendanceEditorBackSection = _TeacherSection.hallStats;
        _reloadTeacherHome();
        // Land on the hall stats screen: it lists every class in the hall so
        // the teacher can take attendance one class at a time.
        _section = _TeacherSection.hallStats;
      });
    } on FormatException catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _qrScanError = error.message.isEmpty
            ? 'Invalid QR code.'
            : error.message;
        _section = _TeacherSection.examScan;
      });
    } on StateError catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _qrScanError = error.message;
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

  void _openLiveHallAttendance() {
    setState(() {
      _selectedClass = null;
      _attendanceEditorBackSection = _TeacherSection.hallStats;
      _section = _TeacherSection.liveHallAttendance;
    });
  }

  void _openClassAttendance(ExamClassGroup group) {
    setState(() {
      _selectedClass = group;
      _attendanceEditorBackSection = _TeacherSection.hallStats;
      _section = _TeacherSection.liveHallAttendance;
    });
  }

  void _openAttendanceSheet(ExamAttendanceSheetSummary sheet) {
    setState(() {
      _selectedAttendanceSheetId = sheet.sheetId;
      _selectedClass = null;
      _attendanceEditorBackSection = _TeacherSection.attendanceSheets;
      _section = _TeacherSection.takeExamAttendance;
    });
  }

  void _openAttendanceHistorySheet(ExamAttendanceSheetSummary sheet) {
    setState(() {
      _selectedAttendanceSheetId = sheet.sheetId;
      _selectedClass = null;
      _attendanceEditorBackSection = _TeacherSection.attendanceHistory;
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
    if (!mounted) {
      return;
    }
    setState(() {
      _reloadTeacherHome();
      _section =
          (_attendanceEditorBackSection == _TeacherSection.attendanceSheets ||
              _attendanceEditorBackSection == _TeacherSection.attendanceHistory)
          ? _attendanceEditorBackSection
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
    required this.canCreateAssessments,
  });

  final _TeacherSection section;
  final ValueChanged<_TeacherSection> onChanged;
  final VoidCallback onLogout;

  /// Per-teacher permission (set by the admin) to build assessments.
  final bool canCreateAssessments;

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
            label: 'Assess',
            icon: Icons.assignment_outlined,
            section: _TeacherSection.builder,
            action: null,
          ),
          (
            label: 'Exam',
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

    // Assess / Live / Results tabs only appear when the admin enabled them.
    final service = FeatureVisibilityService.instance;
    final visibleItems = items.where((item) {
      switch (item.section) {
        case _TeacherSection.builder:
          // Per-teacher: only teachers the admin explicitly allowed can build
          // assessments (set in admin → Assessment Access).
          return canCreateAssessments;
        case _TeacherSection.live:
          return service.isVisible(AppRole.faculty, FeatureKey.teacherLive);
        case _TeacherSection.results:
          return service.isVisible(AppRole.faculty, FeatureKey.teacherResults);
        default:
          return true;
      }
    }).toList();

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
        children: visibleItems.map((item) {
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
                  color: selected ? PortalColors.softBlue : Colors.transparent,
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
                    FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        item.label,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontSize: 10,
                          height: 1.05,
                          fontWeight: selected
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: selected
                              ? PortalColors.brandBlue
                              : PortalColors.navUnselected,
                        ),
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
            current == _TeacherSection.liveHallAttendance ||
            current == _TeacherSection.takeExamAttendance ||
            current == _TeacherSection.hallShare ||
            current == _TeacherSection.acceptAttendance ||
            current == _TeacherSection.attendanceSheets ||
            current == _TeacherSection.attendanceHistory ||
            current == _TeacherSection.exportRecord ||
            current == _TeacherSection.importRecord ||
            current == _TeacherSection.shareAttendance ||
            current == _TeacherSection.attendanceSharing ||
            current == _TeacherSection.attendance;
      case _TeacherSection.qr:
      case _TeacherSection.live:
      case _TeacherSection.results:
      case _TeacherSection.scanSubmission:
        return current == target;
      case _TeacherSection.courseDetail:
      case _TeacherSection.newAssessment:
      case _TeacherSection.assessmentDetail:
      case _TeacherSection.notifications:
      case _TeacherSection.examScan:
      case _TeacherSection.hallStats:
      case _TeacherSection.liveHallAttendance:
      case _TeacherSection.takeExamAttendance:
      case _TeacherSection.hallShare:
      case _TeacherSection.acceptAttendance:
      case _TeacherSection.attendanceSheets:
      case _TeacherSection.attendanceHistory:
      case _TeacherSection.exportRecord:
      case _TeacherSection.importRecord:
      case _TeacherSection.shareAttendance:
      case _TeacherSection.attendanceSharing:
      case _TeacherSection.attendance:
      case _TeacherSection.marksLists:
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
    required this.onScanSubmission,
    required this.onDelete,
  });

  final Assessment? assessment;
  final AppRepository repository;
  final VoidCallback onOpenLive;
  final VoidCallback onOpenResults;
  final VoidCallback onScanSubmission;
  final VoidCallback onDelete;

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
              'Show the QR in class — students scan it with Assess → Scan and the whole paper loads on their phone, fully offline. They can also type the short code shown below by hand.',
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
              if (FeatureVisibilityService.instance.isVisible(
                AppRole.faculty,
                FeatureKey.teacherResults,
              ))
                OutlinedButton.icon(
                  onPressed: onOpenResults,
                  icon: const Icon(Icons.grade_outlined),
                  label: const Text('Results'),
                ),
              if (FeatureVisibilityService.instance.isVisible(
                AppRole.faculty,
                FeatureKey.teacherLive,
              ))
                FilledButton.icon(
                  onPressed: onOpenLive,
                  icon: const Icon(Icons.monitor_heart_outlined),
                  label: const Text('Live'),
                ),
              FilledButton.icon(
                onPressed: onScanSubmission,
                style: FilledButton.styleFrom(
                  backgroundColor: const Color(0xFF047857),
                ),
                icon: const Icon(Icons.qr_code_scanner_rounded),
                label: const Text('Scan submissions'),
              ),
              OutlinedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => LocalExamHostPage(
                      assessment: current,
                      repository: repository,
                    ),
                  ),
                ),
                icon: const Icon(Icons.wifi_tethering_rounded),
                label: const Text('Host on WiFi'),
              ),
              OutlinedButton.icon(
                onPressed: onDelete,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFB91C1C),
                ),
                icon: const Icon(Icons.delete_outline_rounded),
                label: const Text('Delete'),
              ),
            ],
          ),
          child: _ShareableQrBlock(
            assessment: current,
            course: course,
            isLive: isLive,
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
    // AnimatedBuilder so the list refreshes the moment a teacher saves a grade.
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        final current =
            repository.assessmentById(assessment!.id) ?? assessment!;
        final submissions = repository.submissionsForAssessment(current.id);
        final graded = submissions.where(
          (submission) => submission.marks != null,
        );
        final needsGrading = submissions
            .where((submission) => submission.marks == null)
            .length;
        final average = graded.isEmpty
            ? 0
            : graded.fold<int>(0, (sum, s) => sum + s.marks!) / graded.length;
        final isAssignment = current.type == AssessmentType.assignment;

        return _TeacherScroll(
          children: [
            _HeaderCard(
              title: 'Results and grading',
              subtitle: '${current.title} • ${current.type.label}',
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
                  label: 'Needs grading',
                  value: '$needsGrading',
                  icon: Icons.rate_review_outlined,
                ),
                _MetricCard(
                  label: 'Average',
                  value: average.toStringAsFixed(1),
                  icon: Icons.analytics_outlined,
                ),
                _MetricCard(
                  label: 'Total marks',
                  value: '${current.totalMarks}',
                  icon: Icons.score_outlined,
                ),
              ],
            ),
            const SizedBox(height: 16),
            _Panel(
              title: isAssignment ? 'Submissions to grade' : 'Submission list',
              child: submissions.isEmpty
                  ? const _EmptyText('No submissions yet.')
                  : Column(
                      children: [
                        for (final submission in submissions)
                          _SubmissionGradeTile(
                            assessment: current,
                            submission: submission,
                            repository: repository,
                          ),
                      ],
                    ),
            ),
          ],
        );
      },
    );
  }
}

/// Complete marks lists grouped CLASS-wise (BSCS 2A …) then ASSESSMENT-wise
/// (Quiz 1, Quiz 2 …). Built from every scanned submission, which now carries
/// the student's name + program/semester/section.
class _MarksListsScreen extends StatelessWidget {
  const _MarksListsScreen({required this.repository});

  final AppRepository repository;

  String _classLabel(AssessmentSubmission s, Assessment? a) {
    String pick(String sub, String asm) =>
        sub.trim().isNotEmpty ? sub.trim() : asm.trim();
    final program = pick(s.studentProgram, a?.program ?? '');
    final semester = pick(s.studentSemester, a?.semester ?? '');
    final section = pick(s.studentSection, a?.section ?? '');
    final label = '$program $semester$section'.trim();
    return label.isEmpty ? 'Unspecified class' : label;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: repository,
      builder: (context, _) {
        // class -> assessmentId -> submissions
        final byClass = <String, Map<String, List<AssessmentSubmission>>>{};
        final asmTitle = <String, String>{};
        final asmObj = <String, Assessment?>{};
        for (final s in repository.submissions) {
          final a = repository.assessmentById(s.assessmentId);
          asmObj[s.assessmentId] = a;
          asmTitle[s.assessmentId] = (a != null && a.title.isNotEmpty)
              ? a.title
              : (s.assessmentTitle.isNotEmpty
                    ? s.assessmentTitle
                    : s.assessmentId);
          byClass
              .putIfAbsent(_classLabel(s, a), () => {})
              .putIfAbsent(s.assessmentId, () => [])
              .add(s);
        }
        final classes = byClass.keys.toList()..sort();

        return _TeacherScroll(
          children: [
            _HeaderCard(
              title: 'Marks Lists',
              subtitle: 'Class-wise and quiz-wise — built from scanned '
                  'submissions.',
              icon: Icons.grading_outlined,
            ),
            const SizedBox(height: 16),
            if (classes.isEmpty)
              _Panel(
                title: 'No marks yet',
                child: const _EmptyText(
                  'Scan students\' submission QRs (Scan submission) to build the '
                  'class-wise lists here.',
                ),
              )
            else
              for (final cls in classes) ...[
                _Panel(
                  title: cls,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final asmId in byClass[cls]!.keys.toList()..sort())
                        _assessmentBlock(
                          asmTitle[asmId] ?? asmId,
                          asmObj[asmId],
                          byClass[cls]![asmId]!,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
          ],
        );
      },
    );
  }

  Widget _assessmentBlock(
    String title,
    Assessment? assessment,
    List<AssessmentSubmission> subs,
  ) {
    final rows = [...subs]
      ..sort((a, b) => a.studentId.toLowerCase().compareTo(
        b.studentId.toLowerCase(),
      ));
    final graded = rows.where((r) => r.marks != null).length;
    final total = assessment?.totalMarks ?? 0;
    final expected = assessment?.expectedStudents ?? 0;
    final absent = expected > rows.length ? expected - rows.length : 0;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            'Submitted ${rows.length}'
            '${expected > 0 ? ' / $expected  •  Absent $absent' : ''}'
            '  •  Graded $graded'
            '${total > 0 ? '  •  Out of $total' : ''}',
            style: const TextStyle(fontSize: 11.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < rows.length; i++) _studentRow(i + 1, rows[i], total),
        ],
      ),
    );
  }

  Widget _studentRow(int index, AssessmentSubmission s, int totalMarks) {
    final name = s.studentName.isEmpty ? s.studentId : s.studentName;
    final marksText = s.marks == null
        ? 'Not graded'
        : (totalMarks > 0 ? '${s.marks} / $totalMarks' : '${s.marks}');
    final auto = s.status == AttemptStatus.autoLocked;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 22,
            child: Text(
              '$index',
              style: const TextStyle(fontSize: 11, color: Color(0xFF94A3B8)),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${s.studentId}  •  $name',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                  ),
                ),
                if (auto || s.warningCount > 0)
                  Text(
                    auto
                        ? 'Auto-submitted • ${s.warningCount} warning(s)'
                        : '${s.warningCount} warning(s)',
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: Color(0xFFB45309),
                    ),
                  ),
              ],
            ),
          ),
          Text(
            marksText,
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: s.marks == null
                  ? const Color(0xFF94A3B8)
                  : const Color(0xFF0F766E),
            ),
          ),
        ],
      ),
    );
  }
}

/// One submission row in the Results screen. Tap to open the grading sheet
/// (review answers, then enter marks). Works for both auto-graded quizzes
/// (teacher can override) and manually graded assignments.
class _SubmissionGradeTile extends StatelessWidget {
  const _SubmissionGradeTile({
    required this.assessment,
    required this.submission,
    required this.repository,
  });

  final Assessment assessment;
  final AssessmentSubmission submission;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final student = repository.assessmentStudents
        .where((s) => s.id == submission.studentId)
        .firstOrNull;
    final graded = submission.marks != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => _openGradeSheet(context),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.assignment_turned_in_outlined,
                  color: PortalColors.brandBlue,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        student?.name ?? submission.studentId,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${submission.status.label} • ${submission.progress}% • warnings ${submission.warningCount}',
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Badge(
                  label: graded
                      ? '${submission.marks}/${assessment.totalMarks}'
                      : 'Grade',
                  color: graded
                      ? const Color(0xFF0F766E)
                      : const Color(0xFFB45309),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openGradeSheet(BuildContext context) {
    // The objective score is computed HERE, at the teacher's end, using the
    // teacher's authoritative copy (the only one with correct answers).
    final suggested = repository.objectiveAutoMarks(
      assessment,
      submission.answers,
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => _GradeSheet(
        assessment: assessment,
        submission: submission,
        suggestedMarks: suggested,
        studentName:
            repository.assessmentStudents
                .where((s) => s.id == submission.studentId)
                .firstOrNull
                ?.name ??
            submission.studentId,
        onSave: (marks) {
          repository.gradeSubmission(
            assessmentId: assessment.id,
            studentId: submission.studentId,
            marks: marks,
          );
          Navigator.of(sheetContext).pop();
        },
      ),
    );
  }
}

/// Bottom sheet to review a student's answers and enter marks. Shows
/// per-question answers (with correct/wrong for objective questions) for
/// quizzes, or the typed text + attached file for assignments.
class _GradeSheet extends StatefulWidget {
  const _GradeSheet({
    required this.assessment,
    required this.submission,
    required this.suggestedMarks,
    required this.studentName,
    required this.onSave,
  });

  final Assessment assessment;
  final AssessmentSubmission submission;

  /// Objective score computed at the teacher's end from the answer key, or
  /// null if the paper has no auto-gradable questions (assignment).
  final int? suggestedMarks;
  final String studentName;
  final ValueChanged<int> onSave;

  @override
  State<_GradeSheet> createState() => _GradeSheetState();
}

class _GradeSheetState extends State<_GradeSheet> {
  late final TextEditingController _marksController;

  @override
  void initState() {
    super.initState();
    // Pre-fill with the existing grade, else the teacher-end auto-calculated
    // objective score, else blank.
    _marksController = TextEditingController(
      text:
          widget.submission.marks?.toString() ??
          widget.suggestedMarks?.toString() ??
          '',
    );
  }

  @override
  void dispose() {
    _marksController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAssignment = widget.assessment.type == AssessmentType.assignment;
    final answers = widget.submission.answers;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(context).viewInsets.bottom + 18,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.grade_outlined, color: PortalColors.brandBlue),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Grade — ${widget.studentName}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '${widget.assessment.title} • out of ${widget.assessment.totalMarks}',
                style: const TextStyle(color: PortalColors.subtleText),
              ),
              const SizedBox(height: 14),
              if (isAssignment)
                _AssignmentAnswerView(answers: answers)
              else
                _QuizAnswerView(
                  assessment: widget.assessment,
                  answers: answers,
                ),
              const SizedBox(height: 14),
              if (widget.suggestedMarks != null)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAFBEF),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFB9F4C9)),
                  ),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calculate_outlined,
                        size: 18,
                        color: Color(0xFF0F766E),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Auto-calculated from the answer key: '
                          '${widget.suggestedMarks}/${widget.assessment.totalMarks}. '
                          'Review and save (you can override).',
                          style: const TextStyle(
                            color: Color(0xFF0F766E),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: const Color(0xFFFCE8A6)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.rate_review_outlined,
                        size: 18,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'No answer key — grade this manually.',
                          style: TextStyle(
                            color: Color(0xFFB45309),
                            fontWeight: FontWeight.w600,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              TextField(
                controller: _marksController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'Marks (out of ${widget.assessment.totalMarks})',
                  prefixIcon: const Icon(Icons.score_outlined),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    final marks =
                        int.tryParse(_marksController.text.trim()) ?? 0;
                    final clamped = marks.clamp(
                      0,
                      widget.assessment.totalMarks,
                    );
                    widget.onSave(clamped);
                  },
                  icon: const Icon(Icons.save_rounded),
                  label: const Text('Save grade'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuizAnswerView extends StatelessWidget {
  const _QuizAnswerView({required this.assessment, required this.answers});

  final Assessment assessment;
  final Map<String, String> answers;

  @override
  Widget build(BuildContext context) {
    if (assessment.questions.isEmpty) {
      return const _EmptyText('This paper has no questions.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < assessment.questions.length; i++)
          _quizRow(i, assessment.questions[i]),
      ],
    );
  }

  Widget _quizRow(int index, AssessmentQuestion q) {
    final given = (answers[q.id] ?? '').trim();
    final correct = q.correctAnswer?.trim() ?? '';
    final objective = correct.isNotEmpty;
    final isRight = objective && given.toLowerCase() == correct.toLowerCase();
    final color = !objective
        ? PortalColors.subtleText
        : (isRight ? const Color(0xFF0F766E) : const Color(0xFFB91C1C));
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${index + 1}. ${q.question}  (${q.marks} marks)',
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                !objective
                    ? Icons.notes_outlined
                    : (isRight
                          ? Icons.check_circle_outline
                          : Icons.cancel_outlined),
                size: 16,
                color: color,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  given.isEmpty ? '(no answer)' : given,
                  style: TextStyle(color: color, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          if (objective && !isRight) ...[
            const SizedBox(height: 2),
            Text(
              'Correct: $correct',
              style: const TextStyle(
                color: PortalColors.subtleText,
                fontSize: 12,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _AssignmentAnswerView extends StatelessWidget {
  const _AssignmentAnswerView({required this.answers});

  final Map<String, String> answers;

  @override
  Widget build(BuildContext context) {
    final text = (answers['text'] ?? '').trim();
    final file = (answers['file'] ?? '').trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Submitted answer',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: Text(text.isEmpty ? '(no typed answer)' : text),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            const Icon(
              Icons.attach_file_rounded,
              size: 18,
              color: PortalColors.subtleText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                file.isEmpty ? 'No file attached' : file,
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
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

/// Teacher "Assessments" hub. Two clear sub-portions — Quizzes and
/// Assignments — each listing the teacher's items of that type and a button to
/// create a new one (which opens the generator preset to that type). Tapping an
/// item opens its offline QR share screen. The Exam (printed paper + hall
/// attendance) portion lives separately under the Exam Att. nav item.
class _TeacherAssessmentsHub extends StatelessWidget {
  const _TeacherAssessmentsHub({
    required this.repository,
    required this.teacher,
    required this.onCreate,
    required this.onOpenAssessment,
  });

  final AppRepository repository;
  final AssessmentTeacher teacher;
  final ValueChanged<AssessmentType> onCreate;
  final ValueChanged<Assessment> onOpenAssessment;

  @override
  Widget build(BuildContext context) {
    final all = repository.assessmentsForTeacher(teacher);
    final quizzes = all.where((a) => a.type == AssessmentType.quiz).toList();
    final assignments = all
        .where((a) => a.type == AssessmentType.assignment)
        .toList();

    return DefaultTabController(
      length: 2,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
            child: _HeaderCard(
              title: 'Assessments',
              subtitle:
                  'Build quizzes and assignments. Each one gets a printable PDF and a real offline QR students scan to attempt.',
              icon: Icons.assignment_outlined,
            ),
          ),
          const SizedBox(height: 12),
          Material(
            color: Colors.white,
            child: TabBar(
              tabs: const [
                Tab(text: 'Quizzes'),
                Tab(text: 'Assignments'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _AssessmentTypeList(
                  type: AssessmentType.quiz,
                  items: quizzes,
                  repository: repository,
                  onCreate: () => onCreate(AssessmentType.quiz),
                  onOpenAssessment: onOpenAssessment,
                  emptyHint:
                      'No quizzes yet. Create one — MCQ / True-False / short answers, timed and auto-graded.',
                ),
                _AssessmentTypeList(
                  type: AssessmentType.assignment,
                  items: assignments,
                  repository: repository,
                  onCreate: () => onCreate(AssessmentType.assignment),
                  onOpenAssessment: onOpenAssessment,
                  emptyHint:
                      'No assignments yet. Create one — long-answer / file-upload tasks students submit by a due date.',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentTypeList extends StatelessWidget {
  const _AssessmentTypeList({
    required this.type,
    required this.items,
    required this.repository,
    required this.onCreate,
    required this.onOpenAssessment,
    required this.emptyHint,
  });

  final AssessmentType type;
  final List<Assessment> items;
  final AppRepository repository;
  final VoidCallback onCreate;
  final ValueChanged<Assessment> onOpenAssessment;
  final String emptyHint;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add_rounded),
            label: Text('Create ${type.label}'),
          ),
        ),
        const SizedBox(height: 14),
        if (items.isEmpty)
          _EmptyText(emptyHint)
        else
          for (final assessment in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _HubItemCard(
                assessment: assessment,
                course: repository.courseById(assessment.courseId),
                onShareQr: () => onOpenAssessment(assessment),
              ),
            ),
      ],
    );
  }
}

class _HubItemCard extends StatelessWidget {
  const _HubItemCard({
    required this.assessment,
    required this.course,
    required this.onShareQr,
  });

  final Assessment assessment;
  final AssessmentCourse? course;
  final VoidCallback onShareQr;

  @override
  Widget build(BuildContext context) {
    final isLive = assessment.status == AssessmentStatus.active;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  assessment.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              _Badge(
                label: isLive ? 'Live' : assessment.status.label,
                color: isLive
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFB45309),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              _InfoPill('Course', course?.courseCode ?? assessment.courseId),
              _InfoPill('Questions', '${assessment.questions.length}'),
              _InfoPill('Marks', '${assessment.totalMarks}'),
              _InfoPill('Duration', '${assessment.durationMinutes} min'),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onShareQr,
              icon: const Icon(Icons.qr_code_2_rounded),
              label: const Text('Share offline QR'),
            ),
          ),
        ],
      ),
    );
  }
}

/// Teacher screen: point the phone camera at a student's submission QR to
/// receive their answers offline. After a successful scan the submission is
/// imported into the repository and the teacher lands on the Results screen.
class _ScanSubmissionScreen extends StatefulWidget {
  const _ScanSubmissionScreen({
    required this.repository,
    required this.onDone,
    this.assessment,
  });

  final AppRepository repository;
  final VoidCallback onDone;

  /// When set, this scanner belongs to ONE assessment — the header names it and
  /// submissions for a DIFFERENT assessment are rejected with a clear message.
  final Assessment? assessment;

  @override
  State<_ScanSubmissionScreen> createState() => _ScanSubmissionScreenState();
}

class _ScanSubmissionScreenState extends State<_ScanSubmissionScreen> {
  MobileScannerController? _ctrl;
  bool _handled = false;
  String? _lastResult;
  bool _lastSuccess = false;
  bool _keyStep = false;
  // questionId -> option text -> marks controller (per-option partial credit).
  final Map<String, Map<String, TextEditingController>> _markCtrls = {};

  Assessment? get _asm => widget.assessment;

  bool _isObjective(AssessmentQuestion q) =>
      q.type == QuestionType.mcq || q.type == QuestionType.trueFalse;

  @override
  void initState() {
    super.initState();
    final a = _asm;
    if (a != null) {
      for (final q in a.questions) {
        if (!_isObjective(q)) continue;
        final ctrls = <String, TextEditingController>{};
        for (final opt in q.options) {
          // Pre-fill: existing per-option marks, else the old correct option
          // gets the question's full marks, else blank.
          int? value;
          if (q.optionMarks.isNotEmpty) {
            value = q.optionMarks[opt];
          } else if ((q.correctAnswer ?? '') == opt) {
            value = q.marks;
          }
          ctrls[opt] = TextEditingController(
            text: value == null ? '' : '$value',
          );
        }
        _markCtrls[q.id] = ctrls;
      }
      // Ask the teacher for the marking scheme FIRST when an objective question
      // has none — so a paper can be built WITHOUT answers (nothing to leak in
      // the student QR) and marks still apply automatically while scanning.
      _keyStep = widget.repository.assessmentNeedsAnswerKey(a.id);
    }
    if (!_keyStep) _ensureCamera();
  }

  @override
  void dispose() {
    for (final m in _markCtrls.values) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    _ctrl?.dispose();
    super.dispose();
  }

  void _ensureCamera() {
    _ctrl ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
  }

  static const MethodChannel _speech = MethodChannel(
    'csexam_qr_attendance/speech',
  );

  void _say(String message) {
    if (message.trim().isEmpty) return;
    try {
      _speech.invokeMethod<void>('speak', {'message': message});
    } catch (_) {
      // No native TTS (desktop/web) — silent is fine.
    }
  }

  Future<void> _exportResults(Assessment a, {required bool csv}) async {
    final subs = widget.repository.submissionsForAssessment(a.id);
    if (subs.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No submissions to export yet.')),
      );
      return;
    }
    try {
      if (csv) {
        await QuizResultsExport.shareCsv(a, subs);
      } else {
        await QuizResultsExport.sharePdf(a, subs);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    }
  }

  /// Builds the questionId → (option → marks) scheme from the input boxes.
  Map<String, Map<String, int>> _collectScheme() {
    final out = <String, Map<String, int>>{};
    _markCtrls.forEach((qid, ctrls) {
      final om = <String, int>{};
      ctrls.forEach((opt, c) {
        final v = int.tryParse(c.text.trim());
        if (v != null) om[opt] = v;
      });
      if (om.isNotEmpty) out[qid] = om;
    });
    return out;
  }

  /// Ready when every objective question has at least one option scored > 0.
  bool get _schemeReady {
    for (final ctrls in _markCtrls.values) {
      final hasPositive = ctrls.values.any(
        (c) => (int.tryParse(c.text.trim()) ?? 0) > 0,
      );
      if (!hasPositive) return false;
    }
    return _markCtrls.isNotEmpty;
  }

  void _saveKeyAndScan() {
    final a = _asm;
    if (a != null) {
      widget.repository.setAssessmentMarkingScheme(a.id, _collectScheme());
    }
    _ensureCamera();
    setState(() => _keyStep = false);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    _handleRaw(raw);
    // Keep the camera ON — just cool down briefly before the next student,
    // exactly like the exam paper-QR scanner.
    Future.delayed(const Duration(milliseconds: 1300), () {
      if (mounted) _handled = false;
    });
  }

  void _handleRaw(String raw) {
    if (!SubmissionQrCodec.looksLike(raw)) {
      setState(() {
        _lastResult = 'Not a student submission QR — try again.';
        _lastSuccess = false;
      });
      return;
    }
    try {
      final submission = SubmissionQrCodec.decode(raw);
      final scope = _asm;
      if (scope != null && submission.assessmentId != scope.id) {
        setState(() {
          _lastResult =
              'Different quiz — this scanner is only for "${scope.title}".';
          _lastSuccess = false;
        });
        return;
      }
      final imported = widget.repository.importSubmission(submission);
      final name = submission.studentName.trim();
      final who = name.isEmpty
          ? submission.studentId
          : '${submission.studentId} • $name';
      final marksLabel = imported.marks == null
          ? 'needs manual grading'
          : '${imported.marks} marks';
      // Call out the student's name (and marks) so the teacher gets clear
      // audio confirmation of who was just scanned.
      _say(
        name.isEmpty
            ? 'Received'
            : imported.marks == null
            ? name
            : '$name, ${imported.marks} marks',
      );
      setState(() {
        _lastResult = '✓ $who — $marksLabel';
        _lastSuccess = true;
      });
    } on FormatException catch (e) {
      setState(() {
        _lastResult = 'Invalid submission QR: ${e.message}';
        _lastSuccess = false;
      });
    }
  }

  /// Live attendance + collection stats for the last-scanned submission's
  /// assessment: how many were expected, how many submitted (present), and how
  /// many are still pending (absent).
  Widget _buildStatsCard() {
    final id = _asm?.id;
    if (id == null) return const SizedBox.shrink();
    final assessment = widget.repository.assessmentById(id);
    if (assessment == null) return const SizedBox.shrink();
    final present = widget.repository.submissionsForAssessment(id).length;
    final total = assessment.expectedStudents > 0
        ? assessment.expectedStudents
        : widget.repository.studentsForAssessment(assessment).length;
    final absent = total > present ? total - present : 0;
    final pct = total > 0 ? ((present / total) * 100).clamp(0, 100).round() : 0;

    Widget stat(String label, String value, Color color) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withValues(alpha: 0.30)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: const TextStyle(fontSize: 11, color: Color(0xFF475569)),
            ),
          ],
        ),
      ),
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            assessment.title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              stat('Total', '$total', const Color(0xFF334155)),
              stat('Submitted', '$present', const Color(0xFF047857)),
              stat('Absent', '$absent', const Color(0xFFB91C1C)),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: total > 0 ? present / total : 0,
              minHeight: 9,
              backgroundColor: const Color(0xFFE2E8F0),
              color: const Color(0xFF047857),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$present of $total submitted ($pct%) • $absent still absent',
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: Color(0xFF475569),
            ),
          ),
          if (total == 0)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Text(
                'Tip: re-create the paper on this build so the expected count '
                'is known (older papers show 0).',
                style: TextStyle(fontSize: 10.5, color: Color(0xFF94A3B8)),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) => _keyStep ? _answerKeyView() : _scanView(),
    );
  }

  // ----- Step 1: answer key (teacher only, never in the student QR) ---------

  Widget _answerKeyView() {
    final a = _asm!;
    final objective = a.questions.where(_isObjective).toList();
    return _TeacherScroll(
      children: [
        _HeaderCard(
          title: 'Marking scheme — ${a.title}',
          subtitle:
              'Give each option its own marks (your values, your order). The '
              'student earns the marks of the option they pick. This stays on '
              'YOUR phone only — never in the student QR.',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 16),
        for (var i = 0; i < objective.length; i++)
          _keyQuestion(i + 1, objective[i]),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _schemeReady ? _saveKeyAndScan : null,
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF047857),
            ),
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Save scheme & start scanning'),
          ),
        ),
        if (!_schemeReady)
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: Text(
              'Give at least one option a mark above 0 in every question.',
              style: TextStyle(color: Color(0xFFB91C1C), fontSize: 12),
            ),
          ),
      ],
    );
  }

  Widget _keyQuestion(int n, AssessmentQuestion q) {
    final ctrls = _markCtrls[q.id] ?? const {};
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Q$n. ${q.question}',
            style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13.5),
          ),
          const SizedBox(height: 4),
          const Text(
            'Marks for each option',
            style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          for (final opt in q.options)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      opt,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 72,
                    child: TextField(
                      controller: ctrls[opt],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      onChanged: (_) => setState(() {}),
                      decoration: const InputDecoration(
                        isDense: true,
                        hintText: 'marks',
                        border: OutlineInputBorder(),
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
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

  // ----- Step 2: continuous scanning (camera stays ON) ----------------------

  Widget _scanView() {
    final a = _asm;
    return _TeacherScroll(
      children: [
        _HeaderCard(
          title: a == null ? 'Scan student submission' : 'Scan: ${a.title}',
          subtitle:
              'Camera stays ON — show each student\'s submission QR one after '
              'another (like the exam paper scan). Marks apply automatically.',
          icon: Icons.qr_code_scanner_rounded,
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (_ctrl != null)
                          MobileScanner(
                            controller: _ctrl,
                            onDetect: _onDetect,
                          ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: Colors.white,
                                  width: 3,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (_lastResult != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _lastSuccess
                          ? const Color(0xFFEAFBEF)
                          : const Color(0xFFFEE2E2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _lastSuccess
                            ? const Color(0xFFB9F4C9)
                            : const Color(0xFFF4C9C9),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _lastSuccess
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: _lastSuccess
                              ? const Color(0xFF0F766E)
                              : const Color(0xFFB91C1C),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            _lastResult!,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              color: _lastSuccess
                                  ? const Color(0xFF0F766E)
                                  : const Color(0xFFB91C1C),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                _buildStatsCard(),
                const SizedBox(height: 12),
                _liveList(),
                if (a != null) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _exportResults(a, csv: true),
                          icon: const Icon(Icons.grid_on_rounded),
                          label: const Text('Export Excel'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => _exportResults(a, csv: false),
                          icon: const Icon(Icons.picture_as_pdf_rounded),
                          label: const Text('Export PDF'),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    if (a != null) ...[
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () => setState(() => _keyStep = true),
                          icon: const Icon(Icons.vpn_key_outlined),
                          label: const Text('Answer key'),
                        ),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: widget.onDone,
                        icon: const Icon(Icons.grading_outlined),
                        label: const Text('Done'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  /// Live list of who has been scanned for THIS quiz, with their marks.
  Widget _liveList() {
    final a = _asm;
    if (a == null) return const SizedBox.shrink();
    final subs = [...widget.repository.submissionsForAssessment(a.id)]..sort(
      (x, y) => (y.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
          .compareTo(x.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0)),
    );
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F8FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE2E8F0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Scanned for this quiz',
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
              Text(
                '${subs.length}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF047857),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          if (subs.isEmpty)
            const Text(
              'No scans yet — show a student\'s submission QR to the camera.',
              style: TextStyle(fontSize: 12, color: Color(0xFF94A3B8)),
            )
          else
            for (var i = 0; i < subs.length; i++)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(
                  children: [
                    SizedBox(
                      width: 20,
                      child: Text(
                        '${i + 1}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        '${subs[i].studentId}'
                        '${subs[i].studentName.isEmpty ? '' : ' • ${subs[i].studentName}'}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                    Text(
                      subs[i].marks == null
                          ? '—'
                          : '${subs[i].marks}${a.totalMarks > 0 ? '/${a.totalMarks}' : ''}',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12.5,
                        color: subs[i].marks == null
                            ? const Color(0xFF94A3B8)
                            : const Color(0xFF0F766E),
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

/// Renders a REAL scannable QR for the assessment. The QR carries the whole
/// paper packed offline (gzip+base64) so a student phone can scan it with no
/// internet. If the paper is too large to fit in one QR, falls back to a QR of
/// the short code and nudges the teacher to share the PDF instead.
class _ShareableQrBlock extends StatelessWidget {
  const _ShareableQrBlock({
    required this.assessment,
    required this.course,
    required this.isLive,
  });

  final Assessment assessment;
  final AssessmentCourse? course;
  final bool isLive;

  @override
  Widget build(BuildContext context) {
    final payload = AssessmentQrCodec.encode(assessment);
    final fitsOffline = payload != null;
    // When the paper is too big to embed, the QR still works as a short code
    // for same-network / future-backend lookup.
    final qrData = payload ?? assessment.qrCode;

    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: QrImageView(
            data: qrData,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
            errorCorrectionLevel: QrErrorCorrectLevel.M,
          ),
        ),
        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: fitsOffline
                ? const Color(0xFFEAFBEF)
                : const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: fitsOffline
                  ? const Color(0xFFB9F4C9)
                  : const Color(0xFFFCE8A6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                fitsOffline
                    ? Icons.wifi_off_rounded
                    : Icons.info_outline_rounded,
                size: 16,
                color: fitsOffline
                    ? const Color(0xFF0F766E)
                    : const Color(0xFFB45309),
              ),
              const SizedBox(width: 6),
              Text(
                fitsOffline
                    ? 'Offline-ready — full paper inside this QR'
                    : 'Paper too large for offline QR — share the PDF',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  color: fitsOffline
                      ? const Color(0xFF0F766E)
                      : const Color(0xFFB45309),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        SelectableText(
          assessment.qrCode,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
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
            _InfoPill('Type', assessment.type.label),
            _InfoPill('Status', isLive ? 'Live' : assessment.status.label),
            _InfoPill('Course', course?.courseCode ?? assessment.courseId),
            _InfoPill('Questions', '${assessment.questions.length}'),
            _InfoPill('Duration', '${assessment.durationMinutes} min'),
            _InfoPill('Marks', '${assessment.totalMarks}'),
          ],
        ),
        const SizedBox(height: 12),
        const Text(
          'Show this QR in class. Students open Assess → Scan, point the camera '
          'here, and the whole paper loads on their phone — no internet needed.',
          textAlign: TextAlign.center,
          style: TextStyle(color: PortalColors.subtleText),
        ),
      ],
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
        final service = FeatureVisibilityService.instance;
        // The whole modules section is admin-gated for teachers.
        if (!service.isVisible(AppRole.faculty, FeatureKey.teacherModules)) {
          return const SizedBox.shrink();
        }
        final visible = service
            .visibleFor(AppRole.faculty)
            // FYP has its own slot; the gate keys are nav tabs, not cards.
            .where(
              (meta) =>
                  meta.key != FeatureKey.fyp &&
                  meta.key != FeatureKey.teacherModules &&
                  meta.key != FeatureKey.teacherAssess &&
                  meta.key != FeatureKey.teacherLive &&
                  meta.key != FeatureKey.teacherResults,
            )
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
