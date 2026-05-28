import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import 'paper_generator_models.dart';

Future<Uint8List> buildExamPdf(PaperFormData data) async {
  final cleanedData = PaperFormData(
    teacherName: _cleanPdfText(data.teacherName),
    subject: _cleanPdfText(data.subject),
    dateTime: _cleanPdfText(data.dateTime),
    className: _cleanPdfText(data.className),
    program: _cleanPdfText(data.program),
    questions: data.questions.map(_cleanQuestionData).toList(),
    isDraft: data.isDraft,
  );
  final logoBytes = await rootBundle.load('assets/image1.png');
  final csLogoBytes = await rootBundle.load('assets/cs_logo.jpeg');
  final regularFontBytes = await rootBundle.load('assets/fonts/times.ttf');
  final boldFontBytes = await rootBundle.load('assets/fonts/timesbd.ttf');
  final italicFontBytes = await rootBundle.load('assets/fonts/timesi.ttf');
  final boldItalicFontBytes = await rootBundle.load('assets/fonts/timesbi.ttf');

  final logoImage = pw.MemoryImage(logoBytes.buffer.asUint8List());
  final csLogoImage = pw.MemoryImage(csLogoBytes.buffer.asUint8List());
  final regularFont = pw.Font.ttf(regularFontBytes);
  final boldFont = pw.Font.ttf(boldFontBytes);
  final italicFont = pw.Font.ttf(italicFontBytes);
  final boldItalicFont = pw.Font.ttf(boldItalicFontBytes);

  final document = pw.Document(
    title:
        '${cleanedData.subject} ${cleanedData.isDraft ? 'draft ' : ''}exam paper',
    author: cleanedData.teacherName,
    theme: pw.ThemeData.withFont(
      base: regularFont,
      bold: boldFont,
      italic: italicFont,
      boldItalic: boldItalicFont,
    ),
  );

  document.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.fromLTRB(20, 18, 20, 12),
      footer: (context) => pw.Padding(
        padding: const pw.EdgeInsets.only(top: 1),
        child: pw.Align(
          alignment: pw.Alignment.centerRight,
          child: pw.Text(
            'Page ${context.pageNumber} of ${context.pagesCount}',
            style: pw.TextStyle(font: boldFont, fontSize: 7.6),
          ),
        ),
      ),
      build: (context) => [
        _buildHeader(logoImage, csLogoImage, boldFont, boldItalicFont),
        pw.SizedBox(height: 3),
        if (cleanedData.isDraft) ...[
          _buildDraftBanner(boldFont),
          pw.SizedBox(height: 3),
        ],
        _buildExamInfoTable(cleanedData, boldFont),
        pw.SizedBox(height: 2),
        _buildInstructionsLine(boldFont),
        pw.SizedBox(height: 2),
        _buildSummaryTable(cleanedData.questions, boldFont),
        pw.SizedBox(height: 2),
        ..._buildQuestionSection(cleanedData.questions, boldFont),
      ],
    ),
  );

  return document.save();
}

pw.Widget _buildDraftBanner(pw.Font boldFont) {
  return pw.Container(
    width: double.infinity,
    decoration: pw.BoxDecoration(
      color: PdfColor.fromInt(0xFFEDEDED),
      border: pw.Border.all(width: 0.6, color: PdfColors.black),
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
    child: pw.Text(
      'DRAFT COPY - Not for final printing',
      textAlign: pw.TextAlign.center,
      style: pw.TextStyle(font: boldFont, fontSize: 8.4),
    ),
  );
}

pw.Widget _buildHeader(
  pw.MemoryImage logoImage,
  pw.MemoryImage csLogoImage,
  pw.Font boldFont,
  pw.Font boldItalicFont,
) {
  return pw.Column(
    children: [
      pw.Container(height: 1, color: PdfColors.black),
      pw.SizedBox(height: 3),
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        children: [
          pw.SizedBox(
            width: 50,
            child: pw.Image(logoImage, height: 54, fit: pw.BoxFit.contain),
          ),
          pw.SizedBox(width: 6),
          pw.Expanded(
            child: pw.Column(
              children: [
                pw.Text(
                  'ABBOTTABAD UNIVERSITY OF SCIENCE AND TECHNOLOGY',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldItalicFont, fontSize: 14.8),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Department of Computer Science',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldFont, fontSize: 10.5),
                ),
                pw.SizedBox(height: 1),
                pw.Text(
                  'Mid-Term Examination - Spring 2026',
                  textAlign: pw.TextAlign.center,
                  style: pw.TextStyle(font: boldFont, fontSize: 10.5),
                ),
              ],
            ),
          ),
          pw.SizedBox(width: 6),
          pw.SizedBox(
            width: 50,
            child: pw.Image(csLogoImage, height: 54, fit: pw.BoxFit.contain),
          ),
        ],
      ),
      pw.SizedBox(height: 3),
      pw.Container(height: 0.9, color: PdfColors.black),
    ],
  );
}

