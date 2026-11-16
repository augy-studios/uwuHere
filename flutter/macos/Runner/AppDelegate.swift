import Cocoa
import FlutterMacOS

// The app's own channel to macOS (org.uwuapps.here/desktop, lib/desktop/runner.dart): the Dock's
// menu of your events and its badge; uwu://here/ links opened from elsewhere; a click on the
// Dock icon bringing the window back; the window's vibrancy for the macOS Tahoe look. Closing
// the window leaves the app running in the menu bar.
@main
class AppDelegate: FlutterAppDelegate {
  var channel: FlutterMethodChannel?
  private var favourites: [(name: String, link: String)] = []
  private var pendingLinks: [String] = []

  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return false
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  func attach(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "org.uwuapps.here/desktop", binaryMessenger: messenger)
    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "setFavourites":
        let args = call.arguments as? [String: Any]
        let items = args?["items"] as? [[String: Any]] ?? []
        self.favourites = items.compactMap { item in
          guard let name = item["name"] as? String, let link = item["link"] as? String else { return nil }
          return (name, link)
        }
        result(nil)
      case "setBadge":
        NSApp.dockTile.badgeLabel = (call.arguments as? String).flatMap { $0.isEmpty ? nil : $0 }
        result(nil)
      case "setBackdrop":
        // { kind: "vibrancy" | "none", dark } (lib/desktop/backdrop.dart): the main window's.
        let args = call.arguments as? [String: Any]
        let kind = args?["kind"] as? String ?? "none"
        let dark = args?["dark"] as? Bool ?? false
        let content = NSApp.windows.lazy.compactMap { $0.contentViewController as? BackdropViewController }.first
        result(content?.setBackdrop(on: kind == "vibrancy", dark: dark) ?? false)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    self.channel = channel
    for link in pendingLinks { channel.invokeMethod("open", arguments: link) }
    pendingLinks.removeAll()
  }

  // uwu://here/… links (Info.plist's CFBundleURLTypes).
  override func application(_ application: NSApplication, open urls: [URL]) {
    for url in urls {
      if let channel = channel {
        channel.invokeMethod("open", arguments: url.absoluteString)
      } else {
        pendingLinks.append(url.absoluteString)
      }
    }
  }

  // A click on the Dock icon with no window showing.
  override func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
    channel?.invokeMethod("activate", arguments: nil)
    return true
  }

  // The Dock menu: one item per event you host.
  override func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
    let menu = NSMenu()
    if favourites.isEmpty {
      let item = NSMenuItem(title: "Host an event to see it here", action: nil, keyEquivalent: "")
      item.isEnabled = false
      menu.addItem(item)
      return menu
    }
    for (i, f) in favourites.enumerated() {
      let item = NSMenuItem(title: f.name, action: #selector(openFavourite(_:)), keyEquivalent: "")
      item.tag = i
      item.target = self
      menu.addItem(item)
    }
    return menu
  }

  @objc func openFavourite(_ sender: NSMenuItem) {
    guard sender.tag < favourites.count else { return }
    channel?.invokeMethod("open", arguments: favourites[sender.tag].link)
  }
}
