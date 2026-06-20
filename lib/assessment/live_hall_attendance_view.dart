import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/teacher_dashboard_database.dart';
import '../ui/student_portal_shell.dart';
import 'teacher_dashboard_models.dart';

/// Live hall attendance: the camera stays on one side while the hall
/// "skeleton" (seat grid) fills in as student QR codes are scanned. Whoever is
/// still pending at the end is marked absent on Finish. A second tab records
/// UFM (Unfair Means) cases one at a time.
class LiveHallAttendanceView extends StatefulWidget {
  const LiveHallAttendanceView({
    super.key,
    required this.sheetId,
    required this.onBack,
    required this.onFinished,
    this.selectedClass,
  });

  final String sheetId;
  final VoidCallback onBack;
  final ValueChanged<ExamHallStats> onFinished;

  /// When set, attendance is scoped to a single class/section of the hall: the
  /// skeleton shows only that class's seats and every scan is attributed to it.
  final ExamClassGroup? selectedClass;

  @override
  State<LiveHallAttendanceView> createState() => _LiveHallAttendanceViewState();
}

class _LiveHallAttendanceViewState extends State<LiveHallAttendanceView> {
  static const MethodChannel _speechChannel = MethodChannel(
    'csexam_qr_attendance/speech',
  );

  final _database = TeacherDashboardDatabase.instance;
  MobileScannerController? _scanner;

  ExamHallStats? _stats;
  List<ExamAttendanceStudent> _students = const [];
  List<UfmCase> _ufmCases = const [];

  /// studentIds confirmed present (scanned or tapped).
  final Set<String> _present = {};

  int _tab = 0; // 0 = scan & seats, 1 = UFM
  bool _loading = true;
  String? _loadError;
  bool _finishing = false;

