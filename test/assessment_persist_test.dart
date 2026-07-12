import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/assessment/assessment_models.dart';

void main() {
  test('Assessment survives a JSON round-trip with answers + questions', () {
    final original = Assessment(
      id: 'A123',
      title: 'DLD Quiz 1',
      type: AssessmentType.quiz,
      courseId: 'CC122',
      program: 'BSCS',
      semester: '2',
      section: 'A,B,C',
      durationMinutes: 30,
      totalMarks: 10,
      startTime: DateTime(2026, 6, 27, 9),
      endTime: DateTime(2026, 6, 27, 9, 30),
      instructions: 'No cheating.',
      questions: const [
        AssessmentQuestion(
          id: 'Q1',
          type: QuestionType.mcq,
          question: '2 + 2 = ?',
          marks: 5,
          options: ['3', '4', '5'],
          correctAnswer: '4',
          timeMinutes: 2,
        ),
        AssessmentQuestion(
          id: 'Q2',
          type: QuestionType.trueFalse,
          question: 'Sky is green',
          marks: 5,
          options: ['True', 'False'],
          correctAnswer: 'False',
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
      qrCode: 'ASSESS_A123',
      expectedStudents: 58,
    );

    final restored = Assessment.fromJson(original.toJson());

    expect(restored.id, original.id);
    expect(restored.title, original.title);
    expect(restored.type, original.type);
    expect(restored.section, 'A,B,C');
    expect(restored.status, AssessmentStatus.active);
    expect(restored.expectedStudents, 58);
    expect(restored.totalMarks, 10);
    expect(restored.questions.length, 2);
    // The correct answers MUST persist (teacher grades against them).
    expect(restored.questions[0].correctAnswer, '4');
    expect(restored.questions[1].correctAnswer, 'False');
    expect(restored.questions[0].options, ['3', '4', '5']);
    expect(restored.settings.oneAttemptOnly, true);
    expect(restored.startTime, original.startTime);
  });
}
