// The welcome window, "Make it yours" (docs/desktop-features-spec.md §1): the first window of a
// new install, and from the tray's menu after that. Left, a welcome panel in the brand colour;
// right, the choices: start at sign-in, follow the system's light or dark, the theme, and the
// brand colour (or the system's accent). It previews as you pick, and Get started applies
// everything through the app's own settings (ThemeController), so there's one set of settings.
// Closing it any other way changes nothing, but it still counts as seen.
//
// The site is in English only, so there's no language row: the spec's four languages are the
// site's own, and this site has one.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:window_manager/window_manager.dart';

import '../theme/icons.dart';
import '../theme/theme.dart';
import 'desk.dart';
import 'settings.dart';

class WelcomeChoices {
  bool startAtLogin = true;
  bool followSystem = false;
  String mode = 'light';
  String colour = 'classic';
  bool accent = false;
}

class WelcomeApp extends StatefulWidget {
  const WelcomeApp({super.key, required this.done});

  /// Called with the choices on Get started, or null when the window's closed.
  final void Function(WelcomeChoices? choices) done;

  @override
  State<WelcomeApp> createState() => _WelcomeAppState();
}

class _WelcomeAppState extends State<WelcomeApp> with WindowListener {
  final c = WelcomeChoices();
  Brightness _system = SchedulerBinding.instance.platformDispatcher.platformBrightness;

