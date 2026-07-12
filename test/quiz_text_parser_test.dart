import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/assessment/quiz_text_parser.dart';

void main() {
  test('parses numbered questions with A) B) options and a * correct mark', () {
    const raw = '''
1. What is 2 + 2?
A) 3
B) 4*
C) 5
D) 6

2) Capital of Pakistan?
a. Lahore
b. Islamabad
c. Karachi
Answer: B
''';
    final qs = parseQuizText(raw);
    expect(qs.length, 2);

    expect(qs[0].text, 'What is 2 + 2?');
    expect(qs[0].options, ['3', '4', '5', '6']);
    expect(qs[0].correctIndex, 1); // B

    expect(qs[1].text, 'Capital of Pakistan?');
    expect(qs[1].options, ['Lahore', 'Islamabad', 'Karachi']);
    expect(qs[1].correctIndex, 1); // Answer: B
  });

  test('parses bullet options and (correct) marker', () {
    const raw = '''
Q1: Pick a color
- Red
- Green (correct)
- Blue
''';
    final qs = parseQuizText(raw);
    expect(qs.single.text, 'Pick a color');
    expect(qs.single.options, ['Red', 'Green', 'Blue']);
    expect(qs.single.correctIndex, 1);
  });

  test('multi-line question text before options is joined', () {
    const raw = '''
1. A long question that
continues on the next line?
A) Yes
B) No
''';
    final qs = parseQuizText(raw);
    expect(qs.single.text, 'A long question that continues on the next line?');
    expect(qs.single.options, ['Yes', 'No']);
  });

  test('empty / junk text yields no questions', () {
    expect(parseQuizText('   \n\n').isEmpty, isTrue);
  });
}
