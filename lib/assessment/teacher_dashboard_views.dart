import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../theme/theme_picker.dart';
import '../ui/student_portal_shell.dart';
import 'menu_wheel.dart';
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
    required this.onChangePassword,
    required this.onMarksLists,
    this.onAnswerSheets,
    this.onSlotCollection,
    this.onDataShare,
    this.trailing,
  });

  final TeacherDashboardHomeData data;
  final ValueChanged<TeacherCourseSummary> onOpenCourse;
  final VoidCallback onOpenNotifications;
  final Widget? trailing;
  final VoidCallback onOpenExamAttendance;
  final VoidCallback onOpenFyp;
  final VoidCallback onChangePassword;

  /// Opens the class- & quiz-wise marks lists built from scanned submissions.
  final VoidCallback onMarksLists;

  /// Set (non-null) only when the admin allowed this teacher to use the
  /// answer-sheet / marking tracker — then a panel for it is shown.
  final VoidCallback? onAnswerSheets;

  /// Set (non-null) only when the admin allowed this teacher to use the
  /// per-slot paper collection module.
  final VoidCallback? onSlotCollection;

  /// Opens the offline data-share (export/import a data bundle to/from another
  /// device). Available to teachers so invigilators can hand over collected data.
  final VoidCallback? onDataShare;

  @override
  Widget build(BuildContext context) {
    // One page, no scroll: a compact header + the wheel filling the rest.
    return Padding(
      padding: TeacherDashboardTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _HeroCard(
            title: 'Welcome, Teacher ${data.teacherName}',
            icon: Icons.co_present_outlined,
            trailing: const AppearanceButton(color: Colors.white),
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
          const SizedBox(height: 12),
          // Menu as a spinning wheel — flick to spin, or tap any item to open.
          Expanded(
            child: MenuWheel(
              items: [
              WheelItem(
                icon: Icons.notifications_outlined,
                label: 'Notifications',
                sub: '${data.unreadNotifications} unread',
                onTap: onOpenNotifications,
              ),
              WheelItem(
                icon: Icons.fact_check_outlined,
                label: 'Exam Attendance',
                sub: '${data.attendanceSheets} sheets',
                onTap: onOpenExamAttendance,
              ),
              WheelItem(
                icon: Icons.grading_outlined,
                label: 'Marks Lists',
                sub: 'Class & quiz-wise results',
                onTap: onMarksLists,
              ),
              WheelItem(
                icon: Icons.school_outlined,
                label: 'FYP Workspace',
                sub: 'Ideas, allocations, evaluations',
                onTap: onOpenFyp,
              ),
              if (onAnswerSheets != null)
                WheelItem(
                  icon: Icons.assignment_returned_outlined,
                  label: 'Answer Sheets',
                  sub: 'Issue / return envelopes',
                  onTap: onAnswerSheets!,
                ),
              if (onSlotCollection != null)
                WheelItem(
                  icon: Icons.fact_check_outlined,
                  label: 'Per-Slot Collection',
                  sub: 'Collect from invigilators',
                  onTap: onSlotCollection!,
                ),
              if (onDataShare != null)
                WheelItem(
                  icon: Icons.sync_alt_rounded,
                  label: 'Data Share',
                  sub: 'Offline send / receive',
                  onTap: onDataShare!,
                ),
              WheelItem(
                icon: Icons.password_outlined,
                label: 'Change Password',
                sub: 'Update login password',
                onTap: onChangePassword,
              ),
              ],
            ),
          ),
        ],
      ),
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
    required this.onHistory,
    required this.onExport,
    required this.onImport,
    required this.onSummary,
  });

  final ExamAttendanceDashboardData data;
  final VoidCallback onBack;
  final VoidCallback onScan;
  final VoidCallback onViewAttendance;
  final VoidCallback onShareAttendance;
  final VoidCallback onSharingStats;
  final VoidCallback onHistory;
  final VoidCallback onExport;
  final VoidCallback onImport;
  final VoidCallback onSummary;

  @override
  Widget build(BuildContext context) {
    // One page, no scroll: back + stats card, then the wheel fills the rest.
    return Padding(
      padding: TeacherDashboardTheme.pagePadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _BackButton(onPressed: onBack),
          const SizedBox(height: 10),
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
          const SizedBox(height: 12),
          Expanded(
            child: MenuWheel(
              items: [
            WheelItem(
              icon: Icons.qr_code_scanner_rounded,
              label: 'Scan & Mark',
              sub: 'Mark attendance',
              onTap: onScan,
            ),
            WheelItem(
              icon: Icons.calendar_month_outlined,
              label: 'Saved Stats',
              sub: 'Date-wise',
              onTap: onHistory,
            ),
            WheelItem(
              icon: Icons.edit_calendar_outlined,
              label: 'View / Edit',
              sub: 'Attendance',
              onTap: onViewAttendance,
            ),
            WheelItem(
              icon: Icons.ios_share_outlined,
              label: 'Share Stats',
              sub: 'Attendance stats',
              onTap: onShareAttendance,
            ),
            WheelItem(
              icon: Icons.swap_horiz_outlined,
              label: 'Shared / Accepted',
              sub: 'Stats',
              onTap: onSharingStats,
            ),
            WheelItem(
              icon: Icons.summarize_outlined,
              label: 'Summary',
              sub: 'Slot / program / hall',
              onTap: onSummary,
            ),
            WheelItem(
              icon: Icons.upload_file_outlined,
              label: 'Export',
              sub: 'For csexam',
              onTap: onExport,
            ),
            WheelItem(
              icon: Icons.download_for_offline_outlined,
              label: 'Import',
              sub: 'From another phone',
              onTap: onImport,
            ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class ExamQrScanView extends StatefulWidget {
  const ExamQrScanView({
    super.key,
    required this.onBack,
    required this.onQrDetected,
    this.errorMessage,
    this.scannedHalls = const [],
    this.onResumeHall,
  });

  final VoidCallback onBack;
  final ValueChanged<String> onQrDetected;
  final String? errorMessage;

  /// Already-scanned halls — tap one to RE-OPEN it (skeleton + marked kept) and
  /// keep marking the rest, without scanning the QR again.
  final List<ExamAttendanceSheetSummary> scannedHalls;
  final ValueChanged<ExamAttendanceSheetSummary>? onResumeHall;

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
          title: 'Step 1 — Scan the Hall QR',
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: PortalColors.softBlue,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'Scan the printed seating-plan HALL QR to open the hall. '
                  'On the next screen the camera stays on and you scan each '
                  "student's QR to mark them present — the rest are absent.",
                  style: TextStyle(
                    color: PortalColors.brandBlue,
                    fontWeight: FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 280,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _handleCapture,
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 190,
                            height: 190,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(
                                color: Colors.white,
                                width: 3,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 8,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(labelText: 'Hall QR text'),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitText,
                  icon: const Icon(Icons.meeting_room_outlined),
                  label: const Text('Open Hall & Start Scanning'),
                ),
              ),
              if (widget.errorMessage != null) ...[
                const SizedBox(height: 12),
                _ErrorText(widget.errorMessage!),
              ],
            ],
          ),
        ),
        if (widget.scannedHalls.isNotEmpty) ...[
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Resume a scanned hall (no re-scan)',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Already scanned? Tap a hall to re-open it — marked '
                  'attendance stays; just mark the remaining students.',
                  style: TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 10),
                for (final sheet in widget.scannedHalls)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(12),
                        onTap: () => widget.onResumeHall?.call(sheet),
                        child: Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: PortalColors.cardBorder),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.meeting_room_outlined,
                                  color: PortalColors.brandBlue),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      '${sheet.hallName} • ${sheet.courseName}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w800,
                                        color: PortalColors.textPrimary,
                                      ),
                                    ),
                                    Text(
                                      '${DateFormat('dd MMM').format(sheet.examDateTime)} • '
                                      '${sheet.examDateTime.hour >= 12 ? '2nd' : '1st'} shift  •  '
                                      '${sheet.presentCount} present / ${sheet.totalStudents}',
                                      style: const TextStyle(
                                        color: PortalColors.subtleText,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const Icon(Icons.chevron_right_rounded,
                                  color: PortalColors.subtleText),
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

/// One distinct colour per class/section sharing a hall. Kept in sync with the
/// live skeleton's palette so a class shows the same colour on both screens.
const List<Color> _hallClassPalette = [
  Color(0xFF2563EB),
  Color(0xFF7C3AED),
  Color(0xFF0D9488),
  Color(0xFFDB2777),
  Color(0xFFEA580C),
  Color(0xFF4F46E5),
  Color(0xFF0EA5E9),
  Color(0xFFCA8A04),
];

Color _hallClassColor(int index) =>
    _hallClassPalette[index % _hallClassPalette.length];

String _hallProgramCode(String value) {
  final match = RegExp(r'^[A-Za-z]+').firstMatch(value.trim());
  return (match?.group(0) ?? '').toUpperCase();
}

class HallStatsView extends StatelessWidget {
  const HallStatsView({
    super.key,
    required this.stats,
    required this.onBack,
    required this.onTakeAttendance,
    this.students = const [],
    this.onLiveScan,
    this.onSelectClass,
    this.onShare,
    this.onAccept,
  });

  final ExamHallStats stats;
  final List<ExamAttendanceStudent> students;
  final VoidCallback onBack;
  final VoidCallback onTakeAttendance;
  final VoidCallback? onLiveScan;
  final ValueChanged<ExamClassGroup>? onSelectClass;
  final VoidCallback? onShare;
  final VoidCallback? onAccept;

  /// Present count per class (indexed like [stats.classGroups]): exact
  /// class-group matches first, then by roll prefix + remaining capacity.
  List<int> _presentPerClass() {
    final groups = stats.classGroups;
    final result = List<int>.filled(groups.length, 0);
    final present = students
        .where((s) => s.status == 'present')
        .toList(growable: false);
    final leftover = <ExamAttendanceStudent>[];
    for (final student in present) {
      final idx = student.classGroup.isEmpty
          ? -1
          : groups.indexWhere((g) => g.program == student.classGroup);
      if (idx >= 0) {
        result[idx]++;
      } else {
        leftover.add(student);
      }
    }
    for (final student in leftover) {
      final code = _hallProgramCode(student.rollNo);
      for (var i = 0; i < groups.length; i++) {
        if (groups[i].code == code && result[i] < groups[i].count) {
          result[i]++;
          break;
        }
      }
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final hasClasses = stats.classGroups.isNotEmpty && onSelectClass != null;
    final presentPerClass = hasClasses ? _presentPerClass() : const <int>[];
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
        if (hasClasses) ...[
          const Text(
            'CLASSES IN THIS HALL',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
              color: PortalColors.subtleText,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Tap a class to scan its students one paper at a time.',
            style: TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
          ),
          const SizedBox(height: 10),
          for (var i = 0; i < stats.classGroups.length; i++)
            _ClassAttendanceCard(
              color: _hallClassColor(i),
              group: stats.classGroups[i],
              present: i < presentPerClass.length ? presentPerClass[i] : 0,
              onTap: () => onSelectClass!(stats.classGroups[i]),
            ),
          const SizedBox(height: 6),
        ] else if (onLiveScan != null) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onLiveScan,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Live Scan Attendance'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (onShare != null) ...[
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: onShare,
              icon: const Icon(Icons.ios_share_outlined),
              label: const Text('Share attendance (QR / text)'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        if (onAccept != null) ...[
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAccept,
              icon: const Icon(Icons.qr_code_scanner_rounded),
              label: const Text('Accept attendance from another teacher'),
            ),
          ),
          const SizedBox(height: 10),
        ],
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: onTakeAttendance,
            icon: const Icon(Icons.how_to_reg_outlined),
            label: const Text('Manual Attendance List'),
          ),
        ),
      ],
    );
  }
}

