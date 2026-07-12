import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../services/slot_collection_repository.dart';

/// Builds and shares a per-slot attendance PDF (present / absent / UFM per
/// program) for one collected slot, straight from the Per-Slot Collection data.
Future<void> shareSlotCollectionPdf({
  required SlotSummary slot,
  required List<SlotRow> rows,
}) async {
  final doc = pw.Document();

  final sorted = [...rows]
    ..sort((a, b) => a.program.toLowerCase().compareTo(b.program.toLowerCase()));

  pw.Widget cell(String t, {bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: pw.TextStyle(
        fontSize: 8.5,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  final header = pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE6CF)),
    children: [
      cell('Program', bold: true),
      cell('Subject', bold: true),
      cell('Halls', bold: true),
      cell('Expected', bold: true),
      cell('Present', bold: true),
      cell('Absent', bold: true),
      cell('UFM', bold: true),
      cell('Received from', bold: true),
    ],
  );

  final body = <pw.TableRow>[
    for (final r in sorted)
      pw.TableRow(
        children: [
          cell(r.program),
          cell(r.subject),
          cell(r.halls),
          cell('${r.expected}'),
          cell('${r.present}', color: const PdfColor.fromInt(0xFF047857)),
          cell('${r.absent}', color: const PdfColor.fromInt(0xFFB91C1C)),
          cell('${r.ufm}', color: const PdfColor.fromInt(0xFFB45309)),
          cell(r.receivedFrom),
        ],
      ),
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFF5F0DF)),
      children: [
        cell('TOTAL', bold: true),
        cell(''),
        cell(''),
        cell('${slot.expected}', bold: true),
        cell('${slot.totalPresent}', bold: true),
        cell('${slot.totalAbsent}', bold: true),
        cell('${slot.totalUfm}', bold: true),
        cell(''),
      ],
    ),
  ];

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
      build: (ctx) => [
        pw.Text(
          'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Department of Computer Science',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Per-Slot Attendance — ${slot.examDate} · ${slot.shift} shift',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Generated ${_today()}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.Divider(height: 14),
        pw.Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            _stat('Programs', '${slot.programs}'),
            _stat('Halls', '${slot.usedHalls}'),
            _stat('Expected', '${slot.expected}'),
            _stat('Present', '${slot.totalPresent}'),
            _stat('Absent', '${slot.totalAbsent}'),
            _stat('UFM', '${slot.totalUfm}'),
            _stat('Received', '${slot.received}/${slot.programs}'),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
          columnWidths: const {
            0: pw.FlexColumnWidth(2.4),
            1: pw.FlexColumnWidth(3),
            2: pw.FlexColumnWidth(1.6),
            3: pw.FlexColumnWidth(1.2),
            4: pw.FlexColumnWidth(1.2),
            5: pw.FlexColumnWidth(1.2),
            6: pw.FlexColumnWidth(1),
            7: pw.FlexColumnWidth(2.4),
          },
          children: [header, ...body],
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'Slot_${slot.examDate}_${slot.shift}_attendance.pdf'
        .replaceAll(RegExp(r'[^A-Za-z0-9_.-]+'), '_'),
  );
}

