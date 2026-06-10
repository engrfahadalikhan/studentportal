import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/assessment/assessment_models.dart';
import 'package:teacher_student_assessment_app/services/app_repository.dart';

void main() {
  Assessment quizWith({String? correctA, String? correctB}) {
    final now = DateTime(2026, 5, 30, 10);
    return Assessment(
      id: 'GRADE-1',
      title: 'Grading quiz',
      type: AssessmentType.quiz,
      courseId: 'C1',
      program: 'BSCS',
      semester: '4',
      section: 'A',
      durationMinutes: 20,
      totalMarks: 5,
      startTime: now,
      endTime: now.add(const Duration(minutes: 20)),
      instructions: '',
      questions: [
        AssessmentQuestion(
          id: 'Q1',
          type: QuestionType.mcq,
          question: 'Q1?',
          marks: 2,
          options: const ['A', 'B', 'C'],
          correctAnswer: correctA,
        ),
        AssessmentQuestion(
          id: 'Q2',
          type: QuestionType.mcq,
          question: 'Q2?',
          marks: 3,
          options: const ['A', 'B', 'C'],
          correctAnswer: correctB,
        ),
      ],
      settings: const AssessmentSettings(
        randomizeQuestions: false,
        randomizeOptions: false,
        oneAttemptOnly: true,
        autoSubmit: true,
        showResultAfterSubmission: true,
        manualGrading: false,
      ),
      status: AssessmentStatus.active,
      qrCode: 'ASSESS_GRADE1',
    );
  }

  AssessmentStudent student() => const AssessmentStudent(
        id: 'BSCS-1',
        name: 'Test Student',
        studentId: 'BSCS-1',
        program: 'BSCS',
        session: 'S26',
        semester: '4',
        section: 'A',
        email: 'x@y.z',
      );

  test('submit does not grade; teacher computes objective marks at their end',
      () {
    final repo = AppRepository();
    // The teacher's authoritative copy holds the answer key.
    final quiz = repo.importSharedAssessment(
      quizWith(correctA: 'B', correctB: 'C'),
    );

    repo.submitAssessment(
      assessment: quiz,
      student: student(),
      answers: {'Q1': 'B', 'Q2': 'A'}, // Q1 right (2), Q2 wrong (0)
      warningCount: 0,
      flags: const [],
      status: AttemptStatus.submitted,
    );

    // Student submit leaves the score ungraded (their device has no key).
    final sub = repo.submissionsForAssessment(quiz.id).single;
    expect(sub.marks, isNull);

    // Teacher-end calculation against the answer key.
    final suggested = repo.objectiveAutoMarks(quiz, sub.answers);
    expect(suggested, 2);

    // Teacher saves the grade.
    repo.gradeSubmission(
      assessmentId: quiz.id,
      studentId: 'BSCS-1',
      marks: suggested!,
    );
    expect(repo.submissionsForAssessment(quiz.id).single.marks, 2);
  });

  test('answer-safe: a student-facing decoded paper carries no answer key', () {
    final repo = AppRepository();
    final quiz = repo.importSharedAssessment(
      quizWith(correctA: 'B', correctB: 'C'),
    );
    // Simulate the answer-free copy that a student gets from the QR.
    final studentCopy = quiz.copyWith(
      questions: [
        for (final q in quiz.questions)
          AssessmentQuestion(
            id: q.id,
            type: q.type,
            question: q.question,
            marks: q.marks,
            options: q.options,
            // No correctAnswer — exactly what the QR codec strips out.
          ),
      ],
    );
    // Grading against the student's answer-free copy yields nothing...
    expect(repo.objectiveAutoMarks(studentCopy, {'Q1': 'B', 'Q2': 'C'}), isNull);
    // ...but the teacher's authoritative copy still grades correctly.
    expect(repo.objectiveAutoMarks(quiz, {'Q1': 'B', 'Q2': 'C'}), 5);
  });

  test('assignment with no correct answers stays ungraded (manual)', () {
    final repo = AppRepository();
    final assignment = repo.importSharedAssessment(
      quizWith().copyWith(type: AssessmentType.assignment),
    );

    repo.submitAssessment(
      assessment: assignment,
      student: student(),
      answers: {'text': 'My essay', 'file': 'report.pdf'},
      warningCount: 0,
      flags: const [],
      status: AttemptStatus.submitted,
    );

    final sub = repo.submissionsForAssessment(assignment.id).single;
    expect(sub.marks, isNull);

    // Teacher grades it manually.
    repo.gradeSubmission(
      assessmentId: assignment.id,
      studentId: 'BSCS-1',
      marks: 4,
    );
    final regraded = repo.submissionsForAssessment(assignment.id).single;
    expect(regraded.marks, 4);
  });
}