  // Scan feedback.
  String? _scanMessage = "Scan each student's QR to mark them present.";
  bool _scanOk = true;
  DateTime _scanCooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);

  // The last student marked by a scan — for quick "Undo" of a wrong scan.
  String? _undoStudentId;
  String _undoRoll = '';
  bool _undoWasDynamic = false; // true ⇒ delete the record on undo

  @override
  void initState() {
    super.initState();
    _scanner = MobileScannerController(
      detectionSpeed: DetectionSpeed.noDuplicates,
      formats: const [BarcodeFormat.qrCode],
    );
    _load();
  }

  @override
  void dispose() {
    unawaited(_stopSpeech());
    _scanner?.dispose();
    super.dispose();
  }

  // Spoken confirmation after each scan (same native TTS channel the standalone
  // QR attendance scanner used). Silently ignored if the device has no TTS.
  Future<void> _speak(String message) async {
    final text = message.trim();
    if (text.isEmpty) return;
    try {
      await _speechChannel.invokeMethod<void>('speak', {'message': text});
    } catch (_) {
      // Attendance marking must keep working even without phone TTS.
    }
  }

  Future<void> _stopSpeech() async {
    try {
      await _speechChannel.invokeMethod<void>('stop');
    } catch (_) {
      // Ignore — speech is a non-critical convenience.
    }
  }

  /// A short spoken prompt for a marked student. While taking one class's
  /// attendance it simply says "Present"; for the whole hall it adds the class
  /// so the invigilator hears which paper was scanned.
  String _scanPrompt(String rollNo) {
    if (widget.selectedClass != null) {
      return 'Present';
    }
    final code = _programCode(rollNo);
    for (final group in _stats?.classGroups ?? const <ExamClassGroup>[]) {
      if (group.code == code) {
        return '${group.program}, present';
      }
    }
    return 'Present';
  }

  Future<void> _load() async {
    try {
      final detail = await _database.loadAttendanceSheetDetail(widget.sheetId);
      final cases = await _database.loadUfmCases(widget.sheetId);
      if (!mounted) return;
      setState(() {
        _stats = detail.stats;
        _students = detail.students;
        _present
          ..clear()
          ..addAll(
            detail.students
                .where((s) => s.status == 'present')
                .map((s) => s.studentId),
          );
        _ufmCases = cases;
        _loading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadError = error.toString();
        _loading = false;
      });
    }
  }

  // ---------------------------------------------------------------- scanning
  String _normalizeRoll(String value) =>
      value.trim().toUpperCase().replaceAll(RegExp(r'\s+'), '');

  String _normHall(String value) =>
      value.toUpperCase().replaceAll(RegExp(r'\s+'), '');

  /// The class label this screen is attributing scans to (empty for whole-hall).
  String get _classLabel => widget.selectedClass?.program ?? '';

  /// True when [student] belongs to the class this screen is scoped to (or
  /// always true for whole-hall mode).
  bool _inSelectedClass(ExamAttendanceStudent student) {
    final group = widget.selectedClass;
    if (group == null) return true;
    if (student.classGroup.isNotEmpty) {
      return student.classGroup == group.program;
    }
    return _programCode(student.rollNo) == group.code;
  }

  /// Finds a student already in this sheet that matches the scanned payload.
  /// Accepts a plain roll, JSON with a roll field, or pipe formats
  /// (CSEXAM|...) where any part matches a roll in this sheet.
  ExamAttendanceStudent? _matchStudent(String raw) {
    final byRoll = {
      for (final s in _students) _normalizeRoll(s.rollNo): s,
    };
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;

    final direct = byRoll[_normalizeRoll(trimmed)];
    if (direct != null) return direct;

    final extracted = _rollFromPayload(trimmed);
    if (extracted.isNotEmpty) {
      final match = byRoll[_normalizeRoll(extracted)];
      if (match != null) return match;
    }

    // Pipe-separated tokens: any part that equals a roll in this hall.
    if (trimmed.contains('|')) {
      for (final part in trimmed.split('|')) {
        final match = byRoll[_normalizeRoll(part)];
        if (match != null) return match;
      }
    }
    return null;
  }

  /// The CSEXAM seat token (parts[3]) when the payload is a seat QR, else ''.
  String _tokenFromPayload(String raw) {
    final parts = raw.split('|').map((p) => p.trim()).toList();
    if (parts.length >= 4 &&
        parts[0].toUpperCase() == 'CSEXAM' &&
        parts[1].toUpperCase() == 'QPATT') {
      return parts[3].toUpperCase();
    }
    return '';
  }

  /// Best-effort roll extraction: the roll part of a CSEXAM seat token, a JSON
  /// roll field, or the plain payload itself when it looks like a roll number
  /// (e.g. a student ID card QR that renders just the roll).
  String _rollFromPayload(String raw) {
    final trimmed = raw.trim();
    final parts = trimmed.split('|').map((p) => p.trim()).toList();
    if (parts.length >= 8 &&
        parts[0].toUpperCase() == 'CSEXAM' &&
        parts[1].toUpperCase() == 'QPATT') {
      return parts[7];
    }
    final rollKey = RegExp(
      '"(?:rollNo|roll_no|roll|rollno)"\\s*:\\s*"?([^",}]+)',
      caseSensitive: false,
    ).firstMatch(trimmed);
    if (rollKey != null) {
      return (rollKey.group(1) ?? '').trim();
    }
    if (!trimmed.contains('|') &&
        !trimmed.contains('{') &&
        RegExp(r'^[A-Za-z0-9\-/]+$').hasMatch(trimmed)) {
      return trimmed;
    }
    return '';
  }

  /// Seat info pulled from a scanned CSEXAM|QPATT payload, if any.
  ({String hall, int col, int chair})? _seatFromPayload(String raw) {
    final parts = raw.split('|').map((p) => p.trim()).toList();
    if (parts.length < 7 ||
        parts[0].toUpperCase() != 'CSEXAM' ||
        parts[1].toUpperCase() != 'QPATT') {
      return null;
    }
    return (
      hall: parts[6],
      col: parts.length > 8 ? int.tryParse(parts[8]) ?? 0 : 0,
      chair: parts.length > 9 ? int.tryParse(parts[9]) ?? 0 : 0,
    );
  }

  void _handleCapture(BarcodeCapture capture) {
    final now = DateTime.now();
    if (now.isBefore(_scanCooldownUntil)) return;
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    _scanCooldownUntil = now.add(const Duration(milliseconds: 1200));
    unawaited(_processScan(raw));
  }

  /// One scanned QR → mark the student present (the proven QR-attendance
  /// behaviour). The student is either already in the sheet (seeded halls) or
  /// resolved from the bundled seed and added on the spot (dynamic halls).
  Future<void> _processScan(String raw) async {
    final selected = widget.selectedClass;

    // 1. Already in this sheet? Mark present right away.
    final student = _matchStudent(raw);
    if (student != null) {
      // Strict per-class: a student from another paper must NOT be marked here.
      if (selected != null && !_inSelectedClass(student)) {
        final other = student.classGroup.isEmpty
            ? 'another class'
            : student.classGroup;
        _flash(
          'OTHER PAPER: ${student.rollNo} belongs to $other, not ${selected.program}.',
          ok: false,
        );
        unawaited(_speak('Warning. Other paper'));
        return;
      }
      if (_present.contains(student.studentId)) {
        _flash('Already marked: ${student.rollNo}', ok: true);
        unawaited(_speak('Already marked'));
        return;
      }
      await _markPresent(student, rawPayload: raw);
      return;
    }

    // 2. Not in the sheet yet — resolve from the seat QR / seating-plan seed.
    // This is the normal path when the hall was opened from a stats-only QR
    // (the roster starts empty and fills as answer-sheet/seat QRs are scanned).
    // The teacher picked the class, so the student is added under it; wrong
    // PAPER is only flagged when the roster already knows the student belongs
    // to another class (handled in step 1 above).
    final token = _tokenFromPayload(raw);
    final seat = _seatFromPayload(raw);
    final payloadRoll = _rollFromPayload(raw);
    if (token.isEmpty && seat == null && payloadRoll.isEmpty) {
      _flash('Not a recognised student QR.', ok: false);
      return;
    }

    final seedHit = await _database.lookupSeedStudent(
      token: token,
      rollNo: payloadRoll,
    );
    final roll = payloadRoll.isNotEmpty ? payloadRoll : (seedHit?.rollNo ?? '');
    if (roll.isEmpty) {
      _flash('QR has no roll number.', ok: false);
      return;
    }

    // 3. Verify the student belongs to THIS hall (when the QR/seed says so).
    final hallName = _stats?.hallName ?? '';
    final scannedHall = (seat?.hall.isNotEmpty ?? false)
        ? seat!.hall
        : (seedHit?.hall ?? '');
    if (hallName.isNotEmpty &&
        scannedHall.isNotEmpty &&
        _normHall(scannedHall) != _normHall(hallName)) {
      _flash('QR is for hall $scannedHall, not $hallName.', ok: false);
      return;
    }

    // 4. Add to the live sheet, present, with the best seat we have.
    final col = (seat?.col ?? 0) > 0 ? seat!.col : (seedHit?.colNo ?? 0);
    final chair = (seat?.chair ?? 0) > 0 ? seat!.chair : (seedHit?.chairNo ?? 0);
    final hallForLabel = scannedHall.isEmpty ? hallName : scannedHall;
    final seatLabel = col > 0
        ? 'Hall $hallForLabel | Col $col | Chair $chair'
        : (seedHit?.seatLabel ?? '');
    await _database.addAttendanceRecord(
      sheetId: widget.sheetId,
      rollNo: roll,
      studentName: seedHit?.name ?? '',
      status: 'present',
      colNo: col,
      chairNo: chair,
      seatLabel: seatLabel,
      classGroup: _classLabel,
    );
    await _refreshStudents();
    if (!mounted) return;
    final name = seedHit?.name ?? '';
    _undoStudentId = 'STU$roll';
    _undoRoll = roll;
    _undoWasDynamic = true;
    _flash('Present: $roll${name.isEmpty ? '' : ' • $name'}', ok: true);
    unawaited(_speak(_scanPrompt(roll)));
  }

  void _flash(String message, {required bool ok}) {
    if (!mounted) return;
    setState(() {
      _scanOk = ok;
      _scanMessage = message;
    });
  }

  Future<void> _markPresent(
    ExamAttendanceStudent student, {
    String? rawPayload,
  }) async {
    setState(() {
      _present.add(student.studentId);
      _undoStudentId = student.studentId;
      _undoRoll = student.rollNo;
      _undoWasDynamic = false;
      _scanOk = true;
      _scanMessage = 'Present: ${student.rollNo} • ${student.studentName}';
    });
    unawaited(_speak(_scanPrompt(student.rollNo)));
    // If the scan carries the seat and we don't know it yet, store it so the
    // skeleton can place the student on the real hall grid.
    final seat = rawPayload == null ? null : _seatFromPayload(rawPayload);
    final needsSeat = !student.hasSeat && seat != null && seat.col > 0;
    await _database.markAttendanceStatus(
      sheetId: widget.sheetId,
      studentId: student.studentId,
      status: 'present',
      colNo: needsSeat ? seat.col : 0,
      chairNo: needsSeat ? seat.chair : 0,
      seatLabel: needsSeat
          ? 'Hall ${seat.hall} | Col ${seat.col} | Chair ${seat.chair}'
          : '',
      classGroup: _classLabel,
    );
    if (needsSeat) {
      await _refreshStudents();
    }
  }

  /// Re-reads the student list (after a dynamic add or seat update) without
  /// flashing the loading state; keeps the present set in sync with the DB.
  Future<void> _refreshStudents() async {
    final students = await _database.loadAttendanceStudents(widget.sheetId);
    if (!mounted) return;
    setState(() {
      _students = students;
      _present
        ..clear()
        ..addAll(
          students.where((s) => s.status == 'present').map((s) => s.studentId),
        );
    });
  }

  Future<void> _unmarkPresent(ExamAttendanceStudent student) async {
    setState(() {
      _present.remove(student.studentId);
      _scanOk = true;
      _scanMessage = 'Marked absent: ${student.rollNo}';
    });
    await _database.markAttendanceStatus(
      sheetId: widget.sheetId,
      studentId: student.studentId,
      status: 'absent',
    );
  }

  /// Fully removes a scanned student (used when a QR was scanned by mistake).
  Future<void> _deleteScan(ExamAttendanceStudent student) async {
    await _database.removeAttendanceRecord(
      sheetId: widget.sheetId,
      studentId: student.studentId,
    );
    if (_undoStudentId == student.studentId) _undoStudentId = null;
    await _refreshStudents();
    final cases = await _database.loadUfmCases(widget.sheetId);
    if (!mounted) return;
    setState(() {
      _ufmCases = cases;
      _scanOk = true;
      _scanMessage = 'Deleted scan: ${student.rollNo}';
    });
    unawaited(_speak('Deleted'));
  }

  /// Reverts the most recent scan in one tap — deletes it if it was added by
  /// scanning (dynamic), otherwise just marks the roster student absent.
  Future<void> _undoLast() async {
    final id = _undoStudentId;
    if (id == null) return;
    final match = _students.where((s) => s.studentId == id).toList();
    final student = match.isEmpty
        ? ExamAttendanceStudent(
            studentId: id,
            studentName: '',
            rollNo: _undoRoll,
            status: 'present',
          )
        : match.first;
    setState(() => _undoStudentId = null);
    if (_undoWasDynamic) {
      await _deleteScan(student);
    } else {
      await _unmarkPresent(student);
    }
    if (!mounted) return;
    setState(() => _scanMessage = 'Undone: ${student.rollNo}');
  }

  /// Tapping a present student offers: mark absent, delete the scan, or UFM.
  Future<void> _showPresentActions(ExamAttendanceStudent student) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text(
                '${student.rollNo} — ${student.studentName}',
                style: const TextStyle(fontWeight: FontWeight.w800),
              ),
              subtitle: const Text('What do you want to do?'),
            ),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.cancel_outlined, color: Color(0xFF475569)),
              title: const Text('Mark absent'),
              onTap: () => Navigator.pop(ctx, 'absent'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFB91C1C)),
              title: const Text('Delete scan (scanned by mistake)'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
            ListTile(
              leading: const Icon(Icons.gavel_rounded, color: Color(0xFFB45309)),
              title: const Text('Record UFM case'),
              onTap: () => Navigator.pop(ctx, 'ufm'),
            ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'absent':
        await _unmarkPresent(student);
        break;
      case 'delete':
        await _deleteScan(student);
        break;
      case 'ufm':
        await _openUfmDialogFor(student);
        break;
    }
  }

  // ----------------------------------------------------------------- finish
  Future<void> _finish() async {
    final selectedClass = widget.selectedClass;
    // Finish only the class being scanned (whole hall when none selected).
    final scopedStudents = selectedClass == null
        ? _students
        : _students.where(_inSelectedClass).toList(growable: false);
    final presentCount = scopedStudents
        .where((s) => _present.contains(s.studentId))
        .length;
    final baseExpected = selectedClass?.count ?? (_stats?.totalStudents ?? 0);
    final expectedTotal = baseExpected > scopedStudents.length
        ? baseExpected
        : scopedStudents.length;
    final remaining = expectedTotal - presentCount > 0
        ? expectedTotal - presentCount
        : 0;
    final scopeLabel = selectedClass == null
        ? 'this hall'
        : selectedClass.program;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          selectedClass == null
              ? 'Finish attendance?'
              : 'Finish ${selectedClass.program}?',
        ),
        content: Text(
          remaining == 0
              ? 'All students of $scopeLabel are marked present. Save and close?'
              : '$remaining student(s) of $scopeLabel were not scanned. They will count as ABSENT. Continue?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Finish'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _finishing = true);
    try {
      // Only finalize the scoped students so other classes in the hall are
      // left untouched.
      await _database.saveAttendanceStatuses(
        sheetId: widget.sheetId,
        statusesByStudentId: {
          for (final s in scopedStudents)
            s.studentId: _present.contains(s.studentId) ? 'present' : 'absent',
        },
      );
      final stats = await _database.loadExamHallStats(widget.sheetId);
      if (!mounted) return;
      widget.onFinished(stats);
    } finally {
      if (mounted) setState(() => _finishing = false);
    }
  }

  // -------------------------------------------------------------------- UFM
  Future<void> _addUfmCase({
    required ExamAttendanceStudent student,
    required String allegation,
    required String details,
  }) async {
    await _database.addUfmCase(
      sheetId: widget.sheetId,
      studentId: student.studentId,
      allegation: allegation,
      details: details,
    );
    final cases = await _database.loadUfmCases(widget.sheetId);
    if (!mounted) return;
    setState(() => _ufmCases = cases);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('UFM recorded for ${student.rollNo}.')),
    );
  }

  Future<void> _removeUfmCase(UfmCase ufmCase) async {
    await _database.deleteUfmCase(ufmCase.id);
    final cases = await _database.loadUfmCases(widget.sheetId);
    if (!mounted) return;
    setState(() => _ufmCases = cases);
  }

  Future<void> _openUfmDialogFor(ExamAttendanceStudent student) async {
    final result = await showDialog<({String allegation, String details})>(
      context: context,
      builder: (ctx) => _UfmDialog(student: student),
    );
    if (result == null) return;
    await _addUfmCase(
      student: student,
      allegation: result.allegation,
      details: result.details,
    );
  }

  // -------------------------------------------------------------------- UI
  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final error = _loadError;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(error, textAlign: TextAlign.center),
        ),
      );
    }
    final stats = _stats!;
    final selectedClass = widget.selectedClass;
    // Scope everything to the selected class when taking attendance one class
    // at a time; otherwise the whole hall.
    final viewStudents = selectedClass == null
        ? _students
        : _students.where(_inSelectedClass).toList(growable: false);
    final presentCount = viewStudents
        .where((s) => _present.contains(s.studentId))
        .length;
    // Dynamic halls/classes can expect more students than currently have
    // records (they join scan by scan).
    final baseExpected = selectedClass?.count ?? stats.totalStudents;
    final expectedTotal = baseExpected > viewStudents.length
        ? baseExpected
        : viewStudents.length;
    final remaining = expectedTotal - presentCount > 0
        ? expectedTotal - presentCount
        : 0;
    final headerTitle = selectedClass == null
        ? stats.courseName
        : selectedClass.program;
    final headerSub = selectedClass == null
        ? '${stats.hallName} • live attendance'
        : '${stats.hallName} • ${selectedClass.subject.isEmpty ? 'class attendance' : selectedClass.subject}';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              IconButton(
                tooltip: 'Back',
                onPressed: widget.onBack,
                icon: const Icon(Icons.arrow_back_rounded),
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headerTitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    Text(
                      headerSub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: PortalColors.subtleText,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              FilledButton.icon(
                onPressed: _finishing ? null : _finish,
                icon: _finishing
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.flag_rounded, size: 18),
                label: const Text('Finish'),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _CountPill(
                label: 'Present',
                value: '$presentCount',
                color: const Color(0xFF047857),
                background: const Color(0xFFD1FAE5),
              ),
              const SizedBox(width: 8),
              _CountPill(
                label: 'Remaining',
                value: '$remaining',
                color: const Color(0xFF475569),
                background: const Color(0xFFE2E8F0),
              ),
              const SizedBox(width: 8),
              _CountPill(
                label: 'UFM',
                value: '${_ufmCases.length}',
                color: const Color(0xFFB45309),
                background: const Color(0xFFFEF3C7),
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: _TabToggle(
            current: _tab,
            onChanged: (value) => setState(() => _tab = value),
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: IndexedStack(
            index: _tab,
            children: [
              _buildScanTab(viewStudents),
              _buildUfmTab(viewStudents),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildScanTab(List<ExamAttendanceStudent> viewStudents) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 760;
        final camera = _CameraPanel(
          controller: _scanner!,
          onDetect: _handleCapture,
          message: _scanMessage,
          ok: _scanOk,
          canUndo: _undoStudentId != null,
          onUndo: _undoLast,
        );
        final grid = _SeatGrid(
          stats: _stats!,
          onlyClass: widget.selectedClass,
          students: viewStudents,
          present: _present,
          ufmStudentIds: _ufmCases.map((c) => c.studentId).toSet(),
          onTap: (student) {
            if (_present.contains(student.studentId)) {
              _showPresentActions(student);
            } else {
              _markPresent(student);
            }
          },
          onLongPress: _openUfmDialogFor,
        );
        if (wide) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(width: 320, child: camera),
                const SizedBox(width: 12),
                Expanded(child: grid),
              ],
            ),
          );
        }
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Column(
            children: [
              SizedBox(height: 210, child: camera),
              const SizedBox(height: 10),
              Expanded(child: grid),
            ],
          ),
        );
      },
    );
  }

  Widget _buildUfmTab(List<ExamAttendanceStudent> viewStudents) {
    return _UfmTab(
      students: viewStudents,
      cases: _ufmCases,
      onAdd: (student, allegation, details) =>
          _addUfmCase(student: student, allegation: allegation, details: details),
      onRemove: _removeUfmCase,
    );
  }
}

