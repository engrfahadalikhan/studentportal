import 'dart:async';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/student_record.dart';
import '../data/local_student_enrollments.dart';
import '../services/app_repository.dart';
import '../services/local_exam_client.dart';
import '../services/login_store.dart';
import 'registration_course_data.dart' as registration;
import '../ui/student_portal_shell.dart';
import 'package:qr_flutter/qr_flutter.dart';

import 'assessment_lockdown_controller.dart';
import 'assessment_models.dart';
import 'assessment_qr_codec.dart';
import 'submission_qr_codec.dart';

enum _StudentAssessmentStage {
  scan,
  verify,
  rules,
  attempt,
  assignmentSubmit,
  submitted,
  error,
}

enum StudentAssessmentError {
  invalidQr,
  expiredQr,
  notStarted,
  notEnrolled,
  alreadySubmitted,
  networkDisconnected,
  duplicateLogin,
  teacherLocked,
  timeExpired,
}

extension _StudentAssessmentErrorX on StudentAssessmentError {
  String get title {
    switch (this) {
      case StudentAssessmentError.invalidQr:
        return 'Invalid QR Code';
      case StudentAssessmentError.expiredQr:
        return 'QR Code Expired';
      case StudentAssessmentError.notStarted:
        return 'Assessment Not Started';
      case StudentAssessmentError.notEnrolled:
        return 'Not Enrolled';
      case StudentAssessmentError.alreadySubmitted:
        return 'Already Submitted';
      case StudentAssessmentError.networkDisconnected:
        return 'Network Disconnected';
      case StudentAssessmentError.duplicateLogin:
        return 'Duplicate Login Detected';
      case StudentAssessmentError.teacherLocked:
        return 'Teacher Locked Attempt';
      case StudentAssessmentError.timeExpired:
        return 'Time Expired';
    }
  }

  String get message {
    switch (this) {
      case StudentAssessmentError.invalidQr:
        return 'The assessment code is not valid. Scan the QR shown by your teacher or enter the exact code.';
      case StudentAssessmentError.expiredQr:
        return 'This QR code is no longer active. Ask your teacher to generate a fresh code.';
      case StudentAssessmentError.notStarted:
        return 'Your teacher has not started this assessment yet.';
      case StudentAssessmentError.notEnrolled:
        return 'This assessment is for a different program, semester, or section. '
            'You are not enrolled in the class this paper was created for.';
      case StudentAssessmentError.alreadySubmitted:
        return 'This student attempt has already been submitted.';
      case StudentAssessmentError.networkDisconnected:
        return 'The device appears offline. Reconnect before starting the attempt.';
      case StudentAssessmentError.duplicateLogin:
        return 'This roll number is already active on another device.';
      case StudentAssessmentError.teacherLocked:
        return 'The teacher has locked this attempt from the monitoring dashboard.';
      case StudentAssessmentError.timeExpired:
        return 'The timer reached zero and the attempt was auto-submitted.';
    }
  }
}

class StudentAssessmentFlow extends StatefulWidget {
  const StudentAssessmentFlow({
    super.key,
    required this.repository,
    required this.student,
  });

  final AppRepository repository;
  final StudentRecord student;

  @override
  State<StudentAssessmentFlow> createState() => _StudentAssessmentFlowState();
}

class _StudentAssessmentFlowState extends State<StudentAssessmentFlow> {
  final _codeController = TextEditingController(
    text: 'ASSESS_A001_C001_S26_3A',
  );
  _StudentAssessmentStage _stage = _StudentAssessmentStage.scan;
  Assessment? _assessment;
  VerificationRequest? _verification;
  StudentAssessmentError _error = StudentAssessmentError.invalidQr;
  int _lastWarningCount = 0;
  bool _autoSubmitted = false;

  /// Set when the student joined via the teacher's local WiFi host (instead of
  /// a QR). On submit, the answer is uploaded back to this address.
  String? _joinedServerUrl;

  // Admin-approved override for a student whose roll / section data is wrong:
  // the admin approves at runtime and the student re-enters roll + semester +
  // section, which then identify the submission.
  String? _ovRoll;
  String? _ovSemester;
  String? _ovSection;
  Assessment? _pendingApprovalAssessment;

