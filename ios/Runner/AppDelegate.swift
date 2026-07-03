import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let lockedModeChannelName = "aust_exam/locked_mode"
  private var lockedModeEnabled = false
  private var privacyShield: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: lockedModeChannelName,
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "enable":
          self?.enableLockedMode()
          result(nil)
        case "disable":
          self?.disableLockedMode()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  override func applicationWillResignActive(_ application: UIApplication) {
    super.applicationWillResignActive(application)
    if lockedModeEnabled {
      showPrivacyShield()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    removePrivacyShield()
    super.applicationDidBecomeActive(application)
  }

  private func enableLockedMode() {
    lockedModeEnabled = true
    UIApplication.shared.isIdleTimerDisabled = true
  }

  private func disableLockedMode() {
    lockedModeEnabled = false
    UIApplication.shared.isIdleTimerDisabled = false
    removePrivacyShield()
  }

  private func showPrivacyShield() {
    guard privacyShield == nil, let hostWindow = window else {
      return
    }
    let shield = UIView(frame: hostWindow.bounds)
    shield.backgroundColor = UIColor.black
    shield.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    hostWindow.addSubview(shield)
    privacyShield = shield
  }

  private func removePrivacyShield() {
    privacyShield?.removeFromSuperview()
    privacyShield = nil
  }
}
