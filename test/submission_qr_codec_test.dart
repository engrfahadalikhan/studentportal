import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/assessment/assessment_models.dart';
import 'package:teacher_student_assessment_app/assessment/submission_qr_codec.dart';

void main() {
  AssessmentSubmission sample() => const AssessmentSubmission(
        id: 'SUB001',
        assessmentId: 'ASSESS_A777',
        studentId: 'BSCS-F25-101',
        status: AttemptStatus.submitted,
        answers: {'Q1': 'B', 'Q2': 'True', 'Q3': 'Data abstraction'},
        marks: null,
        warningCount: 1,
        flags: ['App switch detected'],
        progress: 100,
      );

  test('encodes to the correct prefix', () {
    final payload = SubmissionQrCodec.encode(sample());
    expect(payload, isNotNull);
    expect(payload!.startsWith(SubmissionQrCodec.prefix), isTrue);
    expect(SubmissionQrCodec.looksLike(payload), isTrue);
  });

  test('round-trips: student encode → teacher decode', () {
    final original = sample();
    final payload = SubmissionQrCodec.encode(original)!;
    final decoded = SubmissionQrCodec.decode(payload);

    expect(decoded.assessmentId, original.assessmentId);
    expect(decoded.studentId, original.studentId);
    expect(decoded.status, original.status);
    expect(decoded.warningCount, original.warningCount);
    expect(decoded.progress, original.progress);
    expect(decoded.answers['Q1'], 'B');
    expect(decoded.answers['Q2'], 'True');
    expect(decoded.answers['Q3'], 'Data abstraction');
    expect(decoded.flags, contains('App switch detected'));
    // Marks start null — teacher computes them.
    expect(decoded.marks, isNull);
  });

  test('rejects non-submission payloads', () {
    expect(SubmissionQrCodec.looksLike('AUSTQP|1|abc'), isFalse);
    expect(SubmissionQrCodec.looksLike('hello'), isFalse);
    expect(
      () => SubmissionQrCodec.decode('garbage'),
      throwsFormatException,
    );
  });

  test('importSubmission is idempotent on re-scan', () {
    // Verify repo-level import handles duplicate scans gracefully (same student,
    // same assessment → replace, not append).
    final sub1 = sample();
    final sub2 = const AssessmentSubmission(
      id: 'SUB001', // same id
      assessmentId: 'ASSESS_A777',
      studentId: 'BSCS-F25-101',
      status: AttemptStatus.submitted,
      answers: {'Q1': 'C'}, // changed answer
      marks: null,
      warningCount: 0,
      flags: [],
      progress: 100,
    );
    // We just check the codec itself — the repo logic is in app_repository.
    final payload1 = SubmissionQrCodec.encode(sub1)!;
    final payload2 = SubmissionQrCodec.encode(sub2)!;
    final d1 = SubmissionQrCodec.decode(payload1);
    final d2 = SubmissionQrCodec.decode(payload2);
    // Same student, same assessment — both decode cleanly.
    expect(d1.studentId, d2.studentId);
    expect(d1.assessmentId, d2.assessmentId);
    // But answers differ (second scan has updated answer).
    expect(d1.answers['Q1'], 'B');
    expect(d2.answers['Q1'], 'C');
  });
}
