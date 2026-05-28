import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../assessment/assessment_models.dart';
import '../models/student_record.dart';
import '../services/app_repository.dart';
import '../ui/student_portal_shell.dart';
import 'academic_store.dart';

// ============================================================================
// Time Table — works for both student and teacher.
// ============================================================================
class TimeTableModule extends StatelessWidget {
  const TimeTableModule({
    super.key,
    required this.repository,
    this.student,
    this.teacher,
  }) : assert(student != null || teacher != null,
            'Either student or teacher must be provided');

  final AppRepository repository;
  final StudentRecord? student;
  final AssessmentTeacher? teacher;

  @override
  Widget build(BuildContext context) {
    final store = AcademicStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final courses = _coursesForUser(repository);
        // Build flat list of (course, slot) entries grouped by day.
        final Map<int, List<_GridEntry>> byDay = {};
        for (final course in courses) {
          var slots = store.slotsForCourse(course.id);
          if (slots.isEmpty) {
            slots = _generateDeterministicSlots(course);
          }
          for (final slot in slots) {
            byDay.putIfAbsent(slot.day, () => []).add(
                  _GridEntry(course: course, slot: slot),
                );
          }
        }
        for (final list in byDay.values) {
          list.sort((a, b) => (a.slot.startHour * 60 + a.slot.startMinute)
              .compareTo(b.slot.startHour * 60 + b.slot.startMinute));
        }
        final days = byDay.keys.toList()..sort();

        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(title: const Text('Time Table')),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (courses.isEmpty)
                const _Empty(text: 'No courses registered for the week.')
              else if (days.isEmpty)
                const _Empty(
                  text:
                      'No class times saved yet. The schedule grid will fill once slots are added.',
                )
              else
                for (final day in days)
                  _DayBlock(day: day, entries: byDay[day]!),
            ],
          ),
        );
      },
    );
  }

  List<AssessmentCourse> _coursesForUser(AppRepository repo) {
    if (teacher != null) {
      return repo.coursesForTeacher(teacher!);
    }
    final s = student!;
    return repo.assessmentCourses
        .where((c) =>
            c.program.toLowerCase().contains(s.program.toLowerCase()) ||
            s.program.toLowerCase().contains(c.program.toLowerCase()))
        .where((c) =>
            c.semester.trim() == s.semester.trim() &&
            c.section.trim().toLowerCase() ==
                s.section.trim().toLowerCase())
        .toList(growable: false);
  }

  /// Deterministic slot generator so the demo schedule looks plausible even
  /// without admin-entered data. Hash the course id to pick a day/time.
  List<TimeSlot> _generateDeterministicSlots(AssessmentCourse course) {
    final hash = course.id.codeUnits.fold<int>(0, (s, c) => s + c);
    final day = (hash % 5) + 1; // Mon..Fri
    final startHour = 8 + (hash % 6);
    return [
      TimeSlot(
        day: day,
        startHour: startHour,
        startMinute: 0,
        durationMinutes: 80,
        room: 'Hall-${(hash % 5) + 1}',
      ),
    ];
  }
}

class _GridEntry {
  const _GridEntry({required this.course, required this.slot});
  final AssessmentCourse course;
  final TimeSlot slot;
}

class _DayBlock extends StatelessWidget {
  const _DayBlock({required this.day, required this.entries});
  final int day;
  final List<_GridEntry> entries;

  String _dayName() {
    const names = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return names[(day - 1).clamp(0, 6)];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 5,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFFE9EEFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  _dayName(),
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PortalColors.brandBlue,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '${entries.length} class${entries.length == 1 ? '' : 'es'}',
                style: const TextStyle(color: PortalColors.subtleText),
              ),
            ],
          ),
          const SizedBox(height: 8),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: _SlotTile(entry: entry),
            ),
        ],
      ),
    );
  }
}

