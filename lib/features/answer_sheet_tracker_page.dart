import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/answer_sheet_repository.dart';
import '../services/cloud_sync_service.dart';
import '../ui/student_portal_shell.dart';

/// Admin module: track answer-sheet custody. Scan a csexam "program stats" /
/// hall QR in **Issue** mode when handing papers to teachers, and in **Return**
/// mode when the marked papers come back. The lists show who is holding papers
/// and who has submitted.
class AnswerSheetTrackerPage extends StatefulWidget {
  const AnswerSheetTrackerPage({super.key});

  @override
  State<AnswerSheetTrackerPage> createState() => _AnswerSheetTrackerPageState();
}

bool get _cameraSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class _AnswerSheetTrackerPageState extends State<AnswerSheetTrackerPage> {
  final _repository = AnswerSheetRepository();
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _pasteController = TextEditingController();

  bool _isReturn = false; // false = Issue, true = Return
  bool _loading = true;
  List<PaperBatch> _batches = const [];
  String? _message;
  bool _ok = true;

  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastCode;

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  @override
  void dispose() {
    _scanner.dispose();
    _pasteController.dispose();
    super.dispose();
  }

  Future<void> _bootstrap() async {
    await _repository.open();
    await _reload();
  }

  Future<void> _reload() async {
    final batches = await _repository.loadAll();
    if (!mounted) return;
    setState(() {
      _batches = batches;
      _loading = false;
    });
  }

  Future<void> _apply(String raw) async {
    final payload = raw.trim();
    if (payload.isEmpty) return;
    try {
      final result = await _repository.recordScan(
        rawPayload: payload,
        isReturn: _isReturn,
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = result.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _message = error is FormatException ? error.message : error.toString();
      });
    }
  }

  Future<void> _openManualEntry() async {
    final result = await showModalBottomSheet<_ManualBatchInput>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ManualEntrySheet(isReturn: _isReturn),
    );
    if (result == null) return;
    try {
      final scanResult = await _repository.recordManualBatch(
        program: result.program,
        subject: result.subject,
        faculty: result.faculty,
        hall: result.hall,
        examDate: result.examDate,
        shift: result.shift,
        count: result.count,
        isReturn: _isReturn,
      );
      await _reload();
      if (!mounted) return;
      setState(() {
        _ok = true;
        _message = scanResult.message;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ok = false;
        _message = error is FormatException ? error.message : error.toString();
      });
    }
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    // Allow the same QR again only after a short pause, or when the mode flips.
    if (raw == _lastCode && now.isBefore(_cooldownUntil)) return;
    _lastCode = raw;
    _cooldownUntil = now.add(const Duration(seconds: 2));
    unawaited(_apply(raw));
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all tracking?'),
        content: const Text(
          'This removes every issued/returned record from this device. The '
          'papers themselves are not affected.',
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
    if (yes != true) return;
    final items = await _repository.clearAll();
    CloudSyncService.instance.pushDeletions(items);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final out = _batches.where((b) => !b.isReturned).toList(growable: false);
    final returned = _batches.where((b) => b.isReturned).toList(growable: false);
    final outPapers = out.fold<int>(0, (sum, b) => sum + b.count);
    final returnedPapers = returned.fold<int>(0, (sum, b) => sum + b.count);

    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(
        title: const Text('Answer Sheets — Marking Tracker'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            onPressed: _batches.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _ModeToggle(
                  isReturn: _isReturn,
                  onChanged: (value) => setState(() {
                    _isReturn = value;
                    _lastCode = null; // let the same QR be scanned in new mode
                  }),
                ),
                const SizedBox(height: 14),
                _ScannerCard(
                  controller: _scanner,
                  onDetect: _onDetect,
                  isReturn: _isReturn,
                  pasteController: _pasteController,
                  onPaste: () {
                    _apply(_pasteController.text);
                    _pasteController.clear();
                  },
                  message: _message,
                  ok: _ok,
                ),
                const SizedBox(height: 12),
                // Fallback when a QR will not scan — type the bundle by hand.
                OutlinedButton.icon(
                  onPressed: _openManualEntry,
                  icon: const Icon(Icons.keyboard_rounded, size: 18),
                  label: Text(
                    _isReturn
                        ? 'Manual entry — return a bundle'
                        : 'Manual entry — issue a bundle',
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    _StatPill(
                      label: 'Out for marking',
                      value: '${out.length}',
                      sub: '$outPapers papers',
                      color: const Color(0xFFB45309),
                      background: const Color(0xFFFEF3C7),
                    ),
                    const SizedBox(width: 10),
                    _StatPill(
                      label: 'Returned',
                      value: '${returned.length}',
                      sub: '$returnedPapers papers',
                      color: const Color(0xFF047857),
                      background: const Color(0xFFD1FAE5),
                    ),
                  ],
                ),
                const SizedBox(height: 18),
                _SectionHeader(
                  icon: Icons.pending_actions_rounded,
                  title: 'Out for marking (with teachers)',
                  count: out.length,
                ),
                const SizedBox(height: 8),
                if (out.isEmpty)
                  const _EmptyHint(
                    'Scan a program/hall QR in Issue mode to hand papers out.',
                  )
                else
                  for (final batch in out)
                    _BatchTile(
                      batch: batch,
                      onTap: () => _toggle(batch),
                    ),
                const SizedBox(height: 18),
                _SectionHeader(
                  icon: Icons.assignment_turned_in_rounded,
                  title: 'Returned (submitted)',
                  count: returned.length,
                ),
                const SizedBox(height: 8),
                if (returned.isEmpty)
                  const _EmptyHint(
                    'Scan in Return mode when a teacher submits their bundle.',
                  )
                else
                  for (final batch in returned)
                    _BatchTile(
                      batch: batch,
                      onTap: () => _toggle(batch),
                    ),
              ],
            ),
    );
  }

  Future<void> _toggle(PaperBatch batch) async {
    await _repository.toggleStatus(batch.id);
    await _reload();
  }
}

