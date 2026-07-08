import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../services/cloud_sync_service.dart';
import '../services/slot_collection_repository.dart';
import '../ui/student_portal_shell.dart';
import 'complete_attendance_page.dart';
import 'slot_collection_pdf.dart';

/// Admin / exam-cell module: consolidate a whole slot's paper collection.
///
/// 1. Scan the "PER-SLOT QR" on the Overall Seating Summary (csexam) — the slot
///    loads with every program row (expected counts).
/// 2. As each teacher reports, scan their attendance transfer QR (or tap a row
///    and type the numbers) — present / absent / UFM fill in.
/// 3. The totals card shows the running total present / absent / UFM for the
///    slot.
class SlotCollectionPage extends StatefulWidget {
  const SlotCollectionPage({super.key});

  @override
  State<SlotCollectionPage> createState() => _SlotCollectionPageState();
}

bool get _cameraSupported =>
    kIsWeb ||
    defaultTargetPlatform == TargetPlatform.android ||
    defaultTargetPlatform == TargetPlatform.iOS ||
    defaultTargetPlatform == TargetPlatform.macOS;

class _SlotCollectionPageState extends State<SlotCollectionPage> {
  final _repository = SlotCollectionRepository();
  final _scanner = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [BarcodeFormat.qrCode],
  );
  final _pasteController = TextEditingController();

  bool _loading = true;
  List<SlotSummary> _slots = const [];
  String? _currentId;
  List<SlotRow> _rows = const [];
  List<SlotReceipt> _receipts = const [];
  String? _message;
  bool _ok = true;

  DateTime _cooldownUntil = DateTime.fromMillisecondsSinceEpoch(0);
  String? _lastCode;

  SlotSummary? get _current {
    if (_currentId == null) return null;
    for (final s in _slots) {
      if (s.id == _currentId) return s;
    }
    return null;
  }

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
    final slots = await _repository.loadSlots();
    final rows = _currentId == null
        ? <SlotRow>[]
        : await _repository.loadRows(_currentId!);
    final receipts = _currentId == null
        ? <SlotReceipt>[]
        : await _repository.loadReceipts(_currentId!);
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _rows = rows;
      _receipts = receipts;
      _loading = false;
    });
  }

  Future<void> _route(String raw) async {
    final payload = raw.trim();
    if (payload.isEmpty) return;
    try {
      if (payload.startsWith('CSEXAM|QSLOT|1|')) {
        final slot = await _repository.seedFromQr(payload);
        _currentId = slot.id;
        await _reload();
        _setMessage(true, 'Loaded slot ${slot.title} — ${slot.programs} programs.');
      } else if (payload.startsWith('CSEXAM|QATTN|1|')) {
        if (_currentId == null) {
          _setMessage(false, 'Load a slot first: scan the PER-SLOT QR.');
          return;
        }
        final result = await _repository.applyTeacherQr(
          slotId: _currentId!,
          rawPayload: payload,
        );
        await _reload();
        _setMessage(result.matched.isNotEmpty, result.message);
      } else {
        _setMessage(
          false,
          'Not a slot or attendance QR. Scan the PER-SLOT QR or a teacher\'s '
          'attendance transfer QR.',
        );
      }
    } catch (error) {
      _setMessage(
        false,
        error is FormatException ? error.message : error.toString(),
      );
    }
  }

  void _setMessage(bool ok, String message) {
    if (!mounted) return;
    setState(() {
      _ok = ok;
      _message = message;
    });
  }

  void _onDetect(BarcodeCapture capture) {
    final now = DateTime.now();
    final raw = capture.barcodes
        .map((b) => b.rawValue?.trim() ?? '')
        .firstWhere((v) => v.isNotEmpty, orElse: () => '');
    if (raw.isEmpty) return;
    if (raw == _lastCode && now.isBefore(_cooldownUntil)) return;
    _lastCode = raw;
    _cooldownUntil = now.add(const Duration(seconds: 2));
    unawaited(_route(raw));
  }

  Future<void> _editRow(SlotRow row) async {
    final presentCtrl = TextEditingController(
      text: row.received ? '${row.present}' : '',
    );
    final absentCtrl = TextEditingController(
      text: row.received ? '${row.absent}' : '',
    );
    final ufmCtrl = TextEditingController(
      text: row.received ? '${row.ufm}' : '',
    );
    final saved = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(row.program, style: const TextStyle(fontSize: 17)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${row.subject}\nExpected: ${row.expected}',
              style: const TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
            ),
            const SizedBox(height: 14),
            _numField(presentCtrl, 'Present', Icons.how_to_reg_outlined),
            const SizedBox(height: 10),
            _numField(absentCtrl, 'Absent', Icons.person_off_outlined),
            const SizedBox(height: 10),
            _numField(ufmCtrl, 'UFM', Icons.gavel_outlined),
          ],
        ),
        actions: [
          if (row.received)
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Reset'),
            ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == null) return; // cancelled
    if (saved == false) {
      await _repository.resetRow(row.id);
    } else {
      await _repository.setRow(
        rowId: row.id,
        present: int.tryParse(presentCtrl.text.trim()) ?? 0,
        absent: int.tryParse(absentCtrl.text.trim()) ?? 0,
        ufm: int.tryParse(ufmCtrl.text.trim()) ?? 0,
      );
    }
    await _reload();
  }

  Widget _numField(TextEditingController c, String label, IconData icon) {
    return TextField(
      controller: c,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon)),
    );
  }

  Future<void> _confirmClear() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear all slots?'),
        content: const Text(
          'This removes every saved slot and its collected totals from this '
          'device.',
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
    setState(() => _currentId = null);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final current = _current;
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(
        title: const Text('Per-Slot Paper Collection'),
        actions: [
          IconButton(
            tooltip: 'Clear all',
            onPressed: _slots.isEmpty ? null : _confirmClear,
            icon: const Icon(Icons.delete_sweep_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                _ScannerCard(
                  controller: _scanner,
                  onDetect: _onDetect,
                  hasSlot: current != null,
                  pasteController: _pasteController,
                  onPaste: () {
                    _route(_pasteController.text);
                    _pasteController.clear();
                  },
                  message: _message,
                  ok: _ok,
                ),
                const SizedBox(height: 16),
                if (current == null)
                  _slotListSection()
                else
                  _slotDetailSection(current),
              ],
            ),
    );
  }

  // ----- no slot open: list saved slots -----------------------------------

  Widget _slotListSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_slots.isNotEmpty) ...[
          _CompleteAttendanceCard(
            slots: _slots,
            onOpen: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) =>
                    CompleteAttendancePage(repository: _repository),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
        const _SectionHeader(
          icon: Icons.event_note_rounded,
          title: 'Saved slots',
        ),
        const SizedBox(height: 8),
        if (_slots.isEmpty)
          const _EmptyHint(
            'No slots yet. Scan the PER-SLOT QR on the Overall Seating Summary '
            'to load a day/shift.',
          )
        else
          for (final s in _slots)
            _SlotCard(
              summary: s,
              onOpen: () async {
                setState(() => _currentId = s.id);
                await _reload();
                _setMessage(true, 'Opened ${s.title}.');
              },
              onDelete: () async {
                final items = await _repository.deleteSlot(s.id);
                CloudSyncService.instance.pushDeletions(items);
                await _reload();
              },
            ),
      ],
    );
  }

  /// How many papers were expected, how many have arrived, and what % / which
  /// programs are still pending — for the person collecting from invigilators.
  Widget _coverageCard(SlotSummary slot) {
    final accounted = slot.totalPresent + slot.totalAbsent;
    final expected = slot.expected;
    final pct = expected > 0
        ? ((accounted / expected) * 100).clamp(0, 100).round()
        : 0;
    final pending = _rows.where((r) => !r.received).toList();
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFAF4E2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFEADBB0)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Collection coverage',
            style: TextStyle(
              fontWeight: FontWeight.w900,
              color: PortalColors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Expected: $expected papers   •   Received: $accounted   •   '
            'Pending: ${(expected - accounted) < 0 ? 0 : expected - accounted}',
            style: const TextStyle(
              color: PortalColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: expected > 0 ? accounted / expected : 0,
              minHeight: 10,
              backgroundColor: const Color(0xFFE8DCB6),
              color: const Color(0xFF8A6E16),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            '$pct% received   •   programs ${slot.received}/${slot.programs}',
            style: const TextStyle(
              color: PortalColors.subtleText,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          if (pending.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Still awaiting (${pending.length}): '
              '${pending.map((r) => '${r.program}${r.halls.isEmpty ? '' : ' [${r.halls}]'}').join(', ')}',
              style: const TextStyle(
                color: Color(0xFFB45309),
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ],
      ),
    );
  }

  // ----- slot open: detail + rows + totals ---------------------------------

  Widget _slotDetailSection(SlotSummary slot) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                slot.title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                  color: PortalColors.textPrimary,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: _rows.isEmpty
                  ? null
                  : () => shareSlotCollectionPdf(slot: slot, rows: _rows),
              icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
              label: const Text('PDF'),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() => _currentId = null);
                _reload();
              },
              icon: const Icon(Icons.swap_horiz_rounded, size: 18),
              label: const Text('Slots'),
            ),
          ],
        ),
        Text(
          '${slot.programs} programs  •  ${slot.usedHalls} halls  •  '
          'expected ${slot.expected}  •  received ${slot.received}/${slot.programs}',
          style: const TextStyle(color: PortalColors.subtleText, fontSize: 12.5),
        ),
        const SizedBox(height: 14),
        Row(
          children: [
            _TotalPill(
              label: 'Present',
              value: slot.totalPresent,
              color: const Color(0xFF047857),
              background: const Color(0xFFD1FAE5),
            ),
            const SizedBox(width: 8),
            _TotalPill(
              label: 'Absent',
              value: slot.totalAbsent,
              color: const Color(0xFFB45309),
              background: const Color(0xFFFEF3C7),
            ),
            const SizedBox(width: 8),
            _TotalPill(
              label: 'UFM',
              value: slot.totalUfm,
              color: const Color(0xFFB91C1C),
              background: const Color(0xFFFEE2E2),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _coverageCard(slot),
        const SizedBox(height: 18),
        const _SectionHeader(
          icon: Icons.list_alt_rounded,
          title: 'Programs (tap to enter / edit)',
        ),
        const SizedBox(height: 8),
        for (final row in _rows)
          _RowTile(row: row, onTap: () => _editRow(row)),
        const SizedBox(height: 18),
        _SectionHeader(
          icon: Icons.history_rounded,
          title: 'Received log (${_receipts.length})',
        ),
        const SizedBox(height: 8),
        if (_receipts.isEmpty)
          const _EmptyHint(
            'No data received yet. Each teacher scan is logged here with who '
            'handed it over and when.',
          )
        else
          for (final r in _receipts) _ReceiptTile(receipt: r),
      ],
    );
  }
}

