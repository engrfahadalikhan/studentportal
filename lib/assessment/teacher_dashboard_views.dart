import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../ui/student_portal_shell.dart';
import 'teacher_dashboard_models.dart';
import 'teacher_dashboard_theme.dart';

class TeacherDashboardHomeView extends StatelessWidget {
  const TeacherDashboardHomeView({
    super.key,
    required this.data,
    required this.onOpenCourse,
    required this.onOpenNotifications,
    required this.onOpenExamAttendance,
    required this.onOpenFyp,
    this.trailing,
  });

  final TeacherDashboardHomeData data;
  final ValueChanged<TeacherCourseSummary> onOpenCourse;
  final VoidCallback onOpenNotifications;
  final Widget? trailing;
  final VoidCallback onOpenExamAttendance;
  final VoidCallback onOpenFyp;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _HeroCard(
          title: 'Welcome, Teacher ${data.teacherName}',
          icon: Icons.co_present_outlined,
          children: [
            _MetricTile(
              icon: Icons.class_outlined,
              label: 'Courses',
              value: '${data.totalCourses}',
            ),
            _MetricTile(
              icon: Icons.groups_outlined,
              label: 'Students',
              value: '${data.totalStudents}',
            ),
            _MetricTile(
              icon: Icons.assignment_outlined,
              label: 'Assessments',
              value: '${data.totalAssessments}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 720;
            final panels = [
              _ActionPanel(
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                value: '${data.unreadNotifications} unread',
                onTap: onOpenNotifications,
              ),
              _ActionPanel(
                icon: Icons.fact_check_outlined,
                title: 'Exam Attendance',
                value: '${data.attendanceSheets} sheets',
                onTap: onOpenExamAttendance,
              ),
              _ActionPanel(
                icon: Icons.school_outlined,
                title: 'FYP Workspace',
                value: 'Ideas, allocations, evaluations',
                onTap: onOpenFyp,
              ),
            ];
            if (compact) {
              return Column(
                children: [
                  for (final panel in panels) ...[
                    panel,
                    const SizedBox(height: 10),
                  ],
                ],
              );
            }
            return Row(
              children: [
                for (var i = 0; i < panels.length; i++) ...[
                  Expanded(child: panels[i]),
                  if (i < panels.length - 1) const SizedBox(width: 12),
                ],
              ],
            );
          },
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Registered courses',
          child: data.courses.isEmpty
              ? const _EmptyState('No registered courses found.')
              : Column(
                  children: data.courses
                      .map(
                        (course) => _CourseTile(
                          course: course,
                          onTap: () => onOpenCourse(course),
                        ),
                      )
                      .toList(),
                ),
        ),
        if (trailing != null) ...[const SizedBox(height: 16), trailing!],
      ],
    );
  }
}

class NotificationsView extends StatelessWidget {
  const NotificationsView({
    super.key,
    required this.notifications,
    required this.onBack,
    required this.onMarkRead,
  });

  final List<TeacherNotification> notifications;
  final VoidCallback onBack;
  final ValueChanged<TeacherNotification> onMarkRead;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Notifications',
          child: notifications.isEmpty
              ? const _EmptyState('No notifications found.')
              : Column(
                  children: [
                    for (final notification in notifications)
                      _NotificationTile(
                        notification: notification,
                        onMarkRead: () => onMarkRead(notification),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ExamAttendanceHomeView extends StatelessWidget {
  const ExamAttendanceHomeView({
    super.key,
    required this.data,
    required this.onBack,
    required this.onScan,
    required this.onViewAttendance,
    required this.onShareAttendance,
    required this.onSharingStats,
  });

  final ExamAttendanceDashboardData data;
  final VoidCallback onBack;
  final VoidCallback onScan;
  final VoidCallback onViewAttendance;
  final VoidCallback onShareAttendance;
  final VoidCallback onSharingStats;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: 'Exam Attendance',
          icon: Icons.fact_check_outlined,
          children: [
            _MetricTile(
              icon: Icons.list_alt_outlined,
              label: 'Sheets',
              value: '${data.totalSheets}',
            ),
            _MetricTile(
              icon: Icons.ios_share_outlined,
              label: 'Shared',
              value: '${data.sharedSheets}',
            ),
            _MetricTile(
              icon: Icons.move_to_inbox_outlined,
              label: 'Accepted',
              value: '${data.acceptedSheets}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            _MenuCard(
              icon: Icons.qr_code_scanner_rounded,
              title: 'Scan QR Code',
              onTap: onScan,
            ),
            _MenuCard(
              icon: Icons.edit_calendar_outlined,
              title: 'View/Edit Attendance',
              onTap: onViewAttendance,
            ),
            _MenuCard(
              icon: Icons.ios_share_outlined,
              title: 'Share Attendance Stats',
              onTap: onShareAttendance,
            ),
            _MenuCard(
              icon: Icons.swap_horiz_outlined,
              title: 'Shared/Accepted Stats',
              onTap: onSharingStats,
            ),
          ],
        ),
      ],
    );
  }
}

