import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-teacher permission to use the Per-Slot Paper Collection module (scan the
/// PER-SLOT QR on the Overall Seating Summary, then track papers received from
/// invigilators). Admin approves individual teachers; only an allowed teacher
/// sees the entry. Mirrors the other access services; persists to prefs.
class SlotCollectionAccessService extends ChangeNotifier {
  SlotCollectionAccessService._();
  static final SlotCollectionAccessService instance =
      SlotCollectionAccessService._();

  static const String _prefsKey = 'slot_collection_access_v1';

  final Set<String> _allowed = {};
  bool _loaded = false;

  Future<void> load() async {
    if (_loaded) return;
    final prefs = await SharedPreferences.getInstance();
    _allowed
      ..clear()
      ..addAll(prefs.getStringList(_prefsKey) ?? const []);
    _loaded = true;
    notifyListeners();
  }

  bool isAllowed(String teacherId) => _allowed.contains(teacherId);

  int get allowedCount => _allowed.length;

  Future<void> setAllowed(String teacherId, bool allowed) async {
    if (teacherId.isEmpty) return;
    if (allowed) {
      if (!_allowed.add(teacherId)) return;
    } else {
      if (!_allowed.remove(teacherId)) return;
    }
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(_prefsKey, _allowed.toList());
  }
}
