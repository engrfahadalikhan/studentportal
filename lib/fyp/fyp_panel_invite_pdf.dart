import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_group_models.dart';
import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Builds the external-examiner invitation letter for one examiner panel. It is
/// the sheet handed / sent to the panel's teachers to inform them that they are
/// to attend as external examiners, on a given date, following the allotted
/// time schedule — and that their assigned students may present only to them.
Future<Uint8List> buildFypPanelInvitePdf({
  required FypPanel panel,
  required List<FypGroup> groups,
  required DateTime date,
  int? startMinuteOfDay,
  int minutesPerGroup = 20,
  String venue = '',
}) async {
  final assets = await FypPdfAssets.load();
  final document = pw.Document(
    title: 'External Examiner Invite — ${panel.name}',
    theme: pw.ThemeData.withFont(
      base: assets.regularFont,
      bold: assets.boldFont,
      italic: assets.italicFont,
      boldItalic: assets.boldItalicFont,
    ),
  );

  final panelName = panel.name.trim().isEmpty ? 'Examiner Panel' : panel.name;
  final examiners = panel.members
      .where((m) => m.trim().isNotEmpty)
      .toList(growable: false);

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(28, 22, 28, 20),
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
          formTitle: 'FYP External Examiner — Invitation & Duty Schedule',
          subTitle: panelName,
        ),
        pw.SizedBox(height: 12),
        _refDateRow(assets, date),
        pw.SizedBox(height: 10),
        _toBlock(assets, examiners),
        pw.SizedBox(height: 10),
        fypSectionTitle('Subject: Invitation as External Examiner (FYP)',
            assets.boldFont),
        pw.SizedBox(height: 8),
        _bodyText(assets, panelName, date, venue, startMinuteOfDay),
        pw.SizedBox(height: 12),
        fypSectionTitle(
          'Evaluation schedule (${groups.length} group'
          '${groups.length == 1 ? '' : 's'})',
          assets.boldFont,
        ),
        pw.SizedBox(height: 6),
        if (groups.isEmpty)
          pw.Text(
            'No groups are currently assigned to this panel.',
            style: const pw.TextStyle(fontSize: 10),
          )
        else
          _scheduleTable(groups, assets.boldFont, startMinuteOfDay,
              minutesPerGroup),
        pw.SizedBox(height: 10),
        _instructions(assets),
        pw.SizedBox(height: 26),
        _threeSignatures(assets.boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _refDateRow(FypPdfAssets assets, DateTime date) {
  return pw.Row(
    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
    children: [
      pw.Text(
        'Ref: AUST/CS/FYP/EE/____',
        style: pw.TextStyle(font: assets.boldFont, fontSize: 10),
      ),
      pw.Text(
        'Date of evaluation: ${_fmtDate(date)}',
        style: pw.TextStyle(font: assets.boldFont, fontSize: 10),
      ),
    ],
  );
}

pw.Widget _toBlock(FypPdfAssets assets, List<String> examiners) {
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('To,', style: pw.TextStyle(font: assets.boldFont, fontSize: 10.5)),
      pw.SizedBox(height: 2),
      if (examiners.isEmpty)
        pw.Text('The Examiner', style: const pw.TextStyle(fontSize: 10.5))
      else
        for (final e in examiners)
          pw.Text(
            e,
            style: pw.TextStyle(font: assets.boldFont, fontSize: 10.5),
          ),
      pw.Text(
        'Department of Computer Science, AUST',
        style: const pw.TextStyle(fontSize: 10),
      ),
    ],
  );
}

pw.Widget _bodyText(
  FypPdfAssets assets,
  String panelName,
  DateTime date,
  String venue,
  int? startMinuteOfDay,
) {
  final when = startMinuteOfDay == null
      ? 'on ${_fmtDate(date)}'
      : 'on ${_fmtDate(date)} at ${_fmtTime(startMinuteOfDay)}';
  final where = venue.trim().isEmpty ? '' : ' at ${venue.trim()}';
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Respected Sir / Madam,',
          style: pw.TextStyle(font: assets.boldFont, fontSize: 10.5)),
      pw.SizedBox(height: 5),
      pw.Paragraph(
        text:
            'It is to inform you that you have been nominated as an EXTERNAL '
            'EXAMINER on "$panelName" for the Final Year Project (FYP) '
            'evaluation. You are cordially requested to be present $when$where '
            'and to conduct the evaluation of the groups listed in the schedule '
            'below.',
        style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.4),
        margin: pw.EdgeInsets.zero,
      ),
      pw.SizedBox(height: 4),
      pw.Paragraph(
        text:
            'You are requested to kindly follow the allotted time against each '
            'group so the evaluations run to schedule. Please note that the '
            'students assigned to your panel shall present their project ONLY '
            'to you (their assigned examiner) and to no other panel.',
        style: const pw.TextStyle(fontSize: 10.5, lineSpacing: 1.4),
        margin: pw.EdgeInsets.zero,
      ),
    ],
  );
}

