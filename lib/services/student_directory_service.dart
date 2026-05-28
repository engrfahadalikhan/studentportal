import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/student_directory_summary.dart';
import '../models/student_record.dart';

class StudentDirectoryService {
  StudentDirectoryService({FirebaseDatabase? database})
    : _database =
          database ??
          FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: 'https://fahad1-bbd65-default-rtdb.firebaseio.com',
          );

  final FirebaseDatabase _database;
  String? _matchedPath;

  static const List<String> _candidatePaths = [
    'root/student_data',
    'student_data',
    '',
    'students',
    'Students',
    'studentportal',
    'studentportal/students',
    'Updated_Students',
  ];

  Future<StudentRecord?> findStudentByRollNo(String rollNo) async {
    final normalizedRollNo = rollNo.trim();
    final rollAsInt = int.tryParse(normalizedRollNo);
    final searchValues = <Object>[
      normalizedRollNo,
      if (rollAsInt != null) rollAsInt,
    ];

    for (final path in _prioritizedPaths()) {
      try {
        for (final searchValue in searchValues) {
          final snapshot = await _reference(
            path,
          ).orderByChild('Roll no').equalTo(searchValue).get();

          final rows = _extractRows(snapshot.value);
          if (rows.isNotEmpty) {
            _matchedPath = path;
            return StudentRecord.fromRows(rows);
          }
        }
      } on FirebaseException catch (error) {
        if (_isPermissionDenied(error)) {
          continue;
        }

        if (!_isMissingIndexError(error)) {
          rethrow;
        }

        final fallbackRows = await _findByFullScan(path, normalizedRollNo);
        if (fallbackRows.isNotEmpty) {
          _matchedPath = path;
          return StudentRecord.fromRows(fallbackRows);
        }
      }
    }

    return null;
  }

  Future<StudentDirectorySummary> loadSummary() async {
    for (final path in _prioritizedPaths()) {
      DataSnapshot snapshot;
      try {
        snapshot = await _reference(path).get();
      } on FirebaseException catch (error) {
        if (_isPermissionDenied(error)) {
          continue;
        }
        rethrow;
      }
      final rows = _extractRows(snapshot.value);
      if (rows.isEmpty) {
        continue;
      }

      final uniqueRolls = <String>{};
      for (final row in rows) {
        final rollNo = row['Roll no']?.toString().trim();
        if (rollNo != null && rollNo.isNotEmpty) {
          uniqueRolls.add(rollNo);
        }
      }

      _matchedPath = path;
      return StudentDirectorySummary(
        studentCount: uniqueRolls.length,
        courseRegistrationCount: rows.length,
        matchedPath: path.isEmpty ? '/' : path,
      );
    }

    return const StudentDirectorySummary(
      studentCount: 0,
      courseRegistrationCount: 0,
      matchedPath: 'Not found',
    );
  }

  Future<List<StudentRecord>> searchStudents(
    String query, {
    int limit = 25,
  }) async {
    final normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) {
      return const [];
    }

    for (final path in _prioritizedPaths()) {
      DataSnapshot snapshot;
      try {
        snapshot = await _reference(path).get();
      } on FirebaseException catch (error) {
        if (_isPermissionDenied(error)) {
          continue;
        }
        rethrow;
      }

      final rows = _extractRows(snapshot.value);
      if (rows.isEmpty) {
        continue;
      }

      final groupedRows = <String, List<Map<String, dynamic>>>{};
      for (final row in rows) {
        final rollNo = _stringValue(row, const [
          'Roll no',
          'roll_no',
          'rollNo',
        ]);
        final name = _stringValue(row, const [
          'Student_name',
          'student_name',
          'name',
        ]);
        final matchesRoll = rollNo.toLowerCase() == normalizedQuery;
        final matchesName = name.toLowerCase().contains(normalizedQuery);

        if (!matchesRoll && !matchesName) {
          continue;
        }

        final key = rollNo.isEmpty ? '${groupedRows.length}' : rollNo;
        groupedRows.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
      }

      if (groupedRows.isNotEmpty) {
        _matchedPath = path;
        return groupedRows.values
            .take(limit)
            .map(StudentRecord.fromRows)
            .toList(growable: false);
      }
    }

    return const [];
  }

  Iterable<String> _prioritizedPaths() sync* {
    if (_matchedPath != null) {
      yield _matchedPath!;
    }

    for (final path in _candidatePaths) {
      if (path != _matchedPath) {
        yield path;
      }
    }
  }

  DatabaseReference _reference(String path) {
    return path.isEmpty ? _database.ref() : _database.ref(path);
  }

  Future<List<Map<String, dynamic>>> _findByFullScan(
    String path,
    String rollNo,
  ) async {
    final snapshot = await _reference(path).get();
    final rows = _extractRows(snapshot.value);
    return rows
        .where((row) => row['Roll no']?.toString().trim() == rollNo)
        .toList();
  }

  bool _isMissingIndexError(FirebaseException error) {
    final message = error.message?.toLowerCase() ?? '';
    return message.contains('index') && message.contains('roll no');
  }

  bool _isPermissionDenied(FirebaseException error) {
    final message = error.message?.toLowerCase() ?? '';
    return error.code == 'permission-denied' ||
        message.contains('permission denied') ||
        message.contains('access to the specified path is denied');
  }

  List<Map<String, dynamic>> _extractRows(dynamic value) {
    final rows = <Map<String, dynamic>>[];

    if (value is Map) {
      for (final entry in value.values) {
        if (entry is Map) {
          final row = Map<String, dynamic>.from(entry);
          if (row.containsKey('Roll no')) {
            rows.add(row);
          }
        }
      }
    } else if (value is List) {
      for (final entry in value) {
        if (entry is Map) {
          final row = Map<String, dynamic>.from(entry);
          if (row.containsKey('Roll no')) {
            rows.add(row);
          }
        }
      }
    }

    return rows;
  }

  String _stringValue(Map<String, dynamic> row, List<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value == null) {
        continue;
      }

      final text = value.toString().trim();
      if (text.isNotEmpty && text.toLowerCase() != 'null') {
        return text;
      }
    }

    return '';
  }
}
