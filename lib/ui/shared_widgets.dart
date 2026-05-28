import 'package:flutter/material.dart';

class BusyView extends StatelessWidget {
  const BusyView({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text(message),
          ],
        ),
      ),
    );
  }
}

class StatusScaffold extends StatelessWidget {
  const StatusScaffold({
    super.key,
    required this.title,
    required this.message,
    required this.icon,
    required this.action,
  });

  final String title;
  final String message;
  final IconData icon;
  final Widget action;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(icon, size: 48, color: const Color(0xFFB8860B)),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: Theme.of(context).textTheme.headlineSmall
                          ?.copyWith(fontWeight: FontWeight.w800),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(message, textAlign: TextAlign.center),
                    const SizedBox(height: 24),
                    action,
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

String friendlyError(Object? error) {
  if (error is PortalAuthException) {
    return error.message;
  }

  return error?.toString() ?? 'Something went wrong.';
}

class PortalAuthException implements Exception {
  const PortalAuthException(this.message);

  final String message;
}
