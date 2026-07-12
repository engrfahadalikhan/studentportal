import 'dart:convert';

import 'package:archive/archive.dart';

import 'assessment_models.dart';
import 'assessment_mock_data.dart' as mock;

/// Offline "question-paper over QR" codec.
///
/// A QR code is just a small text container (~2-3 KB). To exchange a paper
/// between two phones with **no internet**, we pack the whole assessment into
/// the QR itself: compact JSON -> gzip -> base64url -> prefixed string.
///
/// This mirrors the proven approach already used by the attendance transfer
/// QR (`CSEXAM|QXFER|1|...`). The student phone scans the QR, this codec
/// decodes it back into a real [Assessment], and the attempt flow runs fully
/// offline.
///
/// Format:  `AUSTQP|1|<base64url(gzip(utf8(json)))>`
class AssessmentQrCodec {
  AssessmentQrCodec._();

  static const String prefix = 'AUSTQP|1|';

  /// Rough capacity guard. QR version 40 (the largest) holds ~2.9 KB of
  /// binary; we keep a safety margin. Beyond this, a paper is too big to fit
  /// in a single offline QR and should be shared as a printed PDF instead.
  static const int maxPayloadChars = 2200;

  // ------------------------------------------------------------------ encode
  /// Build the QR string for [assessment]. Returns null if the packed payload
  /// is too large to fit in a single scannable QR.
  static String? encode(Assessment assessment) {
    final body = <String, Object?>{
      'v': 1,
      'id': assessment.id,
      't': assessment.title,
      'ty': assessment.type.index,
      'c': assessment.courseId,
      'p': assessment.program,
      's': assessment.semester,
      'se': assessment.section,
      'd': assessment.durationMinutes,
      'i': assessment.instructions,
      'q': [
        for (final q in assessment.questions)
          {
            'i': q.id,
            't': q.type.index,
            'q': q.question,
            'm': q.marks,
            if (q.options.isNotEmpty) 'o': q.options,
            // NOTE: the correct answer is deliberately NOT included. The
            // student-facing QR must be answer-safe — a student could otherwise
            // decode the QR and read the answer key. Correct answers stay only
            // on the teacher's device, and marks are computed at the teacher's
            // end (see AppRepository.objectiveAutoMarks + the Results grade
            // sheet).
            if (q.timeMinutes > 0) 'tm': q.timeMinutes,
          },
      ],
    };

    final jsonBytes = utf8.encode(jsonEncode(body));
    final gzipped = GZipEncoder().encode(jsonBytes);
    final encoded = base64Url.encode(gzipped);
    final payload = '$prefix$encoded';
    if (payload.length > maxPayloadChars) {
      return null;
    }
    return payload;
  }

  /// How big the encoded payload is (for UI "fits in QR?" hints). Returns -1
  /// if encoding fails.
  static int payloadSize(Assessment assessment) {
    final encoded = encode(assessment);
    return encoded?.length ?? -1;
  }

  // ------------------------------------------------------------------ decode
  static bool looksLikeAssessmentQr(String raw) =>
      raw.trim().startsWith(prefix);

  /// Decode a scanned QR string back into an [Assessment]. Throws
  /// [FormatException] on anything malformed so callers can show a friendly
  /// "invalid QR" message.
  static Assessment decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(prefix)) {
      throw const FormatException('Not an AUST question-paper QR.');
    }
    final encoded = trimmed.substring(prefix.length);
    final List<int> gzipped;
    try {
      gzipped = base64Url.decode(_withPadding(encoded));
    } catch (_) {
      throw const FormatException('QR payload is not valid base64.');
    }
    final List<int> jsonBytes;
    try {
      jsonBytes = GZipDecoder().decodeBytes(gzipped);
    } catch (_) {
      throw const FormatException('QR payload could not be decompressed.');
    }
    final decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is! Map) {
      throw const FormatException('QR payload is not a valid paper.');
    }

    final typeIndex = _int(decoded['ty']);
    final type = (typeIndex >= 0 && typeIndex < AssessmentType.values.length)
        ? AssessmentType.values[typeIndex]
        : AssessmentType.quiz;

    final rawQuestions = decoded['q'];
    final questions = <AssessmentQuestion>[];
    if (rawQuestions is List) {
      for (final entry in rawQuestions) {
        if (entry is! Map) continue;
        final qTypeIndex = _int(entry['t']);
        final qType =
            (qTypeIndex >= 0 && qTypeIndex < QuestionType.values.length)
            ? QuestionType.values[qTypeIndex]
            : QuestionType.mcq;
        questions.add(
          AssessmentQuestion(
            id: _string(entry['i']).isEmpty
                ? 'Q${questions.length + 1}'
                : _string(entry['i']),
            type: qType,
            question: _string(entry['q']),
            marks: _int(entry['m']),
            options: [
              if (entry['o'] is List)
                for (final o in (entry['o'] as List)) o.toString(),
            ],
            correctAnswer:
                entry['a'] == null ? null : _string(entry['a']),
            timeMinutes: _int(entry['tm']),
          ),
        );
      }
    }

    final duration = _int(decoded['d']) == 0 ? 30 : _int(decoded['d']);
    final totalMarks = questions.fold<int>(0, (sum, q) => sum + q.marks);
    final now = DateTime.now();
    final id = _string(decoded['id']).isEmpty
        ? 'SHARED-${now.millisecondsSinceEpoch}'
        : _string(decoded['id']);

    return Assessment(
      id: id,
      title: _string(decoded['t']).isEmpty ? 'Shared paper' : _string(decoded['t']),
      type: type,
      courseId: _string(decoded['c']),
      program: _string(decoded['p']),
      semester: _string(decoded['s']),
      section: _string(decoded['se']),
      durationMinutes: duration,
      totalMarks: totalMarks,
      startTime: now,
      endTime: now.add(Duration(minutes: duration)),
      instructions: _string(decoded['i']),
      questions: questions,
      settings: mock.assessmentSettings,
      status: AssessmentStatus.active,
      qrCode: id,
    );
  }

  // ------------------------------------------------------------------ helpers
  static String _withPadding(String value) {
    final remainder = value.length % 4;
    if (remainder == 0) return value;
    return value.padRight(value.length + (4 - remainder), '=');
  }

  static int _int(Object? value) {
    if (value is int) return value;
    return int.tryParse(value?.toString() ?? '') ?? 0;
  }

  static String _string(Object? value) => (value ?? '').toString();
}