class _SlotTile extends StatelessWidget {
  const _SlotTile({required this.entry});
  final _GridEntry entry;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            alignment: Alignment.center,
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
              color: PortalColors.brandBlue,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Column(
              children: [
                Text(
                  entry.slot.startLabel,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  '${entry.slot.durationMinutes}m',
                  style: const TextStyle(
                    color: Color(0xFFEFF6FF),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${entry.course.courseCode} — ${entry.course.courseName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PortalColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  '${entry.course.program} ${entry.course.semester}${entry.course.section} • ${entry.slot.room}',
                  style: const TextStyle(
                    color: PortalColors.subtleText,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Class Attendance — teacher marks daily; student sees %.
// ============================================================================
class ClassAttendanceModule extends StatefulWidget {
  const ClassAttendanceModule({
    super.key,
    required this.repository,
    this.student,
    this.teacher,
  });

  final AppRepository repository;
  final StudentRecord? student;
  final AssessmentTeacher? teacher;

  @override
  State<ClassAttendanceModule> createState() => _ClassAttendanceModuleState();
}

class _ClassAttendanceModuleState extends State<ClassAttendanceModule> {
  AssessmentCourse? _selectedCourse;

  @override
  Widget build(BuildContext context) {
    final isTeacher = widget.teacher != null;
    final courses = isTeacher
        ? widget.repository.coursesForTeacher(widget.teacher!)
        : widget.repository.assessmentCourses;

    return AnimatedBuilder(
      animation: AcademicStore.instance,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(title: const Text('Class Attendance')),
          body: isTeacher
              ? _teacherView(courses)
              : _studentView(courses),
        );
      },
    );
  }

  Widget _teacherView(List<AssessmentCourse> courses) {
    final selected = _selectedCourse ?? (courses.isEmpty ? null : courses.first);
    final attendance = selected == null
        ? <AttendanceRecord>[]
        : AcademicStore.instance.attendanceForCourse(selected.id);
    final today = DateTime.now();
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (courses.isEmpty)
          const _Empty(text: 'No courses assigned to mark attendance.')
        else ...[
          DropdownButtonFormField<AssessmentCourse>(
            initialValue: selected,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Course',
              prefixIcon: Icon(Icons.class_outlined),
            ),
            items: [
              for (final course in courses)
                DropdownMenuItem<AssessmentCourse>(
                  value: course,
                  child: Text(
                    '${course.courseCode} ${course.section} — ${course.courseName}',
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
            onChanged: (value) => setState(() => _selectedCourse = value),
          ),
          const SizedBox(height: 14),
          if (selected != null)
            _RosterMarker(
              course: selected,
              repository: widget.repository,
              today: today,
              records: attendance,
            ),
        ],
      ],
    );
  }

  Widget _studentView(List<AssessmentCourse> courses) {
    final rollNo = widget.student!.rollNo;
    final all = AcademicStore.instance.attendanceForStudent(rollNo);
    final Map<String, List<AttendanceRecord>> byCourse = {};
    for (final record in all) {
      byCourse.putIfAbsent(record.courseId, () => []).add(record);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
      children: [
        if (byCourse.isEmpty)
          const _Empty(
            text:
                'No class attendance recorded yet. Once your teachers mark attendance, it will appear here.',
          )
        else
          for (final entry in byCourse.entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _StudentAttendanceRow(
                courseId: entry.key,
                records: entry.value,
                repository: widget.repository,
              ),
            ),
      ],
    );
  }
}

class _RosterMarker extends StatelessWidget {
  const _RosterMarker({
    required this.course,
    required this.repository,
    required this.today,
    required this.records,
  });

  final AssessmentCourse course;
  final AppRepository repository;
  final DateTime today;
  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    // Build roster from assessmentStudents matching course.
    final roster = repository.assessmentStudents
        .where((s) =>
            s.program.toLowerCase().contains(course.program.toLowerCase()) ||
            course.program.toLowerCase().contains(s.program.toLowerCase()))
        .where((s) => s.semester.trim() == course.semester.trim())
        .where((s) =>
            s.section.trim().toLowerCase() ==
            course.section.trim().toLowerCase())
        .toList(growable: false);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Roll today — ${DateFormat('dd MMM yyyy').format(today)}',
            style: const TextStyle(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Tap each row to mark present / absent.',
            style: const TextStyle(color: PortalColors.subtleText, fontSize: 12),
          ),
          const SizedBox(height: 10),
          if (roster.isEmpty)
            const Text(
              'No students mapped to this course/section in the enrollment list.',
              style: TextStyle(color: PortalColors.subtleText),
            )
          else
            for (final student in roster)
              _RosterRow(
                courseId: course.id,
                student: student,
                today: today,
                records: records,
              ),
        ],
      ),
    );
  }
}

class _RosterRow extends StatelessWidget {
  const _RosterRow({
    required this.courseId,
    required this.student,
    required this.today,
    required this.records,
  });

