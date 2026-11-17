import Cocoa
import FlutterMacOS

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    if let screen = NSScreen.main?.visibleFrame {
      self.setContentSize(NSSize(width: min(1440, screen.width - 36), height: min(900, screen.height - 60)))
    }
    self.minSize = NSSize(width: 390, height: 600)
    self.titlebarAppearsTransparent = true
    self.backgroundColor = NSColor(red: 231/255, green: 232/255, blue: 228/255, alpha: 1)
    self.center()

    let localWorkspace = FlutterMethodChannel(
      name: "org.localerp.workspace/local",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    localWorkspace.setMethodCallHandler { call, result in
      guard call.method == "applicationSupport" else {
        result(FlutterMethodNotImplemented)
        return
      }
      result(FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?.path)
    }
    RegisterGeneratedPlugins(registry: flutterViewController)
    FlutterEventChannel(
      name: "org.localerp.workspace/reduceTransparency",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    ).setStreamHandler(ReduceTransparencyStream())

    super.awakeFromNib()
  }
}

private final class ReduceTransparencyStream: NSObject, FlutterStreamHandler {
  private var observation: NSObjectProtocol?

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    observation = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main
    ) { _ in events(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency) }
    events(NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency)
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    removeObservation()
    return nil
  }

  private func removeObservation() {
    if let observation { NSWorkspace.shared.notificationCenter.removeObserver(observation) }
    observation = nil
  }

  deinit { removeObservation() }
}
