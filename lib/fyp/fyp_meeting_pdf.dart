import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #14 — Supervisor Meeting Log.
///
/// Section 1 is filled by the students BEFORE the meeting.
/// Section 2 is filled by the supervisor AT the meeting.
Future<Uint8List> buildFypMeetingLogPdf(FypMeetingLog log) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'FYP Meeting Log — ${log.projectTitle}',
    author: log.members.isEmpty ? 'AUST' : log.members.first.name,
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
          formTitle: 'Meeting Log (FYP)',
          subTitle: log.term,
        ),
        pw.SizedBox(height: 12),
        _sectionBanner(
          'SECTION 1  (To be completed by the students prior to meeting)',
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        fypInfoTable(
          [
            ['Title of Project', log.projectTitle],
            ['Supervisor Name', log.supervisorName],
            ['Program', log.program.label],
            [
              'Student Names with Roll No.',
              log.members
                  .map((m) =>
                      '${m.serialNo}. ${m.name} (${m.rollNo})')
                  .join('\n'),
            ],
            ['Date', log.meetingDate],
            ['Date of Previous Meeting', log.previousMeetingDate],
          ],
          assets.boldFont,
          labelWidth: 170,
        ),
        pw.SizedBox(height: 8),
        _longField(
          'Work done since last meeting',
          log.workDoneSinceLastMeeting,
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        _longField(
          'Issues / tasks to be discussed',
          log.issuesToDiscuss,
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        _signatureRow('Signatures (Students)', assets.boldFont, log.members),
        pw.SizedBox(height: 14),
        _sectionBanner(
          'SECTION 2  (To be completed by the supervisor at the time of meeting)',
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        _longField(
          'Tasks assigned to students',
          log.tasksAssigned,
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        fypInfoTable(
          [
            ['Date of next meeting', log.nextMeetingDate],
            [
              'Supervisor signed at',
              log.supervisorSignedAt == null
                  ? '— pending —'
                  : log.supervisorSignedAt!
                      .toIso8601String()
                      .substring(0, 16)
                      .replaceFirst('T', ' '),
            ],
          ],
          assets.boldFont,
          labelWidth: 170,
        ),
        pw.SizedBox(height: 8),
        _supervisorSignatureRow(assets.boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _sectionBanner(String text, pw.Font boldFont) {
  return pw.Container(
    width: double.infinity,
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    color: const PdfColor.fromInt(0xFFE9E8F6),
    child: pw.Text(
      text,
      style: pw.TextStyle(font: boldFont, fontSize: 10.5),
    ),
  );
}

pw.Widget _longField(String label, String value, pw.Font boldFont) {
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
        pw.SizedBox(height: 4),
        pw.Text(
          value.isEmpty ? '—' : value,
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.2),
        ),
      ],
    ),
  );
}

pw.Widget _signatureRow(
  String heading,
  pw.Font boldFont,
  List<FypMember> members,
) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        heading,
        style: pw.TextStyle(font: boldFont, fontSize: 10.5),
      ),
      pw.SizedBox(height: 5),
      pw.Row(
        children: [
          for (var index = 0; index < members.length; index++) ...[
            pw.Expanded(
              child: pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.center,
                children: [
                  pw.Container(
                    height: 20,
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
                    members[index].name.isEmpty
                        ? 'Member ${members[index].serialNo}'
                        : members[index].name,
                    style: pw.TextStyle(font: boldFont, fontSize: 9.5),
                  ),
                ],
              ),
            ),
            if (index < members.length - 1) pw.SizedBox(width: 24),
          ],
        ],
      ),
    ],
  );
}

pw.Widget _supervisorSignatureRow(pw.Font boldFont) {
  return pw.Row(
    children: [
      pw.Text(
        'Signature: ',
        style: pw.TextStyle(font: boldFont, fontSize: 10),
      ),
      pw.Expanded(
        child: pw.Container(
          height: 18,
          decoration: const pw.BoxDecoration(
            border: pw.Border(
              bottom: pw.BorderSide(width: 0.7, color: PdfColors.black),
            ),
          ),
        ),
      ),
      pw.SizedBox(width: 16),
      pw.Text(
        '(Supervisor)',
        style: pw.TextStyle(font: boldFont, fontSize: 10),
      ),
    ],
  );
}
