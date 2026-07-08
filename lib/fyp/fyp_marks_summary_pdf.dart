import 'dart:typed_data';

import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'fyp_group_models.dart';
import 'fyp_models.dart';
import 'fyp_pdf_common.dart';

/// Consolidated examiner-marks report for the coordinator/admin: every group
/// per phase with each examiner's Proposal and SRS marks, a combined average
/// across the examiners who marked, the presentation decision, and how many of
/// the assigned examiners are still pending (with their names) — the one sheet
/// the coordinator needs after the viva days.
Future<Uint8List> buildFypMarksSummaryPdf({
  required List<FypGroup> groups,
  required List<FypEvaluation> evaluations,
  required int Function(FypGroup) serialOf,
}) async {
  final assets = await FypPdfAssets.load();
  final document = pw.Document(
    title: 'FYP marks summary',
    theme: pw.ThemeData.withFont(
      base: assets.regularFont,
      bold: assets.boldFont,
      italic: assets.italicFont,
      boldItalic: assets.boldItalicFont,
    ),
  );

  final byGroup = <String, List<FypEvaluation>>{};
  for (final e in evaluations) {
    (byGroup[e.groupId.trim()] ??= []).add(e);
  }

  final content = <pw.Widget>[
    fypHeader(
      assets,
      formTitle: 'FYP Examiner Marks — Summary',
      subTitle: 'Generated ${_today()}',
    ),
    pw.SizedBox(height: 10),
  ];

  var grandGroups = 0;
  var grandMarked = 0;

  for (final phase in FypPhase.values) {
    final phaseGroups =
        groups
            .where(
              (g) => g.phase == phase && g.status != FypGroupStatus.rejected,
            )
            .toList()
          ..sort((a, b) => serialOf(a).compareTo(serialOf(b)));
    if (phaseGroups.isEmpty) continue;

    final marked = phaseGroups
        .where((g) => (byGroup[g.id] ?? const []).isNotEmpty)
        .length;
    grandGroups += phaseGroups.length;
    grandMarked += marked;

    content.addAll([
      pw.SizedBox(height: 8),
      fypSectionTitle(
        '${phase.label} — ${phaseGroups.length} group(s), '
        '$marked marked / ${phaseGroups.length - marked} pending',
        assets.boldFont,
      ),
      pw.SizedBox(height: 6),
      _phaseTable(phaseGroups, byGroup, serialOf, assets.boldFont),
    ]);
  }

  if (grandGroups == 0) {
    content.add(
      pw.Text(
        'No FYP groups to report.',
        style: const pw.TextStyle(fontSize: 10),
      ),
    );
  } else {
    content.addAll([
      pw.SizedBox(height: 12),
      pw.Text(
        'TOTAL: $grandGroups group(s) — $grandMarked marked, '
        '${grandGroups - grandMarked} pending.',
        style: pw.TextStyle(font: assets.boldFont, fontSize: 10.5),
      ),
    ]);
  }

  content.addAll([
    pw.SizedBox(height: 20),
    fypFooterSignatures(assets.boldFont),
  ]);

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
      build: (context) => content,
    ),
  );

  return document.save();
}

