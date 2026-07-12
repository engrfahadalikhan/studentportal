import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import 'cloud_lite.dart';
import 'connect_models.dart' show ConnectIdentity, ConnectNotification;
import 'event_models.dart';

/// AUST Event store. Offline-first (one local JSON file) + LIVE Firebase sync.
/// An event is posted (pending), a staff member approves/rejects it, and the
/// approved events show in everyone's feed. Notifications are created on the
/// client (there is no server) and addressed to the poster.
class EventRepository extends ChangeNotifier {
  EventRepository._();
  static final EventRepository instance = EventRepository._();

  static const _cEvents = 'event_events';
  static const _cNotifications = 'event_notifications';

  final List<CampusEvent> _events = [];
  final List<ConnectNotification> _notifications = [];

  bool _loaded = false;
  bool _listening = false;
  bool syncing = false;
  final List<StreamSubscription> _subs = [];

  bool get isConfigured => CloudLite.available;

  // -------- accessors --------
  /// Approved, not deleted, upcoming first then past — the public feed.
  List<CampusEvent> get approvedEvents {
    final list = _events
        .where((e) => !e.deleted && e.status == 'approved')
        .toList()
      ..sort((a, b) {
        if (a.isPast != b.isPast) return a.isPast ? 1 : -1;
        return a.date.compareTo(b.date);
      });
    return List.unmodifiable(list);
  }

  /// Pending events awaiting moderation.
  List<CampusEvent> get pendingEvents {
    final list = _events
        .where((e) => !e.deleted && e.status == 'pending')
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return List.unmodifiable(list);
  }

  List<CampusEvent> myEvents(ConnectIdentity who) {
    final key = who.id.trim().toLowerCase();
    final list = _events
        .where((e) => !e.deleted && e.byId.trim().toLowerCase() == key)
        .toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
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
    return File('${dir.path}/aust_events.json');
  }

  Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final f = await _storeFile();
      if (await f.exists()) {
        final d = jsonDecode(await f.readAsString());
        if (d is Map) {
          _readList(d['events'], _events, CampusEvent.fromJson);
          _readList(
            d['notifications'],
            _notifications,
            ConnectNotification.fromJson,
          );
        }
      }
    } catch (e) {
      debugPrint('AUST Event load failed: $e');
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
          'events': [for (final e in _events) e.toJson()],
          'notifications': [for (final n in _notifications) n.toJson()],
        }),
      );
    } catch (e) {
      debugPrint('AUST Event save failed: $e');
    }
  }

  // -------- live Firebase sync --------
  Future<void> sync(ConnectIdentity who) async {
    if (!CloudLite.available) return;
    if (_listening) return;
    _listening = true;
    syncing = true;
    notifyListeners();
    _subs.add(
      CloudLite.listen(_cEvents, (rows) {
        _mergeNewest(
          rows,
          _events,
          CampusEvent.fromJson,
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

  void _pushEvent(CampusEvent e) => CloudLite.push(_cEvents, e.id, e.toJson());

  void _notify(
    String userKey,
    String title,
    String body,
    String refId,
  ) {
    if (userKey.trim().isEmpty) return;
    final n = ConnectNotification(
      id: 'EN${DateTime.now().microsecondsSinceEpoch}',
      userKey: userKey,
      title: title,
      body: body,
      refType: 'event',
      refId: refId,
      createdAt: DateTime.now(),
    );
    _notifications.insert(0, n);
    CloudLite.push(_cNotifications, n.id, n.toJson());
    notifyListeners();
    _persistSoon();
  }

  String _newId(String p) =>
      '$p${DateTime.now().microsecondsSinceEpoch}${_events.length}';

  // -------- mutations --------
  Future<CampusEvent> postEvent({
    required ConnectIdentity who,
    required String title,
    required String caption,
    required DateTime date,
    required int minuteOfDay,
    required String location,
    required String department,
    required int poster,
  }) async {
    final now = DateTime.now();
    // Admins post events that are visible immediately; students/teachers post
    // to the approval queue.
    final approved = who.isAdmin;
    final event = CampusEvent(
      id: _newId('E'),
      title: title,
      caption: caption,
      date: date,
      minuteOfDay: minuteOfDay,
      location: location,
      poster: poster % kEventPosterCount,
      department: department,
      byName: who.name,
      byRole: who.role,
      byId: who.id,
      status: approved ? 'approved' : 'pending',
      createdAt: now,
      updatedAt: now,
      approvedAt: approved ? now : null,
    );
    _events.insert(0, event);
    _pushEvent(event);
    notifyListeners();
    _persistSoon();
    return event;
  }

  Future<void> approveEvent(CampusEvent e, ConnectIdentity who) async {
    e.status = 'approved';
    e.approvedAt = DateTime.now();
    e.updatedAt = DateTime.now();
    _pushEvent(e);
    _notify(
      '${e.byRole}:${e.byId.trim().toLowerCase()}',
      'Event approved',
      '"${e.title}" is now live on the events board.',
      e.id,
    );
    notifyListeners();
    _persistSoon();
  }

  Future<void> rejectEvent(CampusEvent e, ConnectIdentity who) async {
    e.status = 'rejected';
    e.updatedAt = DateTime.now();
    _pushEvent(e);
    _notify(
      '${e.byRole}:${e.byId.trim().toLowerCase()}',
      'Event not approved',
      '"${e.title}" was not approved for the events board.',
      e.id,
    );
    notifyListeners();
    _persistSoon();
  }

  Future<void> deleteEvent(CampusEvent e) async {
    e.deleted = true;
    e.updatedAt = DateTime.now();
    _pushEvent(e);
    notifyListeners();
    _persistSoon();
  }

  Future<void> markNotificationRead(ConnectNotification n) async {
    if (!n.unread) return;
    n.readAt = DateTime.now();
    CloudLite.push(_cNotifications, n.id, n.toJson());
    notifyListeners();
    _persistSoon();
  }
}
