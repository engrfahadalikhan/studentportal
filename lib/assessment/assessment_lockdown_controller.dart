import 'dart:async';

import 'package:flutter/services.dart';

class AssessmentLockdownController {
  AssessmentLockdownController._();

  static const MethodChannel _channel = MethodChannel('aust_exam/locked_mode');

  /// Fired when the native side reports a lock break (e.g. the app was put into
  /// split-screen / multi-window during a locked attempt). The locked screen
  /// registers this to raise a warning / auto-submit.
  static void Function(String reason)? onLockBreak;

  static Future<void> enable() async {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'lockBreak') {
        onLockBreak?.call((call.arguments ?? 'Lock break').toString());
      }
      return null;
    });
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    await SystemChrome.setPreferredOrientations(const [
      DeviceOrientation.portraitUp,
    ]);
    await _invokeNative('enable');
  }

  static Future<void> disable() async {
    onLockBreak = null;
    _channel.setMethodCallHandler(null);
    await _invokeNative('disable');
    await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    await SystemChrome.setPreferredOrientations(DeviceOrientation.values);
  }

  static Future<void> _invokeNative(String method) async {
    try {
      await _channel.invokeMethod<void>(method);
    } on MissingPluginException {
      // Desktop/web builds have no native lockdown hook.
    } on PlatformException {
      // Keep the Dart-side locked flow running even if the OS refuses kiosk
      // behavior on an unmanaged device.
    }
  }
}
