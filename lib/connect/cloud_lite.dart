import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import '../services/firebase_paths.dart';

/// Minimal Firestore transport shared by the AUST Connect and AUST Event
/// modules. Each record is one doc (doc id = record id, so writes are
/// idempotent and can never duplicate). These collections are LOW frequency
/// (a complaint / file / event now and then), so always-on listeners are the
/// right call for the "live" behaviour — they only re-read on real changes,
/// unlike the exam tables that caused the quota crunch.
class CloudLite {
  CloudLite._();

  static bool get available => Firebase.apps.isNotEmpty;

  /// Upserts one record. Silent no-op offline (Firestore queues the write and
  /// flushes it when the network returns).
  static Future<void> push(
    String collection,
    String id,
    Map<String, Object?> data,
  ) async {
    if (!available || id.trim().isEmpty) return;
    try {
      // Stamp the client build so the Firestore rules can reject writes from
      // old / non-current APKs (same guard the FYP sync uses).
      final payload = Map<String, dynamic>.from(data)
        ..addAll(FirebasePaths.clientWriteMeta());
      await FirebaseFirestore.instance
          .collection(collection)
          .doc(id)
          .set(payload, SetOptions(merge: true));
    } catch (e) {
      debugPrint('CloudLite push $collection/$id failed: $e');
    }
  }

  /// Live listener: delivers changed docs (id injected) as they arrive.
  static StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? listen(
    String collection,
    void Function(List<Map<String, dynamic>> rows) onRows,
  ) {
    if (!available) return null;
    return FirebaseFirestore.instance
        .collection(collection)
        .snapshots()
        .listen(
          (snap) {
            final rows = <Map<String, dynamic>>[];
            for (final c in snap.docChanges) {
              if (c.type == DocumentChangeType.removed) continue;
              final d = c.doc.data();
              if (d != null) {
                rows.add(
                  Map<String, dynamic>.from(d)
                    ..putIfAbsent('id', () => c.doc.id),
                );
              }
            }
            if (rows.isNotEmpty) onRows(rows);
          },
          onError: (Object e) => debugPrint('CloudLite listen $collection: $e'),
        );
  }
}