/// One class card on the hall-stats screen: shows the class, its faculty and a
/// done/total counter, colour-coded, tappable to take that class's attendance.
class _ClassAttendanceCard extends StatelessWidget {
  const _ClassAttendanceCard({
    required this.color,
    required this.group,
    required this.present,
    required this.onTap,
  });

  final Color color;
  final ExamClassGroup group;
  final int present;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final total = group.count;
    final remaining = total - present > 0 ? total - present : 0;
    final done = total > 0 && present >= total;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: color.withValues(alpha: 0.45)),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.event_seat_outlined, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        group.program,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (group.subject.isNotEmpty) group.subject,
                          if (group.faculty.isNotEmpty) group.faculty,
                        ].join('  •  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        done
                            ? 'All $total marked present'
                            : 'Present $present / $total   •   $remaining remaining',
                        style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: done
                        ? const Color(0xFFD1FAE5)
                        : color.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        done
                            ? Icons.check_circle_rounded
                            : Icons.arrow_forward_rounded,
                        size: 16,
                        color: done ? const Color(0xFF047857) : color,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        done ? 'Done' : 'Scan',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: done ? const Color(0xFF047857) : color,
                        ),
                      ),
                    ],
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

/// Share an attendance sheet — whole hall OR one class (programwise) — as both
/// a scannable QR and copyable text. The other teacher accepts it on their
/// phone via [AcceptAttendanceView].
class HallShareView extends StatefulWidget {
  const HallShareView({
    super.key,
    required this.stats,
    required this.onLoad,
    required this.onRecordShared,
    required this.onBack,
  });