  final String courseId;
  final AssessmentStudent student;
  final DateTime today;
  final List<AttendanceRecord> records;

  @override
  Widget build(BuildContext context) {
    AttendanceRecord? todayRecord;
    final iso = DateFormat('yyyy-MM-dd').format(today);
    for (final record in records) {
      if (record.rollNo == student.studentId &&
          DateFormat('yyyy-MM-dd').format(record.date) == iso) {
        todayRecord = record;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  student.name,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                Text(
                  student.studentId,
                  style: const TextStyle(
                      color: PortalColors.subtleText, fontSize: 12),
                ),
              ],
            ),
          ),
          ChoiceChip(
            label: const Text('Present'),
            selected: todayRecord?.present == true,
            onSelected: (_) => AcademicStore.instance.markAttendance(
              courseId: courseId,
              rollNo: student.studentId,
              date: today,
              present: true,
            ),
            selectedColor: const Color(0xFFD1FAE5),
          ),
          const SizedBox(width: 6),
          ChoiceChip(
            label: const Text('Absent'),
            selected: todayRecord?.present == false,
            onSelected: (_) => AcademicStore.instance.markAttendance(
              courseId: courseId,
              rollNo: student.studentId,
              date: today,
              present: false,
            ),
            selectedColor: const Color(0xFFFEE2E2),
          ),
        ],
      ),
    );
  }
}

class _StudentAttendanceRow extends StatelessWidget {
  const _StudentAttendanceRow({
    required this.courseId,
    required this.records,
    required this.repository,
  });