pw.Widget _buildExamInfoTable(PaperFormData data, pw.Font boldFont) {
  final leftRows = [
    ['Class', _cleanPdfText(data.className)],
    ['Subject', _cleanPdfText(data.subject)],
    ['Time Allowed', '1 Hour'],
  ];

  final rightRows = [
    ['Date', _cleanPdfText(data.dateTime)],
    ['Instructor', _cleanPdfText(data.teacherName)],
    ['Max Marks', '${data.totalMarks} marks'],
  ];

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Expanded(child: _buildInfoBox(leftRows, boldFont)),
      pw.SizedBox(width: 8),
      pw.Expanded(child: _buildInfoBox(rightRows, boldFont)),
    ],
  );
}

pw.Widget _buildInfoBox(List<List<String>> rows, pw.Font boldFont) {
  return pw.Table(
    border: pw.TableBorder.all(color: PdfColors.black, width: 0.65),
    columnWidths: {
      0: const pw.FixedColumnWidth(72),
      1: const pw.FlexColumnWidth(),
    },
    children: rows
        .map(
          (row) => pw.TableRow(
            children: [
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: pw.Text(
                  _cleanPdfText(row[0]),
                  maxLines: 2,
                  style: pw.TextStyle(font: boldFont, fontSize: 8.4),
                ),
              ),
              pw.Padding(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 3,
                ),
                child: pw.Text(
                  _cleanPdfText(row[1]),
                  maxLines: 2,
                  style: const pw.TextStyle(fontSize: 8.4),
                ),
              ),
            ],
          ),
        )
        .toList(),
  );
}

pw.Widget _buildInstructionsLine(pw.Font boldFont) {
  const line =
      'Question interpretation is part of the exam. Using unfair means will result in paper cancellation. For each question, read the respective instructions very carefully.';

  return pw.Row(
    crossAxisAlignment: pw.CrossAxisAlignment.start,
    children: [
      pw.Text(
        'Instructions: ',
        style: pw.TextStyle(font: boldFont, fontSize: 8.2),
      ),
      pw.Expanded(
        child: pw.Text(line, style: const pw.TextStyle(fontSize: 8.1)),
      ),
    ],
  );
}

pw.Widget _buildSummaryTable(
  List<PaperQuestionData> questions,
  pw.Font boldFont,
) {
  final questionCount = questions.isEmpty ? 1 : questions.length;
  final labelColumnWidth = questionCount <= 6 ? 78.0 : 70.0;
  final fontSize = questionCount <= 6 ? 7.2 : 6.6;

  return pw.Align(
    alignment: pw.Alignment.center,
    child: pw.SizedBox(
      width: 410,
      child: pw.Table(
        columnWidths: {
          0: pw.FixedColumnWidth(labelColumnWidth),
          for (var index = 0; index < questionCount; index++)
            index + 1: const pw.FlexColumnWidth(),
        },
        children: [
          pw.TableRow(
            children: [
              _summaryCell(
                'Question #',
                boldFont,
                align: pw.TextAlign.center,
                border: _summaryBorder(),
                fontSize: fontSize,
              ),
              for (final question in questions)
                _summaryCell(
                  _cleanPdfText(question.number),
                  boldFont,
                  align: pw.TextAlign.center,
                  border: _summaryBorder(),
                  fontSize: fontSize,
                ),
            ],
          ),
          pw.TableRow(
            children: [
              _summaryCell(
                'CLOs',
                boldFont,
                shaded: true,
                align: pw.TextAlign.center,
                border: _summaryBorder(),
                fontSize: fontSize,
              ),
              for (final question in questions)
                _summaryCell(
                  _cleanPdfText(question.clo),
                  boldFont,
                  align: pw.TextAlign.center,
                  border: _summaryBorder(),
                  fontSize: fontSize,
                ),
            ],
          ),
          pw.TableRow(
            children: [
              _summaryCell(
                'Marks',
                boldFont,
                shaded: true,
                align: pw.TextAlign.center,
                border: _summaryBorder(),
                fontSize: fontSize,
              ),
              for (final question in questions)
                _summaryCell(
                  _cleanPdfText(question.effectiveMarksText),
                  boldFont,
                  align: pw.TextAlign.center,
                  border: _summaryBorder(),
                  fontSize: fontSize,
                ),
            ],
          ),
        ],
      ),
    ),
  );
}

