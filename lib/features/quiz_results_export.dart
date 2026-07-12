import 'dart:io';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import '../assessment/assessment_models.dart';

/// Exports one quiz's scanned results as a spreadsheet (CSV — opens directly in
/// Excel) or a PDF, straight from the phone.
class QuizResultsExport {
  static const _headers = [
    '#',
    'Roll No',
    'Name',
    'Class',
    'Marks',
    'Out of',
    'Status',
    'Warnings',
  ];

  static List<List<String>> _rows(
    Assessment a,
    List<AssessmentSubmission> subs,
  ) {
    final sorted = [...subs]..sort(
      (x, y) => x.studentId.toLowerCase().compareTo(y.studentId.toLowerCase()),
    );
    final out = <List<String>>[];
    for (var i = 0; i < sorted.length; i++) {
      final s = sorted[i];
      final cls =
          '${s.studentProgram} ${s.studentSemester}${s.studentSection}'.trim();
      out.add([
        '${i + 1}',
        s.studentId,
        s.studentName,
        cls,
        s.marks == null ? '' : '${s.marks}',
        '${a.totalMarks}',
        s.status == AttemptStatus.autoLocked ? 'Auto-submitted' : 'Submitted',
        '${s.warningCount}',
      ]);
    }
    return out;
  }

  // ---- CSV (Excel) --------------------------------------------------------

  static Future<void> shareCsv(
    Assessment a,
    List<AssessmentSubmission> subs,
  ) async {
    final buf = StringBuffer();
    buf.writeln(_csvLine([a.title]));
    buf.writeln(_csvLine(_headers));
    for (final r in _rows(a, subs)) {
      buf.writeln(_csvLine(r));
    }
    final dir = await getApplicationDocumentsDirectory();
    final file = File('${dir.path}/Quiz_${_safe(a.title)}_${_stamp()}.csv');
    await file.writeAsString(buf.toString(), flush: true);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: '${a.title} — results',
      text: 'Quiz results — opens in Excel / Google Sheets.',
    );
  }

  static String _csvLine(List<String> cells) => cells.map(_csvCell).join(',');

  static String _csvCell(String v) {
    final needsQuote =
        v.contains(',') || v.contains('"') || v.contains('\n');
    final esc = v.replaceAll('"', '""');
    return needsQuote ? '"$esc"' : esc;
  }

  // ---- PDF ----------------------------------------------------------------

  static Future<void> sharePdf(
    Assessment a,
    List<AssessmentSubmission> subs,
  ) async {
    final doc = pw.Document();
    final rows = _rows(a, subs);
    final total = a.expectedStudents;
    doc.addPage(
      pw.MultiPage(
        margin: const pw.EdgeInsets.all(26),
        build: (ctx) => [
          pw.Text(
            'Abbottabad University of Science & Technology',
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            a.title,
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
          pw.Text(
            'Generated: ${DateFormat('dd MMM yyyy, hh:mm a').format(DateTime.now())}'
            '   •   Submitted: ${subs.length}${total > 0 ? ' / $total' : ''}'
            '   •   Out of: ${a.totalMarks}',
            style: const pw.TextStyle(fontSize: 9),
          ),
          pw.SizedBox(height: 10),
          if (rows.isEmpty)
            pw.Text('No submissions scanned yet.')
          else
            pw.Table(
              border: pw.TableBorder.all(width: 0.6),
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(color: PdfColors.grey300),
                  children: [for (final h in _headers) _cell(h, bold: true)],
                ),
                for (final r in rows)
                  pw.TableRow(children: [for (final v in r) _cell(v)]),
              ],
            ),
        ],
      ),
    );
    await Printing.sharePdf(
      bytes: await doc.save(),
      filename: 'Quiz_${_safe(a.title)}_${_stamp()}.pdf',
    );
  }

  static pw.Widget _cell(String t, {bool bold = false}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 3),
    child: pw.Text(
      t,
      style: pw.TextStyle(
        fontSize: 8,
        fontWeight: bold ? pw.FontWeight.bold : null,
      ),
    ),
  );

  static String _safe(String s) =>
      s.replaceAll(RegExp(r'[^A-Za-z0-9]+'), '_');
  static String _stamp() => DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
}
