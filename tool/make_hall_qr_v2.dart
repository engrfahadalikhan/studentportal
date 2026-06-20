// Generates a realistic CSEXAM|QHALL|2| payload (the SS1 hall: 3 classes,
// 108 students) exactly the way csexam's buildCsexamHallQrV2 does, so the
// portal's hall-scan flow can be exercised on desktop where there is no
// camera. Run: dart run tool/make_hall_qr_v2.dart > hall_qr_v2.txt
import 'dart:convert';

import 'package:archive/archive.dart';

void main() {
  final seats = <List<Object?>>[];
  for (var i = 0; i < 58; i++) {
    seats.add(['BSCS-F25-${101 + i}', i ~/ 12 + 1, i % 12 + 1, 0]);
  }
  for (var i = 0; i < 2; i++) {
    seats.add(['BSCS-F22-${301 + i}', 6, i + 1, 1]);
  }
  for (var i = 0; i < 48; i++) {
    seats.add(['BSSE-F25-${101 + i}', i ~/ 12 + 6, i % 12 + 1, 2]);
  }

  final data = <String, Object?>{
    't': 'hall_seating_stats',
    'd': '30-Jun-26',
    's': '2nd',
    'h': 'SS1',
    'n': seats.length,
    'g': [
      ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 58],
      ['BSCS 7A', 'WIRELESS NETWORK SECURITY', 'SYEDA KINZA NAQVI', 2],
      ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. IQRA MAHEEN', 48],
    ],
    'm': seats,
  };

  final compressed = GZipEncoder().encode(utf8.encode(jsonEncode(data)));
  // ignore: avoid_print
  print('CSEXAM|QHALL|2|${base64Url.encode(compressed)}');
}
