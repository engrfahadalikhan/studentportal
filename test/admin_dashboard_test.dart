import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:teacher_student_assessment_app/models/portal_session.dart';
import 'package:teacher_student_assessment_app/services/app_repository.dart';
import 'package:teacher_student_assessment_app/theme/app_palettes.dart';
import 'package:teacher_student_assessment_app/theme/app_theme.dart';
import 'package:teacher_student_assessment_app/ui/dashboard_page.dart';

void main() {
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    SharedPreferences.setMockInitialValues({});
  });

  // Regression: the admin dashboard used to put `Expanded` children inside a
  // Column in a scroll view on narrow screens, which threw an unbounded-height
  // RenderFlex error and blanked the entire dashboard on phones.
  testWidgets('admin dashboard renders on a narrow (phone) screen', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final repository = AppRepository();
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(kAppPalettes.first),
        home: DashboardPage(
          repository: repository,
          session: PortalSession.admin(),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 600));

    expect(tester.takeException(), isNull);
    expect(find.text('Admin Control Room'), findsOneWidget);
    // The verification-access card (the one that used to crash) renders.
    expect(find.text('Grant access'), findsOneWidget);
  });
}
