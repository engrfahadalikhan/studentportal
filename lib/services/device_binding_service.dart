import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One person allowed to sign in on this device.
class BindingEntry {
  const BindingEntry({
    required this.role,
    required this.key,
    required this.label,
  });

  final String role; // 'student' | 'faculty'
  final String key; // roll number or teacher id/email
  final String label; // display name

  Map<String, Object?> toJson() => {'role': role, 'key': key, 'label': label};

  static BindingEntry fromJson(Map<String, Object?> j) => BindingEntry(
    role: (j['role'] ?? '').toString(),
    key: (j['key'] ?? '').toString(),
    label: (j['label'] ?? '').toString(),
  );
}

/// Binds this installation to one OR MORE people. The first non-admin login
/// claims the device; afterwards only the assigned people (plus Admin, the
/// override) can sign in. An admin can ADD more people, CHANGE/REMOVE an
/// assignment, or release the device entirely.
class DeviceBindingService extends ChangeNotifier {
  DeviceBindingService._();
  static final DeviceBindingService instance = DeviceBindingService._();

  static const _kList = 'device_bound_list_v2';
  static const _kAllowAll = 'device_allow_all_v1';
  // Legacy single-binding keys (migrated on load).
  static const _kRole = 'device_bound_role';
  static const _kKey = 'device_bound_key';
  static const _kLabel = 'device_bound_label';

  final List<BindingEntry> _entries = [];
  bool _allowAll = false;

  List<BindingEntry> get entries => List.unmodifiable(_entries);
  bool get isBound => _entries.isNotEmpty;

  /// Open device: EVERYONE (students + teachers + admin) may sign in, and the
  /// first login never claims it. Individual assignments below stay possible
  /// and take effect again the moment this is switched off.
  bool get allowAll => _allowAll;

  Future<void> setAllowAll(bool value) async {
    if (_allowAll == value) return;
    _allowAll = value;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAllowAll, value);
    notifyListeners();
  }

  /// Key of the only student/teacher entry (for locking the login field), or
  /// null when there are zero or several of that role.
  String? _singleKeyOfRole(String role) {
    final of = _entries.where((e) => e.role == role).toList();
    return of.length == 1 ? of.first.key : null;
  }

  // On an open (allow-all) device nothing is locked to a single person.
  String? singleKeyOf(String role) =>
      _allowAll ? null : _singleKeyOfRole(role);
  String? singleLabelOf(String role) {
    if (_allowAll) return null;
    final of = _entries.where((e) => e.role == role).toList();
    return of.length == 1 ? of.first.label : null;
  }

  Set<String> get boundRoles => _entries.map((e) => e.role).toSet();

  /// Short human summary for the login banner.
  String get summaryLabel {
    if (_allowAll) return 'Everyone (open device)';
    if (_entries.isEmpty) return '';
    if (_entries.length == 1) return _entries.first.label;
    return '${_entries.length} people';
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    _allowAll = prefs.getBool(_kAllowAll) ?? false;
    _entries.clear();
    final raw = prefs.getString(_kList);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final e in decoded) {
            if (e is Map) _entries.add(BindingEntry.fromJson(e.cast()));
          }
        }
      } catch (_) {}
    } else {
      // Migrate a legacy single binding, if present.
      final role = prefs.getString(_kRole) ?? '';
      final key = prefs.getString(_kKey) ?? '';
      if ((role == 'student' || role == 'faculty') && key.isNotEmpty) {
        _entries.add(
          BindingEntry(
            role: role,
            key: key,
            label: prefs.getString(_kLabel) ?? key,
          ),
        );
        await _save();
      }
    }
    notifyListeners();
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _kList,
      jsonEncode([for (final e in _entries) e.toJson()]),
    );
    await prefs.remove(_kRole);
    await prefs.remove(_kKey);
    await prefs.remove(_kLabel);
  }

  bool _has(String role, String key) => _entries.any(
    (e) => e.role == role && e.key.toLowerCase() == key.trim().toLowerCase(),
  );

  /// First student/teacher to log in claims the device (only when empty).
  /// An open ("allowed for all") device is never claimed.
  Future<void> bindIfUnclaimed({
    required String role,
    required String key,
    required String label,
  }) async {
    if (_allowAll) return;
    if (_entries.isNotEmpty) return;
    await addPerson(role: role, key: key, label: label);
  }

  /// Admin: add an allowed person (assign to multiple people).
  Future<bool> addPerson({
    required String role,
    required String key,
    required String label,
  }) async {
    if (role != 'student' && role != 'faculty') return false;
    if (key.trim().isEmpty) return false;
    if (_has(role, key)) return false;
    _entries.add(
      BindingEntry(
        role: role,
        key: key.trim(),
        label: label.trim().isEmpty ? key.trim() : label.trim(),
      ),
    );
    await _save();
    notifyListeners();
    return true;
  }

  /// Admin: remove one assignment (change the assignment).
  Future<void> removePerson(String key) async {
    _entries.removeWhere((e) => e.key.toLowerCase() == key.toLowerCase());
    await _save();
    notifyListeners();
  }

  /// Admin: release the whole device so anyone can claim it again.
  Future<void> release() async {
    _entries.clear();
    await _save();
    notifyListeners();
  }

  /// Whether [role]+[key] may sign in. Admin always; an "allowed for all"
  /// device allows everyone; an unbound device allows anyone; a bound device
  /// only its assigned people.
  bool allows({required String role, required String key}) {
    if (_allowAll) return true;
    if (role == 'admin') return true;
    if (_entries.isEmpty) return true;
    return _has(role, key);
  }
}
