import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Form #5 — FYP-I Proposal cover sheet.
///
/// The full IEEE-style proposal template is a 30-page document students
/// fill outside the app. This PDF acts as the registration cover sheet
/// + plagiarism declaration that goes on top of the proposal.
Future<Uint8List> buildFypProposalPdf(FypProposal proposal) async {
  final assets = await FypPdfAssets.load();

  final document = pw.Document(
    title: 'FYP Proposal — ${proposal.title}',
    author: proposal.members.isEmpty ? 'AUST' : proposal.members.first.name,
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
          formTitle: 'Final Year Project Proposal',
          subTitle: proposal.term,
        ),
        pw.SizedBox(height: 12),
        pw.Center(
          child: pw.Text(
            proposal.title,
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: assets.boldFont, fontSize: 16),
          ),
        ),
        pw.SizedBox(height: 14),
        fypSectionTitle('Project Registration', assets.boldFont),
        pw.SizedBox(height: 6),
        fypInfoTable(
          [
            ['Project ID (office use)', proposal.projectId],
            ['Type (Nature of project)', proposal.projectType.label],
            ['Area of specialization', proposal.areaOfSpecialization],
          ],
          assets.boldFont,
          labelWidth: 160,
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Project Group Members', assets.boldFont),
        pw.SizedBox(height: 6),
        _membersTable(proposal.members, assets.boldFont),
        pw.SizedBox(height: 12),
        fypSectionTitle('Plagiarism Free Certificate', assets.boldFont),
        pw.SizedBox(height: 6),
        pw.Text(
          'This is to certify that I, ${proposal.members.isEmpty ? '____________' : proposal.members.first.name}, group leader of FYP under roll no '
          '${proposal.members.isEmpty ? '____________' : proposal.members.first.rollNo} at Computer Science Department, Abbottabad UST, '
          'declare that my FYP proposal is checked by my supervisor and the similarity index is '
          '${proposal.similarityIndex.isEmpty ? '____' : proposal.similarityIndex}% which is less than 20%, '
          'an acceptable limit by HEC. Report is attached herewith as Appendix A.',
          style: const pw.TextStyle(fontSize: 10, lineSpacing: 1.3),
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle('Supervisor Details', assets.boldFont),
        pw.SizedBox(height: 6),
        fypInfoTable(
          [
            ['Supervisor Name', proposal.supervisorName],
            ['Supervisor Designation', proposal.supervisorDesignation],
            ['Co-Supervisor Name', proposal.coSupervisorName],
            ['Co-Supervisor Designation', proposal.coSupervisorDesignation],
          ],
          assets.boldFont,
          labelWidth: 170,
        ),
        pw.SizedBox(height: 16),
        fypQrPanel(
          qrData: proposal.qrCode,
          caption: 'Proposal lookup',
          captionDetail:
              'Faculty can scan to view this proposal record and the linked evaluation marks once entered.',
          boldFont: assets.boldFont,
        ),
        pw.SizedBox(height: 14),
        fypFooterSignatures(assets.boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _membersTable(List<FypMember> members, pw.Font boldFont) {
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(38),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(3),
      3: pw.FixedColumnWidth(46),
      4: pw.FlexColumnWidth(3),
      5: pw.FlexColumnWidth(2),
    },
    children: [
      pw.TableRow(
        decoration:
            const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
        children: [
          for (final header in [
            'Sr. #',
            'Roll #',
            'Student Name',
            'CGPA',
            'Email ID',
            'Phone #',
          ])
            pw.Padding(
              padding: const pw.EdgeInsets.symmetric(
                horizontal: 4,
                vertical: 4,
              ),
              child: pw.Text(
                header,
                style: pw.TextStyle(font: boldFont, fontSize: 9.5),
              ),
            ),
        ],
      ),
      for (final member in members)
        pw.TableRow(
          children: [
            _cell('${member.serialNo}${member.serialNo == 1 ? ' (Leader)' : ''}'),
            _cell(member.rollNo),
            _cell(member.name),
            _cell(member.cgpa),
            _cell(member.email),
            _cell(member.phone),
          ],
        ),
    ],
  );
}

pw.Widget _cell(String text) {
  return pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 4, vertical: 4),
    child: pw.Text(
      text.isEmpty ? '—' : text,
      style: const pw.TextStyle(fontSize: 9.5),
    ),
  );
}
