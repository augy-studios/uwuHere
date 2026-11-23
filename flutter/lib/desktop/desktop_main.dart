// uwuHere for Windows, macOS and Linux: the same app as the phone's, with the desktop's extras
// round it (docs/desktop-features-spec.md lists each one, docs/flutter-desktop-app-spec.md says
// how). uwuHere had no desktop app before 2.0.0, so there's nothing to take over from:
//
// - one copy at a time, links forwarded to it (desk.dart);
// - the update window at launch, and updating itself (splash.dart, updater.dart);
// - Make it yours, the first window, and from the tray's menu after (welcome.dart);
// - the tray, where closing the window leaves it running (tray.dart);
// - its own title bar and command bar, shortcuts, the macOS menu bar (chrome.dart);
// - the tray glance, the Jump List, thumbnail buttons and Dock (glance.dart);
// - "Your event" widgets, each in its own window and engine (widgets_window.dart);
// - check-in notifications, polled where a phone gets pushes (alerts_poll.dart);
// - location on Linux without a location service (location.dart);
// - starting at sign-in, uwu://here/ links shared with the sibling apps (desk.dart).
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';

import '../app/app.dart';
import '../app/fullscreen.dart';
import '../app/nav.dart';
import '../app/pages.dart';
import '../data/geo.dart';
import '../data/here_store.dart';
import '../features/theme/theme_sheet.dart';
import '../native/bridge.dart';
import '../theme/theme.dart';
import 'adaptive.dart';
import 'alerts_poll.dart';
import 'backdrop.dart';
import 'chrome.dart';
import 'desk.dart';
import 'glance.dart';
import 'host.dart';
import 'location.dart';
import 'notify.dart';
import 'runner.dart';
import 'settings.dart';
import 'splash.dart';
import 'tray.dart';
import 'updater.dart';
import 'welcome.dart';
import 'widgets_window.dart';

/// A desktop widget's own engine runs only its small screen. True when this engine was one.
Future<bool> runDesktopSubWindow(List<String> args) async {
  try {
    final c = await WindowController.fromCurrentEngine();
    if (c.arguments.isEmpty) return false;
    final m = jsonDecode(c.arguments);
    if (m is Map && m['kind'] == 'widget') {
      await runWidgetWindow('${m['id']}');
      return true;
    }
  } catch (_) {
    // The main window.
  }
  return false;
}

/// Before the app: one copy only, the window, the update window, and Make it yours the first time.
Future<void> desktopBeforeApp(List<String> args) async {
  Desktop.launchArgs = args;
  if (!await Desktop.claimInstance(args)) exit(0);
  Native.host = DesktopHost();
  if (Platform.isLinux) Geo.fallback = LinuxLocation.find;
  await Desktop.setUp();
  ThemeController.I.init();
  ThemeController.I.systemAccent = DeskSettings.get<bool>('useSystemAccent') ?? false;

  // The update window, every launch of an installed copy.
  if (!Desktop.fromSource || Platform.environment['UWUHERE_SPLASH_DEMO'] == '1') {
    await splashWindow();
    runApp(const SplashApp());
    await Updater.startup();
  }

  // Make it yours: once, for a new install.
  if (DeskSettings.get<bool>('setupDone') != true) await _welcome();
}

Future<void> _welcome() async {
  final done = Completer<WelcomeChoices?>();
  await welcomeWindow();
  runApp(
    WelcomeApp(
      done: (c) {
        if (!done.isCompleted) done.complete(c);
      },
    ),
  );
  await applyWelcome(await done.future);
}

/// The event before or after the open one, in your events' order, round from the end.
void _stepEvent(int by) {
  final all = Glance.favourites();
  if (all.isEmpty) return;
  final at = all.indexWhere((e) => e['code'] == AppPages.hostCode.value);
  final next = all[((at < 0 ? 0 : at + by) % all.length + all.length) % all.length];
  Desktop.show('uwu://here/host?id=${next['code']}');
}

/// After the app's started: the chrome round it, the tray, notifications, the glance surfaces,
/// the widgets, links, start at sign-in, and the update checks.
Future<void> desktopAfterApp(List<String> args) async {
  desktopChrome = (context, child) => DesktopChrome(child: child);
  // The system's accent, read now and again whenever the window comes back to the front (it may
  // have been changed in the system's settings meanwhile): the system's glass is in it, and the
  // UwU Apps look can use it in place of the brand colour.
  ThemeController.I.setSystemAccentColor(_readAccent(_runSync));
  AppLifecycleListener(
    onResume: () async => ThemeController.I.setSystemAccentColor(_readAccent(await _runAll(_accentCommands()))),
  );
  desktopAccentScheme = (b) => ColorScheme.fromSeed(seedColor: ThemeController.I.systemAccentColor ?? const Color(0xFF22A85A), brightness: b);
  desktopAccentGet = () => ThemeController.I.systemAccent;
  desktopAccentSet = (on) {
    DeskSettings.write({'useSystemAccent': on});
    ThemeController.I.setSystemAccent(on);
  };
  Fullscreen.desktop = Desktop.setFullScreen;
  Desktop.fullScreen.addListener(() => Fullscreen.on.value = Desktop.fullScreen.value);
  desktopEventMenu = (context, at, code, name) => showContextMenu(context as BuildContext, at as Offset, [
    MenuAction('Open in Split Pane', () => Desktop.show('uwu://here/host?id=$code'), icon: 'sidebar'),
    MenuAction('Pin to Desktop Widget', () => DeskWidgets.add(code, name), icon: 'widget'),
    MenuAction('Set as Tray Glance', () => Glance.follow(code, name), icon: 'pushpin'),
    MenuAction('Copy Link', () => copyText('https://here.uwuapps.org/join?id=$code'), icon: 'link'),
  ]);
  ViewHistory.start();
  Runner.listen();
  Backdrop.start();
  Runner.onDock = (code) => Desktop.show('uwu://here/host?id=$code');
  // The taskbar's thumbnail buttons: refresh what's on show where it is, or the event before or
  // after the open one.
  Runner.onThumbnailButton = (what) {
    switch (what) {
      case 'toggle':
        Glance.refreshTray();
        refreshPage();
      case 'previous':
        _stepEvent(-1);
      case 'next':
        _stepEvent(1);
    }
  };
  HereStore.changes('hosted').listen((_) => Glance.favouritesChanged());
  Runner.onOpen = (link) => link == null ? Desktop.show() : Desktop.onSecondCopy([link]);
  DeskWidgets.listen((link) => Desktop.show(link));
  Updater.showSplash = () async {
    await splashWindow();
    runApp(const SplashApp());
  };
  DeskTray.openWelcome = () async {
    await Desktop.hide();
    // Not the main window for now: its size and place stay as they were kept, not the welcome
    // window's, and it comes back maximised if it was.
    Desktop.shown = false;
    final done = Completer<WelcomeChoices?>();
    await welcomeWindow();
    runApp(
      WelcomeApp(
        done: (c) {
          if (!done.isCompleted) done.complete(c);
        },
      ),
    );
    await applyWelcome(await done.future);
    Desktop.shown = false;
    runApp(const UwuHereApp());
    await Desktop.firstShow();
  };

  await DeskNotify.initialize();
  await Desktop.firstShow();
  unawaited(DeskTray.instance.start());
  Glance.start();
  AlertsPoll.start();
  unawaited(DeskWidgets.reopenAll());
  unawaited(Desktop.registerScheme());
  unawaited(Desktop.startAtLoginFirstRun());
  Updater.start();
}