pw.Border _summaryBorder() {
  return const pw.Border(
    top: pw.BorderSide(width: 0.55, color: PdfColors.black),
    right: pw.BorderSide(width: 0.55, color: PdfColors.black),
    bottom: pw.BorderSide(width: 0.55, color: PdfColors.black),
    left: pw.BorderSide(width: 0.55, color: PdfColors.black),
  );
}

pw.Widget _summaryCell(
  String text,
  pw.Font boldFont, {
  bool shaded = false,
  pw.TextAlign align = pw.TextAlign.left,
  pw.Border? border,
  double fontSize = 7.8,
}) {
  return pw.Container(
    decoration: pw.BoxDecoration(
      color: shaded ? PdfColor.fromInt(0xFFD9D9D9) : PdfColors.white,
      border: border,
    ),
    padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.2),
    child: pw.Text(
      _cleanPdfText(text),
      textAlign: align,
      style: pw.TextStyle(font: shaded ? boldFont : null, fontSize: fontSize),
    ),
  );
}

List<pw.Widget> _buildQuestionSection(
  List<PaperQuestionData> questions,
  pw.Font boldFont,
) {
  if (!_shouldUseTwoColumnLayout(questions)) {
    return _buildQuestionBlocks(questions, boldFont, compact: false);
  }

  final rows = <pw.Widget>[];
  for (var index = 0; index < questions.length; index += 2) {
    rows.add(
      pw.Padding(
        padding: const pw.EdgeInsets.only(bottom: 3),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.Expanded(
              child: _buildQuestionBlock(
                questions[index],
                boldFont,
                compact: true,
              ),
            ),
            pw.SizedBox(width: 6),
            pw.Expanded(
              child: index + 1 < questions.length
                  ? _buildQuestionBlock(
                      questions[index + 1],
                      boldFont,
                      compact: true,
                    )
                  : pw.SizedBox(),
            ),
          ],
        ),
      ),
    );
  }
  return rows;
}

List<pw.Widget> _buildQuestionBlocks(
  List<PaperQuestionData> questions,
  pw.Font boldFont, {
  required bool compact,
}) {
  return questions
      .map(
        (question) => pw.Padding(
          padding: const pw.EdgeInsets.only(bottom: 2),
          child: _buildQuestionBlock(question, boldFont, compact: compact),
        ),
      )
      .toList();
}

