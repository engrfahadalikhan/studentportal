import 'package:flutter/material.dart';

/// All modules that can be shown/hidden via the admin Feature Controls panel.
/// The key is what's stored on disk (snake_case so existing
/// `FeatureVisibility.fromMap` migrations stay readable).
enum FeatureKey {
  // ---- Tier 1: data-driven extensions of existing tables ------------------
  grades,
  timeTable,
  classAttendance,
  courseMaterials,
  announcements,
  // ---- Tier 2: common academic needs --------------------------------------
  feeVoucher,
  digitalIdCard,
  documentCenter,
  academicCalendar,
  notificationsHub,
  // ---- Tier 3: student-life --------------------------------------------------
  internships,
  library,
  hostelTransport,
  clearance,
  feedback,
  // ---- Tier 4: communication & engagement ---------------------------------
  messages,
  counseling,
  clubs,
  placement,
  // ---- Existing core modules (admin can also hide these) ------------------
  fyp,
}

extension FeatureKeyX on FeatureKey {
  String get storageKey {
    switch (this) {
      case FeatureKey.grades:
        return 'grades';
      case FeatureKey.timeTable:
        return 'time_table';
      case FeatureKey.classAttendance:
        return 'class_attendance';
      case FeatureKey.courseMaterials:
        return 'course_materials';
      case FeatureKey.announcements:
        return 'announcements';
      case FeatureKey.feeVoucher:
        return 'fee_voucher';
      case FeatureKey.digitalIdCard:
        return 'digital_id_card';
      case FeatureKey.documentCenter:
        return 'document_center';
      case FeatureKey.academicCalendar:
        return 'academic_calendar';
      case FeatureKey.notificationsHub:
        return 'notifications_hub';
      case FeatureKey.internships:
        return 'internships';
      case FeatureKey.library:
        return 'library';
      case FeatureKey.hostelTransport:
        return 'hostel_transport';
      case FeatureKey.clearance:
        return 'clearance';
      case FeatureKey.feedback:
        return 'feedback';
      case FeatureKey.messages:
        return 'messages';
      case FeatureKey.counseling:
        return 'counseling';
      case FeatureKey.clubs:
        return 'clubs';
      case FeatureKey.placement:
        return 'placement';
      case FeatureKey.fyp:
        return 'fyp';
    }
  }

  static FeatureKey? fromStorageKey(String key) {
    for (final feature in FeatureKey.values) {
      if (feature.storageKey == key) return feature;
    }
    return null;
  }
}

enum FeatureAudience { student, teacher, both }

class FeatureMeta {
  const FeatureMeta({
    required this.key,
    required this.label,
    required this.description,
    required this.icon,
    required this.color,
    required this.audience,
    required this.tier,
  });

  final FeatureKey key;
  final String label;
  final String description;
  final IconData icon;
  final Color color;
  final FeatureAudience audience;
  final int tier;
}