pw.Widget _scheduleTable(
  List<FypGroup> groups,
  pw.Font boldFont,
  int? startMinuteOfDay,
  int minutesPerGroup,
) {
  final showTime = startMinuteOfDay != null;

  pw.Widget headerCell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(t, style: pw.TextStyle(font: boldFont, fontSize: 9)),
  );
  pw.Widget cell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: const pw.TextStyle(fontSize: 8.5, lineSpacing: 1.1),
    ),
  );

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
      children: [
        headerCell('#'),
        if (showTime) headerCell('Time'),
        headerCell('Project title'),
        headerCell('Prog / Phase'),
        headerCell('Students (Roll — Name)'),
        headerCell('Supervisor'),
      ],
    ),
  ];

  for (var i = 0; i < groups.length; i++) {
    final g = groups[i];
    final members = g.members
        .map((m) => '${m.rollNo} — ${m.name}'.trim())
        .join('\n');
    final sup = g.coSupervisorName.trim().isEmpty
        ? g.supervisorName
        : '${g.supervisorName}\nCo: ${g.coSupervisorName}';
    final slot = showTime
        ? _fmtTime(startMinuteOfDay + i * minutesPerGroup)
        : '';
    rows.add(
      pw.TableRow(
        children: [
          cell('${i + 1}'),
          if (showTime) cell(slot),
          cell(g.title),
          cell('${g.program.label} · ${g.phase.label}'),
          cell(members),
          cell(sup),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: showTime
        ? const {
            0: pw.FixedColumnWidth(18),
            1: pw.FixedColumnWidth(52),
            2: pw.FlexColumnWidth(2.7),
            3: pw.FixedColumnWidth(58),
            4: pw.FlexColumnWidth(3.2),
            5: pw.FlexColumnWidth(2.2),
          }
        : const {
            0: pw.FixedColumnWidth(18),
            1: pw.FlexColumnWidth(3),
            2: pw.FixedColumnWidth(58),
            3: pw.FlexColumnWidth(3.4),
            4: pw.FlexColumnWidth(2.3),
          },
    children: rows,
  );
}

pw.Widget _instructions(FypPdfAssets assets) {
  const lines = [
    'Kindly reach the venue a few minutes before your first slot.',
    'Follow the time allotted against each group.',
    'Assigned students may present to their assigned examiner only.',
    'Award marks on the provided evaluation sheet for each group.',
  ];
  return pw.Column(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text('Instructions:',
          style: pw.TextStyle(font: assets.boldFont, fontSize: 10)),
      pw.SizedBox(height: 3),
      for (final l in lines)
        pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 1.5),
          child: pw.Text('•  $l', style: const pw.TextStyle(fontSize: 9.5)),
        ),
    ],
  );
}

/// Three signature blocks: FYP Coordinator, Exam Coordinator, Chairman.
pw.Widget _threeSignatures(pw.Font boldFont) {
  pw.Widget block(String label) => pw.Expanded(
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        pw.Container(
          height: 24,
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
          style: pw.TextStyle(font: boldFont, fontSize: 9.5),
        ),
      ],
    ),
  );

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      block('FYP Coordinator'),
      pw.SizedBox(width: 22),
      block('Exam Coordinator'),
      pw.SizedBox(width: 22),
      block('Chairman, Dept. of CS'),
    ],
  );
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

String _fmtDate(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}-${_months[d.month - 1]}-${d.year}';

String _fmtTime(int minuteOfDay) {
  final h = minuteOfDay ~/ 60;
  final m = minuteOfDay % 60;
  final h12 = h % 12 == 0 ? 12 : h % 12;
  final ap = h < 12 ? 'AM' : 'PM';
  return '$h12:${m.toString().padLeft(2, '0')} $ap';
}
