// The desktop app's core (docs/desktop-features-spec.md): its one main window, kept running in
// the tray when closed, one copy at a time, starting at sign-in, and uwu://here/ links shared
// with the sibling UwU Apps. Its names and places never change, so each version installs over the
// last and its shortcuts, links and settings carry on.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../app/links.dart';
import 'settings.dart';

class Desktop {
  Desktop._();

  static const name = 'uwuHere';
  static const appId = 'org.uwuapps.here';
  static const site = 'https://here.uwuapps.org';
  static const releases = 'https://github.com/augy-studios/uwuHere/releases/latest';

  /// The .desktop file the .deb installs.
  static const linuxDesktopFile = 'uwuhere-desktop.desktop';

  static bool get mac => Platform.isMacOS;
  static bool get windows => Platform.isWindows;
  static bool get linux => Platform.isLinux;

  /// Run from `flutter run`, not an installed copy: nothing to update, no start at sign-in.
  static bool get fromSource => !kReleaseMode;

  /// The command line the app was started with.
  static List<String> launchArgs = const [];

  /// Quitting for real: closing the window then lets it go.
  static bool quitting = false;

  /// The main window's been shown once (after the update window and Make it yours).
  static bool shown = false;

  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  // ---------- the main window ----------

  static const minSize = Size(800, 600);
  static const compactMin = Size(360, 520);
  static const defaultSize = Size(1120, 760);
  static Rect? _normal;
  static Timer? _keepTimer;

  static final _listener = _WindowEvents();

