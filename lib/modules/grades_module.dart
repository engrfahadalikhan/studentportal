import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../assessment/assessment_models.dart';
import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../ui/student_portal_shell.dart';

/// Tier-1 module: students see all their assessment marks grouped by course,
/// per-course average, and can download a transcript PDF.
class GradesModule extends StatelessWidget {
  const GradesModule({
    super.key,
    required this.repository,
    required this.student,
  });

  final AppRepository repository;
  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    final submissions = repository.submissionsForStudentRoll(student.rollNo);
    final byCourse = _groupByCourse(submissions);
    final overall = _overallStats(byCourse);

    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(
        title: const Text('Grades & Transcripts'),
        actions: [
          IconButton(
            tooltip: 'Download transcript PDF',
            onPressed: byCourse.isEmpty
                ? null
                : () => _downloadTranscript(byCourse),
            icon: const Icon(Icons.download_rounded),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          _OverallCard(stats: overall, student: student),
          const SizedBox(height: 14),
          if (byCourse.isEmpty)
            _Empty(text: 'No assessment marks recorded yet.'),
          for (final entry in byCourse.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: _CourseGradeCard(
                courseId: entry.key,
                rows: entry.value,
                repository: repository,
              ),
            ),
        ],
      ),
    );
  }

  Map<String, List<AssessmentSubmission>> _groupByCourse(
    List<AssessmentSubmission> submissions,
  ) {
    final map = <String, List<AssessmentSubmission>>{};
    for (final submission in submissions) {
      final assessment = repository.assessmentById(submission.assessmentId);
      final key = assessment?.courseId ?? 'Unknown';
      map.putIfAbsent(key, () => []).add(submission);
    }
    return map;
  }

  _OverallStats _overallStats(
    Map<String, List<AssessmentSubmission>> byCourse,
  ) {
    var graded = 0;
    var totalScored = 0;
    var totalPossible = 0;
    for (final rows in byCourse.values) {
      for (final submission in rows) {
        if (submission.marks == null) continue;
        final assessment = repository.assessmentById(submission.assessmentId);
        if (assessment == null) continue;
        graded++;
        totalScored += submission.marks!;
        totalPossible += assessment.totalMarks;
      }
    }
    final percent = totalPossible == 0
        ? 0.0
        : (totalScored / totalPossible) * 100;
    return _OverallStats(
      gradedCount: graded,
      courseCount: byCourse.length,
      averagePercent: percent,
    );
  }

  Future<void> _downloadTranscript(
    Map<String, List<AssessmentSubmission>> byCourse,
  ) async {
    final logoBytes = await rootBundle.load('assets/image1.png');
    final regularBytes = await rootBundle.load('assets/fonts/times.ttf');
    final boldBytes = await rootBundle.load('assets/fonts/timesbd.ttf');
    final italicBytes = await rootBundle.load('assets/fonts/timesi.ttf');

    final logo = pw.MemoryImage(logoBytes.buffer.asUint8List());
    final regular = pw.Font.ttf(regularBytes);
    final bold = pw.Font.ttf(boldBytes);
    final italic = pw.Font.ttf(italicBytes);

    final doc = pw.Document(
      theme: pw.ThemeData.withFont(base: regular, bold: bold, italic: italic),
    );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.fromLTRB(28, 22, 28, 18),
        build: (context) => [
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.SizedBox(width: 56, child: pw.Image(logo, height: 60)),
              pw.SizedBox(width: 10),
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    pw.Text(
                      'ABBOTTABAD UNIVERSITY OF SCIENCE & TECHNOLOGY',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: bold, fontSize: 14),
                    ),
                    pw.SizedBox(height: 2),
                    pw.Text(
                      'Department of Computer Science',
                      textAlign: pw.TextAlign.center,
                      style: pw.TextStyle(font: bold, fontSize: 11),
                    ),
                    pw.SizedBox(height: 6),
                    pw.Text(
                      'Student Transcript (Internal)',
                      style: pw.TextStyle(font: bold, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ],
          ),
          pw.SizedBox(height: 10),
          pw.Container(height: 1, color: PdfColors.black),
          pw.SizedBox(height: 12),
          pw.Table(
            border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
            columnWidths: const {
              0: pw.FixedColumnWidth(120),
              1: pw.FlexColumnWidth(),
            },
            children: [
              _row('Student Name', student.studentName, bold),
              _row('Roll No', student.rollNo, bold),
              _row('Program', student.program, bold),
              _row(
                'Semester / Section',
                '${student.semester}${student.section}',
                bold,
              ),
            ],
          ),
          pw.SizedBox(height: 14),
          for (final entry in byCourse.entries) ...[
            pw.Text(
              repository.courseById(entry.key)?.courseName ?? entry.key,
              style: pw.TextStyle(font: bold, fontSize: 12),
            ),
            pw.SizedBox(height: 4),
            pw.Table(
              border: pw.TableBorder.all(width: 0.5, color: PdfColors.black),
              columnWidths: const {
                0: pw.FlexColumnWidth(3),
                1: pw.FixedColumnWidth(70),
                2: pw.FixedColumnWidth(70),
                3: pw.FixedColumnWidth(70),
              },
              children: [
                pw.TableRow(
                  decoration: const pw.BoxDecoration(
                    color: PdfColor.fromInt(0xFFEEEEEE),
                  ),
                  children: [
                    _cell('Assessment', bold: bold, header: true),
                    _cell('Score', bold: bold, header: true),
                    _cell('Total', bold: bold, header: true),
                    _cell('Percent', bold: bold, header: true),
                  ],
                ),
                for (final submission in entry.value)
                  pw.TableRow(
                    children: [
                      _cell(repository
                              .assessmentById(submission.assessmentId)
                              ?.title ??
                          submission.assessmentId),
                      _cell(submission.marks?.toString() ?? '—'),
                      _cell(
                        repository
                                .assessmentById(submission.assessmentId)
                                ?.totalMarks
                                .toString() ??
                            '—',
                      ),
                      _cell(_percent(submission)),
                    ],
                  ),
              ],
            ),
            pw.SizedBox(height: 10),
          ],
        ],
      ),
    );

    final bytes = await doc.save();
    await Printing.layoutPdf(
      name: '${student.rollNo}-transcript.pdf',
      onLayout: (_) async => bytes,
    );
  }

  String _percent(AssessmentSubmission submission) {
    final assessment = repository.assessmentById(submission.assessmentId);
    if (submission.marks == null || assessment == null) return '—';
    if (assessment.totalMarks == 0) return '—';
    return '${((submission.marks! / assessment.totalMarks) * 100).toStringAsFixed(1)}%';
  }

  pw.TableRow _row(String label, String value, pw.Font bold) {
    return pw.TableRow(
      children: [
        _cell(label, bold: bold, header: true),
        _cell(value),
      ],
    );
  }

  pw.Widget _cell(
    String text, {
    pw.Font? bold,
    bool header = false,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      child: pw.Text(
        text.isEmpty ? '—' : text,
        style: pw.TextStyle(
          font: header ? bold : null,
          fontSize: 9.5,
        ),
      ),
    );
  }
}

