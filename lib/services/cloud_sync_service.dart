import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../attendance/qr_attendance_section.dart';
import '../fyp/fyp_codec.dart';
import '../fyp/fyp_group_models.dart';
import '../fyp/fyp_models.dart';
import '../fyp/fyp_repository.dart';
import 'answer_sheet_repository.dart';
import 'app_repository.dart';
import 'login_store.dart';
import 'firebase_paths.dart';
import 'slot_collection_repository.dart';
import 'teacher_dashboard_database.dart';

/// Automatic cloud sync over Firebase Cloud Firestore.
///
/// Coverage (one collection per table, doc id = the row's stable id, so
/// re-uploads overwrite themselves and duplicates are impossible):
///  - QR attendance scans                 → `attendance_scans`
///  - Exam attendance (sheets/records/UFM/students/halls)
///                                        → `exam_*` collections
///  - Assessments + marks                 → `cloud_assignments` / `cloud_submissions`
///  - Answer-sheet tracker                → `cloud_paper_batches`
///  - Per-slot collection                 → `slot_*` collections
///  - Deletions (tombstones)              → `exam_deleted`
///
/// Every teacher/admin device pushes its own data and listens for everyone
/// else's; deletes propagate through tombstones so a removed wrong-scan or a
/// deleted assessment disappears on every device. All writes queue offline.
class CloudSyncService extends ChangeNotifier {
  CloudSyncService._();
  static final CloudSyncService instance = CloudSyncService._();

  /// Temporary quota-protection mode: only FYP workspace data is allowed to
  /// sync. Exam attendance, assignments, answer sheets, slots, and QR
  /// attendance stay local until this is turned off in a later build.
  static const bool _fypOnlySyncMode = true;

  // ---- QR attendance scans.
  static const _collection = 'attendance_scans';
  static const _kFullPushDone = 'cloud_full_push_done_v1';
  final AttendanceRepository _repo = AttendanceRepository();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;
  bool _started = false;
  bool _busy = false;

  // ---- Exam-attendance store (Exam Attendance / Summary — teacher dashboard).
  static const Map<String, String> _examCollections = {
    'students': 'exam_students',
    'exam_halls': 'exam_halls',
    'exam_attendance_sheets': 'exam_sheets',
    'exam_attendance_records': 'exam_records',
    'exam_ufm_cases': 'exam_ufm',
  };

  /// Keep-newest timestamp column per exam table (null = insert-only).
  static const Map<String, String?> _examTsCols = {
    'students': null,
    'exam_halls': 'created_at',
    'exam_attendance_sheets': 'last_updated_at',
    'exam_attendance_records': 'marked_at',
    'exam_ufm_cases': 'created_at',
  };
  static const _kExamLastPush = 'cloud_exam_last_push_v1';
  final TeacherDashboardDatabase _dash = TeacherDashboardDatabase.instance;
  final List<StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>
  _examSubs = [];
  bool _examStarted = false;
  bool _busyExam = false;

  // ---- Deletions (tombstones): doc id = deleted row id, {'t': table}.
  static const _deletedCollection = 'exam_deleted';
  static const Map<String, String> _tableToColl = {
    'exam_attendance_records': 'exam_records',
    'exam_ufm_cases': 'exam_ufm',
    'exam_attendance_sheets': 'exam_sheets',
    'teacher_assignments': 'cloud_assignments',
    'student_submissions': 'cloud_submissions',
    // Slot collection + answer-sheet tracker: deletes must propagate too.
    'slots': 'slot_slots',
    'slot_rows': 'slot_rows',
    'slot_receipts': 'slot_receipts',
    'slot_contributions': 'slot_contributions',
    'paper_batches': 'cloud_paper_batches',
  };
  static const Set<String> _slotTombstoneTables = {
    'slots',
    'slot_rows',
    'slot_receipts',
    'slot_contributions',
  };
  final Set<String> _deletedIds = {};

  // ---- Personal login passwords (overrides) sync across devices.
  static const _credentialsCollection = 'cloud_credentials';
  bool _credsStarted = false;

  // ---- Other modules (assessments+marks, answer sheets, slot collection).
  final AnswerSheetRepository _ansRepo = AnswerSheetRepository();
  final SlotCollectionRepository _slotRepo = SlotCollectionRepository();

  /// Live repository so merged assessments/marks show immediately.
  AppRepository? repository;
  final Set<String> _dirtyModules = {};
  Timer? _modulesTimer;
  bool _busyModules = false;

  /// Human-readable status for the Data Share screen.
  String status = 'Off';
  int uploadedTotal = 0;
  int receivedTotal = 0;
  DateTime? lastSyncAt;

  bool get isRunning => _started;