  final String courseId;
  final List<AttendanceRecord> records;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final course = repository.courseById(courseId);
    final present = records.where((r) => r.present).length;
    final total = records.length;
    final pct = total == 0 ? 0.0 : (present / total) * 100;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  course == null
                      ? courseId
                      : '${course.courseCode} — ${course.courseName}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(
                  '$present / $total classes attended',
                  style: const TextStyle(
                      color: PortalColors.subtleText, fontSize: 12),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: pct >= 75
                  ? const Color(0xFFD1FAE5)
                  : (pct >= 50
                      ? const Color(0xFFFFF3CD)
                      : const Color(0xFFFEE2E2)),
              borderRadius: BorderRadius.circular(999),
            ),
            child: Text(
              '${pct.toStringAsFixed(0)}%',
              style: const TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// Course Materials — teacher uploads links/notes; student lists/downloads.
// ============================================================================
class CourseMaterialsModule extends StatefulWidget {
  const CourseMaterialsModule({
    super.key,
    required this.repository,
    this.student,
    this.teacher,
  });
  final AppRepository repository;
  final StudentRecord? student;
  final AssessmentTeacher? teacher;
  @override
  State<CourseMaterialsModule> createState() => _CourseMaterialsModuleState();
}

class _CourseMaterialsModuleState extends State<CourseMaterialsModule> {
  AssessmentCourse? _selected;
  @override
  Widget build(BuildContext context) {
    final isTeacher = widget.teacher != null;
    final courses = isTeacher
        ? widget.repository.coursesForTeacher(widget.teacher!)
        : widget.repository.assessmentCourses;
    final selected =
        _selected ?? (courses.isEmpty ? null : courses.first);
    return AnimatedBuilder(
      animation: AcademicStore.instance,
      builder: (context, _) {
        final materials = selected == null
            ? <CourseMaterial>[]
            : AcademicStore.instance.materialsForCourse(selected.id);
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(title: const Text('Course Materials')),
          floatingActionButton: isTeacher && selected != null
              ? FloatingActionButton.extended(
                  onPressed: () => _showAddSheet(context, selected),
                  icon: const Icon(Icons.add),
                  label: const Text('Upload'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (courses.isEmpty)
                const _Empty(text: 'No courses available.')
              else
                DropdownButtonFormField<AssessmentCourse>(
                  initialValue: selected,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Course',
                    prefixIcon: Icon(Icons.class_outlined),
                  ),
                  items: [
                    for (final c in courses)
                      DropdownMenuItem<AssessmentCourse>(
                        value: c,
                        child: Text(
                          '${c.courseCode} ${c.section} — ${c.courseName}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) => setState(() => _selected = value),
                ),
              const SizedBox(height: 14),
              if (materials.isEmpty)
                _Empty(
                  text: isTeacher
                      ? 'No materials uploaded yet. Tap Upload to add.'
                      : 'No materials uploaded for this course yet.',
                )
              else
                for (final material in materials)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _MaterialCard(
                      material: material,
                      onDelete: isTeacher
                          ? () => AcademicStore.instance
                              .removeMaterial(material.id)
                          : null,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showAddSheet(
    BuildContext context,
    AssessmentCourse course,
  ) async {
    final titleController = TextEditingController();
    final refController = TextEditingController();
    MaterialKind kind = MaterialKind.link;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Add material',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<MaterialKind>(
                initialValue: kind,
                decoration: const InputDecoration(labelText: 'Type'),
                items: [
                  for (final k in MaterialKind.values)
                    DropdownMenuItem(value: k, child: Text(k.label)),
                ],
                onChanged: (value) =>
                    setSheetState(() => kind = value ?? kind),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: refController,
                minLines: 2,
                maxLines: 4,
                decoration: InputDecoration(
                  labelText:
                      kind == MaterialKind.note ? 'Note text' : 'URL / path',
                ),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  AcademicStore.instance.addMaterial(
                    courseId: course.id,
                    title: titleController.text.trim(),
                    kind: kind,
                    reference: refController.text.trim(),
                    teacherName: widget.teacher?.name ?? 'Teacher',
                  );
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.save_outlined),
                label: const Text('Save'),
              ),
            ],
          ),
        ),
      ),
    );
    titleController.dispose();
    refController.dispose();
  }
}

class _MaterialCard extends StatelessWidget {
  const _MaterialCard({required this.material, this.onDelete});
  final CourseMaterial material;
  final VoidCallback? onDelete;
  @override
  Widget build(BuildContext context) {
    final iconForKind = switch (material.kind) {
      MaterialKind.slides => Icons.slideshow_outlined,
      MaterialKind.pdf => Icons.picture_as_pdf_rounded,
      MaterialKind.link => Icons.link_rounded,
      MaterialKind.note => Icons.notes_rounded,
    };
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1E0),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(iconForKind, color: const Color(0xFFB45309)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  material.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                Text(
                  material.reference,
                  style: const TextStyle(
                      color: PortalColors.subtleText, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '${material.kind.label} • ${material.teacherName} • ${DateFormat('dd MMM yyyy').format(material.uploadedAt)}',
                  style: const TextStyle(
                      color: PortalColors.subtleText, fontSize: 11),
                ),
              ],
            ),
          ),
          if (onDelete != null)
            IconButton(
              onPressed: onDelete,
              tooltip: 'Remove',
              icon: const Icon(Icons.delete_outline),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// Announcements — teacher/admin post; everyone reads.
// ============================================================================
class AnnouncementsModule extends StatefulWidget {
  const AnnouncementsModule({
    super.key,
    required this.canPost,
    this.authorName,
  });

  final bool canPost;
  final String? authorName;

  @override
  State<AnnouncementsModule> createState() => _AnnouncementsModuleState();
}

class _AnnouncementsModuleState extends State<AnnouncementsModule> {
  @override
  Widget build(BuildContext context) {
    final store = AcademicStore.instance;
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final items = [...store.announcements];
        items.sort((a, b) {
          if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
          return b.postedAt.compareTo(a.postedAt);
        });
        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(title: const Text('Announcements')),
          floatingActionButton: widget.canPost
              ? FloatingActionButton.extended(
                  onPressed: _showPostSheet,
                  icon: const Icon(Icons.campaign_outlined),
                  label: const Text('Post'),
                )
              : null,
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              if (items.isEmpty)
                const _Empty(text: 'No announcements yet.')
              else
                for (final ann in items)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _AnnouncementCard(
                      announcement: ann,
                      onDelete: widget.canPost
                          ? () => store.deleteAnnouncement(ann.id)
                          : null,
                    ),
                  ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showPostSheet() async {
    final titleController = TextEditingController();
    final bodyController = TextEditingController();
    bool pinned = false;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 18,
          right: 18,
          top: 18,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 18,
        ),
        child: StatefulBuilder(
          builder: (ctx, setSheetState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'New announcement',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: titleController,
                decoration: const InputDecoration(labelText: 'Title'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: bodyController,
                minLines: 3,
                maxLines: 8,
                decoration: const InputDecoration(labelText: 'Body'),
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: pinned,
                onChanged: (v) =>
                    setSheetState(() => pinned = v ?? false),
                title: const Text('Pin to top'),
                controlAffinity: ListTileControlAffinity.leading,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: () {
                  if (titleController.text.trim().isEmpty) return;
                  AcademicStore.instance.post(
                    title: titleController.text.trim(),
                    body: bodyController.text.trim(),
                    author: widget.authorName ?? 'Faculty',
                    pinned: pinned,
                  );
                  Navigator.pop(ctx);
                },
                icon: const Icon(Icons.send_outlined),
                label: const Text('Post'),
              ),
            ],
          ),
        ),
      ),
    );
    titleController.dispose();
    bodyController.dispose();
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({required this.announcement, this.onDelete});
  final Announcement announcement;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: announcement.pinned
              ? const Color(0xFFB91C1C)
              : PortalColors.cardBorder,
          width: announcement.pinned ? 1.4 : 1.0,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (announcement.pinned)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEE2E2),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: const Text(
                    'PINNED',
                    style: TextStyle(
                      color: Color(0xFFB91C1C),
                      fontWeight: FontWeight.w800,
                      fontSize: 10,
                    ),
                  ),
                ),
              if (announcement.pinned) const SizedBox(width: 8),
              Expanded(
                child: Text(
                  announcement.title,
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
              ),
              if (onDelete != null)
                IconButton(
                  onPressed: onDelete,
                  tooltip: 'Delete',
                  icon: const Icon(Icons.delete_outline, size: 20),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            announcement.body,
            style: const TextStyle(height: 1.5),
          ),
          const SizedBox(height: 8),
          Text(
            '${announcement.author} • ${DateFormat('dd MMM yyyy HH:mm').format(announcement.postedAt)}',
            style: const TextStyle(
                color: PortalColors.subtleText, fontSize: 11),
          ),
        ],
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.text});
  final String text;
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Text(text, style: const TextStyle(color: PortalColors.subtleText)),
    );
  }
}
