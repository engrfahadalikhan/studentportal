import 'package:http/http.dart' as http;

import '../assessment/assessment_models.dart';
import '../assessment/assessment_qr_codec.dart';
import '../assessment/submission_qr_codec.dart';

/// PROTOTYPE — student side of the local (no-internet) exam. Connects to the
/// teacher host over the local WiFi by URL (e.g. http://192.168.1.5:8080).
class LocalExamClient {
  static String normalize(String url) {
    var s = url.trim();
    if (s.isEmpty) return s;
    if (!s.startsWith('http://') && !s.startsWith('https://')) {
      s = 'http://$s';
    }
    if (s.endsWith('/')) s = s.substring(0, s.length - 1);
    return s;
  }

  /// Downloads the (answer-safe) quiz from the teacher host.
  static Future<Assessment> fetchQuiz(String baseUrl) async {
    final r = await http
        .get(Uri.parse('${normalize(baseUrl)}/quiz'))
        .timeout(const Duration(seconds: 8));
    if (r.statusCode != 200 || r.body.trim().isEmpty) {
      throw const FormatException('No quiz available from the teacher host.');
    }
    return AssessmentQrCodec.decode(r.body.trim());
  }

  /// Uploads the student's submission to the teacher host. Returns true on 200.
  static Future<bool> submit(String baseUrl, AssessmentSubmission s) async {
    final payload = SubmissionQrCodec.encode(s);
    if (payload == null) return false;
    final r = await http
        .post(Uri.parse('${normalize(baseUrl)}/submit'), body: payload)
        .timeout(const Duration(seconds: 8));
    return r.statusCode == 200;
  }
}
