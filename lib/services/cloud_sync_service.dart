import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../attendance/qr_attendance_section.dart';
import '../fyp/fyp_group_models.dart';
import '../fyp/fyp_repository.dart';
import 'answer_sheet_repository.dart';
import 'app_repository.dart';
import 'login_store.dart';
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
      unawaited(pushLocalScans());
      unawaited(pushExamData());
      unawaited(pushModules(all: true));
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
      // Live pull: receive everyone's scans (Firestore only sends deltas
      // after the first snapshot, and its offline cache persists them).
      _sub = FirebaseFirestore.instance
          .collection(_collection)
          .snapshots()
          .listen(
            _onCloudChange,
            onError: (Object e) {
              status = 'Waiting for internet…';
              notifyListeners();
            },
          );
      await pushLocalScans();
      await _startExam();
      await _startModules();
      await _startCredentials();
      // Any FYP group change (create / approve / reject / examiners) pushes.
      FypRepository.instance.onGroupsChanged = () => pushModulesSoon('fyp');
      FypRepository.instance.onPanelsChanged = () => pushModulesSoon('fyp');
      FypRepository.instance.onMeetingsChanged = () => pushModulesSoon('fyp');
      unawaited(pushModules(all: true));
      status = 'On (auto)';
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
            ..['uploaded_at'] = FieldValue.serverTimestamp();
          batch.set(
            db.collection(_collection).doc(s.token),
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
    if (_examStarted || Firebase.apps.isEmpty) return;
    _examStarted = true;
    final db = FirebaseFirestore.instance;
    _examCollections.forEach((table, coll) {
      _examSubs.add(
        db
            .collection(coll)
            .snapshots()
            .listen(
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
      db
          .collection(_deletedCollection)
          .snapshots()
          .listen(
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
            batch.delete(db.collection(coll).doc(id));
            batch.set(db.collection(_deletedCollection).doc(id), {
              't': table,
              'id': id,
              'at': now,
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
        await _dash.deleteRowById(table, id);
        if (table == 'teacher_assignments' || table == 'student_submissions') {
          repository?.applyCloudRemoval(table, id);
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
    final db = FirebaseFirestore.instance;

    void listen(
      String coll,
      Future<void> Function(List<Map<String, Object?>> rows) apply,
    ) {
      _examSubs.add(
        db
            .collection(coll)
            .snapshots()
            .listen(
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

    _listenFypGroups();
  }

  bool _fypListening = false;

  /// FYP groups (allotment workflow): docs carry the group JSON in `data`;
  /// the `_meta` doc carries the coordinator name.
  void _listenFypGroups() {
    if (_fypListening || Firebase.apps.isEmpty) return;
    _fypListening = true;
    _examSubs.add(
      FirebaseFirestore.instance
          .collection('cloud_fyp_groups')
          .snapshots()
          .listen(
            (snap) {
              String? coordinator;
              final groups = <FypGroup>[];
              for (final c in snap.docChanges) {
                if (c.type == DocumentChangeType.removed) continue;
                final r = c.doc.data();
                if (r == null) continue;
                if ((r['id'] ?? '').toString() == '_meta') {
                  final rawCoordinators = r['coordinators'];
                  coordinator = rawCoordinators is List
                      ? rawCoordinators.map((e) => e.toString()).join(',')
                      : (r['coordinator'] ?? '').toString();
                  continue;
                }
                final raw = (r['data'] ?? '').toString();
                if (raw.isEmpty) continue;
                try {
                  final decoded = jsonDecode(raw);
                  if (decoded is Map) groups.add(FypGroup.fromJson(decoded));
                } catch (_) {
                  // Skip malformed docs; never break sync.
                }
              }
              if (groups.isEmpty && coordinator == null) return;
              FypRepository.instance.applyCloudGroups(
                groups,
                coordinator: coordinator,
              );
              lastSyncAt = DateTime.now();
              notifyListeners();
            },
            onError: (Object e) {
              status = 'Waiting for internet…';
              notifyListeners();
            },
          ),
    );
    // Examiner panels + meetings (docs carry JSON in `data`).
    _examSubs.add(
      FirebaseFirestore.instance
          .collection('cloud_fyp_panels')
          .snapshots()
          .listen((snap) {
            final panels = <FypPanel>[];
            for (final c in snap.docChanges) {
              if (c.type == DocumentChangeType.removed) continue;
              final raw = (c.doc.data()?['data'] ?? '').toString();
              if (raw.isEmpty) continue;
              try {
                final d = jsonDecode(raw);
                if (d is Map) panels.add(FypPanel.fromJson(d));
              } catch (_) {}
            }
            if (panels.isNotEmpty) {
              FypRepository.instance.applyCloudPanels(panels);
              notifyListeners();
            }
          }, onError: (_) {}),
    );
    _examSubs.add(
      FirebaseFirestore.instance
          .collection('cloud_fyp_meetings')
          .snapshots()
          .listen((snap) {
            final meetings = <FypMeeting>[];
            for (final c in snap.docChanges) {
              if (c.type == DocumentChangeType.removed) continue;
              final raw = (c.doc.data()?['data'] ?? '').toString();
              if (raw.isEmpty) continue;
              try {
                final d = jsonDecode(raw);
                if (d is Map) meetings.add(FypMeeting.fromJson(d));
              } catch (_) {}
            }
            if (meetings.isNotEmpty) {
              FypRepository.instance.applyCloudMeetings(meetings);
              notifyListeners();
            }
          }, onError: (_) {}),
    );
  }

  bool _fypOnlyStarted = false;

  /// STUDENT devices: sync ONLY the FYP groups (so a group a student creates
  /// reaches the supervisor/coordinator, and approvals come back) + login
  /// passwords — none of the staff data (attendance, marks) is pulled here.
  Future<void> startFypOnly() async {
    if (_started || _fypOnlyStarted || Firebase.apps.isEmpty) return;
    _fypOnlyStarted = true;
    _listenFypGroups();
    await _startCredentials();
    FypRepository.instance.onGroupsChanged = () => pushModulesSoon('fyp');
    pushModulesSoon('fyp');
  }

  // ==================== Login passwords (overrides) =========================
  String _credDocId(String key) =>
      base64Url.encode(utf8.encode(key)).replaceAll('=', '');

  Future<void> _startCredentials() async {
    if (_credsStarted || Firebase.apps.isEmpty) return;
    _credsStarted = true;
    _examSubs.add(
      FirebaseFirestore.instance
          .collection(_credentialsCollection)
          .snapshots()
          .listen(
            (snap) async {
              var applied = 0;
              for (final c in snap.docChanges) {
                if (c.type == DocumentChangeType.removed) continue;
                final d = c.doc.data();
                if (d == null) continue;
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
            },
            onError: (Object e) {
              status = 'Waiting for internet…';
              notifyListeners();
            },
          ),
    );
    LoginStore.instance.onOverrideChanged = () => unawaited(pushCredentials());
    await pushCredentials();
  }

  /// Uploads this device's personal password overrides (doc id = key, so it's
  /// idempotent; keep-newest by ts on pull). NOTE: passwords are plaintext —
  /// the app has no Firebase Auth, matching the rest of the open collections.
  Future<void> pushCredentials() async {
    if (Firebase.apps.isEmpty) return;
    try {
      final db = FirebaseFirestore.instance;
      final overrides = LoginStore.instance.allPasswordOverrides();
      for (var i = 0; i < overrides.length; i += 400) {
        final chunk = overrides.skip(i).take(400).toList();
        final batch = db.batch();
        for (final o in chunk) {
          batch.set(
            db.collection(_credentialsCollection).doc(_credDocId(o.key)),
            {'key': o.key, 'password': o.password, 'ts': o.ts},
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      }
    } catch (e) {
      debugPrint('Credential push failed: $e');
    }
  }

  /// Marks a module's data dirty and pushes it shortly (debounced), so rapid
  /// scans batch into one upload.
  void pushModulesSoon(String module) {
    _dirtyModules.add(module);
    if ((!_started && !_fypOnlyStarted) || Firebase.apps.isEmpty) return;
    _modulesTimer?.cancel();
    _modulesTimer = Timer(const Duration(seconds: 4), () {
      unawaited(pushModules());
    });
  }

  /// Uploads the dirty (or all) module tables. These tables are small, so
  /// they're pushed whole — doc id = row id keeps it duplicate-free.
  Future<void> pushModules({bool all = false}) async {
    if (Firebase.apps.isEmpty || _busyModules) return;
    _busyModules = true;
    try {
      final targets = all
          ? {'assessments', 'answerSheets', 'slots', 'fyp'}
          : Set<String>.from(_dirtyModules);
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
        await _pushRows(db, 'cloud_assignments', assigns);
        await _pushRows(db, 'cloud_submissions', subs);
      }

      if (targets.contains('answerSheets')) {
        await _ansRepo.open();
        final dump = await _ansRepo.exportBundle();
        await _pushRows(
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
          await _pushRows(
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
        final rows = <Map<String, Object?>>[
          for (final g in fypRepo.groups)
            {
              'id': g.id,
              'updated_at': g.updatedAt.toIso8601String(),
              'data': jsonEncode(g.toJson()),
            },
          {
            'id': '_meta',
            'updated_at': DateTime.now().toIso8601String(),
            'coordinator': fypRepo.coordinatorName,
            'coordinators': fypRepo.coordinatorNames,
          },
        ];
        await _pushRows(db, 'cloud_fyp_groups', rows);
        await _pushRows(db, 'cloud_fyp_panels', [
          for (final p in fypRepo.panels)
            {
              'id': p.id,
              'updated_at': p.updatedAt.toIso8601String(),
              'data': jsonEncode(p.toJson()),
            },
        ]);
        await _pushRows(db, 'cloud_fyp_meetings', [
          for (final m in fypRepo.meetings)
            {
              'id': m.id,
              'updated_at': m.updatedAt.toIso8601String(),
              'data': jsonEncode(m.toJson()),
            },
        ]);
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
          db.collection(coll).doc(id),
          Map<String, dynamic>.from(r),
          SetOptions(merge: true),
        );
      }
      await batch.commit();
    }
  }
}