// ---------------------------------------------------------------- widgets

class _TabToggle extends StatelessWidget {
  const _TabToggle({required this.current, required this.onChanged});

  final int current;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final items = const [
      (icon: Icons.qr_code_scanner_rounded, label: 'Scan & Seats'),
      (icon: Icons.gavel_rounded, label: 'UFM Cases'),
    ];
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          for (var i = 0; i < items.length; i++)
            Expanded(
              child: GestureDetector(
                onTap: () => onChanged(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  decoration: BoxDecoration(
                    color: current == i ? Colors.white : Colors.transparent,
                    borderRadius: BorderRadius.circular(11),
                    boxShadow: current == i
                        ? [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.06),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ]
                        : const [],
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        items[i].icon,
                        size: 17,
                        color: current == i
                            ? PortalColors.brandBlue
                            : PortalColors.subtleText,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12.5,
                          color: current == i
                              ? PortalColors.brandBlue
                              : PortalColors.subtleText,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _CameraPanel extends StatelessWidget {
  const _CameraPanel({
    required this.controller,
    required this.onDetect,
    required this.message,
    required this.ok,
    required this.canUndo,
    required this.onUndo,
  });

  final MobileScannerController controller;
  final ValueChanged<BarcodeCapture> onDetect;
  final String? message;
  final bool ok;
  final bool canUndo;
  final VoidCallback onUndo;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(controller: controller, onDetect: onDetect),
                const _ScannerFocusFrame(),
              ],
            ),
          ),
        ),
        if (message != null) ...[
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color:
                        ok ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: ok
                          ? const Color(0xFF047857)
                          : const Color(0xFFB91C1C),
                    ),
                  ),
                ),
              ),
              if (canUndo) ...[
                const SizedBox(width: 6),
                Material(
                  color: const Color(0xFFFFE4E6),
                  borderRadius: BorderRadius.circular(10),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: onUndo,
                    child: const Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.undo_rounded,
                              size: 15, color: Color(0xFFB91C1C)),
                          SizedBox(width: 4),
                          Text(
                            'Undo',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFB91C1C),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ],
    );
  }
}