  AssessmentStudent get _student {
    final roll = (_ovRoll ?? widget.student.rollNo);
    return AssessmentStudent(
      id: roll.isEmpty ? 'firebase-student' : roll,
      name: widget.student.studentName.isEmpty
          ? (roll.isEmpty ? 'Student' : roll)
          : widget.student.studentName,
      studentId: roll,
      program: widget.student.program,
      session: widget.student.currentSession.isEmpty
          ? 'S26'
          : widget.student.currentSession,
      semester: _ovSemester ?? widget.student.semester,
      section: _ovSection ?? widget.student.section,
      email: '$roll@student.local',
    );
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.repository,
      builder: (context, _) {
        return switch (_stage) {
          _StudentAssessmentStage.scan => _ScanScreen(
            controller: _codeController,
            repository: widget.repository,
            student: _student,
            onVerify: _verifyCode,
            onScanned: _handleScannedRaw,
            onPreviewError: _showError,
            onJoinWifi: _promptJoinWifi,
          ),
          _StudentAssessmentStage.verify => _VerifyScreen(
            assessment: _assessment!,
            student: _student,
            verification: _verification,
            onRequest: _requestVerification,
            onRefresh: _refreshVerification,
            onDemoApprove: _demoApprove,
            onBack: () => setState(() => _stage = _StudentAssessmentStage.scan),
            onContinue: () => setState(() {
              _stage = _StudentAssessmentStage.rules;
            }),
          ),
          _StudentAssessmentStage.rules => _RulesScreen(
            assessment: _assessment!,
            student: _student,
            onBack: () =>
                setState(() => _stage = _StudentAssessmentStage.scan),
            onStart: () =>
                setState(() => _stage = _StudentAssessmentStage.attempt),
          ),
          _StudentAssessmentStage.attempt => _LockedAssessmentScreen(
            key: ValueKey(_assessment!.id),
            assessment: _assessment!,
            student: _student,
            repository: widget.repository,
            onSubmitted: (warningCount, autoSubmitted) {
              setState(() {
                _lastWarningCount = warningCount;
                _autoSubmitted = autoSubmitted;
                _stage = _StudentAssessmentStage.submitted;
              });
            },
          ),
          _StudentAssessmentStage.assignmentSubmit => _AssignmentSubmitScreen(
            assessment: _assessment!,
            student: _student,
            repository: widget.repository,
            onBack: () =>
                setState(() => _stage = _StudentAssessmentStage.scan),
            onSubmitted: () {
              setState(() {
                _lastWarningCount = 0;
                _autoSubmitted = false;
                _stage = _StudentAssessmentStage.submitted;
              });
            },
          ),
          _StudentAssessmentStage.submitted => _SubmittedScreen(
            assessment: _assessment!,
            student: _student,
            repository: widget.repository,
            warningCount: _lastWarningCount,
            autoSubmitted: _autoSubmitted,
            onHome: _reset,
            serverUrl: _joinedServerUrl,
          ),
          _StudentAssessmentStage.error => _AssessmentErrorScreen(
            error: _error,
            onBack: () => setState(() => _stage = _StudentAssessmentStage.scan),
            onAdminApprove:
                (_error == StudentAssessmentError.notEnrolled &&
                    _pendingApprovalAssessment != null)
                ? _adminApprovedEntry
                : null,
          ),
        };
      },
    );
  }

  /// Handles a raw value coming from the camera or the transfer field. If it
  /// is an offline AUST question-paper QR, decode the whole paper locally and
  /// import it (no internet). Otherwise treat it as a plain assessment code.
  void _handleScannedRaw(String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return;
    }
    // A scanned host address (the teacher's "Host on WiFi" QR) → join over WiFi.
    if (value.startsWith('http://') || value.startsWith('https://')) {
      unawaited(_joinViaWifi(value));
      return;
    }
    if (AssessmentQrCodec.looksLikeAssessmentQr(value)) {
      try {
        final decoded = AssessmentQrCodec.decode(value);
        final imported = widget.repository.importSharedAssessment(decoded);
        _codeController.text = imported.qrCode;
      } on FormatException {
        _showError(StudentAssessmentError.invalidQr);
        return;
      } catch (_) {
        _showError(StudentAssessmentError.invalidQr);
        return;
      }
    } else {
      _codeController.text = value;
    }
    _verifyCode();
  }

  /// Asks the student for the teacher host address, then joins over WiFi.
  Future<void> _promptJoinWifi() async {
    final ctrl = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Join teacher\'s WiFi exam'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Enter the address shown on the teacher\'s phone (or close this '
              'and scan its QR with the camera).',
              style: TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(
                hintText: 'http://192.168.x.x:8080',
                prefixIcon: Icon(Icons.wifi_rounded),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, ctrl.text.trim()),
            child: const Text('Connect'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    if (url != null && url.isNotEmpty) {
      await _joinViaWifi(url);
    }
  }

  /// Downloads the quiz from the teacher host on the local WiFi and proceeds
  /// through the same eligibility / rules flow as a scanned QR.
  Future<void> _joinViaWifi(String url) async {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );
    try {
      final quiz = await LocalExamClient.fetchQuiz(url);
      final imported = widget.repository.importSharedAssessment(quiz);
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop(); // close spinner
      _joinedServerUrl = LocalExamClient.normalize(url);
      _codeController.text = imported.qrCode;
      _verifyCode();
    } catch (_) {
      if (!mounted) return;
      Navigator.of(context, rootNavigator: true).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Could not connect to the teacher. Check you are on the same WiFi '
            'and the address is correct.',
          ),
        ),
      );
    }
  }

  void _verifyCode() {
    final assessment = widget.repository.assessmentByCode(_codeController.text);
    if (assessment == null) {
      _showError(StudentAssessmentError.invalidQr);
      return;
    }
    if (assessment.status == AssessmentStatus.draft) {
      _showError(StudentAssessmentError.notStarted);
      return;
    }
    if (assessment.status == AssessmentStatus.completed) {
      _showError(StudentAssessmentError.expiredQr);
      return;
    }

    // Enrollment check: the student must be in the program/semester/section
    // this assessment was created for. This prevents students from other
    // sections scanning a paper meant for a different class.
    if (!_isStudentEnrolled(assessment)) {
      // Keep the paper so the student can get admin approval at runtime and
      // re-enter their roll / semester / section.
      _pendingApprovalAssessment = assessment;
      _showError(StudentAssessmentError.notEnrolled);
      return;
    }

    // ONE attempt only — if this student already has a submission for this
    // paper on this device, block a second attempt.
    final alreadyDone = widget.repository
        .submissionsForAssessment(assessment.id)
        .any(
          (s) =>
              s.studentId.trim().toLowerCase() ==
              _student.studentId.trim().toLowerCase(),
        );
    if (alreadyDone) {
      _showError(StudentAssessmentError.alreadySubmitted);
      return;
    }

    setState(() {
      _assessment = assessment;
      // Offline mode: there is no teacher/online verification step — once the
      // paper is valid and the student is in a matching section, go straight
      // to the rules screen.
      _stage = _StudentAssessmentStage.rules;
    });
  }

  void _requestVerification() {
    if (_assessment == null) {
      return;
    }
    setState(() {
      _verification = widget.repository.requestVerification(
        student: _student,
        assessmentId: _assessment!.id,
      );
    });
  }

  void _refreshVerification() {
    if (_assessment == null) {
      return;
    }
    setState(() {
      _verification = widget.repository.latestVerificationFor(
        assessmentId: _assessment!.id,
        studentId: _student.studentId,
      );
      if (_verification?.status == VerificationStatus.approved) {
        _stage = _StudentAssessmentStage.rules;
      }
    });
  }

  void _demoApprove() {
    final request = _verification;
    if (request == null) {
      return;
    }
    widget.repository.updateVerification(
      request.id,
      VerificationStatus.approved,
    );
    _refreshVerification();
  }

  /// Returns true when the logged-in student's program/semester/section
  /// matches the assessment. Both are normalised to lowercase + trimmed so
  /// minor casing differences in the enrollment data don't block access.
  ///
  /// If the assessment has an empty program/semester/section (e.g. a paper
  /// shared via a one-to-one offline QR with no class restriction) it is
  /// always accessible.
  /// Normalises a roll number / course code for loose matching (case- and
  /// separator-insensitive, e.g. "BSCS-F25-202" ≈ "f25202", "CSC 123" ≈
  /// "csc123").
  String _key(String s) =>
      s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  /// The course code (e.g. "CC122") for the assessment's courseId, resolved
  /// from the bundled registration courses.
  String _courseCodeFor(String courseId) {
    for (final c in registration.registrationCourses) {
      if (c.id == courseId) return c.courseCode;
    }
    return '';
  }

  /// PRIMARY rule: a student who is REGISTERED in the assessment's course may
  /// attempt it — regardless of their semester/section (covers retakes and
  /// wrong enrolment data). Checked against the bundled local enrollment sheet.
  bool _registeredInAssessmentCourse(Assessment assessment) {
    final roll = _key(widget.student.rollNo);
    if (roll.isEmpty) return false;
    final code = _key(_courseCodeFor(assessment.courseId));
    if (code.isEmpty) return false;
    for (final row in localStudentEnrollmentRows) {
      if (row.length > 7 &&
          _key(row[0]) == roll &&
          _key(row[7]) == code) {
        return true;
      }
    }
    return false;
  }

  bool _isStudentEnrolled(Assessment assessment) {
    // Registered in the course → always allowed.
    if (_registeredInAssessmentCourse(assessment)) return true;

    String n(String s) => s.trim().toLowerCase();
    // An assessment can target SEVERAL sections / semesters / programs at once
    // (the teacher multi-selects, stored comma-separated, e.g. "A,B,C"). Split
    // into tokens so a student in ANY of them is allowed in.
    List<String> toks(String s) =>
        s.split(',').map(n).where((e) => e.isNotEmpty).toList();

    final ap = toks(assessment.program);
    final as_ = toks(assessment.semester);
    final ase = toks(assessment.section);

    // No restriction on the paper → open to all.
    if (ap.isEmpty && as_.isEmpty && ase.isEmpty) {
      return true;
    }

    final sp = n(widget.student.program);
    final ss = n(widget.student.semester);
    final sse = n(widget.student.section);

    final programOk =
        ap.isEmpty || ap.any((t) => sp.contains(t) || t.contains(sp));
    final semesterOk = as_.isEmpty || as_.any((t) => ss == t);
    final sectionOk = ase.isEmpty || ase.any((t) => sse == t);

    return programOk && semesterOk && sectionOk;
  }

  void _showError(StudentAssessmentError error) {
    setState(() {
      _error = error;
      _stage = _StudentAssessmentStage.error;
    });
  }

  /// Runtime admin override for a student whose roll / section is wrong: the
  /// admin enters the admin password, the student re-enters roll + semester +
  /// section (dropdowns), and the attempt proceeds with those values.
  Future<void> _adminApprovedEntry() async {
    final paper = _pendingApprovalAssessment;
    if (paper == null) return;
    const semesters = ['1', '2', '3', '4', '5', '6', '7', '8'];
    const sections = ['A', 'B', 'C', 'D', 'E', 'F', 'G'];
    final passCtrl = TextEditingController();
    final rollCtrl = TextEditingController(text: widget.student.rollNo);
    var semester = semesters.contains(widget.student.semester)
        ? widget.student.semester
        : '1';
    final secUpper = widget.student.section.toUpperCase();
    var section = sections.contains(secUpper) ? secUpper : 'A';
    String? err;

    final approved = await showDialog<bool>(
      context: context,
      builder: (c) => StatefulBuilder(
        builder: (c, setLocal) => AlertDialog(
          title: const Text('Admin approval to attempt'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Ask the admin to enter the admin password, then enter your '
                  'details.',
                  style: TextStyle(fontSize: 12),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: passCtrl,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Admin password',
                    prefixIcon: Icon(Icons.admin_panel_settings_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: rollCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Roll number',
                    prefixIcon: Icon(Icons.badge_outlined),
                  ),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: semester,
                  decoration: const InputDecoration(labelText: 'Semester'),
                  items: [
                    for (final s in semesters)
                      DropdownMenuItem(value: s, child: Text('Semester $s')),
                  ],
                  onChanged: (v) => setLocal(() => semester = v ?? semester),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: section,
                  decoration: const InputDecoration(labelText: 'Section'),
                  items: [
                    for (final s in sections)
                      DropdownMenuItem(value: s, child: Text('Section $s')),
                  ],
                  onChanged: (v) => setLocal(() => section = v ?? section),
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
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final adminPass =
                    LoginStore.instance.passwordOverride('admin') ??
                    'pdfpakistan123#';
                if (passCtrl.text.trim() != adminPass) {
                  setLocal(() => err = 'Admin password is wrong.');
                  return;
                }
                if (rollCtrl.text.trim().isEmpty) {
                  setLocal(() => err = 'Enter the roll number.');
                  return;
                }
                Navigator.pop(c, true);
              },
              child: const Text('Approve & start'),
            ),
          ],
        ),
      ),
    );

    final roll = rollCtrl.text.trim();
    passCtrl.dispose();
    rollCtrl.dispose();
    if (approved != true || !mounted) return;
    setState(() {
      _ovRoll = roll;
      _ovSemester = semester;
      _ovSection = section;
      _assessment = paper;
      _stage = _StudentAssessmentStage.rules;
    });
  }

  void _reset() {
    setState(() {
      _stage = _StudentAssessmentStage.scan;
      _assessment = null;
      _verification = null;
      _lastWarningCount = 0;
      _autoSubmitted = false;
      _joinedServerUrl = null;
    });
  }
}