  /// Hidden, its own title bar, close keeping the app in the tray.
  static Future<void> setUp() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: name,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: true,
        minimumSize: compactMin,
        size: defaultSize,
        center: true,
        skipTaskbar: false,
      ),
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(_listener);
  }

  static void _keepBounds({bool now = false}) {
    if (!shown) return;
    _keepTimer?.cancel();
    Future<void> write() async {
      try {
        final max = await windowManager.isMaximized();
        final full = await windowManager.isFullScreen();
        final min = await windowManager.isMinimized();
        if (!max && !full && !min) _normal = await windowManager.getBounds();
        final b = _normal;
        DeskSettings.write({
          if (b != null) 'bounds': {'x': b.left.round(), 'y': b.top.round(), 'width': b.width.round(), 'height': b.height.round()},
          'maximized': max,
        });
      } catch (_) {}
    }

    if (now) {
      write();
    } else {
      _keepTimer = Timer(const Duration(milliseconds: 600), write);
    }
  }

  /// The window, the first time: at its kept size and place (if that's still on a screen),
  /// maximised unless it was last closed un-maximised.
  static Future<void> firstShow() async {
    if (shown) return;
    shown = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(compactMin);
    final s = DeskSettings.read();
    final b = s['bounds'];
    var placed = false;
    if (b is Map && b['width'] is num && b['height'] is num) {
      final rect = Rect.fromLTWH(
        (b['x'] as num? ?? 40).toDouble(),
        (b['y'] as num? ?? 40).toDouble(),
        (b['width'] as num).toDouble(),
        (b['height'] as num).toDouble(),
      );
      if (_onAScreen(rect)) {
        await windowManager.setBounds(rect);
        placed = true;
      } else {
        await windowManager.setSize(rect.size);
      }
    }
    if (!placed) {
      if (b is! Map) await windowManager.setSize(defaultSize);
      await windowManager.center();
    }
    _normal = await windowManager.getBounds();
    if (s['maximized'] != false) await windowManager.maximize();
    await windowManager.show();
    await windowManager.focus();
    for (final f in List.of(onShown)) {
      f();
    }
  }

  static final List<void Function()> onShown = [];

  static bool _onAScreen(Rect r) {
    try {
      for (final d in ui.PlatformDispatcher.instance.displays) {
        final size = d.size / d.devicePixelRatio;
        if (r.overlaps(Rect.fromLTWH(-size.width, -size.height, size.width * 3, size.height * 3))) return true;
      }
    } catch (_) {}
    return false;
  }

  /// The window, forward; on a link's page if there's one.
  static Future<void> show([String? link]) async {
    if (!shown) {
      await firstShow();
    } else {
      if (await windowManager.isMinimized()) await windowManager.restore();
      await windowManager.show();
      await windowManager.focus();
    }
    if (link != null && link.isNotEmpty) Links.open(link);
  }

  /// Shown and in front, or hidden if it already is (the tray icon's click).
  static Future<void> toggle() async {
    if (shown && await windowManager.isVisible() && await windowManager.isFocused() && !await windowManager.isMinimized()) {
      await hide();
    } else {
      await show();
    }
  }

  /// Into the tray. The first time, a notification says it's still running.
  static Future<void> hide() async {
    _keepBounds(now: true);
    await windowManager.hide();
    if (DeskSettings.get<bool>('trayHintShown') == true) return;
    DeskSettings.write({'trayHintShown': true});
    stillRunning?.call();
  }

  /// Set by notify.dart: "uwuHere is still running".
  static void Function()? stillRunning;

  static Future<bool> get inFront async => shown && await windowManager.isVisible() && await windowManager.isFocused();

  /// Quits: anything waiting for the quit (an update to install) runs first.
  static Future<void> quit() async {
    quitting = true;
    _keepBounds(now: true);
    for (final f in List.of(beforeQuit)) {
      try {
        await f();
      } catch (_) {}
    }
    await windowManager.setPreventClose(false);
    exit(0);
  }

  static final List<Future<void> Function()> beforeQuit = [];

  static Future<void> setFullScreen(bool on) async {
    await windowManager.setFullScreen(on);
    fullScreen.value = on;
  }

  // ---------- one copy at a time ----------

  static ServerSocket? _instance;

  static File get _portFile => File('${DeskSettings.folder}${Platform.pathSeparator}instance.port');

  /// True when this is the only copy. Otherwise the running copy is handed this one's command
  /// line (a link, or just "come forward"), and this one should quit.
  static Future<bool> claimInstance(List<String> args) async {
    try {
      final port = int.tryParse(_portFile.readAsStringSync().trim());
      if (port != null) {
        final s = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 700));
        s.write(jsonEncode({'app': appId, 'args': args}));
        await s.flush();
        await s.close();
        return false;
      }
    } catch (_) {
      // Nobody listening: this copy is the one.
    }
    try {
      _instance = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _portFile.parent.createSync(recursive: true);
      _portFile.writeAsStringSync('${_instance!.port}');
      _instance!.listen((client) {
        utf8.decoder.bind(client).join().then((text) {
          try {
            final m = jsonDecode(text);
            if (m is Map && m['app'] == appId) onSecondCopy(List<String>.from(m['args'] as List? ?? const []));
          } catch (_) {}
        });
      });
    } catch (_) {}
    return true;
  }

  /// Another copy was opened: this one comes forward, on its link if it had one.
  static void onSecondCopy(List<String> args) {
    final link = linkIn(args);
    if (link != null && !_ours(link)) {
      handOff(link);
      return;
    }
    show(link);
  }

  // ---------- links ----------

  static String? linkIn(List<String> args) => args.where((a) => a.toLowerCase().startsWith('$appScheme://')).firstOrNull;

  static bool _ours(String link) => (Uri.tryParse(link)?.host ?? '').toLowerCase() == appHost;

  /// Registers uwu:// for this app at every start (Windows), so links keep working after an update
  /// or a move. A desktop gives a scheme to one app only, so whichever UwU App holds it is noted
  /// first, and links for its host are handed to it (handOff).
  static Future<void> registerScheme() async {
    if (fromSource) return;
    if (windows) {
      final exe = Platform.resolvedExecutable;
      const key = r'HKCU\Software\Classes\uwu';
      final mine = '"$exe" "%1"';
      try {
        final r = await Process.run('reg', ['query', '$key\\shell\\open\\command', '/ve']);
        final current = RegExp(r'REG_SZ\s+(.+)$', multiLine: true).firstMatch('${r.stdout}')?.group(1)?.trim();
        if (current != null && current.isNotEmpty && current.toLowerCase() != mine.toLowerCase() && !current.toLowerCase().contains('uwuhere')) {
          DeskSettings.write({
            'linkHandoff': {'command': current},
          });
        }
        await Process.run('reg', ['add', key, '/ve', '/d', 'URL:UwU Apps link', '/f']);
        await Process.run('reg', ['add', key, '/v', 'URL Protocol', '/d', '', '/f']);
        await Process.run('reg', ['add', '$key\\shell\\open\\command', '/ve', '/d', mine, '/f']);
      } catch (_) {}
    } else if (linux) {
      try {
        final r = await Process.run('xdg-mime', ['query', 'default', 'x-scheme-handler/uwu']);
        final current = '${r.stdout}'.trim();
        if (current.isNotEmpty && current != linuxDesktopFile) {
          DeskSettings.write({
            'linkHandoff': {'desktop': current},
          });
        }
        await Process.run('xdg-mime', ['default', linuxDesktopFile, 'x-scheme-handler/uwu']);
      } catch (_) {}
    }
  }

  /// A link for another UwU App, passed to the one that held the scheme before this one, as one
  /// argument and never through a shell.
  static Future<bool> handOff(String link) async {
    final h = DeskSettings.get<Map<String, dynamic>>('linkHandoff');
    try {
      if (windows && h?['command'] is String) {
        final parts = RegExp(r'"([^"]+)"|(\S+)').allMatches(h!['command'] as String).map((m) => m.group(1) ?? m.group(2)!).toList();
        if (parts.isEmpty) return false;
        final args = [for (final p in parts.skip(1)) p == '%1' ? link : p];
        if (!args.contains(link)) args.add(link);
        await Process.start(parts.first, args, mode: ProcessStartMode.detached);
        return true;
      }
      if (linux && h?['desktop'] is String) {
        await Process.start('gtk-launch', [h!['desktop'] as String, link], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ---------- starting at sign-in ----------

  static File get _autostart => File('${Platform.environment['XDG_CONFIG_HOME'] ?? '${Platform.environment['HOME']}/.config'}/autostart/uwuhere.desktop');
  static File get _launchAgent => File('${Platform.environment['HOME']}/Library/LaunchAgents/$appId.plist');
  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  static Future<bool> startsAtLogin() async {
    try {
      if (linux) return _autostart.existsSync();
      if (mac) return _launchAgent.existsSync();
      final r = await Process.run('reg', ['query', _runKey, '/v', name]);
      return r.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  static Future<void> setStartAtLogin(bool on) async {
    if (fromSource) return;
    try {
      if (linux) {
        final f = _autostart;
        if (!on) {
          if (f.existsSync()) f.deleteSync();
          return;
        }
        // An AppImage runs from a temporary mount, so it's started by the file itself.
        final exec = Platform.environment['APPIMAGE'] ?? Platform.resolvedExecutable;
        f.parent.createSync(recursive: true);
        f.writeAsStringSync(
          ['[Desktop Entry]', 'Type=Application', 'Name=$name', 'Exec="$exec" --hidden', 'Icon=uwuhere', 'X-GNOME-Autostart-enabled=true', ''].join('\n'),
        );
      } else if (mac) {
        final f = _launchAgent;
        if (!on) {
          if (f.existsSync()) f.deleteSync();
          return;
        }
        final app = File(Platform.resolvedExecutable).parent.parent.parent.path;
        f.parent.createSync(recursive: true);
        f.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$appId</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$app</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
''');
      } else {
        if (on) {
          await Process.run('reg', ['add', _runKey, '/v', name, '/d', '"${Platform.resolvedExecutable}"', '/f']);
        } else {
          await Process.run('reg', ['delete', _runKey, '/v', name, '/f']);
        }
      }
    } catch (_) {}
  }

  /// From the first run of an installed copy the app starts at sign-in, until it's turned off;
  /// once chosen, the choice sticks (loginChosen).
  static Future<void> startAtLoginFirstRun() async {
    if (fromSource || DeskSettings.get<bool>('loginChosen') == true) return;
    await setStartAtLogin(true);
    DeskSettings.write({'loginChosen': true});
  }

  // ---------- small things ----------

  /// Opens a link in the browser (or mail app).
  static Future<void> openExternal(String url) async {
    try {
      if (windows) {
        await Process.start('rundll32', ['url.dll,FileProtocolHandler', url], mode: ProcessStartMode.detached);
      } else if (mac) {
        await Process.start('open', [url], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [url], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }

  /// Shows a file in its folder.
  static Future<void> showInFolder(String path) async {
    try {
      if (windows) {
        await Process.start('explorer.exe', ['/select,', path], mode: ProcessStartMode.detached);
      } else if (mac) {
        await Process.start('open', ['-R', path], mode: ProcessStartMode.detached);
      } else {
        await Process.start('xdg-open', [File(path).parent.path], mode: ProcessStartMode.detached);
      }
    } catch (_) {}
  }

  /// The Downloads folder.
  static String get downloads {
    final env = Platform.environment;
    if (windows) return '${env['USERPROFILE']}\\Downloads';
    final home = env['HOME'] ?? '';
    if (linux) {
      try {
        final dirs = File('$home/.config/user-dirs.dirs').readAsStringSync();
        final m = RegExp(r'^XDG_DOWNLOAD_DIR="(.+)"$', multiLine: true).firstMatch(dirs);
        if (m != null) return m[1]!.replaceAll(r'$HOME', home);
      } catch (_) {}
    }
    return '$home/Downloads';
  }
}

class _WindowEvents with WindowListener {
  @override
  void onWindowClose() {
    // Not while the window is Make it yours or the update window: they handle their own close.
    if (Desktop.quitting || !Desktop.shown) return;
    Desktop.hide();
  }

  @override
  void onWindowMoved() => Desktop._keepBounds();

  @override
  void onWindowResized() => Desktop._keepBounds();

  @override
  void onWindowMaximize() {
    Desktop.maximized.value = true;
    Desktop._keepBounds();
  }

  @override
  void onWindowUnmaximize() {
    Desktop.maximized.value = false;
    Desktop._keepBounds();
  }

  @override
  void onWindowEnterFullScreen() => Desktop.fullScreen.value = true;

  @override
  void onWindowLeaveFullScreen() => Desktop.fullScreen.value = false;
}
