import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_lite.dart';
import 'connect_models.dart';

/// AUST Connect store. Offline-first (one local JSON file) + LIVE Firebase sync
/// (was Hostinger; moved to Firebase by request). Each record is one Firestore
/// doc; the server-side logic the PHP used to do (creating notifications on a
/// status change / file advance) is now done here on the client.
class ConnectRepository extends ChangeNotifier {
  ConnectRepository._();
  static final ConnectRepository instance = ConnectRepository._();

  // Firestore collections.
  static const _cComplaints = 'connect_complaints';
  static const _cFiles = 'connect_files';
  static const _cDepartments = 'connect_departments';
  static const _cNotifications = 'connect_notifications';

  final List<ComplaintRecord> _complaints = [];
  final List<FileRecord> _files = [];
  final List<ConnectDepartment> _departments = [];
  final List<ConnectNotification> _notifications = [];

  bool _loaded = false;
  bool _listening = false;
  bool syncing = false;
  final List<StreamSubscription> _subs = [];

  bool get isConfigured => CloudLite.available;

  // -------- accessors --------
  List<ConnectDepartment> get departments {
    final list = _departments.where((d) => !d.deleted).toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    return List.unmodifiable(list);
  }

  /// Complaints for the shared dashboard: not deleted, and not expired
  /// (auto-hidden 3 days after Done).
  List<ComplaintRecord> get dashboardComplaints {
    final list = _complaints
        .where((c) => !c.deleted && !c.expiredFromDashboard)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  List<ComplaintRecord> get allComplaints {
    final list = _complaints.where((c) => !c.deleted).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  List<FileRecord> get files {
    final list = _files.where((f) => !f.deleted).toList()
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return List.unmodifiable(list);
  }

  List<ConnectNotification> notificationsFor(ConnectIdentity who) {
    final list =
        _notifications.where((n) => n.userKey == who.userKey).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  int unreadFor(ConnectIdentity who) =>
      _notifications.where((n) => n.userKey == who.userKey && n.unread).length;

  // -------- persistence --------
  Future<File> _storeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/aust_connect.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _storeFile();
      if (await f.exists()) {
        final d = jsonDecode(await f.readAsString());
        if (d is Map) {
          _readList(d['complaints'], _complaints, ComplaintRecord.fromJson);
          _readList(d['files'], _files, FileRecord.fromJson);
          _readList(d['departments'], _departments, ConnectDepartment.fromJson);
          _readList(
            d['notifications'],
            _notifications,
            ConnectNotification.fromJson,
          );
        }
      }
    } catch (e) {
      debugPrint('AUST Connect load failed: $e');
    }
    notifyListeners();
  }

  void _readList<T>(
    Object? raw,
    List<T> into,
    T Function(Map<dynamic, dynamic>) f,
  ) {
    into.clear();
    if (raw is List) {
      for (final e in raw) {
        if (e is Map) into.add(f(e));
      }
    }
  }

  Timer? _saveTimer;
  void _persistSoon() {
    _saveTimer?.cancel();
    _saveTimer = Timer(const Duration(milliseconds: 400), _persist);
  }

  Future<void> _persist() async {
    try {
      final f = await _storeFile();
      await f.writeAsString(
        jsonEncode({
          'complaints': [for (final c in _complaints) c.toJson()],
          'files': [for (final x in _files) x.toJson()],
          'departments': [for (final d in _departments) d.toJson()],
          'notifications': [for (final n in _notifications) n.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('AUST Connect save failed: $e');
    }
  }

  // -------- live Firebase sync --------
  /// Attaches the live listeners (idempotent) and does a first read. Called
  /// when a Connect screen opens and on pull-to-refresh.
  Future<void> sync(ConnectIdentity who) async {
    if (!CloudLite.available) return;
    if (_listening) return;
    _listening = true;
    syncing = true;
    notifyListeners();
    _subs.add(
      CloudLite.listen(_cComplaints, (rows) {
        _mergeNewest(rows, _complaints, ComplaintRecord.fromJson, (e) => e.id, (
          e,
        ) => e.updatedAt);
      })!,
    );
    _subs.add(
      CloudLite.listen(_cFiles, (rows) {
        _mergeNewest(
          rows,
          _files,
          FileRecord.fromJson,
          (e) => e.id,
          (e) => e.updatedAt,
        );
      })!,
    );
    _subs.add(
      CloudLite.listen(_cDepartments, (rows) {
        _mergeNewest(
          rows,
          _departments,
          ConnectDepartment.fromJson,
          (e) => e.id,
          (e) => e.updatedAt,
        );
      })!,
    );
    _subs.add(
      CloudLite.listen(_cNotifications, (rows) {
        _mergeNewest(
          rows,
          _notifications,
          ConnectNotification.fromJson,
          (e) => e.id,
          (e) => e.createdAt,
        );
      })!,
    );
    syncing = false;
    notifyListeners();
  }

  void stop() {
    for (final s in _subs) {
      s.cancel();
    }
    _subs.clear();
    _listening = false;
  }

  void _mergeNewest<T>(
    List<Map<String, dynamic>> rows,
    List<T> into,
    T Function(Map<dynamic, dynamic>) f,
    String Function(T) idOf,
    DateTime Function(T) stampOf,
  ) {
    var changed = false;
    for (final m in rows) {
      final rec = f(m);
      final id = idOf(rec);
      if (id.isEmpty) continue;
      final i = into.indexWhere((x) => idOf(x) == id);
      if (i == -1) {
        into.add(rec);
        changed = true;
      } else if (!stampOf(rec).isBefore(stampOf(into[i]))) {
        into[i] = rec;
        changed = true;
      }
    }
    if (changed) {
      _persistSoon();
      notifyListeners();
    }
  }

  void _pushComplaint(ComplaintRecord c) =>
      CloudLite.push(_cComplaints, c.id, c.toJson());
  void _pushFile(FileRecord f) => CloudLite.push(_cFiles, f.id, f.toJson());
  void _pushDept(ConnectDepartment d) =>
      CloudLite.push(_cDepartments, d.id, d.toJson());

  void _notify(String userKey, String title, String body, String refType,
      String refId) {
    if (userKey.trim().isEmpty) return;
    final n = ConnectNotification(
      id: 'N${DateTime.now().microsecondsSinceEpoch}',
      userKey: userKey,
      title: title,
      body: body,
      refType: refType,
      refId: refId,
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, n);
    CloudLite.push(_cNotifications, n.id, n.toJson());
    notifyListeners();
    _persistSoon();
  }

  String _localId(String p) =>
      '$p${DateTime.now().microsecondsSinceEpoch}${_complaints.length}';
  String _track(String p) =>
      '$p${DateTime.now().millisecondsSinceEpoch.toRadixString(36).toUpperCase().substring(2)}';

  // -------- complaints --------
  Future<ComplaintRecord> submitComplaint({
    required ConnectIdentity who,
    required String category,
    required String subject,
    required String body,
    required bool anonymous,
  }) async {
    final now = DateTime.now();
    final record = ComplaintRecord(
      id: _localId('C'),
      trackingId: _track('CMP-'),
      category: category,
      subject: subject,
      body: body,
      byName: who.name,
      byRole: who.role,
      byId: who.id,
      isAnon: anonymous,
      status: 'new',
      handledBy: '',
      createdAt: now,
      updatedAt: now,
    );
    _complaints.insert(0, record);
    _pushComplaint(record);
    _persistSoon();
    notifyListeners();
    return record;
  }

  Future<void> setComplaintStatus(
    ComplaintRecord c,
    String status,
    ConnectIdentity who,
  ) async {
    c.status = status;
    c.handledBy = who.name;
    c.updatedAt = DateTime.now();
    if (status == 'done') c.doneAt = DateTime.now();
    _pushComplaint(c);
    // Tell the submitter their complaint moved.
    _notify(
      '${c.byRole}:${c.byId.trim().toLowerCase()}',
      'Complaint ${c.trackingId}',
      'Status changed to ${complaintStatusLabel(status)}',
      'complaint',
      c.id,
    );
    notifyListeners();
    _persistSoon();
  }

  Future<void> deleteComplaint(ComplaintRecord c) async {
    c.deleted = true;
    c.updatedAt = DateTime.now();
    _pushComplaint(c);
    notifyListeners();
    _persistSoon();
  }

  // -------- departments --------
  Future<void> upsertDepartment({
    String? id,
    required String name,
    required int seq,
    required List<String> staff,
  }) async {
    final dept = ConnectDepartment(
      id: id ?? _localId('D'),
      name: name,
      seq: seq,
      staff: staff,
      updatedAt: DateTime.now(),
    );
    final existing = _departments.indexWhere((d) => d.id == dept.id);
    if (existing == -1) {
      _departments.add(dept);
    } else {
      _departments[existing] = dept;
    }
    _pushDept(dept);
    notifyListeners();
    _persistSoon();
  }

  Future<void> deleteDepartment(ConnectDepartment d) async {
    d.deleted = true;
    d.updatedAt = DateTime.now();
    _pushDept(d);
    notifyListeners();
    _persistSoon();
  }

  // -------- files --------
  Future<FileRecord> submitFile({
    required ConnectIdentity who,
    required String title,
    required String description,
    required List<ConnectDepartment> route,
  }) async {
    final now = DateTime.now();
    final steps = [
      for (var i = 0; i < route.length; i++)
        FileStep(deptId: route[i].id, deptName: route[i].name, seq: i),
    ];
    final record = FileRecord(
      id: _localId('F'),
      trackingId: _track('FILE-'),
      title: title,
      description: description,
      byName: who.name,
      byRole: who.role,
      byId: who.id,
      currentSeq: 0,
      status: 'submitted',
      steps: steps,
      createdAt: now,
      updatedAt: now,
    );
    _files.insert(0, record);
    _pushFile(record);
    notifyListeners();
    _persistSoon();
    return record;
  }

  /// Advance the current department's step. [stepStatus] = 'under_process' or
  /// 'done'. On 'done', the file moves to the next department (or Completed).
  Future<void> advanceFile(
    FileRecord f,
    String stepStatus,
    ConnectIdentity who,
  ) async {
    final now = DateTime.now();
    for (final s in f.steps) {
      if (s.seq == f.currentSeq) {
        s.status = stepStatus;
        s.by = who.name;
        s.at = now.toIso8601String();
        if (stepStatus == 'done') {
          final next = f.currentSeq + 1;
          if (next < f.steps.length) {
            f.currentSeq = next;
            f.status = 'in_progress';
          } else {
            f.status = 'completed';
            f.completedAt = now;
          }
        } else {
          f.status = 'in_progress';
        }
        break;
      }
    }
    f.updatedAt = now;
    _pushFile(f);
    // Tell the file owner it moved.
    final cur = f.currentStep;
    _notify(
      '${f.byRole}:${f.byId.trim().toLowerCase()}',
      'File ${f.trackingId}',
      f.status == 'completed'
          ? 'Your file is COMPLETED.'
          : 'Now at ${cur?.deptName ?? ''} (${stepStatus == 'done' ? 'DONE' : 'UNDER PROCESS'})',
      'file',
      f.id,
    );
    notifyListeners();
    _persistSoon();
  }

  // -------- notifications --------
  Future<void> markNotificationRead(ConnectNotification n) async {
    if (!n.unread) return;
    n.readAt = DateTime.now();
    CloudLite.push(_cNotifications, n.id, n.toJson());
    notifyListeners();
    _persistSoon();
  }
}