/// A white rounded focus box over the camera so the invigilator knows where to
/// hold the QR (same idea as the standalone scanner's frame).
class _ScannerFocusFrame extends StatelessWidget {
  const _ScannerFocusFrame();

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Center(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final side = constraints.biggest.shortestSide * 0.62;
            return Container(
              width: side,
              height: side,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 8,
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

// One distinct colour per class/section sharing the hall.
const List<Color> _classPalette = [
  Color(0xFF2563EB), // blue
  Color(0xFF7C3AED), // violet
  Color(0xFF0D9488), // teal
  Color(0xFFDB2777), // pink
  Color(0xFFEA580C), // orange
  Color(0xFF4F46E5), // indigo
  Color(0xFF0EA5E9), // sky
  Color(0xFFCA8A04), // amber
];

Color _classColor(int index) => _classPalette[index % _classPalette.length];

/// The leading program code of a roll/program (e.g. "BSCS" from "BSCS-F25-101"
/// or "BSCS 2A"), used to colour a student by their class.
String _programCode(String value) {
  final match = RegExp(r'^[A-Za-z]+').firstMatch(value.trim());
  return (match?.group(0) ?? '').toUpperCase();
}

/// The hall "skeleton". When the HALL QR lists the classes sharing the hall,
/// it draws one colour-coded block of seats per class immediately on fetch
/// (filling green as students scan). Otherwise it draws the real Col×Chair
/// matrix (seeded halls) or a simple flowing grid.
class _SeatGrid extends StatelessWidget {
  const _SeatGrid({
    required this.stats,
    required this.students,
    required this.present,
    required this.ufmStudentIds,
    required this.onTap,
    required this.onLongPress,
    this.onlyClass,
  });

  final ExamHallStats stats;
  final List<ExamAttendanceStudent> students;
  final Set<String> present;
  final Set<String> ufmStudentIds;
  final ValueChanged<ExamAttendanceStudent> onTap;
  final ValueChanged<ExamAttendanceStudent> onLongPress;

  /// When set, only this one class's block is drawn (per-class attendance),
  /// but coloured by its real position in the full hall so the colour matches
  /// the hall-stats card.
  final ExamClassGroup? onlyClass;

  /// The class blocks to draw: just the selected class, or every class.
  List<ExamClassGroup> get _renderGroups =>
      onlyClass != null ? [onlyClass!] : stats.classGroups;

  /// The palette index for a class — its position in the full hall list — so a
  /// class keeps the same colour whether shown alone or with the others.
  int _colorIndexOf(ExamClassGroup group) {
    final idx = stats.classGroups.indexWhere((g) => g.program == group.program);
    return idx >= 0 ? idx : 0;
  }

  @override
  Widget build(BuildContext context) {
    final groups = _renderGroups;
    final blockCapacity = onlyClass != null
        ? onlyClass!.count
        : stats.totalStudents;
    final expectedTotal = blockCapacity > students.length
        ? blockCapacity
        : students.length;
    final hasRealSeats = students.any((s) => s.hasSeat);
    // Show the colour-coded class blocks whenever there are classes and the
    // roster is still filling (the dynamic-hall case the user wants).
    final useBlocks = groups.isNotEmpty && students.length < expectedTotal;

    Widget body;
    if (useBlocks) {
      body = _buildClassBlocks(context);
    } else if (students.isEmpty) {
      body = const Center(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Text(
            "No students yet — scan each student's QR to mark them present.",
            textAlign: TextAlign.center,
            style: TextStyle(color: PortalColors.subtleText),
          ),
        ),
      );
    } else if (hasRealSeats) {
      body = _buildHallMatrix(context);
    } else {
      body = _buildFlowGrid();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      padding: const EdgeInsets.all(10),
      child: groups.isEmpty
          ? body
          : Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _ClassLegend(
                  groups: groups,
                  present: _presentByGroup(),
                  colors: [for (final g in groups) _classColor(_colorIndexOf(g))],
                ),
                const SizedBox(height: 8),
                Expanded(child: body),
              ],
            ),
    );
  }

