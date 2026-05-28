import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';

Future<Uint8List> buildFypProformaPdf(FypSubmission submission) async {
  final logoBytes = await rootBundle.load('assets/image1.png');
  final csLogoBytes = await rootBundle.load('assets/cs_logo.jpeg');
  final regularFontBytes = await rootBundle.load('assets/fonts/times.ttf');
  final boldFontBytes = await rootBundle.load('assets/fonts/timesbd.ttf');
  final italicFontBytes = await rootBundle.load('assets/fonts/timesi.ttf');
  final boldItalicFontBytes = await rootBundle.load('assets/fonts/timesbi.ttf');

  final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
  final csLogoImage = pw.MemoryImage(csLogoBytes.buffer.asUint8List());
  final regularFont = pw.Font.ttf(regularFontBytes);
  final boldFont = pw.Font.ttf(boldFontBytes);
  final italicFont = pw.Font.ttf(italicFontBytes);
  final boldItalicFont = pw.Font.ttf(boldItalicFontBytes);

  final document = pw.Document(
    title: '${submission.phase.label} Group Submission Form',
    author: submission.members.isEmpty ? 'AUST' : submission.members.first.name,
    theme: pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: italicFont,
      boldItalic: boldItalicFont,
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
            style: pw.TextStyle(font: boldFont, fontSize: 8),
          ),
        ),
      ),
      build: (context) => [
        _buildHeader(logoImage, csLogoImage, boldFont, boldItalicFont,
            submission: submission),
        pw.SizedBox(height: 12),
        _buildStudentInformationSection(submission, boldFont),
        pw.SizedBox(height: 10),
        _buildMembersTable(submission, boldFont),
        pw.SizedBox(height: 14),
        _buildSignatureSection(submission, boldFont),
        pw.SizedBox(height: 14),
        _buildChecklistSection(submission, boldFont),
        pw.SizedBox(height: 14),
        _buildSupervisorSection(submission, boldFont),
        pw.SizedBox(height: 18),
        _buildFooterSignatures(boldFont),
        pw.SizedBox(height: 10),
        pw.Text(
          'Cc: FYP master file',
          style: pw.TextStyle(font: boldFont, fontSize: 10),
        ),
        pw.SizedBox(height: 14),
        _buildQrFooter(submission, boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _buildHeader(
  pw.MemoryImage logoImage,
  pw.MemoryImage csLogoImage,
  pw.Font boldFont,
  pw.Font boldItalicFont, {
  required FypSubmission submission,
}) {
  return pw.Column(
    children: [
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 62,
            child: pw.Image(logoImage, height: 66, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 8),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(
                  'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldItalicFont, fontSize: 15.5),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  'Department of Computer Science',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldFont, fontSize: 11.5),
                ),
                pw.SizedBox(height: 4),
                pw.Text(
                  '${submission.phase.label} Group Submission Form',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldFont, fontSize: 13.5),
                ),
                pw.SizedBox(height: 2),
                pw.Text(
                  submission.term,
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldFont, fontSize: 11),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 8),
          pw.SizedBox(
            width: 62,
            child: pw.Image(csLogoImage, height: 66, fit: pw.BoxFit.contain),
          ),
        ],
      ),
      pw.SizedBox(height: 6),
      pw.Container(height: 1, color: PdfColors.black),
    ],
  );
}

pw.Widget _buildStudentInformationSection(
  FypSubmission submission,
  pw.Font boldFont,
) {
  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Text(
        'Student Information',
        style: pw.TextStyle(font: boldFont, fontSize: 12.5),
      ),
      pw.SizedBox(width: 18),
      _checkbox(
        label: 'BSCS',
        checked: submission.program == FypProgram.bscs,
        boldFont: boldFont,
      ),
      pw.SizedBox(width: 18),
      _checkbox(
        label: 'BSSE',
        checked: submission.program == FypProgram.bsse,
        boldFont: boldFont,
      ),
    ],
  );
}

pw.Widget _buildMembersTable(FypSubmission submission, pw.Font boldFont) {
  final headerCells = ['Sr. No', 'Roll No', 'Name', 'Email'];
  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
      children: headerCells
          .map(
            (header) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 6,
                vertical: 4,
              ),
              child: pw.Text(
                header,
                style: pw.TextStyle(font: boldFont, fontSize: 10),
              ),
            ),
          )
          .toList(),
    ),
  ];

  final members = [...submission.members];
  while (members.length < 2) {
    members.add(
      FypMember(
        serialNo: members.length + 1,
        rollNo: '',
        name: '',
        email: '',
      ),
    );
  }

  for (final member in members) {
    rows.add(
      pw.TableRow(
        children: [
          _cell('${member.serialNo}', alignCenter: true),
          _cell(member.rollNo),
          _cell(member.name),
          _cell(member.email),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(width: 0.7, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(46),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(3),
      3: pw.FlexColumnWidth(4),
    },
    children: rows,
  );
}

pw.Widget _buildSignatureSection(FypSubmission submission, pw.Font boldFont) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Student Signatures',
        style: pw.TextStyle(font: boldFont, fontSize: 11),
      ),
      pw.SizedBox(height: 8),
      for (final member in submission.members)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 8),
          child: pw.Row(
            children: [
              pw.Text(
                'Signature: ',
                style: pw.TextStyle(font: boldFont, fontSize: 10),
              ),
              pw.SizedBox(
                width: 180,
                child: pw.Container(
                  height: 14,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 14),
              pw.Text(
                'Date: ',
                style: pw.TextStyle(font: boldFont, fontSize: 10),
              ),
              pw.SizedBox(
                width: 110,
                child: pw.Container(
                  height: 14,
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(width: 0.6, color: PdfColors.black),
                    ),
                  ),
                ),
              ),
              pw.SizedBox(width: 12),
              pw.Text(
                member.name.isEmpty ? '(${member.serialNo})' : member.name,
                style: const pw.TextStyle(fontSize: 9.5),
              ),
            ],
          ),
        ),
    ],
  );
}

