import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    FlutterEventChannel(
      name: "org.localerp.workspace/reduceTransparency",
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    ).setStreamHandler(ReduceTransparencyStream())
  }
}

private final class ReduceTransparencyStream: NSObject, FlutterStreamHandler {
  private var observations: [NSObjectProtocol] = []

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    // Re-read on foregrounding in case Settings changed while the app was suspended.
    let notifications = [UIAccessibility.reduceTransparencyStatusDidChangeNotification,
                         UIApplication.didBecomeActiveNotification]
    for name in notifications {
      observations.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
        events(UIAccessibility.isReduceTransparencyEnabled)
      })
    }
    events(UIAccessibility.isReduceTransparencyEnabled)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObservations()
    return nil
  }

  private func removeObservations() {
    for observation in observations { NotificationCenter.default.removeObserver(observation) }
    observations.removeAll()
  }

  deinit { removeObservations() }
}
