import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #2 — Faculty submits a Final Year Project idea.
Future<Uint8List> buildFypIdeaPdf(FypIdea idea) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'FYP Idea — ${idea.title}',
    author: idea.facultyName,
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
          formTitle: 'Final Year Project Idea',
          subTitle: idea.term,
        ),
        pw.SizedBox(height: 12),
        fypInfoTable(
          [
            ['Supervisor', idea.supervisor],
            ['Co-Supervisor (if any)', idea.coSupervisor],
            ['Faculty email', idea.facultyEmail],
            ['Title', idea.title],
            ['Project domain', idea.projectDomain],
          ],
          assets.boldFont,
          labelWidth: 140,
        ),
        pw.SizedBox(height: 10),
        fypSectionTitle('Description', assets.boldFont),
        pw.SizedBox(height: 6),
        pw.Text(
          idea.description.isEmpty ? '—' : idea.description,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
        ),
        pw.SizedBox(height: 10),
        fypSectionTitle('Tools and technologies', assets.boldFont),
        pw.SizedBox(height: 6),
        pw.Text(
          idea.tools.isEmpty ? '—' : idea.tools,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
        ),
        pw.SizedBox(height: 10),
        fypSectionTitle('Additional information', assets.boldFont),
        pw.SizedBox(height: 6),
        pw.Text(
          idea.additionalInfo.isEmpty ? '—' : idea.additionalInfo,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
        ),
        pw.SizedBox(height: 18),
        fypQrPanel(
          qrData: idea.id,
          caption: 'Students can scan to pick this project',
          captionDetail:
              'After scanning in the student app, the group can claim this idea and submit their allocation form against the supervisor named above.',
          boldFont: assets.boldFont,
        ),
        pw.SizedBox(height: 14),
        fypFooterSignatures(
          assets.boldFont,
          leftLabel: 'Faculty Signature',
          rightLabel: 'FYP Coordinator',
        ),
      ],
    ),
  );

  return document.save();
}
