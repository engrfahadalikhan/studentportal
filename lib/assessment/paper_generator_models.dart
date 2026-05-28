import 'dart:typed_data';

class PaperFormData {
  const PaperFormData({
    required this.teacherName,
    required this.subject,
    required this.dateTime,
    required this.className,
    required this.program,
    required this.questions,
    this.isDraft = false,
  });

  final String teacherName;
  final String subject;
  final String dateTime;
  final String className;
  final String program;
  final List<PaperQuestionData> questions;
  final bool isDraft;

  int get totalMarks {
    return questions.fold<int>(0, (sum, question) {
      return sum + question.effectiveMarks;
    });
  }
}

enum QuestionImagePlacement { left, center, right }

enum SubpartPlacement { indent, middle }

class PaperQuestionData {
  const PaperQuestionData({
    required this.number,
    required this.text,
    required this.marks,
    required this.clo,
    required this.plo,
    required this.subparts,
    this.options = const [],
    this.timeMinutes = 0,
    this.imageBytes,
    this.imageName,
    this.imagePlacement = QuestionImagePlacement.center,
    this.subpartPlacement = SubpartPlacement.indent,
  });

  final String number;
  final String text;
  final String marks;
  final String clo;
  final String plo;
  final List<PaperSubpartData> subparts;
  final List<String> options;
  final int timeMinutes;
  final Uint8List? imageBytes;
  final String? imageName;
  final QuestionImagePlacement imagePlacement;
  final SubpartPlacement subpartPlacement;

  int get effectiveMarks {
    if (subparts.isNotEmpty) {
      return subparts.fold<int>(0, (sum, subpart) => sum + subpart.marksValue);
    }
    return int.tryParse(marks) ?? 0;
  }

  String get effectiveMarksText {
    if (subparts.isNotEmpty) {
      return '$effectiveMarks';
    }
    return marks;
  }
}

class PaperSubpartData {
  const PaperSubpartData({required this.text, required this.marks});

  final String text;
  final String marks;

  int get marksValue => int.tryParse(marks) ?? 0;
}
