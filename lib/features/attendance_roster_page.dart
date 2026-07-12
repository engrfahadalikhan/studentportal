import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../attendance/qr_attendance_section.dart';
import '../data/local_student_enrollments.dart';
import '../ui/student_portal_shell.dart';

/// Links the student roster to the collected QR attendance, PER STUDENT.
///
/// A QR scan means the student was seen present (there is no "absent" scan), so
/// every student with at least one scan is Present; a roster student with no
/// scan is "No attendance yet". Search by roll or name to find anyone and see
/// whether their attendance is in.
class AttendanceRosterPage extends StatefulWidget {
  const AttendanceRosterPage({super.key});

  @override
  State<AttendanceRosterPage> createState() => _AttendanceRosterPageState();
}

class _RosterEntry {
  _RosterEntry({
    required this.rollNo,
    required this.name,
    required this.program,
    required this.semester,
    required this.section,
    this.inRoster = false,
  });

  final String rollNo;
  String name;
  String program;
  String semester;
  String section;

  /// True when the student exists in the bundled roster (not scan-only).
  bool inRoster;

  // Attendance (from the newest scan, if any).
  bool present = false;
  String hall = '';
  DateTime? scannedAt;
  String collectedBy = '';
}

class _AttendanceRosterPageState extends State<AttendanceRosterPage> {
  final _repo = AttendanceRepository();
  final _search = TextEditingController();
  String _query = '';
  bool _loading = true;

  final Map<String, _RosterEntry> _byRoll = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String _norm(String roll) => roll.trim().toUpperCase();

  Future<void> _load() async {
    // 1) Every distinct student in the bundled roster (max semester per roll).
    for (final row in localStudentEnrollmentRows) {
      if (row.length <= 4) continue;
      final roll = row[0].trim();
      if (roll.isEmpty) continue;
      final key = _norm(roll);
      final sem = int.tryParse(row[3].trim()) ?? 0;
      final existing = _byRoll[key];
      if (existing == null) {
        _byRoll[key] = _RosterEntry(
          rollNo: roll,
          name: row[1].trim(),
          program: row[2].trim(),
          semester: row[3].trim(),
          section: row[4].trim(),
          inRoster: true,
        );
      } else {
        // Keep the highest semester (a retake row can carry a lower one).
        final curSem = int.tryParse(existing.semester) ?? 0;
        if (sem > curSem) existing.semester = row[3].trim();
        if (existing.name.isEmpty) existing.name = row[1].trim();
      }
    }

    // 2) Overlay the QR scans — a scan = the student was present.
    try {
      await _repo.open();
      final scans = await _repo.loadScans();
      for (final s in scans) {
        final roll = s.rollNo.trim();
        if (roll.isEmpty) continue;
        final key = _norm(roll);
        final entry = _byRoll.putIfAbsent(
          key,
          () => _RosterEntry(
            rollNo: roll,
            name: s.studentName.trim(),
            program: s.program.trim(),
            semester: '',
            section: '',
          ),
        );
        // Newest scan wins for the shown hall/time.
        if (entry.scannedAt == null || s.scannedAt.isAfter(entry.scannedAt!)) {
          entry.hall = s.hallCode.trim();
          entry.scannedAt = s.scannedAt;
          entry.collectedBy = s.collectedBy.trim();
        }
        entry.present = true;
        if (entry.name.isEmpty) entry.name = s.studentName.trim();
        if (entry.program.isEmpty) entry.program = s.program.trim();
      }
    } catch (_) {
      // No attendance DB yet — the roster still shows (all pending).
    }

    if (!mounted) return;
    setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final all = _byRoll.values.toList()
      ..sort((a, b) => a.rollNo.compareTo(b.rollNo));
    final present = all.where((e) => e.present).length;
    final pending = all.length - present;

    final q = _query.trim().toLowerCase();
    final shown = q.isEmpty
        ? all
        : all
              .where(
                (e) =>
                    e.rollNo.toLowerCase().contains(q) ||
                    e.name.toLowerCase().contains(q),
              )
              .toList();

    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Attendance Roster')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          _stat('Present', present, const Color(0xFF047857),
                              const Color(0xFFE6F4EE)),
                          const SizedBox(width: 10),
                          _stat('No paper yet', pending, const Color(0xFFB45309),
                              const Color(0xFFFBF1E0)),
                          const SizedBox(width: 10),
                          _stat('Total', all.length,
                              PortalColors.textPrimary, const Color(0xFFEFEFEF)),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '$present of ${all.length} students have attendance in.',
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _search,
                        onChanged: (v) => setState(() => _query = v),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: Colors.white,
                          prefixIcon: const Icon(Icons.search_rounded),
                          hintText: 'Search roll number or name',
                          suffixIcon: _query.isEmpty
                              ? null
                              : IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _search.clear();
                                    setState(() => _query = '');
                                  },
                                ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: shown.isEmpty
                      ? const Center(
                          child: Text(
                            'No students match.',
                            style: TextStyle(color: PortalColors.subtleText),
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (_, i) => _tile(shown[i]),
                        ),
                ),
              ],
            ),
    );
  }

  Widget _stat(String label, int value, Color color, Color bg) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w900,
                color: color,
              ),
            ),
            Text(
              label,
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w800,
                color: color,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(_RosterEntry e) {
    final present = e.present;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            margin: const EdgeInsets.only(right: 10),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: present
                  ? const Color(0xFF047857)
                  : const Color(0xFFB45309),
            ),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.rollNo}   ${e.name}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  [
                    if (e.program.isNotEmpty) e.program,
                    if (e.semester.isNotEmpty) 'Sem ${e.semester}',
                    if (e.section.isNotEmpty) e.section,
                    if (!e.inRoster) 'scan only',
                  ].join(' · '),
                  style: const TextStyle(
                    fontSize: 11.5,
                    color: PortalColors.subtleText,
                  ),
                ),
                if (present) ...[
                  const SizedBox(height: 3),
                  Text(
                    'Present'
                    '${e.hall.isEmpty ? '' : ' · ${e.hall}'}'
                    '${e.scannedAt == null ? '' : ' · ${DateFormat('dd MMM, hh:mm a').format(e.scannedAt!)}'}'
                    '${e.collectedBy.isEmpty ? '' : ' · by ${e.collectedBy}'}',
                    style: const TextStyle(
                      fontSize: 11.5,
                      color: Color(0xFF047857),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: (present
                      ? const Color(0xFF047857)
                      : const Color(0xFFB45309))
                  .withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              present ? 'Present' : 'No paper yet',
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w800,
                color: present
                    ? const Color(0xFF047857)
                    : const Color(0xFFB45309),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
