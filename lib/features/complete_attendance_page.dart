import 'package:flutter/material.dart';

import '../services/slot_collection_repository.dart';
import '../ui/student_portal_shell.dart';
import 'attendance_roster_page.dart';
import 'slot_collection_pdf.dart';

/// One consolidated view of the WHOLE attendance — every day and every slot
/// together: grand totals, a per-programme roll-up across all slots, and a
/// day/slot breakdown. Reached from the Per-Slot Collection module (which the
/// admin can grant an individual teacher access to).
class CompleteAttendancePage extends StatefulWidget {
  const CompleteAttendancePage({super.key, required this.repository});

  final SlotCollectionRepository repository;

  @override
  State<CompleteAttendancePage> createState() => _CompleteAttendancePageState();
}

class _CompleteAttendancePageState extends State<CompleteAttendancePage> {
  bool _loading = true;
  List<SlotSummary> _slots = const [];
  List<SlotRow> _rows = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await widget.repository.open();
    final slots = await widget.repository.loadSlots();
    final rows = await widget.repository.loadAllRows();
    if (!mounted) return;
    setState(() {
      _slots = slots;
      _rows = rows;
      _loading = false;
    });
  }

  ({int expected, int present, int absent, int ufm}) get _totals {
    var e = 0, p = 0, a = 0, u = 0;
    for (final s in _slots) {
      e += s.expected;
      p += s.totalPresent;
      a += s.totalAbsent;
      u += s.totalUfm;
    }
    return (expected: e, present: p, absent: a, ufm: u);
  }

  Map<String, List<int>> get _byProgram {
    final m = <String, List<int>>{};
    for (final r in _rows) {
      final key = r.program.trim().isEmpty ? '—' : r.program.trim();
      final agg = m.putIfAbsent(key, () => [0, 0, 0, 0]);
      agg[0] += r.expected;
      agg[1] += r.present;
      agg[2] += r.absent;
      agg[3] += r.ufm;
    }
    return m;
  }

  @override
  Widget build(BuildContext context) {
    final t = _totals;
    final days = _slots.map((s) => s.examDate.trim()).toSet()
      ..removeWhere((e) => e.isEmpty);
    final programKeys = _byProgram.keys.toList()
      ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(
        title: const Text('Complete Attendance'),
        actions: [
          IconButton(
            tooltip: 'Per-student roster (link to attendance)',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AttendanceRosterPage(),
              ),
            ),
            icon: const Icon(Icons.groups_rounded),
          ),
          IconButton(
            tooltip: 'Download PDF',
            onPressed: _slots.isEmpty
                ? null
                : () => shareCompleteAttendancePdf(slots: _slots, rows: _rows),
            icon: const Icon(Icons.picture_as_pdf_outlined),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _slots.isEmpty
          ? const Center(
              child: Padding(
                padding: EdgeInsets.all(28),
                child: Text(
                  'No attendance collected yet. Scan the PER-SLOT QR in the '
                  'Per-Slot Collection module to load days/slots first.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: PortalColors.subtleText),
                ),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
              children: [
                Text(
                  'All days & all slots',
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                    color: PortalColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${days.length} day(s) · ${_slots.length} slot(s) · '
                  'Expected ${t.expected}',
                  style: const TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12.5,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _total('Present', t.present, const Color(0xFF047857),
                        const Color(0xFFE6F4EE)),
                    const SizedBox(width: 10),
                    _total('Absent', t.absent, const Color(0xFFB91C1C),
                        const Color(0xFFFBEAEA)),
                    const SizedBox(width: 10),
                    _total('UFM', t.ufm, const Color(0xFFB45309),
                        const Color(0xFFFBF1E0)),
                  ],
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const AttendanceRosterPage(),
                      ),
                    ),
                    icon: const Icon(Icons.groups_rounded),
                    label: const Text(
                      'Per-student roster — who attended',
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                _heading('Programme totals (all slots)'),
                const SizedBox(height: 8),
                _tableCard(
                  header: const ['Programme', 'Exp', 'P', 'A', 'UFM'],
                  flex: const [4, 2, 2, 2, 2],
                  rows: [
                    for (final k in programKeys)
                      [
                        k,
                        '${_byProgram[k]![0]}',
                        '${_byProgram[k]![1]}',
                        '${_byProgram[k]![2]}',
                        '${_byProgram[k]![3]}',
                      ],
                  ],
                  totalRow: [
                    'TOTAL',
                    '${t.expected}',
                    '${t.present}',
                    '${t.absent}',
                    '${t.ufm}',
                  ],
                ),
                const SizedBox(height: 20),
                _heading('Day / slot breakdown'),
                const SizedBox(height: 8),
                _tableCard(
                  header: const ['Date · Shift', 'Prog', 'P', 'A', 'UFM'],
                  flex: const [4, 2, 2, 2, 2],
                  rows: [
                    for (final s in _slots)
                      [
                        s.title,
                        '${s.programs}',
                        '${s.totalPresent}',
                        '${s.totalAbsent}',
                        '${s.totalUfm}',
                      ],
                  ],
                ),
              ],
            ),
    );
  }

  Widget _total(String label, int value, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
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

  Widget _heading(String t) => Text(
    t,
    style: const TextStyle(
      fontWeight: FontWeight.w900,
      fontSize: 14,
      color: PortalColors.textPrimary,
    ),
  );

  Widget _tableCard({
    required List<String> header,
    required List<int> flex,
    required List<List<String>> rows,
    List<String>? totalRow,
  }) {
    Widget rowWidget(List<String> cells, {bool head = false, bool tot = false}) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: head
              ? const Color(0xFFF3ECD6)
              : tot
              ? const Color(0xFFFAF4E2)
              : Colors.white,
        ),
        child: Row(
          children: [
            for (var i = 0; i < cells.length; i++)
              Expanded(
                flex: flex[i],
                child: Text(
                  cells[i],
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: head || tot
                        ? FontWeight.w800
                        : FontWeight.w500,
                    color: PortalColors.textPrimary,
                  ),
                ),
              ),
          ],
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          rowWidget(header, head: true),
          for (final r in rows) ...[
            const Divider(height: 1),
            rowWidget(r),
          ],
          if (totalRow != null) ...[
            const Divider(height: 1),
            rowWidget(totalRow, tot: true),
          ],
        ],
      ),
    );
  }
}
