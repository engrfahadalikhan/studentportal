import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../ui/student_portal_shell.dart';
import 'feature_catalog.dart';
import 'feature_visibility_service.dart';

/// Admin-only screen. Lets the admin toggle each module on/off for students
/// and teachers independently. Persists to SharedPreferences instantly.
class AdminFeatureControlsPage extends StatelessWidget {
  const AdminFeatureControlsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final service = FeatureVisibilityService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        final grouped = <int, List<FeatureMeta>>{};
        for (final meta in featureCatalog) {
          grouped.putIfAbsent(meta.tier, () => []).add(meta);
        }
        final tiers = grouped.keys.toList()..sort();

        return Scaffold(
          backgroundColor: PortalColors.pageBackground,
          appBar: AppBar(
            title: const Text('Feature Controls'),
            actions: [
              TextButton.icon(
                onPressed: () async {
                  final ok = await showDialog<bool>(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('Reset visibility?'),
                      content: const Text(
                        'This will return every module to its default visibility for students and teachers.',
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx, false),
                          child: const Text('Cancel'),
                        ),
                        FilledButton(
                          onPressed: () => Navigator.pop(ctx, true),
                          child: const Text('Reset'),
                        ),
                      ],
                    ),
                  );
                  if (ok == true) {
                    await service.resetToDefaults();
                  }
                },
                icon: const Icon(Icons.restart_alt_rounded),
                label: const Text('Reset'),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _IntroBanner(
                visibleCountForStudent: service
                    .visibleFor(AppRole.student)
                    .length,
                visibleCountForTeacher: service
                    .visibleFor(AppRole.faculty)
                    .length,
              ),
              const SizedBox(height: 18),
              for (final tier in tiers) ...[
                _TierHeading(tier: tier),
                const SizedBox(height: 8),
                for (final meta in grouped[tier]!)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _FeatureRow(meta: meta, service: service),
                  ),
                const SizedBox(height: 6),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _IntroBanner extends StatelessWidget {
  const _IntroBanner({
    required this.visibleCountForStudent,
    required this.visibleCountForTeacher,
  });

  final int visibleCountForStudent;
  final int visibleCountForTeacher;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5C63), Color(0xFF1F7A8C)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Module visibility',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w800,
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            'Toggle each module to control whether students or teachers can see it. Admin always sees everything.',
            style: TextStyle(color: Color(0xFFEFFBFC), height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: _StatPill(
                  label: 'Visible to students',
                  value: '$visibleCountForStudent',
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _StatPill(
                  label: 'Visible to teachers',
                  value: '$visibleCountForTeacher',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w900,
              fontSize: 22,
            ),
          ),
          const SizedBox(height: 2),
          Text(label, style: const TextStyle(color: Color(0xFFEFFBFC))),
        ],
      ),
    );
  }
}

class _TierHeading extends StatelessWidget {
  const _TierHeading({required this.tier});
  final int tier;

  @override
  Widget build(BuildContext context) {
    final label = switch (tier) {
      1 => 'Tier 1 — Core academic',
      2 => 'Tier 2 — Common needs',
      3 => 'Tier 3 — Student life',
      4 => 'Tier 4 — Communication',
      _ => 'Tier $tier',
    };
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: Text(
        label.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w800,
          color: Color(0xFF5A5E72),
          letterSpacing: 0.8,
          fontSize: 12,
        ),
      ),
    );
  }
}

class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.meta, required this.service});
  final FeatureMeta meta;
  final FeatureVisibilityService service;

  @override
  Widget build(BuildContext context) {
    final studentApplicable = meta.audience != FeatureAudience.teacher;
    final teacherApplicable = meta.audience != FeatureAudience.student;

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
          Row(
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(meta.icon, color: meta.color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      meta.description,
                      style: const TextStyle(
                        color: PortalColors.subtleText,
                        fontSize: 12,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _RoleToggle(
                  label: 'Students',
                  applicable: studentApplicable,
                  value: studentApplicable && service.studentFlag(meta.key),
                  onChanged: studentApplicable
                      ? (value) => service.setVisibility(
                            feature: meta.key,
                            role: AppRole.student,
                            visible: value,
                          )
                      : null,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _RoleToggle(
                  label: 'Teachers',
                  applicable: teacherApplicable,
                  value: teacherApplicable && service.teacherFlag(meta.key),
                  onChanged: teacherApplicable
                      ? (value) => service.setVisibility(
                            feature: meta.key,
                            role: AppRole.faculty,
                            visible: value,
                          )
                      : null,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RoleToggle extends StatelessWidget {
  const _RoleToggle({
    required this.label,
    required this.applicable,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final bool applicable;
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: !applicable
            ? const Color(0xFFF1F5F9)
            : (value
                ? const Color(0xFFEAFBEF)
                : const Color(0xFFFFF3F3)),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: !applicable
              ? PortalColors.cardBorder
              : (value
                  ? const Color(0xFFB9F4C9)
                  : const Color(0xFFF4C9C9)),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              applicable ? label : '$label (n/a)',
              style: TextStyle(
                fontWeight: FontWeight.w700,
                color: applicable
                    ? PortalColors.textPrimary
                    : PortalColors.subtleText,
              ),
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}
