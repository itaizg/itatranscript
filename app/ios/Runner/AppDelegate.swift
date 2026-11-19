import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var launchChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AudioCapturePlugin") {
      AudioCapturePlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "AppleSpeechPlugin") {
      AppleSpeechPlugin.register(with: registrar)
    }
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LaunchChannel") {
      let channel = FlutterMethodChannel(
        name: "itatranscript/launch", binaryMessenger: registrar.messenger())
      channel.setMethodCallHandler { [weak self] call, result in
        if call.method == "arguments" {
          result(self?.takeStartRequest() == true ? ["start": "true"] : [String: String]())
        } else {
          result(FlutterMethodNotImplemented)
        }
      }
      launchChannel = channel
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)
    // Warm start from the Lock Screen control: tell Dart a start was requested.
    if takeStartRequest() { launchChannel?.invokeMethod("startRequested", arguments: nil) }
  }

  /// Reads and clears the flag set by `StartCaptionsIntent`.
  private func takeStartRequest() -> Bool {
    let defaults = UserDefaults.standard
    let requested = defaults.bool(forKey: "itatranscript.startRequested")
    if requested { defaults.removeObject(forKey: "itatranscript.startRequested") }
    return requested
  }
}
