import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../models/app_user_profile.dart';
import '../models/feature_visibility.dart';
import '../services/app_repository.dart';

final List<FeatureDefinition> facultyFeatures = [
  const FeatureDefinition(
    key: 'course_manager',
    title: 'Course Manager',
    description:
        'Create outlines, organize modules, and keep lesson plans ready.',
    icon: Icons.menu_book_rounded,
  ),
  const FeatureDefinition(
    key: 'attendance_entry',
    title: 'Attendance Entry',
    description: 'Record attendance with a cleaner, faster classroom flow.',
    icon: Icons.how_to_reg_rounded,
  ),
  const FeatureDefinition(
    key: 'grading_tools',
    title: 'Grading Tools',
    description: 'Review submissions and publish marks without extra steps.',
    icon: Icons.fact_check_rounded,
  ),
  const FeatureDefinition(
    key: 'materials_center',
    title: 'Materials Center',
    description: 'Upload notes, resources, and session handouts for students.',
    icon: Icons.folder_copy_rounded,
  ),
  const FeatureDefinition(
    key: 'schedule_board',
    title: 'Schedule Board',
    description: 'Track classes, room assignments, and timing changes.',
    icon: Icons.calendar_month_rounded,
  ),
];

final List<FeatureDefinition> studentFeatures = [
  const FeatureDefinition(
    key: 'announcements',
    title: 'Announcements',
    description: 'Stay updated on campus notices, deadlines, and alerts.',
    icon: Icons.campaign_rounded,
  ),
  const FeatureDefinition(
    key: 'assignments',
    title: 'Assignments',
    description:
        'Follow due dates, upload work, and monitor submission status.',
    icon: Icons.assignment_rounded,
  ),
  const FeatureDefinition(
    key: 'attendance_view',
    title: 'Attendance',
    description: 'Review attendance percentage and class-by-class records.',
    icon: Icons.timeline_rounded,
  ),
  const FeatureDefinition(
    key: 'results',
    title: 'Results',
    description: 'Check marks, grade summaries, and academic performance.',
    icon: Icons.bar_chart_rounded,
  ),
  const FeatureDefinition(
    key: 'schedule_board',
    title: 'Schedule Board',
    description: 'See your timetable, room details, and session updates.',
    icon: Icons.event_note_rounded,
  ),
];

class DashboardPage extends StatelessWidget {
  const DashboardPage({
    super.key,
    required this.repository,
    required this.profile,
    required this.visibility,
    required this.users,
  });

  final AppRepository repository;
  final AppUserProfile profile;
  final FeatureVisibility visibility;
  final List<AppUserProfile> users;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Student Portal'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Chip(
              avatar: const Icon(Icons.verified_user_rounded, size: 18),
              label: Text(profile.role.label),
            ),
          ),
          IconButton(
            tooltip: 'Logout',
            onPressed: () async {
              await repository.signOut();
            },
            icon: const Icon(Icons.logout_rounded),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1200),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                HeroBanner(profile: profile),
                const SizedBox(height: 24),
                if (profile.role == AppRole.admin)
                  AdminDashboard(
                    repository: repository,
                    visibility: visibility,
                    users: users,
                  )
                else
                  RoleWorkspace(profile: profile, visibility: visibility),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class AdminDashboard extends StatelessWidget {
  const AdminDashboard({
    super.key,
    required this.repository,
    required this.visibility,
    required this.users,
  });

  final AppRepository repository;
  final FeatureVisibility visibility;
  final List<AppUserProfile> users;

  @override
  Widget build(BuildContext context) {
    final adminCount = users.where((user) => user.role == AppRole.admin).length;
    final facultyCount = users
        .where((user) => user.role == AppRole.faculty)
        .length;
    final studentCount = users
        .where((user) => user.role == AppRole.student)
        .length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            StatCard(
              title: 'Admins',
              value: '$adminCount',
              subtitle: 'Power users with portal control',
              color: const Color(0xFF0D5C63),
              icon: Icons.admin_panel_settings_rounded,
            ),
            StatCard(
              title: 'Faculty',
              value: '$facultyCount',
              subtitle: 'Teaching accounts in the system',
              color: const Color(0xFF1F7A8C),
              icon: Icons.co_present_rounded,
            ),
            StatCard(
              title: 'Students',
              value: '$studentCount',
              subtitle: 'Learners currently onboarded',
              color: const Color(0xFFB8860B),
              icon: Icons.school_rounded,
            ),
          ],
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'Faculty feature controls',
          subtitle: 'Enable or disable modules shown on faculty accounts.',
        ),
        const SizedBox(height: 14),
        FeatureToggleCard(
          role: AppRole.faculty,
          features: facultyFeatures,
          visibility: visibility,
          repository: repository,
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'Student feature controls',
          subtitle: 'Choose what students can currently see inside the portal.',
        ),
        const SizedBox(height: 14),
        FeatureToggleCard(
          role: AppRole.student,
          features: studentFeatures,
          visibility: visibility,
          repository: repository,
        ),
        const SizedBox(height: 24),
        const SectionTitle(
          title: 'Registered users',
          subtitle: 'Quick view of the people already connected to Firebase.',
        ),
        const SizedBox(height: 14),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: users.isEmpty
                ? const Text('No users have signed up yet.')
                : Column(
                    children: users.take(8).map((user) {
                      final initial = user.name.isNotEmpty
                          ? user.name.characters.first.toUpperCase()
                          : '?';

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          children: [
                            CircleAvatar(
                              backgroundColor: const Color(0xFFE7F1F1),
                              child: Text(
                                initial,
                                style: const TextStyle(
                                  color: Color(0xFF0D5C63),
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    user.name,
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleSmall
                                        ?.copyWith(fontWeight: FontWeight.w700),
                                  ),
                                  Text(user.email),
                                ],
                              ),
                            ),
                            Chip(label: Text(user.role.label)),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
          ),
        ),
      ],
    );
  }
}