  Color? _colorForStudent(ExamAttendanceStudent student) {
    final groups = _renderGroups;
    if (groups.isEmpty) return null;
    // Exact class match first (set when the QR carries the seat map or the
    // scan was taken class-by-class) — tells same-prefix classes apart.
    if (student.classGroup.isNotEmpty) {
      for (final group in groups) {
        if (group.program == student.classGroup) {
          return _classColor(_colorIndexOf(group));
        }
      }
    }
    final code = _programCode(student.rollNo);
    for (final group in groups) {
      if (group.code == code) {
        return _classColor(_colorIndexOf(group));
      }
    }
    // Per-class screen: attribute to the selected class regardless of prefix.
    if (onlyClass != null) {
      return _classColor(_colorIndexOf(onlyClass!));
    }
    return null;
  }

  /// Present students grouped into their class block by program code +
  /// remaining capacity. Returns (per-group lists, leftover) keyed by the index
  /// within [_renderGroups].
  (Map<int, List<ExamAttendanceStudent>>, List<ExamAttendanceStudent>)
  _distribute() {
    final groups = _renderGroups;
    final buckets = <int, List<ExamAttendanceStudent>>{
      for (var i = 0; i < groups.length; i++) i: [],
    };
    final extra = <ExamAttendanceStudent>[];
    final presentStudents = students
        .where((s) => present.contains(s.studentId))
        .toList(growable: false);
    for (final student in presentStudents) {
      // Per-class screen: every scoped present student belongs to that class.
      if (onlyClass != null) {
        buckets[0]!.add(student);
        continue;
      }
      // Exact class match first — set by full-detail QRs / per-class scans.
      if (student.classGroup.isNotEmpty) {
        final exact = groups.indexWhere(
          (g) => g.program == student.classGroup,
        );
        if (exact >= 0) {
          buckets[exact]!.add(student);
          continue;
        }
      }
      final code = _programCode(student.rollNo);
      int? target;
      for (var i = 0; i < groups.length; i++) {
        final group = groups[i];
        if (group.code == code && buckets[i]!.length < group.count) {
          target = i;
          break;
        }
      }
      if (target != null) {
        buckets[target]!.add(student);
      } else {
        extra.add(student);
      }
    }
    return (buckets, extra);
  }