class ExamQrScanView extends StatefulWidget {
  const ExamQrScanView({
    super.key,
    required this.onBack,
    required this.onQrDetected,
    this.errorMessage,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onQrDetected;
  final String? errorMessage;

  @override
  State<ExamQrScanView> createState() => _ExamQrScanViewState();
}

class _ExamQrScanViewState extends State<ExamQrScanView> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _textController = TextEditingController();
  bool _handled = false;

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Scan QR Code',
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 280,
                  child: MobileScanner(
                    controller: _controller,
                    onDetect: _handleCapture,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'QR code'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitText,
                  icon: const Icon(Icons.search_outlined),
                  label: const Text('Fetch Hall Stats'),
                ),
              ),
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorText(widget.errorMessage!),
              ],
            ],
          ),
        ),
      ],
    );
  }

  void _handleCapture(BarcodeCapture capture) {
    if (_handled) {
      return;
    }
    final raw = capture.barcodes
        .map((barcode) => barcode.rawValue?.trim() ?? '')
        .firstWhere((value) => value.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) {
      return;
    }
    _handled = true;
    widget.onQrDetected(raw);
  }

  void _submitText() {
    final raw = _textController.text.trim();
    if (raw.isEmpty) {
      return;
    }
    widget.onQrDetected(raw);
  }
}

class HallStatsView extends StatelessWidget {
  const HallStatsView({
    super.key,
    required this.stats,
    required this.onBack,
    required this.onTakeAttendance,
  });

  final ExamHallStats stats;
  final VoidCallback onBack;
  final VoidCallback onTakeAttendance;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: stats.hallName,
          icon: Icons.meeting_room_outlined,
          children: [
            _MetricTile(
              icon: Icons.menu_book_outlined,
              label: 'Course',
              value: stats.courseName,
            ),
            _MetricTile(
              icon: Icons.groups_outlined,
              label: 'Total',
              value: '${stats.totalStudents}',
            ),
            _MetricTile(
              icon: Icons.check_circle_outline,
              label: 'Present',
              value: '${stats.presentStudents}',
            ),
            _MetricTile(
              icon: Icons.cancel_outlined,
              label: 'Absent',
              value: '${stats.absentStudents}',
            ),
            _MetricTile(
              icon: Icons.verified_outlined,
              label: 'Status',
              value: stats.status,
            ),
          ],
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: onTakeAttendance,
            icon: const Icon(Icons.how_to_reg_outlined),
            label: const Text('Take Attendance'),
          ),
        ),
      ],
    );
  }
}

class TakeExamAttendanceView extends StatefulWidget {
  const TakeExamAttendanceView({
    super.key,
    required this.detail,
    required this.onBack,
    required this.onSave,
  });

  final ExamAttendanceSheetDetail detail;
  final VoidCallback onBack;
  final Future<void> Function(Map<String, String> statusesByStudentId) onSave;

  @override
  State<TakeExamAttendanceView> createState() => _TakeExamAttendanceViewState();
}