class _ScannerCard extends StatelessWidget {
  const _ScannerCard({
    required this.controller,
    required this.onDetect,
    required this.hasSlot,
    required this.pasteController,
    required this.onPaste,
    required this.message,
    required this.ok,
  });

  final MobileScannerController controller;
  final ValueChanged<BarcodeCapture> onDetect;
  final bool hasSlot;
  final TextEditingController pasteController;
  final VoidCallback onPaste;
  final String? message;
  final bool ok;

  @override
  Widget build(BuildContext context) {
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
            hasSlot
                ? 'Scan each teacher\'s attendance QR to fill this slot (or tap '
                      'a program below to type the numbers).'
                : 'Scan the PER-SLOT QR on the Overall Seating Summary to load '
                      'a day/shift.',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              color: PortalColors.brandBlue,
            ),
          ),
          const SizedBox(height: 12),
          if (_cameraSupported)
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                height: 230,
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
            icon: const Icon(Icons.qr_code_scanner_rounded),
            label: const Text('Load from pasted text'),
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

class _TotalPill extends StatelessWidget {
  const _TotalPill({
    required this.label,
    required this.value,
    required this.color,
    required this.background,
  });

  final String label;
  final int value;
  final Color color;
  final Color background;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 26,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner atop the slot list: grand totals across ALL days & slots + a button
/// into the consolidated Complete Attendance view.
class _CompleteAttendanceCard extends StatelessWidget {
  const _CompleteAttendanceCard({required this.slots, required this.onOpen});