/// All module metadata in one place. The admin Feature Controls page reads
/// this list to render its toggles.
const List<FeatureMeta> featureCatalog = [
  // Tier 1
  FeatureMeta(
    key: FeatureKey.grades,
    label: 'Grades & Transcripts',
    description:
        'Students view per-course marks, semester GPA and download an official transcript PDF.',
    icon: Icons.grade_outlined,
    color: Color(0xFF2948B7),
    audience: FeatureAudience.both,
    tier: 1,
  ),
  FeatureMeta(
    key: FeatureKey.timeTable,
    label: 'Time Table',
    description:
        'Weekly class schedule per student or teacher, pulled from the course registration list.',
    icon: Icons.calendar_view_week_outlined,
    color: Color(0xFF0F766E),
    audience: FeatureAudience.both,
    tier: 1,
  ),
  FeatureMeta(
    key: FeatureKey.classAttendance,
    label: 'Class Attendance',
    description:
        'Per-course attendance (different from QR exam attendance). Teacher marks daily; student sees %.',
    icon: Icons.fact_check_outlined,
    color: Color(0xFF6E27C5),
    audience: FeatureAudience.both,
    tier: 1,
  ),
  FeatureMeta(
    key: FeatureKey.courseMaterials,
    label: 'Course Materials',
    description: 'Teacher uploads slides/PDFs/links per course, students download.',
    icon: Icons.menu_book_outlined,
    color: Color(0xFFB45309),
    audience: FeatureAudience.both,
    tier: 1,
  ),
  FeatureMeta(
    key: FeatureKey.announcements,
    label: 'Announcements',
    description: 'Department/course notice board with pinned items.',
    icon: Icons.campaign_outlined,
    color: Color(0xFFB91C1C),
    audience: FeatureAudience.both,
    tier: 1,
  ),
  // Tier 2
  FeatureMeta(
    key: FeatureKey.feeVoucher,
    label: 'Fee Voucher',
    description: 'Outstanding fee summary + bank-printable PDF voucher.',
    icon: Icons.receipt_long_outlined,
    color: Color(0xFF0F766E),
    audience: FeatureAudience.student,
    tier: 2,
  ),
  FeatureMeta(
    key: FeatureKey.digitalIdCard,
    label: 'Digital Student ID',
    description: 'On-screen ID with QR for hall entry verification.',
    icon: Icons.badge_outlined,
    color: Color(0xFF2948B7),
    audience: FeatureAudience.student,
    tier: 2,
  ),
  FeatureMeta(
    key: FeatureKey.documentCenter,
    label: 'Document Center',
    description: 'Generate bonafide letter, character certificate, NOC etc.',
    icon: Icons.assignment_outlined,
    color: Color(0xFF6E27C5),
    audience: FeatureAudience.both,
    tier: 2,
  ),
  FeatureMeta(
    key: FeatureKey.academicCalendar,
    label: 'Academic Calendar',
    description: 'Term start/end, exam weeks, holidays, FYP milestones.',
    icon: Icons.event_note_outlined,
    color: Color(0xFFB45309),
    audience: FeatureAudience.both,
    tier: 2,
  ),
  FeatureMeta(
    key: FeatureKey.notificationsHub,
    label: 'Notifications',
    description:
        'Real backing for the bell icon — assessment posted, FYP graded, fee deadline.',
    icon: Icons.notifications_outlined,
    color: Color(0xFFB91C1C),
    audience: FeatureAudience.both,
    tier: 2,
  ),
  // Tier 3
  FeatureMeta(
    key: FeatureKey.internships,
    label: 'Internships',
    description:
        'Companies/openings, application form, supervisor allocation, evaluation rubric, weekly log.',
    icon: Icons.work_outline_rounded,
    color: Color(0xFFFF6B6B),
    audience: FeatureAudience.both,
    tier: 3,
  ),
  FeatureMeta(
    key: FeatureKey.library,
    label: 'Library',
    description: 'Search books, view borrowed items, due dates.',
    icon: Icons.local_library_outlined,
    color: Color(0xFF0F766E),
    audience: FeatureAudience.student,
    tier: 3,
  ),
  FeatureMeta(
    key: FeatureKey.hostelTransport,
    label: 'Hostel & Transport',
    description: 'Room allocation, bus route + transport pass.',
    icon: Icons.directions_bus_outlined,
    color: Color(0xFF2948B7),
    audience: FeatureAudience.student,
    tier: 3,
  ),
  FeatureMeta(
    key: FeatureKey.clearance,
    label: 'Clearance Form',
    description:
        'Pre-graduation clearance signed by library, fee office, HoD, etc.',
    icon: Icons.task_alt_outlined,
    color: Color(0xFF6E27C5),
    audience: FeatureAudience.both,
    tier: 3,
  ),
  FeatureMeta(
    key: FeatureKey.feedback,
    label: 'Course Feedback',
    description: 'Anonymous end-of-semester course evaluation.',
    icon: Icons.rate_review_outlined,
    color: Color(0xFFB45309),
    audience: FeatureAudience.both,
    tier: 3,
  ),
  // Tier 4
  FeatureMeta(
    key: FeatureKey.messages,
    label: 'Messages',
    description: 'Direct chat student ↔ teacher / admin.',
    icon: Icons.chat_bubble_outline,
    color: Color(0xFF2948B7),
    audience: FeatureAudience.both,
    tier: 4,
  ),
  FeatureMeta(
    key: FeatureKey.counseling,
    label: 'Counselling',
    description: 'Book counselling appointments with on-campus counsellor.',
    icon: Icons.psychology_outlined,
    color: Color(0xFF0F766E),
    audience: FeatureAudience.student,
    tier: 4,
  ),
  FeatureMeta(
    key: FeatureKey.clubs,
    label: 'Clubs & Societies',
    description: 'Browse, join clubs, see club events.',
    icon: Icons.diversity_3_outlined,
    color: Color(0xFF6E27C5),
    audience: FeatureAudience.student,
    tier: 4,
  ),
  FeatureMeta(
    key: FeatureKey.placement,
    label: 'Placement Cell',
    description: 'On-campus recruiting drives, alumni network.',
    icon: Icons.business_center_outlined,
    color: Color(0xFFB45309),
    audience: FeatureAudience.student,
    tier: 4,
  ),
  // Existing core
  FeatureMeta(
    key: FeatureKey.fyp,
    label: 'Final Year Project',
    description:
        'The full FYP workflow — group form, ideas, allocation, proposal, SRS, consent, evaluation, meeting logs.',
    icon: Icons.school_outlined,
    color: Color(0xFF6E27C5),
    audience: FeatureAudience.both,
    tier: 1,
  ),
];

FeatureMeta featureMetaOf(FeatureKey key) {
  return featureCatalog.firstWhere((meta) => meta.key == key);
}