  List<int> _presentByGroup() {
    final (buckets, _) = _distribute();
    return [
      for (var i = 0; i < _renderGroups.length; i++) buckets[i]?.length ?? 0,
    ];
  }

  /// One colour-coded block of seats per class, sized to the class count and
  /// filling green as that class's students scan in.
  Widget _buildClassBlocks(BuildContext context) {
    final groups = _renderGroups;
    final (buckets, extra) = _distribute();
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (var i = 0; i < groups.length; i++)
          _classSection(
            color: _classColor(_colorIndexOf(groups[i])),
            group: groups[i],
            filled: buckets[i] ?? const [],
          ),
        if (extra.isNotEmpty)
          _classSection(
            color: _classColor(stats.classGroups.length),
            group: ExamClassGroup(
              program: 'Other',
              subject: '',
              faculty: '',
              count: extra.length,
            ),
            filled: extra,
          ),
      ],
    );
  }

  Widget _classSection({
    required Color color,
    required ExamClassGroup group,
    required List<ExamAttendanceStudent> filled,
  }) {
    final capacity = group.count > filled.length ? group.count : filled.length;
    final placeholders = capacity - filled.length;
    final title = group.subject.isEmpty
        ? group.program
        : '${group.program} • ${group.subject}';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13,
                    color: PortalColors.textPrimary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  '${filled.length}/$capacity',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 11.5,
                    color: color,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final student in filled) _miniSeat(student, color),
              for (var i = 0; i < placeholders; i++) _placeholderSeat(color),
            ],
          ),
        ],
      ),
    );
  }

  /// A small filled seat in a class block: roll + present tick, class colour.
  Widget _miniSeat(ExamAttendanceStudent student, Color color) {
    final hasUfm = ufmStudentIds.contains(student.studentId);
    return GestureDetector(
      onTap: () => onTap(student),
      onLongPress: () => onLongPress(student),
      child: Container(
        width: 70,
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color, width: 1.4),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                student.rollNo,
                maxLines: 1,
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w800,
                  color: color,
                ),
              ),
            ),
            const SizedBox(height: 2),
            Icon(
              hasUfm ? Icons.warning_amber_rounded : Icons.check_circle_rounded,
              size: 14,
              color: hasUfm ? const Color(0xFFB45309) : color,
            ),
          ],
        ),
      ),
    );
  }

  /// A faint empty seat in a class block (not yet scanned).
  Widget _placeholderSeat(Color color) {
    return Container(
      width: 70,
      height: 44,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.30)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.event_seat_outlined,
        size: 16,
        color: color.withValues(alpha: 0.45),
      ),
    );
  }

  /// True hall skeleton: a Col × Chair matrix exactly like the seating plan.
  /// Unassigned positions render as faint empty seats.
  Widget _buildHallMatrix(BuildContext context) {
    var maxCol = 0;
    var maxChair = 0;
    final byPosition = <String, ExamAttendanceStudent>{};
    final unseated = <ExamAttendanceStudent>[];
    for (final student in students) {
      if (student.hasSeat) {
        if (student.colNo > maxCol) maxCol = student.colNo;
        if (student.chairNo > maxChair) maxChair = student.chairNo;
        byPosition['${student.colNo}|${student.chairNo}'] = student;
      } else {
        unseated.add(student);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 6.0;
        final fitWidth =
            (constraints.maxWidth - (maxCol - 1) * spacing) / maxCol;
        final cellWidth = fitWidth.clamp(56.0, 96.0);
        final gridWidth = cellWidth * maxCol + spacing * (maxCol - 1);
        final grid = SizedBox(
          width: gridWidth,
          child: GridView.builder(
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: maxCol,
              mainAxisSpacing: spacing,
              crossAxisSpacing: spacing,
              childAspectRatio: 0.95,
            ),
            itemCount: maxCol * maxChair,
            itemBuilder: (context, index) {
              final col = index % maxCol + 1;
              final chair = index ~/ maxCol + 1;
              final student = byPosition['$col|$chair'];
              if (student == null) {
                return _EmptySeatCell(label: 'C$col·$chair');
              }
              return _seatCell(student, 'C$col·$chair');
            },
          ),
        );
        final scrollable = gridWidth > constraints.maxWidth
            ? SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: grid,
              )
            : Center(child: grid);
        if (unseated.isEmpty) {
          return scrollable;
        }
        // Rare: a few students without a seat in the plan — show them below.
        return Column(
          children: [
            Expanded(child: scrollable),
            const SizedBox(height: 8),
            SizedBox(
              height: 76,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (final student in unseated)
                    Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: SizedBox(
                        width: 80,
                        child: _seatCell(student, 'No seat'),
                      ),
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  /// Fallback when the sheet has no seating-plan data: simple flowing grid in
  /// roll order.
  Widget _buildFlowGrid() {
    return GridView.builder(
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: 86,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
        childAspectRatio: 0.92,
      ),
      itemCount: students.length,
      itemBuilder: (context, index) =>
          _seatCell(students[index], 'S${index + 1}'),
    );
  }

  Widget _seatCell(ExamAttendanceStudent student, String seatText) {
    final isPresent = present.contains(student.studentId);
    final hasUfm = ufmStudentIds.contains(student.studentId);
    final accent = _colorForStudent(student) ?? const Color(0xFF059669);
    return GestureDetector(
      onTap: () => onTap(student),
      onLongPress: () => onLongPress(student),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        decoration: BoxDecoration(
          color: isPresent
              ? accent.withValues(alpha: 0.14)
              : const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isPresent ? accent : PortalColors.cardBorder,
            width: isPresent ? 1.6 : 1,
          ),
        ),
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    seatText,
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: PortalColors.subtleText,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        student.rollNo,
                        maxLines: 1,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: isPresent ? accent : PortalColors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Icon(
                    isPresent
                        ? Icons.check_circle_rounded
                        : Icons.event_seat_outlined,
                    size: 15,
                    color: isPresent ? accent : const Color(0xFF94A3B8),
                  ),
                ],
              ),
            ),
            if (hasUfm)
              Positioned(
                top: 4,
                right: 4,
                child: Container(
                  width: 10,
                  height: 10,
                  decoration: const BoxDecoration(
                    color: Color(0xFFF59E0B),
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// A seat that exists in the hall grid but has no student assigned.
class _EmptySeatCell extends StatelessWidget {
  const _EmptySeatCell({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFFCFCFD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEDF0F5)),
      ),
      alignment: Alignment.center,
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w600,
          color: Color(0xFFB6BFCC),
        ),
      ),
    );
  }
}

