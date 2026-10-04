import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(
      name: "com.folio/capture",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
    channel.setMethodCallHandler { call, result in
      if call.method == "openMessageShortcut" {
        Self.openBundledShortcut(result: result)
      } else if call.method == "setSession" {
        let args = call.arguments as? [String: Any]
        let defaults = UserDefaults.standard
        defaults.set(args?["token"] as? String ?? "", forKey: "flutter.token")
        defaults.set(args?["baseUrl"] as? String ?? "", forKey: "flutter.baseUrl")
        result(nil)
      } else if call.method == "clearSession" {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: "flutter.token")
        defaults.removeObject(forKey: "flutter.baseUrl")
        result(nil)
      } else {
        result(FlutterMethodNotImplemented)
      }
    }
  }

  /// Opens the signed shortcut so Shortcuts shows its Add sheet. The file
  /// already contains the message automation and the Save data to Takings action.
  private static func openBundledShortcut(result: @escaping FlutterResult) {
    DispatchQueue.main.async {
      guard let bundled = Bundle.main.url(forResource: "RunTakings", withExtension: "shortcut") else {
        result(false)
        return
      }
      let dest = FileManager.default.temporaryDirectory.appendingPathComponent("RunTakings.shortcut")
      do {
        if FileManager.default.fileExists(atPath: dest.path) {
          try FileManager.default.removeItem(at: dest)
        }
        try FileManager.default.copyItem(at: bundled, to: dest)
      } catch {
        result(false)
        return
      }
      UIApplication.shared.open(dest, options: [:]) { opened in
        result(opened)
      }
    }
  }
}
