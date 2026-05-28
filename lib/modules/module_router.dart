import 'package:flutter/material.dart';

import '../assessment/assessment_models.dart';
import '../features/feature_catalog.dart';
import '../fyp/fyp_models.dart';
import '../fyp/fyp_section.dart';
import '../fyp/fyp_teacher_section.dart';
import '../internships/internships_section.dart';
import '../models/student_record.dart';
import '../services/app_repository.dart';
import 'grades_module.dart';
import 'modules_common.dart';
import 'tier1_modules.dart';

/// Central place that maps a [FeatureKey] to a screen widget.
/// Both student and teacher dashboards use this so they share behavior.
class ModuleRouter {
  ModuleRouter._();

  /// Open [feature] in a new route. Either [student] or [teacher] must be
  /// provided depending on which dashboard launched it.
  static void open(
    BuildContext context, {
    required FeatureKey feature,
    required AppRepository repository,
    StudentRecord? student,
    AssessmentTeacher? teacher,
  }) {
    final builder = _routeBuilder(
      feature: feature,
      repository: repository,
      student: student,
      teacher: teacher,
    );
    Navigator.of(context).push(MaterialPageRoute(builder: builder));
  }

  static WidgetBuilder _routeBuilder({
    required FeatureKey feature,
    required AppRepository repository,
    StudentRecord? student,
    AssessmentTeacher? teacher,
  }) {
    switch (feature) {
      case FeatureKey.grades:
        return (_) => student != null
            ? GradesModule(repository: repository, student: student)
            : _teacherGradesReadout(repository, teacher!);
      case FeatureKey.timeTable:
        return (_) => TimeTableModule(
              repository: repository,
              student: student,
              teacher: teacher,
            );
      case FeatureKey.classAttendance:
        return (_) => ClassAttendanceModule(
              repository: repository,
              student: student,
              teacher: teacher,
            );
      case FeatureKey.courseMaterials:
        return (_) => CourseMaterialsModule(
              repository: repository,
              student: student,
              teacher: teacher,
            );
      case FeatureKey.announcements:
        return (_) => AnnouncementsModule(
              canPost: teacher != null,
              authorName: teacher?.name ?? 'Faculty',
            );
      case FeatureKey.fyp:
        if (student != null) {
          return (_) => FypSection(
                repository: repository,
                student: student,
                initialPhase: FypPhase.fyp1,
              );
        }
        return (_) => FypTeacherSection(teacher: teacher!);
      case FeatureKey.internships:
        return (_) => const InternshipsSection();
      case FeatureKey.feeVoucher:
        return (_) => const ModuleComingSoonScreen(
              title: 'Fee Voucher',
              description:
                  'Generate a bank-printable fee voucher PDF, view dues and payment history.',
              icon: Icons.receipt_long_outlined,
              color: Color(0xFF0F766E),
              bulletPoints: [
                'Outstanding balance & per-component breakdown (tuition, library, hostel)',
                'Voucher PDF with university header and barcoded reference',
                'Last 5 payments with date and challan number',
              ],
            );
      case FeatureKey.digitalIdCard:
        return (_) => student != null
            ? _DigitalIdCardScreen(student: student)
            : const ModuleComingSoonScreen(
                title: 'Digital Student ID',
                description: 'Student-only module.',
                icon: Icons.badge_outlined,
                color: Color(0xFF2948B7),
              );
      case FeatureKey.documentCenter:
        return (_) => const ModuleComingSoonScreen(
              title: 'Document Center',
              description:
                  'Generate official documents (bonafide letter, character certificate, NOC, degree-progress letter).',
              icon: Icons.assignment_outlined,
              color: Color(0xFF6E27C5),
              bulletPoints: [
                'Pick a document type → fill any extra fields',
                'PDF auto-signed digitally by HoD via the existing QR flow',
                'Request log so students can track approval status',
              ],
            );
      case FeatureKey.academicCalendar:
        return (_) => const ModuleComingSoonScreen(
              title: 'Academic Calendar',
              description:
                  'Term start/end dates, exam weeks, registered holidays, FYP milestone deadlines.',
              icon: Icons.event_note_outlined,
              color: Color(0xFFB45309),
              bulletPoints: [
                'Month grid + agenda view',
                'Admin uploads the calendar JSON; everyone reads',
                'Adds reminders to the in-app notifications hub',
              ],
            );
      case FeatureKey.notificationsHub:
        return (_) => const ModuleComingSoonScreen(
              title: 'Notifications',
              description:
                  'A real inbox behind the top-bar bell — assessment posted, FYP graded, fee deadline, etc.',
              icon: Icons.notifications_outlined,
              color: Color(0xFFB91C1C),
              bulletPoints: [
                'Per-event preferences (mute / push / email)',
                'Tap-through deeplink to the originating record',
                'Backed by Firebase Cloud Messaging once persistence lands',
              ],
            );
      case FeatureKey.library:
        return (_) => const ModuleComingSoonScreen(
              title: 'Library',
              description:
                  'Search books, view borrowed items, reserve seats, renew loans.',
              icon: Icons.local_library_outlined,
              color: Color(0xFF0F766E),
              bulletPoints: [
                'Catalogue search with availability',
                'My borrowed items with due dates and fine accruals',
                'QR issue at the front desk (same scanner used elsewhere)',
              ],
            );
      case FeatureKey.hostelTransport:
        return (_) => const ModuleComingSoonScreen(
              title: 'Hostel & Transport',
              description:
                  'Hostel room allocation, mess menu, bus routes, transport pass renewal.',
              icon: Icons.directions_bus_outlined,
              color: Color(0xFF2948B7),
              bulletPoints: [
                'Hostel block / room / roommate listing',
                'Bus routes with live stop ETA',
                'Pass renewal — fee voucher integration',
              ],
            );
      case FeatureKey.clearance:
        return (_) => const ModuleComingSoonScreen(
              title: 'Clearance Form',
              description:
                  'Pre-graduation departmental clearance signed by library, fee office, HoD and dean.',
              icon: Icons.task_alt_outlined,
              color: Color(0xFF6E27C5),
              bulletPoints: [
                'Each office signs digitally (same flow as supervisor consent)',
                'Final clearance PDF released after all offices sign',
                'Progress tracker so the student knows what is pending',
              ],
            );
      case FeatureKey.feedback:
        return (_) => const ModuleComingSoonScreen(
              title: 'Course Feedback',
              description:
                  'Anonymous end-of-semester course evaluation form, results visible to admin only.',
              icon: Icons.rate_review_outlined,
              color: Color(0xFFB45309),
              bulletPoints: [
                'Rubric mirrors the FYP evaluation pattern',
                'Anonymity guaranteed — submission carries no roll number',
                'Admin aggregate dashboard per teacher / course',
              ],
            );
      case FeatureKey.messages:
        return (_) => const ModuleComingSoonScreen(
              title: 'Messages',
              description: 'Direct chat between student, teacher and admin.',
              icon: Icons.chat_bubble_outline,
              color: Color(0xFF2948B7),
              bulletPoints: [
                '1:1 threads with read receipts',
                'Threads scoped to a course or FYP group',
                'Push notifications via the existing notification hub',
              ],
            );
      case FeatureKey.counseling:
        return (_) => const ModuleComingSoonScreen(
              title: 'Counselling',
              description:
                  'Confidential counselling appointment booking with the on-campus counsellor.',
              icon: Icons.psychology_outlined,
              color: Color(0xFF0F766E),
              bulletPoints: [
                'Calendar with the counsellor\'s open slots',
                'Brief intake form (mood, urgency, preferred mode)',
                'Confirmation token shown only to the student',
              ],
            );
      case FeatureKey.clubs:
        return (_) => const ModuleComingSoonScreen(
              title: 'Clubs & Societies',
              description:
                  'Browse, join clubs, see their upcoming events, RSVP.',
              icon: Icons.diversity_3_outlined,
              color: Color(0xFF6E27C5),
              bulletPoints: [
                'Per-club page with leads, upcoming events, members count',
                'One-tap join request approved by the club lead',
                'Event RSVP wired to the notifications hub',
              ],
            );
      case FeatureKey.placement:
        return (_) => const ModuleComingSoonScreen(
              title: 'Placement Cell',
              description:
                  'On-campus recruiting drives, alumni mentor network, internship leads.',
              icon: Icons.business_center_outlined,
              color: Color(0xFFB45309),
              bulletPoints: [
                'Active drives with company profile and rounds',
                'CV upload + per-drive eligibility filter',
                'Mentor matchmaking with alumni',
              ],
            );
    }
  }