  final ExamHallStats stats;
  final Future<AttendanceShareData> Function(String classGroup) onLoad;
  final Future<void> Function(String classGroup) onRecordShared;
  final VoidCallback onBack;

  @override
  State<HallShareView> createState() => _HallShareViewState();
}

class _HallShareViewState extends State<HallShareView> {
  String _scope = ''; // '' = whole hall, else a class program
  AttendanceShareData? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    setState(() => _loading = true);
    final data = await widget.onLoad(_scope);
    if (!mounted) return;
    setState(() {
      _data = data;
      _loading = false;
    });
  }

  void _selectScope(String scope) {
    if (_scope == scope) return;
    setState(() => _scope = scope);
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final data = _data;
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Share attendance',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Choose what to share, then let the other teacher scan the QR '
                '(or send the text). Same data, two ways.',
                style: TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('Whole hall'),
                    selected: _scope.isEmpty,
                    onSelected: (_) => _selectScope(''),
                  ),
                  for (final group in widget.stats.classGroups)
                    ChoiceChip(
                      label: Text(group.program),
                      selected: _scope == group.program,
                      onSelected: (_) => _selectScope(group.program),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (_loading || data == null)
          const Padding(
            padding: EdgeInsets.all(40),
            child: Center(child: CircularProgressIndicator()),
          )
        else ...[
          _SectionCard(
            title: data.scopeLabel,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _ShareStat(label: 'Total', value: '${data.total}'),
                    _ShareStat(
                      label: 'Present',
                      value: '${data.present}',
                      color: const Color(0xFF047857),
                    ),
                    _ShareStat(
                      label: 'Absent',
                      value: '${data.absent}',
                      color: const Color(0xFFB91C1C),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: PortalColors.cardBorder),
                    ),
                    child: QrImageView(
                      data: data.qrPayload,
                      version: QrVersions.auto,
                      size: 240,
                      gapless: false,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                const Center(
                  child: Text(
                    'Scan this on the other phone — Exam → Accept Attendance.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                      child: FilledButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: data.text),
                          );
                          await widget.onRecordShared(_scope);
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Attendance text copied & logged.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.copy_rounded, size: 18),
                        label: const Text('Copy text'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () async {
                          await Clipboard.setData(
                            ClipboardData(text: data.qrPayload),
                          );
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('QR payload copied.'),
                            ),
                          );
                        },
                        icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                        label: const Text('Copy QR code'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Text summary',
            child: SelectableText(
              data.text,
              style: const TextStyle(fontSize: 12.5, height: 1.4),
            ),
          ),
        ],
      ],
    );
  }
}