pw.Widget _buildQuestionBlock(
  PaperQuestionData question,
  pw.Font boldFont, {
  required bool compact,
}) {
  final questionFontSize = compact ? 8.7 : 11.2;
  final headingFontSize = compact ? 7.1 : 8.3;
  final padding = compact ? 3.2 : 5.0;
  final marksColumnWidth = compact ? 54.0 : 92.0;
  final minBodyHeight = compact ? 24.0 : 58.0;
  final questionBody = <pw.Widget>[
    if (question.text.isNotEmpty)
      pw.Padding(
        padding: pw.EdgeInsets.fromLTRB(padding, 3, padding, 4),
        child: pw.Text(
          _cleanPdfText(question.text),
          style: pw.TextStyle(fontSize: questionFontSize, lineSpacing: 1),
        ),
      ),
    if (question.options.isNotEmpty)
      _buildOptionsBlock(question, boldFont, compact: compact),
    for (final entry in question.subparts.asMap().entries)
      _buildSubpartBlock(question, entry, boldFont, compact: compact),
    if (question.imageBytes != null)
      _buildQuestionImageBlock(question, boldFont, compact: compact),
    if (question.text.isEmpty &&
        question.subparts.isEmpty &&
        question.imageBytes == null &&
        question.options.isEmpty)
      pw.SizedBox(height: minBodyHeight),
  ];

  return pw.Table(
    border: pw.TableBorder.all(width: 0.6, color: PdfColors.black),
    columnWidths: {
      0: const pw.FlexColumnWidth(),
      1: pw.FixedColumnWidth(marksColumnWidth),
    },
    children: [
      pw.TableRow(
        children: [
          pw.Container(
            padding: pw.EdgeInsets.fromLTRB(padding, 2.4, padding, 2.4),
            child: pw.Text(
              'Q${_cleanPdfText(question.number)}: [CLO ${_cleanPdfText(question.clo)}, PLO ${_cleanPdfText(question.plo)}] Total marks: ${_cleanPdfText(question.effectiveMarksText)}',
              style: pw.TextStyle(font: boldFont, fontSize: headingFontSize),
            ),
          ),
          pw.Container(
            alignment: pw.Alignment.center,
            padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 2),
            child: pw.Text(
              'Marks [ ${_cleanPdfText(question.effectiveMarksText)} ]',
              textAlign: pw.TextAlign.center,
              style: pw.TextStyle(font: boldFont, fontSize: headingFontSize),
            ),
          ),
        ],
      ),
      pw.TableRow(
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: questionBody,
          ),
          pw.SizedBox(height: minBodyHeight),
        ],
      ),
    ],
  );
}

pw.Widget _buildSubpartBlock(
  PaperQuestionData question,
  MapEntry<int, PaperSubpartData> entry,
  pw.Font boldFont, {
  required bool compact,
}) {
  final marksWidth = compact ? 42.0 : 58.0;
  final fontSize = compact ? 8.5 : 10.8;
  final labelFontSize = compact ? 7.4 : 8.1;

  return pw.Container(
    decoration: const pw.BoxDecoration(
      border: pw.Border(
        top: pw.BorderSide(width: 0.45, color: PdfColors.black),
      ),
    ),
    padding: pw.EdgeInsets.fromLTRB(
      _subpartLeftInset(question.subpartPlacement, compact),
      2.4,
      compact ? 3.2 : 5,
      2.4,
    ),
    child: pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                '(${_subpartLabel(entry.key)}) ',
                style: pw.TextStyle(font: boldFont, fontSize: labelFontSize),
              ),
              pw.Expanded(
                child: pw.Text(
                  _cleanPdfText(entry.value.text),
                  style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1),
                ),
              ),
            ],
          ),
        ),
        pw.SizedBox(width: compact ? 2 : 5),
        pw.Container(
          width: marksWidth,
          decoration: pw.BoxDecoration(
            border: pw.Border.all(width: 0.45, color: PdfColors.black),
          ),
          padding: const pw.EdgeInsets.symmetric(horizontal: 2, vertical: 1.5),
          child: pw.Text(
            'Marks: ${_cleanPdfText(entry.value.marks)}',
            textAlign: pw.TextAlign.center,
            style: pw.TextStyle(font: boldFont, fontSize: compact ? 6.8 : 7.4),
          ),
        ),
      ],
    ),
  );
}

