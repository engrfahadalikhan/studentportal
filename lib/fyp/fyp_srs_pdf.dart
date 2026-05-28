import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #10 — Software Requirements Specification (IEEE-style template).
/// The full IEEE template is a long document; this builder produces a
/// structured PDF capturing the key sections the student writes inside the
/// app, sized for review by the supervisor and evaluation panel.
Future<Uint8List> buildFypSrsPdf(FypSrs srs) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'SRS — ${srs.title}',
    author: srs.members.isEmpty ? 'AUST' : srs.members.first.name,
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
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 4),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(font: assets.boldFont, fontSize: 8),
          ),
        ),
      ),
      build: (context) => [
        fypHeader(
          assets,
          formTitle: 'Software Requirements Specification',
          subTitle: srs.term,
        ),
        pw.SizedBox(height: 14),
        pw.Center(
          child: pw.Text(
            srs.title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: assets.boldFont, fontSize: 15),
          ),
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Project information', assets.boldFont),
        pw.SizedBox(height: 6),
        fypInfoTable(
          [
            ['Supervisor', srs.supervisorName],
            if (srs.coSupervisorName.isNotEmpty)
              ['Co-supervisor', srs.coSupervisorName],
            [
              'Group Members',
              srs.members
                  .map((m) =>
                      '${m.serialNo}. ${m.name} (${m.rollNo})')
                  .join('\n'),
            ],
          ],
          assets.boldFont,
          labelWidth: 130,
        ),
        pw.SizedBox(height: 12),
        for (final section in srs.sections) ...[
          _srsSection(section, assets.boldFont),
          pw.SizedBox(height: 8),
        ],
        pw.SizedBox(height: 12),
        fypQrPanel(
          qrData: srs.qrCode,
          caption: 'SRS lookup',
          captionDetail:
              'Faculty / evaluation panel can scan this QR to pull up this SRS record and the matching SRS evaluation marks.',
          boldFont: assets.boldFont,
        ),
        pw.SizedBox(height: 14),
        fypFooterSignatures(
          assets.boldFont,
          leftLabel: 'Group Supervisor',
          rightLabel: 'FYP Coordinator',
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _srsSection(FypSrsSection section, pw.Font boldFont) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          section.heading,
          style: pw.TextStyle(font: boldFont, fontSize: 11.5),
        ),
        pw.SizedBox(height: 5),
        pw.Text(
          section.body.isEmpty ? '—' : section.body,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.3),
        ),
      ],
    ),
  );
}