class RoleWorkspace extends StatelessWidget {
  const RoleWorkspace({
    super.key,
    required this.profile,
    required this.visibility,
  });

  final AppUserProfile profile;
  final FeatureVisibility visibility;

  @override
  Widget build(BuildContext context) {
    final featureSet = profile.role == AppRole.faculty
        ? facultyFeatures
        : studentFeatures;
    final available = featureSet
        .where((feature) => visibility.isEnabled(profile.role, feature.key))
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionTitle(
          title: profile.role == AppRole.faculty
              ? 'Faculty workspace'
              : 'Student workspace',
          subtitle:
              'Only the features enabled by Admin are shown below for your role.',
        ),
        const SizedBox(height: 14),
        if (available.isEmpty)
          const Card(
            child: Padding(
              padding: EdgeInsets.all(24),
              child: Text(
                'No modules are enabled right now. Ask your admin to turn features on for this role.',
              ),
            ),
          )
        else
          Wrap(
            spacing: 16,
            runSpacing: 16,
            children: available.map((feature) {
              return SizedBox(
                width: 330,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF3F4),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Icon(
                            feature.icon,
                            color: const Color(0xFF0D5C63),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          feature.title,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        Text(feature.description),
                        const SizedBox(height: 16),
                        TextButton.icon(
                          onPressed: () {},
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: const Text('Open module'),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
      ],
    );
  }
}

class FeatureToggleCard extends StatelessWidget {
  const FeatureToggleCard({
    super.key,
    required this.role,
    required this.features,
    required this.visibility,
    required this.repository,
  });

  final AppRole role;
  final List<FeatureDefinition> features;
  final FeatureVisibility visibility;
  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: features.map((feature) {
            final enabled = visibility.isEnabled(role, feature.key);
            return Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: SwitchListTile.adaptive(
                value: enabled,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
                secondary: Icon(feature.icon, color: const Color(0xFF0D5C63)),
                title: Text(
                  feature.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
                subtitle: Text(feature.description),
                onChanged: (value) async {
                  await repository.updateRoleFeature(
                    role: role,
                    featureKey: feature.key,
                    enabled: value,
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${feature.title} ${value ? 'enabled' : 'disabled'} for ${role.label.toLowerCase()} users.',
                        ),
                      ),
                    );
                  }
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class HeroBanner extends StatelessWidget {
  const HeroBanner({super.key, required this.profile});

  final AppUserProfile profile;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(28),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF0D5C63), Color(0xFF1F7A8C), Color(0xFF86B3A6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Wrap(
        alignment: WrapAlignment.spaceBetween,
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 18,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: const Color(0x26FFFFFF),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  profile.role.headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Hello, ${profile.name}',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Text(
                  profile.role == AppRole.admin
                      ? 'Manage visibility for faculty and student features, keep the portal organized, and monitor everyone connected to the app.'
                      : 'Your home screen shows the tools currently enabled for your role. Firebase authentication keeps access connected to your account.',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: const Color(0xFFF3FAFB),
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0x1FFFFFFF),
              borderRadius: BorderRadius.circular(26),
              border: Border.all(color: const Color(0x33FFFFFF)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Signed in as',
                  style: TextStyle(color: Color(0xFFEAF6F7)),
                ),
                const SizedBox(height: 8),
                Text(
                  profile.email,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Role: ${profile.role.label}',
                  style: const TextStyle(color: Colors.white),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  const SectionTitle({super.key, required this.title, required this.subtitle});

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
            fontWeight: FontWeight.w800,
            color: const Color(0xFF12343B),
          ),
        ),
        const SizedBox(height: 6),
        Text(subtitle),
      ],
    );
  }
}

class StatCard extends StatelessWidget {
  const StatCard({
    super.key,
    required this.title,
    required this.value,
    required this.subtitle,
    required this.color,
    required this.icon,
  });

  final String title;
  final String value;
  final String subtitle;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 250,
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(22),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(height: 18),
              Text(
                title,
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                value,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF12343B),
                ),
              ),
              const SizedBox(height: 6),
              Text(subtitle),
            ],
          ),
        ),
      ),
    );
  }
}

class FeatureDefinition {
  const FeatureDefinition({
    required this.key,
    required this.title,
    required this.description,
    required this.icon,
  });

  final String key;
  final String title;
  final String description;
  final IconData icon;
}
