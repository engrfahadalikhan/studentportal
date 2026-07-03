import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../attendance/qr_attendance_section.dart';
import '../services/admin_data_bundle.dart';
import '../services/admin_data_importer.dart';
import '../services/answer_sheet_repository.dart';
import '../services/app_repository.dart';
import '../services/cloud_sync_service.dart';
import '../services/login_store.dart';
import '../services/slot_collection_repository.dart';
import '../services/teacher_dashboard_database.dart';
import '../ui/student_portal_shell.dart';

/// Admin ⇄ Admin offline data share. One admin picks which modules to bundle
/// into a file and sends it (WhatsApp/Bluetooth/cable/WiFi); the other admin
/// imports the file, which MERGES into their own data (keep-newest on clashes),
/// so both admins end up holding the full picture. Fully offline — no server.
class AdminDataSyncPage extends StatefulWidget {
  const AdminDataSyncPage({super.key, required this.repository});

  final AppRepository repository;

  @override
  State<AdminDataSyncPage> createState() => _AdminDataSyncPageState();
}

class _AdminDataSyncPageState extends State<AdminDataSyncPage> {
  final Set<AdminModule> _selected = {...AdminModule.values};
  bool _busy = false;
  String? _status;
  List<ModuleImportResult>? _lastImport;

  // ---------------------------------------------------------------- export
  Future<Map<String, dynamic>> _buildModule(AdminModule m) async {
    switch (m) {
      case AdminModule.attendance:
        final r = AttendanceRepository();
        await r.open();
        return {'scans': await r.exportScans()};
      case AdminModule.assessments:
        return TeacherDashboardDatabase.instance.exportAssessments();
      case AdminModule.ufm:
        return TeacherDashboardDatabase.instance.exportUfm();
      case AdminModule.answerSheets:
        final r = AnswerSheetRepository();
        await r.open();
        return r.exportBundle();
      case AdminModule.slots:
        final r = SlotCollectionRepository();
        await r.open();
        return r.exportBundle();
    }
  }

