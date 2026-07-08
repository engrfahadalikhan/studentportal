import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../models/student_record.dart';
import 'fyp_group_models.dart';
import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Builds a phase report PDF with two sections: the groups that are already
/// formed (serial, title, members, supervisor, examiners, status) and the
/// final-year students who are not yet in any group.
Future<Uint8List> buildFypPhaseReportPdf({
  required FypPhase phase,
  required List<FypGroup> groups,
  required List<StudentRecord> ungrouped,
  required int Function(FypGroup) serialOf,
}) async {
  final assets = await FypPdfAssets.load();
  final document = pw.Document(
    title: '${phase.label} report',
    theme: pw.ThemeData.withFont(
      base: assets.regularFont,
      bold: assets.boldFont,
      italic: assets.italicFont,
      boldItalic: assets.boldItalicFont,
    ),
  );

  final sorted = [...groups]..sort((a, b) => serialOf(a).compareTo(serialOf(b)));

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(24, 20, 24, 18),
      footer: (context) => pw.Align(
        alignment: pw.Alignment.centerRight,
        child: pw.Text(
          'Page ${context.pageNumber} of ${context.pagesCount}',
          style: pw.TextStyle(font: assets.boldFont, fontSize: 8),
        ),
      ),
      build: (context) => [
        fypHeader(
          assets,
          formTitle: 'FYP Report — ${phase.label}',
          subTitle: 'Generated ${_today()}',
        ),
        pw.SizedBox(height: 12),
        fypSectionTitle(
          'Allotted / in-progress groups (${sorted.length})',
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        if (sorted.isEmpty)
          pw.Text(
            'No groups in this phase yet.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          _groupsTable(sorted, serialOf, assets.boldFont),
        pw.SizedBox(height: 16),
        fypSectionTitle(
          'Students without a group (${ungrouped.length})',
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        if (ungrouped.isEmpty)
          pw.Text(
            'Every eligible student is already in a group.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          _ungroupedTable(ungrouped, assets.boldFont),
        pw.SizedBox(height: 20),
        fypFooterSignatures(assets.boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _groupsTable(
  List<FypGroup> groups,
  int Function(FypGroup) serialOf,
  pw.Font boldFont,
) {
  pw.Widget headerCell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(t, style: pw.TextStyle(font: boldFont, fontSize: 9)),
  );
  pw.Widget cell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: const pw.TextStyle(fontSize: 8.5),
    ),
  );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
      children: [
        headerCell('#'),
        headerCell('Title'),
        headerCell('Members'),
        headerCell('Supervisor'),
        headerCell('Examiners'),
        headerCell('Status'),
      ],
    ),
  ];
  for (final g in groups) {
    final members = g.members
        .map((m) => '${m.rollNo} ${m.name}'.trim())
        .join('\n');
    final sup = g.coSupervisorName.isEmpty
        ? g.supervisorName
        : '${g.supervisorName}\nCo: ${g.coSupervisorName}';
    rows.add(
      pw.TableRow(
        children: [
          cell('${serialOf(g)}'),
          cell(g.title),
          cell(members),
          cell(sup),
          cell(g.examiners.join('\n')),
          cell(g.status.label),
        ],
      ),
    );
  }
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(20),
      1: pw.FlexColumnWidth(3),
      2: pw.FlexColumnWidth(3.2),
      3: pw.FlexColumnWidth(2.4),
      4: pw.FlexColumnWidth(2.2),
      5: pw.FlexColumnWidth(2),
    },
    children: rows,
  );
}

pw.Widget _ungroupedTable(List<StudentRecord> students, pw.Font boldFont) {
  pw.Widget headerCell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(t, style: pw.TextStyle(font: boldFont, fontSize: 9)),
  );
  pw.Widget cell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: const pw.TextStyle(fontSize: 8.5),
    ),
  );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
      children: [
        headerCell('Sr.'),
        headerCell('Roll No'),
        headerCell('Name'),
        headerCell('Program'),
        headerCell('Sem'),
        headerCell('Section'),
      ],
    ),
  ];
  var i = 1;
  for (final s in students) {
    rows.add(
      pw.TableRow(
        children: [
          cell('${i++}'),
          cell(s.rollNo),
          cell(s.studentName),
          cell(s.program),
          cell(s.semester),
          cell(s.section),
        ],
      ),
    );
  }
  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(24),
      1: pw.FlexColumnWidth(2),
      2: pw.FlexColumnWidth(4),
      3: pw.FlexColumnWidth(2),
      4: pw.FixedColumnWidth(30),
      5: pw.FixedColumnWidth(44),
    },
    children: rows,
  );
}

String _today() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.year}';
}
