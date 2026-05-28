import 'package:flutter/material.dart';

import '../ui/student_portal_shell.dart';

class InternshipsSection extends StatelessWidget {
  const InternshipsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(
        title: const Text('Internships'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Container(
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: PortalColors.cardBorder),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [
                        Color(0xFFFFB46B),
                        Color(0xFFFF6B6B),
                      ],
                    ),
                  ),
                  child: const Icon(
                    Icons.work_outline_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Internships module',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: PortalColors.textPrimary,
                      ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Coming soon. This module will list available internship opportunities and let students submit applications and proformas, similar to the FYP flow.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: PortalColors.subtleText,
                    height: 1.45,
                  ),
                ),
                const SizedBox(height: 18),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded),
                  label: const Text('Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
