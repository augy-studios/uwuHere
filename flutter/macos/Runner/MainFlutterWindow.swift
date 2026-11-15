import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    // Each desktop widget is a window with an engine of its own: it gets the same plugins.
    FlutterMultiWindowPlugin.setOnWindowCreatedCallback { controller in
      RegisterGeneratedPlugins(registry: controller)
    }
    (NSApp.delegate as? AppDelegate)?.attach(flutterViewController.engine.binaryMessenger)

    super.awakeFromNib()
  }
}
