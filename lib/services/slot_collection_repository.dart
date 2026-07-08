import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'admin_data_bundle.dart';
import 'cloud_sync_service.dart';

/// Per-slot (per-day / per-shift) paper-collection consolidation.
///
/// The exam-cell scans the csexam "Overall Seating Summary" QR
/// (`CSEXAM|QSLOT|1|…`) to load the whole slot's program rows (program /
/// subject / faculty / halls / expected). Then, as each teacher reports their
/// stats, the cell either scans that teacher's attendance transfer QR
/// (`CSEXAM|QATTN|1|…`) or types the numbers; the matching program row is
/// filled with present / absent / UFM. At the end the slot shows the running
/// totals — total present, total absent, total UFM.
class SlotCollectionRepository {
  Database? _db;

  static const String _slotQrPrefix = 'CSEXAM|QSLOT|1|';
  static const String _attnQrPrefix = 'CSEXAM|QATTN|1|';

  Future<void> open() async {
    if (_db != null) return;
    final root = await getDatabasesPath();
    _db = await openDatabase(
      p.join(root, 'slot_collection.db'),
      version: 1,
      onCreate: (db, _) async => _ensureSchema(db),
      onUpgrade: (db, _, __) async => _ensureSchema(db),
      onOpen: _ensureSchema,
    );
  }

