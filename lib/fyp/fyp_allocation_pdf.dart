import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #3 — FYP Supervisor Allocation Form (BS Programs).
Future<Uint8List> buildFypAllocationPdf(FypAllocation allocation) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'FYP Supervisor Allocation — ${allocation.projectTitle}',
    author: allocation.members.isEmpty
        ? 'AUST'
        : allocation.members.first.name,
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
          formTitle: 'FYP Supervisor Allocation Form (BS Programs)',
          subTitle: allocation.term,
        ),
        pw.SizedBox(height: 12),
        fypInfoTable(
          [
            ['Project Title', allocation.projectTitle],
            ['Expected Outcome', allocation.expectedOutcome],
          ],
          assets.boldFont,
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Students Details', assets.boldFont),
        pw.SizedBox(height: 6),
        for (final member in allocation.members)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 8),
            child: _memberBlock(member, assets.boldFont),
          ),
        pw.SizedBox(height: 8),
        _signatureRow(assets.boldFont, 'Student Signatures'),
        pw.SizedBox(height: 12),
        _supervisorBlock(
          label:
              'Main Supervisor (I declare that, I agree to supervise these students)',
          name: allocation.supervisorName,
          email: allocation.supervisorEmail,
          approvedAt: allocation.supervisorApprovedAt,
          boldFont: assets.boldFont,
        ),
        pw.SizedBox(height: 10),
        if (allocation.coSupervisorName.isNotEmpty)
          _supervisorBlock(
            label:
                'Co-Supervisor (I declare that, I agree to co-supervise these students)',
            name: allocation.coSupervisorName,
            email: allocation.coSupervisorEmail,
            approvedAt: allocation.coSupervisorApprovedAt,
            boldFont: assets.boldFont,
          ),
        pw.SizedBox(height: 10),
        pw.Text(
          '* Students must attach complete transcript of 6 semesters.',
          style: pw.TextStyle(
            font: assets.italicFont,
            fontSize: 9.5,
          ),
        ),
        pw.SizedBox(height: 14),
        fypQrPanel(
          qrData: allocation.qrCode,
          caption: 'Supervisor / Co-Supervisor verification',
          captionDetail:
              'Faculty members named above can scan this QR in the teacher app to approve the allocation. Approvals are timestamped and reflected on this form.',
          boldFont: assets.boldFont,
        ),
        pw.SizedBox(height: 14),
        fypFooterSignatures(
          assets.boldFont,
          leftLabel: 'FYP Coordinator',
          rightLabel: 'Chairman, Department of Computer Science, AUST',
        ),
      ],
    ),
  );

  return document.save();
}

pw.Widget _memberBlock(FypMember member, pw.Font boldFont) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          'Group Member ${member.serialNo}',
          style: pw.TextStyle(font: boldFont, fontSize: 10.5),
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            _kv('Roll No', member.rollNo, boldFont),
            _kv('Name', member.name, boldFont),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            _kv('Email', member.email, boldFont),
            _kv('CGPA', member.cgpa, boldFont),
          ],
        ),
      ],
    ),
  );
}

pw.Widget _kv(String label, String value, pw.Font boldFont) {
  return pw.Expanded(
    child: pw.RichText(
      text: pw.TextSpan(
        children: [
          pw.TextSpan(
            text: '$label: ',
            style: pw.TextStyle(font: boldFont, fontSize: 9.5),
          ),
          pw.TextSpan(
            text: value.isEmpty ? '—' : value,
            style: const pw.TextStyle(fontSize: 9.5),
          ),
        ],
      ),
    ),
  );
}

pw.Widget _signatureRow(pw.Font boldFont, String heading) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        heading,
        style: pw.TextStyle(font: boldFont, fontSize: 11),
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          for (var i = 1; i <= 2; i++) ...[
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    height: 22,
                    decoration: const pw.BoxDecoration(
                      border: pw.Border(
                        bottom: pw.BorderSide(
                          width: 0.7,
                          color: PdfColors.black,
                        ),
                      ),
                    ),
                  ),
                  pw.SizedBox(height: 3),
                  pw.Text(
                    'Group Member $i',
                    style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            if (i == 1) pw.SizedBox(width: 30),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _supervisorBlock({
  required String label,
  required String name,
  required String email,
  required DateTime? approvedAt,
  required pw.Font boldFont,
}) {
  final approvedText = approvedAt == null
      ? 'Pending'
      : 'Approved on ${approvedAt.toIso8601String().substring(0, 10)}';
  return pw.Container(
    padding: const pw.EdgeInsets.all(8),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
    ),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Text(
          label,
          style: pw.TextStyle(font: boldFont, fontSize: 10),
        ),
        pw.SizedBox(height: 5),
        pw.Row(
          children: [
            _kv('Name', name, boldFont),
            _kv('Email', email, boldFont),
          ],
        ),
        pw.SizedBox(height: 4),
        pw.Row(
          children: [
            pw.Text(
              'Signature: ',
              style: pw.TextStyle(font: boldFont, fontSize: 9.5),
            ),
            pw.Expanded(
              child: pw.Container(
                height: 14,
                decoration: const pw.BoxDecoration(
                  border: pw.Border(
                    bottom:
                        pw.BorderSide(width: 0.6, color: PdfColors.black),
                  ),
                ),
              ),
            ),
            pw.SizedBox(width: 12),
            pw.Text(
              approvedText,
              style: pw.TextStyle(
                font: boldFont,
                fontSize: 9.5,
                color: approvedAt == null
                    ? const PdfColor.fromInt(0xFFB45309)
                    : const PdfColor.fromInt(0xFF0F766E),
              ),
            ),
          ],
        ),
      ],
    ),
  );
}