pw.Widget _phaseTable(
  List<FypGroup> groups,
  Map<String, List<FypEvaluation>> byGroup,
  int Function(FypGroup) serialOf,
  pw.Font boldFont,
) {
  pw.Widget headerCell(String t) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(t, style: pw.TextStyle(font: boldFont, fontSize: 9)),
  );
  pw.Widget cell(String t, {PdfColor? color}) => pw.Padding(
    padding: const pw.EdgeInsets.symmetric(horizontal: 5, vertical: 4),
    child: pw.Text(
      t.isEmpty ? '—' : t,
      style: pw.TextStyle(fontSize: 8.5, color: color),
    ),
  );

  String marksLines(List<FypEvaluation> evals, FypEvaluationKind kind) {
    final list = evals.where((e) => e.kind == kind).toList()
      ..sort((a, b) => a.examinerName.compareTo(b.examinerName));
    if (list.isEmpty) return '';
    final lines = [
      for (final e in list)
        '${e.marksObtained}/${e.marksMax} — ${e.examinerName}',
    ];
    // Combined mark = average across the examiners who marked this kind.
    if (list.length >= 2) {
      final pct =
          list
              .map((e) => e.marksMax == 0 ? 0.0 : e.marksObtained / e.marksMax)
              .reduce((a, b) => a + b) /
          list.length;
      final maxes = list.map((e) => e.marksMax).toSet();
      if (maxes.length == 1 && maxes.first > 0) {
        final avg =
            list.map((e) => e.marksObtained).reduce((a, b) => a + b) /
            list.length;
        lines.add(
          'Avg: ${avg.toStringAsFixed(1)}/${maxes.first} '
          '(${(pct * 100).round()}%)',
        );
      } else {
        lines.add('Avg: ${(pct * 100).round()}%');
      }
    }
    return lines.join('\n');
  }

  String decision(List<FypEvaluation> evals) {
    if (evals.isEmpty) return '';
    final repeat = evals.any(
      (e) => e.presentationDecision == FypPresentationDecision.repeatRequired,
    );
    return repeat ? 'REPEAT required' : 'Completed';
  }

  const green = PdfColor.fromInt(0xFF047857);
  const red = PdfColor.fromInt(0xFFB91C1C);
  const amber = PdfColor.fromInt(0xFFB45309);

  final rows = <pw.TableRow>[
    pw.TableRow(
      decoration: const pw.BoxDecoration(color: PdfColor.fromInt(0xFFEEEEEE)),
      children: [
        headerCell('#'),
        headerCell('Group / members'),
        headerCell('Supervisor'),
        headerCell('Proposal marks'),
        headerCell('SRS marks'),
        headerCell('Status'),
      ],
    ),
  ];

  for (final g in groups) {
    final evals = byGroup[g.id] ?? const [];
    final proposal = marksLines(evals, FypEvaluationKind.proposal);
    final srs = marksLines(evals, FypEvaluationKind.srs);
    final dec = decision(evals);
    final baseStatus = evals.isEmpty ? 'PENDING' : dec;

    // Assigned examiners vs. who has actually marked, so the coordinator can
    // see how many of the panel are still pending and chase them.
    final assigned = [
      for (final e in g.examiners)
        if (e.trim().isNotEmpty) e.trim(),
    ];
    final markedSet = {
      for (final e in evals) e.examinerName.trim().toLowerCase(),
    };
    final pending = [
      for (final a in assigned)
        if (!markedSet.contains(a.toLowerCase())) a,
    ];
    final markedCount = assigned.length - pending.length;
    final statusBuf = StringBuffer(baseStatus);
    if (assigned.isNotEmpty) {
      statusBuf.write('\n$markedCount of ${assigned.length} examiners');
      if (pending.isNotEmpty) {
        statusBuf.write('\nPending: ${pending.join(', ')}');
      }
    }

    rows.add(
      pw.TableRow(
        children: [
          cell('${serialOf(g)}'),
          cell(
            '${g.title.isEmpty ? '(no title)' : g.title}\n'
            '${g.members.map((m) => '${m.rollNo} ${m.name}').join('\n')}',
          ),
          cell(
            g.coSupervisorName.isEmpty
                ? g.supervisorName
                : '${g.supervisorName}\nCo: ${g.coSupervisorName}',
          ),
          cell(proposal, color: proposal.isEmpty ? null : green),
          cell(srs, color: srs.isEmpty ? null : green),
          cell(
            statusBuf.toString(),
            color: baseStatus == 'PENDING'
                ? amber
                : baseStatus == 'REPEAT required'
                ? red
                : green,
          ),
        ],
      ),
    );
  }

  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: const {
      0: pw.FixedColumnWidth(18),
      1: pw.FlexColumnWidth(3.0),
      2: pw.FlexColumnWidth(1.8),
      3: pw.FlexColumnWidth(2.3),
      4: pw.FlexColumnWidth(2.3),
      5: pw.FlexColumnWidth(2.7),
    },
    children: rows,
  );
}

String _today() {
  final n = DateTime.now();
  return '${n.day.toString().padLeft(2, '0')}-'
      '${n.month.toString().padLeft(2, '0')}-${n.year}';
}
