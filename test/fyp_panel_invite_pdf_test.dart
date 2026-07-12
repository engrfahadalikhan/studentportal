import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_group_models.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_models.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_panel_invite_pdf.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  FypGroup group(String id, String title, List<String> examiners) => FypGroup(
    id: id,
    title: title,
    phase: FypPhase.fyp3,
    program: FypProgram.bscs,
    term: 'Fall 2026',
    members: const [
      FypMember(
        serialNo: 1,
        rollNo: '21B-001-CS',
        name: 'Ali',
        email: 'ali@student.local',
      ),
      FypMember(
        serialNo: 2,
        rollNo: '21B-002-CS',
        name: 'Sara',
        email: 'sara@student.local',
      ),
    ],
    supervisorName: 'Dr. Supervisor',
    createdByRole: 'coordinator',
    createdByName: 'Coord',
    status: FypGroupStatus.approved,
    examiners: examiners,
    createdAt: DateTime(2026, 7, 1),
    updatedAt: DateTime(2026, 7, 1),
  );

  test('panel invite PDF renders with a timed schedule', () async {
    final panel = FypPanel(
      id: 'P1',
      name: 'Panel A',
      members: const ['Dr. Examiner One', 'Dr. Examiner Two'],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    final bytes = await buildFypPanelInvitePdf(
      panel: panel,
      groups: [
        group('G1', 'Smart Attendance', panel.members),
        group('G2', 'Campus Navigator', panel.members),
      ],
      date: DateTime(2026, 7, 20),
      startMinuteOfDay: 9 * 60,
      minutesPerGroup: 20,
      venue: 'Seminar Hall',
    );
    expect(bytes.lengthInBytes, greaterThan(1000));
    expect(bytes.sublist(0, 4), [0x25, 0x50, 0x44, 0x46]); // %PDF
  });

  test('panel invite PDF renders with no groups and no time', () async {
    final panel = FypPanel(
      id: 'P2',
      name: 'Panel B',
      members: const ['Dr. Solo'],
      createdAt: DateTime(2026, 7, 1),
      updatedAt: DateTime(2026, 7, 1),
    );
    final bytes = await buildFypPanelInvitePdf(
      panel: panel,
      groups: const [],
      date: DateTime(2026, 7, 20),
    );
    expect(bytes.lengthInBytes, greaterThan(1000));
  });
}