class _OverallStats {
  const _OverallStats({
    required this.gradedCount,
    required this.courseCount,
    required this.averagePercent,
  });

  final int gradedCount;
  final int courseCount;
  final double averagePercent;
}

class _OverallCard extends StatelessWidget {
  const _OverallCard({required this.stats, required this.student});
  final _OverallStats stats;
  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF2948B7), Color(0xFF10B7C4)],
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            student.studentName,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          Text(
            '${student.rollNo} • ${student.program} ${student.semester}${student.section}',
            style: const TextStyle(color: Color(0xFFEFF6FF)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              _StatPill(
                label: 'Courses',
                value: '${stats.courseCount}',
              ),
              const SizedBox(width: 10),
              _StatPill(
                label: 'Graded',
                value: '${stats.gradedCount}',
              ),
              const SizedBox(width: 10),
              _StatPill(
                label: 'Average',
                value:
                    stats.gradedCount == 0 ? '—' : '${stats.averagePercent.toStringAsFixed(1)}%',
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 2),
            Text(label, style: const TextStyle(color: Color(0xFFEFF6FF))),
          ],
        ),
      ),
    );
  }
}

class _CourseGradeCard extends StatelessWidget {
  const _CourseGradeCard({
    required this.courseId,
    required this.rows,
    required this.repository,
  });

  final String courseId;
  final List<AssessmentSubmission> rows;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final course = repository.courseById(courseId);
    var totalScored = 0;
    var totalPossible = 0;
    for (final submission in rows) {
      if (submission.marks != null) {
        final assessment = repository.assessmentById(submission.assessmentId);
        if (assessment != null) {
          totalScored += submission.marks!;
          totalPossible += assessment.totalMarks;
        }
      }
    }
    final percent = totalPossible == 0
        ? null
        : (totalScored / totalPossible) * 100;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  course == null
                      ? courseId
                      : '${course.courseCode} — ${course.courseName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (percent != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE5E7EB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '${percent.toStringAsFixed(1)}%',
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          for (final submission in rows)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _SubmissionLine(
                submission: submission,
                repository: repository,
              ),
            ),
        ],
      ),
    );
  }
}

class _SubmissionLine extends StatelessWidget {
  const _SubmissionLine({
    required this.submission,
    required this.repository,
  });
  final AssessmentSubmission submission;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final assessment = repository.assessmentById(submission.assessmentId);
    final score = submission.marks;
    final total = assessment?.totalMarks ?? 0;
    return Row(
      children: [
        const Icon(Icons.assignment_outlined,
            size: 16, color: PortalColors.subtleText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            assessment?.title ?? submission.assessmentId,
            style: const TextStyle(color: PortalColors.textPrimary),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          score == null ? 'pending' : '$score / $total',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            color: score == null
                ? const Color(0xFFB45309)
                : PortalColors.textPrimary,
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Text(text, style: const TextStyle(color: PortalColors.subtleText)),
    );
  }
}
