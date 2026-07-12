import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Per-teacher permission to CREATE assessments. The admin (logged in on the
/// app) explicitly allows individual teachers; only an allowed teacher sees the
/// "Assess" tab and can build quizzes/assignments. Persists to
/// SharedPreferences so the grant survives restarts.
class AssessmentAccessService extends ChangeNotifier {
  AssessmentAccessService._();
  static final AssessmentAccessService instance = AssessmentAccessService._();

  static const String _prefsKey = 'assessment_access_v1';

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

  /// Whether [teacherId] may create assessments.
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
