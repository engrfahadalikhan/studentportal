import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../firebase/firebase_bootstrap.dart';
import '../models/app_role.dart';
import '../models/app_user_profile.dart';
import '../models/feature_visibility.dart';
import '../services/app_repository.dart';
import 'auth_landing_page.dart';
import 'dashboard_page.dart';
import 'shared_widgets.dart';

class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.repository});

  final AppRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: repository.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const BusyView(message: 'Checking your session...');
        }

        final user = snapshot.data;
        if (user == null) {
          return AuthLandingPage(repository: repository);
        }

        return AuthenticatedHome(repository: repository, user: user);
      },
    );
  }
}

class AuthenticatedHome extends StatefulWidget {
  const AuthenticatedHome({
    super.key,
    required this.repository,
    required this.user,
  });

  final AppRepository repository;
  final User user;

  @override
  State<AuthenticatedHome> createState() => _AuthenticatedHomeState();
}

class _AuthenticatedHomeState extends State<AuthenticatedHome> {
  late Future<AppUserProfile> _profileFuture;

  @override
  void initState() {
    super.initState();
    _profileFuture = widget.repository.ensureUserProfile(widget.user);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AppUserProfile>(
      future: _profileFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const BusyView(message: 'Preparing your workspace...');
        }

        if (snapshot.hasError) {
          return StatusScaffold(
            title: 'Profile setup could not finish',
            message: friendlyError(snapshot.error),
            icon: Icons.warning_amber_rounded,
            action: FilledButton(
              onPressed: () {
                setState(() {
                  _profileFuture = widget.repository.ensureUserProfile(
                    widget.user,
                  );
                });
              },
              child: const Text('Try again'),
            ),
          );
        }

        return StreamBuilder<AppUserProfile?>(
          stream: widget.repository.watchUserProfile(widget.user.uid),
          builder: (context, profileSnapshot) {
            if (profileSnapshot.connectionState == ConnectionState.waiting) {
              return const BusyView(message: 'Loading your profile...');
            }

            final profile = profileSnapshot.data;
            if (profile == null) {
              return StatusScaffold(
                title: 'Profile not found',
                message:
                    'Your authentication worked, but your profile is not available yet.',
                icon: Icons.person_search_rounded,
                action: FilledButton(
                  onPressed: () async {
                    await widget.repository.ensureUserProfile(widget.user);
                    if (mounted) {
                      setState(() {
                        _profileFuture = widget.repository.ensureUserProfile(
                          widget.user,
                        );
                      });
                    }
                  },
                  child: const Text('Create profile'),
                ),
              );
            }

            return StreamBuilder<FeatureVisibility>(
              stream: widget.repository.watchFeatureVisibility(),
              builder: (context, featureSnapshot) {
                if (featureSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const BusyView(message: 'Loading feature settings...');
                }

                final visibility =
                    featureSnapshot.data ??
                    FeatureVisibility(roles: FeatureVisibility.defaultRoles());

                if (profile.role == AppRole.admin) {
                  return StreamBuilder<List<AppUserProfile>>(
                    stream: widget.repository.watchAllUsers(),
                    builder: (context, usersSnapshot) {
                      return DashboardPage(
                        repository: widget.repository,
                        profile: profile,
                        visibility: visibility,
                        users: usersSnapshot.data ?? const [],
                      );
                    },
                  );
                }

                return DashboardPage(
                  repository: widget.repository,
                  profile: profile,
                  visibility: visibility,
                  users: const [],
                );
              },
            );
          },
        );
      },
    );
  }
}

class FirebaseUnavailablePage extends StatelessWidget {
  const FirebaseUnavailablePage({super.key, required this.status});

  final FirebaseConnectionStatus status;

  @override
  Widget build(BuildContext context) {
    return StatusScaffold(
      title: 'Firebase is not ready on this platform',
      message:
          'The project is configured for Android Firebase right now. ${status.errorMessage ?? ''}'
              .trim(),
      icon: Icons.cloud_off_rounded,
      action: OutlinedButton(
        onPressed: () {},
        child: const Text('Add more Firebase platforms later'),
      ),
    );
  }
}