  /// Starts auto-sync (call after a FACULTY or ADMIN login). Safe to call
  /// repeatedly; does nothing on platforms where Firebase isn't initialized.
  Future<void> start({AppRepository? repository}) async {
    if (repository != null) this.repository = repository;
    if (_started) {
      return;
    }
    if (Firebase.apps.isEmpty) {
      status = 'Unavailable on this device';
      notifyListeners();
      return;
    }
    _started = true;
    status = 'Starting…';
    notifyListeners();
    try {
      await _repo.open();
      if (!_fypOnlySyncMode && _sub != null) {
        // Live pull: receive everyone's scans (Firestore only sends deltas
        // after the first snapshot, and its offline cache persists them).
        _sub = FirebasePaths.collection(_collection).snapshots().listen(
          _onCloudChange,
          onError: (Object e) {
            status = 'Waiting for internet…';
            notifyListeners();
          },
        );
      }
      if (!_fypOnlySyncMode) {
        await _startExam();
        await _startModules();
      }
      LoginStore.instance.onOverrideChanged = () =>
          unawaited(pushCredentials());
      // Any FYP group change (create / approve / reject / examiners) pushes.
      FypRepository.instance.onGroupsChanged = () => pushFypNow();
      FypRepository.instance.onPanelsChanged = () => pushFypNow();
      FypRepository.instance.onMeetingsChanged = () => pushFypNow();
      FypRepository.instance.onVivaChanged = () => pushFypNow();
      FypRepository.instance.onEvaluationsChanged = () => pushFypNow();
      FypRepository.instance.onArtifactsChanged = () => pushModulesSoon('fyp');
      status = 'On (on-demand)';
    } catch (e) {
      status = 'Error: $e';
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _sub = null;
    for (final s in _examSubs) {
      await s.cancel();
    }
    _examSubs.clear();
    _modulesTimer?.cancel();
    _dash.onExamDataChanged = null;
    _dash.onExamDataRemoved = null;
    FypRepository.instance.onGroupsChanged = null;
    FypRepository.instance.onPanelsChanged = null;
    FypRepository.instance.onMeetingsChanged = null;
    FypRepository.instance.onVivaChanged = null;
    FypRepository.instance.onEvaluationsChanged = null;
    FypRepository.instance.onArtifactsChanged = null;
    LoginStore.instance.onOverrideChanged = null;
    _started = false;
    _examStarted = false;
    _credsStarted = false;
    _fypOnlyStarted = false;
    status = 'Off';
    notifyListeners();
  }

  // ==================== QR attendance scans =================================

  /// Uploads local scans that haven't reached the cloud yet. The very first
  /// run pushes EVERYTHING this phone holds (so old data arrives too); after
  /// that only new/pending scans go up. Firestore queues writes offline and
  /// delivers them when internet returns.
  Future<void> pushLocalScans() async {
    if (_fypOnlySyncMode) return;
    if (Firebase.apps.isEmpty || _busy) return;
    _busy = true;
    try {
      await _repo.open();
      final prefs = await SharedPreferences.getInstance();
      final fullDone = prefs.getBool(_kFullPushDone) ?? false;
      final scans = fullDone
          ? await _repo.loadPendingScans(limit: 100000)
          : await _repo.loadScans();
      if (scans.isEmpty) {
        if (!fullDone) await prefs.setBool(_kFullPushDone, true);
        return;
      }
      final db = FirebaseFirestore.instance;
      final me = LoginStore.instance.currentUserName.trim();
      // Firestore batches allow max 500 writes.
      for (var i = 0; i < scans.length; i += 400) {
        final chunk = scans.skip(i).take(400).toList();
        final batch = db.batch();
        for (final s in chunk) {
          final data = s.toJson()
            ..['uploaded_by'] = me.isEmpty ? s.deviceName : me
            ..['uploaded_at'] = FieldValue.serverTimestamp()
            ..addAll(FirebasePaths.clientWriteMeta());
          batch.set(
            FirebasePaths.doc(_collection, s.token),
            data,
            SetOptions(merge: true),
          );
        }
        await batch.commit();
        await _repo.markSynced([for (final s in chunk) s.token]);
        uploadedTotal += chunk.length;
        lastSyncAt = DateTime.now();
        notifyListeners();
      }
      await prefs.setBool(_kFullPushDone, true);
      status = 'On (auto)';
    } catch (e) {
      // Offline or rules issue — Firestore retries queued writes by itself.
      debugPrint('Cloud push failed: $e');
      status = 'Waiting for internet…';
    } finally {
      _busy = false;
      notifyListeners();
    }
  }

  /// Applies cloud changes to the local DB (dedup via saveScan-by-token).
  Future<void> _onCloudChange(QuerySnapshot<Map<String, dynamic>> snap) async {
    final incoming = <AttendanceScan>[];
    for (final change in snap.docChanges) {
      if (change.type == DocumentChangeType.removed) continue;
      final data = change.doc.data();
      if (data == null) continue;
      try {
        // Docs were written with AttendanceScan.toJson keys; fromTransferJson
        // reads those long keys and leaves the local row id/synced_at unset.
        // (uploaded_at is a Firestore Timestamp — ignored.)
        incoming.add(AttendanceScan.fromTransferJson(data));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (incoming.isEmpty) return;
    try {
      await _repo.open();
      final result = await _repo.importTransferredScans(incoming);
      // Mark pulled tokens as synced so we don't push them straight back up.
      await _repo.markSynced([for (final s in incoming) s.token]);
      if (result.inserted > 0) {
        receivedTotal += result.inserted;
        lastSyncAt = DateTime.now();
        status = 'On (auto)';
        notifyListeners();
      }
    } catch (e) {
      debugPrint('Cloud pull apply failed: $e');
    }
  }

  // ==================== Exam-attendance store (Summary / sheets) ============
  Future<void> _startExam() async {
    if (_fypOnlySyncMode) return;
    if (_examStarted || Firebase.apps.isEmpty) return;
    _examStarted = true;
    _dash.onExamDataChanged = () => unawaited(pushExamData());
    _dash.onExamDataRemoved = (items) => pushDeletions(items);
    if (status.isNotEmpty) return;
    _examCollections.forEach((table, coll) {
      _examSubs.add(
        FirebasePaths.collection(coll).snapshots().listen(
          (snap) => _onExamChange(table, snap),
          onError: (Object e) {
            status = 'Waiting for internet…';
            notifyListeners();
          },
        ),
      );
    });
    // Tombstones: deletions made on any device are applied here too.
    _examSubs.add(
      FirebasePaths.collection(_deletedCollection).snapshots().listen(
        _onDeletedChange,
        onError: (Object e) {
          status = 'Waiting for internet…';
          notifyListeners();
        },
      ),
    );
    // Push this device's exam data on every later change; propagate deletes.
    _dash.onExamDataChanged = () => unawaited(pushExamData());
    _dash.onExamDataRemoved = (items) => pushDeletions(items);
    await pushExamData();
  }

  Future<void> _onExamChange(
    String table,
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    final rows = <Map<String, Object?>>[];
    for (final c in snap.docChanges) {
      if (c.type == DocumentChangeType.removed) continue;
      final d = c.doc.data();
      if (d == null) continue;
      // Never resurrect a row we know was deleted.
      if (_deletedIds.contains((d['id'] ?? '').toString())) continue;
      rows.add(Map<String, Object?>.from(d));
    }
    if (rows.isEmpty) return;
    try {
      // Keep-newest merge so an older cloud copy never overwrites newer local.
      await _dash.mergeCloudRows(table, rows, tsCol: _examTsCols[table]);
      // Count only attendance records (not students/halls/sheets/ufm) so the
      // number lines up with the Summary's record count.
      if (table == 'exam_attendance_records') receivedTotal += rows.length;
      lastSyncAt = DateTime.now();
      status = 'On (auto)';
      notifyListeners();
    } catch (e) {
      debugPrint('Exam pull $table failed: $e');
    }
  }

  /// Uploads exam-attendance rows changed since the last push (all on first
  /// run). Doc id = row id ⇒ re-uploads overwrite, never duplicate.
  Future<void> pushExamData() async {
    if (_fypOnlySyncMode) return;
    if (Firebase.apps.isEmpty || _busyExam) return;
    _busyExam = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final since = prefs.getString(_kExamLastPush);
      final now = DateTime.now().toIso8601String();
      final db = FirebaseFirestore.instance;

      final sheets = await _dash.examRowsSince(
        'exam_attendance_sheets',
        'last_updated_at',
        since,
      );
      final records =
          (await _dash.examRowsSince(
                'exam_attendance_records',
                'marked_at',
                since,
              ))
              .where((r) => !_deletedIds.contains((r['id'] ?? '').toString()))
              .toList();
      final ufm =
          (await _dash.examRowsSince('exam_ufm_cases', 'created_at', since))
              .where((r) => !_deletedIds.contains((r['id'] ?? '').toString()))
              .toList();
      // Students/halls referenced by the changed rows (all on the first push,
      // so names + halls for pre-existing sheets go up too).
      final studentIds = <String>{
        for (final r in records) (r['student_id'] ?? '').toString(),
        for (final u in ufm) (u['student_id'] ?? '').toString(),
      }..removeWhere((e) => e.isEmpty);
      final hallIds = <String>{
        for (final s in sheets) (s['hall_id'] ?? '').toString(),
      }..removeWhere((e) => e.isEmpty);
      final students = since == null
          ? await _dash.examRowsSince('students', '', null)
          : await _dash.examRowsByIds('students', studentIds);
      final halls = since == null
          ? await _dash.examRowsSince('exam_halls', '', null)
          : await _dash.examRowsByIds('exam_halls', hallIds);

      await _pushRows(db, 'exam_students', students);
      await _pushRows(db, 'exam_halls', halls);
      await _pushRows(db, 'exam_sheets', sheets);
      await _pushRows(db, 'exam_records', records);
      await _pushRows(db, 'exam_ufm', ufm);

      await prefs.setString(_kExamLastPush, now);
      // Count only records so "sent" lines up with the attendance total.
      if (records.isNotEmpty) {
        uploadedTotal += records.length;
        lastSyncAt = DateTime.now();
      }
      status = 'On (auto)';
    } catch (e) {
      debugPrint('Exam push failed: $e');
      status = 'Waiting for internet…';
    } finally {
      _busyExam = false;
      notifyListeners();
    }
  }

  // ==================== Deletions (tombstones) ==============================

  /// Propagates local deletions: removes the main cloud docs and writes
  /// tombstones so every device (even ones currently offline) deletes too.
  void pushDeletions(List<(String, String)> items) {
    for (final (_, id) in items) {
      _deletedIds.add(id);
    }
    if (_fypOnlySyncMode) return;
    if (Firebase.apps.isEmpty || items.isEmpty) return;
    unawaited(() async {
      try {
        final db = FirebaseFirestore.instance;
        final now = DateTime.now().toIso8601String();
        for (var i = 0; i < items.length; i += 200) {
          final chunk = items.skip(i).take(200).toList();
          final batch = db.batch();
          for (final (table, id) in chunk) {
            final coll = _tableToColl[table];
            if (coll == null || id.isEmpty) continue;
            batch.delete(FirebasePaths.doc(coll, id));
            batch.set(FirebasePaths.doc(_deletedCollection, id), {
              't': table,
              'id': id,
              'at': now,
              ...FirebasePaths.clientWriteMeta(),
            });
          }
          await batch.commit();
        }
      } catch (e) {
        debugPrint('Cloud delete push failed: $e');
      }
    }());
  }

  /// Applies tombstones from other devices: delete the row locally too.
  Future<void> _onDeletedChange(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) async {
    for (final c in snap.docChanges) {
      if (c.type == DocumentChangeType.removed) continue;
      final d = c.doc.data();
      if (d == null) continue;
      final table = (d['t'] ?? '').toString();
      final id = (d['id'] ?? '').toString();
      if (table.isEmpty || id.isEmpty) continue;
      _deletedIds.add(id);
      try {
        if (_slotTombstoneTables.contains(table)) {
          await _slotRepo.open();
          await _slotRepo.deleteRowById(table, id);
        } else if (table == 'paper_batches') {
          await _ansRepo.open();
          await _ansRepo.deleteBatch(id);
        } else {
          await _dash.deleteRowById(table, id);
          if (table == 'teacher_assignments' ||
              table == 'student_submissions') {
            repository?.applyCloudRemoval(table, id);
          }
        }
      } catch (e) {
        debugPrint('Tombstone apply failed: $e');
      }
    }
  }

  // ==================== Other modules =======================================

  /// Collections for the smaller modules. Slot tables sync 1:1 by name.
  static const List<String> _slotTables = [
    'slots',
    'slot_rows',
    'slot_receipts',
    'slot_contributions',
  ];
  static String _slotColl(String table) =>
      table == 'slots' ? 'slot_slots' : table;

  Future<void> _startModules() async {
    if (_fypOnlySyncMode) return;
    if (status.isNotEmpty) return;

    void listen(
      String coll,
      Future<void> Function(List<Map<String, Object?>> rows) apply,
    ) {
      _examSubs.add(
        FirebasePaths.collection(coll).snapshots().listen(
          (snap) async {
            final rows = <Map<String, Object?>>[];
            for (final c in snap.docChanges) {
              if (c.type == DocumentChangeType.removed) continue;
              final d = c.doc.data();
              if (d == null) continue;
              if (_deletedIds.contains((d['id'] ?? '').toString())) {
                continue;
              }
              rows.add(Map<String, Object?>.from(d));
            }
            if (rows.isEmpty) return;
            try {
              await apply(rows);
              lastSyncAt = DateTime.now();
              notifyListeners();
            } catch (e) {
              debugPrint('Module pull $coll failed: $e');
            }
          },
          onError: (Object e) {
            status = 'Waiting for internet…';
            notifyListeners();
          },
        ),
      );
    }

    // Assessments + marks → merge into the tables, then refresh the live
    // repository so Marks Lists / courses update immediately.
    listen('cloud_assignments', (rows) async {
      await _dash.mergeCloudRows(
        'teacher_assignments',
        rows,
        tsCol: 'updated_at',
      );
      await repository?.loadPersistedAssessments();
    });
    listen('cloud_submissions', (rows) async {
      await _dash.mergeCloudRows(
        'student_submissions',
        rows,
        tsCol: 'updated_at',
      );
      await repository?.loadPersistedSubmissions();
    });

    // Answer-sheet tracker.
    listen('cloud_paper_batches', (rows) async {
      await _ansRepo.open();
      await _ansRepo.importBundle({'paper_batches': rows});
    });

    // Per-slot collection.
    for (final table in _slotTables) {
      listen(_slotColl(table), (rows) async {
        await _slotRepo.open();
        await _slotRepo.applyCloudRows(table, rows);
      });
    }

    // FYP is pulled on demand from FYP screens, not listened to all day.
  }

  bool _fypListening = false;

  /// FYP groups (allotment workflow): docs carry the group JSON in `data`;
  /// the `_meta` doc carries the coordinator name.
  // ignore: unused_element
  void _listenFypGroups() {
    if (_fypListening || Firebase.apps.isEmpty) return;
    _fypListening = true;
    _examSubs.add(
      FirebasePaths.collection('cloud_fyp_groups').snapshots().listen(
        (snap) {
          _applyFypGroupRows([
            for (final c in snap.docChanges)
              if (c.type != DocumentChangeType.removed && c.doc.data() != null)
                Map<String, dynamic>.from(c.doc.data()!)
                  ..putIfAbsent('id', () => c.doc.id),
          ]);
        },
        onError: (Object e) {
          status = 'Waiting for internet…';
          notifyListeners();
        },
      ),
    );
    // Examiner panels + meetings (docs carry JSON in `data`).
    _examSubs.add(
      FirebasePaths.collection('cloud_fyp_panels').snapshots().listen((snap) {
        _applyFypPanelRows([
          for (final c in snap.docChanges)
            if (c.type != DocumentChangeType.removed && c.doc.data() != null)
              Map<String, dynamic>.from(c.doc.data()!)
                ..putIfAbsent('id', () => c.doc.id),
        ]);
      }, onError: (_) {}),
    );
    _examSubs.add(
      FirebasePaths.collection('cloud_fyp_meetings').snapshots().listen((snap) {
        _applyFypMeetingRows([
          for (final c in snap.docChanges)
            if (c.type != DocumentChangeType.removed && c.doc.data() != null)
              Map<String, dynamic>.from(c.doc.data()!)
                ..putIfAbsent('id', () => c.doc.id),
        ]);
      }, onError: (_) {}),
    );
    _examSubs.add(
      FirebasePaths.collection('cloud_fyp_viva').snapshots().listen((snap) {
        _applyFypVivaRows([
          for (final c in snap.docChanges)
            if (c.type != DocumentChangeType.removed && c.doc.data() != null)
              Map<String, dynamic>.from(c.doc.data()!)
                ..putIfAbsent('id', () => c.doc.id),
        ]);
      }, onError: (_) {}),
    );
    _examSubs.add(
      FirebasePaths.collection('cloud_fyp_evaluations').snapshots().listen((
        snap,
      ) {
        _applyFypEvaluationRows([
          for (final c in snap.docChanges)
            if (c.type != DocumentChangeType.removed && c.doc.data() != null)
              Map<String, dynamic>.from(c.doc.data()!)
                ..putIfAbsent('id', () => c.doc.id),
        ]);
      }, onError: (_) {}),
    );
    for (final kind in FypRepository.artifactKinds) {
      _examSubs.add(
        FirebasePaths.collection('cloud_fyp_$kind').snapshots().listen((snap) {
          _applyFypArtifactRows(kind, [
            for (final c in snap.docChanges)
              if (c.type != DocumentChangeType.removed && c.doc.data() != null)
                Map<String, dynamic>.from(c.doc.data()!)
                  ..putIfAbsent('id', () => c.doc.id),
          ]);
        }, onError: (_) {}),
      );
    }
  }

  DateTime? _lastFypPullAt;
  bool _lastFypPullIncludedEvaluations = false;

  Future<void> pullFypWorkspace({
    bool force = false,
    bool includeEvaluations = true,
  }) async {
    if (Firebase.apps.isEmpty) return;
    status = 'Pulling FYP...';
    notifyListeners();
    try {
      await _pullFypWorkspaceOnce(
        force: force,
        includeEvaluations: includeEvaluations,
      );
      lastSyncAt = DateTime.now();
      if (_started || _fypOnlyStarted) status = 'On (auto)';
    } catch (e) {
      debugPrint('FYP pull failed: $e');
      status = 'Waiting for internet...';
    } finally {
      notifyListeners();
    }
  }

  Future<void> _pullFypWorkspaceOnce({
    bool force = false,
    bool includeEvaluations = true,
  }) async {
    if (Firebase.apps.isEmpty) return;
    final now = DateTime.now();
    if (!force &&
        _lastFypPullAt != null &&
        now.difference(_lastFypPullAt!) < const Duration(seconds: 30) &&
        (!includeEvaluations || _lastFypPullIncludedEvaluations)) {
      return;
    }
    _lastFypPullAt = now;
    _lastFypPullIncludedEvaluations = includeEvaluations;
    final groups = await FirebasePaths.collection('cloud_fyp_groups').get();
    _applyFypGroupRows([
      for (final doc in groups.docs)
        Map<String, dynamic>.from(doc.data())..putIfAbsent('id', () => doc.id),
    ]);
    final panels = await FirebasePaths.collection('cloud_fyp_panels').get();
    _applyFypPanelRows([
      for (final doc in panels.docs)
        Map<String, dynamic>.from(doc.data())..putIfAbsent('id', () => doc.id),
    ]);
    final meetings = await FirebasePaths.collection('cloud_fyp_meetings').get();
    _applyFypMeetingRows([
      for (final doc in meetings.docs)
        Map<String, dynamic>.from(doc.data())..putIfAbsent('id', () => doc.id),
    ]);
    final viva = await FirebasePaths.collection('cloud_fyp_viva').get();
    _applyFypVivaRows([
      for (final doc in viva.docs)
        Map<String, dynamic>.from(doc.data())..putIfAbsent('id', () => doc.id),
    ]);
    if (includeEvaluations) {
      final evals = await FirebasePaths.collection(
        'cloud_fyp_evaluations',
      ).get();
      _applyFypEvaluationRows([
        for (final doc in evals.docs)
          Map<String, dynamic>.from(doc.data())
            ..putIfAbsent('id', () => doc.id),
      ]);
    }
    for (final kind in FypRepository.artifactKinds) {
      final docs = await FirebasePaths.collection('cloud_fyp_$kind').get();
      _applyFypArtifactRows(kind, [
        for (final doc in docs.docs)
          Map<String, dynamic>.from(doc.data())
            ..putIfAbsent('id', () => doc.id),
      ]);
    }
  }

  void _seedFypRowSignature(String coll, Map<String, dynamic> row) {
    final id = (row['id'] ?? '').toString();
    if (id.isEmpty) return;
    // A row that just ARRIVED from the cloud must never be pushed back
    // unchanged — seed its signature into the persisted push cache.
    unawaited(() async {
      final cache = await _sigCache();
      cache['$coll/$id'] = _rowSignature(Map<String, Object?>.from(row));
      _saveSigCacheSoon();
    }());
  }

  String _coordinatorFromRow(Map<String, dynamic> row) {
    final rawCoordinators = row['coordinators'];
    if (rawCoordinators is List) {
      return rawCoordinators.map((e) => e.toString()).join(',');
    }
    return (row['coordinator'] ?? '').toString();
  }

  void _applyFypGroupRows(Iterable<Map<String, dynamic>> rows) {
    String? coordinator;
    final groups = <FypGroup>[];
    final tombstones = <String, String>{};
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_groups', row);
      final id = (row['id'] ?? '').toString();
      if (id == '_meta') {
        coordinator = _coordinatorFromRow(row);
        continue;
      }
      if (row['deleted'] == true) {
        tombstones[id] = (row['updated_at'] ?? '').toString();
        continue;
      }
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) groups.add(FypGroup.fromJson(decoded));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (tombstones.isNotEmpty) {
      FypRepository.instance.applyCloudTombstones(groups: tombstones);
    }
    if (groups.isNotEmpty || coordinator != null) {
      FypRepository.instance.applyCloudGroups(groups, coordinator: coordinator);
    }
    if (groups.isNotEmpty || coordinator != null || tombstones.isNotEmpty) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  void _applyFypPanelRows(Iterable<Map<String, dynamic>> rows) {
    final panels = <FypPanel>[];
    final tombstones = <String, String>{};
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_panels', row);
      final id = (row['id'] ?? '').toString();
      if (row['deleted'] == true) {
        tombstones[id] = (row['updated_at'] ?? '').toString();
        continue;
      }
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) panels.add(FypPanel.fromJson(decoded));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (tombstones.isNotEmpty) {
      FypRepository.instance.applyCloudTombstones(panels: tombstones);
    }
    if (panels.isNotEmpty) {
      FypRepository.instance.applyCloudPanels(panels);
    }
    if (panels.isNotEmpty || tombstones.isNotEmpty) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  void _applyFypMeetingRows(Iterable<Map<String, dynamic>> rows) {
    final meetings = <FypMeeting>[];
    final tombstones = <String, String>{};
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_meetings', row);
      final id = (row['id'] ?? '').toString();
      if (row['deleted'] == true) {
        tombstones[id] = (row['updated_at'] ?? '').toString();
        continue;
      }
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) meetings.add(FypMeeting.fromJson(decoded));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (tombstones.isNotEmpty) {
      FypRepository.instance.applyCloudTombstones(meetings: tombstones);
    }
    if (meetings.isNotEmpty) {
      FypRepository.instance.applyCloudMeetings(meetings);
    }
    if (meetings.isNotEmpty || tombstones.isNotEmpty) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  void _applyFypVivaRows(Iterable<Map<String, dynamic>> rows) {
    final sessions = <FypVivaSession>[];
    final tombstones = <String, String>{};
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_viva', row);
      final id = (row['id'] ?? '').toString();
      if (row['deleted'] == true) {
        tombstones[id] = (row['updated_at'] ?? '').toString();
        continue;
      }
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) sessions.add(FypVivaSession.fromJson(decoded));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (tombstones.isNotEmpty) {
      FypRepository.instance.applyCloudTombstones(viva: tombstones);
    }
    if (sessions.isNotEmpty) {
      FypRepository.instance.applyCloudVivaSessions(sessions);
    }
    if (sessions.isNotEmpty || tombstones.isNotEmpty) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  void _applyFypEvaluationRows(Iterable<Map<String, dynamic>> rows) {
    final evaluations = <FypEvaluation>[];
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_evaluations', row);
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) evaluations.add(evaluationFromMap(decoded));
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (evaluations.isNotEmpty) {
      FypRepository.instance.applyCloudEvaluations(evaluations);
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  void _applyFypArtifactRows(String kind, Iterable<Map<String, dynamic>> rows) {
    final maps = <Map<dynamic, dynamic>>[];
    for (final row in rows) {
      _seedFypRowSignature('cloud_fyp_$kind', row);
      final raw = (row['data'] ?? '').toString();
      if (raw.isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) maps.add(decoded);
      } catch (_) {
        // Skip malformed docs; never break sync.
      }
    }
    if (maps.isNotEmpty) {
      FypRepository.instance.applyCloudArtifactMaps(kind, maps);
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  bool _fypOnlyStarted = false;

  /// Pulls the cloud login/FYP workspace before the password check. This keeps
  /// a fresh install from accepting stale local defaults such as student 1234.
  Future<void> bootstrapLoginData({
    Duration timeout = const Duration(seconds: 5),
    List<String> credentialKeys = const [],
    bool includeFypWorkspace = false,
  }) async {
    if (Firebase.apps.isEmpty) return;
    status = 'Checking cloud login...';
    notifyListeners();
    LoginStore.instance.onOverrideChanged = () => unawaited(pushCredentials());
    try {
      await Future.wait([
        // Targeted single-doc reads when the caller knows whose password to
        // check — a whole-collection pull per login burned the daily quota.
        if (credentialKeys.isNotEmpty) _pullCredentialKeys(credentialKeys),
        if (includeFypWorkspace) _pullFypWorkspaceOnce(),
      ]).timeout(timeout);
      lastSyncAt = DateTime.now();
      if (!_started && !_fypOnlyStarted) status = 'Ready';
    } on TimeoutException {
      debugPrint('Login bootstrap timed out.');
      if (!_started && !_fypOnlyStarted) status = 'Waiting for internet...';
    } catch (e) {
      debugPrint('Login bootstrap failed: $e');
      if (!_started && !_fypOnlyStarted) status = 'Waiting for internet...';
    } finally {
      notifyListeners();
    }
  }

  /// STUDENT devices: sync ONLY the FYP groups (so a group a student creates
  /// reaches the supervisor/coordinator, and approvals come back) + login
  /// passwords — none of the staff data (attendance, marks) is pulled here.
  Future<void> startFypOnly() async {
    if (_started || Firebase.apps.isEmpty) return;
    if (_fypOnlyStarted) {
      pushFypNow();
      return;
    }
    _fypOnlyStarted = true;
    FypRepository.instance.onGroupsChanged = () => pushFypNow();
    FypRepository.instance.onPanelsChanged = () => pushFypNow();
    FypRepository.instance.onMeetingsChanged = () => pushFypNow();
    FypRepository.instance.onVivaChanged = () => pushFypNow();
    FypRepository.instance.onEvaluationsChanged = () => pushFypNow();
    FypRepository.instance.onArtifactsChanged = () => pushModulesSoon('fyp');
    LoginStore.instance.onOverrideChanged = () => unawaited(pushCredentials());
    unawaited(pushCurrentStudentFypGroup());
    status = 'On (auto)';
    notifyListeners();
  }

  /// Flushes FYP changes right away. On student devices it only uploads the
  /// current student's own group, so old local staff/admin data cannot reappear.
  void pushFypNow() {
    if (_fypOnlyStarted && !_started && _currentLoginLooksStudent()) {
      unawaited(pushCurrentStudentFypGroup());
      return;
    }
    pushModulesSoon('fyp');
    unawaited(pushModules());
  }

  bool _currentLoginLooksStudent() {
    // The recorded role is authoritative — rolls are NOT always numeric
    // (e.g. BSCS-F25-101), so the old digits-only regex misclassified those
    // students and sent them down the full staff push path.
    if (LoginStore.instance.lastRole == 'student') return true;
    final who = LoginStore.instance.currentUserName.trim();
    return RegExp(r'^\d+$').hasMatch(who);
  }

  Future<void> pushCurrentStudentFypGroup() async {
    if (Firebase.apps.isEmpty) return;
    final roll = LoginStore.instance.currentUserName.trim().toLowerCase();
    if (roll.isEmpty) return;
    final repo = FypRepository.instance;
    final rows = <Map<String, Object?>>[];
    for (final group in repo.groups) {
      final createdByMe =
          group.createdByRole == 'student' &&
          group.createdByName.trim().toLowerCase() == roll;
      final containsMe = group.members.any(
        (member) => member.rollNo.trim().toLowerCase() == roll,
      );
      if (!createdByMe && !containsMe) continue;
      if (repo.deletedGroupTombstones.containsKey(group.id)) continue;
      rows.add({
        'id': group.id,
        'updated_at': group.updatedAt.toIso8601String(),
        'data': jsonEncode(group.toJson()),
        'deleted': false,
      });
    }
    // A student deleting their own (rejected) group must propagate too —
    // otherwise the coordinator keeps seeing it. Tombstones are tiny and the
    // signature cache stops re-pushes within a session.
    for (final e in repo.deletedGroupTombstones.entries) {
      rows.add({
        'id': e.key,
        'updated_at': e.value,
        'data': '',
        'deleted': true,
      });
    }
    if (rows.isEmpty) return;
    try {
      await _pushChangedRows(
        FirebaseFirestore.instance,
        'cloud_fyp_groups',
        rows,
      );
      lastSyncAt = DateTime.now();
      if (_started || _fypOnlyStarted) status = 'On (auto)';
      notifyListeners();
    } catch (e) {
      debugPrint('Student FYP push failed: $e');
      status = 'Waiting for internet...';
      notifyListeners();
    }
  }

  // ==================== Login passwords (overrides) =========================
  String _credDocId(String key) =>
      base64Url.encode(utf8.encode(key)).replaceAll('=', '');

  // ignore: unused_element
  Future<void> _startCredentials({bool pushLocal = true}) async {
    if (Firebase.apps.isEmpty) return;
    if (_credsStarted) {
      if (pushLocal) await pushCredentials();
      return;
    }
    _credsStarted = true;
    _examSubs.add(
      FirebasePaths.collection(_credentialsCollection).snapshots().listen(
        (snap) async {
          var applied = 0;
          final cache = await _sigCache();
          var seeded = false;
          for (final c in snap.docChanges) {
            if (c.type == DocumentChangeType.removed) continue;
            final d = c.doc.data();
            if (d == null) continue;
            final key = (d['key'] ?? '').toString();
            if (key.isEmpty) continue;
            final password = (d['password'] ?? '').toString();
            final ts = (d['ts'] ?? '').toString();
            final ok = await LoginStore.instance.applySyncedOverride(
              key,
              password,
              ts,
            );
            if (ok) {
              applied++;
              // Received from the cloud — never push this same value back.
              cache['cred/${key.toLowerCase()}'] = '$password|$ts';
              seeded = true;
            }
          }
          if (seeded) _saveSigCacheSoon();
          if (applied > 0) {
            lastSyncAt = DateTime.now();
            notifyListeners();
          }
        },
        onError: (Object e) {
          status = 'Waiting for internet…';
          notifyListeners();
        },
      ),
    );
    LoginStore.instance.onOverrideChanged = () => unawaited(pushCredentials());
    if (pushLocal) {
      try {
        await _pullCredentialsOnce().timeout(const Duration(seconds: 5));
      } catch (_) {
        // Keep login responsive; the live listener will catch up later.
      }
      await pushCredentials();
    }
  }

  /// Fetches just the given credential docs (1 read each) and applies them
  /// keep-newest — enough to validate one person's login.
  Future<void> _pullCredentialKeys(List<String> keys) async {
    if (Firebase.apps.isEmpty) return;
    var applied = 0;
    for (final key in keys) {
      final k = key.trim().toLowerCase();
      if (k.isEmpty) continue;
      try {
        final doc = await FirebasePaths.doc(
          _credentialsCollection,
          _credDocId(k),
        ).get();
        final d = doc.data();
        if (d == null) continue;
        final ok = await LoginStore.instance.applySyncedOverride(
          k,
          (d['password'] ?? '').toString(),
          (d['ts'] ?? '').toString(),
        );
        if (ok) applied++;
      } catch (_) {
        // Offline / quota — validation falls back to what this phone holds.
      }
    }
    if (applied > 0) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  Future<void> _pullCredentialsOnce() async {
    if (Firebase.apps.isEmpty) return;
    final snap = await FirebasePaths.collection(_credentialsCollection).get();
    var applied = 0;
    for (final doc in snap.docs) {
      final d = doc.data();
      final key = (d['key'] ?? '').toString();
      if (key.isEmpty) continue;
      final ok = await LoginStore.instance.applySyncedOverride(
        key,
        (d['password'] ?? '').toString(),
        (d['ts'] ?? '').toString(),
      );
      if (ok) applied++;
    }
    if (applied > 0) {
      lastSyncAt = DateTime.now();
      notifyListeners();
    }
  }

  /// Uploads this device's personal password overrides (doc id = key, so it's
  /// idempotent; keep-newest by ts on pull). NOTE: passwords are plaintext —
  /// the app has no Firebase Auth, matching the rest of the open collections.
  /// Settled overrides live in the PERSISTED signature cache (prefix `cred/`),
  /// so repeat launches skip their read AND write entirely — previously every
  /// app start burned one read per override per device.
  Future<void> pushCredentials() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final cache = await _sigCache();
      final db = FirebaseFirestore.instance;
      final overrides = LoginStore.instance.allPasswordOverrides();
      for (var i = 0; i < overrides.length; i += 400) {
        final chunk = overrides.skip(i).take(400).toList();
        final batch = db.batch();
        var writes = 0;
        final done = <String, String>{};
        for (final o in chunk) {
          final sig = '${o.password}|${o.ts}';
          if (cache['cred/${o.key}'] == sig) continue;
          final ref = FirebasePaths.doc(
            _credentialsCollection,
            _credDocId(o.key),
          );
          final remote = await ref.get();
          final remoteTs = (remote.data()?['ts'] ?? '').toString();
          if (remoteTs.isNotEmpty &&
              o.ts.isNotEmpty &&
              remoteTs.compareTo(o.ts) >= 0) {
            done['cred/${o.key}'] = sig; // remote already newer — settled
            continue;
          }
          batch.set(ref, {
            'key': o.key,
            'password': o.password,
            'ts': o.ts,
            ...FirebasePaths.clientWriteMeta(),
          }, SetOptions(merge: true));
          done['cred/${o.key}'] = sig;
          writes++;
        }
        if (writes > 0) await batch.commit();
        cache.addAll(done);
        if (done.isNotEmpty) _saveSigCacheSoon();
      }
    } catch (e) {
      debugPrint('Credential push failed: $e');
    }
  }

  /// Marks a module's data dirty and pushes it shortly (debounced), so rapid
  /// scans batch into one upload.
  void pushModulesSoon(String module) {
    if (_fypOnlySyncMode && module != 'fyp') return;
    _dirtyModules.add(module);
    if ((!_started && !_fypOnlyStarted) || Firebase.apps.isEmpty) return;
    _modulesTimer?.cancel();
    _modulesTimer = Timer(const Duration(seconds: 4), () {
      unawaited(pushModules());
    });
  }

  /// Saves FYP coordinator appointments directly to Firebase so every device
  /// listening to the FYP workspace receives the coordinator list immediately.
  Future<void> pushFypCoordinators(Iterable<String> names) async {
    if (Firebase.apps.isEmpty) return;
    final coordinators = <String>[];
    final seen = <String>{};
    for (final name in names) {
      final trimmed = name.trim();
      if (trimmed.isEmpty) continue;
      final key = trimmed.toLowerCase();
      if (seen.add(key)) coordinators.add(trimmed);
    }
    if (coordinators.isEmpty) return;
    try {
      final now = DateTime.now().toIso8601String();
      await FirebasePaths.doc('cloud_fyp_groups', '_meta').set({
        'id': '_meta',
        'updated_at': now,
        'coordinator': coordinators.join(', '),
        'coordinators': coordinators,
        ...FirebasePaths.clientWriteMeta(),
      }, SetOptions(merge: true));
      lastSyncAt = DateTime.now();
      if (_started || _fypOnlyStarted) status = 'On (auto)';
      notifyListeners();
    } catch (e) {
      debugPrint('FYP coordinator push failed: $e');
      status = 'Waiting for internetâ€¦';
      notifyListeners();
    }
  }

  /// Uploads the dirty (or all) module tables. These tables are small, so
  /// they're pushed whole — doc id = row id keeps it duplicate-free.
  Future<void> pushModules({bool all = false}) async {
    if (Firebase.apps.isEmpty || _busyModules) return;
    _busyModules = true;
    try {
      final rawTargets = all
          ? {'assessments', 'answerSheets', 'slots', 'fyp'}
          : Set<String>.from(_dirtyModules);
      final targets = _fypOnlySyncMode
          ? rawTargets.where((module) => module == 'fyp').toSet()
          : rawTargets;
      _dirtyModules.clear();
      if (targets.isEmpty) return;
      final db = FirebaseFirestore.instance;

      if (targets.contains('assessments')) {
        final assigns =
            (await _dash.examRowsSince('teacher_assignments', '', null))
                .where((r) => !_deletedIds.contains((r['id'] ?? '').toString()))
                .toList();
        final subs =
            (await _dash.examRowsSince('student_submissions', '', null))
                .where((r) => !_deletedIds.contains((r['id'] ?? '').toString()))
                .toList();
        await _pushChangedRows(db, 'cloud_assignments', assigns);
        await _pushChangedRows(db, 'cloud_submissions', subs);
      }

      if (targets.contains('answerSheets')) {
        await _ansRepo.open();
        final dump = await _ansRepo.exportBundle();
        await _pushChangedRows(
          db,
          'cloud_paper_batches',
          ((dump['paper_batches'] as List?) ?? const [])
              .whereType<Map>()
              .map((r) => Map<String, Object?>.from(r))
              .toList(),
        );
      }

      if (targets.contains('slots')) {
        await _slotRepo.open();
        final dump = await _slotRepo.exportBundle();
        for (final table in _slotTables) {
          await _pushChangedRows(
            db,
            _slotColl(table),
            ((dump[table] as List?) ?? const [])
                .whereType<Map>()
                .map((r) => Map<String, Object?>.from(r))
                .toList(),
          );
        }
      }

      if (targets.contains('fyp')) {
        final fypRepo = FypRepository.instance;
        final liveGroupIds = {for (final g in fypRepo.groups) g.id};
        final livePanelIds = {for (final p in fypRepo.panels) p.id};
        final liveMeetingIds = {for (final m in fypRepo.meetings) m.id};
        // Delete markers ride in the SAME doc id as the record: a tombstone
        // overwrites the live doc (data blanked, deleted:true) so every device
        // removes it; a genuine re-creation with a newer updated_at wins back.
        // Both sides set `deleted` explicitly because _pushRows merges fields.
        Map<String, Object?> tombstone(String id, String ts) => {
          'id': id,
          'updated_at': ts,
          'data': '',
          'deleted': true,
        };
        final rows = <Map<String, Object?>>[
          for (final g in fypRepo.groups)
            {
              'id': g.id,
              'updated_at': g.updatedAt.toIso8601String(),
              'data': jsonEncode(g.toJson()),
              'deleted': false,
            },
          for (final e in fypRepo.deletedGroupTombstones.entries)
            if (!liveGroupIds.contains(e.key)) tombstone(e.key, e.value),
          // Only refresh the coordinator metadata when THIS device actually
          // has coordinators set. Pushing an empty list here would wipe the
          // coordinator for everyone — any phone that never set it (a student,
          // or a teacher) could overwrite the cloud. That is exactly how the
          // coordinator got lost before.
          if (fypRepo.coordinatorNames.isNotEmpty)
            {
              'id': '_meta',
              'updated_at': DateTime.now().toIso8601String(),
              'coordinator': fypRepo.coordinatorName,
              'coordinators': fypRepo.coordinatorNames,
            },
        ];
        await _pushChangedRows(db, 'cloud_fyp_groups', rows);
        await _pushChangedRows(db, 'cloud_fyp_panels', [
          for (final p in fypRepo.panels)
            {
              'id': p.id,
              'updated_at': p.updatedAt.toIso8601String(),
              'data': jsonEncode(p.toJson()),
              'deleted': false,
            },
          for (final e in fypRepo.deletedPanelTombstones.entries)
            if (!livePanelIds.contains(e.key)) tombstone(e.key, e.value),
        ]);
        await _pushChangedRows(db, 'cloud_fyp_meetings', [
          for (final m in fypRepo.meetings)
            {
              'id': m.id,
              'updated_at': m.updatedAt.toIso8601String(),
              'data': jsonEncode(m.toJson()),
              'deleted': false,
            },
          for (final e in fypRepo.deletedMeetingTombstones.entries)
            if (!liveMeetingIds.contains(e.key)) tombstone(e.key, e.value),
        ]);
        final liveVivaIds = {for (final v in fypRepo.vivaSessions) v.id};
        await _pushChangedRows(db, 'cloud_fyp_viva', [
          for (final v in fypRepo.vivaSessions)
            {
              'id': v.id,
              'updated_at': v.updatedAt.toIso8601String(),
              'data': jsonEncode(v.toJson()),
              'deleted': false,
            },
          for (final e in fypRepo.deletedVivaTombstones.entries)
            if (!liveVivaIds.contains(e.key)) tombstone(e.key, e.value),
        ]);
        await _pushChangedRows(db, 'cloud_fyp_evaluations', [
          for (final ev in fypRepo.evaluations)
            {
              'id': ev.id,
              'updated_at': ev.submittedAt.toIso8601String(),
              'data': jsonEncode(evaluationToMap(ev)),
              'deleted': false,
            },
        ]);
        for (final kind in FypRepository.artifactKinds) {
          await _pushChangedRows(
            db,
            'cloud_fyp_$kind',
            fypRepo.artifactRows(kind),
          );
        }
      }

      lastSyncAt = DateTime.now();
      status = 'On (auto)';
    } catch (e) {
      debugPrint('Module push failed: $e');
      status = 'Waiting for internet…';
    } finally {
      _busyModules = false;
      notifyListeners();
    }
  }

  // -------- push signature cache (PERSISTED) --------------------------------
  // Every doc pushed gets a content signature; identical content is never
  // written again — not even after an app restart. Without persistence every
  // launch re-pushed whole tables, and those no-op writes both burned the
  // daily write quota AND triggered a read on every listening phone.
  static const _kPushSigCache = 'push_sig_cache_v1';
  Map<String, String>? _pushSigCache;
  Timer? _sigSaveTimer;

  Future<Map<String, String>> _sigCache() async {
    final cached = _pushSigCache;
    if (cached != null) return cached;
    final prefs = await SharedPreferences.getInstance();
    final out = <String, String>{};
    final raw = prefs.getString(_kPushSigCache);
    if (raw != null && raw.isNotEmpty) {
      try {
        final d = jsonDecode(raw);
        if (d is Map) {
          d.forEach((k, v) => out[k.toString()] = v.toString());
        }
      } catch (_) {}
    }
    _pushSigCache = out;
    return out;
  }

  void _saveSigCacheSoon() {
    _sigSaveTimer?.cancel();
    _sigSaveTimer = Timer(const Duration(seconds: 3), () async {
      final cache = _pushSigCache;
      if (cache == null) return;
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(_kPushSigCache, jsonEncode(cache));
      } catch (_) {}
    });
  }

  Future<void> _pushChangedRows(
    FirebaseFirestore db,
    String coll,
    List<Map<String, Object?>> rows,
  ) async {
    final cache = await _sigCache();
    final changed = <Map<String, Object?>>[];
    final signatures = <String, String>{};
    for (final row in rows) {
      final id = (row['id'] ?? '').toString();
      if (id.isEmpty) continue;
      final cacheKey = '$coll/$id';
      final signature = _rowSignature(row);
      if (cache[cacheKey] == signature) continue;
      changed.add(row);
      signatures[cacheKey] = signature;
    }
    if (changed.isEmpty) return;
    await _pushRows(db, coll, changed);
    cache.addAll(signatures);
    // Safety valve: an unbounded cache would bloat SharedPreferences. Clearing
    // costs at most one full (deduped) re-push.
    if (cache.length > 6000) cache.clear();
    _saveSigCacheSoon();
  }

  String _rowSignature(Map<String, Object?> row) {
    final normalized = Map<String, Object?>.from(row);
    if ((normalized['id'] ?? '').toString() == '_meta') {
      normalized.remove('updated_at');
    }
    return jsonEncode(normalized);
  }

  Future<void> _pushRows(
    FirebaseFirestore db,
    String coll,
    List<Map<String, Object?>> rows,
  ) async {
    for (var i = 0; i < rows.length; i += 400) {
      final chunk = rows.skip(i).take(400).toList();
      final batch = db.batch();
      for (final r in chunk) {
        final id = (r['id'] ?? '').toString();
        if (id.isEmpty) continue;
        batch.set(
          FirebasePaths.doc(coll, id),
          Map<String, dynamic>.from(r)..addAll(FirebasePaths.clientWriteMeta()),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }
}