class _ScanScreen extends StatefulWidget {
  const _ScanScreen({
    required this.controller,
    required this.repository,
    required this.student,
    required this.onVerify,
    required this.onScanned,
    required this.onPreviewError,
    required this.onJoinWifi,
  });

  final TextEditingController controller;
  final AppRepository repository;
  final AssessmentStudent student;
  final VoidCallback onVerify;
  final ValueChanged<String> onScanned;
  final ValueChanged<StudentAssessmentError> onPreviewError;
  final VoidCallback onJoinWifi;

  @override
  State<_ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<_ScanScreen> {
  MobileScannerController? _scannerController;
  bool _cameraOpen = false;
  bool _handled = false;

  @override
  void dispose() {
    _scannerController?.dispose();
    super.dispose();
  }

  Future<void> _openCamera() async {
    _handled = false;
    _scannerController ??= MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    setState(() => _cameraOpen = true);
    await _scannerController?.start();
  }

  Future<void> _closeCamera() async {
    await _scannerController?.stop();
    if (!mounted) return;
    setState(() => _cameraOpen = false);
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _handled = true;
    unawaited(_scannerController?.stop());
    setState(() => _cameraOpen = false);
    widget.onScanned(raw);
  }

  @override
  Widget build(BuildContext context) {
    final active = widget.repository.assessments.where(
      (assessment) => assessment.status == AssessmentStatus.active,
    );

    return _StudentScroll(
      children: [
        const _StudentHeader(
          title: 'Scan to attempt',
          subtitle:
              'Point your camera at the teacher\'s QR. The whole paper loads on your phone — no internet needed.',
          icon: Icons.qr_code_scanner_outlined,
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'QR scanner',
          child: Column(
            children: [
              if (_cameraOpen)
                ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MobileScanner(
                          controller: _scannerController,
                          onDetect: _onDetect,
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Container(
                              width: 200,
                              height: 200,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(20),
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
                )
              else
                Container(
                  width: double.infinity,
                  height: 170,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: PortalColors.blueBorder,
                      width: 2,
                    ),
                    color: const Color(0xFFF8FAFC),
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_scanner_outlined,
                        size: 60,
                        color: PortalColors.brandBlue,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Camera is off',
                        style: TextStyle(color: PortalColors.subtleText),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: _cameraOpen
                    ? OutlinedButton.icon(
                        onPressed: _closeCamera,
                        icon: const Icon(Icons.close_rounded),
                        label: const Text('Close camera'),
                      )
                    : FilledButton.icon(
                        onPressed: _openCamera,
                        icon: const Icon(Icons.photo_camera_rounded),
                        label: const Text('Open camera scanner'),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'Join teacher\'s WiFi exam (no internet)',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'If the teacher is hosting on the local WiFi, connect to get the '
                'quiz directly — no QR scan needed. Your answers upload back to '
                'the teacher automatically.',
                style: TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onJoinWifi,
                icon: const Icon(Icons.wifi_rounded),
                label: const Text('Connect to teacher (WiFi)'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Builder(
          builder: (context) {
            final mine = widget.repository.submissionsForStudentRoll(
              widget.student.studentId,
            );
            if (mine.isEmpty) return const SizedBox.shrink();
            return Column(
              children: [
                _StudentPanel(
                  title: 'My submitted assessments',
                  child: Column(
                    children: [
                      Text(
                        'You have ${mine.length} saved submission(s). Open one '
                        'to show its QR to the teacher again.',
                        style: const TextStyle(color: PortalColors.subtleText),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          onPressed: () => Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => _MySubmissionsScreen(
                                repository: widget.repository,
                                student: widget.student,
                              ),
                            ),
                          ),
                          icon: const Icon(Icons.history_rounded),
                          label: const Text('View / re-share my submissions'),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            );
          },
        ),
        _StudentPanel(
          title: 'Enter code manually',
          child: Column(
            children: [
              TextField(
                controller: widget.controller,
                decoration: const InputDecoration(
                  labelText: 'Assessment code',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: widget.onVerify,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verify assessment'),
              ),
              const SizedBox(height: 10),
              if (active.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    widget.controller.text = active.first.qrCode;
                    widget.onVerify();
                  },
                  icon: const Icon(Icons.qr_code_2_outlined),
                  label: const Text('Use latest active QR'),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'Error state previews',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: StudentAssessmentError.values.map((error) {
              return ActionChip(
                label: Text(error.title),
                onPressed: () => widget.onPreviewError(error),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

/// The student's own saved submissions on THIS phone — so they can re-open any
/// of them later and show the submission QR to the teacher again.
class _MySubmissionsScreen extends StatelessWidget {
  const _MySubmissionsScreen({
    required this.repository,
    required this.student,
  });

  final AppRepository repository;
  final AssessmentStudent student;

  static String _fmtDate(DateTime? d) {
    if (d == null) return '—';
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(d.day)}/${two(d.month)}/${d.year}  ${two(d.hour)}:${two(d.minute)}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('My Submissions')),
      body: AnimatedBuilder(
        animation: repository,
        builder: (context, _) {
          final mine =
              [...repository.submissionsForStudentRoll(student.studentId)]..sort(
                (a, b) =>
                    (b.submittedAt ?? DateTime.fromMillisecondsSinceEpoch(0))
                        .compareTo(
                          a.submittedAt ??
                              DateTime.fromMillisecondsSinceEpoch(0),
                        ),
              );
          if (mine.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No submissions saved on this phone yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PortalColors.subtleText),
                ),
              ),
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: mine.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (context, i) {
              final s = mine[i];
              final title = s.assessmentTitle.isEmpty
                  ? s.assessmentId
                  : s.assessmentTitle;
              return Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: PortalColors.cardBorder),
                  ),
                  leading: const Icon(Icons.assignment_turned_in_outlined),
                  title: Text(
                    title,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    '${_fmtDate(s.submittedAt)}  •  '
                    '${s.status == AttemptStatus.autoLocked ? 'Auto-submitted' : 'Submitted'}'
                    '${s.marks == null ? '' : '  •  Marks: ${s.marks}'}',
                  ),
                  trailing: const Icon(Icons.qr_code_2_rounded),
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          _SubmissionDetailScreen(submission: s, title: title),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

class _SubmissionDetailScreen extends StatelessWidget {
  const _SubmissionDetailScreen({
    required this.submission,
    required this.title,
  });

  final AssessmentSubmission submission;
  final String title;

  @override
  Widget build(BuildContext context) {
    final payload = SubmissionQrCodec.encode(submission);
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Re-share submission')),
      body: _StudentScroll(
        children: [
          _StudentPanel(
            title: 'Show this QR to your teacher',
            child: Column(
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: Theme.of(
                    context,
                  ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 12),
                if (payload != null)
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: PortalColors.cardBorder),
                    ),
                    child: QrImageView(data: payload, size: 240),
                  )
                else
                  const Text(
                    'This submission is too large to fit in one QR.',
                    textAlign: TextAlign.center,
                  ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip('Answers', '${submission.answers.length}'),
                    _InfoChip('Warnings', '${submission.warningCount}'),
                    if (submission.marks != null)
                      _InfoChip('Marks', '${submission.marks}'),
                  ],
                ),
                const SizedBox(height: 10),
                const Text(
                  'The teacher scans this to import your answers — marks are '
                  'applied on the teacher phone.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12,
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

class _VerifyScreen extends StatelessWidget {
  const _VerifyScreen({
    required this.assessment,
    required this.student,
    required this.verification,
    required this.onRequest,
    required this.onRefresh,
    required this.onDemoApprove,
    required this.onBack,
    required this.onContinue,
  });

  final Assessment assessment;
  final AssessmentStudent student;
  final VerificationRequest? verification;
  final VoidCallback onRequest;
  final VoidCallback onRefresh;
  final VoidCallback onDemoApprove;
  final VoidCallback onBack;
  final VoidCallback onContinue;

  @override
  Widget build(BuildContext context) {
    final approved = verification?.status == VerificationStatus.approved;
    final rejected = verification?.status == VerificationStatus.rejected;
    final pending = verification?.status == VerificationStatus.pending;

    return _StudentScroll(
      children: [
        const _StudentHeader(
          title: 'Assessment verification',
          subtitle:
              'The same teacher QR opens the paper assigned to your own student record.',
          icon: Icons.verified_user_outlined,
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'Assessment found',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                assessment.title,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              Text(
                'Personal paper for ${student.name}',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: PortalColors.brandBlue,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip('Type', assessment.type.label),
                  _InfoChip('Program', assessment.program),
                  _InfoChip('Semester', assessment.semester),
                  _InfoChip('Section', assessment.section),
                  _InfoChip('Marks', '${assessment.totalMarks}'),
                  _InfoChip('Duration', '${assessment.durationMinutes} min'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'Identity confirmation',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _ProfileRow('Student', student.name),
              _ProfileRow('Roll number', student.studentId),
              _ProfileRow(
                'Program',
                '${student.program} ${student.semester}${student.section}',
              ),
              const SizedBox(height: 14),
              if (verification == null)
                FilledButton.icon(
                  onPressed: onRequest,
                  icon: const Icon(Icons.send_outlined),
                  label: const Text('Request teacher verification'),
                )
              else if (approved)
                FilledButton.icon(
                  onPressed: onContinue,
                  icon: const Icon(Icons.rule_outlined),
                  label: const Text('Continue to rules'),
                )
              else ...[
                _StatusMessage(
                  icon: rejected
                      ? Icons.cancel_outlined
                      : Icons.hourglass_empty_rounded,
                  title: rejected
                      ? 'Verification declined'
                      : 'Waiting for teacher verification',
                  message: rejected
                      ? 'Submit a fresh request or contact your teacher.'
                      : 'Your request is visible in the teacher dashboard.',
                  color: rejected
                      ? const Color(0xFFB91C1C)
                      : const Color(0xFFB45309),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: onRefresh,
                      icon: const Icon(Icons.refresh_rounded),
                      label: const Text('Refresh status'),
                    ),
                    if (pending)
                      OutlinedButton.icon(
                        onPressed: onDemoApprove,
                        icon: const Icon(Icons.play_circle_outline),
                        label: const Text('Demo approve'),
                      ),
                    if (rejected)
                      FilledButton.icon(
                        onPressed: onRequest,
                        icon: const Icon(Icons.send_outlined),
                        label: const Text('Request again'),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.arrow_back_rounded),
                label: const Text('Back to QR screen'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _RulesScreen extends StatefulWidget {
  const _RulesScreen({
    required this.assessment,
    required this.student,
    required this.onBack,
    required this.onStart,
  });

  final Assessment assessment;
  final AssessmentStudent student;
  final VoidCallback onBack;
  final VoidCallback onStart;

  @override
  State<_RulesScreen> createState() => _RulesScreenState();
}

class _RulesScreenState extends State<_RulesScreen> {
  bool _accepted = false;

  @override
  Widget build(BuildContext context) {
    return _StudentScroll(
      children: [
        const _StudentHeader(
          title: 'Assessment rules',
          subtitle:
              'The attempt runs in locked mode until you submit or time ends.',
          icon: Icons.rule_outlined,
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: widget.assessment.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _RuleLine(
                icon: Icons.lock_outline,
                text:
                    'Do not minimize, switch apps, copy/paste, take screenshots, or quit during the attempt.',
              ),
              _RuleLine(
                icon: Icons.warning_amber_outlined,
                text:
                    'Back, app switch, screen capture, or tampering = ONE warning. '
                    'Do it a second time and your quiz is submitted automatically.',
              ),
              _RuleLine(
                icon: Icons.timer_outlined,
                text:
                    'The timer keeps counting by clock time and submits automatically at zero.',
              ),
              _RuleLine(
                icon: Icons.qr_code_2_outlined,
                text:
                    'After submit, show the submission QR to the teacher so marks are handled on the teacher phone.',
              ),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _accepted,
                onChanged: (value) =>
                    setState(() => _accepted = value ?? false),
                title: const Text('I understand the rules.'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: widget.onBack,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _accepted ? widget.onStart : null,
                      icon: const Icon(Icons.lock_outline),
                      label: const Text('Start locked mode'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _LockedAssessmentScreen extends StatefulWidget {
  const _LockedAssessmentScreen({
    super.key,
    required this.assessment,
    required this.student,
    required this.repository,
    required this.onSubmitted,
  });

  final Assessment assessment;
  final AssessmentStudent student;
  final AppRepository repository;
  final void Function(int warningCount, bool autoSubmitted) onSubmitted;

  @override
  State<_LockedAssessmentScreen> createState() =>
      _LockedAssessmentScreenState();
}

class _LockedAssessmentScreenState extends State<_LockedAssessmentScreen>
    with WidgetsBindingObserver {
  Timer? _timer;
  late DateTime _endsAt;
  late int _secondsLeft;
  int _questionIndex = 0;
  int _warningCount = 0;
  bool _showWarning = false;
  bool _submitted = false;
  bool _appWasCovered = false;
  String _warningReason = 'Suspicious action detected';
  final Map<String, String> _answers = {};
  final Set<String> _review = {};
  final List<String> _flags = [];
  late final List<AssessmentQuestion> _shuffledQuestions;
  late final Map<String, List<String>> _shuffledOptionsByQuestion;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _endsAt = DateTime.now().add(
      Duration(minutes: max(1, widget.assessment.durationMinutes)),
    );
    _secondsLeft = _remainingSeconds();
    // Per-student randomized order: each student sees a different shuffle.
    // Numbering stays 1, 2, 3... but the underlying question differs.
    final seed = '${widget.assessment.id}|${widget.student.studentId}'.hashCode;
    _shuffledQuestions = List.of(widget.assessment.questions)
      ..shuffle(Random(seed));
    _shuffledOptionsByQuestion = {
      for (final question in _shuffledQuestions)
        question.id: List<String>.of(question.options)
          ..shuffle(
            Random(
              '${widget.assessment.id}|${widget.student.studentId}|${question.id}|options'
                  .hashCode,
            ),
          ),
    };
    unawaited(AssessmentLockdownController.enable());
    // Split-screen / multi-window during the attempt → treat as a bypass.
    AssessmentLockdownController.onLockBreak = (reason) {
      if (mounted && !_submitted) _warn('Split screen / multi-window blocked');
    };
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      _syncTimer();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    unawaited(AssessmentLockdownController.disable());
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_submitted) {
      return;
    }
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.paused) {
      _appWasCovered = true;
      return;
    }
    if (state == AppLifecycleState.resumed && _appWasCovered) {
      _appWasCovered = false;
      _syncTimer();
      if (!_submitted) {
        _warn('App switch or screen lock attempt');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final questions = _shuffledQuestions;
    if (questions.isEmpty) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, result) {
          if (!didPop) _warn('Back button attempt');
        },
        child: Stack(
          children: [
            _StudentScroll(
              children: [
                _LockedHeader(
                  title: widget.assessment.title,
                  timeLeft: _formatTime(_secondsLeft),
                  warningCount: _warningCount,
                  onQuit: () => _warn('Quit attempt blocked'),
                ),
                const SizedBox(height: 16),
                _StudentPanel(
                  title: 'No questions',
                  child: FilledButton.icon(
                    onPressed: () => _submit(
                      autoSubmitted: false,
                      status: AttemptStatus.submitted,
                    ),
                    icon: const Icon(Icons.check_circle_outline),
                    label: const Text('Submit assessment'),
                  ),
                ),
              ],
            ),
            if (_showWarning)
              _WarningModal(
                count: _warningCount,
                reason: _warningReason,
                onContinue: () => setState(() => _showWarning = false),
                onSubmit: () => _submit(
                  autoSubmitted: true,
                  status: AttemptStatus.autoLocked,
                ),
              ),
          ],
        ),
      );
    }
    final question = questions[_questionIndex];
    final answered = _answers.length;
    final progress = questions.isEmpty ? 0.0 : answered / questions.length;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _warn('Back button attempt');
      },
      child: Stack(
        children: [
          _StudentScroll(
            children: [
              _LockedHeader(
                title: widget.assessment.title,
                timeLeft: _formatTime(_secondsLeft),
                warningCount: _warningCount,
                onQuit: () => _warn('Quit attempt blocked'),
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 16),
              _StudentPanel(
                title: 'Question ${_questionIndex + 1} of ${questions.length}',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _InfoChip(
                          question.type.label,
                          '${question.marks} marks',
                        ),
                        const Spacer(),
                        TextButton.icon(
                          onPressed: () {
                            setState(() {
                              if (_review.contains(question.id)) {
                                _review.remove(question.id);
                              } else {
                                _review.add(question.id);
                              }
                            });
                          },
                          icon: Icon(
                            _review.contains(question.id)
                                ? Icons.bookmark
                                : Icons.bookmark_border,
                          ),
                          label: const Text('Review'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      question.question,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    _AnswerInput(
                      question: question,
                      options:
                          _shuffledOptionsByQuestion[question.id] ??
                          question.options,
                      value: _answers[question.id],
                      onChanged: (value) => _setAnswer(question, value),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              _StudentPanel(
                title: 'Security monitor',
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _InfoChip('Mode', 'Locked'),
                    _InfoChip('Warnings', '$_warningCount/1'),
                    _InfoChip('Answered', '$answered/${questions.length}'),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _questionIndex == 0
                          ? null
                          : () => setState(() => _questionIndex--),
                      icon: const Icon(Icons.chevron_left_rounded),
                      label: const Text('Previous'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _questionIndex == questions.length - 1
                          ? null
                          : () => setState(() => _questionIndex++),
                      icon: const Icon(Icons.chevron_right_rounded),
                      label: const Text('Next'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FilledButton.icon(
                onPressed: () => _confirmSubmit(context),
                icon: const Icon(Icons.check_circle_outline),
                label: const Text('Submit assessment'),
              ),
            ],
          ),
          if (_showWarning)
            _WarningModal(
              count: _warningCount,
              reason: _warningReason,
              onContinue: () => setState(() => _showWarning = false),
              onSubmit: () => _submit(
                autoSubmitted: true,
                status: AttemptStatus.autoLocked,
              ),
            ),
        ],
      ),
    );
  }

  void _syncTimer() {
    if (_submitted) {
      return;
    }
    final next = _remainingSeconds();
    if (next <= 0) {
      _submit(autoSubmitted: true, status: AttemptStatus.submitted);
      return;
    }
    if (next != _secondsLeft) {
      setState(() => _secondsLeft = next);
    }
  }

  int _remainingSeconds() {
    return max(0, _endsAt.difference(DateTime.now()).inSeconds);
  }

  void _setAnswer(AssessmentQuestion question, String value) {
    final clean = value.trim();
    setState(() {
      if (clean.isEmpty) {
        _answers.remove(question.id);
      } else {
        _answers[question.id] = value;
      }
    });
  }

  void _warn(String reason) {
    if (_submitted) {
      return;
    }
    // Policy: ONE warning only — the very next bypass auto-submits.
    final nextCount = min(2, _warningCount + 1);
    setState(() {
      _warningCount = nextCount;
      _warningReason = reason;
      _flags.add(reason);
      _showWarning = nextCount < 2;
    });
    _say('Warning');
    if (nextCount >= 2) {
      _submit(autoSubmitted: true, status: AttemptStatus.autoLocked);
    }
  }

  Future<void> _confirmSubmit(BuildContext context) async {
    final shouldSubmit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Submit assessment?'),
        content: Text(
          'You answered ${_answers.length} of ${_shuffledQuestions.length} questions. ${_review.isEmpty ? '' : '${_review.length} marked for review.'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continue'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (shouldSubmit == true) {
      _submit(autoSubmitted: false, status: AttemptStatus.submitted);
    }
  }

  static const MethodChannel _speech = MethodChannel(
    'csexam_qr_attendance/speech',
  );

  void _say(String message) {
    try {
      _speech.invokeMethod<void>('speak', {'message': message});
    } catch (_) {
      // No native TTS (desktop/web) — silent is fine.
    }
  }

  void _submit({required bool autoSubmitted, required AttemptStatus status}) {
    if (_submitted) {
      return;
    }
    _submitted = true;
    _timer?.cancel();
    _say(autoSubmitted ? 'Time up. Assessment submitted' : 'Assessment submitted');
    unawaited(AssessmentLockdownController.disable());
    widget.repository.submitAssessment(
      assessment: widget.assessment,
      student: widget.student,
      answers: Map.unmodifiable(_answers),
      warningCount: _warningCount,
      flags: List.unmodifiable(_flags),
      status: status,
    );
    widget.onSubmitted(_warningCount, autoSubmitted);
  }

  String _formatTime(int seconds) {
    final minutes = seconds ~/ 60;
    final remaining = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${remaining.toString().padLeft(2, '0')}';
  }
}

class _AnswerInput extends StatelessWidget {
  const _AnswerInput({
    required this.question,
    required this.options,
    required this.value,
    required this.onChanged,
  });

  final AssessmentQuestion question;
  final List<String> options;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.mcq:
      case QuestionType.trueFalse:
        return Column(
          children: options.map((option) {
            final selected = value == option;
            return ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: selected
                    ? PortalColors.brandBlue
                    : PortalColors.subtleText,
              ),
              title: Text(option),
              onTap: () => onChanged(option),
            );
          }).toList(),
        );
      case QuestionType.shortAnswer:
        return TextField(
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(labelText: 'Short answer'),
        );
      case QuestionType.longAnswer:
        return TextField(
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: false,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Long answer'),
        );
      case QuestionType.fileUpload:
        return TextField(
          onChanged: onChanged,
          autocorrect: false,
          enableSuggestions: false,
          enableInteractiveSelection: false,
          decoration: const InputDecoration(
            labelText: 'File reference',
            prefixIcon: Icon(Icons.insert_drive_file_outlined),
          ),
        );
    }
  }
}

/// Assignment submission screen — shown instead of the locked quiz attempt
/// when the assessment type is `assignment`. Students read the tasks, type
/// their answer, optionally attach a file, and submit. Graded manually by the
/// teacher later (no auto-grading, no proctoring).
class _AssignmentSubmitScreen extends StatefulWidget {
  const _AssignmentSubmitScreen({
    required this.assessment,
    required this.student,
    required this.repository,
    required this.onBack,
    required this.onSubmitted,
  });

  final Assessment assessment;
  final AssessmentStudent student;
  final AppRepository repository;
  final VoidCallback onBack;
  final VoidCallback onSubmitted;

  @override
  State<_AssignmentSubmitScreen> createState() =>
      _AssignmentSubmitScreenState();
}

class _AssignmentSubmitScreenState extends State<_AssignmentSubmitScreen> {
  final _answerController = TextEditingController();
  String? _attachedFileName;
  bool _submitting = false;

  @override
  void dispose() {
    _answerController.dispose();
    super.dispose();
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(withData: false);
    if (result == null || result.files.isEmpty) return;
    setState(() => _attachedFileName = result.files.first.name);
  }

  void _submit() {
    if (_submitting) return;
    setState(() => _submitting = true);
    widget.repository.submitAssessment(
      assessment: widget.assessment,
      student: widget.student,
      answers: {
        'text': _answerController.text.trim(),
        if (_attachedFileName != null) 'file': _attachedFileName!,
      },
      warningCount: 0,
      flags: const [],
      status: AttemptStatus.submitted,
    );
    widget.onSubmitted();
  }

  @override
  Widget build(BuildContext context) {
    final dueLabel =
        '${widget.assessment.endTime.day}/${widget.assessment.endTime.month}/${widget.assessment.endTime.year}';
    return _StudentScroll(
      children: [
        const _StudentHeader(
          title: 'Assignment',
          subtitle: 'Read the tasks, write your answer, attach a file, submit.',
          icon: Icons.assignment_outlined,
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: widget.assessment.title,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip('Marks', '${widget.assessment.totalMarks}'),
                  _InfoChip('Tasks', '${widget.assessment.questions.length}'),
                  _InfoChip('Due', dueLabel),
                ],
              ),
              if (widget.assessment.instructions.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  widget.assessment.instructions,
                  style: const TextStyle(color: PortalColors.subtleText),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 16),
        if (widget.assessment.questions.isNotEmpty)
          _StudentPanel(
            title: 'Tasks',
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (var i = 0; i < widget.assessment.questions.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${i + 1}. ',
                          style: const TextStyle(fontWeight: FontWeight.w800),
                        ),
                        Expanded(
                          child: Text(
                            '${widget.assessment.questions[i].question}  '
                            '(${widget.assessment.questions[i].marks} marks)',
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'Your submission',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _answerController,
                minLines: 4,
                maxLines: 10,
                decoration: const InputDecoration(
                  labelText: 'Type your answer',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  OutlinedButton.icon(
                    onPressed: _pickFile,
                    icon: const Icon(Icons.attach_file_rounded),
                    label: const Text('Attach file'),
                  ),
                  const SizedBox(width: 10),
                  if (_attachedFileName != null)
                    Expanded(
                      child: Text(
                        _attachedFileName!,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _submitting ? null : widget.onBack,
                      child: const Text('Back'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: _submitting ? null : _submit,
                      icon: _submitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send_rounded),
                      label: Text(_submitting ? 'Submitting…' : 'Submit'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _SubmittedScreen extends StatefulWidget {
  const _SubmittedScreen({
    required this.assessment,
    required this.student,
    required this.repository,
    required this.warningCount,
    required this.autoSubmitted,
    required this.onHome,
    this.serverUrl,
  });

  final Assessment assessment;
  final AssessmentStudent student;
  final AppRepository repository;
  final int warningCount;
  final bool autoSubmitted;
  final VoidCallback onHome;

  /// When the student joined via the teacher's local WiFi host, the submission
  /// is uploaded back to this address automatically (QR stays as a fallback).
  final String? serverUrl;

  @override
  State<_SubmittedScreen> createState() => _SubmittedScreenState();
}

class _SubmittedScreenState extends State<_SubmittedScreen> {
  /// null = not a WiFi join; otherwise 'sending' | 'ok' | 'fail'.
  String? _wifiStatus;

  @override
  void initState() {
    super.initState();
    if (widget.serverUrl != null) unawaited(_uploadToHost());
  }

  AssessmentSubmission? _findSubmission() => widget.repository
      .submissionsForAssessment(widget.assessment.id)
      .where((s) => s.studentId == widget.student.id)
      .fold<AssessmentSubmission?>(
        null,
        (latest, s) =>
            latest == null ||
                (s.submittedAt ?? DateTime(0)).isAfter(
                  latest.submittedAt ?? DateTime(0),
                )
            ? s
            : latest,
      );

  Future<void> _uploadToHost() async {
    final sub = _findSubmission();
    if (sub == null) {
      if (mounted) setState(() => _wifiStatus = 'fail');
      return;
    }
    setState(() => _wifiStatus = 'sending');
    try {
      final ok = await LocalExamClient.submit(widget.serverUrl!, sub);
      if (mounted) setState(() => _wifiStatus = ok ? 'ok' : 'fail');
    } catch (_) {
      if (mounted) setState(() => _wifiStatus = 'fail');
    }
  }

  @override
  Widget build(BuildContext context) {
    final assessment = widget.assessment;
    final warningCount = widget.warningCount;
    final autoSubmitted = widget.autoSubmitted;
    final onHome = widget.onHome;

    // Look up the submission the student just created.
    final submission = _findSubmission();

    final qrPayload = submission == null
        ? null
        : SubmissionQrCodec.encode(submission);

    return _StudentScroll(
      children: [
        _StudentPanel(
          title: autoSubmitted ? 'Auto-submitted' : 'Submitted successfully',
          child: Column(
            children: [
              Icon(
                autoSubmitted
                    ? Icons.timer_off_outlined
                    : Icons.check_circle_outline,
                color: autoSubmitted
                    ? const Color(0xFFB45309)
                    : const Color(0xFF0F766E),
                size: 60,
              ),
              const SizedBox(height: 12),
              Text(
                assessment.title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 10),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip('Questions', '${assessment.questions.length}'),
                  _InfoChip('Warnings', '$warningCount'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        // ---- Submission QR ------------------------------------------------
        _StudentPanel(
          title: widget.serverUrl != null
              ? 'Sent to teacher (WiFi)'
              : 'Show this QR to your teacher',
          child: Column(
            children: [
              if (widget.serverUrl != null) ...[
                _wifiUploadBanner(),
                const SizedBox(height: 12),
              ],
              if (qrPayload != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: PortalColors.cardBorder),
                  ),
                  child: QrImageView(
                    data: qrPayload,
                    version: QrVersions.auto,
                    size: 240,
                    backgroundColor: Colors.white,
                    errorCorrectionLevel: QrErrorCorrectLevel.M,
                  ),
                )
              else
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF3CD),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFFFCE8A6)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.warning_amber_rounded,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Submission has too many long answers to fit in one QR. '
                          'Show this screen to your teacher manually.',
                          style: TextStyle(color: Color(0xFFB45309)),
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 14),
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
                child: const Row(
                  children: [
                    Icon(
                      Icons.wifi_off_rounded,
                      size: 16,
                      color: Color(0xFF0F766E),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Your answers are packed inside this QR. '
                        'Teacher scans it — no internet needed.',
                        style: TextStyle(
                          color: Color(0xFF0F766E),
                          fontWeight: FontWeight.w600,
                          fontSize: 12.5,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: onHome,
                icon: const Icon(Icons.home_outlined),
                label: const Text('Back to assessment home'),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _wifiUploadBanner() {
    final Color bg;
    final Color fg;
    final IconData icon;
    final String text;
    switch (_wifiStatus) {
      case 'ok':
        bg = const Color(0xFFEAFBEF);
        fg = const Color(0xFF0F766E);
        icon = Icons.check_circle_rounded;
        text = 'Your answers were sent to the teacher over WiFi. No QR needed.';
      case 'fail':
        bg = const Color(0xFFFDECEC);
        fg = const Color(0xFFB91C1C);
        icon = Icons.error_outline_rounded;
        text = 'Could not reach the teacher — show the QR below instead.';
      default: // 'sending' or null
        bg = const Color(0xFFFFF7E6);
        fg = const Color(0xFFB45309);
        icon = Icons.sync_rounded;
        text = 'Sending your answers to the teacher…';
    }
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: fg.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: fg),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                color: fg,
                fontWeight: FontWeight.w600,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _AssessmentErrorScreen extends StatelessWidget {
  const _AssessmentErrorScreen({
    required this.error,
    required this.onBack,
    this.onAdminApprove,
  });

  final StudentAssessmentError error;
  final VoidCallback onBack;

  /// When set (e.g. a section mismatch), offers a runtime admin-approved entry.
  final VoidCallback? onAdminApprove;

  @override
  Widget build(BuildContext context) {
    return _StudentScroll(
      children: [
        _StudentPanel(
          title: error.title,
          child: Column(
            children: [
              const Icon(
                Icons.error_outline_rounded,
                color: Color(0xFFB91C1C),
                size: 70,
              ),
              const SizedBox(height: 14),
              Text(
                error.message,
                textAlign: TextAlign.center,
                style: const TextStyle(color: PortalColors.subtleText),
              ),
              const SizedBox(height: 18),
              if (onAdminApprove != null) ...[
                FilledButton.icon(
                  onPressed: onAdminApprove,
                  icon: const Icon(Icons.admin_panel_settings_outlined),
                  label: const Text('Get admin approval to attempt'),
                ),
                const SizedBox(height: 10),
              ],
              OutlinedButton.icon(
                onPressed: onBack,
                icon: const Icon(Icons.qr_code_scanner_outlined),
                label: const Text('Try another code'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StudentScroll extends StatelessWidget {
  const _StudentScroll({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: children,
      ),
    );
  }
}

class _StudentHeader extends StatelessWidget {
  const _StudentHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
  });

  final String title;
  final String subtitle;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: PortalColors.heroGradient,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(
        children: [
          Icon(icon, color: Colors.white, size: 36),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Color(0xFFEFF6FF)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LockedHeader extends StatelessWidget {
  const _LockedHeader({
    required this.title,
    required this.timeLeft,
    required this.warningCount,
    required this.onQuit,
  });

  final String title;
  final String timeLeft;
  final int warningCount;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: PortalColors.textPrimary,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, color: Colors.white),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Locked mode',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              IconButton(
                tooltip: 'Quit',
                onPressed: onQuit,
                icon: const Icon(Icons.close_rounded, color: Colors.white),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(title, style: const TextStyle(color: Color(0xFFE5E7EB))),
          const SizedBox(height: 12),
          Row(
            children: [
              _DarkPill(icon: Icons.timer_outlined, label: timeLeft),
              const SizedBox(width: 8),
              _DarkPill(
                icon: Icons.warning_amber_outlined,
                label: 'Warnings $warningCount/1',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StudentPanel extends StatelessWidget {
  const _StudentPanel({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 14),
            child,
          ],
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  const _InfoChip(this.label, this.value);

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

class _ProfileRow extends StatelessWidget {
  const _ProfileRow(this.label, this.value);

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: const TextStyle(
                color: PortalColors.subtleText,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '-' : value,
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

class _RuleLine extends StatelessWidget {
  const _RuleLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: PortalColors.brandBlue),
          const SizedBox(width: 10),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}

class _StatusMessage extends StatelessWidget {
  const _StatusMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  final IconData icon;
  final String title;
  final String message;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(color: color, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(message, style: TextStyle(color: color)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _DarkPill extends StatelessWidget {
  const _DarkPill({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}

class _WarningModal extends StatelessWidget {
  const _WarningModal({
    required this.count,
    required this.reason,
    required this.onContinue,
    required this.onSubmit,
  });

  final int count;
  final String reason;
  final VoidCallback onContinue;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final finalWarning = count >= 2;
    return _OverlayCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            finalWarning ? Icons.lock_outline : Icons.warning_amber_outlined,
            color: finalWarning
                ? const Color(0xFFB91C1C)
                : const Color(0xFFB45309),
            size: 60,
          ),
          const SizedBox(height: 12),
          Text(
            finalWarning ? 'Final Warning' : 'Warning — last chance',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Text(
            reason,
            textAlign: TextAlign.center,
            style: const TextStyle(color: PortalColors.subtleText),
          ),
          const SizedBox(height: 8),
          const Text(
            'This is your ONLY warning. If you try this again, your quiz will '
            'be submitted automatically.',
            textAlign: TextAlign.center,
            style: TextStyle(
              color: Color(0xFFB91C1C),
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
          const SizedBox(height: 18),
          if (finalWarning)
            FilledButton.icon(
              onPressed: onSubmit,
              icon: const Icon(Icons.lock_outline),
              label: const Text('Submit locked attempt'),
            )
          else
            FilledButton(
              onPressed: onContinue,
              child: const Text('Continue assessment'),
            ),
        ],
      ),
    );
  }
}

class _OverlayCard extends StatelessWidget {
  const _OverlayCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.45),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Card(
            child: Padding(padding: const EdgeInsets.all(22), child: child),
          ),
        ),
      ),
    );
  }
}
