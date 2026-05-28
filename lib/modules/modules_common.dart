import 'package:flutter/material.dart';

import '../ui/student_portal_shell.dart';

/// Shared "Coming soon" screen used by stub Tier 2/3/4 modules. Each module
/// passes its label + description so the screen feels intentional rather than
/// like an unfinished page. When the admin enables a stub module, students or
/// teachers can navigate to it and see this screen; the next iteration will
/// replace the body with real functionality.
class ModuleComingSoonScreen extends StatelessWidget {
  const ModuleComingSoonScreen({
    super.key,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    this.bulletPoints = const [],
  });

  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<String> bulletPoints;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    color,
                    color.withValues(alpha: 0.7),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(22),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(18),
                    ),
                    child: Icon(icon, color: Colors.white, size: 30),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 22,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    description,
                    style: const TextStyle(
                      color: Color(0xFFF8FAFC),
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: PortalColors.cardBorder),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.construction_rounded,
                        color: Color(0xFFB45309),
                      ),
                      SizedBox(width: 10),
                      Text(
                        'Coming in the next release',
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          color: PortalColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'This module is wired into the admin Feature Controls. Once the data backend lands, this screen will replace its placeholder with the real workflow.',
                    style: TextStyle(color: PortalColors.subtleText, height: 1.5),
                  ),
                  if (bulletPoints.isNotEmpty) ...[
                    const SizedBox(height: 14),
                    const Text(
                      'What this module will include:',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final bullet in bulletPoints)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 7),
                              child: Icon(
                                Icons.fiber_manual_record,
                                size: 8,
                                color: PortalColors.subtleText,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                bullet,
                                style: const TextStyle(
                                  color: PortalColors.subtleText,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Helper that renders a grid of module cards. Used by both student and
/// teacher dashboards so they look identical and respect visibility flags.
class ModuleCardGrid extends StatelessWidget {
  const ModuleCardGrid({super.key, required this.cards});

  final List<ModuleCardData> cards;

  @override
  Widget build(BuildContext context) {
    if (cards.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF6E5),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFFFD8A8)),
        ),
        child: const Text(
          'No additional modules are enabled by the admin yet.',
          style: TextStyle(color: PortalColors.subtleText),
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final crossCount = constraints.maxWidth > 720
            ? 4
            : constraints.maxWidth > 480
                ? 3
                : 2;
        final tileWidth =
            (constraints.maxWidth - (crossCount - 1) * 10) / crossCount;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards)
              SizedBox(
                width: tileWidth,
                child: _ModuleTile(card: card),
              ),
          ],
        );
      },
    );
  }
}

class ModuleCardData {
  const ModuleCardData({
    required this.title,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  final String title;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
}

class _ModuleTile extends StatelessWidget {
  const _ModuleTile({required this.card});
  final ModuleCardData card;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: card.onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: PortalColors.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: card.color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(card.icon, color: card.color),
              ),
              const SizedBox(height: 10),
              Text(
                card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: PortalColors.textPrimary,
                  fontSize: 13,
                  height: 1.25,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
