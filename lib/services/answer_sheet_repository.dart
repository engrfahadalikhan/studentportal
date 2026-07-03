import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'admin_data_bundle.dart';
import 'cloud_sync_service.dart';

/// Tracks the custody of exam answer-sheet bundles between the admin/exam-cell
/// and the teachers who mark them.
///
/// The admin scans a csexam "program stats" QR (`type: program_stats`,
/// `action: open_answer_sheet_workflow`) — or any hall/envelope QR that lists
/// classes — when **issuing** papers to teachers, and scans the same QR again
/// when the marked papers are **returned**. Each (program · subject · faculty)
/// bundle is one row whose status moves issued → returned.
class AnswerSheetRepository {
  Database? _db;

  Future<void> open() async {
    if (_db != null) return;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'answer_sheet_tracker.db'),
      version: 1,
      onCreate: (db, _) async => _ensureSchema(db),
      onUpgrade: (db, _, __) async => _ensureSchema(db),
      onOpen: _ensureSchema,
    );
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS paper_batches(
        id TEXT PRIMARY KEY,
        program TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        faculty TEXT NOT NULL DEFAULT '',
        hall TEXT NOT NULL DEFAULT '',
        exam_date TEXT NOT NULL DEFAULT '',
        shift TEXT NOT NULL DEFAULT '',
        count INTEGER NOT NULL DEFAULT 0,
        status TEXT NOT NULL DEFAULT 'issued',
        issued_at TEXT,
        returned_at TEXT
      )
    ''');
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('AnswerSheetRepository.open() was not called.');
    }
    return db;
  }

  // ---------------------------------------------------- admin data-share
  Future<Map<String, dynamic>> exportBundle() async {
    return {'paper_batches': await TableSync.dump(_requireDb(), 'paper_batches')};
  }

  Future<(int, int)> importBundle(Map<String, dynamic> data) async {
    return TableSync.merge(
      _requireDb(),
      'paper_batches',
      (data['paper_batches'] as List?) ?? const [],
      tsOf: (r) => TableSync.tsAny(r, ['returned_at', 'issued_at']),
    );
  }

  /// Parses [rawPayload] and records every paper bundle in it as issued (or
  /// returned when [isReturn] is true). Returns the affected rows + a summary.
  Future<PaperScanResult> recordScan({
    required String rawPayload,
    required bool isReturn,
  }) async {
    final parsed = parsePaperBatches(rawPayload);
    if (parsed.isEmpty) {
      throw const FormatException(
        'Not a CSEXAM program / hall QR. Scan the "Program stats" or hall QR '
        'printed by csexam.',
      );
    }
    final db = _requireDb();
    final now = DateTime.now().toIso8601String();
    final affected = <PaperBatch>[];
    var created = 0;
    await db.transaction((txn) async {
      for (final batch in parsed) {
        final existing = await txn.query(
          'paper_batches',
          where: 'id = ?',
          whereArgs: [batch.id],
          limit: 1,
        );
        if (existing.isEmpty) {
          created += 1;
        }
        final values = <String, Object?>{
          'id': batch.id,
          'program': batch.program,
          'subject': batch.subject,
          'faculty': batch.faculty,
          'hall': batch.hall,
          'exam_date': batch.examDate,
          'shift': batch.shift,
          'count': batch.count,
          'status': isReturn ? 'returned' : 'issued',
        };
        if (isReturn) {
          values['returned_at'] = now;
          // Preserve the original issue time if we have it.
          if (existing.isNotEmpty && existing.first['issued_at'] != null) {
            values['issued_at'] = existing.first['issued_at'];
          } else {
            values['issued_at'] = existing.isNotEmpty
                ? existing.first['issued_at']
                : now;
          }
        } else {
          values['issued_at'] = now;
          values['returned_at'] = null;
        }
        await txn.insert(
          'paper_batches',
          values,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        affected.add(PaperBatch.fromMap(values));
      }
    });
    final teachers = affected
        .map((b) => b.faculty.trim().isEmpty ? b.program : b.faculty)
        .toSet()
        .length;
    final verb = isReturn ? 'Returned' : 'Issued';
    CloudSyncService.instance.pushModulesSoon('answerSheets');
    return PaperScanResult(
      affected: affected,
      created: created,
      message:
          '$verb ${affected.length} bundle(s) for $teachers teacher(s).',
    );
  }

  /// Manually flips one bundle between issued and returned (tap on a row).
  Future<void> toggleStatus(String id) async {
    final db = _requireDb();
    final rows = await db.query(
      'paper_batches',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final current = rows.first['status']?.toString() ?? 'issued';
    final now = DateTime.now().toIso8601String();
    if (current == 'returned') {
      await db.update(
        'paper_batches',
        {'status': 'issued', 'issued_at': now, 'returned_at': null},
        where: 'id = ?',
        whereArgs: [id],
      );
    } else {
      await db.update(
        'paper_batches',
        {'status': 'returned', 'returned_at': now},
        where: 'id = ?',
        whereArgs: [id],
      );
    }
    CloudSyncService.instance.pushModulesSoon('answerSheets');
  }

  Future<List<PaperBatch>> loadAll() async {
    final rows = await _requireDb().query(
      'paper_batches',
      orderBy: 'faculty COLLATE NOCASE, program, subject',
    );
    return rows.map(PaperBatch.fromMap).toList(growable: false);
  }

  Future<void> deleteBatch(String id) async {
    await _requireDb().delete('paper_batches', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> clearAll() async {
    await _requireDb().delete('paper_batches');
  }

  // ----------------------------------------------------------------- parsing

  /// Extracts the paper bundles from a scanned csexam QR. Handles the
  /// `program_stats` workflow QR, hall/envelope `groups` QRs, and the
  /// compressed `CSEXAM|QHALL|2|` hall QR. Returns an empty list if the
  /// payload is not a recognised csexam stats QR.
  static List<PaperBatch> parsePaperBatches(String rawPayload) {
    final raw = rawPayload.trim();
    if (raw.isEmpty) return const [];

    Map<dynamic, dynamic>? data;
    if (raw.startsWith('CSEXAM|QHALL|2|')) {
      data = _inflateHallV2(raw.substring('CSEXAM|QHALL|2|'.length));
    } else {
      final decoded = _tryJson(raw);
      if (decoded is Map) {
        data = decoded;
      }
    }
    if (data == null) return const [];

    final app = (data['app'] ?? '').toString().toUpperCase();
    // QHALL v2 has no 'app' field; everything else should say CSEXAM.
    if (app.isNotEmpty && app != 'CSEXAM') return const [];

    final examDate = _str(data, ['date', 'd']);
    final shift = _str(data, ['shift', 's']);
    final batches = <PaperBatch>[];

    // 1) program_stats workflow QR: one program, many subject rows.
    final type = (data['type'] ?? '').toString();
    if (type == 'program_stats' && data['rows'] is List) {
      final program = _str(data, ['program', 'p']);
      for (final row in data['rows'] as List) {
        if (row is! List || row.length < 2) continue;
        final venue = row[0].toString().trim();
        final subject = row[1].toString().trim();
        // After the csexam update rows carry faculty; older QRs do not.
        String faculty = '';
        int count = 0;
        if (row.length >= 4 && row[2] is! num) {
          faculty = row[2].toString().trim();
          count = _int(row[3]);
        } else if (row.length >= 3) {
          count = _int(row[2]);
        }
        batches.add(
          PaperBatch.create(
            program: program,
            subject: subject,
            faculty: faculty,
            hall: venue,
            examDate: examDate,
            shift: shift,
            count: count,
          ),
        );
      }
    }

    // 2) hall / envelope QR with a groups list (program, subject, faculty, n).
    final groups = data['groups'] ?? data['g'];
    if (groups is List) {
      final hall = _str(data, ['hall', 'h']);
      for (final group in groups) {
        if (group is! List || group.length < 2) continue;
        final program = group[0].toString().trim();
        final subject = group.length > 1 ? group[1].toString().trim() : '';
        final faculty = group.length > 2 ? group[2].toString().trim() : '';
        final count = group.length > 3 ? _int(group[3]) : 0;
        batches.add(
          PaperBatch.create(
            program: program,
            subject: subject,
            faculty: faculty,
            hall: hall,
            examDate: examDate,
            shift: shift,
            count: count,
          ),
        );
      }
    }

    // De-duplicate bundles that appear more than once in the same QR.
    final byId = <String, PaperBatch>{};
    for (final batch in batches) {
      byId[batch.id] = batch;
    }
    return byId.values.toList(growable: false);
  }

  static Map<dynamic, dynamic>? _inflateHallV2(String body) {
    try {
      var encoded = body.trim();
      final mod = encoded.length % 4;
      if (mod != 0) {
        encoded = encoded.padRight(encoded.length + (4 - mod), '=');
      }
      final bytes = base64Url.decode(encoded);
      final json = utf8.decode(GZipDecoder().decodeBytes(bytes));
      final decoded = jsonDecode(json);
      return decoded is Map ? decoded : null;
    } catch (_) {
      return null;
    }
  }

  static Object? _tryJson(String value) {
    try {
      return jsonDecode(value);
    } catch (_) {
      return null;
    }
  }

  static String _str(Map<dynamic, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return '';
  }

  static int _int(Object? value) => int.tryParse('${value ?? 0}') ?? 0;
}

/// One answer-sheet bundle: a (program · subject · faculty) batch handed to a
/// teacher for marking.
class PaperBatch {
  const PaperBatch({
    required this.id,
    required this.program,
    required this.subject,
    required this.faculty,
    required this.hall,
    required this.examDate,
    required this.shift,
    required this.count,
    required this.status,
    this.issuedAt,
    this.returnedAt,
  });

  factory PaperBatch.create({
    required String program,
    required String subject,
    required String faculty,
    required String hall,
    required String examDate,
    required String shift,
    required int count,
  }) {
    return PaperBatch(
      id: _stableId('$program|$subject|$faculty|$examDate|$shift|$hall'),
      program: program,
      subject: subject,
      faculty: faculty,
      hall: hall,
      examDate: examDate,
      shift: shift,
      count: count,
      status: 'issued',
    );
  }

  factory PaperBatch.fromMap(Map<String, Object?> map) {
    return PaperBatch(
      id: (map['id'] ?? '').toString(),
      program: (map['program'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      faculty: (map['faculty'] ?? '').toString(),
      hall: (map['hall'] ?? '').toString(),
      examDate: (map['exam_date'] ?? '').toString(),
      shift: (map['shift'] ?? '').toString(),
      count: int.tryParse('${map['count'] ?? 0}') ?? 0,
      status: (map['status'] ?? 'issued').toString(),
      issuedAt: DateTime.tryParse((map['issued_at'] ?? '').toString()),
      returnedAt: DateTime.tryParse((map['returned_at'] ?? '').toString()),
    );
  }

  final String id;
  final String program;
  final String subject;
  final String faculty;
  final String hall;
  final String examDate;
  final String shift;
  final int count;
  final String status; // 'issued' | 'returned'
  final DateTime? issuedAt;
  final DateTime? returnedAt;

  bool get isReturned => status == 'returned';

  /// Who holds / held the papers. Falls back to the program when csexam did
  /// not record a faculty name.
  String get teacherLabel => faculty.trim().isEmpty ? program : faculty;

  static String _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.toUpperCase().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'PB${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

class PaperScanResult {
  const PaperScanResult({
    required this.affected,
    required this.created,
    required this.message,
  });

  final List<PaperBatch> affected;
  final int created;
  final String message;
}
