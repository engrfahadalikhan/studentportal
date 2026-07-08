import 'dart:async';

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';

import '../services/firebase_paths.dart';

class RemoteVersionGate extends StatefulWidget {
  const RemoteVersionGate({super.key, required this.child});

  final Widget child;

  @override
  State<RemoteVersionGate> createState() => _RemoteVersionGateState();
}

class _RemoteVersionGateState extends State<RemoteVersionGate> {
  late Future<_VersionGateResult> _check;

  @override
  void initState() {
    super.initState();
    _check = _checkRemoteVersion();
  }

  Future<_VersionGateResult> _checkRemoteVersion() async {
    if (Firebase.apps.isEmpty) return _VersionGateResult.allowed();
    try {
      final doc = await FirebasePaths.appControlDoc.get().timeout(
        const Duration(seconds: 5),
      );
      final data = doc.data();
      if (data == null) return _VersionGateResult.allowed();
      final minBuild = _asInt(data['min_build']);
      final disabled = data['disabled'] == true;
      if (disabled || minBuild > kAustPortalBuildNumber) {
        return _VersionGateResult.blocked(
          minBuild: minBuild,
          latestVersion: (data['latest_version'] ?? '').toString(),
          message: (data['message'] ?? '').toString(),
        );
      }
      return _VersionGateResult.allowed();
    } catch (_) {
      // Offline/quota should not brick the current valid app. Old APKs are
      // stopped by Firestore rules and the new namespace, not by this read.
      return _VersionGateResult.allowed();
    }
  }

  int _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse((value ?? '').toString()) ?? 0;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<_VersionGateResult>(
      future: _check,
      builder: (context, snapshot) {
        final result = snapshot.data;
        if (result == null) return const _VersionCheckingScreen();
        if (result.blocked) {
          return _UpdateRequiredScreen(
            result: result,
            onRetry: () => setState(() => _check = _checkRemoteVersion()),
          );
        }
        return widget.child;
      },
    );
  }
}

class _VersionGateResult {
  const _VersionGateResult({
    required this.blocked,
    required this.minBuild,
    required this.latestVersion,
    required this.message,
  });

  factory _VersionGateResult.allowed() => const _VersionGateResult(
    blocked: false,
    minBuild: 0,
    latestVersion: '',
    message: '',
  );

  factory _VersionGateResult.blocked({
    required int minBuild,
    required String latestVersion,
    required String message,
  }) => _VersionGateResult(
    blocked: true,
    minBuild: minBuild,
    latestVersion: latestVersion,
    message: message,
  );

  final bool blocked;
  final int minBuild;
  final String latestVersion;
  final String message;
}

class _VersionCheckingScreen extends StatelessWidget {
  const _VersionCheckingScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(body: Center(child: CircularProgressIndicator()));
  }
}

class _UpdateRequiredScreen extends StatelessWidget {
  const _UpdateRequiredScreen({required this.result, required this.onRetry});

  final _VersionGateResult result;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final latest = result.latestVersion.trim().isEmpty
        ? 'latest version'
        : result.latestVersion.trim();
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(22),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.system_update_alt_rounded,
                    size: 56,
                    color: scheme.primary,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Update required',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    result.message.trim().isEmpty
                        ? 'Please install $latest of AUST Student Portal.'
                        : result.message.trim(),
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: scheme.onSurfaceVariant,
                      fontWeight: FontWeight.w700,
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Installed: $kAustPortalVersionLabel '
                    '($kAustPortalBuildNumber)\n'
                    'Required build: ${result.minBuild}',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed: onRetry,
                    icon: const Icon(Icons.refresh_rounded),
                    label: const Text('Check again'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
