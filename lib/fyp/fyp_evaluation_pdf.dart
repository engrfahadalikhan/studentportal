import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Forms #8 (Proposal Evaluation) and #11 (SRS Evaluation) share the same
/// rubric layout — this single builder handles both.
Future<Uint8List> buildFypEvaluationPdf(FypEvaluation evaluation) async {
  final assets = await FypPdfAssets.load();

  final formTitle = '${evaluation.kind.label} Evaluation Form';

  final document = pw.Document(
    title: '$formTitle — ${evaluation.projectTitle}',
    author: evaluation.examinerName,
    theme: pw.ThemeData.withFont(
      base: assets.regularFont,
      bold: assets.boldFont,
      italic: assets.italicFont,
      boldItalic: assets.boldItalicFont,
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 22, 28, 18),
      build: (context) => [
        fypHeader(
          assets,
          formTitle: formTitle,
          subTitle: evaluation.term,
        ),
        pw.SizedBox(height: 10),
        _scaleLegend(assets.boldFont),
        pw.SizedBox(height: 12),
        fypInfoTable(
          [
            ['FYP Title', evaluation.projectTitle],
            ['Supervised by', evaluation.supervisorName],
            [
              'Group Members',
              evaluation.members
                  .map((m) => '${m.serialNo}. ${m.name} (${m.rollNo})')
                  .join('\n'),
            ],
          ],
          assets.boldFont,
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Technical Evaluation', assets.boldFont),
        pw.SizedBox(height: 6),
        _rubricTable(evaluation.rubric, assets.boldFont),
        pw.SizedBox(height: 14),
        _totalsRow(evaluation, assets.boldFont),
        pw.SizedBox(height: 16),
        fypInfoTable(
          [
            ['Examiner Name', evaluation.examinerName],
            [
              'Marks obtained',
              '${evaluation.marksObtained} / ${evaluation.marksMax}',
            ],
            [
              'Date',
              evaluation.submittedAt.toIso8601String().substring(0, 10),
            ],
          ],
          assets.boldFont,
          labelWidth: 140,
        ),
        pw.SizedBox(height: 12),
        pw.Text(
          'Cc: Group Supervisor, FYP Coordinator, FYP master file',
          style: pw.TextStyle(font: assets.boldFont, fontSize: 10),
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _scaleLegend(pw.Font boldFont) {
  return pw.Row(
    children: [
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          color: const PdfColor.fromInt(0xFFFEE2E2),
          child: pw.Text(
            '1–2 : Does not meet expectations',
            style: pw.TextStyle(font: boldFont, fontSize: 9),
          ),
        ),
      ),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          color: const PdfColor.fromInt(0xFFFEF9C3),
          child: pw.Text(
            '3 : Meets expectations',
            style: pw.TextStyle(font: boldFont, fontSize: 9),
          ),
        ),
      ),
      pw.SizedBox(width: 6),
      pw.Expanded(
        child: pw.Container(
          padding: const pw.EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 5,
          ),
          color: const PdfColor.fromInt(0xFFDCFCE7),
          child: pw.Text(
            '4–5 : Exceeds expectations',
            style: pw.TextStyle(font: boldFont, fontSize: 9),
          ),
        ),
      ),
    ],
  );
}

pw.Widget _rubricTable(List<FypRubricRow> rubric, pw.Font boldFont) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(40),
      1: pw.FlexColumnWidth(5),
      2: pw.FixedColumnWidth(60),
      3: pw.FixedColumnWidth(40),
    },
    children: [
      pw.TableRow(
        decoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
        children: [
          _cell('Sr. No', bold: true, boldFont: boldFont),
          _cell('Dimension', bold: true, boldFont: boldFont),
          _cell('Max Marks', bold: true, boldFont: boldFont),
          _cell('Score (1–5)', bold: true, boldFont: boldFont),
        ],
      ),
      for (var index = 0; index < rubric.length; index++)
        pw.TableRow(
          children: [
            _cell('${index + 1}'),
            _cell(rubric[index].label),
            _cell('${rubric[index].maxMarks}'),
            _cell(
              rubric[index].score == 0 ? '—' : '${rubric[index].score}',
              bold: true,
              boldFont: boldFont,
            ),
          ],
        ),
    ],
  );
}

pw.Widget _totalsRow(FypEvaluation evaluation, pw.Font boldFont) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    color: const PdfColor.fromInt(0xFFE9E8F6),
    child: pw.Row(
      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
      children: [
        pw.Text(
          'Total Score',
          style: pw.TextStyle(font: boldFont, fontSize: 12),
        ),
        pw.Text(
          '${evaluation.marksObtained} / ${evaluation.marksMax}',
          style: pw.TextStyle(font: boldFont, fontSize: 12),
        ),
      ],
    ),
  );
}

pw.Widget _cell(String text, {bool bold = false, pw.Font? boldFont}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      text,
      style: pw.TextStyle(
        font: bold ? boldFont : null,
        fontSize: 9.5,
      ),
    ),
  );
}
