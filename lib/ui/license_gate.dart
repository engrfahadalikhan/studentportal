import 'package:flutter/material.dart';

import '../services/login_store.dart';

/// Licensed usage window. The app runs normally between these dates; outside
/// the window it locks and only the admin password unlocks it (per session).
final DateTime kLicenseStart = DateTime(2026, 6, 20);
final DateTime kLicenseEnd = DateTime(2026, 7, 15, 23, 59, 59);

/// The default admin password that unlocks an expired/locked app. If the admin
/// changed their password (LoginStore override) that new one also works.
const String _kAdminPassword = 'pdfpakistan123#';

/// Wraps the whole app: inside the licensed window (or after the admin unlocks
/// this session) it shows [child]; otherwise it shows a lock screen that
/// demands the admin password — without it, nothing in the app is reachable.
class LicenseGate extends StatefulWidget {
  const LicenseGate({super.key, required this.child});

  final Widget child;

  @override
  State<LicenseGate> createState() => _LicenseGateState();
}

class _LicenseGateState extends State<LicenseGate> {
  bool _unlocked = false;

  bool get _withinLicense {
    final now = DateTime.now();
    return !now.isBefore(kLicenseStart) && !now.isAfter(kLicenseEnd);
  }

  @override
  Widget build(BuildContext context) {
    if (_withinLicense || _unlocked) return widget.child;
    return _LockScreen(
      onUnlock: () => setState(() => _unlocked = true),
    );
  }
}

class _LockScreen extends StatefulWidget {
  const _LockScreen({required this.onUnlock});

  final VoidCallback onUnlock;

  @override
  State<_LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends State<_LockScreen> {
  final _controller = TextEditingController();
  bool _obscure = true;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _tryUnlock() {
    final current =
        LoginStore.instance.passwordOverride('admin') ?? _kAdminPassword;
    if (_controller.text.trim() == current) {
      widget.onUnlock();
    } else {
      setState(() => _error = 'Admin password is wrong.');
    }
  }

  String _d(DateTime d) => '${d.day}/${d.month}/${d.year}';

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final notStarted = DateTime.now().isBefore(kLicenseStart);
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Color(0xFFFBF6EA), Color(0xFFFFFFFF), Color(0xFFF6ECCF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 460),
                child: Container(
                  padding: const EdgeInsets.all(26),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFEADBB0)),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x22000000),
                        blurRadius: 30,
                        offset: Offset(0, 16),
                      ),
                    ],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        width: 66,
                        height: 66,
                        alignment: Alignment.center,
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            colors: [Color(0xFF1B1813), Color(0xFF6E5713)],
                          ),
                          borderRadius: BorderRadius.all(Radius.circular(18)),
                        ),
                        child: const Icon(
                          Icons.lock_outline_rounded,
                          color: Color(0xFFE7C955),
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Application locked',
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineSmall
                            ?.copyWith(fontWeight: FontWeight.w900),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        notStarted
                            ? 'This application becomes active on '
                                  '${_d(kLicenseStart)}.'
                            : 'The licensed period '
                                  '(${_d(kLicenseStart)} – ${_d(kLicenseEnd)}) '
                                  'has ended.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          height: 1.4,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Enter the admin password to continue.',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _controller,
                        obscureText: _obscure,
                        onSubmitted: (_) => _tryUnlock(),
                        decoration: InputDecoration(
                          labelText: 'Admin password',
                          prefixIcon: const Icon(Icons.key_outlined),
                          errorText: _error,
                          suffixIcon: IconButton(
                            onPressed: () =>
                                setState(() => _obscure = !_obscure),
                            icon: Icon(
                              _obscure
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      FilledButton.icon(
                        onPressed: _tryUnlock,
                        icon: const Icon(Icons.lock_open_rounded),
                        label: const Text('Unlock'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
