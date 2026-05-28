import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../ui/student_portal_shell.dart';
import 'assessment_models.dart';

enum _StudentAssessmentStage { scan, verify, rules, attempt, submitted, error }

enum StudentAssessmentError {
  invalidQr,
  expiredQr,
  notStarted,
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

  AssessmentStudent get _student => AssessmentStudent(
    id: widget.student.rollNo.isEmpty
        ? 'firebase-student'
        : widget.student.rollNo,
    name: widget.student.studentName.isEmpty
        ? 'Student'
        : widget.student.studentName,
    studentId: widget.student.rollNo,
    program: widget.student.program,
    session: widget.student.currentSession.isEmpty
        ? 'S26'
        : widget.student.currentSession,
    semester: widget.student.semester,
    section: widget.student.section,
    email: '${widget.student.rollNo}@student.local',
  );

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
            onVerify: _verifyCode,
            onPreviewError: _showError,
          ),
          _StudentAssessmentStage.verify => _VerifyScreen(
            assessment: _assessment!,
            student: _student,
            verification: _verification,
            onRequest: _requestVerification,
            onRefresh: _refreshVerification,
            onDemoApprove: _demoApprove,
            onBack: () => setState(() => _stage = _StudentAssessmentStage.scan),
            onContinue: () =>
                setState(() => _stage = _StudentAssessmentStage.rules),
          ),
          _StudentAssessmentStage.rules => _RulesScreen(
            assessment: _assessment!,
            student: _student,
            onBack: () =>
                setState(() => _stage = _StudentAssessmentStage.verify),
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
          _StudentAssessmentStage.submitted => _SubmittedScreen(
            assessment: _assessment!,
            warningCount: _lastWarningCount,
            autoSubmitted: _autoSubmitted,
            onHome: _reset,
          ),
          _StudentAssessmentStage.error => _AssessmentErrorScreen(
            error: _error,
            onBack: () => setState(() => _stage = _StudentAssessmentStage.scan),
          ),
        };
      },
    );
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

    setState(() {
      _assessment = assessment;
      _verification = widget.repository.latestVerificationFor(
        assessmentId: assessment.id,
        studentId: _student.studentId,
      );
      _stage = _StudentAssessmentStage.verify;
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

  void _showError(StudentAssessmentError error) {
    setState(() {
      _error = error;
      _stage = _StudentAssessmentStage.error;
    });
  }

  void _reset() {
    setState(() {
      _stage = _StudentAssessmentStage.scan;
      _assessment = null;
      _verification = null;
      _lastWarningCount = 0;
      _autoSubmitted = false;
    });
  }
}

class _ScanScreen extends StatelessWidget {
  const _ScanScreen({
    required this.controller,
    required this.repository,
    required this.onVerify,
    required this.onPreviewError,
  });

  final TextEditingController controller;
  final AppRepository repository;
  final VoidCallback onVerify;
  final ValueChanged<StudentAssessmentError> onPreviewError;

  @override
  Widget build(BuildContext context) {
    final active = repository.assessments.where(
      (assessment) => assessment.status == AssessmentStatus.active,
    );

    return _StudentScroll(
      children: [
        const _StudentHeader(
          title: 'Student assessment',
          subtitle: 'Scan the classroom QR code or enter the assessment code.',
          icon: Icons.qr_code_scanner_outlined,
        ),
        const SizedBox(height: 16),
        _StudentPanel(
          title: 'QR scan',
          child: Column(
            children: [
              Container(
                width: 170,
                height: 170,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: PortalColors.blueBorder, width: 2),
                  color: const Color(0xFFF8FAFC),
                ),
                child: const Icon(
                  Icons.qr_code_scanner_outlined,
                  size: 70,
                  color: PortalColors.brandBlue,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                decoration: const InputDecoration(
                  labelText: 'Assessment code',
                  prefixIcon: Icon(Icons.key_outlined),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: onVerify,
                icon: const Icon(Icons.verified_outlined),
                label: const Text('Verify assessment'),
              ),
              const SizedBox(height: 10),
              if (active.isNotEmpty)
                OutlinedButton.icon(
                  onPressed: () {
                    controller.text = active.first.qrCode;
                    onVerify();
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
                onPressed: () => onPreviewError(error),
              );
            }).toList(),
          ),
        ),
      ],
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
              'Locked mode is represented here as frontend UI simulation.',
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
                    'Warning 1, Warning 2, and Final Warning are shown as simulated UI states.',
              ),
              _RuleLine(
                icon: Icons.timer_outlined,
                text:
                    'Timer counts down and auto-submit state appears when time expires.',
              ),
              _RuleLine(
                icon: Icons.cloud_outlined,
                text:
                    'Answers are kept in local mock state for now; no backend submission is added.',
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

class _LockedAssessmentScreenState extends State<_LockedAssessmentScreen> {
  Timer? _timer;
  late int _secondsLeft;
  int _questionIndex = 0;
  int _warningCount = 0;
  bool _showWarning = false;
  bool _showQuitConfirm = false;
  String _warningReason = 'Suspicious action detected';
  final Map<String, String> _answers = {};
  final Set<String> _review = {};
  final List<String> _flags = [];
  late final List<AssessmentQuestion> _shuffledQuestions;

  @override
  void initState() {
    super.initState();
    _secondsLeft = widget.assessment.durationMinutes * 60;
    // Per-student randomized order: each student sees a different shuffle.
    // Numbering stays 1, 2, 3... but the underlying question differs.
    final seed = '${widget.assessment.id}|${widget.student.studentId}'
        .hashCode;
    _shuffledQuestions = List.of(widget.assessment.questions)
      ..shuffle(Random(seed));
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      if (_secondsLeft <= 1) {
        _submit(autoSubmitted: true, status: AttemptStatus.submitted);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final questions = _shuffledQuestions;
    final question = questions[_questionIndex];
    final answered = _answers.length;
    final progress = questions.isEmpty ? 0.0 : answered / questions.length;

    return Stack(
      children: [
        _StudentScroll(
          children: [
            _LockedHeader(
              title: widget.assessment.title,
              timeLeft: _formatTime(_secondsLeft),
              warningCount: _warningCount,
              onQuit: () => setState(() => _showQuitConfirm = true),
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
                      _InfoChip(question.type.label, '${question.marks} marks'),
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
                    value: _answers[question.id],
                    onChanged: (value) {
                      setState(() => _answers[question.id] = value);
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _StudentPanel(
              title: 'Locked mode simulation',
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _SimButton(
                    icon: Icons.tab_outlined,
                    label: 'App switch',
                    onPressed: () => _warn('App switch detected'),
                  ),
                  _SimButton(
                    icon: Icons.screenshot_outlined,
                    label: 'Screenshot',
                    onPressed: () => _warn('Screenshot attempt'),
                  ),
                  _SimButton(
                    icon: Icons.content_paste_off_outlined,
                    label: 'Copy/Paste',
                    onPressed: () => _warn('Copy/paste attempt'),
                  ),
                  _SimButton(
                    icon: Icons.phonelink_lock_outlined,
                    label: 'Tamper',
                    onPressed: () => _warn('Tampering attempt'),
                  ),
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
            onSubmit: () =>
                _submit(autoSubmitted: false, status: AttemptStatus.flagged),
          ),
        if (_showQuitConfirm)
          _QuitModal(
            onCancel: () => setState(() => _showQuitConfirm = false),
            onQuit: () =>
                _submit(autoSubmitted: false, status: AttemptStatus.quit),
          ),
      ],
    );
  }

  void _warn(String reason) {
    setState(() {
      _warningCount++;
      _warningReason = reason;
      _flags.add(reason);
      _showWarning = true;
    });
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

  void _submit({required bool autoSubmitted, required AttemptStatus status}) {
    _timer?.cancel();
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
    required this.value,
    required this.onChanged,
  });

  final AssessmentQuestion question;
  final String? value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    switch (question.type) {
      case QuestionType.mcq:
      case QuestionType.trueFalse:
        return Column(
          children: question.options.map((option) {
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
          decoration: const InputDecoration(labelText: 'Short answer'),
        );
      case QuestionType.longAnswer:
        return TextField(
          onChanged: onChanged,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Long answer'),
        );
      case QuestionType.fileUpload:
        return OutlinedButton.icon(
          onPressed: () => onChanged('File upload placeholder selected'),
          icon: const Icon(Icons.upload_file_outlined),
          label: Text(value ?? 'File upload placeholder'),
        );
    }
  }
}

class _SubmittedScreen extends StatelessWidget {
  const _SubmittedScreen({
    required this.assessment,
    required this.warningCount,
    required this.autoSubmitted,
    required this.onHome,
  });

  final Assessment assessment;
  final int warningCount;
  final bool autoSubmitted;
  final VoidCallback onHome;

  @override
  Widget build(BuildContext context) {
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
                size: 70,
              ),
              const SizedBox(height: 14),
              Text(
                assessment.title,
                textAlign: TextAlign.center,
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  _InfoChip('Questions', '${assessment.questions.length}'),
                  _InfoChip('Warnings', '$warningCount'),
                  _InfoChip(
                    'Result',
                    assessment.settings.showResultAfterSubmission
                        ? 'Visible'
                        : 'Teacher review',
                  ),
                ],
              ),
              const SizedBox(height: 18),
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
}

class _AssessmentErrorScreen extends StatelessWidget {
  const _AssessmentErrorScreen({required this.error, required this.onBack});

  final StudentAssessmentError error;
  final VoidCallback onBack;

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
              FilledButton.icon(
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
        gradient: const LinearGradient(
          colors: [Color(0xFF2948B7), Color(0xFF10B7C4)],
        ),
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
                label: 'Warnings $warningCount/3',
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

class _SimButton extends StatelessWidget {
  const _SimButton({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon),
      label: Text(label),
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
    final finalWarning = count >= 3;
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
            finalWarning ? 'Final Warning' : 'Warning $count of 3',
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

class _QuitModal extends StatelessWidget {
  const _QuitModal({required this.onCancel, required this.onQuit});

  final VoidCallback onCancel;
  final VoidCallback onQuit;

  @override
  Widget build(BuildContext context) {
    return _OverlayCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.logout_rounded, color: Color(0xFFB91C1C), size: 58),
          const SizedBox(height: 12),
          Text(
            'Quit assessment?',
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          const Text(
            'Quit will mark the attempt as left early in the teacher monitor.',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onCancel,
                  child: const Text('Continue'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton(
                  onPressed: onQuit,
                  child: const Text('Quit'),
                ),
              ),
            ],
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
