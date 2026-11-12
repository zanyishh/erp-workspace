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

    RegisterGeneratedPlugins(registry: flutterViewController)

    super.awakeFromNib()
  }
}
