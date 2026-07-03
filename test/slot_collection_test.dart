import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teacher_student_assessment_app/services/slot_collection_repository.dart';

String _qslot(Map<String, Object?> body) {
  final gz = GZipEncoder().encode(utf8.encode(jsonEncode(body)));
  return 'CSEXAM|QSLOT|1|${base64Url.encode(gz)}';
}

String _qattn(Map<String, Object?> body) {
  final gz = GZipEncoder().encode(utf8.encode(jsonEncode(body)));
  return 'CSEXAM|QATTN|1|${base64Url.encode(gz)}';
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('parseSlotOverview decodes a QSLOT payload', () {
    final payload = _qslot({
      't': 'slot_overview',
      'd': '22-Jun-26',
      's': '1st',
      'n': 720,
      'hu': 13,
      'r': [
        ['BSCS 4A', 'INFORMATION SECURITY', 'MS. UROOJ TARIQ', 'G24, SS4', 44],
        ['BSCS 6A', 'COMPILER CONSTRUCTION', 'MR. ASAD IQBAL', 'G24, G9', 43],
      ],
    });
    final overview = SlotCollectionRepository.parseSlotOverview(payload);
    expect(overview, isNotNull);
    expect(overview!.examDate, '22-Jun-26');
    expect(overview.shift, '1st');
    expect(overview.totalExpected, 720);
    expect(overview.rows.length, 2);
    expect(overview.rows.first.program, 'BSCS 4A');
    expect(overview.rows.first.expected, 44);
  });

  test('seed, scan a teacher QR, and manual entry build slot totals', () async {
    final repo = SlotCollectionRepository();
    await repo.open();
    await repo.clearAll();

    final slot = await repo.seedFromQr(_qslot({
      't': 'slot_overview',
      'd': '22-Jun-26',
      's': '1st',
      'n': 87,
      'hu': 2,
      'r': [
        ['BSCS 4A', 'INFORMATION SECURITY', 'MS. UROOJ TARIQ', 'G24, SS4', 44],
        ['BSCS 6A', 'COMPILER CONSTRUCTION', 'MR. ASAD IQBAL', 'G24, G9', 43],
      ],
    }));
    expect(slot.programs, 2);
    expect(slot.received, 0);

    // A teacher's hall QR carrying two BSCS 4A present, one absent, one UFM.
    final applied = await repo.applyTeacherQr(
      slotId: slot.id,
      rawPayload: _qattn({
        'h': 'SS4',
        'd': DateTime(2026, 6, 22, 9).toIso8601String(),
        's': '',
        'c': '',
        'by': 'MS. UROOJ TARIQ',
        'n': 3,
        'st': [
          ['F24-1', 'P', 'Col 1 Chair 1', 'BSCS 4A'],
          ['F24-2', 'P', 'Col 1 Chair 2', 'BSCS 4A'],
          ['F24-3', 'A', 'Col 1 Chair 3', 'BSCS 4A'],
        ],
        'u': [
          ['F24-1', 'Mobile phone', ''],
        ],
      }),
    );
    expect(applied.matched, contains('BSCS 4A'));
    expect(applied.from, 'MS. UROOJ TARIQ');

    var rows = await repo.loadRows(slot.id);
    final r4a = rows.firstWhere((r) => r.program == 'BSCS 4A');
    expect(r4a.present, 2);
    expect(r4a.absent, 1);
    expect(r4a.ufm, 1);
    expect(r4a.received, isTrue);
    expect(r4a.receivedFrom, 'MS. UROOJ TARIQ');

    // The receipt log records who handed the data over.
    final receipts = await repo.loadReceipts(slot.id);
    expect(receipts.length, 1);
    expect(receipts.first.receivedFrom, 'MS. UROOJ TARIQ');
    expect(receipts.first.programs, contains('BSCS 4A'));

    // The other program filled by hand.
    final r6a = rows.firstWhere((r) => r.program == 'BSCS 6A');
    await repo.setRow(rowId: r6a.id, present: 40, absent: 3, ufm: 0);

    final totals = await repo.loadSlot(slot.id);
    expect(totals!.totalPresent, 42); // 2 + 40
    expect(totals.totalAbsent, 4); // 1 + 3
    expect(totals.totalUfm, 1);
    expect(totals.received, 2);

    await repo.clearAll();
  });
}
