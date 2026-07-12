import 'package:flutter_test/flutter_test.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_group_models.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_models.dart';
import 'package:teacher_student_assessment_app/fyp/fyp_repository.dart';

// The "old group still shows" bug: deletes only vanished locally — other
// devices kept the record (and could re-push it) forever. These tests pin the
// tombstone behaviour that fixes it. Persistence failures inside the
// repository are swallowed (no path_provider in tests), so only the in-memory
// logic is exercised.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final repo = FypRepository.instance;

  FypMember member(String roll) =>
      FypMember(serialNo: 1, rollNo: roll, name: 'Student $roll', email: '');

  FypGroup create(String title, String roll) => repo.createGroup(
    title: title,
    phase: FypPhase.fyp3,
    program: FypProgram.bscs,
    term: 'Fall 2026',
    members: [member(roll)],
    supervisorName: 'DR. TEST',
    createdByRole: 'coordinator',
    createdByName: 'Coordinator',
  );

  test('a deleted group cannot be resurrected by a stale cloud re-push', () {
    final g = create('Old project', '12238');
    expect(repo.groupForRollNo('12238')?.id, g.id);

    repo.deleteGroup(g.id);
    expect(repo.groupForRollNo('12238'), isNull);
    expect(repo.deletedGroupTombstones.containsKey(g.id), isTrue);

    // A stale device re-pushes the SAME (pre-delete) copy — must stay dead.
    repo.applyCloudGroups([g]);
    expect(repo.groups.where((e) => e.id == g.id), isEmpty);
  });

  test(
    'a genuinely newer copy (re-created after delete) wins the tombstone',
    () {
      final g = create('Recreated project', '99001');
      repo.deleteGroup(g.id);

      final newer = g.copyWith(
        title: 'Recreated project v2',
        updatedAt: DateTime.now().add(const Duration(minutes: 1)),
      );
      repo.applyCloudGroups([newer]);
      expect(repo.groupForRollNo('99001')?.title, 'Recreated project v2');
      expect(repo.deletedGroupTombstones.containsKey(newer.id), isFalse);
      repo.deleteGroup(newer.id); // clean up
    },
  );

  test('applyCloudTombstones removes the local copy on other devices', () {
    final g = create('Remote-deleted project', '99002');
    repo.applyCloudTombstones(
      groups: {
        g.id: DateTime.now().add(const Duration(seconds: 1)).toIso8601String(),
      },
    );
    expect(repo.groupForRollNo('99002'), isNull);
  });

  test('groupForRollNo prefers the NEWEST group when stale data lingers', () {
    // Simulates the student device that still carries the old group locally.
    final old = create('Old lingering group', '99003');
    final fresh = old.copyWith(
      title: 'New group',
      updatedAt: DateTime.now().add(const Duration(minutes: 2)),
    );
    // Different id → both live side by side, like stale + re-created.
    final freshCopy = FypGroup.fromJson(
      fresh.toJson()..['id'] = '${old.id}-new',
    );
    repo.applyCloudGroups([freshCopy]);
    expect(repo.groupForRollNo('99003')?.title, 'New group');
    repo.deleteGroup(old.id);
    repo.deleteGroup(freshCopy.id);
  });
}
