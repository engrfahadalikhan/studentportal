import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../assessment/assessment_models.dart';
import '../assessment/assessment_qr_codec.dart';
import '../assessment/submission_qr_codec.dart';
import 'app_repository.dart';

/// PROTOTYPE — local (no-internet) exam host. The teacher's phone runs a tiny
/// HTTP server on the local WiFi; student phones fetch the quiz and POST their
/// submission back, so no QR scanning is needed for connected devices.
///
/// It reuses the SAME answer-safe codecs as the QR flow:
///   GET  /quiz   -> `AssessmentQrCodec.encode` (no answer key)
///   POST /submit -> body = `SubmissionQrCodec.encode`, imported + auto-graded
class LocalExamServer extends ChangeNotifier {
  LocalExamServer(this.repository);

  final AppRepository repository;
  HttpServer? _server;
  Assessment? assessment;
  String? url;
  int submissionCount = 0;
  final Set<String> _seenClients = {};

  bool get running => _server != null;
  int get connectedCount => _seenClients.length;

  Future<String?> start(Assessment a, {int port = 8080}) async {
    if (_server != null) await stop();
    assessment = a;
    submissionCount = 0;
    _seenClients.clear();
    final ip = await _wifiIp();
    _server = await HttpServer.bind(InternetAddress.anyIPv4, port, shared: true);
    _server!.listen(_handle);
    url = ip == null ? null : 'http://$ip:$port';
    notifyListeners();
    return url;
  }

  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
    notifyListeners();
  }

  Future<void> _handle(HttpRequest req) async {
    final res = req.response;
    res.headers.set('Access-Control-Allow-Origin', '*');
    _seenClients.add(req.connectionInfo?.remoteAddress.address ?? '');
    try {
      if (req.method == 'GET' && req.uri.path == '/quiz') {
        final payload =
            assessment == null ? '' : (AssessmentQrCodec.encode(assessment!) ?? '');
        res
          ..statusCode = 200
          ..headers.contentType = ContentType.text
          ..write(payload);
      } else if (req.method == 'POST' && req.uri.path == '/submit') {
        final body = await utf8.decodeStream(req);
        try {
          final sub = SubmissionQrCodec.decode(body.trim());
          repository.importSubmission(sub);
          submissionCount++;
          notifyListeners();
          res
            ..statusCode = 200
            ..write('OK');
        } catch (_) {
          res
            ..statusCode = 400
            ..write('bad submission');
        }
      } else if (req.uri.path == '/' || req.uri.path == '/ping') {
        res
          ..statusCode = 200
          ..write('AUST exam host: ${assessment?.title ?? ''}');
      } else {
        res.statusCode = 404;
      }
    } catch (_) {
      try {
        res.statusCode = 500;
      } catch (_) {}
    }
    await res.close();
  }

  /// The phone's LAN IPv4 (192.x / 10.x / 172.x) for students to connect to.
  Future<String?> _wifiIp() async {
    try {
      for (final ni in await NetworkInterface.list(
        type: InternetAddressType.IPv4,
        includeLoopback: false,
      )) {
        for (final a in ni.addresses) {
          final ip = a.address;
          if (ip.startsWith('192.') ||
              ip.startsWith('10.') ||
              ip.startsWith('172.')) {
            return ip;
          }
        }
      }
    } catch (_) {}
    return null;
  }

  @override
  void dispose() {
    _server?.close(force: true);
    super.dispose();
  }
}