  Future<void> _ensureSchema(Database db) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slots(
        id TEXT PRIMARY KEY,
        exam_date TEXT NOT NULL DEFAULT '',
        shift TEXT NOT NULL DEFAULT '',
        expected INTEGER NOT NULL DEFAULT 0,
        used_halls INTEGER NOT NULL DEFAULT 0,
        created_at TEXT,
        updated_at TEXT
      )
    ''');
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slot_rows(
        id TEXT PRIMARY KEY,
        slot_id TEXT NOT NULL,
        prog_key TEXT NOT NULL DEFAULT '',
        program TEXT NOT NULL DEFAULT '',
        subject TEXT NOT NULL DEFAULT '',
        faculty TEXT NOT NULL DEFAULT '',
        halls TEXT NOT NULL DEFAULT '',
        expected INTEGER NOT NULL DEFAULT 0,
        present INTEGER NOT NULL DEFAULT 0,
        absent INTEGER NOT NULL DEFAULT 0,
        ufm INTEGER NOT NULL DEFAULT 0,
        received INTEGER NOT NULL DEFAULT 0,
        received_from TEXT NOT NULL DEFAULT '',
        updated_at TEXT
      )
    ''');
    // A log of every receipt: who (invigilator) handed which data, and when.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slot_receipts(
        id TEXT PRIMARY KEY,
        slot_id TEXT NOT NULL,
        received_from TEXT NOT NULL DEFAULT '',
        hall TEXT NOT NULL DEFAULT '',
        programs TEXT NOT NULL DEFAULT '',
        present INTEGER NOT NULL DEFAULT 0,
        absent INTEGER NOT NULL DEFAULT 0,
        ufm INTEGER NOT NULL DEFAULT 0,
        received_at TEXT NOT NULL DEFAULT ''
      )
    ''');
    // Each (program · source · hall) contribution to a slot. A program row's
    // present/absent/UFM is the SUM of its contributions, so a class split
    // across several halls ADDS UP, while a teacher re-scanning REPLACES their
    // own contribution (id is deterministic) — never double-counts.
    await db.execute('''
      CREATE TABLE IF NOT EXISTS slot_contributions(
        id TEXT PRIMARY KEY,
        slot_id TEXT NOT NULL,
        prog_key TEXT NOT NULL DEFAULT '',
        source TEXT NOT NULL DEFAULT '',
        hall TEXT NOT NULL DEFAULT '',
        present INTEGER NOT NULL DEFAULT 0,
        absent INTEGER NOT NULL DEFAULT 0,
        ufm INTEGER NOT NULL DEFAULT 0,
        updated_at TEXT
      )
    ''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_slot_contrib ON slot_contributions(slot_id, prog_key)',
    );
    // Guarded migration for installs created before received_from existed.
    final cols = await db.rawQuery('PRAGMA table_info(slot_rows)');
    if (!cols.any((c) => c['name'] == 'received_from')) {
      await db.execute(
        "ALTER TABLE slot_rows ADD COLUMN received_from TEXT NOT NULL DEFAULT ''",
      );
    }
  }

  Database _requireDb() {
    final db = _db;
    if (db == null) {
      throw StateError('SlotCollectionRepository.open() was not called.');
    }
    return db;
  }

  // --------------------------------------------------------------- seeding

  /// Seeds (or refreshes) a slot from a scanned/pasted `CSEXAM|QSLOT|1|` QR.
  /// Existing present/absent/UFM/received values for matching rows are kept, so
  /// re-scanning the slot QR never wipes collected progress. Returns the slot.
  Future<SlotSummary> seedFromQr(String rawPayload) async {
    final overview = parseSlotOverview(rawPayload);
    if (overview == null) {
      throw const FormatException(
        'Not a per-slot QR. Scan the "PER-SLOT QR" on the Overall Seating '
        'Summary page printed by csexam.',
      );
    }
    final db = _requireDb();
    final now = DateTime.now().toIso8601String();
    final slotId = _stableId('${overview.examDate}|${overview.shift}');
    await db.transaction((txn) async {
      final existingSlot = await txn.query(
        'slots',
        where: 'id = ?',
        whereArgs: [slotId],
        limit: 1,
      );
      await txn.insert('slots', {
        'id': slotId,
        'exam_date': overview.examDate,
        'shift': overview.shift,
        'expected': overview.totalExpected,
        'used_halls': overview.usedHalls,
        'created_at': existingSlot.isEmpty
            ? now
            : existingSlot.first['created_at'],
        'updated_at': now,
      }, conflictAlgorithm: ConflictAlgorithm.replace);

      for (final row in overview.rows) {
        final rowId = _stableId('$slotId|${row.progKey}');
        final prev = await txn.query(
          'slot_rows',
          where: 'id = ?',
          whereArgs: [rowId],
          limit: 1,
        );
        await txn.insert('slot_rows', {
          'id': rowId,
          'slot_id': slotId,
          'prog_key': row.progKey,
          'program': row.program,
          'subject': row.subject,
          'faculty': row.faculty,
          'halls': row.halls,
          'expected': row.expected,
          // preserve collected progress on re-seed
          'present': prev.isEmpty ? 0 : prev.first['present'],
          'absent': prev.isEmpty ? 0 : prev.first['absent'],
          'ufm': prev.isEmpty ? 0 : prev.first['ufm'],
          'received': prev.isEmpty ? 0 : prev.first['received'],
          'updated_at': prev.isEmpty ? null : prev.first['updated_at'],
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    CloudSyncService.instance.pushModulesSoon('slots');
    return (await loadSlot(slotId))!;
  }

  // --------------------------------------------------------------- updating

  /// Manually sets one program row's present/absent/UFM and marks it received.
  Future<void> setRow({
    required String rowId,
    required int present,
    required int absent,
    required int ufm,
  }) async {
    final db = _requireDb();
    final rows = await db.query(
      'slot_rows',
      columns: ['slot_id', 'prog_key'],
      where: 'id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    if (rows.isEmpty) return;
    final slotId = rows.first['slot_id'].toString();
    final progKey = (rows.first['prog_key'] ?? '').toString();
    await db.transaction((txn) async {
      // Manual entry is authoritative: clear every contribution for this
      // program and record one manual contribution with the typed numbers.
      await txn.delete(
        'slot_contributions',
        where: 'slot_id = ? AND prog_key = ?',
        whereArgs: [slotId, progKey],
      );
      await txn.insert('slot_contributions', {
        'id': _stableId('$slotId|$progKey|MANUAL'),
        'slot_id': slotId,
        'prog_key': progKey,
        'source': 'Manual entry',
        'hall': '',
        'present': present < 0 ? 0 : present,
        'absent': absent < 0 ? 0 : absent,
        'ufm': ufm < 0 ? 0 : ufm,
        'updated_at': DateTime.now().toIso8601String(),
      }, conflictAlgorithm: ConflictAlgorithm.replace);
      await _recomputeRow(txn, slotId, progKey, rowId);
    });
    await _touchSlotByRow(rowId);
    CloudSyncService.instance.pushModulesSoon('slots');
  }

  /// Clears a row back to "not received" (present/absent/UFM = 0).
  Future<void> resetRow(String rowId) async {
    final db = _requireDb();
    final rows = await db.query(
      'slot_rows',
      columns: ['slot_id', 'prog_key'],
      where: 'id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    final slotId = rows.isEmpty ? '' : rows.first['slot_id'].toString();
    final progKey = rows.isEmpty ? '' : (rows.first['prog_key'] ?? '').toString();
    await db.transaction((txn) async {
      if (slotId.isNotEmpty) {
        await txn.delete(
          'slot_contributions',
          where: 'slot_id = ? AND prog_key = ?',
          whereArgs: [slotId, progKey],
        );
      }
      await txn.update(
        'slot_rows',
        {
          'present': 0,
          'absent': 0,
          'ufm': 0,
          'received': 0,
          'received_from': '',
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [rowId],
      );
    });
    await _touchSlotByRow(rowId);
    CloudSyncService.instance.pushModulesSoon('slots');
  }

  /// Applies a teacher's attendance transfer QR (`CSEXAM|QATTN|1|`) to [slotId]:
  /// aggregates present/absent/UFM per program (class) and sets the matching
  /// rows. Returns a summary of what matched. Setting (not adding) keeps it
  /// idempotent — re-scanning the same teacher's QR is safe.
  Future<SlotApplyResult> applyTeacherQr({
    required String slotId,
    required String rawPayload,
  }) async {
    final decoded = _decodeAttn(rawPayload);
    if (decoded == null) {
      throw const FormatException(
        'Not an attendance transfer QR (expected CSEXAM|QATTN|1|…).',
      );
    }
    final agg = _aggregateByProgram(decoded);
    if (agg.isEmpty) {
      throw const FormatException(
        'This attendance QR has no per-class data to match against the slot.',
      );
    }
    final by = (decoded['by'] ?? '').toString().trim();
    final from = by.isEmpty ? 'Unknown teacher' : by;
    final hall = (decoded['h'] ?? '').toString().trim();
    final db = _requireDb();
    final rows = await loadRows(slotId);
    final byKey = {for (final r in rows) r.progKey: r};
    final matched = <String>[];
    final unmatched = <String>[];
    var rPresent = 0, rAbsent = 0, rUfm = 0;
    final now = DateTime.now().toIso8601String();
    await db.transaction((txn) async {
      for (final entry in agg.entries) {
        final target = byKey[entry.key];
        if (target == null) {
          unmatched.add(entry.value.program);
          continue;
        }
        // A real QR scan supersedes any manual override for this program.
        await txn.delete(
          'slot_contributions',
          where: 'slot_id = ? AND prog_key = ? AND source = ?',
          whereArgs: [slotId, target.progKey, 'Manual entry'],
        );
        // One contribution per teacher+hall. Deterministic id ⇒ the same
        // teacher re-scanning REPLACES their own numbers (idempotent); two
        // different halls for the same class ADD UP.
        await txn.insert('slot_contributions', {
          'id': _stableId('$slotId|${target.progKey}|$from|$hall'),
          'slot_id': slotId,
          'prog_key': target.progKey,
          'source': from,
          'hall': hall,
          'present': entry.value.present,
          'absent': entry.value.absent,
          'ufm': entry.value.ufm,
          'updated_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        await _recomputeRow(txn, slotId, target.progKey, target.id);
        matched.add(target.program);
        rPresent += entry.value.present;
        rAbsent += entry.value.absent;
        rUfm += entry.value.ufm;
      }
      // Log this receipt. Deterministic id per teacher+hall so re-scanning the
      // same teacher updates (not duplicates) their receipt.
      if (matched.isNotEmpty) {
        await txn.insert('slot_receipts', {
          'id': _stableId('$slotId|$from|$hall|receipt'),
          'slot_id': slotId,
          'received_from': from,
          'hall': hall,
          'programs': matched.join(', '),
          'present': rPresent,
          'absent': rAbsent,
          'ufm': rUfm,
          'received_at': now,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
      }
    });
    await _touchSlot(slotId);
    CloudSyncService.instance.pushModulesSoon('slots');
    return SlotApplyResult(matched: matched, unmatched: unmatched, from: from);
  }

  Future<List<SlotReceipt>> loadReceipts(String slotId) async {
    final rows = await _requireDb().query(
      'slot_receipts',
      where: 'slot_id = ?',
      whereArgs: [slotId],
      orderBy: 'received_at DESC',
    );
    return rows.map(SlotReceipt.fromMap).toList(growable: false);
  }

  /// Rebuilds a program row's present/absent/UFM as the SUM of its
  /// contributions (so split halls add up), listing every source.
  Future<void> _recomputeRow(
    DatabaseExecutor txn,
    String slotId,
    String progKey,
    String rowId,
  ) async {
    final rows = await txn.query(
      'slot_contributions',
      where: 'slot_id = ? AND prog_key = ?',
      whereArgs: [slotId, progKey],
    );
    var present = 0, absent = 0, ufm = 0;
    final sources = <String>{};
    for (final r in rows) {
      present += int.tryParse('${r['present'] ?? 0}') ?? 0;
      absent += int.tryParse('${r['absent'] ?? 0}') ?? 0;
      ufm += int.tryParse('${r['ufm'] ?? 0}') ?? 0;
      final s = (r['source'] ?? '').toString().trim();
      if (s.isNotEmpty) sources.add(s);
    }
    await txn.update(
      'slot_rows',
      {
        'present': present,
        'absent': absent,
        'ufm': ufm,
        'received': rows.isEmpty ? 0 : 1,
        'received_from': sources.join(', '),
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [rowId],
    );
  }

  Future<void> _touchSlot(String slotId) async {
    await _requireDb().update(
      'slots',
      {'updated_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [slotId],
    );
  }

  Future<void> _touchSlotByRow(String rowId) async {
    final rows = await _requireDb().query(
      'slot_rows',
      columns: ['slot_id'],
      where: 'id = ?',
      whereArgs: [rowId],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      await _touchSlot(rows.first['slot_id'].toString());
    }
  }

  // --------------------------------------------------------------- loading

  Future<List<SlotSummary>> loadSlots() async {
    final slots = await _requireDb().query('slots', orderBy: 'updated_at DESC');
    final out = <SlotSummary>[];
    for (final s in slots) {
      out.add(await _summaryFromRow(s));
    }
    return out;
  }

  Future<SlotSummary?> loadSlot(String slotId) async {
    final slots = await _requireDb().query(
      'slots',
      where: 'id = ?',
      whereArgs: [slotId],
      limit: 1,
    );
    if (slots.isEmpty) return null;
    return _summaryFromRow(slots.first);
  }

  Future<SlotSummary> _summaryFromRow(Map<String, Object?> s) async {
    final slotId = s['id'].toString();
    final rows = await loadRows(slotId);
    var present = 0, absent = 0, ufm = 0, received = 0;
    for (final r in rows) {
      present += r.present;
      absent += r.absent;
      ufm += r.ufm;
      if (r.received) received += 1;
    }
    return SlotSummary(
      id: slotId,
      examDate: (s['exam_date'] ?? '').toString(),
      shift: (s['shift'] ?? '').toString(),
      expected: int.tryParse('${s['expected'] ?? 0}') ?? 0,
      usedHalls: int.tryParse('${s['used_halls'] ?? 0}') ?? 0,
      programs: rows.length,
      received: received,
      totalPresent: present,
      totalAbsent: absent,
      totalUfm: ufm,
      updatedAt: DateTime.tryParse((s['updated_at'] ?? '').toString()),
    );
  }

  Future<List<SlotRow>> loadRows(String slotId) async {
    final rows = await _requireDb().query(
      'slot_rows',
      where: 'slot_id = ?',
      whereArgs: [slotId],
      orderBy: 'program COLLATE NOCASE, subject COLLATE NOCASE',
    );
    return rows.map(SlotRow.fromMap).toList(growable: false);
  }

  /// Every program row across EVERY slot/day — for the consolidated
  /// "Complete Attendance" view (all days & slots in one place).
  Future<List<SlotRow>> loadAllRows() async {
    final rows = await _requireDb().query(
      'slot_rows',
      orderBy: 'program COLLATE NOCASE, subject COLLATE NOCASE',
    );
    return rows.map(SlotRow.fromMap).toList(growable: false);
  }

  /// Deletes a slot and returns (table, id) tombstone items so the caller can
  /// push them to the cloud — otherwise other devices re-push the slot back
  /// and it "reappears" (same bug class as the FYP group deletes).
  Future<List<(String, String)>> deleteSlot(String slotId) async {
    final db = _requireDb();
    final items = <(String, String)>[('slots', slotId)];
    Future<void> collect(String table, String col) async {
      final rows = await db.query(
        table,
        columns: const ['id'],
        where: '$col = ?',
        whereArgs: [slotId],
      );
      for (final r in rows) {
        final id = (r['id'] ?? '').toString();
        if (id.isNotEmpty) items.add((table, id));
      }
    }

    await collect('slot_rows', 'slot_id');
    await collect('slot_receipts', 'slot_id');
    await collect('slot_contributions', 'slot_id');
    await db.delete('slot_rows', where: 'slot_id = ?', whereArgs: [slotId]);
    await db.delete('slot_receipts', where: 'slot_id = ?', whereArgs: [slotId]);
    await db.delete(
      'slot_contributions',
      where: 'slot_id = ?',
      whereArgs: [slotId],
    );
    await db.delete('slots', where: 'id = ?', whereArgs: [slotId]);
    return items;
  }

  /// Clears everything and returns tombstone items for the cloud (see
  /// [deleteSlot]).
  Future<List<(String, String)>> clearAll() async {
    final db = _requireDb();
    final items = <(String, String)>[];
    for (final table in const [
      'slots',
      'slot_rows',
      'slot_receipts',
      'slot_contributions',
    ]) {
      final rows = await db.query(table, columns: const ['id']);
      for (final r in rows) {
        final id = (r['id'] ?? '').toString();
        if (id.isNotEmpty) items.add((table, id));
      }
    }
    await db.delete('slot_rows');
    await db.delete('slot_receipts');
    await db.delete('slot_contributions');
    await db.delete('slots');
    return items;
  }

  /// Applies a remote tombstone: removes one row by id (any slot table).
  Future<void> deleteRowById(String table, String id) async {
    const allowed = {'slots', 'slot_rows', 'slot_receipts', 'slot_contributions'};
    if (!allowed.contains(table) || id.isEmpty) return;
    await _requireDb().delete(table, where: 'id = ?', whereArgs: [id]);
  }

  // ---------------------------------------------------- cloud sync
  /// Merges rows of one table pulled from the cloud (keep-newest), then — for
  /// contributions — recomputes the affected program rows so split-hall totals
  /// stay correct on every synced device.
  Future<void> applyCloudRows(
    String table,
    List<Map<String, Object?>> rows,
  ) async {
    const allowed = {'slots', 'slot_rows', 'slot_receipts', 'slot_contributions'};
    if (!allowed.contains(table) || rows.isEmpty) return;
    final db = _requireDb();
    await TableSync.merge(
      db,
      table,
      rows,
      tsOf: table == 'slot_receipts'
          ? null // append-only log
          : (r) => TableSync.ts(r, 'updated_at'),
    );
    if (table == 'slot_contributions') {
      final pairs = <String>{
        for (final r in rows)
          '${r['slot_id'] ?? ''}|${r['prog_key'] ?? ''}',
      }..removeWhere((e) => e.startsWith('|') || e.endsWith('|'));
      await db.transaction((txn) async {
        for (final p in pairs) {
          final parts = p.split('|');
          await _recomputeRow(
            txn,
            parts[0],
            parts[1],
            _stableId('${parts[0]}|${parts[1]}'),
          );
        }
      });
    }
  }

  // ---------------------------------------------------- admin data-share
  Future<Map<String, dynamic>> exportBundle() async {
    final db = _requireDb();
    return {
      'slots': await TableSync.dump(db, 'slots'),
      'slot_rows': await TableSync.dump(db, 'slot_rows'),
      'slot_receipts': await TableSync.dump(db, 'slot_receipts'),
      'slot_contributions': await TableSync.dump(db, 'slot_contributions'),
    };
  }

  Future<(int, int)> importBundle(Map<String, dynamic> data) async {
    final db = _requireDb();
    final s = await TableSync.merge(
      db,
      'slots',
      (data['slots'] as List?) ?? const [],
      tsOf: (r) => TableSync.ts(r, 'updated_at'),
    );
    final r = await TableSync.merge(
      db,
      'slot_rows',
      (data['slot_rows'] as List?) ?? const [],
      tsOf: (row) => TableSync.ts(row, 'updated_at'),
    );
    // Contributions are keyed by (slot·program·source·hall): the same teacher
    // dedups, different teachers/halls survive as separate rows.
    final c = await TableSync.merge(
      db,
      'slot_contributions',
      (data['slot_contributions'] as List?) ?? const [],
      tsOf: (row) => TableSync.ts(row, 'updated_at'),
    );
    // Receipts are an append-only log — add new ones, never overwrite.
    final rc = await TableSync.merge(
      db,
      'slot_receipts',
      (data['slot_receipts'] as List?) ?? const [],
    );
    // Recompute every program row from the MERGED contributions so numbers
    // collected by both admins add up (don't trust the imported row totals).
    final keys = await db.rawQuery(
      'SELECT DISTINCT slot_id, prog_key FROM slot_contributions',
    );
    await db.transaction((txn) async {
      for (final k in keys) {
        final slotId = (k['slot_id'] ?? '').toString();
        final progKey = (k['prog_key'] ?? '').toString();
        await _recomputeRow(
          txn,
          slotId,
          progKey,
          _stableId('$slotId|$progKey'),
        );
      }
    });
    return (s.$1 + r.$1 + c.$1 + rc.$1, s.$2 + r.$2 + c.$2 + rc.$2);
  }

  // --------------------------------------------------------------- parsing

  /// Decodes a `CSEXAM|QSLOT|1|` QR into the slot overview, or null.
  static SlotOverview? parseSlotOverview(String rawPayload) {
    final raw = rawPayload.trim();
    if (!raw.startsWith(_slotQrPrefix)) return null;
    final data = _inflate(raw.substring(_slotQrPrefix.length));
    if (data == null) return null;
    if ((data['t'] ?? '').toString() != 'slot_overview') return null;
    final rowsRaw = data['r'];
    final rows = <SlotOverviewRow>[];
    if (rowsRaw is List) {
      for (final r in rowsRaw) {
        if (r is! List || r.isEmpty) continue;
        final program = r[0].toString().trim();
        final subject = r.length > 1 ? r[1].toString().trim() : '';
        final faculty = r.length > 2 ? r[2].toString().trim() : '';
        final halls = r.length > 3 ? r[3].toString().trim() : '';
        final expected = r.length > 4 ? _int(r[4]) : 0;
        rows.add(SlotOverviewRow(
          program: program,
          subject: subject,
          faculty: faculty,
          halls: halls,
          expected: expected,
          progKey: _progKey(program),
        ));
      }
    }
    if (rows.isEmpty) return null;
    return SlotOverview(
      examDate: (data['d'] ?? '').toString(),
      shift: (data['s'] ?? '').toString(),
      totalExpected: _int(data['n']),
      usedHalls: _int(data['hu']),
      rows: rows,
    );
  }

  /// Aggregates a decoded QATTN payload into per-program present/absent/UFM.
  static Map<String, _ProgAgg> _aggregateByProgram(
    Map<String, Object?> decoded,
  ) {
    final scope = (decoded['c'] ?? '').toString().trim();
    final students = decoded['st'];
    final agg = <String, _ProgAgg>{};
    final rollProgram = <String, String>{};
    if (students is List) {
      for (final row in students) {
        if (row is! List || row.isEmpty) continue;
        final roll = row[0].toString().trim();
        final present = row.length > 1 && row[1].toString() == 'P';
        var program = row.length > 3 ? row[3].toString().trim() : '';
        if (program.isEmpty) program = scope;
        if (program.isEmpty) continue;
        final key = _progKey(program);
        rollProgram[roll] = key;
        final a = agg.putIfAbsent(key, () => _ProgAgg(program));
        if (present) {
          a.present += 1;
        } else {
          a.absent += 1;
        }
      }
    }
    // UFM cases: map each roll back to its program.
    final ufm = decoded['u'];
    if (ufm is List) {
      for (final c in ufm) {
        if (c is! List || c.isEmpty) continue;
        final roll = c[0].toString().trim();
        final key = rollProgram[roll];
        if (key == null) continue;
        agg[key]?.ufm += 1;
      }
    }
    return agg;
  }

  static Map<dynamic, dynamic>? _inflate(String body) {
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

  static Map<String, Object?>? _decodeAttn(String rawPayload) {
    final raw = rawPayload.trim();
    if (!raw.startsWith(_attnQrPrefix)) return null;
    final data = _inflate(raw.substring(_attnQrPrefix.length));
    return data?.cast<String, Object?>();
  }

  /// Normalised program key for matching ("BSCS  4A" -> "BSCS 4A").
  static String _progKey(String program) =>
      program.toUpperCase().replaceAll(RegExp(r'\s+'), ' ').trim();

  static int _int(Object? value) => int.tryParse('${value ?? 0}') ?? 0;

  static String _stableId(String value) {
    var hash = 0x811c9dc5;
    for (final unit in value.toUpperCase().codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return 'SC${hash.toRadixString(16).padLeft(8, '0')}';
  }
}

class _ProgAgg {
  _ProgAgg(this.program);
  final String program;
  int present = 0;
  int absent = 0;
  int ufm = 0;
}

class SlotOverview {
  const SlotOverview({
    required this.examDate,
    required this.shift,
    required this.totalExpected,
    required this.usedHalls,
    required this.rows,
  });

  final String examDate;
  final String shift;
  final int totalExpected;
  final int usedHalls;
  final List<SlotOverviewRow> rows;
}

class SlotOverviewRow {
  const SlotOverviewRow({
    required this.program,
    required this.subject,
    required this.faculty,
    required this.halls,
    required this.expected,
    required this.progKey,
  });

  final String program;
  final String subject;
  final String faculty;
  final String halls;
  final int expected;
  final String progKey;
}

class SlotRow {
  const SlotRow({
    required this.id,
    required this.slotId,
    required this.progKey,
    required this.program,
    required this.subject,
    required this.faculty,
    required this.halls,
    required this.expected,
    required this.present,
    required this.absent,
    required this.ufm,
    required this.received,
    this.receivedFrom = '',
    this.updatedAt,
  });

  factory SlotRow.fromMap(Map<String, Object?> map) {
    return SlotRow(
      id: (map['id'] ?? '').toString(),
      slotId: (map['slot_id'] ?? '').toString(),
      progKey: (map['prog_key'] ?? '').toString(),
      program: (map['program'] ?? '').toString(),
      subject: (map['subject'] ?? '').toString(),
      faculty: (map['faculty'] ?? '').toString(),
      halls: (map['halls'] ?? '').toString(),
      expected: int.tryParse('${map['expected'] ?? 0}') ?? 0,
      present: int.tryParse('${map['present'] ?? 0}') ?? 0,
      absent: int.tryParse('${map['absent'] ?? 0}') ?? 0,
      ufm: int.tryParse('${map['ufm'] ?? 0}') ?? 0,
      received: (int.tryParse('${map['received'] ?? 0}') ?? 0) == 1,
      receivedFrom: (map['received_from'] ?? '').toString(),
      updatedAt: DateTime.tryParse((map['updated_at'] ?? '').toString()),
    );
  }

  final String id;
  final String slotId;
  final String progKey;
  final String program;
  final String subject;
  final String faculty;
  final String halls;
  final int expected;
  final int present;
  final int absent;
  final int ufm;
  final bool received;
  final String receivedFrom;
  final DateTime? updatedAt;

  int get accounted => present + absent;
}

/// One logged receipt: which invigilator handed over which programs, and when.
class SlotReceipt {
  const SlotReceipt({
    required this.id,
    required this.slotId,
    required this.receivedFrom,
    required this.hall,
    required this.programs,
    required this.present,
    required this.absent,
    required this.ufm,
    this.receivedAt,
  });

  factory SlotReceipt.fromMap(Map<String, Object?> map) {
    return SlotReceipt(
      id: (map['id'] ?? '').toString(),
      slotId: (map['slot_id'] ?? '').toString(),
      receivedFrom: (map['received_from'] ?? '').toString(),
      hall: (map['hall'] ?? '').toString(),
      programs: (map['programs'] ?? '').toString(),
      present: int.tryParse('${map['present'] ?? 0}') ?? 0,
      absent: int.tryParse('${map['absent'] ?? 0}') ?? 0,
      ufm: int.tryParse('${map['ufm'] ?? 0}') ?? 0,
      receivedAt: DateTime.tryParse((map['received_at'] ?? '').toString()),
    );
  }

  final String id;
  final String slotId;
  final String receivedFrom;
  final String hall;
  final String programs;
  final int present;
  final int absent;
  final int ufm;
  final DateTime? receivedAt;
}

class SlotSummary {
  const SlotSummary({
    required this.id,
    required this.examDate,
    required this.shift,
    required this.expected,
    required this.usedHalls,
    required this.programs,
    required this.received,
    required this.totalPresent,
    required this.totalAbsent,
    required this.totalUfm,
    this.updatedAt,
  });

  final String id;
  final String examDate;
  final String shift;
  final int expected;
  final int usedHalls;
  final int programs;
  final int received;
  final int totalPresent;
  final int totalAbsent;
  final int totalUfm;
  final DateTime? updatedAt;

  String get title => '$examDate  •  $shift shift';
}

class SlotApplyResult {
  const SlotApplyResult({
    required this.matched,
    required this.unmatched,
    this.from = '',
  });

  final List<String> matched;
  final List<String> unmatched;
  final String from;

  String get message {
    final src = from.isEmpty ? '' : ' from $from';
    final m = 'Received ${matched.length} program(s)$src';
    if (unmatched.isEmpty) return '$m.';
    return '$m. ${unmatched.length} not in this slot: '
        '${unmatched.take(3).join(', ')}'
        '${unmatched.length > 3 ? '…' : ''}';
  }
}