class _ShareStat extends StatelessWidget {
  const _ShareStat({
    required this.label,
    required this.value,
    this.color = PortalColors.textPrimary,
  });

  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            fontSize: 22,
            fontWeight: FontWeight.w900,
            color: color,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            color: PortalColors.subtleText,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

/// Accept an attendance transfer from another teacher — scan their QR or paste
/// the `CSEXAM|QATTN|1|…` text.
class AcceptAttendanceView extends StatefulWidget {
  const AcceptAttendanceView({
    super.key,
    required this.onAccept,
    required this.onBack,
  });

  /// Decodes + stores the payload; returns a confirmation message or throws.
  final Future<String> Function(String rawPayload) onAccept;
  final VoidCallback onBack;

  @override
  State<AcceptAttendanceView> createState() => _AcceptAttendanceViewState();
}

class _AcceptAttendanceViewState extends State<AcceptAttendanceView> {
  final _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _textController = TextEditingController();
  bool _handled = false;
  String? _message;
  bool _ok = true;

  @override
  void dispose() {
    _controller.dispose();
    _textController.dispose();
    super.dispose();
  }

  Future<void> _accept(String raw) async {
    final payload = raw.trim();
    if (payload.isEmpty) return;
    try {
      final summary = await widget.onAccept(payload);
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = summary;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _message = error is FormatException ? error.message : error.toString();
        _handled = false; // allow another scan after a failure
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    _accept(raw);
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Accept attendance',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Scan the share QR from the other phone, or paste the QR text '
                'below.',
                style: TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(18),
                child: SizedBox(
                  height: 260,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      MobileScanner(
                        controller: _controller,
                        onDetect: _onDetect,
                      ),
                      IgnorePointer(
                        child: Center(
                          child: Container(
                            width: 180,
                            height: 180,
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: Colors.white, width: 3),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _textController,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(
                  labelText: 'Paste attendance QR text',
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => _accept(_textController.text),
                icon: const Icon(Icons.download_done_rounded),
                label: const Text('Accept pasted text'),
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
    );
  }
}

/// Exports every hall's attendance (date + shift + hall + program) to one JSON
/// file that the desktop csexam app imports for the master record.
class ExportRecordView extends StatefulWidget {
  const ExportRecordView({
    super.key,
    required this.buildJson,
    required this.onBack,
  });

  final Future<String> Function() buildJson;
  final VoidCallback onBack;

  @override
  State<ExportRecordView> createState() => _ExportRecordViewState();
}

class _ExportRecordViewState extends State<ExportRecordView> {
  String? _json;
  int _sessions = 0;
  bool _loading = true;
  String? _message;
  bool _ok = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final json = await widget.buildJson();
    var count = 0;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map && decoded['sessionCount'] is int) {
        count = decoded['sessionCount'] as int;
      }
    } catch (_) {}
    if (!mounted) return;
    setState(() {
      _json = json;
      _sessions = count;
      _loading = false;
    });
  }

  Future<void> _saveFile() async {
    final json = _json;
    if (json == null) return;
    final bytes = Uint8List.fromList(utf8.encode(json));
    final stamp = DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
    try {
      // Saved as .txt (not .json): WhatsApp and most chat apps reject/error on
      // .json uploads but send .txt documents fine. csexam imports it anyway
      // (it reads the content, not the extension).
      final path = await FilePicker.platform.saveFile(
        dialogTitle: 'Save attendance record for csexam',
        fileName: 'aust_attendance_$stamp.txt',
        bytes: bytes,
      );
      if (path == null) {
        _flash('Save cancelled.', ok: false);
        return;
      }
      // On desktop file_picker returns the path without writing — ensure the
      // bytes land on disk. On mobile it already wrote them.
      try {
        final f = File(path);
        if (!await f.exists() || (await f.length()) == 0) {
          await f.writeAsBytes(bytes);
        }
      } catch (_) {}
      _flash('Saved: $path', ok: true);
    } catch (error) {
      _flash('Could not save file: $error', ok: false);
    }
  }

  /// The most reliable transfer: write a real file, then hand it to the OS
  /// share sheet so WhatsApp/Drive/Email receive it directly (no manual
  /// "attach document", which is what was erroring).
  Future<void> _shareFile() async {
    final json = _json;
    if (json == null) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final stamp =
          DateTime.now().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');
      final file = File('${dir.path}/aust_attendance_$stamp.txt');
      await file.writeAsString(json, flush: true);
      await Share.shareXFiles(
        [XFile(file.path, mimeType: 'text/plain')],
        subject: 'AUST attendance record',
        text: 'AUST attendance export — open in csexam → Import Attendance.',
      );
      _flash('Shared: ${file.path.split('/').last}', ok: true);
    } catch (error) {
      _flash('Could not share: $error', ok: false);
    }
  }