/// What the manual-entry sheet returns — the same fields a scanned bundle has.
class _ManualBatchInput {
  const _ManualBatchInput({
    required this.faculty,
    required this.program,
    required this.subject,
    required this.hall,
    required this.examDate,
    required this.shift,
    required this.count,
  });

  final String faculty;
  final String program;
  final String subject;
  final String hall;
  final String examDate;
  final String shift;
  final int count;
}

/// Type a bundle by hand when the QR will not scan. Works for both Issue and
/// Return — the mode is decided by the page's current toggle.
class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({required this.isReturn});

  final bool isReturn;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _formKey = GlobalKey<FormState>();
  final _faculty = TextEditingController();
  final _program = TextEditingController();
  final _subject = TextEditingController();
  final _hall = TextEditingController();
  final _date = TextEditingController();
  final _shift = TextEditingController();
  final _count = TextEditingController();

  @override
  void dispose() {
    _faculty.dispose();
    _program.dispose();
    _subject.dispose();
    _hall.dispose();
    _date.dispose();
    _shift.dispose();
    _count.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    Navigator.pop(
      context,
      _ManualBatchInput(
        faculty: _faculty.text.trim(),
        program: _program.text.trim(),
        subject: _subject.text.trim(),
        hall: _hall.text.trim(),
        examDate: _date.text.trim(),
        shift: _shift.text.trim(),
        count: int.tryParse(_count.text.trim()) ?? 0,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    final verb = widget.isReturn ? 'Return' : 'Issue';
    return Padding(
      padding: EdgeInsets.fromLTRB(18, 18, 18, bottom + 18),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Icon(
                  widget.isReturn
                      ? Icons.move_to_inbox_rounded
                      : Icons.outbox_rounded,
                  color: PortalColors.brandBlue,
                ),
                const SizedBox(width: 8),
                Text(
                  'Manual entry — $verb bundle',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              widget.isReturn
                  ? 'Type the bundle the teacher is returning after marking.'
                  : 'Type the bundle you are handing to the teacher.',
              style: const TextStyle(
                color: PortalColors.subtleText,
                fontSize: 12.5,
              ),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _faculty,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Teacher / faculty',
                prefixIcon: Icon(Icons.person_outline_rounded),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _program,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                labelText: 'Program',
                hintText: 'e.g. BSCS',
                prefixIcon: Icon(Icons.school_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _subject,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Subject',
                prefixIcon: Icon(Icons.menu_book_outlined),
              ),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _count,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                labelText: 'Number of papers',
                prefixIcon: Icon(Icons.tag_rounded),
              ),
              validator: (v) {
                final n = int.tryParse((v ?? '').trim());
                if (n == null || n <= 0) return 'Enter a number greater than 0';
                return null;
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _hall,
                    decoration: const InputDecoration(
                      labelText: 'Hall (optional)',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextFormField(
                    controller: _shift,
                    decoration: const InputDecoration(
                      labelText: 'Shift (optional)',
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _date,
              decoration: const InputDecoration(
                labelText: 'Exam date (optional)',
                hintText: 'e.g. 22-Jun-2026',
                prefixIcon: Icon(Icons.event_outlined),
              ),
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              onPressed: _submit,
              icon: const Icon(Icons.check_rounded, size: 18),
              label: Text('$verb this bundle'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModeToggle extends StatelessWidget {
  const _ModeToggle({required this.isReturn, required this.onChanged});

  final bool isReturn;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          _segment(
            label: 'Issue to teacher',
            icon: Icons.outbox_rounded,
            selected: !isReturn,
            onTap: () => onChanged(false),
          ),
          _segment(
            label: 'Collect / Return',
            icon: Icons.move_to_inbox_rounded,
            selected: isReturn,
            onTap: () => onChanged(true),
          ),
        ],
      ),
    );
  }

  Widget _segment({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: selected ? Colors.white : Colors.transparent,
            borderRadius: BorderRadius.circular(11),
            boxShadow: selected
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
                icon,
                size: 18,
                color: selected
                    ? PortalColors.brandBlue
                    : PortalColors.subtleText,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 12.5,
                    color: selected
                        ? PortalColors.brandBlue
                        : PortalColors.subtleText,
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

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.controller,
    required this.onDetect,
    required this.isReturn,
    required this.pasteController,
    required this.onPaste,
    required this.message,
    required this.ok,
  });

  final MobileScannerController controller;
  final ValueChanged<BarcodeCapture> onDetect;
  final bool isReturn;
  final TextEditingController pasteController;
  final VoidCallback onPaste;
  final String? message;
  final bool ok;

  @override
  Widget build(BuildContext context) {
    final accent = isReturn
        ? const Color(0xFF047857)
        : const Color(0xFFB45309);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            isReturn
                ? 'Scan the QR when a teacher RETURNS marked papers.'
                : 'Scan the QR when you ISSUE papers to a teacher.',
            style: TextStyle(fontWeight: FontWeight.w700, color: accent),
          ),
          const SizedBox(height: 12),
          if (_cameraSupported)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 240,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    MobileScanner(controller: controller, onDetect: onDetect),
                    IgnorePointer(
                      child: Center(
                        child: Container(
                          width: 170,
                          height: 170,
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
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
            controller: pasteController,
            minLines: 1,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Or paste the QR text',
              prefixIcon: Icon(Icons.keyboard_alt_outlined),
            ),
          ),
          const SizedBox(height: 10),
          FilledButton.icon(
            onPressed: onPaste,
            icon: Icon(isReturn ? Icons.move_to_inbox_rounded : Icons.outbox_rounded),
            label: Text(isReturn ? 'Mark returned' : 'Mark issued'),
          ),
          if (message != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: ok ? const Color(0xFFD1FAE5) : const Color(0xFFFEE2E2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                message!,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: ok ? const Color(0xFF047857) : const Color(0xFFB91C1C),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({
    required this.label,
    required this.value,
    required this.sub,
    required this.color,
    required this.background,
  });

  final String label;
  final String value;
  final String sub;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 12),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
            Text(
              sub,
              style: TextStyle(fontSize: 11, color: color.withValues(alpha: 0.8)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.count,
  });

  final IconData icon;
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: PortalColors.subtleText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w800,
              color: PortalColors.textPrimary,
            ),
          ),
        ),
        Text(
          '$count',
          style: const TextStyle(
            fontWeight: FontWeight.w800,
            color: PortalColors.subtleText,
          ),
        ),
      ],
    );
  }
}

class _BatchTile extends StatelessWidget {
  const _BatchTile({required this.batch, required this.onTap});

  final PaperBatch batch;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final time = batch.isReturned ? batch.returnedAt : batch.issuedAt;
    final when = time == null
        ? ''
        : DateFormat('dd MMM, HH:mm').format(time.toLocal());
    final accent = batch.isReturned
        ? const Color(0xFF047857)
        : const Color(0xFFB45309);
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
                CircleAvatar(
                  radius: 22,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  child: Icon(Icons.person_outline_rounded, color: accent),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        batch.teacherLabel,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          if (batch.program.isNotEmpty) batch.program,
                          if (batch.subject.isNotEmpty) batch.subject,
                          if (batch.hall.isNotEmpty) 'Hall ${batch.hall}',
                        ].join('  •  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12,
                        ),
                      ),
                      if (when.isNotEmpty)
                        Text(
                          '${batch.isReturned ? 'Returned' : 'Issued'} $when',
                          style: TextStyle(
                            color: accent,
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        '${batch.count} papers',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11.5,
                          color: accent,
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      batch.isReturned ? 'tap → out' : 'tap → returned',
                      style: const TextStyle(
                        fontSize: 10,
                        color: PortalColors.subtleText,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyHint extends StatelessWidget {
  const _EmptyHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Text(
        text,
        style: const TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
      ),
    );
  }
}