/// The commands that say the system's accent: Windows' DWM accent, macOS's AppleAccentColor,
/// GNOME's accent-color and Deepin's active colour.
List<List<String>> _accentCommands() {
  if (Platform.isWindows) return [['reg', 'query', r'HKCU\Software\Microsoft\Windows\DWM', '/v', 'AccentColor']];
  if (Platform.isMacOS) return [['defaults', 'read', '-g', 'AppleAccentColor']];
  return [
    ['gsettings', 'get', 'org.gnome.desktop.interface', 'accent-color'],
    ['gsettings', 'get', 'com.deepin.dde.appearance', 'qt-active-color'],
  ];
}

/// What each command printed ('' for one that failed), at start-up, before the first frame.
List<String> get _runSync => [
  for (final c in _accentCommands())
    (() {
      try {
        return '${Process.runSync(c.first, c.sublist(1)).stdout}';
      } catch (_) {
        return '';
      }
    })(),
];

/// The same, later, without holding up the window.
Future<List<String>> _runAll(List<List<String>> commands) => Future.wait([
  for (final c in commands)
    Process.run(c.first, c.sublist(1)).then((r) => '${r.stdout}').catchError((_) => ''),
]);

/// The system's accent colour from what [_accentCommands] printed, or COSMIC's from its theme
/// file, or null where none can be read.
Color? _readAccent(List<String> out) {
  try {
    if (Platform.isWindows) {
      final m = RegExp(r'0x([0-9a-fA-F]{8})').firstMatch(out.first);
      if (m == null) return null;
      // ABGR.
      final v = int.parse(m.group(1)!, radix: 16);
      return Color.fromARGB(255, v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff);
    }
    if (Platform.isMacOS) {
      const accents = {
        '-1': Color(0xFF8E8E93),
        '0': Color(0xFFFF3B30),
        '1': Color(0xFFFF9500),
        '2': Color(0xFFFFCC00),
        '3': Color(0xFF34C759),
        '5': Color(0xFFAF52DE),
        '6': Color(0xFFFF2D55),
      };
      // Unset is the multicolour default: blue.
      return accents[out.first.trim()] ?? const Color(0xFF007AFF);
    }
    const gnome = {
      'blue': Color(0xFF3584E4),
      'teal': Color(0xFF2190A4),
      'green': Color(0xFF3A944A),
      'yellow': Color(0xFFC88800),
      'orange': Color(0xFFED5B00),
      'red': Color(0xFFE62D42),
      'pink': Color(0xFFD56199),
      'purple': Color(0xFF9141AC),
      'slate': Color(0xFF6F8396),
    };
    final desktop = (Platform.environment['XDG_CURRENT_DESKTOP'] ?? '').toUpperCase();
    // Deepin's: '#0081FF'.
    if (desktop.contains('DEEPIN') || desktop.contains('DDE')) {
      final m = RegExp(r'#([0-9a-fA-F]{6})').firstMatch(out.length > 1 ? out[1] : '');
      if (m != null) return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
    }
    // COSMIC's: its theme's accent, as red, green and blue from 0 to 1.
    if (desktop.contains('COSMIC')) {
      final home = Platform.environment['HOME'] ?? '';
      final config = Platform.environment['XDG_CONFIG_HOME'] ?? '$home/.config';
      for (final mode in ['Dark', 'Light']) {
        final f = File('$config/cosmic/com.system76.CosmicTheme.$mode.Builder/v1/accent');
        if (!f.existsSync()) continue;
        double? part(String name) => double.tryParse(RegExp('$name:\\s*([0-9.]+)').firstMatch(f.readAsStringSync())?.group(1) ?? '');
        final r = part('red'), g = part('green'), b = part('blue');
        if (r != null && g != null && b != null) return Color.from(alpha: 1, red: r.clamp(0, 1), green: g.clamp(0, 1), blue: b.clamp(0, 1));
      }
    }
    return gnome[out.first.replaceAll("'", '').trim()];
  } catch (_) {
    return null;
  }
}