  /// Tiny placeholder for the teacher's grades view — they can already view
  /// per-assessment marks via Live/Results, so this is just a redirect note.
  static Widget _teacherGradesReadout(
    AppRepository repository,
    AssessmentTeacher teacher,
  ) {
    return const ModuleComingSoonScreen(
      title: 'Grades (teacher view)',
      description:
          'Teacher-side grade compilation. You can already enter and view per-assessment marks under Live / Results inside the assessment app.',
      icon: Icons.grade_outlined,
      color: Color(0xFF2948B7),
      bulletPoints: [
        'Bulk import marks from CSV',
        'Per-course gradebook with weighted aggregation',
        'Publish to students once finalized',
      ],
    );
  }
}

/// Lightweight digital ID card so the Tier-2 toggle has at least one
/// student-visible feature with a real screen.
class _DigitalIdCardScreen extends StatelessWidget {
  const _DigitalIdCardScreen({required this.student});
  final StudentRecord student;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5FB),
      appBar: AppBar(title: const Text('Digital Student ID')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(22),
                gradient: const LinearGradient(
                  colors: [Color(0xFF12343B), Color(0xFF2948B7)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x441F2A44),
                    blurRadius: 30,
                    offset: Offset(0, 18),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      const Icon(Icons.school_rounded,
                          color: Colors.white, size: 32),
                      const SizedBox(width: 10),
                      const Expanded(
                        child: Text(
                          'AUST Student Card',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  CircleAvatar(
                    radius: 44,
                    backgroundColor: Colors.white.withValues(alpha: 0.18),
                    child: const Icon(Icons.person, color: Colors.white, size: 50),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    student.studentName,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                  Text(
                    student.rollNo,
                    style: const TextStyle(
                      color: Color(0xFFEFF6FF),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                    ),
                  ),
                  const SizedBox(height: 18),
                  _idRow('Program', student.program),
                  _idRow('Semester', '${student.semester}${student.section}'),
                  _idRow('Session', student.currentSession),
                  const SizedBox(height: 18),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.qr_code_2_rounded,
                      size: 90,
                      color: Color(0xFF12343B),
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Show this code at the exam hall / library / hostel entry.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Color(0xFFEFF6FF), fontSize: 11),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _idRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 100,
            child: Text(
              label,
              style: const TextStyle(
                color: Color(0xFFB7C7FF),
                fontWeight: FontWeight.w700,
                fontSize: 12,
              ),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '—' : value,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