pw.Widget _buildOptionsBlock(
  PaperQuestionData question,
  pw.Font boldFont, {
  required bool compact,
}) {
  final fontSize = compact ? 8.4 : 10.4;
  final labelFontSize = compact ? 7.4 : 8.4;
  final leftPad = compact ? 10.0 : 18.0;

  return pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(leftPad, 2, compact ? 3.2 : 5, 4),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        for (final entry in question.options.asMap().entries)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 2),
            child: pw.Row(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  '(${_subpartLabel(entry.key)}) ',
                  style: pw.TextStyle(font: boldFont, fontSize: labelFontSize),
                ),
                pw.Expanded(
                  child: pw.Text(
                    _cleanPdfText(entry.value),
                    style: pw.TextStyle(fontSize: fontSize, lineSpacing: 1),
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

pw.Widget _buildQuestionImageBlock(
  PaperQuestionData question,
  pw.Font boldFont, {
  required bool compact,
}) {
  final alignment = _imageAlignment(question.imagePlacement);
  final maxWidth = compact ? 150.0 : 220.0;
  final maxHeight = compact ? 66.0 : 96.0;

  return pw.Padding(
    padding: pw.EdgeInsets.fromLTRB(compact ? 3.2 : 5, 0, compact ? 3.2 : 5, 5),
    child: pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.stretch,
      children: [
        if ((question.imageName ?? '').isNotEmpty)
          pw.Padding(
            padding: const pw.EdgeInsets.only(bottom: 3),
            child: pw.Align(
              alignment: alignment,
              child: pw.Text(
                'Attached image: ${_cleanPdfText(question.imageName ?? '')}',
                style: pw.TextStyle(
                  font: boldFont,
                  fontSize: compact ? 6.7 : 7.7,
                ),
              ),
            ),
          ),
        pw.Align(
          alignment: alignment,
          child: pw.Container(
            constraints: pw.BoxConstraints(
              maxWidth: maxWidth,
              maxHeight: maxHeight,
            ),
            child: pw.Image(
              pw.MemoryImage(question.imageBytes!),
              fit: pw.BoxFit.contain,
            ),
          ),
        ),
      ],
    ),
  );
}

bool _shouldUseTwoColumnLayout(List<PaperQuestionData> questions) {
  if (questions.length >= 5) {
    return true;
  }

  final estimatedLines = questions.fold<int>(
    0,
    (sum, question) => sum + _estimatedQuestionLines(question),
  );
  return estimatedLines > 30;
}

int _estimatedQuestionLines(PaperQuestionData question) {
  final questionLines = _estimatedTextLines(_cleanPdfText(question.text), 78);
  final subpartLines = question.subparts.fold<int>(
    0,
    (sum, subpart) =>
        sum + _estimatedTextLines(_cleanPdfText(subpart.text), 84),
  );
  final imageLines = question.imageBytes == null ? 0 : 7;
  return 3 + questionLines + subpartLines + imageLines;
}

int _estimatedTextLines(String text, int charsPerLine) {
  final trimmed = text.trim();
  if (trimmed.isEmpty) {
    return 0;
  }
  return (trimmed.length / charsPerLine).ceil().clamp(1, 30).toInt();
}

double _subpartLeftInset(SubpartPlacement placement, bool compact) {
  return switch (placement) {
    SubpartPlacement.indent => compact ? 10 : 22,
    SubpartPlacement.middle => compact ? 42 : 145,
  };
}

pw.Alignment _imageAlignment(QuestionImagePlacement placement) {
  return switch (placement) {
    QuestionImagePlacement.left => pw.Alignment.centerLeft,
    QuestionImagePlacement.center => pw.Alignment.center,
    QuestionImagePlacement.right => pw.Alignment.centerRight,
  };
}

String _subpartLabel(int index) {
  if (index < 26) {
    return String.fromCharCode(97 + index);
  }
  return '${index + 1}';
}

PaperQuestionData _cleanQuestionData(PaperQuestionData question) {
  return PaperQuestionData(
    number: _cleanPdfText(question.number),
    text: _cleanPdfText(question.text),
    marks: _cleanPdfText(question.marks),
    clo: _cleanPdfText(question.clo),
    plo: _cleanPdfText(question.plo),
    subparts: [
      for (final subpart in question.subparts)
        PaperSubpartData(
          text: _cleanPdfText(subpart.text),
          marks: _cleanPdfText(subpart.marks),
        ),
    ],
    imageBytes: question.imageBytes,
    imageName: question.imageName == null
        ? null
        : _cleanPdfText(question.imageName!),
    imagePlacement: question.imagePlacement,
    subpartPlacement: question.subpartPlacement,
  );
}

String _cleanPdfText(String value) {
  final normalized = value
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .replaceAll(' ', '\n')
      .replaceAll(' ', '\n')
      .replaceAll(' ', ' ')
      .replaceAll('​', '')
      .replaceAll('‌', '')
      .replaceAll('‍', '')
      .replaceAll('﻿', '');
  final buffer = StringBuffer();
  for (final rune in normalized.runes) {
    if (rune == 0x09) {
      buffer.write(' ');
      continue;
    }
    if (rune == 0x0A) {
      buffer.write('\n');
      continue;
    }
    if (rune < 0x20 || (rune >= 0x7F && rune <= 0x9F)) {
      continue;
    }
    buffer.writeCharCode(rune);
  }
  return buffer
      .toString()
      .replaceAll(RegExp(r'[ \t]+\n'), '\n')
      .replaceAll(RegExp(r'\n{3,}'), '\n\n')
      .trim();
}
