import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../assessment/assessment_models.dart';
import '../services/app_repository.dart';
import '../services/local_exam_server.dart';
import '../ui/student_portal_shell.dart';

/// PROTOTYPE — teacher hosts a quiz on the local WiFi so connected student
/// phones get it (and submit back) WITHOUT scanning a QR.
class LocalExamHostPage extends StatefulWidget {
  const LocalExamHostPage({
    super.key,
    required this.assessment,
    required this.repository,
  });

  final Assessment assessment;
  final AppRepository repository;

  @override
  State<LocalExamHostPage> createState() => _LocalExamHostPageState();
}

class _LocalExamHostPageState extends State<LocalExamHostPage> {
  late final LocalExamServer _server = LocalExamServer(widget.repository);
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _server.stop();
    _server.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final url = await _server.start(widget.assessment);
      if (url == null) {
        _error =
            'No WiFi address found. Connect this phone to the exam WiFi (not '
            'mobile data) and try again.';
      }
    } catch (e) {
      _error = 'Could not start the host: $e';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Host on WiFi (no internet)')),
      body: AnimatedBuilder(
        animation: _server,
        builder: (context, _) {
          final url = _server.url;
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: PortalColors.heroGradient,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Local exam host',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.assessment.title,
                      style: const TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Everyone (this phone + all students) must be on the SAME local '
                'WiFi — a router / access point with no internet is fine. '
                'Students open the app → "Join teacher\'s WiFi exam" and enter '
                'the address below (or scan the QR). No internet needed.',
                style: TextStyle(fontSize: 12.5, color: PortalColors.subtleText),
              ),
              const SizedBox(height: 14),
              if (!_server.running)
                FilledButton.icon(
                  onPressed: _busy ? null : _start,
                  icon: const Icon(Icons.wifi_tethering_rounded),
                  label: Text(_busy ? 'Starting…' : 'Start hosting'),
                )
              else ...[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: PortalColors.cardBorder),
                  ),
                  child: Column(
                    children: [
                      if (url != null) ...[
                        QrImageView(data: url, size: 200),
                        const SizedBox(height: 10),
                        SelectableText(
                          url,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ] else
                        const Text('Address unavailable — check WiFi.'),
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          _stat('Connected', '${_server.connectedCount}'),
                          _stat('Submitted', '${_server.submissionCount}'),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () => _server.stop(),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFB91C1C),
                  ),
                  icon: const Icon(Icons.stop_circle_outlined),
                  label: const Text('Stop hosting'),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: const TextStyle(
                    color: Color(0xFFB91C1C),
                    fontSize: 12.5,
                  ),
                ),
              ],
              const SizedBox(height: 16),
              const Text(
                'PROTOTYPE: tested for the flow on a local WiFi. For very large '
                'classes the WiFi access points are the real limit, not the app.',
                style: TextStyle(fontSize: 11, color: PortalColors.subtleText),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _stat(String label, String value) => Column(
    children: [
      Text(
        value,
        style: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.w900,
          color: Color(0xFF047857),
        ),
      ),
      Text(
        label,
        style: const TextStyle(fontSize: 12, color: PortalColors.subtleText),
      ),
    ],
  );
}
