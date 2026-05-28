import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';

import '../models/seating_plan_entry.dart';

class SeatingPlanService {
  SeatingPlanService({FirebaseDatabase? database})
    : _database =
          database ??
          FirebaseDatabase.instanceFor(
            app: Firebase.app(),
            databaseURL: 'https://fahad1-bbd65-default-rtdb.firebaseio.com',
          );

  final FirebaseDatabase _database;
  static const List<String> _candidatePaths = ['root/seating', 'seating'];

  Future<List<SeatingPlanEntry>> findByRollNo(String rollNo) async {
    final normalizedRollNo = rollNo.trim();
    final rollAsInt = int.tryParse(normalizedRollNo);
    final searchValues = <Object>[
      normalizedRollNo,
      if (rollAsInt != null) rollAsInt,
    ];

    for (final path in _candidatePaths) {
      for (final value in searchValues) {
        try {
          final snapshot = await _database
              .ref(path)
              .orderByChild('RollNo')
              .equalTo(value)
              .get();
          final records = _extract(snapshot.value);
          if (records.isNotEmpty) {
            return records;
          }
        } on FirebaseException catch (error) {
          if (_isPermissionDenied(error)) {
            continue;
          }

          if (!_isMissingIndexError(error)) {
            rethrow;
          }

          final fallback = await _database.ref(path).get();
          final records = _extract(
            fallback.value,
          ).where((entry) => entry.rollNo == normalizedRollNo).toList();
          if (records.isNotEmpty) {
            return records;
          }
        }
      }
    }

    return const [];
  }

  bool _isMissingIndexError(FirebaseException error) {
    final message = error.message?.toLowerCase() ?? '';
    return message.contains('index') && message.contains('rollno');
  }

  bool _isPermissionDenied(FirebaseException error) {
    final message = error.message?.toLowerCase() ?? '';
    return error.code == 'permission-denied' ||
        message.contains('permission denied') ||
        message.contains('access to the specified path is denied');
  }

  List<SeatingPlanEntry> _extract(dynamic value) {
    final rows = <SeatingPlanEntry>[];

    if (value is Map) {
      for (final entry in value.values) {
        if (entry is Map) {
          rows.add(SeatingPlanEntry.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    } else if (value is List) {
      for (final entry in value) {
        if (entry is Map) {
          rows.add(SeatingPlanEntry.fromMap(Map<String, dynamic>.from(entry)));
        }
      }
    }

    return rows;
  }
}
