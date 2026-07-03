import '../attendance/qr_attendance_section.dart';
import 'admin_data_bundle.dart';
import 'answer_sheet_repository.dart';
import 'app_repository.dart';
import 'slot_collection_repository.dart';
import 'teacher_dashboard_database.dart';

/// Shared logic for importing an admin data bundle — used by both the manual
/// "Choose file & merge" button and the "Open with AUST Portal" (shared file)
/// path, so a WhatsApp-received file lands directly in the database.
class AdminDataImporter {
  /// Parses [text] (throws [FormatException] if it isn't a bundle).
  static ParsedBundle parse(String text) => AdminDataBundle.parse(text);

  /// Imports every module in the bundle [text] (merge, keep-newest) and returns
  /// a per-module added/updated summary.
  static Future<List<ModuleImportResult>> importText(
    String text,
    AppRepository repository,
  ) async {
    final bundle = AdminDataBundle.parse(text);
    final modulesRaw = (bundle.raw['modules'] as Map?) ?? const {};
    final results = <ModuleImportResult>[];
    for (final m in bundle.modules) {
      final data = (modulesRaw[m.key] as Map?)?.cast<String, dynamic>();
      if (data == null) continue;
      results.add(await _importModule(m, data));
    }
    // Refresh the live repository so merged assessments/marks show immediately
    // and aren't overwritten by the next in-memory save.
    if (bundle.modules.contains(AdminModule.assessments)) {
      await repository.loadPersistedAssessments();
      await repository.loadPersistedSubmissions();
    }
    return results;
  }

  static Future<ModuleImportResult> _importModule(
    AdminModule m,
    Map<String, dynamic> data,
  ) async {
    switch (m) {
      case AdminModule.attendance:
        final r = AttendanceRepository();
        await r.open();
        final (a, u) = await r.importScans(
          (data['scans'] as List?) ?? const [],
        );
        return ModuleImportResult(m, a, u);
      case AdminModule.assessments:
        final (a, u) = await TeacherDashboardDatabase.instance
            .importAssessments(data);
        return ModuleImportResult(m, a, u);
      case AdminModule.ufm:
        final (a, u) = await TeacherDashboardDatabase.instance.importUfm(data);
        return ModuleImportResult(m, a, u);
      case AdminModule.answerSheets:
        final r = AnswerSheetRepository();
        await r.open();
        final (a, u) = await r.importBundle(data);
        return ModuleImportResult(m, a, u);
      case AdminModule.slots:
        final r = SlotCollectionRepository();
        await r.open();
        final (a, u) = await r.importBundle(data);
        return ModuleImportResult(m, a, u);
    }
  }
}