  final List<SlotSummary> slots;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    var present = 0, absent = 0, ufm = 0;
    for (final s in slots) {
      present += s.totalPresent;
      absent += s.totalAbsent;
      ufm += s.totalUfm;
    }
    final days = slots.map((s) => s.examDate.trim()).toSet()
      ..removeWhere((e) => e.isEmpty);
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            gradient: PortalColors.heroGradient,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.fact_check_rounded, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Complete Attendance',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                  ),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Colors.white,
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                'All ${days.length} day(s) · ${slots.length} slot(s) — '
                'P $present  A $absent  UFM $ufm',
                style: const TextStyle(
                  color: Color(0xFFF3E7BF),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SlotCard extends StatelessWidget {
  const _SlotCard({
    required this.summary,
    required this.onOpen,
    required this.onDelete,
  });

  final SlotSummary summary;
  final VoidCallback onOpen;
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
          onTap: onOpen,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        summary.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete slot',
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      color: PortalColors.subtleText,
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Received ${summary.received}/${summary.programs} programs  •  '
                  'P ${summary.totalPresent}  A ${summary.totalAbsent}  '
                  'UFM ${summary.totalUfm}',
                  style: const TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12.5,
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

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.onTap});

  final SlotRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final accent = row.received
        ? const Color(0xFF047857)
        : PortalColors.subtleText;
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
              border: Border.all(
                color: row.received
                    ? const Color(0xFF047857).withValues(alpha: 0.45)
                    : PortalColors.cardBorder,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  row.received
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  color: accent,
                  size: 22,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${row.program}  •  exp ${row.expected}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 1),
                      Text(
                        [
                          if (row.subject.isNotEmpty) row.subject,
                          if (row.faculty.isNotEmpty) row.faculty,
                          if (row.halls.isNotEmpty) row.halls,
                        ].join('  •  '),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 11.5,
                        ),
                      ),
                      if (row.received && row.receivedFrom.isNotEmpty)
                        Text(
                          'from ${row.receivedFrom}'
                          '${row.updatedAt != null ? ' • ${_hm(row.updatedAt!)}' : ''}',
                          style: const TextStyle(
                            color: Color(0xFF047857),
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (row.received)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        'P ${row.present}  A ${row.absent}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12.5,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      Text(
                        'UFM ${row.ufm}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFFB91C1C),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  )
                else
                  const Text(
                    'tap to fill',
                    style: TextStyle(
                      fontSize: 11,
                      color: PortalColors.subtleText,
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

String _hm(DateTime dt) {
  final l = dt.toLocal();
  final h = l.hour.toString().padLeft(2, '0');
  final m = l.minute.toString().padLeft(2, '0');
  return '${l.day}/${l.month} $h:$m';
}

class _ReceiptTile extends StatelessWidget {
  const _ReceiptTile({required this.receipt});

  final SlotReceipt receipt;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PortalColors.cardBorder),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.move_to_inbox_rounded,
              color: Color(0xFF047857),
              size: 22,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    receipt.receivedFrom,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: PortalColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    [
                      if (receipt.hall.isNotEmpty) 'Hall ${receipt.hall}',
                      if (receipt.programs.isNotEmpty) receipt.programs,
                    ].join('  •  '),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 11.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'P ${receipt.present}  A ${receipt.absent}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 12,
                    color: PortalColors.textPrimary,
                  ),
                ),
                if (receipt.receivedAt != null)
                  Text(
                    _hm(receipt.receivedAt!),
                    style: const TextStyle(
                      fontSize: 10.5,
                      color: PortalColors.subtleText,
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title});

  final IconData icon;
  final String title;

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
      ],
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