pw.Widget _buildChecklistSection(FypSubmission submission, pw.Font boldFont) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      _checkbox(
        label: 'I have joined WhatsApp group for ${submission.phase.label}',
        checked: submission.joinedWhatsApp,
        boldFont: boldFont,
      ),
      pw.SizedBox(height: 6),
      _checkbox(
        label:
            'I have joined Google Classroom for ${submission.phase.label}',
        checked: submission.joinedGoogleClassroom,
        boldFont: boldFont,
      ),
    ],
  );
}

pw.Widget _buildSupervisorSection(FypSubmission submission, pw.Font boldFont) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Supervision Preference',
        style: pw.TextStyle(font: boldFont, fontSize: 11),
      ),
      pw.SizedBox(height: 6),
      pw.Row(
        children: [
          pw.Text(
            'Preferred Supervisor: ',
            style: pw.TextStyle(font: boldFont, fontSize: 10),
          ),
          pw.Expanded(
            child: pw.Text(
              submission.preferredSupervisor.isEmpty
                  ? '________________________________________'
                  : submission.preferredSupervisor,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Row(
        children: [
          pw.Text(
            'Preferred Co-supervisor: ',
            style: pw.TextStyle(font: boldFont, fontSize: 10),
          ),
          pw.Expanded(
            child: pw.Text(
              submission.preferredCoSupervisor.isEmpty
                  ? '________________________________________'
                  : submission.preferredCoSupervisor,
              style: const pw.TextStyle(fontSize: 10),
            ),
          ),
        ],
      ),
    ],
  );
}

pw.Widget _buildFooterSignatures(pw.Font boldFont) {
  pw.Widget block(String label) {
    return pw.Expanded(
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.Container(
            height: 22,
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                bottom: pw.BorderSide(width: 0.7, color: PdfColors.black),
              ),
            ),
          ),
          pw.SizedBox(height: 4),
          pw.Text(
            label,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: 10),
          ),
        ],
      ),
    );
  }

  return pw.Column(
    children: [
      pw.Row(
        children: [
          block('FYP Coordinator'),
          pw.SizedBox(width: 40),
          block('HoD'),
        ],
      ),
      pw.SizedBox(height: 4),
      pw.Text(
        'Department of Computer Science, AUST',
        style: pw.TextStyle(font: boldFont, fontSize: 10),
      ),
    ],
  );
}

pw.Widget _buildQrFooter(FypSubmission submission, pw.Font boldFont) {
  return pw.Container(
    padding: const pw.EdgeInsets.all(10),
    decoration: pw.BoxDecoration(
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
      borderRadius: pw.BorderRadius.circular(8),
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.SizedBox(
          width: 80,
          height: 80,
          child: pw.BarcodeWidget(
            barcode: pw.Barcode.qrCode(),
            data: submission.qrCode,
            drawText: false,
          ),
        ),
        pw.SizedBox(width: 14),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                'Supervisor verification',
                style: pw.TextStyle(font: boldFont, fontSize: 11),
              ),
              pw.SizedBox(height: 4),
              pw.Text(
                'Faculty members can scan this QR with the AUST teacher app to view this submission and mark themselves as interested supervisor or co-supervisor.',
                style: const pw.TextStyle(fontSize: 9, lineSpacing: 1),
              ),
              pw.SizedBox(height: 6),
              pw.Text(
                'Submission ID: ${submission.id}',
                style: pw.TextStyle(font: boldFont, fontSize: 9),
              ),
              pw.Text(
                'QR Code: ${submission.qrCode}',
                style: const pw.TextStyle(fontSize: 9),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

pw.Widget _checkbox({
  required String label,
  required bool checked,
  required pw.Font boldFont,
}) {
  return pw.Row(
    mainAxisSize: pw.MainAxisSize.min,
    crossAxisAlignment: pw.CrossAxisAlignment.center,
    children: [
      pw.Container(
        width: 12,
        height: 12,
        decoration: pw.BoxDecoration(
          border: pw.Border.all(width: 0.8, color: PdfColors.black),
        ),
        alignment: pw.Alignment.center,
        child: checked
            ? pw.Text(
                'X',
                style: pw.TextStyle(font: boldFont, fontSize: 10),
              )
            : pw.SizedBox(),
      ),
      pw.SizedBox(width: 6),
      pw.Text(label, style: pw.TextStyle(font: boldFont, fontSize: 10)),
    ],
  );
}

pw.Widget _cell(String text, {bool alignCenter = false}) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 5),
    child: pw.Text(
      text,
      textAlign: alignCenter ? pw.TextAlign.center : pw.TextAlign.left,
      style: const pw.TextStyle(fontSize: 10),
    ),
  );
}