  @override
  void initState() {
    super.initState();
    // What's set already, filled in.
    final t = ThemeController.I;
    c.mode = t.modePreference;
    c.colour = t.colorThemeId;
    c.accent = DeskSettings.get<bool>('useSystemAccent') ?? false;
    c.followSystem = DeskSettings.get<bool>('followSystem') ?? false;
    Desktop.startsAtLogin().then((on) {
      if (mounted) setState(() => c.startAtLogin = DeskSettings.get<bool>('loginChosen') == true ? on : true);
    });
    SchedulerBinding.instance.platformDispatcher.onPlatformBrightnessChanged = () {
      if (mounted) setState(() => _system = SchedulerBinding.instance.platformDispatcher.platformBrightness);
    };
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  @override
  void onWindowClose() => widget.done(null);

  Brightness get _brightness {
    if (c.followSystem) return _system;
    return resolveMode(c.mode) == 'dark' ? Brightness.dark : Brightness.light;
  }

  @override
  Widget build(BuildContext context) {
    final brand = colorThemes.firstWhere((t) => t.id == c.colour).color;
    final theme = buildTheme(look: lookUwuApps, brightness: _brightness, brand: brand, desktop: true);
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Make uwuHere yours',
      theme: theme,
      themeAnimationDuration: Duration(milliseconds: reduce ? 0 : 200),
      home: Builder(
        builder: (context) {
          final u = UwuColors.of(context);
          return Scaffold(
            body: Column(
              children: [
                SizedBox(
                  height: 40,
                  child: Row(
                    children: [
                      Expanded(
                        child: DragToMoveArea(
                          child: Container(
                            padding: const EdgeInsets.only(left: 16),
                            alignment: Alignment.centerLeft,
                            child: Text('Make uwuHere yours', style: TextStyle(color: u.muted, fontSize: 12)),
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close',
                        onPressed: () => widget.done(null),
                        icon: AppIcon('close', size: 16, color: u.ink),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, box) {
                      final wide = box.maxWidth >= 760;
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (wide) SizedBox(width: box.maxWidth / 3, child: _panel(brand)),
                          Expanded(child: _choices(context, u)),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _panel(Color brand) {
    const ink = Color(0xFF121815);
    Widget feature(String icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          AppIcon(icon, size: 20, color: ink),
          const SizedBox(width: 10),
          Expanded(
            child: Text(text, style: const TextStyle(color: ink, fontSize: 14)),
          ),
        ],
      ),
    );
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [brand, Color.lerp(brand, Colors.white, 0.45)!]),
      ),
      child: Stack(
        children: [
          Positioned(top: -40, right: -40, child: _circle(140)),
          Positioned(bottom: -60, left: -50, child: _circle(180)),
          Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClipRRect(borderRadius: BorderRadius.circular(18), child: Image.asset('assets/images/icon-512.png', width: 72, height: 72)),
                const SizedBox(height: 18),
                const Text(
                  'Welcome to uwuHere',
                  style: TextStyle(color: ink, fontSize: 24, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                const Text("Take attendance in one tap. People check in when they're near you.", style: TextStyle(color: ink, fontSize: 14)),
                const SizedBox(height: 26),
                feature('qr', 'A code, a link and a QR code for every event'),
                feature('wifi', 'Checked in on the same wifi, or near by location'),
                feature('widget', 'Your event on the desktop, the taskbar and the tray'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _circle(double size) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.18), shape: BoxShape.circle),
  );

  Widget _choices(BuildContext context, UwuColors u) {
    Widget row(String icon, String label, Widget control) => Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: u.surfaceStrong,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: u.border),
      ),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(color: u.brandFill, borderRadius: BorderRadius.circular(10)),
            child: Center(child: AppIcon(icon, size: 18, color: u.onBrand)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: TextStyle(color: u.ink, fontSize: 14)),
          ),
          control,
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 12, 32, 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Make uwuHere yours',
            style: TextStyle(color: u.ink, fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text('Choose how the app should look and feel.', style: TextStyle(color: u.muted, fontSize: 14)),
          const SizedBox(height: 18),
          Expanded(
            child: ListView(
              children: [
                row('power', 'Start when I sign in', Switch(value: c.startAtLogin, onChanged: (v) => setState(() => c.startAtLogin = v))),
                row('sun', 'Follow system theme', Switch(value: c.followSystem, onChanged: (v) => setState(() => c.followSystem = v))),
                row(
                  'moon',
                  'Theme',
                  MouseRegion(
                    // A dropdown has no cursor of its own to set: the hand while it can be opened.
                    cursor: c.followSystem ? SystemMouseCursors.basic : SystemMouseCursors.click,
                    child: DropdownButton<String>(
                      value: c.mode,
                      underline: const SizedBox.shrink(),
                      onChanged: c.followSystem ? null : (v) => setState(() => c.mode = v ?? 'light'),
                      items: const [
                        DropdownMenuItem(value: 'light', child: Text('Light')),
                        DropdownMenuItem(value: 'dark', child: Text('Dark')),
                        DropdownMenuItem(value: 'time', child: Text('Time-based')),
                      ],
                    ),
                  ),
                ),
                row(
                  'palette',
                  'Brand colour',
                  Semantics(
                    container: true,
                    label: 'Brand colour',
                    child: Wrap(
                      spacing: 6,
                      children: [for (final t in colorThemes) _swatch(u, t.id, t.label, t.color), _swatch(u, 'system', 'System accent', null)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Row(
            children: [
              Expanded(
                child: Text('You can change these any time, from Make it yours in the tray’s menu.', style: TextStyle(color: u.muted, fontSize: 12.5)),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: () => widget.done(c),
                iconAlignment: IconAlignment.end,
                icon: AppIcon('arrow-right', size: 16, color: u.onBrand),
                label: const Text('Get started'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _swatch(UwuColors u, String id, String label, Color? colour) {
    final picked = id == 'system' ? c.accent : (!c.accent && c.colour == id);
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        label: label,
        inMutuallyExclusiveGroup: true,
        checked: picked,
        button: true,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          customBorder: const CircleBorder(),
          onTap: () => setState(() {
            if (id == 'system') {
              c.accent = true;
            } else {
              c.accent = false;
              c.colour = id;
            }
          }),
          child: Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: colour,
              gradient: colour == null ? const SweepGradient(colors: [Colors.red, Colors.yellow, Colors.green, Colors.blue, Colors.purple, Colors.red]) : null,
              border: Border.all(color: picked ? u.brandInk : u.border, width: picked ? 3 : 1),
            ),
          ),
        ),
      ),
    );
  }
}

/// The window set up as the welcome window: about 940 × 660, at least 620 × 560.
Future<void> welcomeWindow() async {
  // From the tray's menu it's the main window, which may be maximised or full screen: resized
  // like that, Windows keeps the maximised frame and the app draws at the wrong size and place,
  // here and again when the boards come back.
  if (await windowManager.isFullScreen()) await windowManager.setFullScreen(false);
  if (await windowManager.isMaximized()) await windowManager.unmaximize();
  await windowManager.setTitleBarStyle(TitleBarStyle.hidden, windowButtonVisibility: false);
  await windowManager.setResizable(true);
  await windowManager.setMinimumSize(const Size(620, 560));
  await windowManager.setSize(const Size(940, 660));
  await windowManager.center();
  await windowManager.show();
  await windowManager.focus();
}

/// Applies the choices through the app's own settings, and marks the window seen.
Future<void> applyWelcome(WelcomeChoices? c) async {
  DeskSettings.write({'setupDone': true});
  if (c == null) return;
  final t = ThemeController.I;
  if (c.followSystem) {
    final b = SchedulerBinding.instance.platformDispatcher.platformBrightness;
    t.setMode(b == Brightness.dark ? 'dark' : 'light');
  } else {
    t.setMode(c.mode);
  }
  t.setColorTheme(c.colour);
  DeskSettings.write({'useSystemAccent': c.accent, 'followSystem': c.followSystem, 'loginChosen': true});
  t.setSystemAccent(c.accent);
  unawaited(Desktop.setStartAtLogin(c.startAtLogin));
}
