import 'dart:convert';

import 'package:archive/archive.dart';

import 'assessment_models.dart';

/// Offline "student submission over QR" codec.
///
/// After a student submits their answers, this codec packs the submission into
/// a QR the teacher scans — completing the offline loop without any internet.
///
/// Format:  `AUSTQS|1|<base64url(gzip(utf8(json)))>`
///
/// What is packed:
///   - assessment id + student id
///   - per-question answers (but NO correct answers — those never leave the
///     teacher's device)
///   - attempt metadata: status, warningCount, flags, progress
///
/// What is NOT packed:
///   - The question text or options (teacher already has the paper)
///   - Any personal student info beyond the id (roll number)
class SubmissionQrCodec {
  SubmissionQrCodec._();

  static const String prefix = 'AUSTQS|1|';

  /// Max payload size (QR v40 can hold ~2.9 KB; we leave headroom).
  static const int maxPayloadChars = 2400;

  // ------------------------------------------------------------------ encode
  /// Encodes a submission as a QR string. Returns null when the payload is too
  /// large (many long essay answers would be unusual, but we guard for it).
  static String? encode(AssessmentSubmission submission) {
    final body = <String, Object?>{
      'v': 1,
      'a': submission.assessmentId,
      's': submission.studentId,
      'st': submission.status.index,
      'w': submission.warningCount,
      'p': submission.progress,
      if (submission.flags.isNotEmpty) 'f': submission.flags,
      // Answers: {questionId: givenAnswer}. We cap each answer at 300 chars
      // to keep the QR manageable (long essays should be shared separately).
      'ans': {
        for (final entry in submission.answers.entries)
          entry.key: entry.value.length > 300
              ? entry.value.substring(0, 300)
              : entry.value,
      },
    };

    final jsonBytes = utf8.encode(jsonEncode(body));
    final gzipped = GZipEncoder().encode(jsonBytes);
    final encoded = base64Url.encode(gzipped);
    final payload = '$prefix$encoded';
    return payload.length > maxPayloadChars ? null : payload;
  }

  // ------------------------------------------------------------------ decode
  static bool looksLike(String raw) => raw.trim().startsWith(prefix);

  /// Decodes a scanned QR string back into an [AssessmentSubmission].
  /// Throws [FormatException] on malformed input.
  static AssessmentSubmission decode(String raw) {
    final trimmed = raw.trim();
    if (!trimmed.startsWith(prefix)) {
      throw const FormatException('Not an AUST submission QR.');
    }
    final encoded = trimmed.substring(prefix.length);
    final List<int> gzipped;
    try {
      gzipped = base64Url.decode(_pad(encoded));
    } catch (_) {
      throw const FormatException('Submission QR payload is not valid base64.');
    }
    final List<int> jsonBytes;
    try {
      jsonBytes = GZipDecoder().decodeBytes(gzipped);
    } catch (_) {
      throw const FormatException('Submission QR payload could not be decompressed.');
    }
    final decoded = jsonDecode(utf8.decode(jsonBytes));
    if (decoded is! Map) {
      throw const FormatException('Submission QR payload is not valid JSON.');
    }

    final statusIndex = _int(decoded['st']);
    final status =
        (statusIndex >= 0 && statusIndex < AttemptStatus.values.length)
        ? AttemptStatus.values[statusIndex]
        : AttemptStatus.submitted;

    final rawAnswers = decoded['ans'];
    final answers = <String, String>{};
    if (rawAnswers is Map) {
      for (final entry in rawAnswers.entries) {
        answers[entry.key.toString()] = entry.value.toString();
      }
    }

    final rawFlags = decoded['f'];
    final flags = <String>[];
    if (rawFlags is List) {
      flags.addAll(rawFlags.map((f) => f.toString()));
    }

    return AssessmentSubmission(
      id: 'QR-${DateTime.now().millisecondsSinceEpoch}',
      assessmentId: _str(decoded['a']),
      studentId: _str(decoded['s']),
      status: status,
      answers: Map.unmodifiable(answers),
      marks: null,
      warningCount: _int(decoded['w']),
      flags: List.unmodifiable(flags),
      progress: _int(decoded['p']),
      submittedAt: DateTime.now(),
    );
  }

  // ------------------------------------------------------------------ helpers
  static String _pad(String v) {
    final r = v.length % 4;
    return r == 0 ? v : v.padRight(v.length + (4 - r), '=');
  }

  static int _int(Object? v) =>
      v is int ? v : int.tryParse(v?.toString() ?? '') ?? 0;

  static String _str(Object? v) => (v ?? '').toString();
}
