import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #6 — FYP-I Proposal Presentation slides.
///
/// Same proposal data as form #5 but rendered as a 16:9 slide deck:
/// title slide → project info → group → supervisors → registration →
/// closing thank-you. Students can show this directly on a projector.
Future<Uint8List> buildFypProposalSlidesPdf(FypProposal proposal) async {
  final assets = await FypPdfAssets.load();

  const slideFormat = PdfPageFormat(960, 540);

  final document = pw.Document(
    title: 'Proposal slides — ${proposal.title}',
    author: proposal.members.isEmpty ? 'AUST' : proposal.members.first.name,
    theme: pw.ThemeData.withFont(
      base: assets.regularFont,
      bold: assets.boldFont,
      italic: assets.italicFont,
      boldItalic: assets.boldItalicFont,
    ),
  );

  pw.Page slide({required pw.Widget child, String? slideTitle}) {
    return pw.Page(
      pageFormat: slideFormat,
      margin: const pw.EdgeInsets.fromLTRB(36, 28, 36, 28),
      build: (context) => pw.Stack(
        children: [
          // Decorative top bar with logos.
          pw.Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: pw.Container(
              height: 6,
              decoration: const pw.BoxDecoration(
                gradient: pw.LinearGradient(
                  colors: [
                    PdfColor.fromInt(0xFF2948B7),
                    PdfColor.fromInt(0xFF6E27C5),
                  ],
                ),
              ),
            ),
          ),
          pw.Padding(
            padding: const pw.EdgeInsets.fromLTRB(0, 18, 0, 0),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                if (slideTitle != null)
                  _slideHeader(slideTitle, assets, boldFont: assets.boldFont),
                pw.SizedBox(height: 12),
                pw.Expanded(child: child),
                pw.SizedBox(height: 6),
                _slideFooter(proposal, assets.boldFont),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // Slide 1: Title
  document.addPage(
    slide(
      child: pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              children: [
                pw.SizedBox(
                  width: 70,
                  child: pw.Image(assets.logoImage, height: 80),
                ),
                pw.SizedBox(width: 16),
                pw.SizedBox(
                  width: 70,
                  child: pw.Image(assets.csLogoImage, height: 80),
                ),
              ],
            ),
            pw.SizedBox(height: 22),
            pw.Text(
              'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
              style:
                  pw.TextStyle(font: assets.boldItalicFont, fontSize: 16),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 4),
            pw.Text(
              'Department of Computer Science',
              style: pw.TextStyle(font: assets.boldFont, fontSize: 12),
              textAlign: pw.TextAlign.center,
            ),
            pw.SizedBox(height: 30),
            pw.Container(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 18,
                vertical: 8,
              ),
              decoration: pw.BoxDecoration(
                color: const PdfColor.fromInt(0xFFE9E8F6),
                borderRadius: pw.BorderRadius.circular(999),
              ),
              child: pw.Text(
                'Final Year Project Proposal • ${proposal.term}',
                style: pw.TextStyle(font: assets.boldFont, fontSize: 12),
              ),
            ),
            pw.SizedBox(height: 24),
            pw.Text(
              proposal.title,
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: assets.boldFont, fontSize: 28),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              proposal.areaOfSpecialization.isEmpty
                  ? proposal.projectType.label
                  : '${proposal.projectType.label} • ${proposal.areaOfSpecialization}',
              style: pw.TextStyle(
                font: assets.italicFont,
                fontSize: 14,
                color: const PdfColor.fromInt(0xFF505081),
              ),
            ),
          ],
        ),
      ),
    ),
  );

  // Slide 2: Project Registration
  document.addPage(
    slide(
      slideTitle: 'Project Registration',
      child: _kvSlide(
        entries: [
          ['Project ID', proposal.projectId.isEmpty ? '(office use)' : proposal.projectId],
          ['Type', proposal.projectType.label],
          ['Area of specialization', proposal.areaOfSpecialization],
          ['Term', proposal.term],
        ],
        assets: assets,
      ),
    ),
  );

  // Slide 3: Group Members
  document.addPage(
    slide(
      slideTitle: 'Project Group',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          for (final member in proposal.members)
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 14),
              child: pw.Row(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    width: 34,
                    height: 34,
                    alignment: pw.Alignment.center,
                    decoration: const pw.BoxDecoration(
                      shape: pw.BoxShape.circle,
                      color: PdfColor.fromInt(0xFF2948B7),
                    ),
                    child: pw.Text(
                      '${member.serialNo}',
                      style: pw.TextStyle(
                        font: assets.boldFont,
                        color: PdfColors.white,
                        fontSize: 14,
                      ),
                    ),
                  ),
                  pw.SizedBox(width: 16),
                  pw.Expanded(
                    child: pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        pw.Text(
                          member.name.isEmpty ? '—' : member.name,
                          style: pw.TextStyle(
                            font: assets.boldFont,
                            fontSize: 18,
                          ),
                        ),
                        pw.SizedBox(height: 3),
                        pw.Text(
                          [
                            if (member.rollNo.isNotEmpty)
                              'Roll: ${member.rollNo}',
                            if (member.cgpa.isNotEmpty)
                              'CGPA: ${member.cgpa}',
                            if (member.email.isNotEmpty) member.email,
                            if (member.phone.isNotEmpty) member.phone,
                          ].join('  •  '),
                          style: const pw.TextStyle(
                            fontSize: 11,
                            color: PdfColor.fromInt(0xFF505081),
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (member.serialNo == 1)
                    pw.Container(
                      padding: const pw.EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: pw.BoxDecoration(
                        color: const PdfColor.fromInt(0xFFE9E8F6),
                        borderRadius: pw.BorderRadius.circular(999),
                      ),
                      child: pw.Text(
                        'Group Leader',
                        style: pw.TextStyle(
                          font: assets.boldFont,
                          fontSize: 10,
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    ),
  );

  // Slide 4: Supervisors
  document.addPage(
    slide(
      slideTitle: 'Supervisors',
      child: _kvSlide(
        entries: [
          ['Supervisor', proposal.supervisorName],
          [
            'Supervisor Designation',
            proposal.supervisorDesignation,
          ],
          if (proposal.coSupervisorName.isNotEmpty) ...[
            ['Co-supervisor', proposal.coSupervisorName],
            ['Co-supervisor Designation', proposal.coSupervisorDesignation],
          ],
        ],
        assets: assets,
      ),
    ),
  );

  // Slide 5: Plagiarism Free Certificate
  document.addPage(
    slide(
      slideTitle: 'Plagiarism Free Certificate',
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Text(
            'I, ${proposal.members.isEmpty ? '____________' : proposal.members.first.name}, '
            'group leader of FYP under roll no '
            '${proposal.members.isEmpty ? '____________' : proposal.members.first.rollNo} '
            'at the Computer Science Department, Abbottabad UST, declare that '
            'my FYP proposal is checked by my supervisor and the similarity '
            'index is ${proposal.similarityIndex.isEmpty ? '____' : proposal.similarityIndex}% '
            '— less than the 20% HEC acceptable limit.',
            style: const pw.TextStyle(fontSize: 14, lineSpacing: 1.5),
          ),
          pw.SizedBox(height: 18),
          pw.Container(
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: const PdfColor.fromInt(0xFFE9E8F6),
              borderRadius: pw.BorderRadius.circular(10),
            ),
            child: pw.Row(
              children: [
                pw.Text(
                  'Similarity index: ',
                  style: pw.TextStyle(font: assets.boldFont, fontSize: 13),
                ),
                pw.Text(
                  proposal.similarityIndex.isEmpty
                      ? '— pending —'
                      : '${proposal.similarityIndex}%',
                  style: pw.TextStyle(
                    font: assets.boldFont,
                    fontSize: 16,
                    color: const PdfColor.fromInt(0xFF0F766E),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );

  // Slide 6: Thank you / QR
  document.addPage(
    slide(
      child: pw.Center(
        child: pw.Column(
          mainAxisAlignment: pw.MainAxisAlignment.center,
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            pw.Text(
              'Thank you',
              style: pw.TextStyle(font: assets.boldFont, fontSize: 44),
            ),
            pw.SizedBox(height: 16),
            pw.Text(
              'Questions & feedback welcomed.',
              style: pw.TextStyle(
                font: assets.italicFont,
                fontSize: 16,
                color: const PdfColor.fromInt(0xFF505081),
              ),
            ),
            pw.SizedBox(height: 28),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(
                  width: 0.6,
                  color: PdfColors.black,
                ),
              ),
              child: pw.SizedBox(
                width: 110,
                height: 110,
                child: pw.BarcodeWidget(
                  barcode: pw.Barcode.qrCode(),
                  data: proposal.qrCode,
                  drawText: false,
                ),
              ),
            ),
            pw.SizedBox(height: 6),
            pw.Text(
              proposal.qrCode,
              style: pw.TextStyle(font: assets.boldFont, fontSize: 11),
            ),
          ],
        ),
      ),
    ),
  );

  return document.save();
}

pw.Widget _slideHeader(
  String title,
  FypPdfAssets assets, {
  required pw.Font boldFont,
}) {
  return pw.Row(
    children: [
      pw.SizedBox(
        width: 32,
        child: pw.Image(assets.csLogoImage, height: 36),
      ),
      pw.SizedBox(width: 10),
      pw.Expanded(
        child: pw.Text(
          title,
          style: pw.TextStyle(font: boldFont, fontSize: 24),
        ),
      ),
    ],
  );
}

pw.Widget _slideFooter(FypProposal proposal, pw.Font boldFont) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'AUST • Department of Computer Science',
        style: const pw.TextStyle(
          fontSize: 9,
          color: PdfColor.fromInt(0xFF8686AC),
        ),
      ),
      pw.Text(
        proposal.id,
        style: pw.TextStyle(
          font: boldFont,
          fontSize: 9,
          color: const PdfColor.fromInt(0xFF8686AC),
        ),
      ),
    ],
  );
}

pw.Widget _kvSlide({
  required List<List<String>> entries,
  required FypPdfAssets assets,
}) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      for (final entry in entries)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 14),
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.SizedBox(
                width: 220,
                child: pw.Text(
                  entry[0],
                  style: pw.TextStyle(
                    font: assets.boldFont,
                    fontSize: 16,
                    color: const PdfColor.fromInt(0xFF505081),
                  ),
                ),
              ),
              pw.Expanded(
                child: pw.Text(
                  entry[1].isEmpty ? '—' : entry[1],
                  style: pw.TextStyle(font: assets.boldFont, fontSize: 18),
                ),
              ),
            ],
          ),
        ),
    ],
  );
}
