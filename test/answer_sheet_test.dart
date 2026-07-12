import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teacher_student_assessment_app/services/answer_sheet_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  test('parses the csexam program_stats QR into per-teacher bundles', () {
    final raw = jsonEncode({
      'app': 'CSEXAM',
      'v': 1,
      'type': 'program_stats',
      'action': 'open_answer_sheet_workflow',
      'date': '30-Jun-26',
      'shift': '2nd',
      'program': 'BSCS 2A',
      'students': 60,
      'rows': [
        // venue, subject, faculty, count, submitted, evaluator, controller
        ['SS1', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 58, 0, 0, 0],
        ['SS1', 'WIRELESS NETWORK SECURITY', 'SYEDA KINZA NAQVI', 2, 0, 0, 0],
      ],
    });
    final batches = AnswerSheetRepository.parsePaperBatches(raw);
    expect(batches, hasLength(2));
    final aman = batches.firstWhere((b) => b.faculty == 'MR. ABDUL AMAN');
    expect(aman.program, 'BSCS 2A');
    expect(aman.subject, 'EXPOSITORY WRITING');
    expect(aman.count, 58);
    expect(aman.teacherLabel, 'MR. ABDUL AMAN');
  });

  test('parses a hall/envelope groups QR (faculty per group)', () {
    final raw = jsonEncode({
      'app': 'CSEXAM',
      'type': 'envelope_summary',
      'action': 'open_hall_attendance',
      'date': '30-Jun-26',
      'shift': '2nd',
      'hall': 'SS1',
      'groups': [
        ['BSCS 2A', 'EXPOSITORY WRITING', 'MR. ABDUL AMAN', 58, 'pending'],
        ['BSSE 2A', 'EXPOSITORY WRITING', 'MS. IQRA MAHEEN', 48, 'pending'],
      ],
    });
    final batches = AnswerSheetRepository.parsePaperBatches(raw);
    expect(batches, hasLength(2));
    expect(batches.any((b) => b.faculty == 'MS. IQRA MAHEEN'), isTrue);
    expect(batches.every((b) => b.hall == 'SS1'), isTrue);
  });

  test('rejects a non-csexam payload', () {
    expect(AnswerSheetRepository.parsePaperBatches('hello world'), isEmpty);
    expect(
      AnswerSheetRepository.parsePaperBatches(
        jsonEncode({'app': 'OTHER', 'groups': []}),
      ),
      isEmpty,
    );
  });

  test('issue then return moves a bundle between buckets', () async {
    final repo = AnswerSheetRepository();
    await repo.open();
    await repo.clearAll();

    final qr = jsonEncode({
      'app': 'CSEXAM',
      'type': 'program_stats',
      'action': 'open_answer_sheet_workflow',
      'date': '29-May-26',
      'shift': '1st',
      'program': 'BSCS 4A',
      'rows': [
        ['G10', 'DATA STRUCTURES', 'DR. ASIM', 40, 0, 0, 0],
      ],
    });

    // Issue.
    final issued = await repo.recordScan(rawPayload: qr, isReturn: false);
    expect(issued.affected, hasLength(1));
    expect(issued.created, 1);
    var all = await repo.loadAll();
    expect(all, hasLength(1));
    expect(all.first.isReturned, isFalse);
    expect(all.first.issuedAt, isNotNull);

    // Return the same bundle (same id → updates, not duplicates).
    final returned = await repo.recordScan(rawPayload: qr, isReturn: true);
    expect(returned.created, 0);
    all = await repo.loadAll();
    expect(all, hasLength(1));
    expect(all.first.isReturned, isTrue);
    expect(all.first.returnedAt, isNotNull);

    // Manual toggle flips it back to "out".
    await repo.toggleStatus(all.first.id);
    all = await repo.loadAll();
    expect(all.first.isReturned, isFalse);

    // A bad scan is reported clearly.
    expect(
      () => repo.recordScan(rawPayload: 'nonsense', isReturn: false),
      throwsA(isA<FormatException>()),
    );

    await repo.clearAll();
    expect(await repo.loadAll(), isEmpty);
  });
}
