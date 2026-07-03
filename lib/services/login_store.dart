import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Persists login conveniences (all offline, on-device):
/// - the last role used (so the login screen pre-selects it),
/// - auto-saved username + password per role (so the user just taps Login),
/// - custom "Other" teachers (name + password) added at the login screen,
/// - per-credential password overrides set from "Change password".
class LoginStore extends ChangeNotifier {
  LoginStore._();
  static final LoginStore instance = LoginStore._();

  static const _kLastRole = 'login_last_role_v1';
  static const _kAutoSave = 'login_autosave_v1';
  static const _kUserPrefix = 'login_user_'; // + role
  static const _kPassPrefix = 'login_pass_'; // + role
  static const _kLastTeacher = 'login_last_teacher_v1'; // teacher key
  static const _kCurrentUserName = 'login_current_user_name_v1'; // display name
  static const _kCustomTeachers = 'login_custom_teachers_v1'; // json list
  static const _kOverridePrefix = 'login_pwoverride_'; // + credential key

  SharedPreferences? _p;
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    _p = await SharedPreferences.getInstance();
    _loaded = true;
    notifyListeners();
  }

  SharedPreferences get _prefs {
    final p = _p;
    if (p == null) throw StateError('LoginStore.load() was not called.');
    return p;
  }

  // ---- last role + auto-save ------------------------------------------------

  String? get lastRole => _p?.getString(_kLastRole);
  bool get autoSave => _p?.getBool(_kAutoSave) ?? false;

  String savedUsername(String role) =>
      _p?.getString('$_kUserPrefix$role') ?? '';
  String savedPassword(String role) =>
      autoSave ? (_p?.getString('$_kPassPrefix$role') ?? '') : '';

  /// The last teacher selected (a seed teacher email, or `custom:<name>`).
  String? get lastTeacher => _p?.getString(_kLastTeacher);

  /// The display name of whoever is currently logged in (teacher name, "Admin",
  /// or a student roll). Used to stamp who collected an attendance batch.
  String get currentUserName => _p?.getString(_kCurrentUserName) ?? '';

  /// Records the human-readable name of the person now logged in.
  Future<void> setCurrentUserName(String name) async {
    await _prefs.setString(_kCurrentUserName, name.trim());
    notifyListeners();
  }

  /// Record a successful login so next launch is one tap.
  Future<void> recordLogin({
    required String role,
    required String username,
    required String password,
    required bool save,
    String? teacherKey,
  }) async {
    final p = _prefs;
    await p.setString(_kLastRole, role);
    await p.setBool(_kAutoSave, save);
    await p.setString('$_kUserPrefix$role', username);
    if (save) {
      await p.setString('$_kPassPrefix$role', password);
    } else {
      await p.remove('$_kPassPrefix$role');
    }
    if (teacherKey != null) {
      await p.setString(_kLastTeacher, teacherKey);
    }
    notifyListeners();
  }

  Future<void> setAutoSave(bool value) async {
    await _prefs.setBool(_kAutoSave, value);
    notifyListeners();
  }

  // ---- custom "Other" teachers ---------------------------------------------

  List<CustomTeacher> customTeachers() {
    final raw = _p?.getString(_kCustomTeachers);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final list = jsonDecode(raw);
      if (list is! List) return const [];
      return [
        for (final e in list)
          if (e is Map)
            CustomTeacher(
              name: (e['name'] ?? '').toString(),
              password: (e['pass'] ?? '').toString(),
            ),
      ].where((t) => t.name.isNotEmpty).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  CustomTeacher? customTeacherByName(String name) {
    final key = name.trim().toLowerCase();
    for (final t in customTeachers()) {
      if (t.name.trim().toLowerCase() == key) return t;
    }
    return null;
  }

  /// Adds (or updates the password of) a custom teacher and remembers it as the
  /// default selection for next time.
  Future<void> addCustomTeacher(String name, String password) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return;
    final list = customTeachers().toList();
    final idx =
        list.indexWhere((t) => t.name.toLowerCase() == trimmed.toLowerCase());
    if (idx >= 0) {
      list[idx] = CustomTeacher(name: list[idx].name, password: password);
    } else {
      list.add(CustomTeacher(name: trimmed, password: password));
    }
    await _prefs.setString(
      _kCustomTeachers,
      jsonEncode([
        for (final t in list) {'name': t.name, 'pass': t.password},
      ]),
    );
    await _prefs.setString(_kLastTeacher, 'custom:${trimmed.toLowerCase()}');
    notifyListeners();
  }

  // ---- password overrides (Change password) --------------------------------

  static const _kOverrideTsPrefix = 'login_pwoverridets_';

  /// Fired when a personal password override changes, so the cloud sync can
  /// push it. Set by CloudSyncService.
  void Function()? onOverrideChanged;

  /// Credential keys: `admin`, `teacher:<emailOrName>`, `student:<roll>`.
  String? passwordOverride(String key) =>
      _p?.getString('$_kOverridePrefix${key.toLowerCase()}');

  String passwordOverrideTs(String key) =>
      _p?.getString('$_kOverrideTsPrefix${key.toLowerCase()}') ?? '';

  Future<void> setPasswordOverride(String key, String password) async {
    final k = key.toLowerCase();
    await _prefs.setString('$_kOverridePrefix$k', password);
    await _prefs.setString(
      '$_kOverrideTsPrefix$k',
      DateTime.now().toIso8601String(),
    );
    notifyListeners();
    onOverrideChanged?.call();
  }

  /// All personal password overrides (key, password, ts) for cloud sync.
  /// The `admin` credential is deliberately excluded.
  List<({String key, String password, String ts})> allPasswordOverrides() {
    final out = <({String key, String password, String ts})>[];
    final p = _p;
    if (p == null) return out;
    for (final k in p.getKeys()) {
      if (!k.startsWith(_kOverridePrefix) ||
          k.startsWith(_kOverrideTsPrefix)) {
        continue;
      }
      final key = k.substring(_kOverridePrefix.length);
      if (key == 'admin') continue;
      out.add((
        key: key,
        password: p.getString(k) ?? '',
        ts: p.getString('$_kOverrideTsPrefix$key') ?? '',
      ));
    }
    return out;
  }

  /// Applies a synced override ONLY if it's newer than what we hold (so a stale
  /// cloud copy can't clobber a fresher local password change). Returns true if
  /// applied. `admin` is never accepted from the cloud.
  Future<bool> applySyncedOverride(
    String key,
    String password,
    String ts,
  ) async {
    final k = key.toLowerCase();
    if (k == 'admin' || password.isEmpty) return false;
    final localTs = passwordOverrideTs(k);
    if (ts.isNotEmpty && localTs.isNotEmpty && localTs.compareTo(ts) >= 0) {
      return false;
    }
    await _prefs.setString('$_kOverridePrefix$k', password);
    await _prefs.setString(
      '$_kOverrideTsPrefix$k',
      ts.isEmpty ? DateTime.now().toIso8601String() : ts,
    );
    notifyListeners();
    return true;
  }

  /// Updates a custom teacher's stored password (used by Change password).
  Future<void> updateCustomTeacherPassword(
    String name,
    String password,
  ) async {
    if (customTeacherByName(name) != null) {
      await addCustomTeacher(name, password);
    }
  }
}

class CustomTeacher {
  const CustomTeacher({required this.name, required this.password});
  final String name;
  final String password;
}
