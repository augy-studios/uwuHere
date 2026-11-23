// The tray icon (the menu bar on macOS) and its menu (docs/desktop-features-spec.md §4): a click
// shows or hides the window on Windows and Linux; the menu, rebuilt whenever something in it
// changes, top to bottom:
//   Restart to update to x.y.z / Download version x.y.z (only while there is one)
//   Tray glance: {event} and Stop the tray glance (while it's on)
//   Open uwuHere, Check in with a code, Host an event
//   Add a widget, Make it yours...
//   Check for updates..., Start when I sign in (a check box)
//   Quit
import 'dart:async';
import 'dart:io';

import 'package:tray_manager/tray_manager.dart';

import '../app/links.dart';
import 'desk.dart';
import 'glance.dart';
import 'updater.dart';
import 'widgets_window.dart';

class DeskTray with TrayListener {
  DeskTray._();
  static final DeskTray instance = DeskTray._();

  /// Set by desktop_main.dart: opens Make it yours again.
  static Future<void> Function()? openWelcome;

  /// Whether the app starts when the user signs in, as the menu's check box shows it.
  bool _startsAtLogin = false;

  /// Puts the icon in the tray, and rebuilds the menu whenever the glance or an update changes.
  Future<void> start() async {
    String icon;
    if (Platform.isWindows) {
      icon = 'assets/images/tray.ico';
    } else if (Platform.isMacOS) {
      icon = 'assets/images/tray_template.png';
    } else {
      icon = 'assets/images/tray.png';
    }
    await trayManager.setIcon(icon, isTemplate: Platform.isMacOS);
    await trayManager.setToolTip(Desktop.name);
    trayManager.addListener(this);
    Glance.onTray = (tooltip, title) {
      trayManager.setToolTip(tooltip);
      if (Platform.isMacOS) trayManager.setTitle(title);
    };
    Glance.followed.addListener(rebuild);
    Updater.available.addListener(rebuild);
    Updater.ready.addListener(rebuild);
    Updater.checking.addListener(rebuild);
    _startsAtLogin = await Desktop.startsAtLogin();
    await rebuild();
  }

  /// Sets the tray's menu afresh from what's true now (see the list at the top of this file).
  Future<void> rebuild() async {
    final ready = Updater.ready.value;
    final available = Updater.available.value;
    final followed = Glance.followed.value;
    final checking = Updater.checking.value;
    String checkLabel;
    if (checking) {
      checkLabel = 'Checking for updates...';
    } else {
      checkLabel = 'Check for updates...';
    }
    await trayManager.setContextMenu(
      Menu(
        items: [
          if (ready != null) ...[
            MenuItem(
              key: 'restart',
              label: 'Restart to update to $ready',
              onClick: (_) {
                Updater.restartToUpdate();
              },
            ),
            MenuItem.separator(),
          ] else if (available != null && !Updater.canInstall) ...[
            MenuItem(
              key: 'download',
              label: 'Download version $available',
              onClick: (_) {
                Desktop.openExternal(Desktop.releases);
              },
            ),
            MenuItem.separator(),
          ],
          if (followed != null) ...[
            MenuItem(
              key: 'glance',
              label: 'Tray glance: ${followed['name']}',
              onClick: (_) {
                Desktop.show('uwu://here/host?id=${followed['code']}');
              },
            ),
            MenuItem(
              key: 'stop',
              label: 'Stop the tray glance',
              onClick: (_) {
                Glance.follow(null);
              },
            ),
            MenuItem.separator(),
          ],
          MenuItem(
            key: 'open',
            label: 'Open ${Desktop.name}',
            onClick: (_) {
              Desktop.show();
            },
          ),
          MenuItem(
            key: 'join',
            label: 'Check in with a code',
            onClick: (_) async {
              await Desktop.show();
              Links.open('uwu://here/#join');
            },
          ),
          MenuItem(
            key: 'host',
            label: 'Host an event',
            onClick: (_) async {
              await Desktop.show();
              Links.open('uwu://here/#host');
            },
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'widget',
            label: 'Add a widget',
            onClick: (_) {
              DeskWidgets.add();
            },
          ),
          MenuItem(
            key: 'welcome',
            label: 'Make it yours...',
            onClick: (_) {
              final openWelcomeAgain = openWelcome;
              if (openWelcomeAgain != null) openWelcomeAgain();
            },
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'check',
            label: checkLabel,
            disabled: checking,
            onClick: (_) {
              Updater.checkNow();
            },
          ),
          MenuItem.checkbox(
            key: 'login',
            label: 'Start when I sign in',
            checked: _startsAtLogin,
            onClick: (_) async {
              _startsAtLogin = !_startsAtLogin;
              await Desktop.setStartAtLogin(_startsAtLogin);
              rebuild();
            },
          ),
          MenuItem.separator(),
          MenuItem(
            key: 'quit',
            label: 'Quit',
            onClick: (_) {
              Desktop.quit();
            },
          ),
        ],
      ),
    );
  }

  @override
  void onTrayIconMouseDown() {
    // macOS opens the menu on a click; Windows and Linux show or hide the window.
    if (Platform.isMacOS) {
      trayManager.popUpContextMenu();
    } else {
      Desktop.toggle();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    Desktop.startsAtLogin().then((startsAtLogin) {
      _startsAtLogin = startsAtLogin;
      // On Windows a tray menu only closes on a click elsewhere if the app is the foreground
      // window as it opens (TrackPopupMenu's rule); this doesn't show a hidden window.
      rebuild().then((_) {
        // ignore: deprecated_member_use
        trayManager.popUpContextMenu(bringAppToFront: Platform.isWindows);
      });
    });
  }
}
