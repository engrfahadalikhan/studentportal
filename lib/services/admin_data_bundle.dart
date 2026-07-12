import 'dart:convert';

import 'package:sqflite/sqflite.dart';

/// Generic "dump a table" / "merge rows into a table (keep newest)" helpers used
/// to move whole data stores between the two admin phones offline.
class TableSync {
  /// Every row of [table] as plain maps.
  static Future<List<Map<String, Object?>>> dump(
    DatabaseExecutor db,
    String table,
  ) async {
    final rows = await db.query(table);
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  /// Merges [rows] into [table] by primary key [pk].
  ///
  /// - A row whose id is not present is inserted.
  /// - A row whose id IS present is replaced only when [tsOf] says the incoming
  ///   copy is newer (keep-newest). If [tsOf] is null the existing row is kept
  ///   (append-only / immutable tables).
  ///
  /// Returns (added, updated).
  static Future<(int, int)> merge(
    DatabaseExecutor db,
    String table,
    List<dynamic> rows, {
    String pk = 'id',
    DateTime? Function(Map<String, Object?>)? tsOf,
  }) async {
    var added = 0;
    var updated = 0;
    for (final raw in rows) {
      if (raw is! Map) continue;
      final row = <String, Object?>{
        for (final e in raw.entries) e.key.toString(): e.value,
      };
      final id = row[pk];
      if (id == null) continue;
      final existing = await db.query(
        table,
        where: '$pk = ?',
        whereArgs: [id],
        limit: 1,
      );
      if (existing.isEmpty) {
        await db.insert(
          table,
          row,
          conflictAlgorithm: ConflictAlgorithm.replace,
        );
        added++;
      } else if (tsOf != null) {
        final incoming = tsOf(row);
        final current = tsOf(existing.first);
        if (incoming != null &&
            (current == null || incoming.isAfter(current))) {
          await db.insert(
            table,
            row,
            conflictAlgorithm: ConflictAlgorithm.replace,
          );
          updated++;
        }
      }
    }
    return (added, updated);
  }

  static DateTime? ts(Map<String, Object?> row, String col) =>
      DateTime.tryParse((row[col] ?? '').toString());

  /// First non-empty timestamp among [cols] (e.g. returned_at ?? issued_at).
  static DateTime? tsAny(Map<String, Object?> row, List<String> cols) {
    for (final c in cols) {
      final d = DateTime.tryParse((row[c] ?? '').toString());
      if (d != null) return d;
    }
    return null;
  }
}

/// The modules an admin can pick to share.
enum AdminModule { attendance, assessments, ufm, answerSheets, slots }

extension AdminModuleX on AdminModule {
  String get key => switch (this) {
    AdminModule.attendance => 'attendance',
    AdminModule.assessments => 'assessments',
    AdminModule.ufm => 'ufm',
    AdminModule.answerSheets => 'answerSheets',
    AdminModule.slots => 'slots',
  };

  String get label => switch (this) {
    AdminModule.attendance => 'Attendance scans',
    AdminModule.assessments => 'Assessments + marks',
    AdminModule.ufm => 'UFM cases + exam sheets',
    AdminModule.answerSheets => 'Answer-sheet tracker',
    AdminModule.slots => 'Slot collection',
  };
}

/// Per-module result of an import (added / updated record counts).
class ModuleImportResult {
  const ModuleImportResult(this.module, this.added, this.updated);
  final AdminModule module;
  final int added;
  final int updated;
}

/// The header + parsed modules of a received bundle.
class ParsedBundle {
  const ParsedBundle({
    required this.sharedBy,
    required this.sharedAt,
    required this.modules,
    required this.raw,
  });

  final String sharedBy;
  final DateTime? sharedAt;
  final Set<AdminModule> modules;
  final Map<String, dynamic> raw;
}

/// Builds and parses the offline admin-to-admin data bundle. Format:
/// ```
/// { "fmt":"AUST-ADMIN-BUNDLE", "v":1, "sharedBy":"...", "sharedAt":"...",
///   "modules": { "attendance": {...}, "assessments": {...}, ... } }
/// ```
/// The payload is plain JSON in v1 (the format has an `enc` slot reserved so a
/// password lock can be added later without breaking older files).
class AdminDataBundle {
  static const String formatTag = 'AUST-ADMIN-BUNDLE';
  static const int formatVersion = 1;

  static String encode({
    required String sharedBy,
    required Map<String, dynamic> modules,
  }) {
    final map = <String, dynamic>{
      'fmt': formatTag,
      'v': formatVersion,
      'enc': false,
      'sharedBy': sharedBy,
      'sharedAt': DateTime.now().toIso8601String(),
      'modules': modules,
    };
    return const JsonEncoder.withIndent('  ').convert(map);
  }

  /// Parses a bundle file's text. Throws [FormatException] if it isn't one.
  static ParsedBundle parse(String text) {
    final decoded = jsonDecode(text);
    if (decoded is! Map || decoded['fmt'] != formatTag) {
      throw const FormatException('This is not an AUST admin data file.');
    }
    final modulesRaw = decoded['modules'];
    final present = <AdminModule>{};
    if (modulesRaw is Map) {
      for (final m in AdminModule.values) {
        if (modulesRaw[m.key] != null) present.add(m);
      }
    }
    return ParsedBundle(
      sharedBy: (decoded['sharedBy'] ?? 'Unknown admin').toString(),
      sharedAt: DateTime.tryParse((decoded['sharedAt'] ?? '').toString()),
      modules: present,
      raw: decoded.cast<String, dynamic>(),
    );
  }
}
