import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:teacher_student_assessment_app/assessment/icon_cloud.dart';
import 'package:teacher_student_assessment_app/assessment/menu_switcher.dart';
import 'package:teacher_student_assessment_app/assessment/menu_wheel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});

  List<WheelItem> items() => [
    WheelItem(icon: Icons.home, label: 'Home', onTap: () {}),
    WheelItem(icon: Icons.settings, label: 'Settings', onTap: () {}),
    WheelItem(icon: Icons.person, label: 'Profile', onTap: () {}),
    WheelItem(icon: Icons.book, label: 'Courses', onTap: () {}),
  ];

  testWidgets('MenuSwitcher toggles wheel, 3D globe, and clear 3D cloud',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 600, child: MenuSwitcher(items: items())),
        ),
      ),
    );
    await tester.pump();

    // Default is the wheel; all three toggle chips are present.
    expect(find.byType(MenuWheel), findsOneWidget);
    expect(find.byType(IconCloud3D), findsNothing);
    expect(find.text('Wheel'), findsOneWidget);
    expect(find.text('3D'), findsOneWidget);
    expect(find.text('Clear'), findsOneWidget);

    // Switch to the 3D globe.
    await tester.tap(find.text('3D'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byType(IconCloud3D), findsOneWidget);
    expect(find.byType(MenuWheel), findsNothing);
    final globe = tester.widget<IconCloud3D>(find.byType(IconCloud3D));
    expect(globe.transparent, isFalse);

    // Switch to the transparent (clear) 3D cloud.
    await tester.tap(find.text('Clear'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    final clear = tester.widget<IconCloud3D>(find.byType(IconCloud3D));
    expect(clear.transparent, isTrue);

    // Back to the wheel.
    await tester.tap(find.text('Wheel'));
    await tester.pump();
    expect(find.byType(MenuWheel), findsOneWidget);
  });
}