class _TakeExamAttendanceViewState extends State<TakeExamAttendanceView> {
  late Map<String, String> _statuses;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _statuses = {
      for (final student in widget.detail.students)
        student.studentId: student.status,
    };
  }

  @override
  Widget build(BuildContext context) {
    final present = _statuses.values
        .where((status) => status == 'present')
        .length;
    final absent = _statuses.values
        .where((status) => status != 'present')
        .length;
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: widget.detail.stats.courseName,
          icon: Icons.how_to_reg_outlined,
          children: [
            _MetricTile(
              icon: Icons.meeting_room_outlined,
              label: 'Hall',
              value: widget.detail.stats.hallName,
            ),
            _MetricTile(
              icon: Icons.check_circle_outline,
              label: 'Present',
              value: '$present',
            ),
            _MetricTile(
              icon: Icons.cancel_outlined,
              label: 'Absent',
              value: '$absent',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Students',
          child: widget.detail.students.isEmpty
              ? const _EmptyState('No students found.')
              : Column(
                  children: [
                    for (final student in widget.detail.students)
                      _AttendanceStudentTile(
                        student: student.copyWith(
                          status: _statuses[student.studentId],
                        ),
                        onChanged: (status) {
                          setState(() {
                            _statuses[student.studentId] = status;
                          });
                        },
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.save_outlined),
            label: Text(_saving ? 'Saving...' : 'Save Attendance'),
          ),
        ),
      ],
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await widget.onSave(_statuses);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class AttendanceSheetsView extends StatelessWidget {
  const AttendanceSheetsView({
    super.key,
    required this.sheets,
    required this.onBack,
    required this.onOpenSheet,
  });

  final List<ExamAttendanceSheetSummary> sheets;
  final VoidCallback onBack;
  final ValueChanged<ExamAttendanceSheetSummary> onOpenSheet;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'View/Edit Attendance',
          child: sheets.isEmpty
              ? const _EmptyState('No attendance found.')
              : Column(
                  children: [
                    for (final sheet in sheets)
                      _AttendanceSheetTile(
                        sheet: sheet,
                        onTap: () => onOpenSheet(sheet),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class ShareAttendanceView extends StatelessWidget {
  const ShareAttendanceView({
    super.key,
    required this.sheets,
    required this.onBack,
    required this.onShare,
  });

  final List<ExamAttendanceSheetSummary> sheets;
  final VoidCallback onBack;
  final ValueChanged<ExamAttendanceSheetSummary> onShare;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Share Attendance Stats',
          child: sheets.isEmpty
              ? const _EmptyState('No attendance found.')
              : Column(
                  children: [
                    for (final sheet in sheets)
                      _AttendanceSheetTile(
                        sheet: sheet,
                        trailing: FilledButton.tonalIcon(
                          onPressed: () => onShare(sheet),
                          icon: const Icon(Icons.ios_share_outlined),
                          label: const Text('Share'),
                        ),
                        onTap: () => onShare(sheet),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class AttendanceSharingView extends StatelessWidget {
  const AttendanceSharingView({
    super.key,
    required this.data,
    required this.onBack,
  });

  final AttendanceSharingData data;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        Card(
          child: DefaultTabController(
            length: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const TabBar(
                  tabs: [
                    Tab(text: 'Shared Attendance Sheets'),
                    Tab(text: 'Accepted Attendance Sheets'),
                  ],
                ),
                SizedBox(
                  height: 520,
                  child: TabBarView(
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: data.sharedSheets.isEmpty
                            ? const _EmptyState('No shared attendance found.')
                            : ListView(
                                children: [
                                  for (final sheet in data.sharedSheets)
                                    _SharedAttendanceTile(sheet: sheet),
                                ],
                              ),
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16),
                        child: data.acceptedSheets.isEmpty
                            ? const _EmptyState('No accepted attendance found.')
                            : ListView(
                                children: [
                                  for (final sheet in data.acceptedSheets)
                                    _AcceptedAttendanceTile(sheet: sheet),
                                ],
                              ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class RegisteredCoursesView extends StatelessWidget {
  const RegisteredCoursesView({
    super.key,
    required this.courses,
    required this.onOpenCourse,
  });

  final List<TeacherCourseSummary> courses;
  final ValueChanged<TeacherCourseSummary> onOpenCourse;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _SectionCard(
          title: 'Registered courses',
          child: courses.isEmpty
              ? const _EmptyState('No registered courses found.')
              : Column(
                  children: [
                    for (final course in courses)
                      _CourseTile(
                        course: course,
                        onTap: () => onOpenCourse(course),
                      ),
                  ],
                ),
        ),
      ],
    );
  }
}

class CourseDetailView extends StatelessWidget {
  const CourseDetailView({
    super.key,
    required this.data,
    required this.onBack,
    required this.onNewAssessment,
    required this.onOpenAssessment,
  });

  final TeacherCourseDetailData data;
  final VoidCallback onBack;
  final VoidCallback onNewAssessment;
  final ValueChanged<CourseAssessmentSummary> onOpenAssessment;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: data.course.courseName,
          icon: Icons.menu_book_outlined,
          children: [
            _MetricTile(
              icon: Icons.groups_outlined,
              label: 'Students',
              value: '${data.course.totalStudents}',
            ),
            _MetricTile(
              icon: Icons.assignment_outlined,
              label: 'Assessments',
              value: '${data.course.totalAssessments}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Assessments',
          action: FilledButton.icon(
            onPressed: onNewAssessment,
            icon: const Icon(Icons.add_rounded),
            label: const Text('New Assessment'),
          ),
          child: data.assessments.isEmpty
              ? const _EmptyState('No assessments found.')
              : Column(
                  children: data.assessments
                      .map(
                        (assessment) => _AssessmentTile(
                          assessment: assessment,
                          onTap: () => onOpenAssessment(assessment),
                        ),
                      )
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class NewAssessmentView extends StatefulWidget {
  const NewAssessmentView({
    super.key,
    required this.course,
    required this.onBack,
    required this.onSave,
  });

  final TeacherCourseSummary course;
  final VoidCallback onBack;
  final Future<void> Function(NewTeacherAssessmentInput input) onSave;

  @override
  State<NewAssessmentView> createState() => _NewAssessmentViewState();
}

class _NewAssessmentViewState extends State<NewAssessmentView> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _marksController = TextEditingController();
  final _instructionsController = TextEditingController();
  TeacherAssessmentKind _type = TeacherAssessmentKind.quiz;
  DateTime _dueDate = DateTime.now();
  bool _saving = false;

  @override
  void dispose() {
    _titleController.dispose();
    _marksController.dispose();
    _instructionsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: '+ New Assessment',
          child: Form(
            key: _formKey,
            child: Column(
              children: [
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Assessment title',
                  ),
                  validator: (value) =>
                      value == null || value.trim().isEmpty ? 'Required' : null,
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<TeacherAssessmentKind>(
                  initialValue: _type,
                  items: TeacherAssessmentKind.values
                      .map(
                        (type) => DropdownMenuItem(
                          value: type,
                          child: Text(type.label),
                        ),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _type = value);
                    }
                  },
                  decoration: const InputDecoration(
                    labelText: 'Assessment type',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _marksController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Total marks'),
                  validator: (value) {
                    final marks = int.tryParse(value ?? '');
                    return marks == null || marks <= 0 ? 'Required' : null;
                  },
                ),
                const SizedBox(height: 12),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _pickDate,
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Date / due date',
                      prefixIcon: Icon(Icons.event_outlined),
                    ),
                    child: Text(_dateLabel(_dueDate)),
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _instructionsController,
                  minLines: 2,
                  maxLines: 4,
                  decoration: const InputDecoration(
                    labelText: 'Description / instructions',
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? const SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(_saving ? 'Saving...' : 'Save Assessment'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      initialDate: _dueDate,
    );
    if (picked != null) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave(
        NewTeacherAssessmentInput(
          courseId: widget.course.id,
          title: _titleController.text.trim(),
          type: _type,
          totalMarks: int.parse(_marksController.text.trim()),
          dueDate: _dueDate,
          instructions: _instructionsController.text.trim(),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class AssessmentDetailView extends StatelessWidget {
  const AssessmentDetailView({
    super.key,
    required this.data,
    required this.onBack,
  });

  final AssessmentDetailData data;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: data.assessment.title,
          icon: Icons.assignment_outlined,
          children: [
            _MetricTile(
              icon: Icons.category_outlined,
              label: 'Type',
              value: data.assessment.type.label,
            ),
            _MetricTile(
              icon: Icons.grade_outlined,
              label: 'Marks',
              value: '${data.assessment.totalMarks}',
            ),
            _MetricTile(
              icon: Icons.event_outlined,
              label: 'Date',
              value: _dateLabel(data.assessment.dueDate),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Submitted',
          child: data.submittedStudents.isEmpty
              ? const _EmptyState('No students found.')
              : Column(
                  children: data.submittedStudents
                      .map((student) => _StudentTile(student: student))
                      .toList(),
                ),
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Not submitted',
          child: data.notSubmittedStudents.isEmpty
              ? const _EmptyState('No students found.')
              : Column(
                  children: data.notSubmittedStudents
                      .map((student) => _StudentTile(student: student))
                      .toList(),
                ),
        ),
      ],
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({
    required this.icon,
    required this.title,
    required this.value,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: TeacherDashboardTheme.actionCardHeight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDashboardTheme.cardRadius),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _IconBox(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        value,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: PortalColors.subtleText),
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 230,
      height: TeacherDashboardTheme.menuCardHeight,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TeacherDashboardTheme.cardRadius),
        child: Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                _IconBox(icon),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: PortalColors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconBox extends StatelessWidget {
  const _IconBox(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: PortalColors.softBlue,
        borderRadius: BorderRadius.circular(
          TeacherDashboardTheme.compactRadius,
        ),
      ),
      child: Icon(icon, color: PortalColors.brandBlue),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    required this.notification,
    required this.onMarkRead,
  });

  final TeacherNotification notification;
  final VoidCallback onMarkRead;

  @override
  Widget build(BuildContext context) {
    return _ClickableTile(
      icon: notification.isRead
          ? Icons.mark_email_read_outlined
          : Icons.notifications_active_outlined,
      title: notification.title,
      subtitle:
          '${notification.message}  |  ${_dateTimeLabel(notification.createdAt)}',
      trailing: notification.isRead
          ? const _SmallBadge('Read')
          : FilledButton.tonalIcon(
              onPressed: onMarkRead,
              icon: const Icon(Icons.done_rounded),
              label: const Text('Unread'),
            ),
      onTap: notification.isRead ? () {} : onMarkRead,
    );
  }
}

class _AttendanceStudentTile extends StatelessWidget {
  const _AttendanceStudentTile({
    required this.student,
    required this.onChanged,
  });

  final ExamAttendanceStudent student;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      icon: Icons.person_outline,
      title: student.studentName,
      subtitle: student.rollNo,
      trailing: SegmentedButton<String>(
        segments: const [
          ButtonSegment(value: 'present', label: Text('Present')),
          ButtonSegment(value: 'absent', label: Text('Absent')),
        ],
        selected: {student.status == 'present' ? 'present' : 'absent'},
        onSelectionChanged: (values) => onChanged(values.first),
      ),
    );
  }
}

class _AttendanceSheetTile extends StatelessWidget {
  const _AttendanceSheetTile({
    required this.sheet,
    required this.onTap,
    this.trailing,
  });

  final ExamAttendanceSheetSummary sheet;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return _ClickableTile(
      icon: Icons.fact_check_outlined,
      title: sheet.courseName,
      subtitle:
          '${sheet.hallName}  |  ${_dateTimeLabel(sheet.examDateTime)}  |  Updated ${_dateTimeLabel(sheet.lastUpdatedAt)}',
      trailing:
          trailing ??
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _SmallBadge('${sheet.presentCount} present'),
              _SmallBadge('${sheet.absentCount} absent'),
            ],
          ),
      onTap: onTap,
    );
  }
}

class _SharedAttendanceTile extends StatelessWidget {
  const _SharedAttendanceTile({required this.sheet});

  final SharedAttendanceSheetSummary sheet;

  @override
  Widget build(BuildContext context) {
    return _PlainTile(
      icon: Icons.ios_share_outlined,
      title: sheet.courseName,
      subtitle:
          '${sheet.hallName}  |  ${_dateTimeLabel(sheet.examDateTime)}  |  ${sheet.sharedWith}  |  ${_dateTimeLabel(sheet.sharedAt)}  |  ${sheet.status}',
    );
  }
}

class _AcceptedAttendanceTile extends StatelessWidget {
  const _AcceptedAttendanceTile({required this.sheet});

  final AcceptedAttendanceSheetSummary sheet;

  @override
  Widget build(BuildContext context) {
    return _PlainTile(
      icon: Icons.move_to_inbox_outlined,
      title: sheet.courseName,
      subtitle:
          '${sheet.hallName}  |  ${_dateTimeLabel(sheet.examDateTime)}  |  ${sheet.receivedFrom}  |  ${_dateTimeLabel(sheet.acceptedAt)}  |  ${sheet.status}',
    );
  }
}

class _ErrorText extends StatelessWidget {
  const _ErrorText(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Text(
      message,
      style: const TextStyle(
        color: Color(0xFFB91C1C),
        fontWeight: FontWeight.w800,
      ),
      textAlign: TextAlign.center,
    );
  }
}

class _DashboardList extends StatelessWidget {
  const _DashboardList({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: TeacherDashboardTheme.pagePadding,
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 980),
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

class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.title,
    required this.icon,
    required this.children,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: PortalColors.brandBlue,
        borderRadius: BorderRadius.circular(TeacherDashboardTheme.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(spacing: 10, runSpacing: 10, children: children),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  const _MetricTile({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minWidth: 142, maxWidth: 260),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(
          TeacherDashboardTheme.compactRadius,
        ),
        border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 20),
          const SizedBox(width: 10),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: const TextStyle(color: Colors.white70)),
                Text(
                  value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w900,
                    fontSize: 20,
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

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.title, required this.child, this.action});

  final String title;
  final Widget child;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                if (action != null) action!,
              ],
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _CourseTile extends StatelessWidget {
  const _CourseTile({required this.course, required this.onTap});

  final TeacherCourseSummary course;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ClickableTile(
      icon: Icons.menu_book_outlined,
      title: course.courseName,
      subtitle: course.courseCode.isEmpty ? course.id : course.courseCode,
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SmallBadge('${course.totalStudents} students'),
          _SmallBadge('${course.totalAssessments} assessments'),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _AssessmentTile extends StatelessWidget {
  const _AssessmentTile({required this.assessment, required this.onTap});

  final CourseAssessmentSummary assessment;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ClickableTile(
      icon: Icons.assignment_outlined,
      title: assessment.title,
      subtitle:
          '${assessment.type.label}  |  ${assessment.totalMarks} marks  |  ${_dateLabel(assessment.dueDate)}',
      trailing: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _SmallBadge('${assessment.submittedCount} submitted'),
          _SmallBadge('${assessment.notSubmittedCount} pending'),
        ],
      ),
      onTap: onTap,
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile({required this.student});

  final StudentSubmissionSummary student;

  @override
  Widget build(BuildContext context) {
    final marks = student.marks == null ? '-' : '${student.marks}';
    return _PlainTile(
      icon: Icons.person_outline,
      title: student.studentName,
      subtitle: '${student.rollNo}  |  ${student.status}  |  Marks: $marks',
    );
  }
}

class _ClickableTile extends StatelessWidget {
  const _ClickableTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.trailing,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Widget trailing;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: _TileShell(
        icon: icon,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
      ),
    );
  }
}

class _PlainTile extends StatelessWidget {
  const _PlainTile({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return _TileShell(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: const SizedBox.shrink(),
    );
  }
}

class _TileShell extends StatelessWidget {
  const _TileShell({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: TeacherDashboardTheme.panelFill,
        borderRadius: BorderRadius.circular(
          TeacherDashboardTheme.compactRadius,
        ),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final info = Row(
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
                        fontWeight: FontWeight.w900,
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
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [info, const SizedBox(height: 10), trailing],
            );
          }
          return Row(
            children: [
              Expanded(child: info),
              const SizedBox(width: 12),
              Flexible(
                child: Align(alignment: Alignment.centerRight, child: trailing),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _SmallBadge extends StatelessWidget {
  const _SmallBadge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Chip(
      label: Text(text),
      visualDensity: VisualDensity.compact,
      backgroundColor: Colors.white,
      side: const BorderSide(color: PortalColors.cardBorder),
    );
  }
}

class _BackButton extends StatelessWidget {
  const _BackButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: OutlinedButton.icon(
        onPressed: onPressed,
        icon: const Icon(Icons.arrow_back_rounded),
        label: const Text('Back'),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 18),
      child: Center(
        child: Text(
          text,
          style: const TextStyle(color: PortalColors.subtleText),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

String _dateLabel(DateTime value) {
  return DateFormat('dd MMM yyyy').format(value);
}

String _dateTimeLabel(DateTime value) {
  return DateFormat('dd MMM yyyy, hh:mm a').format(value);
}
