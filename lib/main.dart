import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'features/feature_visibility_service.dart';
import 'services/app_repository.dart';
import 'theme/app_theme.dart';
import 'theme/theme_controller.dart';
import 'ui/app_shell.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.linux)) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  }
  await Future.wait([
    FeatureVisibilityService.instance.load(),
    ThemeController.instance.load(),
  ]);
  runApp(const StudentPortalApp());
}

class StudentPortalApp extends StatefulWidget {
  const StudentPortalApp({super.key});

  @override
  State<StudentPortalApp> createState() => _StudentPortalAppState();
}

class _StudentPortalAppState extends State<StudentPortalApp> {
  late final AppRepository _repository;

  @override
  void initState() {
    super.initState();
    _repository = AppRepository();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: ThemeController.instance,
      builder: (context, _) {
        return MaterialApp(
          title: 'AUST Student Portal',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(ThemeController.instance.palette),
          darkTheme: AppTheme.dark(ThemeController.instance.palette),
          themeMode: ThemeController.instance.mode,
          home: AppShell(repository: _repository),
        );
      },
    );
  }
}
