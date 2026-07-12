import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_group_models.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_marks_summary_pdf.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FypEvaluation eval(String id, String examiner, int score) => FypEvaluation(
    id: id,
    kind: FypEvaluationKind.proposal,
    groupId: 'G1',
    term: 'Fall 2026',
    projectTitle: 'Smart Attendance',
    supervisorName: 'Dr. Sup',
    examinerName: examiner,
    members: const [
      FypMember(serialNo: 1, rollNo: '21B-001-CS', name: 'Ali', email: 'a@x'),
    ],
    rubric: [FypRubricRow(label: 'Total', maxMarks: 50, score: score)],
    submittedAt: DateTime(2026, 7, 20),
  );

  test('marks summary renders with 2 of 5 examiners marked (avg + pending)',
      () async {
    final group = FypGroup(
      id: 'G1',
      title: 'Smart Attendance',
      phase: FypPhase.fyp3,
      program: FypProgram.bscs,
      term: 'Fall 2026',
      members: const [
        FypMember(serialNo: 1, rollNo: '21B-001-CS', name: 'Ali', email: 'a@x'),
      ],
      supervisorName: 'Dr. Sup',
      createdByRole: 'coordinator',
      createdByName: 'Coord',
      status: FypGroupStatus.approved,
      examiners: const [
        'Dr. A',
        'Dr. B',
        'Dr. C',
        'Dr. D',
        'Dr. E',
      ],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );

    final bytes = await buildFypMarksSummaryPdf(
      groups: [group],
      evaluations: [eval('E1', 'Dr. A', 45), eval('E2', 'Dr. B', 40)],
      serialOf: (_) => 1,
    );

    expect(bytes.lengthInBytes, greaterThan(1000));
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
  });
}
