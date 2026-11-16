import Cocoa
import FlutterMacOS
import desktop_multi_window

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    // The Flutter view over the window's own vibrancy, which the macOS Tahoe look turns on.
    self.contentViewController = BackdropViewController(flutter: flutterViewController)
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

// The main window's content: the Flutter view, and under it the system's see-through material
// (NSVisualEffectView, blending with what's behind the window), for the macOS Tahoe look
// (lib/desktop/backdrop.dart). Hidden, with the window and the Flutter view opaque as before, in
// the other looks.
class BackdropViewController: NSViewController {
  let flutter: FlutterViewController
  private let effect = NSVisualEffectView()

  init(flutter: FlutterViewController) {
    self.flutter = flutter
    super.init(nibName: nil, bundle: nil)
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) is not used")
  }

  override func loadView() {
    let root = NSView(frame: NSRect(x: 0, y: 0, width: 1120, height: 760))
    effect.blendingMode = .behindWindow
    effect.material = .underWindowBackground
    effect.state = .followsWindowActiveState
    effect.isHidden = true
    effect.frame = root.bounds
    effect.autoresizingMask = [.width, .height]
    root.addSubview(effect)

    addChild(flutter)
    flutter.view.frame = root.bounds
    flutter.view.autoresizingMask = [.width, .height]
    root.addSubview(flutter.view)
    view = root
  }

  /// Shows the vibrancy behind the window, light or dark to match the app, or takes it away.
  /// Whether it's showing.
  func setBackdrop(on: Bool, dark: Bool) -> Bool {
    effect.isHidden = !on
    effect.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
    flutter.backgroundColor = on ? .clear : nil
    if let window = view.window {
      window.isOpaque = !on
      window.backgroundColor = on ? .clear : .windowBackgroundColor
    }
    return on
  }
}