  Future<void> _share() async {
    if (_selected.isEmpty) {
      setState(() => _status = 'Pick at least one module to share.');
      return;
    }
    setState(() {
      _busy = true;
      _status = 'Packing data…';
    });
    try {
      final modules = <String, dynamic>{};
      for (final m in _selected) {
        modules[m.key] = await _buildModule(m);
      }
      final sharedBy = LoginStore.instance.currentUserName.trim().isEmpty
          ? 'Admin'
          : LoginStore.instance.currentUserName.trim();
      final text = AdminDataBundle.encode(sharedBy: sharedBy, modules: modules);
      final dir = await getTemporaryDirectory();
      final stamp = DateFormat('yyyyMMdd-HHmm').format(DateTime.now());
      final file = File('${dir.path}/AUST_data_$stamp.austdata');
      await file.writeAsString(text);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Ready. Choose how to send it to the other admin.';
      });
      await Share.shareXFiles(
        [XFile(file.path)],
        subject: 'AUST admin data — shared by $sharedBy',
        text:
            'AUST portal data bundle from $sharedBy. Open the AUST app → Admin '
            '→ Data share → Import this file.',
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Could not build the file: $e';
      });
    }
  }

  // ---------------------------------------------------------------- import
  Future<void> _import() async {
    setState(() {
      _busy = true;
      _status = null;
      _lastImport = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(withData: true);
      if (picked == null || picked.files.isEmpty) {
        setState(() {
          _busy = false;
          _status = 'No file chosen.';
        });
        return;
      }
      final f = picked.files.first;
      final text = f.bytes != null
          ? utf8.decode(f.bytes!)
          : await File(f.path!).readAsString();
      final bundle = AdminDataImporter.parse(text);
      final results = await AdminDataImporter.importText(
        text,
        widget.repository,
      );
      if (!mounted) return;
      final when = bundle.sharedAt == null
          ? ''
          : ' (${DateFormat('dd MMM, hh:mm a').format(bundle.sharedAt!)})';
      setState(() {
        _busy = false;
        _lastImport = results;
        _status = 'Merged data shared by ${bundle.sharedBy}$when.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _status = 'Could not import: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PortalColors.pageBackground,
      appBar: AppBar(title: const Text('Data share (offline)')),
      body: AbsorbPointer(
        absorbing: _busy,
        child: ListView(
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
                    'Share collected data between devices',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Signed in as ${LoginStore.instance.currentUserName.isEmpty ? "Admin" : LoginStore.instance.currentUserName}',
                    style: const TextStyle(color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---- CLOUD AUTO-SYNC (Firebase) -------------------------------
            AnimatedBuilder(
              animation: CloudSyncService.instance,
              builder: (context, _) {
                final s = CloudSyncService.instance;
                return _card(
                  title: 'Cloud auto-sync (all data)',
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Text(
                        'Attendance, marks, UFM, answer sheets and slot '
                        'collection upload to Firebase automatically and '
                        'everyone\'s data downloads here — teachers and both '
                        'admins all stay complete. Deletions sync too. Needs '
                        'internet; works in background.',
                        style: TextStyle(
                          color: PortalColors.subtleText,
                          fontSize: 12.5,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Icon(
                            s.isRunning
                                ? Icons.cloud_done_rounded
                                : Icons.cloud_off_rounded,
                            size: 20,
                            color: s.isRunning
                                ? const Color(0xFF047857)
                                : PortalColors.subtleText,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              '${s.status} · sent ${s.uploadedTotal} · '
                              'received ${s.receivedTotal}',
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: _busy
                            ? null
                            : () async {
                                final sync = CloudSyncService.instance;
                                await sync.start(
                                  repository: widget.repository,
                                );
                                await sync.pushLocalScans();
                                await sync.pushExamData();
                                await sync.pushModules(all: true);
                              },
                        icon: const Icon(Icons.cloud_sync_rounded),
                        label: const Text('Sync now'),
                      ),
                    ],
                  ),
                );
              },
            ),
            const SizedBox(height: 16),

            // ---- SHARE ----------------------------------------------------
            _card(
              title: '1 · Share your data',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Tick what to include, then send the file to the other '
                    'admin any way you like.',
                    style: TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  for (final m in AdminModule.values)
                    CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: _selected.contains(m),
                      onChanged: (v) => setState(() {
                        if (v == true) {
                          _selected.add(m);
                        } else {
                          _selected.remove(m);
                        }
                      }),
                      title: Text(m.label),
                    ),
                  const SizedBox(height: 8),
                  FilledButton.icon(
                    onPressed: _busy ? null : _share,
                    icon: const Icon(Icons.ios_share_rounded),
                    label: const Text('Build & share data file'),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // ---- IMPORT ---------------------------------------------------
            _card(
              title: '2 · Import data from the other admin',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Pick the file the other admin sent you. It MERGES into your '
                    'data — nothing is lost, newest copy wins on any clash.',
                    style: TextStyle(
                      color: PortalColors.subtleText,
                      fontSize: 12.5,
                    ),
                  ),
                  const SizedBox(height: 10),
                  OutlinedButton.icon(
                    onPressed: _busy ? null : _import,
                    icon: const Icon(Icons.file_open_rounded),
                    label: const Text('Choose file & merge'),
                  ),
                ],
              ),
            ),

            if (_busy) ...[
              const SizedBox(height: 20),
              const Center(child: CircularProgressIndicator()),
            ],
            if (_status != null) ...[
              const SizedBox(height: 16),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFFEAFBEF),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0xFFB9F4C9)),
                ),
                child: Text(
                  _status!,
                  style: const TextStyle(
                    color: Color(0xFF0F766E),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (_lastImport != null && _lastImport!.isNotEmpty) ...[
              const SizedBox(height: 12),
              _card(
                title: 'Merged',
                child: Column(
                  children: [
                    for (final r in _lastImport!)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(
                          Icons.check_circle_rounded,
                          color: Color(0xFF047857),
                        ),
                        title: Text(r.module.label),
                        trailing: Text(
                          '${r.added} added · ${r.updated} updated',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _card({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: PortalColors.cardBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              fontSize: 14.5,
            ),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }
}