/// A compact legend — one colour chip per class sharing the hall, with the
/// present/total count, so the two (or more) classes are visually distinct.
class _ClassLegend extends StatelessWidget {
  const _ClassLegend({
    required this.groups,
    required this.present,
    required this.colors,
  });

  final List<ExamClassGroup> groups;

  /// Present count per group, indexed the same as [groups].
  final List<int> present;

  /// Colour per group, indexed the same as [groups].
  final List<Color> colors;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (var i = 0; i < groups.length; i++)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
            decoration: BoxDecoration(
              color: colors[i].withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: colors[i].withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 9,
                  height: 9,
                  decoration: BoxDecoration(
                    color: colors[i],
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  '${groups[i].program} '
                  '(${i < present.length ? present[i] : 0}/${groups[i].count})',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: colors[i],
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _CountPill extends StatelessWidget {
  const _CountPill({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
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

/// UFM tab: pick a student, choose the allegation, optional details, add —
/// strictly one case at a time. Existing cases are listed below.
class _UfmTab extends StatefulWidget {
  const _UfmTab({
    required this.students,
    required this.cases,
    required this.onAdd,
    required this.onRemove,
  });

  final List<ExamAttendanceStudent> students;
  final List<UfmCase> cases;
  final Future<void> Function(
    ExamAttendanceStudent student,
    String allegation,
    String details,
  ) onAdd;
  final ValueChanged<UfmCase> onRemove;

  @override
  State<_UfmTab> createState() => _UfmTabState();
}

class _UfmTabState extends State<_UfmTab> {
  String? _studentId;
  String _allegation = ufmAllegationOptions.first;
  final _detailsController = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      children: [
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Record UFM case',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  color: PortalColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              const Text(
                'Ek waqt me ek case — select the student, then what they are accused of.',
                style: TextStyle(
                  color: PortalColors.subtleText,
                  fontSize: 12.5,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _studentId,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Student',
                  prefixIcon: Icon(Icons.person_search_outlined),
                ),
                items: [
                  for (final student in widget.students)
                    DropdownMenuItem(
                      value: student.studentId,
                      child: Text(
                        '${student.rollNo} — ${student.studentName}',
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (value) => setState(() => _studentId = value),
              ),
              const SizedBox(height: 12),
              const Text(
                'ALLEGATION',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.8,
                  color: PortalColors.subtleText,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final option in ufmAllegationOptions)
                    ChoiceChip(
                      selected: _allegation == option,
                      label: Text(option),
                      onSelected: (_) => setState(() => _allegation = option),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _detailsController,
                minLines: 1,
                maxLines: 3,
                decoration: InputDecoration(
                  labelText: _allegation == 'Other'
                      ? 'Details (required for Other)'
                      : 'Details (optional)',
                  prefixIcon: const Icon(Icons.notes_outlined),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _submit,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.gavel_rounded, size: 18),
                  label: Text(_saving ? 'Saving…' : 'Add UFM case'),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          'RECORDED CASES (${widget.cases.length})',
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.8,
            color: PortalColors.subtleText,
          ),
        ),
        const SizedBox(height: 8),
        if (widget.cases.isEmpty)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFF8FAFC),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: const Text(
              'No UFM cases recorded for this hall.',
              style: TextStyle(color: PortalColors.subtleText),
            ),
          )
        else
          for (final ufmCase in widget.cases)
            Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFFBEB),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFFDE68A)),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.warning_amber_rounded,
                    color: Color(0xFFB45309),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${ufmCase.rollNo} — ${ufmCase.studentName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: PortalColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          ufmCase.details.isEmpty
                              ? ufmCase.allegation
                              : '${ufmCase.allegation} • ${ufmCase.details}',
                          style: const TextStyle(
                            color: Color(0xFF92400E),
                            fontSize: 12.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Remove case',
                    onPressed: () => widget.onRemove(ufmCase),
                    icon: const Icon(Icons.delete_outline_rounded),
                  ),
                ],
              ),
            ),
      ],
    );
  }

  Future<void> _submit() async {
    final studentId = _studentId;
    if (studentId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Select a student first.')),
      );
      return;
    }
    final details = _detailsController.text.trim();
    if (_allegation == 'Other' && details.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Write details for "Other" allegation.')),
      );
      return;
    }
    final student = widget.students.firstWhere(
      (s) => s.studentId == studentId,
    );
    setState(() => _saving = true);
    try {
      await widget.onAdd(student, _allegation, details);
      if (mounted) {
        setState(() {
          _studentId = null;
          _allegation = ufmAllegationOptions.first;
          _detailsController.clear();
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

/// Quick UFM dialog opened by long-pressing a seat in the grid.
class _UfmDialog extends StatefulWidget {
  const _UfmDialog({required this.student});

  final ExamAttendanceStudent student;

  @override
  State<_UfmDialog> createState() => _UfmDialogState();
}

class _UfmDialogState extends State<_UfmDialog> {
  String _allegation = ufmAllegationOptions.first;
  final _detailsController = TextEditingController();

  @override
  void dispose() {
    _detailsController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('UFM — ${widget.student.rollNo}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.student.studentName,
            style: const TextStyle(color: PortalColors.subtleText),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final option in ufmAllegationOptions)
                ChoiceChip(
                  selected: _allegation == option,
                  label: Text(option),
                  onSelected: (_) => setState(() => _allegation = option),
                ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _detailsController,
            minLines: 1,
            maxLines: 3,
            decoration: InputDecoration(
              labelText: _allegation == 'Other'
                  ? 'Details (required)'
                  : 'Details (optional)',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final details = _detailsController.text.trim();
            if (_allegation == 'Other' && details.isEmpty) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Write details for "Other" allegation.'),
                ),
              );
              return;
            }
            Navigator.pop(
              context,
              (allegation: _allegation, details: details),
            );
          },
          child: const Text('Add case'),
        ),
      ],
    );
  }
}