/// Builds and shares a COMPLETE attendance PDF — every day + every slot in one
/// document: grand totals, a per-program roll-up across all slots, then a
/// per-slot (date · shift) breakdown.
Future<void> shareCompleteAttendancePdf({
  required List<SlotSummary> slots,
  required List<SlotRow> rows,
}) async {
  final doc = pw.Document();

  var gPresent = 0, gAbsent = 0, gUfm = 0, gExpected = 0;
  for (final s in slots) {
    gPresent += s.totalPresent;
    gAbsent += s.totalAbsent;
    gUfm += s.totalUfm;
    gExpected += s.expected;
  }
  final days = slots.map((s) => s.examDate.trim()).toSet()
    ..removeWhere((e) => e.isEmpty);

  // Per-program roll-up across ALL slots.
  final byProgram = <String, List<int>>{}; // program -> [expected,P,A,UFM]
  for (final r in rows) {
    final key = r.program.trim().isEmpty ? '—' : r.program.trim();
    final agg = byProgram.putIfAbsent(key, () => [0, 0, 0, 0]);
    agg[0] += r.expected;
    agg[1] += r.present;
    agg[2] += r.absent;
    agg[3] += r.ufm;
  }
  final programKeys = byProgram.keys.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

  pw.Widget cell(String t, {bool bold = false, PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: pw.TextStyle(
        fontSize: 8.5,
        color: color,
        fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal,
      ),
    ),
  );

  const green = PdfColor.fromInt(0xFF047857);
  const red = PdfColor.fromInt(0xFFB91C1C);
  const amber = PdfColor.fromInt(0xFFB45309);

  pw.TableRow progHeader() => pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE6CF)),
    children: [
      cell('Program', bold: true),
      cell('Expected', bold: true),
      cell('Present', bold: true),
      cell('Absent', bold: true),
      cell('UFM', bold: true),
    ],
  );

  final slotsSorted = [...slots]
    ..sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));

  pw.TableRow slotHeader() => pw.TableRow(
    decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEDE6CF)),
    children: [
      cell('Date', bold: true),
      cell('Shift', bold: true),
      cell('Programs', bold: true),
      cell('Expected', bold: true),
      cell('Present', bold: true),
      cell('Absent', bold: true),
      cell('UFM', bold: true),
      cell('Received', bold: true),
    ],
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 24, 28, 20),
      footer: (ctx) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
          style: pw.TextStyle(fontSize: 8, fontWeight: pw.FontWeight.bold),
        ),
      ),
      build: (ctx) => [
        pw.Text(
          'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 14, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 2),
        pw.Center(
          child: pw.Text(
            'Department of Computer Science',
            style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.SizedBox(height: 6),
        pw.Center(
          child: pw.Text(
            'Complete Attendance — all days & slots',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
        pw.Center(
          child: pw.Text(
            'Generated ${_today()}',
            style: const pw.TextStyle(fontSize: 9),
          ),
        ),
        pw.Divider(height: 14),
        pw.Wrap(
          spacing: 18,
          runSpacing: 4,
          children: [
            _stat('Days', '${days.length}'),
            _stat('Slots', '${slots.length}'),
            _stat('Expected', '$gExpected'),
            _stat('Present', '$gPresent'),
            _stat('Absent', '$gAbsent'),
            _stat('UFM', '$gUfm'),
          ],
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Programme totals (across all slots)',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
          columnWidths: const {
            0: pw.FlexColumnWidth(3),
            1: pw.FlexColumnWidth(1.3),
            2: pw.FlexColumnWidth(1.3),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1),
          },
          children: [
            progHeader(),
            for (final k in programKeys)
              pw.TableRow(
                children: [
                  cell(k),
                  cell('${byProgram[k]![0]}'),
                  cell('${byProgram[k]![1]}', color: green),
                  cell('${byProgram[k]![2]}', color: red),
                  cell('${byProgram[k]![3]}', color: amber),
                ],
              ),
            pw.TableRow(
              decoration: const pw.BoxDecoration(
                color: PdfColor.fromInt(0xFFF5F0DF),
              ),
              children: [
                cell('TOTAL', bold: true),
                cell('$gExpected', bold: true),
                cell('$gPresent', bold: true),
                cell('$gAbsent', bold: true),
                cell('$gUfm', bold: true),
              ],
            ),
          ],
        ),
        pw.SizedBox(height: 16),
        pw.Text(
          'Day / slot breakdown',
          style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 4),
        pw.Table(
          border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
          columnWidths: const {
            0: pw.FlexColumnWidth(2),
            1: pw.FlexColumnWidth(1.2),
            2: pw.FlexColumnWidth(1.4),
            3: pw.FlexColumnWidth(1.3),
            4: pw.FlexColumnWidth(1.3),
            5: pw.FlexColumnWidth(1.3),
            6: pw.FlexColumnWidth(1),
            7: pw.FlexColumnWidth(1.4),
          },
          children: [
            slotHeader(),
            for (final s in slotsSorted)
              pw.TableRow(
                children: [
                  cell(s.examDate),
                  cell(s.shift),
                  cell('${s.programs}'),
                  cell('${s.expected}'),
                  cell('${s.totalPresent}', color: green),
                  cell('${s.totalAbsent}', color: red),
                  cell('${s.totalUfm}', color: amber),
                  cell('${s.received}/${s.programs}'),
                ],
              ),
          ],
        ),
      ],
    ),
  );

  await Printing.sharePdf(
    bytes: await doc.save(),
    filename: 'Complete_Attendance_all_slots.pdf',
  );
}

pw.Widget _stat(String label, String value) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        label,
        style: const pw.TextStyle(fontSize: 8, color: PdfColors.grey700),
      ),
      pw.Text(
        value,
        style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
      ),
    ],
  );
}

String _today() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.year}';
}
