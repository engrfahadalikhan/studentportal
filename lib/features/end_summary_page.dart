import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assessment/teacher_dashboard_models.dart';
import '../services/teacher_dashboard_database.dart';
import '../ui/student_portal_shell.dart';
import 'attendance_report_pdf.dart';

/// End-of-exam summary with drill-down: SLOT (day + shift) → PROGRAM or HALL →
/// the student list. Aggregates every sheet the teacher holds (own scans plus
/// everything accepted/merged from other invigilators).
class EndSummaryPage extends StatefulWidget {
  const EndSummaryPage({super.key, required this.teacherId});

  final String teacherId;

  @override
  State<EndSummaryPage> createState() => _EndSummaryPageState();
}

class _EndSummaryPageState extends State<EndSummaryPage> {
  final _db = TeacherDashboardDatabase.instance;
  bool _loading = true;
  List<AttendanceSummaryRow> _rows = const [];
  List<UfmSummaryRow> _ufm = const [];

  final _searchCtrl = TextEditingController();
  String _search = '';

  String? _slot; // selected slot key
  String? _drillKind; // 'program' | 'hall'
  String? _drillValue;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final rows = await _db.loadAttendanceSummaryRows(widget.teacherId);
    final ufm = await _db.loadUfmSummaryRows(widget.teacherId);
    if (!mounted) return;
    setState(() {
      _rows = rows;
      _ufm = ufm;
      _loading = false;
    });
  }

  /// Loose roll match (case- + separator-insensitive).
  String _norm(String s) => s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

  Future<void> _exportPdf(String kind) async {
    try {
      if (kind == 'ufm') {
        final ufm = await _db.loadUfmSummaryRows(widget.teacherId);
        await AttendanceReportPdf.shareUfm(rows: ufm);
      } else if (kind == 'paper_not_returned' || kind == 'qr_problem') {
        await AttendanceReportPdf.shareFlagged(rows: _rows, flag: kind);
      } else {
        await AttendanceReportPdf.sharePresentAbsent(
          rows: _rows,
          onlyStatus: kind,
        );
      }
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF failed: $error')),
      );
    }
  }

  String _slotKey(AttendanceSummaryRow r) =>
      '${r.dateTime.year}-${r.dateTime.month}-${r.dateTime.day}|${r.shift}';

  String _slotLabel(AttendanceSummaryRow r) =>
      '${DateFormat('dd MMM yyyy').format(r.dateTime)}  •  ${r.shift} shift';

  void _back() {
    setState(() {
      if (_drillValue != null) {
        _drillValue = null;
        _drillKind = null;
      } else if (_slot != null) {
        _slot = null;
      } else {
        Navigator.of(context).maybePop();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _slot == null,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        backgroundColor: PortalColors.pageBackground,
        appBar: AppBar(
          title: const Text('Attendance Summary'),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: _back,
          ),
          actions: [
            if (!_loading && _rows.isNotEmpty)
              PopupMenuButton<String>(
                icon: const Icon(Icons.picture_as_pdf_rounded),
                tooltip: 'Export PDF',
                onSelected: _exportPdf,
                itemBuilder: (_) => const [
                  PopupMenuItem(
                    value: 'present',
                    child: Text('PDF — Present students'),
                  ),
                  PopupMenuItem(
                    value: 'absent',
                    child: Text('PDF — Absent students'),
                  ),
                  PopupMenuItem(
                    value: 'ufm',
                    child: Text('PDF — UFM cases'),
                  ),
                  PopupMenuItem(
                    value: 'paper_not_returned',
                    child: Text('PDF — Paper not submitted'),
                  ),
                ],
              ),
          ],
        ),
        body: _loading
            ? const Center(child: CircularProgressIndicator())
            : _rows.isEmpty
            ? const Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: Text(
                    'No attendance yet. Scan halls and accept other teachers\' '
                    'data — the slot / program / hall summary builds here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: PortalColors.subtleText),
                  ),
                ),
              )
            : Column(
                children: [
                  _searchBar(),
                  Expanded(
                    child: _search.trim().isNotEmpty
                        ? _searchResults()
                        : _drillValue != null
                        ? _studentList()
                        : _slot != null
                        ? _slotDetail()
                        : _slotsList(),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _searchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _search = v),
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          isDense: true,
          hintText: 'Search a roll number…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: _search.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => setState(() {
                    _searchCtrl.clear();
                    _search = '';
                  }),
                ),
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: PortalColors.cardBorder),
          ),
        ),
      ),
    );
  }

  /// One student's full record: every paper they sat (present/absent, hall,
  /// who scanned them) + any UFM / QR / paper-not-submitted flags.
  Widget _searchResults() {
    final q = _norm(_search);
    final mine = _rows.where((r) => _norm(r.rollNo).contains(q)).toList()
      ..sort((a, b) => a.dateTime.compareTo(b.dateTime));
    final ufm = _ufm.where((u) => _norm(u.rollNo).contains(q)).toList();
    if (mine.isEmpty && ufm.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'No record found for "$_search".',
            style: const TextStyle(color: PortalColors.subtleText),
          ),
        ),
      );
    }
    final present = mine.where((r) => r.isPresent).length;
    final absent = mine.length - present;
    final name = mine.isEmpty ? '' : mine.first.studentName;
    final flags = mine.where((r) => r.flag.isNotEmpty).toList();
    return ListView(
      padding: const EdgeInsets.all(12),
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: PortalColors.heroGradient,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                mine.isEmpty ? _search : mine.first.rollNo,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w900,
                  fontSize: 18,
                ),
              ),
              if (name.isNotEmpty)
                Text(name, style: const TextStyle(color: Colors.white70)),
              const SizedBox(height: 8),
              Text(
                'Papers sat: ${mine.length}   ·   Present: $present   ·   '
                'Absent: $absent',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        if (ufm.isNotEmpty) ...[
          const SizedBox(height: 12),
          _flagCard(
            'UFM case(s)',
            const Color(0xFFB91C1C),
            [
              for (final u in ufm)
                [
                  '${u.allegation} — ${u.details}'.trim(),
                  if (u.collectedBy.isNotEmpty) 'recorded by ${u.collectedBy}',
                ].join('  ·  '),
            ],
          ),
        ],
        if (flags.isNotEmpty) ...[
          const SizedBox(height: 12),
          _flagCard(
            'Flags',
            const Color(0xFFB45309),
            [
              for (final r in flags)
                '${DateFormat('dd MMM').format(r.dateTime)} · ${r.hall} · '
                    '${_flagLabel(r.flag)}',
            ],
          ),
        ],
        const SizedBox(height: 12),
        const Text(
          'Every paper',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
        ),
        const SizedBox(height: 6),
        for (final r in mine)
          Card(
            margin: const EdgeInsets.only(bottom: 8),
            child: ListTile(
              dense: true,
              leading: Icon(
                r.isPresent
                    ? Icons.check_circle_rounded
                    : Icons.cancel_rounded,
                color: r.isPresent
                    ? const Color(0xFF047857)
                    : const Color(0xFFB91C1C),
              ),
              title: Text(
                '${DateFormat('dd MMM yyyy').format(r.dateTime)}  ·  ${r.shift} '
                'shift  ·  ${r.hall}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
              ),
              subtitle: Text(
                [
                  r.program,
                  r.isPresent ? 'Present' : 'Absent',
                  if (r.flag.isNotEmpty) _flagLabel(r.flag),
                  if (r.collectedBy.isNotEmpty) 'Scanned by ${r.collectedBy}',
                ].join('  ·  '),
              ),
            ),
          ),
      ],
    );
  }

  Widget _flagCard(String title, Color color, List<String> lines) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(color: color, fontWeight: FontWeight.w900),
          ),
          const SizedBox(height: 4),
          for (final l in lines)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(l, style: TextStyle(color: color, fontSize: 12.5)),
            ),
        ],
      ),
    );
  }

  String _flagLabel(String flag) => switch (flag) {
    'paper_not_returned' => 'Paper not submitted',
    'qr_problem' => 'QR problem',
    _ => flag,
  };

  Widget _statRow(Iterable<AttendanceSummaryRow> rows) {
    final list = rows.toList();
    final present = list.where((r) => r.isPresent).length;
    final absent = list.length - present;
    final qr = list.where((r) => r.flag == 'qr_problem').length;
    final nr = list.where((r) => r.flag == 'paper_not_returned').length;
    return Row(
      children: [
        _Pill('Present', present, const Color(0xFF047857)),
        const SizedBox(width: 6),
        _Pill('Absent', absent, const Color(0xFFB91C1C)),
        if (qr > 0) ...[
          const SizedBox(width: 6),
          _Pill('QR', qr, const Color(0xFFB45309)),
        ],
        if (nr > 0) ...[
          const SizedBox(width: 6),
          _Pill('No-return', nr, const Color(0xFF7C3AED)),
        ],
      ],
    );
  }

  // ----- Level 0: slots ------------------------------------------------------
  /// Prominent, always-visible export buttons — Present / Absent / UFM /
  /// Paper-not-submitted, each its own PDF.
  Widget _exportCard() {
    final present = _rows.where((r) => r.isPresent).length;
    final absent = _rows.length - present;
    final ufmCount = _rows.where((r) => r.flag == 'qr_problem').length; // soft
    Widget btn(String label, String kind, Color color, IconData icon) {
      return OutlinedButton.icon(
        onPressed: () => _exportPdf(kind),
        style: OutlinedButton.styleFrom(foregroundColor: color),
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Export PDF (separate lists)',
            style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            'Present $present  •  Absent $absent  •  total ${_rows.length}'
            '${ufmCount > 0 ? '  •  QR-problem $ufmCount' : ''}',
            style: const TextStyle(fontSize: 12, color: PortalColors.subtleText),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              btn('Present', 'present', const Color(0xFF047857),
                  Icons.check_circle_outline),
              btn('Absent', 'absent', const Color(0xFFB91C1C),
                  Icons.cancel_outlined),
              btn('UFM', 'ufm', const Color(0xFFB45309), Icons.gavel_rounded),
              btn('Paper not submitted', 'paper_not_returned',
                  const Color(0xFF6D28D9), Icons.assignment_late_outlined),
            ],
          ),
        ],
      ),
    );
  }

  Widget _slotsList() {
    final keys = <String, List<AttendanceSummaryRow>>{};
    final label = <String, String>{};
    for (final r in _rows) {
      final k = _slotKey(r);
      keys.putIfAbsent(k, () => []).add(r);
      label[k] = _slotLabel(r);
    }
    final sorted = keys.keys.toList()
      ..sort((a, b) => keys[b]!.first.dateTime.compareTo(
        keys[a]!.first.dateTime,
      ));
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _exportCard(),
        const SizedBox(height: 8),
        const _Header('Slots (tap to open day + shift)'),
        for (final k in sorted)
          _Card(
            title: label[k]!,
            subtitle:
                '${keys[k]!.map((r) => r.hall).toSet().length} halls  •  '
                '${keys[k]!.map((r) => r.program).toSet().length} programs',
            stat: _statRow(keys[k]!),
            onTap: () => setState(() => _slot = k),
          ),
      ],
    );
  }

  // ----- Level 1: a slot's programs + halls ----------------------------------
  Widget _slotDetail() {
    final slotRows = _rows.where((r) => _slotKey(r) == _slot).toList();
    final byProgram = <String, List<AttendanceSummaryRow>>{};
    final byHall = <String, List<AttendanceSummaryRow>>{};
    for (final r in slotRows) {
      byProgram.putIfAbsent(r.program, () => []).add(r);
      byHall.putIfAbsent(r.hall, () => []).add(r);
    }
    final programs = byProgram.keys.toList()..sort();
    final halls = byHall.keys.toList()..sort();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Card(
          title: slotRows.isEmpty ? 'Slot' : _slotLabel(slotRows.first),
          subtitle: 'Slot total',
          stat: _statRow(slotRows),
        ),
        const SizedBox(height: 8),
        const _Header('By program (tap for students)'),
        for (final p in programs)
          _Card(
            title: p,
            stat: _statRow(byProgram[p]!),
            onTap: () => setState(() {
              _drillKind = 'program';
              _drillValue = p;
            }),
          ),
        const SizedBox(height: 8),
        const _Header('By hall (tap for students)'),
        for (final h in halls)
          _Card(
            title: 'Hall $h',
            stat: _statRow(byHall[h]!),
            onTap: () => setState(() {
              _drillKind = 'hall';
              _drillValue = h;
            }),
          ),
      ],
    );
  }

  // ----- Level 2: students (absent first) ------------------------------------
  Widget _studentList() {
    final list = _rows.where((r) {
      if (_slotKey(r) != _slot) return false;
      return _drillKind == 'program'
          ? r.program == _drillValue
          : r.hall == _drillValue;
    }).toList();
    list.sort((a, b) {
      final aP = a.isPresent ? 1 : 0;
      final bP = b.isPresent ? 1 : 0;
      if (aP != bP) return aP - bP; // absent first
      return a.rollNo.toLowerCase().compareTo(b.rollNo.toLowerCase());
    });
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
      children: [
        _Card(
          title: _drillKind == 'program' ? _drillValue! : 'Hall $_drillValue',
          subtitle: 'Absent shown first',
          stat: _statRow(list),
        ),
        const SizedBox(height: 8),
        for (final r in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: r.isPresent
                      ? const Color(0xFF047857).withValues(alpha: 0.35)
                      : const Color(0xFFB91C1C).withValues(alpha: 0.35),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    r.isPresent
                        ? Icons.check_circle_rounded
                        : Icons.cancel_rounded,
                    size: 18,
                    color: r.isPresent
                        ? const Color(0xFF047857)
                        : const Color(0xFFB91C1C),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.rollNo,
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: PortalColors.textPrimary,
                          ),
                        ),
                        if (r.studentName.isNotEmpty)
                          Text(
                            r.studentName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: PortalColors.subtleText,
                              fontSize: 12,
                            ),
                          ),
                        if (r.collectedBy.isNotEmpty)
                          Text(
                            'By ${r.collectedBy}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Color(0xFF8A6E16),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                      ],
                    ),
                  ),
                  if (r.flag == 'qr_problem')
                    const _Tag('QR', Color(0xFFB45309)),
                  if (r.flag == 'paper_not_returned')
                    const _Tag('No-return', Color(0xFF7C3AED)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.text);
  final String text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 6, bottom: 8),
    child: Text(
      text,
      style: const TextStyle(
        fontWeight: FontWeight.w800,
        color: PortalColors.subtleText,
        fontSize: 12.5,
        letterSpacing: 0.3,
      ),
    ),
  );
}

class _Card extends StatelessWidget {
  const _Card({
    required this.title,
    this.subtitle,
    required this.stat,
    this.onTap,
  });
  final String title;
  final String? subtitle;
  final Widget stat;
  final VoidCallback? onTap;
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
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    if (onTap != null)
                      const Icon(Icons.chevron_right_rounded,
                          color: PortalColors.subtleText),
                  ],
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    style: const TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                stat,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill(this.label, this.value, this.color);
  final String label;
  final int value;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        '$label $value',
        style: TextStyle(
          fontWeight: FontWeight.w800,
          fontSize: 12,
          color: color,
        ),
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text, this.color);
  final String text;
  final Color color;
  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
