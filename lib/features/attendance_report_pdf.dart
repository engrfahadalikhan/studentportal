import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../assessment/teacher_dashboard_models.dart';

/// Builds & shares the attendance PDFs straight from the phone (no csexam
/// needed): Present-only, Absent-only, and a UFM-cases report. Mirrors the
/// csexam Import-Attendance exports so both apps produce the same paperwork.
class AttendanceReportPdf {
  static const _flagLabel = {
    'qr_problem': 'QR problem',
    'paper_not_returned': 'Paper not returned',
  };

  /// [onlyStatus] = 'present' or 'absent'.
  static Future<void> sharePresentAbsent({
    required List<AttendanceSummaryRow> rows,
    required String onlyStatus,
  }) async {
    final filt = onlyStatus.toLowerCase();
    final filtered = rows
        .where((r) => r.status.toLowerCase() == filt)
        .toList();
    final title = filt == 'present' ? 'PRESENT STUDENTS' : 'ABSENT STUDENTS';
    final tag = filt == 'present' ? 'Present' : 'Absent';

    final doc = pw.Document();

    // Programwise summary (full present/absent/total over ALL rows).
    final prog = <String, List<int>>{}; // program -> [present, total]
    for (final r in rows) {
      final e = prog.putIfAbsent(r.program, () => [0, 0]);
      e[1] += 1;
      if (r.isPresent) e[0] += 1;
    }
    final progNames = prog.keys.toList()..sort();
    final gPresent = rows.where((r) => r.isPresent).length;
    final gTotal = rows.length;

    final content = <pw.Widget>[
      _header(title),
      pw.SizedBox(height: 8),
      _meta(
        left: 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
        right: filt == 'present'
            ? 'Present: $gPresent / $gTotal'
            : 'Absent: ${gTotal - gPresent} / $gTotal',
      ),
      pw.SizedBox(height: 10),
      pw.Text(
        'Programwise Summary (all halls combined)',
        style: pw.TextStyle(fontSize: 10, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 4),
      _table(
        headers: const ['Program', 'Present', 'Absent', 'Total'],
        rows: [
          for (final p in progNames)
            [
              p,
              '${prog[p]![0]}',
              '${prog[p]![1] - prog[p]![0]}',
              '${prog[p]![1]}',
            ],
          ['TOTAL', '$gPresent', '${gTotal - gPresent}', '$gTotal'],
        ],
        widths: const {
          0: pw.FlexColumnWidth(3),
          1: pw.FlexColumnWidth(1),
          2: pw.FlexColumnWidth(1),
          3: pw.FlexColumnWidth(1),
        },
      ),
      pw.SizedBox(height: 14),
    ];

    // Group filtered rows by slot (date + shift) → hall.
    final bySlot = <String, Map<String, List<AttendanceSummaryRow>>>{};
    final slotLabel = <String, String>{};
    for (final r in filtered) {
      final key =
          '${r.dateTime.year}-${r.dateTime.month.toString().padLeft(2, '0')}-'
          '${r.dateTime.day.toString().padLeft(2, '0')}|${r.shift}';
      slotLabel[key] =
          '${DateFormat('dd MMM yyyy').format(r.dateTime)}  •  ${r.shift} shift';
      bySlot
          .putIfAbsent(key, () => {})
          .putIfAbsent(r.hall, () => [])
          .add(r);
    }
    final slotKeys = bySlot.keys.toList()..sort();

    for (final sk in slotKeys) {
      content.add(
        pw.Container(
          width: double.infinity,
          color: PdfColors.grey200,
          padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: pw.Text(
            slotLabel[sk] ?? sk,
            style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
      content.add(pw.SizedBox(height: 4));
      final halls = bySlot[sk]!.keys.toList()..sort();
      for (final hall in halls) {
        final list = bySlot[sk]![hall]!
          ..sort((a, b) => a.rollNo.compareTo(b.rollNo));
        content.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3, top: 2),
            child: pw.Text(
              'Hall $hall  (${list.length})',
              style: pw.TextStyle(fontSize: 9.5, fontWeight: pw.FontWeight.bold),
            ),
          ),
        );
        content.add(
          _table(
            headers: const ['Roll No', 'Student Name', 'Program', 'Note'],
            rows: [
              for (final r in list)
                [
                  r.rollNo,
                  r.studentName,
                  r.program,
                  _flagLabel[r.flag] ?? '',
                ],
            ],
            widths: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(1.4),
              3: pw.FlexColumnWidth(1.8),
            },
          ),
        );
        content.add(pw.SizedBox(height: 8));
      }
    }

    if (filtered.isEmpty) {
      content.add(
        pw.Text(
          'No $filt students recorded yet.',
          style: const pw.TextStyle(fontSize: 11),
        ),
      );
    }

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(26),
        footer: (ctx) => _footer(ctx, title),
        build: (ctx) => content,
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Attendance_${tag}_${_fileStamp()}.pdf',
    );
  }

  static Future<void> shareUfm({required List<UfmSummaryRow> rows}) async {
    final doc = pw.Document();
    final sorted = [...rows]..sort((a, b) => a.dateTime.compareTo(b.dateTime));

    final tableRows = <List<String>>[];
    for (var i = 0; i < sorted.length; i++) {
      final u = sorted[i];
      tableRows.add([
        '${i + 1}',
        DateFormat('dd MMM').format(u.dateTime),
        u.shift,
        u.hall,
        u.rollNo,
        u.studentName,
        u.allegation,
        u.details,
        u.collectedBy,
      ]);
    }

    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(26),
        footer: (ctx) => _footer(ctx, 'UFM Cases'),
        build: (ctx) => [
          _header('UNFAIR MEANS (UFM) CASES'),
          pw.SizedBox(height: 8),
          _meta(
            left: 'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
            right: 'Total UFM: ${rows.length}',
          ),
          pw.SizedBox(height: 10),
          if (tableRows.isEmpty)
            pw.Text(
              'No UFM cases recorded.',
              style: const pw.TextStyle(fontSize: 11),
            )
          else
            _table(
              headers: const [
                '#',
                'Date',
                'Shift',
                'Hall',
                'Roll No',
                'Student Name',
                'Allegation',
                'Details',
                'Recorded by',
              ],
              rows: tableRows,
              widths: const {
                0: pw.FlexColumnWidth(0.6),
                1: pw.FlexColumnWidth(1.2),
                2: pw.FlexColumnWidth(0.8),
                3: pw.FlexColumnWidth(1.0),
                4: pw.FlexColumnWidth(1.4),
                5: pw.FlexColumnWidth(2.2),
                6: pw.FlexColumnWidth(1.8),
                7: pw.FlexColumnWidth(2.0),
                8: pw.FlexColumnWidth(1.6),
              },
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Attendance_UFM_${_fileStamp()}.pdf',
    );
  }

  /// PDF of PRESENT students carrying a specific [flag] —
  /// 'paper_not_returned' (question paper not submitted) or 'qr_problem'.
  static Future<void> shareFlagged({
    required List<AttendanceSummaryRow> rows,
    required String flag,
  }) async {
    final title = flag == 'paper_not_returned'
        ? 'QUESTION PAPER NOT SUBMITTED'
        : 'QR PROBLEM (MARKED PRESENT BY HAND)';
    final tag = flag == 'paper_not_returned' ? 'PaperNotSubmitted' : 'QrProblem';
    final matched = rows.where((r) => r.flag == flag).toList()
      ..sort((a, b) {
        final c = a.dateTime.compareTo(b.dateTime);
        if (c != 0) return c;
        final h = a.hall.compareTo(b.hall);
        if (h != 0) return h;
        return a.rollNo.compareTo(b.rollNo);
      });

    final tableRows = <List<String>>[];
    for (var i = 0; i < matched.length; i++) {
      final r = matched[i];
      tableRows.add([
        '${i + 1}',
        DateFormat('dd MMM').format(r.dateTime),
        r.shift,
        r.hall,
        r.rollNo,
        r.studentName,
        r.program,
      ]);
    }

    final doc = pw.Document();
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(26),
        footer: (ctx) => _footer(ctx, title),
        build: (ctx) => [
          _header(title),
          pw.SizedBox(height: 8),
          _meta(
            left:
                'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}',
            right: 'Total: ${matched.length}',
          ),
          pw.SizedBox(height: 10),
          if (tableRows.isEmpty)
            pw.Text(
              flag == 'paper_not_returned'
                  ? 'No "paper not submitted" cases recorded.'
                  : 'No "QR problem" cases recorded.',
              style: const pw.TextStyle(fontSize: 11),
            )
          else
            _table(
              headers: const [
                '#',
                'Date',
                'Shift',
                'Hall',
                'Roll No',
                'Student Name',
                'Program',
              ],
              rows: tableRows,
              widths: const {
                0: pw.FlexColumnWidth(0.6),
                1: pw.FlexColumnWidth(1.3),
                2: pw.FlexColumnWidth(0.9),
                3: pw.FlexColumnWidth(1.1),
                4: pw.FlexColumnWidth(1.6),
                5: pw.FlexColumnWidth(3),
                6: pw.FlexColumnWidth(1.6),
              },
            ),
        ],
      ),
    );

    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Attendance_${tag}_${_fileStamp()}.pdf',
    );
  }

  // ---- shared bits --------------------------------------------------------

  static String _fileStamp() =>
      DateFormat('yyyyMMdd-HHmm').format(DateTime.now());

  static pw.Widget _header(String title) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        pw.Container(height: 1.5, color: PdfColors.black),
        pw.SizedBox(height: 4),
        pw.Text(
          'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
        ),
        pw.Text(
          'Department of Computer Science',
          textAlign: pw.TextAlign.center,
          style: const pw.TextStyle(fontSize: 9.5),
        ),
        pw.SizedBox(height: 4),
        pw.Container(height: 1.5, color: PdfColors.black),
        pw.SizedBox(height: 8),
        pw.Text(
          title,
          textAlign: pw.TextAlign.center,
          style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _meta({required String left, required String right}) {
    return pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(left, style: const pw.TextStyle(fontSize: 9)),
        pw.Text(
          right,
          style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
        ),
      ],
    );
  }

  static pw.Widget _footer(pw.Context ctx, String label) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(top: 4),
      decoration: const pw.BoxDecoration(
        border: pw.Border(top: pw.BorderSide(color: PdfColors.grey600)),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        children: [
          pw.Text(
            label,
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
          pw.Text(
            'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
            style: const pw.TextStyle(fontSize: 7.5, color: PdfColors.grey700),
          ),
        ],
      ),
    );
  }

  static pw.Widget _table({
    required List<String> headers,
    required List<List<String>> rows,
    required Map<int, pw.TableColumnWidth> widths,
  }) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.black, width: 0.6),
      columnWidths: widths,
      defaultVerticalAlignment: pw.TableCellVerticalAlignment.middle,
      children: [
        pw.TableRow(
          decoration: const pw.BoxDecoration(color: PdfColors.grey300),
          children: [
            for (final h in headers)
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                child: pw.Text(
                  h,
                  style: pw.TextStyle(
                    fontSize: 8,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
          ],
        ),
        for (final row in rows)
          pw.TableRow(
            children: [
              for (final v in row)
                pw.Padding(
                  padding: const pw.EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 3.5,
                  ),
                  child: pw.Text(v, style: const pw.TextStyle(fontSize: 8)),
                ),
            ],
          ),
      ],
    );
  }
}
