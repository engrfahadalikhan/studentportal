import 'package:flutter/material.dart';

import '../services/app_repository.dart';
import '../services/assessment_access_service.dart';
import '../services/paper_tracker_access_service.dart';
import '../services/slot_collection_access_service.dart';
import '../ui/student_portal_shell.dart';

/// Admin module: per-teacher permissions. Switch a teacher ON for
/// "Create assessments" (the Assess tab) and/or "Answer-sheet tracker" (scan
/// program-stats QRs to issue/return marking envelopes). OFF = hidden for them.
class AssessmentAccessPage extends StatelessWidget {
  const AssessmentAccessPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    final teachers = repository.teachers;
    final assess = AssessmentAccessService.instance;
    final papers = PaperTrackerAccessService.instance;
    final slots = SlotCollectionAccessService.instance;
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Teacher Access')),
      body: AnimatedBuilder(
        animation: Listenable.merge([assess, papers, slots]),
        builder: (context, _) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PortalColors.softBlue,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: PortalColors.blueBorder),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline_rounded,
                        color: PortalColors.brandBlue, size: 20),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Allow each teacher to: create assessments, and/or use '
                        'the answer-sheet (marking envelope) tracker. OFF means '
                        'that feature is hidden for them.',
                        style: TextStyle(
                          color: PortalColors.textPrimary,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                child: Text(
                  'Assessments: ${assess.allowedCount} • Answer sheets: '
                  '${papers.allowedCount} • Per-slot: ${slots.allowedCount}  '
                  '(of ${teachers.length} teachers)',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: PortalColors.subtleText,
                    fontSize: 12.5,
                  ),
                ),
              ),
              if (teachers.isEmpty)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF8FAFC),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: PortalColors.cardBorder),
                  ),
                  child: const Text(
                    'No teachers found in the local data.',
                    style: TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12.5,
                    ),
                  ),
                )
              else
                for (final teacher in teachers)
                  _TeacherAccessTile(
                    name: teacher.name,
                    subtitle: teacher.email,
                    canAssess: assess.isAllowed(teacher.id),
                    canTrackPapers: papers.isAllowed(teacher.id),
                    canSlotCollect: slots.isAllowed(teacher.id),
                    onAssess: (v) => assess.setAllowed(teacher.id, v),
                    onTrackPapers: (v) => papers.setAllowed(teacher.id, v),
                    onSlotCollect: (v) => slots.setAllowed(teacher.id, v),
                  ),
            ],
          );
        },
      ),
    );
  }
}

class _TeacherAccessTile extends StatelessWidget {
  const _TeacherAccessTile({
    required this.name,
    required this.subtitle,
    required this.canAssess,
    required this.canTrackPapers,
    required this.canSlotCollect,
    required this.onAssess,
    required this.onTrackPapers,
    required this.onSlotCollect,
  });

  final String name;
  final String subtitle;
  final bool canAssess;
  final bool canTrackPapers;
  final bool canSlotCollect;
  final ValueChanged<bool> onAssess;
  final ValueChanged<bool> onTrackPapers;
  final ValueChanged<bool> onSlotCollect;

  @override
  Widget build(BuildContext context) {
    final anyOn = canAssess || canTrackPapers || canSlotCollect;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: anyOn
                ? const Color(0xFF047857).withValues(alpha: 0.45)
                : PortalColors.cardBorder,
          ),
        ),
        child: Column(
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  backgroundColor: PortalColors.softBlue,
                  child: Icon(
                    Icons.co_present_outlined,
                    color: PortalColors.brandBlue,
                    size: 18,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                      Text(
                        subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            _toggleRow(
              Icons.assignment_outlined,
              'Create assessments',
              canAssess,
              onAssess,
            ),
            _toggleRow(
              Icons.assignment_returned_outlined,
              'Answer-sheet tracker',
              canTrackPapers,
              onTrackPapers,
            ),
            _toggleRow(
              Icons.fact_check_outlined,
              'Per-slot collection',
              canSlotCollect,
              onSlotCollect,
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggleRow(
    IconData icon,
    String label,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return Row(
      children: [
        Icon(icon, size: 18, color: PortalColors.subtleText),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: PortalColors.textPrimary,
            ),
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}