  void _flash(String msg, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: 'Export for csexam',
          icon: Icons.upload_file_outlined,
          children: [
            _MetricTile(
              icon: Icons.list_alt_outlined,
              label: 'Sessions',
              value: '$_sessions',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Master record file',
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      'This saves ALL halls on this device — date-wise, '
                      'shift-wise, hall-wise and program-wise — into one '
                      '.txt file (WhatsApp-friendly). Send/move it to the PC '
                      'and open it in csexam → Import Attendance for the '
                      'official record.',
                      style: TextStyle(
                        color: PortalColors.subtleText,
                        fontSize: 12.5,
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: _sessions == 0 ? null : _shareFile,
                      icon: const Icon(Icons.share_rounded),
                      label: const Text('Share file (WhatsApp / Drive / Email)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _sessions == 0 ? null : _saveFile,
                      icon: const Icon(Icons.save_alt_rounded),
                      label: const Text('Save as file (.txt)'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton.icon(
                      onPressed: _json == null
                          ? null
                          : () async {
                              await Clipboard.setData(
                                ClipboardData(text: _json!),
                              );
                              _flash('JSON copied to clipboard.', ok: true);
                            },
                      icon: const Icon(Icons.copy_rounded),
                      label: const Text('Copy JSON (backup)'),
                    ),
                    if (_sessions == 0) ...[
                      const SizedBox(height: 10),
                      const Text(
                        'No attendance on this device yet.',
                        style: TextStyle(color: PortalColors.subtleText),
                      ),
                    ],
                    if (_message != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: _ok
                              ? const Color(0xFFD1FAE5)
                              : const Color(0xFFFEE2E2),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: SelectableText(
                          _message!,
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
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
    );
  }
}

/// Receives the `attendance_export` .txt from ANOTHER phone (sent via
/// WhatsApp / Bluetooth / Nearby / Drive) and merges it into this device's
/// Saved Stats — the phone-to-phone counterpart of the csexam file import.
class ImportRecordView extends StatefulWidget {
  const ImportRecordView({
    super.key,
    required this.onImport,
    required this.onBack,
  });

  final Future<AttendanceImportSummary> Function(String jsonText) onImport;
  final VoidCallback onBack;

  @override
  State<ImportRecordView> createState() => _ImportRecordViewState();
}

class _ImportRecordViewState extends State<ImportRecordView> {
  final _pasteController = TextEditingController();
  bool _busy = false;
  String? _message;
  bool _ok = true;

  @override
  void dispose() {
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    try {
      final res = await FilePicker.platform.pickFiles(
        dialogTitle: 'Pick the attendance file (.txt) from the other phone',
        type: FileType.custom,
        allowedExtensions: const ['txt', 'json'],
        withData: true,
      );
      if (res == null || res.files.isEmpty) return;
      final f = res.files.first;
      String text;
      if (f.bytes != null) {
        text = utf8.decode(f.bytes!);
      } else if (f.path != null) {
        text = await File(f.path!).readAsString();
      } else {
        _flash('Could not read the file.', ok: false);
        return;
      }
      await _run(text);
    } catch (error) {
      _flash('Import failed: $error', ok: false);
    }
  }

  Future<void> _run(String text) async {
    if (_busy) return;
    if (text.trim().isEmpty) {
      _flash(
        'Nothing to import. Open the .txt file, or paste its contents first.',
        ok: false,
      );
      return;
    }
    setState(() => _busy = true);
    try {
      final s = await widget.onImport(text);
      _flash(
        'Imported ${s.sessions} hall session(s) — '
        'Present ${s.present}, Absent ${s.absent}, UFM ${s.ufm}. '
        'Open Saved Stats / Summary to see the merged data.',
        ok: true,
      );
    } catch (error) {
      _flash('Import failed: $error', ok: false);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _flash(String msg, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _message = msg;
      _ok = ok;
    });
  }

  @override
  Widget build(BuildContext context) {
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: 'Import from another phone',
          icon: Icons.download_for_offline_outlined,
          children: const [
            _MetricTile(
              icon: Icons.merge_type_rounded,
              label: 'Mode',
              value: 'Merge',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: 'Receive attendance file',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'On the OTHER phone: Exam Attendance → "Export for csexam" → '
                'Share file, and send it here (WhatsApp / Bluetooth / Nearby '
                'Share / Drive). Then open that .txt below — every hall merges '
                'into your Saved Stats (present always wins, UFM included).',
                style: TextStyle(
                  color: PortalColors.subtleText,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _busy ? null : _pickFile,
                icon: const Icon(Icons.folder_open_rounded),
                label: const Text('Open attendance file (.txt)'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _pasteController,
                minLines: 1,
                maxLines: 3,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  border: OutlineInputBorder(),
                  hintText: 'Or paste the exported text here…',
                ),
              ),
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: _busy ? null : () => _run(_pasteController.text),
                icon: const Icon(Icons.content_paste_go_rounded),
                label: const Text('Import pasted text'),
              ),
              if (_busy) ...[
                const SizedBox(height: 12),
                const Center(child: CircularProgressIndicator()),
              ],
              if (_message != null) ...[
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: _ok
                        ? const Color(0xFFD1FAE5)
                        : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: SelectableText(
                    _message!,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12,
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

  /// Students grouped by program, each list ordered ABSENT first then present.
  Map<String, List<ExamAttendanceStudent>> _byProgram() {
    final groups = <String, List<ExamAttendanceStudent>>{};
    for (final s in widget.detail.students) {
      final key = s.classGroup.trim().isEmpty
          ? widget.detail.stats.courseName
          : s.classGroup.trim();
      groups.putIfAbsent(key, () => []).add(s);
    }
    for (final list in groups.values) {
      list.sort((a, b) {
        final aPresent = _statuses[a.studentId] == 'present' ? 1 : 0;
        final bPresent = _statuses[b.studentId] == 'present' ? 1 : 0;
        if (aPresent != bPresent) return aPresent - bPresent; // absent first
        return a.rollNo.toLowerCase().compareTo(b.rollNo.toLowerCase());
      });
    }
    return groups;
  }

  @override
  Widget build(BuildContext context) {
    final present = _statuses.values
        .where((status) => status == 'present')
        .length;
    final absent = _statuses.values
        .where((status) => status != 'present')
        .length;
    final groups = _byProgram();
    final programNames = groups.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
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
        const SizedBox(height: 12),
        if (widget.detail.students.isNotEmpty)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _confirmClearAll,
              style: TextButton.styleFrom(
                foregroundColor: const Color(0xFFB91C1C),
              ),
              icon: const Icon(Icons.clear_all_rounded, size: 18),
              label: const Text('Clear all'),
            ),
          ),
        if (widget.detail.students.isEmpty)
          const _SectionCard(
            title: 'Students',
            child: _EmptyState('No students found.'),
          )
        else
          for (final program in programNames) ...[
            Builder(
              builder: (context) {
                final list = groups[program]!;
                final p = list
                    .where((s) => _statuses[s.studentId] == 'present')
                    .length;
                final a = list.length - p;
                return _SectionCard(
                  // Programwise: program name + its own present/absent summary.
                  title: '$program   •   ${list.length} students',
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _MiniCount('Absent', a, const Color(0xFFB91C1C)),
                          const SizedBox(width: 8),
                          _MiniCount('Present', p, const Color(0xFF047857)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Absent students first, then present.
                      for (final student in list)
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
                );
              },
            ),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 4),
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

  Future<void> _confirmClearAll() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all attendance?'),
        content: const Text(
          'Are you sure you want to clear everything? Every student in this '
          'sheet will be reset to ABSENT. This cannot be undone after saving.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) {
      return;
    }
    setState(() {
      _statuses = {
        for (final student in widget.detail.students)
          student.studentId: 'absent',
      };
    });
  }
}

class _MiniCount extends StatelessWidget {
  const _MiniCount(this.label, this.value, this.color);

  final String label;
  final int value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
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

/// All saved attendance sessions grouped by exam DATE (newest first). The data
/// lives in the device's local sqflite DB, so it persists across app restarts.
class AttendanceHistoryView extends StatelessWidget {
  const AttendanceHistoryView({
    super.key,
    required this.sheets,
    required this.onBack,
    required this.onOpenSheet,
    required this.onDelete,
  });

  final List<ExamAttendanceSheetSummary> sheets;
  final VoidCallback onBack;
  final ValueChanged<ExamAttendanceSheetSummary> onOpenSheet;

  /// Deletes a saved attendance session (after a confirmation warning).
  final Future<void> Function(ExamAttendanceSheetSummary sheet) onDelete;

  Future<void> _confirmDelete(
    BuildContext context,
    ExamAttendanceSheetSummary sheet,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this saved attendance?'),
        content: Text(
          '${sheet.hallName} • ${sheet.courseName}\n'
          'Present ${sheet.presentCount} / Total ${sheet.totalStudents}\n\n'
          'This permanently removes this saved session (and its UFM cases) '
          'from this device. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFB91C1C),
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (yes == true) {
      await onDelete(sheet);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Group by exam date.
    final byDate = <DateTime, List<ExamAttendanceSheetSummary>>{};
    for (final sheet in sheets) {
      final d = DateTime(
        sheet.examDateTime.year,
        sheet.examDateTime.month,
        sheet.examDateTime.day,
      );
      byDate.putIfAbsent(d, () => []).add(sheet);
    }
    final dates = byDate.keys.toList()..sort((a, b) => b.compareTo(a));

    return _DashboardList(
      children: [
        _BackButton(onPressed: onBack),
        const SizedBox(height: 12),
        _HeroCard(
          title: 'Saved Stats',
          icon: Icons.calendar_month_outlined,
          children: [
            _MetricTile(
              icon: Icons.event_note_outlined,
              label: 'Days',
              value: '${dates.length}',
            ),
            _MetricTile(
              icon: Icons.list_alt_outlined,
              label: 'Sessions',
              value: '${sheets.length}',
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (sheets.isEmpty)
          const _SectionCard(
            title: 'Attendance history',
            child: _EmptyState('No saved attendance yet.'),
          )
        else
          for (final date in dates) ...[
            Padding(
              padding: const EdgeInsets.only(left: 4, top: 6, bottom: 8),
              child: Text(
                DateFormat('EEEE, dd MMM yyyy').format(date),
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                  color: PortalColors.textPrimary,
                ),
              ),
            ),
            for (final sheet in byDate[date]!)
              _HistorySessionTile(
                sheet: sheet,
                onTap: () => onOpenSheet(sheet),
                onDelete: () => _confirmDelete(context, sheet),
              ),
            const SizedBox(height: 8),
          ],
      ],
    );
  }
}

class _HistorySessionTile extends StatelessWidget {
  const _HistorySessionTile({
    required this.sheet,
    required this.onTap,
    required this.onDelete,
  });

  final ExamAttendanceSheetSummary sheet;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: PortalColors.softBlue,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.meeting_room_outlined,
                    color: PortalColors.brandBlue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${sheet.hallName} • ${sheet.courseName}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Wrap(
                        spacing: 8,
                        children: [
                          _miniStat('Present', sheet.presentCount,
                              const Color(0xFF047857)),
                          _miniStat('Absent', sheet.absentCount,
                              const Color(0xFFB91C1C)),
                          _miniStat('Total', sheet.totalStudents,
                              PortalColors.subtleText),
                        ],
                      ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: 'Delete saved attendance',
                  onPressed: onDelete,
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: const Color(0xFFB91C1C),
                ),
                const Icon(Icons.chevron_right_rounded,
                    color: PortalColors.subtleText),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _miniStat(String label, int value, Color color) {
    return Text(
      '$label $value',
      style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: color),
    );
  }
}

class ShareAttendanceView extends StatefulWidget {
  const ShareAttendanceView({
    super.key,
    required this.sheets,
    required this.onBack,
    required this.onShare,
    required this.onLoadShare,
    required this.onAccept,
  });

  /// Sheets are ordered latest-first (by last update), so the first entry is
  /// the default selection when transferring.
  final List<ExamAttendanceSheetSummary> sheets;
  final VoidCallback onBack;
  final ValueChanged<ExamAttendanceSheetSummary> onShare;

  /// Loads the share payload (QR + text + counts) for the selected sheet
  /// (whole hall).
  final Future<AttendanceShareData> Function(String sheetId) onLoadShare;

  /// Opens the "Accept attendance from another teacher" scanner.
  final VoidCallback onAccept;

  @override
  State<ShareAttendanceView> createState() => _ShareAttendanceViewState();
}

class _ShareAttendanceViewState extends State<ShareAttendanceView> {
  String? _selectedSheetId;

  ExamAttendanceSheetSummary? get _selectedSheet {
    if (widget.sheets.isEmpty) {
      return null;
    }
    return widget.sheets.firstWhere(
      (sheet) => sheet.sheetId == _selectedSheetId,
      orElse: () => widget.sheets.first,
    );
  }

  @override
  Widget build(BuildContext context) {
    final selected = _selectedSheet;
    return _DashboardList(
      children: [
        _BackButton(onPressed: widget.onBack),
        const SizedBox(height: 12),
        _SectionCard(
          title: 'Share Attendance Stats',
          child: widget.sheets.isEmpty
              ? const _EmptyState('No attendance found.')
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: selected?.sheetId,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Attendance sheet (latest selected)',
                        prefixIcon: Icon(Icons.fact_check_outlined),
                      ),
                      items: [
                        for (final sheet in widget.sheets)
                          DropdownMenuItem(
                            value: sheet.sheetId,
                            child: Text(
                              '${sheet.courseName} • ${sheet.hallName} • '
                              '${_shortDate(sheet.examDateTime)}',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                      ],
                      onChanged: (value) =>
                          setState(() => _selectedSheetId = value),
                    ),
                    if (selected != null) ...[
                      const SizedBox(height: 12),
                      _AttendanceSheetTile(
                        sheet: selected,
                        onTap: () => widget.onShare(selected),
                      ),
                    ],
                  ],
                ),
        ),
        if (selected != null) ...[
          const SizedBox(height: 16),
          // Via QR code: load the selected sheet's payload and show the QR so
          // the other phone can scan it (same data as the text/transfer).
          FutureBuilder<AttendanceShareData>(
            key: ValueKey(selected.sheetId),
            future: widget.onLoadShare(selected.sheetId),
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return _SectionCard(
                  title: 'Share via QR',
                  child: _EmptyState(snapshot.error.toString()),
                );
              }
              if (!snapshot.hasData) {
                return const Padding(
                  padding: EdgeInsets.all(32),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              final data = snapshot.data!;
              return _SectionCard(
                title: 'Share via QR code',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _ShareStat(label: 'Total', value: '${data.total}'),
                        _ShareStat(
                          label: 'Present',
                          value: '${data.present}',
                          color: const Color(0xFF047857),
                        ),
                        _ShareStat(
                          label: 'Absent',
                          value: '${data.absent}',
                          color: const Color(0xFFB91C1C),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: PortalColors.cardBorder),
                        ),
                        child: QrImageView(
                          data: data.qrPayload,
                          version: QrVersions.auto,
                          size: 240,
                          gapless: false,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Center(
                      child: Text(
                        'Scan this on the other phone — Exam → Accept '
                        'Attendance.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    FilledButton.icon(
                      onPressed: () => widget.onShare(selected),
                      icon: const Icon(Icons.ios_share_outlined),
                      label: const Text('Share / Transfer (file)'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: data.text),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Attendance text copied.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, size: 18),
                            label: const Text('Copy text'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: () async {
                              await Clipboard.setData(
                                ClipboardData(text: data.qrPayload),
                              );
                              if (!context.mounted) return;
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('QR payload copied.'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.qr_code_2_rounded, size: 18),
                            label: const Text('Copy QR'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          _SectionCard(
            title: 'Receive from another teacher',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Scan another teacher\'s attendance QR to merge their hall '
                  'into yours.',
                  style: TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: widget.onAccept,
                  icon: const Icon(Icons.qr_code_scanner_rounded),
                  label: const Text('Accept attendance from another teacher'),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  String _shortDate(DateTime value) {
    return '${value.day}/${value.month}/${value.year}';
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

// Kept for reuse (the Exam Attendance grid became a wheel).
// ignore: unused_element
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
      width: double.infinity,
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
  const _AttendanceSheetTile({required this.sheet, required this.onTap});

  final ExamAttendanceSheetSummary sheet;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return _ClickableTile(
      icon: Icons.fact_check_outlined,
      title: sheet.courseName,
      subtitle:
          '${sheet.hallName}  |  ${_dateTimeLabel(sheet.examDateTime)}  |  Updated ${_dateTimeLabel(sheet.lastUpdatedAt)}',
      trailing: Wrap(
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
    return GestureDetector(
      onTap: sheet.payload.isEmpty ? null : () => _showDetails(context),
      child: _PlainTile(
        icon: Icons.ios_share_outlined,
        title: sheet.courseName,
        subtitle:
            '${sheet.hallName}  |  ${_dateTimeLabel(sheet.examDateTime)}  |  ${sheet.sharedWith}  |  ${_dateTimeLabel(sheet.sharedAt)}  |  ${sheet.status}'
            '${sheet.payload.isEmpty ? '' : '  |  Tap for details'}',
      ),
    );
  }

  /// Full shared record: present/absent rolls with seats + UFM cases.
  void _showDetails(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('${sheet.courseName} — shared details'),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: SelectableText(
              sheet.payload,
              style: const TextStyle(fontSize: 13, height: 1.45),
            ),
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: sheet.payload));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(
                  const SnackBar(content: Text('Details copied.')),
                );
              }
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copy'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
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
    this.trailing,
  });

  final String title;
  final IconData icon;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(TeacherDashboardTheme.cardRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.16),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
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
              if (trailing != null) trailing!,
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
