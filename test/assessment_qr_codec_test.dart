import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/assessment/assessment_models.dart';
import 'package:teacher_student_assessment_app/assessment/assessment_qr_codec.dart';

void main() {
  Assessment sample({int questionCount = 3}) {
    final now = DateTime(2026, 5, 30, 10);
    return Assessment(
      id: 'A777',
      title: 'Algorithms Quiz 1',
      type: AssessmentType.quiz,
      courseId: 'C123',
      program: 'BSCS',
      semester: '4',
      section: 'A',
      durationMinutes: 25,
      totalMarks: questionCount * 2,
      startTime: now,
      endTime: now.add(const Duration(minutes: 25)),
      instructions: 'Answer all questions. No calculators.',
      questions: [
        for (var i = 0; i < questionCount; i++)
          AssessmentQuestion(
            id: 'Q${i + 1}',
            type: QuestionType.mcq,
            question: 'Sample question number ${i + 1}?',
            marks: 2,
            options: const ['Option A', 'Option B', 'Option C', 'Option D'],
            correctAnswer: 'Option B',
            timeMinutes: 3,
          ),
      ],
      settings: const AssessmentSettings(
        randomizeQuestions: true,
        randomizeOptions: true,
        oneAttemptOnly: true,
        autoSubmit: true,
        showResultAfterSubmission: false,
        manualGrading: false,
      ),
      status: AssessmentStatus.active,
      qrCode: 'ASSESS_A777',
    );
  }

  test('encodes to a prefixed offline payload', () {
    final payload = AssessmentQrCodec.encode(sample());
    expect(payload, isNotNull);
    expect(payload!.startsWith(AssessmentQrCodec.prefix), isTrue);
    expect(AssessmentQrCodec.looksLikeAssessmentQr(payload), isTrue);
  });

  test('round-trips a paper: teacher encode -> student decode', () {
    final original = sample();
    final payload = AssessmentQrCodec.encode(original)!;
    final decoded = AssessmentQrCodec.decode(payload);

    expect(decoded.id, original.id);
    expect(decoded.title, original.title);
    expect(decoded.type, original.type);
    expect(decoded.courseId, original.courseId);
    expect(decoded.program, original.program);
    expect(decoded.section, original.section);
    expect(decoded.durationMinutes, original.durationMinutes);
    expect(decoded.instructions, original.instructions);
    expect(decoded.questions.length, original.questions.length);

    final q = decoded.questions.first;
    expect(q.question, 'Sample question number 1?');
    expect(q.type, QuestionType.mcq);
    expect(q.marks, 2);
    expect(q.options, hasLength(4));
    // The student-facing QR is answer-safe: correct answers are stripped, so a
    // student cannot decode them. They stay only on the teacher's device.
    expect(q.correctAnswer, isNull);
    expect(q.timeMinutes, 3);

    // Total marks are recomputed from the questions on decode.
    expect(decoded.totalMarks, original.totalMarks);
    // A scanned paper is active so the student can attempt immediately.
    expect(decoded.status, AssessmentStatus.active);
  });

  test('rejects a non-AUST payload', () {
    expect(AssessmentQrCodec.looksLikeAssessmentQr('hello world'), isFalse);
    expect(
      () => AssessmentQrCodec.decode('hello world'),
      throwsFormatException,
    );
  });

  test('returns null when a paper is far too big for one QR', () {
    final huge = sample(questionCount: 400);
    expect(AssessmentQrCodec.encode(huge), isNull);
  });
}
