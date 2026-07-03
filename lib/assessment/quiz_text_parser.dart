/// Parses a pasted quiz (WhatsApp / plain text) into questions + options.
///
/// Recognised shapes:
///   - Question lines numbered `1.` `2)` `Q3:` …
///   - Option lines `A) text`, `a. text`, `(B) text`, `- text`, `• text`
///   - Correct option marked with `*` / `✓` / `(correct)` at the end, OR a
///     separate line `Answer: B` / `Ans - C`.
class ParsedQuizQuestion {
  String text = '';
  final List<String> options = [];
  int? correctIndex;
}

final _optRe = RegExp(r'^\s*[\(\[]?([A-Ha-h])[\)\.\]\:\-]\s+(.*\S)\s*$');
final _bulletRe = RegExp(r'^\s*[-•*▪●·]\s+(.*\S)\s*$');
final _qNumRe = RegExp(
  r'^\s*(?:Q(?:uestion)?\s*)?(\d{1,3})\s*[\.\)\:\-]\s*(.*)$',
  caseSensitive: false,
);
final _ansRe = RegExp(
  r'^\s*(?:ans(?:wer)?|correct(?:\s*answer)?)\s*[:\-]?\s*[\(\[]?([A-Ha-h])\b',
  caseSensitive: false,
);
final _correctParen = RegExp(r'\(correct\)', caseSensitive: false);

/// Strips a correct-answer marker (`*`, `✓`, `(correct)`) from an option and
/// reports whether it was present.
(String, bool) _processOption(String raw) {
  var text = raw.trim();
  final correct = text.endsWith('*') ||
      text.contains('✓') ||
      text.contains('✔') ||
      _correctParen.hasMatch(text);
  if (correct) {
    text = text
        .replaceAll('*', '')
        .replaceAll('✓', '')
        .replaceAll('✔', '')
        .replaceAll(_correctParen, '')
        .trim();
  }
  return (text, correct);
}

List<ParsedQuizQuestion> parseQuizText(String raw) {
  final lines =
      raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');

  final out = <ParsedQuizQuestion>[];
  ParsedQuizQuestion? cur;
  void flush() {
    if (cur != null &&
        (cur!.text.trim().isNotEmpty || cur!.options.isNotEmpty)) {
      out.add(cur!);
    }
    cur = null;
  }

  for (final lineRaw in lines) {
    final line = lineRaw.trim();
    if (line.isEmpty) continue;

    final ans = _ansRe.firstMatch(line);
    if (ans != null && cur != null && cur!.options.isNotEmpty) {
      final idx = ans.group(1)!.toUpperCase().codeUnitAt(0) - 65;
      if (idx >= 0 && idx < cur!.options.length) cur!.correctIndex = idx;
      continue;
    }

    final om = _optRe.firstMatch(line);
    final qm = _qNumRe.firstMatch(line);

    if (qm != null && om == null) {
      flush();
      cur = ParsedQuizQuestion()..text = qm.group(2)!.trim();
      continue;
    }
    if (om != null && cur != null) {
      final (opt, correct) = _processOption(om.group(2)!);
      cur!.options.add(opt);
      if (correct) cur!.correctIndex = cur!.options.length - 1;
      continue;
    }
    final bm = _bulletRe.firstMatch(line);
    if (bm != null && cur != null) {
      final (opt, correct) = _processOption(bm.group(1)!);
      cur!.options.add(opt);
      if (correct) cur!.correctIndex = cur!.options.length - 1;
      continue;
    }

    if (cur == null) {
      cur = ParsedQuizQuestion()..text = line;
    } else if (cur!.options.isEmpty) {
      cur!.text = '${cur!.text} $line'.trim();
    } else {
      flush();
      cur = ParsedQuizQuestion()..text = line;
    }
  }
  flush();
  return out;
}
