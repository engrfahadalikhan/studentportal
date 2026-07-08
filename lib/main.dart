import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'connect/connect_repository.dart';
import 'connect/event_repository.dart';
import 'firebase_options.dart';
import 'features/feature_visibility_service.dart';
import 'fyp/fyp_repository.dart';
import 'services/admin_data_bundle.dart';
import 'services/admin_data_importer.dart';
import 'services/app_repository.dart';
import 'services/assessment_access_service.dart';
import 'services/device_binding_service.dart';
import 'services/login_store.dart';
import 'services/paper_tracker_access_service.dart';
import 'services/slot_collection_access_service.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/app_shell.dart';
import 'ui/license_gate.dart';
import 'ui/remote_version_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Connect to Firebase on Android. This is offline-safe: initializeApp needs
  // no network, non-Android/dev builds skip it, and any failure is ignored so
  // the fully-offline app always starts.
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    try {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    } catch (e) {
      debugPrint('Firebase init skipped: $e');
    }
  }
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await Future.wait([
    FypRepository.instance.load(),
    ConnectRepository.instance.load(),
    EventRepository.instance.load(),
    FeatureVisibilityService.instance.load(),
    AssessmentAccessService.instance.load(),
    PaperTrackerAccessService.instance.load(),
    SlotCollectionAccessService.instance.load(),
    DeviceBindingService.instance.load(),
    LoginStore.instance.load(),
    ThemeController.instance.load(),
  ]);
  runApp(const StudentPortalApp());
}

class StudentPortalApp extends StatefulWidget {
  const StudentPortalApp({super.key});

  @override
  State<StudentPortalApp> createState() => _StudentPortalAppState();
}

class _StudentPortalAppState extends State<StudentPortalApp>
    with WidgetsBindingObserver {
  late final AppRepository _repository;
  final _navKey = GlobalKey<NavigatorState>();

  /// Fires when the app is opened with a shared file (WhatsApp / Files → Open
  /// with AUST Portal) so we can import it straight into the database.
  static const _sharedChannel = MethodChannel('aust_import/shared');
  bool _importing = false;

  @override
  void initState() {
    super.initState();
    _repository = AppRepository();
    // Restore teacher-created assessments + student submissions saved on this
    // device so they survive closing/reopening the app.
    _repository.loadPersistedAssessments();
    _repository.loadPersistedSubmissions();
    WidgetsBinding.instance.addObserver(this);
    _sharedChannel.setMethodCallHandler((call) async {
      if (call.method == 'onShared') _checkSharedImport();
      return null;
    });
    // A file the app was cold-started with is waiting on the native side.
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkSharedImport());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _checkSharedImport();
  }

  Future<void> _checkSharedImport() async {
    if (_importing) return;
    String? text;
    try {
      text = await _sharedChannel.invokeMethod<String>('getPending');
    } catch (_) {
      return;
    }
    if (text == null || text.trim().isEmpty) return;
    _importing = true;
    try {
      await _handleSharedImport(text);
    } finally {
      _importing = false;
    }
  }

  Future<void> _handleSharedImport(String text) async {
    final ctx0 = _navKey.currentContext;
    if (ctx0 == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx0);

    ParsedBundle bundle;
    try {
      bundle = AdminDataImporter.parse(text);
    } catch (_) {
      messenger?.showSnackBar(
        const SnackBar(content: Text('This file is not an AUST data bundle.')),
      );
      return;
    }

    final go = await showDialog<bool>(
      context: ctx0,
      builder: (c) => AlertDialog(
        title: const Text('Import received data?'),
        content: Text(
          'Data shared by ${bundle.sharedBy} will be merged into this device. '
          'Nothing is lost and duplicates are skipped.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Import'),
          ),
        ],
      ),
    );
    if (go != true || !mounted) return;

    final ctx1 = _navKey.currentContext;
    if (ctx1 == null || !ctx1.mounted) return;
    showDialog<void>(
      context: ctx1,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    List<ModuleImportResult> results;
    try {
      results = await AdminDataImporter.importText(text, _repository);
    } catch (e) {
      _navKey.currentState?.pop(); // close spinner
      messenger?.showSnackBar(SnackBar(content: Text('Import failed: $e')));
      return;
    }
    _navKey.currentState?.pop(); // close spinner
    if (!mounted) return;

    final ctx2 = _navKey.currentContext;
    if (ctx2 == null || !ctx2.mounted) return;
    final summary = results
        .map((r) => '${r.module.label}: ${r.added} added, ${r.updated} updated')
        .join('\n');
    await showDialog<void>(
      context: ctx2,
      builder: (d) => AlertDialog(
        title: const Text('Import complete'),
        content: Text(summary.isEmpty ? 'Nothing new to import.' : summary),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(d),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'AUST Student Portal',
          debugShowCheckedModeBanner: false,
          navigatorKey: _navKey,
          theme: AppTheme.light(ThemeController.instance.palette),
          // Light only — dark / system modes were removed by request.
          themeMode: ThemeMode.light,
          home: RemoteVersionGate(
            child: LicenseGate(child: AppShell(repository: _repository)),
          ),
        );
      },
    );
  }
}
