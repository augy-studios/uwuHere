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

  static bool get mac {
    return Platform.isMacOS;
  }

  static bool get windows {
    return Platform.isWindows;
  }

  static bool get linux {
    return Platform.isLinux;
  }

  /// Run from `flutter run`, not an installed copy: nothing to update, no start at sign-in.
  static bool get fromSource {
    return !kReleaseMode;
  }

  /// The command line the app was started with.
  static List<String> launchArgs = const [];

  /// Quitting for real: closing the window then lets it go.
  static bool quitting = false;

  /// The main window's been shown once (after the update window and Make it yours).
  static bool shown = false;

  static final ValueNotifier<bool> fullScreen = ValueNotifier(false);
  static final ValueNotifier<bool> maximized = ValueNotifier(false);

  // ---------- the main window ----------

  static const minimumSize = Size(800, 600);
  static const compactMinimumSize = Size(360, 520);
  static const defaultSize = Size(1120, 760);

  /// The window's size and place when last neither maximised, full screen nor minimised.
  static Rect? _normalBounds;
  static Timer? _keepBoundsTimer;

  static final _windowListener = _WindowEvents();

  /// Hidden, its own title bar, close keeping the app in the tray.
  static Future<void> setUp() async {
    await windowManager.ensureInitialized();
    await windowManager.waitUntilReadyToShow(
      const WindowOptions(
        title: name,
        titleBarStyle: TitleBarStyle.hidden,
        windowButtonVisibility: true,
        minimumSize: compactMinimumSize,
        size: defaultSize,
        center: true,
        skipTaskbar: false,
      ),
    );
    await windowManager.setPreventClose(true);
    windowManager.addListener(_windowListener);
  }

  /// Saves the window's size, place and maximised state, so the next launch opens it the same.
  /// While it's being moved or resized this waits until it has been still for 600 ms; with
  /// [now] it saves straight away.
  static void _keepBounds({bool now = false}) {
    if (!shown) {
      return;
    }
    if (_keepBoundsTimer != null) {
      _keepBoundsTimer!.cancel();
    }
    Future<void> write() async {
      try {
        final isMaximized = await windowManager.isMaximized();
        final isFullScreen = await windowManager.isFullScreen();
        final isMinimized = await windowManager.isMinimized();
        if (!isMaximized && !isFullScreen && !isMinimized) {
          _normalBounds = await windowManager.getBounds();
        }
        final bounds = _normalBounds;
        DeskSettings.write({
          if (bounds != null) 'bounds': {'x': bounds.left.round(), 'y': bounds.top.round(), 'width': bounds.width.round(), 'height': bounds.height.round()},
          'maximized': isMaximized,
        });
      } catch (_) {}
    }

    if (now) {
      write();
    } else {
      _keepBoundsTimer = Timer(const Duration(milliseconds: 600), write);
    }
  }

  /// The window, the first time: at its kept size and place (if that's still on a screen),
  /// maximised unless it was last closed un-maximised.
  static Future<void> firstShow() async {
    if (shown) {
      return;
    }
    shown = true;
    await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: true);
    await windowManager.setResizable(true);
    await windowManager.setMinimumSize(compactMinimumSize);
    final settings = DeskSettings.read();
    final savedBounds = settings['bounds'];
    var placed = false;
    if (savedBounds is Map && savedBounds['width'] is num && savedBounds['height'] is num) {
      final savedLeft = savedBounds['x'] as num?;
      double left = 40;
      if (savedLeft != null) {
        left = savedLeft.toDouble();
      }
      final savedTop = savedBounds['y'] as num?;
      double top = 40;
      if (savedTop != null) {
        top = savedTop.toDouble();
      }
      final rectangle = Rect.fromLTWH(
        left,
        top,
        (savedBounds['width'] as num).toDouble(),
        (savedBounds['height'] as num).toDouble(),
      );
      if (_onAScreen(rectangle)) {
        await windowManager.setBounds(rectangle);
        placed = true;
      } else {
        await windowManager.setSize(rectangle.size);
      }
    }
    if (!placed) {
      if (savedBounds is! Map) {
        await windowManager.setSize(defaultSize);
      }
      await windowManager.center();
    }
    _normalBounds = await windowManager.getBounds();
    if (settings['maximized'] != false) {
      await windowManager.maximize();
    }
    await windowManager.show();
    await windowManager.focus();
    for (final callback in List.of(onShown)) {
      callback();
    }
  }

  static final List<void Function()> onShown = [];

  /// Whether a rectangle is on (or near) one of the screens: it counts if it overlaps a screen
  /// widened by a whole screen's size on every side.
  static bool _onAScreen(Rect rectangle) {
    try {
      for (final display in ui.PlatformDispatcher.instance.displays) {
        final size = display.size / display.devicePixelRatio;
        if (rectangle.overlaps(Rect.fromLTWH(-size.width, -size.height, size.width * 3, size.height * 3))) {
          return true;
        }
      }
    } catch (_) {}
    return false;
  }

  /// The window, forward; on a link's page if there's one.
  static Future<void> show([String? link]) async {
    if (!shown) {
      await firstShow();
    } else {
      if (await windowManager.isMinimized()) {
        await windowManager.restore();
      }
      await windowManager.show();
      await windowManager.focus();
    }
    if (link != null && link.isNotEmpty) {
      Links.open(link);
    }
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
    if (DeskSettings.get<bool>('trayHintShown') == true) {
      return;
    }
    DeskSettings.write({'trayHintShown': true});
    final stillRunningCallback = stillRunning;
    if (stillRunningCallback != null) {
      stillRunningCallback();
    }
  }

  /// Set by notify.dart: "uwuHere is still running".
  static void Function()? stillRunning;

  /// Whether the window has been shown and is visible and focused right now.
  static Future<bool> get inFront async {
    if (!shown) {
      return false;
    }
    if (!await windowManager.isVisible()) {
      return false;
    }
    return await windowManager.isFocused();
  }

  /// Quits: anything waiting for the quit (an update to install) runs first.
  static Future<void> quit() async {
    quitting = true;
    _keepBounds(now: true);
    for (final action in List.of(beforeQuit)) {
      try {
        await action();
      } catch (_) {}
    }
    await windowManager.setPreventClose(false);
    exit(0);
  }

  static final List<Future<void> Function()> beforeQuit = [];

  static Future<void> setFullScreen(bool enabled) async {
    await windowManager.setFullScreen(enabled);
    fullScreen.value = enabled;
  }

  // ---------- one copy at a time ----------

  static ServerSocket? _instanceServer;

  static File get _portFile {
    return File('${DeskSettings.folder}${Platform.pathSeparator}instance.port');
  }

  /// True when this is the only copy. Otherwise the running copy is handed this one's command
  /// line (a link, or just "come forward"), and this one should quit.
  ///
  /// The running copy listens on a local port written to instance.port; a new copy that can
  /// reach it sends its command line there and gives way. Otherwise the new copy starts
  /// listening itself.
  static Future<bool> claimInstance(List<String> commandLineArguments) async {
    try {
      final port = int.tryParse(_portFile.readAsStringSync().trim());
      if (port != null) {
        final socket = await Socket.connect(InternetAddress.loopbackIPv4, port, timeout: const Duration(milliseconds: 700));
        socket.write(jsonEncode({'app': appId, 'args': commandLineArguments}));
        await socket.flush();
        await socket.close();
        return false;
      }
    } catch (_) {
      // Nobody listening: this copy is the one.
    }
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      _instanceServer = server;
      _portFile.parent.createSync(recursive: true);
      _portFile.writeAsStringSync('${server.port}');
      server.listen((client) {
        utf8.decoder.bind(client).join().then((text) {
          try {
            final message = jsonDecode(text);
            if (message is Map && message['app'] == appId) {
              final sentArguments = message['args'] as List?;
              List<dynamic> argumentList;
              if (sentArguments == null) {
                argumentList = const [];
              } else {
                argumentList = sentArguments;
              }
              onSecondCopy(List<String>.from(argumentList));
            }
          } catch (_) {}
        });
      });
    } catch (_) {}
    return true;
  }

  /// Another copy was opened: this one comes forward, on its link if it had one.
  static void onSecondCopy(List<String> commandLineArguments) {
    final link = linkIn(commandLineArguments);
    if (link != null && !_isForThisApp(link)) {
      handOff(link);
      return;
    }
    show(link);
  }

  // ---------- links ----------

  /// The first uwu:// link on a command line, if there is one.
  static String? linkIn(List<String> commandLineArguments) {
    for (final argument in commandLineArguments) {
      if (argument.toLowerCase().startsWith('$appScheme://')) {
        return argument;
      }
    }
    return null;
  }

  /// Whether a uwu:// link is for this app (uwu://here/) rather than another UwU App.
  static bool _isForThisApp(String link) {
    final uri = Uri.tryParse(link);
    String host = '';
    if (uri != null) {
      host = uri.host;
    }
    return host.toLowerCase() == appHost;
  }

  /// Registers uwu:// for this app at every start (Windows), so links keep working after an update
  /// or a move. A desktop gives a scheme to one app only, so whichever UwU App holds it is noted
  /// first, and links for its host are handed to it (handOff).
  static Future<void> registerScheme() async {
    if (fromSource) {
      return;
    }
    if (windows) {
      final executablePath = Platform.resolvedExecutable;
      const registryKey = r'HKCU\Software\Classes\uwu';
      final ourCommand = '"$executablePath" "%1"';
      try {
        final queryResult = await Process.run('reg', ['query', '$registryKey\\shell\\open\\command', '/ve']);
        final match = RegExp(r'REG_SZ\s+(.+)$', multiLine: true).firstMatch('${queryResult.stdout}');
        String? currentCommand;
        if (match != null) {
          final matchedCommand = match.group(1);
          if (matchedCommand != null) {
            currentCommand = matchedCommand.trim();
          }
        }
        if (currentCommand != null && currentCommand.isNotEmpty && currentCommand.toLowerCase() != ourCommand.toLowerCase() && !currentCommand.toLowerCase().contains('uwuhere')) {
          DeskSettings.write({
            'linkHandoff': {'command': currentCommand},
          });
        }
        await Process.run('reg', ['add', registryKey, '/ve', '/d', 'URL:UwU Apps link', '/f']);
        await Process.run('reg', ['add', registryKey, '/v', 'URL Protocol', '/d', '', '/f']);
        await Process.run('reg', ['add', '$registryKey\\shell\\open\\command', '/ve', '/d', ourCommand, '/f']);
      } catch (_) {}
    } else if (linux) {
      try {
        final queryResult = await Process.run('xdg-mime', ['query', 'default', 'x-scheme-handler/uwu']);
        final currentHandler = '${queryResult.stdout}'.trim();
        if (currentHandler.isNotEmpty && currentHandler != linuxDesktopFile) {
          DeskSettings.write({
            'linkHandoff': {'desktop': currentHandler},
          });
        }
        await Process.run('xdg-mime', ['default', linuxDesktopFile, 'x-scheme-handler/uwu']);
      } catch (_) {}
    }
  }

  /// A link for another UwU App, passed to the one that held the scheme before this one, as one
  /// argument and never through a shell.
  static Future<bool> handOff(String link) async {
    final handoff = DeskSettings.get<Map<String, dynamic>>('linkHandoff');
    try {
      if (windows && handoff != null && handoff['command'] is String) {
        // The saved command split into its parts: "quoted parts" or plain words.
        final parts = <String>[];
        for (final match in RegExp(r'"([^"]+)"|(\S+)').allMatches(handoff['command'] as String)) {
          final quotedPart = match.group(1);
          if (quotedPart != null) {
            parts.add(quotedPart);
          } else {
            parts.add(match.group(2)!);
          }
        }
        if (parts.isEmpty) {
          return false;
        }
        // The link goes where the command has %1, or on the end.
        final launchArguments = <String>[];
        for (final part in parts.skip(1)) {
          if (part == '%1') {
            launchArguments.add(link);
          } else {
            launchArguments.add(part);
          }
        }
        if (!launchArguments.contains(link)) {
          launchArguments.add(link);
        }
        await Process.start(parts.first, launchArguments, mode: ProcessStartMode.detached);
        return true;
      }
      if (linux && handoff != null && handoff['desktop'] is String) {
        await Process.start('gtk-launch', [handoff['desktop'] as String, link], mode: ProcessStartMode.detached);
        return true;
      }
    } catch (_) {}
    return false;
  }

  // ---------- starting at sign-in ----------

  /// Linux: the autostart entry, in $XDG_CONFIG_HOME (or ~/.config) /autostart.
  static File get _autostartFile {
    final configFolderSetting = Platform.environment['XDG_CONFIG_HOME'];
    String configFolder;
    if (configFolderSetting != null) {
      configFolder = configFolderSetting;
    } else {
      configFolder = '${Platform.environment['HOME']}/.config';
    }
    return File('$configFolder/autostart/uwuhere.desktop');
  }

  /// macOS: the launch agent that opens the app at sign-in.
  static File get _launchAgentFile {
    return File('${Platform.environment['HOME']}/Library/LaunchAgents/$appId.plist');
  }

  static const _runKey = r'HKCU\Software\Microsoft\Windows\CurrentVersion\Run';

  static Future<bool> startsAtLogin() async {
    try {
      if (linux) {
        return _autostartFile.existsSync();
      }
      if (mac) {
        return _launchAgentFile.existsSync();
      }
      final result = await Process.run('reg', ['query', _runKey, '/v', name]);
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }

  /// Turns starting at sign-in on or off: an autostart entry (Linux), a launch agent (macOS) or
  /// the Run key in the registry (Windows).
  static Future<void> setStartAtLogin(bool enabled) async {
    if (fromSource) {
      return;
    }
    try {
      if (linux) {
        final file = _autostartFile;
        if (!enabled) {
          if (file.existsSync()) {
            file.deleteSync();
          }
          return;
        }
        // An AppImage runs from a temporary mount, so it's started by the file itself.
        final appImagePath = Platform.environment['APPIMAGE'];
        String executablePath;
        if (appImagePath != null) {
          executablePath = appImagePath;
        } else {
          executablePath = Platform.resolvedExecutable;
        }
        file.parent.createSync(recursive: true);
        file.writeAsStringSync(
          ['[Desktop Entry]', 'Type=Application', 'Name=$name', 'Exec="$executablePath" --hidden', 'Icon=uwuhere', 'X-GNOME-Autostart-enabled=true', ''].join('\n'),
        );
      } else if (mac) {
        final file = _launchAgentFile;
        if (!enabled) {
          if (file.existsSync()) {
            file.deleteSync();
          }
          return;
        }
        final appBundlePath = File(Platform.resolvedExecutable).parent.parent.parent.path;
        file.parent.createSync(recursive: true);
        file.writeAsStringSync('''<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$appId</string>
<key>ProgramArguments</key><array><string>/usr/bin/open</string><string>-a</string><string>$appBundlePath</string></array>
<key>RunAtLoad</key><true/>
</dict></plist>
''');
      } else {
        if (enabled) {
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
    if (fromSource || DeskSettings.get<bool>('loginChosen') == true) {
      return;
    }
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

  /// The Downloads folder: on Linux, the one named in ~/.config/user-dirs.dirs if there is one.
  static String get downloads {
    final environment = Platform.environment;
    if (windows) {
      return '${environment['USERPROFILE']}\\Downloads';
    }
    final homeSetting = environment['HOME'];
    String home = '';
    if (homeSetting != null) {
      home = homeSetting;
    }
    if (linux) {
      try {
        final userFolders = File('$home/.config/user-dirs.dirs').readAsStringSync();
        final match = RegExp(r'^XDG_DOWNLOAD_DIR="(.+)"$', multiLine: true).firstMatch(userFolders);
        if (match != null) {
          return match[1]!.replaceAll(r'$HOME', home);
        }
      } catch (_) {}
    }
    return '$home/Downloads';
  }
}

/// Follows the main window: close puts it in the tray, moves and resizes are saved, and the
/// maximised and full screen states are kept for the title bar.
class _WindowEvents with WindowListener {
  @override
  void onWindowClose() {
    // Not while the window is Make it yours or the update window: they handle their own close.
    if (Desktop.quitting || !Desktop.shown) {
      return;
    }
    Desktop.hide();
  }

  @override
  void onWindowMoved() {
    Desktop._keepBounds();
  }

  @override
  void onWindowResized() {
    Desktop._keepBounds();
  }

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
  void onWindowEnterFullScreen() {
    Desktop.fullScreen.value = true;
  }

  @override
  void onWindowLeaveFullScreen() {
    Desktop.fullScreen.value = false;
  }
}
