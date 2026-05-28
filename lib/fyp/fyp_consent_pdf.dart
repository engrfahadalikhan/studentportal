import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #7 — Supervisor Consent Form.
/// The supervisor signs to allow the group to appear for selected
/// evaluations (Proposal Defense, SRS, SDS, Progress, Internal, External).
Future<Uint8List> buildFypConsentPdf(FypEvaluationConsent consent) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'Supervisor Consent — ${consent.fypTitle}',
    author: consent.supervisorName,
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
          formTitle: 'Supervisor Consent Form',
          subTitle: consent.term,
        ),
        pw.SizedBox(height: 14),
        fypInfoTable(
          [
            ['Supervisor Name', consent.supervisorName],
            ['FYP Title', consent.fypTitle],
            ['Program', consent.program.label],
          ],
          assets.boldFont,
          labelWidth: 140,
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Group Members', assets.boldFont),
        pw.SizedBox(height: 6),
        _membersTable(consent.members, assets.boldFont),
        pw.SizedBox(height: 14),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.6, color: PdfColors.black),
          ),
          child: pw.Text(
            'I have read the documentation and evaluated the students. '
            'I am satisfied with their progress, I approve the document '
            'and allow the students to appear for the following evaluation:',
            style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.3),
          ),
        ),
        pw.SizedBox(height: 12),
        _evaluationsGrid(consent.approvedEvaluations, assets.boldFont),
        pw.SizedBox(height: 18),
        pw.Row(
          children: [
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Supervisor Name & Signature',
                    style: pw.TextStyle(font: assets.boldFont, fontSize: 10),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    consent.supervisorName,
                    style: pw.TextStyle(font: assets.boldFont, fontSize: 11),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(
                    height: 1,
                    color: PdfColors.black,
                  ),
                ],
              ),
            ),
            pw.SizedBox(width: 30),
            pw.SizedBox(
              width: 160,
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Text(
                    'Date',
                    style: pw.TextStyle(font: assets.boldFont, fontSize: 10),
                  ),
                  pw.SizedBox(height: 6),
                  pw.Text(
                    consent.signedAt.toIso8601String().substring(0, 10),
                    style: const pw.TextStyle(fontSize: 11),
                  ),
                  pw.SizedBox(height: 20),
                  pw.Container(height: 1, color: PdfColors.black),
                ],
              ),
            ),
          ],
        ),
        pw.SizedBox(height: 18),
        fypQrPanel(
          qrData: consent.qrCode,
          caption: 'Evaluation panel verification',
          captionDetail:
              'Scan to confirm the supervisor has approved this group for the evaluations checked above.',
          boldFont: assets.boldFont,
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _membersTable(List<FypMember> members, pw.Font boldFont) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(80),
      1: pw.FlexColumnWidth(3),
      2: pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(
        decoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
        children: [
          _cell('', boldFont: boldFont, bold: true),
          _cell('Name', boldFont: boldFont, bold: true),
          _cell('Roll No', boldFont: boldFont, bold: true),
        ],
      ),
      for (final member in members)
        pw.TableRow(
          children: [
            _cell(
              'Group Member ${member.serialNo}',
              boldFont: boldFont,
              bold: true,
            ),
            _cell(member.name),
            _cell(member.rollNo),
          ],
        ),
    ],
  );
}

pw.Widget _evaluationsGrid(
  List<FypEvaluationType> approved,
  pw.Font boldFont,
) {
  return pw.Wrap(
    spacing: 12,
    runSpacing: 8,
    children: [
      for (final type in FypEvaluationType.values)
        pw.SizedBox(
          width: 165,
          child: pw.Row(
            children: [
              pw.Container(
                width: 12,
                height: 12,
                decoration: pw.BoxDecoration(
                  border: pw.Border.all(width: 0.8, color: PdfColors.black),
                ),
                alignment: pw.Alignment.center,
                child: approved.contains(type)
                    ? pw.Text(
                        'X',
                        style: pw.TextStyle(font: boldFont, fontSize: 10),
                      )
                    : pw.SizedBox(),
              ),
              pw.SizedBox(width: 6),
              pw.Expanded(
                child: pw.Text(
                  type.label,
                  style: const pw.TextStyle(fontSize: 9.5),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _cell(String text, {bool bold = false, pw.Font? boldFont}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      text.isEmpty ? '—' : text,
      style: pw.TextStyle(
        font: bold ? boldFont : null,
        fontSize: 9.5,
      ),
    ),
  );
}
