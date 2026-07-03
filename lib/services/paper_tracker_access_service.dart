import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-teacher permission to use the Answer-Sheet / Marking Tracker (scan the
/// csexam program-stats QR to issue/return marking envelopes). The admin
/// approves individual teachers; only an allowed teacher sees the entry.
/// Mirrors [AssessmentAccessService]. Persists to SharedPreferences.
class PaperTrackerAccessService extends ChangeNotifier {
  PaperTrackerAccessService._();
  static final PaperTrackerAccessService instance =
      PaperTrackerAccessService._();

  static const String _prefsKey = 'paper_tracker_access_v1';

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
