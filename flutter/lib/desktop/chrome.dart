// The desktop's own title bar and command bar, round the shared app (docs/desktop-features-spec.md
// §5, docs/flutter-desktop-app-spec.md §2.3–2.5). 40 px tall, in the brand colour (writing light
// or dark by contrast), draggable where there's nothing to click, double-click to maximise:
//
//   (macOS traffic lights) Back Forward Reload  [ Command / Search bar ]  the page's buttons
//   (Home, QR code, Event settings, CSV) and the app's (Notifications, Report a bug, Show me
//   around, Theme)  Copy link Screenshot Long screenshot (Update)
//   (Windows, Linux: minimise, maximise, close)
//
// The command bar shows what's open at rest (the event's name, or its code); Ctrl+K, Ctrl+F,
// Ctrl+L or F6 (⌘K, ⌘F, ⌘L) opens a live search of your events (names and codes) and the app's
// commands. A typed event code offers its check-in page (and its host page if it's yours); a
// pasted uwu://here/ link, the site's address or a /join?id=… path opens in the app; another
// site's address opens in the browser. Back and Forward step through the pages and events opened.
// The title bar hides in full screen.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import '../app/env.dart';
import '../app/links.dart';
import '../app/nav.dart';
import '../app/pages.dart';
import '../data/store.dart';
import '../app/home.dart' show appTrayItems;
import '../data/codes.dart';
import '../data/here_store.dart';
import '../features/bug/bug_report.dart';
import '../features/notify/notify_sheet.dart';
import '../features/theme/theme_sheet.dart';
import '../features/tour/tour.dart';
import '../widgets/edge_tray.dart';
import '../widgets/page_frame.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/sheet.dart';
import 'desk.dart';
import 'screenshot.dart';
import 'updater.dart';

const titleBarHeight = 40.0;

/// Back and Forward through the pages and events opened: each step a page, and on a host or
/// check-in page, the event that was open.
class ViewHistory {
  ViewHistory._();
  static final List<String> _stack = [];
  static int _at = -1;
  static bool _moving = false;
  static final ValueNotifier<int> changed = ValueNotifier(0);

  static String _now() => switch (AppPages.active()) {
    AppPages.host => 'host:${AppPages.hostCode.value ?? ''}',
    AppPages.join => 'join:${AppPages.joinCode.value ?? ''}',
    _ => 'home:',
  };

  static void _record() {
    if (_moving) return;
    final now = _now();
    if (_at >= 0 && _stack[_at] == now) return;
    _stack.removeRange(_at + 1, _stack.length);
    _stack.add(now);
    _at = _stack.length - 1;
    changed.value++;
  }

  static void start() {
    AppPages.current.addListener(_record);
    AppPages.hostCode.addListener(_record);
    AppPages.joinCode.addListener(_record);
    _record();
  }

  static bool get canBack => _at > 0;
  static bool get canForward => _at < _stack.length - 1;

  static void _go(int d) {
    final to = _at + d;
    if (to < 0 || to >= _stack.length) return;
    _at = to;
    _moving = true;
    final step = _stack[_at];
    final page = step.substring(0, step.indexOf(':'));
    final code = step.substring(step.indexOf(':') + 1);
    if (page == AppPages.host && code.isNotEmpty) {
      AppPages.openHost(code);
    } else if (page == AppPages.join) {
      AppPages.openJoin(code.isEmpty ? null : code);
    } else {
      AppPages.open(AppPages.home);
    }
    _moving = false;
    changed.value++;
  }

  static void back() => _go(-1);
  static void forward() => _go(1);
}

/// One thing the command bar offers.
class _Hit {
  _Hit(this.icon, this.title, this.sub, this.run);
  final String icon;
  final String title;
  final String sub;
  final VoidCallback run;
}

class DesktopChrome extends StatefulWidget {
  const DesktopChrome({super.key, required this.child});
  final Widget child;

  @override
  State<DesktopChrome> createState() => _DesktopChromeState();
}

class _DesktopChromeState extends State<DesktopChrome> {
  final _search = TextEditingController();
  final _focus = FocusNode();
  final _layer = LayerLink();
  OverlayEntry? _results;
  String _message = '';
  Timer? _messageTimer;
  bool _reloading = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(() {
      if (_focus.hasFocus) {
        _search.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _search.text.length,
        );
        _showResults();
      } else {
        Timer(const Duration(milliseconds: 150), _hideResults);
      }
    });
    _search.addListener(() => _results?.markNeedsBuild());
  }

  @override
  void dispose() {
    _hideResults();
    _search.dispose();
    _focus.dispose();
    super.dispose();
  }

  void say(String text) {
    _messageTimer?.cancel();
    setState(() => _message = text);
    _messageTimer = Timer(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _message = '');
    });
  }

  BuildContext? get _ctx => AppNav.context;

  void _focusSearch() {
    _search.text = '';
    _focus.requestFocus();
  }

  /// Reload: the page on show read again from the server (the host page's list, the check-in
  /// page's event), and what another window kept read again from storage.
  Future<void> _reload() async {
    if (_reloading) return;
    setState(() => _reloading = true);
    await Store.I.reload();
    await refreshPage();
    await Future<void>.delayed(const Duration(milliseconds: 300));
    if (mounted) setState(() => _reloading = false);
  }

  /// Ctrl+,: the open event's settings on its host page, else the theme.
  void _settings() {
    final ctx = _ctx;
    final s = PageActions.items.value.where((i) => i.label == 'Event settings').firstOrNull;
    if (s != null) {
      s.onTap();
    } else if (ctx != null) {
      openThemeSheet(ctx);
    }
  }

  Future<void> _copyLink() async {
    await copyText(linkForPage());
    say('Link copied');
  }

  void _closeTop() {
    if (AppSheet.anyOpen ||
        (AppNav.navigatorKey.currentState?.canPop() ?? false)) {
      AppNav.navigatorKey.currentState?.maybePop();
    } else {
      Desktop.hide();
    }
  }

  void _escape() {
    if (_focus.hasFocus) {
      _focus.unfocus();
      return;
    }
    if (Desktop.fullScreen.value) {
      Desktop.setFullScreen(false);
      return;
    }
    AppNav.navigatorKey.currentState?.maybePop();
  }

  /// What the command bar finds for what's typed.
  List<_Hit> _hits(String q) {
    final ctx = _ctx;
    final query = q.trim().toLowerCase();
    final hits = <_Hit>[];
    final text = q.trim();
    if (text.isNotEmpty && parseLink(text) != null) {
      hits.add(_Hit('link', 'Open $text', 'Link', () => _openTyped(text)));
    }
    final code = normaliseCode(text);
    if (isValidCode(code) && text.replaceAll(RegExp('[^A-Za-z0-9]'), '').length == codeLength) {
      hits.add(_Hit('check', 'Check in to $code', 'Event', () => AppPages.openJoin(code)));
      if (HereStore.hostKey(code) != null) hits.add(_Hit('users', 'Open the host page for $code', 'Your event', () => AppPages.openHost(code)));
    }
    final commands = <_Hit>[
      _Hit('home', 'Home', 'Command', () => AppPages.open(AppPages.home)),
      _Hit('plus', 'Host an event', 'Command · Ctrl+N', () => Links.open('uwu://here/#host')),
      _Hit('check', 'Check in with a code', 'Command', () => Links.open('uwu://here/#join')),
      for (final t in PageActions.items.value)
        if (t.label != 'Home') _Hit(t.icon, t.label, t.label == 'Event settings' ? 'This event · Ctrl+,' : 'This event', t.onTap),
      _Hit('bell', 'Notifications', 'Command', () => ctx == null ? null : openNotifySheet(ctx)),
      _Hit('sun', 'Theme', 'Command', () => ctx == null ? null : openThemeSheet(ctx)),
      _Hit('help', 'Show me around', 'Command', () => ctx == null ? null : openTourPicker(ctx)),
      _Hit('bug', 'Report a bug', 'Command', () => ctx == null ? null : openBugReport(ctx)),
      _Hit('fullscreen', 'Full screen', 'Command · F11', () => Desktop.setFullScreen(!Desktop.fullScreen.value)),
      _Hit('screenshot', 'Screenshot', 'Command', () => ctx == null ? null : Screenshots.take(ctx)),
      _Hit('screenshot-long', 'Long screenshot', 'Command', () => ctx == null ? null : Screenshots.takeLong(ctx)),
      _Hit('refresh', 'Reload', 'Command · F5', _reload),
    ];
    for (final c in commands) {
      if (query.isEmpty || c.title.toLowerCase().contains(query)) hits.add(c);
    }
    for (final ev in HereStore.listHosted()) {
      final name = ev.title.isEmpty ? 'Untitled event' : ev.title;
      if (query.isEmpty || name.toLowerCase().contains(query) || ev.code.toLowerCase().contains(query)) {
        hits.add(_Hit('users', name, 'Your event · ${ev.code}${ev.ended ? ' · Ended' : ''}', () => AppPages.openHost(ev.code)));
      }
    }
    return hits.take(12).toList();
  }

  Future<void> _openTyped(String text) async {
    final target = parseLink(text);
    if (target is LinkOut) {
      await Desktop.openExternal(target.uri.toString());
      say('Opened in your browser');
      return;
    }
    if (!await Links.open(text)) say('Not found');
  }

  void _submit(String text) {
    _focus.unfocus();
    // Used, so emptied: at rest the bar shows the open page's title, and the next search starts
    // from nothing.
    _search.clear();
    final t = text.trim();
    if (t.isEmpty) return;
    if (parseLink(t) != null) {
      _openTyped(t);
      return;
    }
    // A bare address: the site's own, or another's.
    if (RegExp(r'^[^\s/?#]+\.[^\s/?#]+').hasMatch(t) && !t.contains(' ')) {
      _openTyped('https://$t');
      return;
    }
    final hits = _hits(t);
    if (hits.isEmpty) {
      say('Not found');
    } else {
      hits.first.run();
    }
  }

  void _showResults() {
    if (_results != null) return;
    // The chrome sits above the navigator, so its overlay is the navigator's.
    final overlay = AppNav.navigatorKey.currentState?.overlay;
    if (overlay == null) return;
    _results = OverlayEntry(
      builder: (context) {
        final c = UwuColors.of(context);
        final hits = _hits(_search.text);
        return Positioned(
          width: 520,
          child: CompositedTransformFollower(
            link: _layer,
            targetAnchor: Alignment.bottomCenter,
            followerAnchor: Alignment.topCenter,
            offset: const Offset(0, 6),
            child: Material(
              elevation: 12,
              color: Color.alphaBlend(c.surfaceStrong, c.bg),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(color: c.border),
              ),
              clipBehavior: Clip.antiAlias,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 420),
                child: hits.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: Text(
                          'Nothing found',
                          style: TextStyle(color: c.muted),
                        ),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        children: [
                          for (final h in hits)
                            ListTile(
                              dense: true,
                              leading: AppIcon(
                                h.icon,
                                size: 16,
                                color: c.muted,
                              ),
                              title: Text(
                                h.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: c.ink, fontSize: 13.5),
                              ),
                              subtitle: Text(
                                h.sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: c.muted,
                                  fontSize: 11.5,
                                ),
                              ),
                              onTap: () {
                                _focus.unfocus();
                                _search.clear();
                                h.run();
                              },
                            ),
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
    overlay.insert(_results!);
  }

  void _hideResults() {
    _results?.remove();
    _results = null;
  }

  Map<ShortcutActivator, VoidCallback> get _shortcuts {
    final mac = Env.macOS;
    SingleActivator mod(LogicalKeyboardKey k, {bool shift = false}) =>
        SingleActivator(k, control: !mac, meta: mac, shift: shift);
    return {
      mod(LogicalKeyboardKey.keyK): _focusSearch,
      mod(LogicalKeyboardKey.keyF): _focusSearch,
      mod(LogicalKeyboardKey.keyL): _focusSearch,
      const SingleActivator(LogicalKeyboardKey.f6): _focusSearch,
      mod(LogicalKeyboardKey.keyC, shift: true): _copyLink,
      const SingleActivator(LogicalKeyboardKey.f5): _reload,
      mod(LogicalKeyboardKey.keyR): _reload,
      mod(LogicalKeyboardKey.comma): _settings,
      mod(LogicalKeyboardKey.keyW): _closeTop,
      const SingleActivator(LogicalKeyboardKey.escape): _escape,
      if (mac) ...{
        const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true):
            ViewHistory.back,
        const SingleActivator(LogicalKeyboardKey.bracketRight, meta: true):
            ViewHistory.forward,
        const SingleActivator(
          LogicalKeyboardKey.keyF,
          meta: true,
          control: true,
        ): () =>
            Desktop.setFullScreen(!Desktop.fullScreen.value),
        const SingleActivator(LogicalKeyboardKey.keyQ, meta: true):
            Desktop.quit,
        const SingleActivator(LogicalKeyboardKey.keyM, meta: true): () =>
            windowManager.minimize(),
      } else ...{
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            ViewHistory.back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            ViewHistory.forward,
        const SingleActivator(LogicalKeyboardKey.f11): () =>
            Desktop.setFullScreen(!Desktop.fullScreen.value),
      },
      mod(LogicalKeyboardKey.keyN): () => Links.open('uwu://here/#host'),
    };
  }

  @override
  Widget build(BuildContext context) {
    final body = ValueListenableBuilder<bool>(
      valueListenable: Desktop.fullScreen,
      builder: (context, full, _) => Column(
        children: [
          if (!full) _bar(context),
          // Its own semantics container: a window's barrier below blocks what was drawn before it
          // in the same container, which would take the title bar from screen readers.
          Expanded(
            child: Semantics(
              container: true,
              explicitChildNodes: true,
              child: widget.child,
            ),
          ),
        ],
      ),
    );
    Widget app = CallbackShortcuts(
      bindings: _shortcuts,
      // The title bar sits above the navigator, so its tooltips and the command bar's text menus
      // need an overlay of their own. Without one, showing a tooltip throws, and the error box
      // fills the title bar.
      child: Focus(autofocus: true, child: Overlay.wrap(child: body)),
    );
    if (Env.macOS) app = _MacMenus(chrome: this, child: app);
    return app;
  }

  Widget _bar(BuildContext context) {
    final c = UwuColors.of(context);
    // In the systems' glass the title bar is the window's own backdrop (Mica, the vibrancy, the
    // glows), as Windows 11's, macOS's and COSMIC's are, and writes in the page's ink.
    final native = c.native;
    final brand = c.glass ? ThemeController.I.colorTheme.color : c.brandFill;
    final dark = c.glass && ThemeController.I.brightness == Brightness.dark;
    final bg = native ? Colors.transparent : (dark ? Color.lerp(brand, Colors.black, 0.72)! : brand);
    final ink = native
        ? c.ink
        : (ThemeData.estimateBrightnessForColor(bg) == Brightness.dark
            ? Colors.white
            : const Color(0xFF121815));
    final mac = Env.macOS;
    // macOS Tahoe sets a toolbar's buttons in capsules of glass, a group to each.
    Widget group(Widget row) => c.kind == GlassKind.liquid
        ? Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: NativeGlass(
              shape: const StadiumBorder(),
              fill: c.surface,
              shadow: false,
              padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
              child: row,
            ),
          )
        : row;
    Widget tool(
      String icon,
      String label,
      VoidCallback? onTap, {
      Color? colour,
    }) => Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          customBorder: c.capsule ? const StadiumBorder() : null,
          borderRadius: c.capsule ? null : BorderRadius.circular(native ? c.controlRadius : 6),
          child: SizedBox(
            width: 32,
            height: c.capsule ? 28 : 30,
            child: Center(
              child: AppIcon(
                icon,
                size: 16,
                color: onTap == null
                    ? ink.withValues(alpha: 0.35)
                    : (colour ?? ink),
              ),
            ),
          ),
        ),
      ),
    );
    // Copy link and the screenshots: after the app's buttons, in their capsule on Tahoe.
    final extras = <Widget>[
      tool('link', 'Copy link', _copyLink),
      ValueListenableBuilder<bool>(
        valueListenable: Screenshots.busy,
        builder: (context, busy, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            tool(
              'screenshot',
              'Screenshot',
              busy ? null : () => Screenshots.take(context),
            ),
            tool(
              'screenshot-long',
              'Long screenshot',
              busy ? null : () => Screenshots.takeLong(context),
            ),
          ],
        ),
      ),
    ];
    return Material(
      color: bg,
      child: SizedBox(
        height: titleBarHeight,
        child: Row(
          children: [
            SizedBox(width: mac ? 78 : 8),
            group(
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<int>(
                    valueListenable: ViewHistory.changed,
                    builder: (context, _, _) => Row(
                      children: [
                        tool(
                          'arrow-left',
                          'Back',
                          ViewHistory.canBack ? ViewHistory.back : null,
                        ),
                        tool(
                          'arrow-right',
                          'Forward',
                          ViewHistory.canForward ? ViewHistory.forward : null,
                        ),
                      ],
                    ),
                  ),
                  _reloading
                      ? SizedBox(
                          width: 32,
                          child: Center(
                            child: SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ink,
                              ),
                            ),
                          ),
                        )
                      : tool('refresh', 'Reload', _reload),
                ],
              ),
            ),
            Expanded(
              child: DragToMoveArea(
                child: SizedBox(
                  height: titleBarHeight,
                  child: Center(child: _commandBar(c, ink, bg)),
                ),
              ),
            ),
            // The page's own buttons (the Edge Tray's on a phone), then the app's.
            ListenableBuilder(
              listenable: Listenable.merge([PageActions.items, AppPages.current, ThemeController.I]),
              builder: (context, _) {
                final page = AppPages.active() == AppPages.home ? const <TrayItem>[] : PageActions.items.value;
                final liquid = c.kind == GlassKind.liquid;
                return Row(
                  children: [
                    if (page.isNotEmpty)
                      group(
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [for (final t in page) KeyedSubtree(key: t.tourId == null ? null : TourTargets.key(t.tourId!), child: tool(t.icon, t.label, t.onTap))],
                        ),
                      ),
                    if (page.isNotEmpty && !liquid) Container(width: 1, height: 18, margin: const EdgeInsets.symmetric(horizontal: 4), color: ink.withValues(alpha: 0.25)),
                    group(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (final t in appTrayItems(context)) tool(t.icon, t.label, t.onTap),
                          if (liquid) ...extras,
                        ],
                      ),
                    ),
                    if (!liquid) ...extras,
                  ],
                );
              },
            ),
            ValueListenableBuilder<String?>(
              valueListenable: Updater.ready,
              builder: (context, ready, _) => ready == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF16A34A),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10),
                          minimumSize: const Size(0, 28),
                        ),
                        onPressed: Updater.restartToUpdate,
                        icon: const AppIcon(
                          'appUpdate',
                          size: 14,
                          color: Colors.white,
                        ),
                        label: Text(
                          'Update to $ready',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
            ),
            if (!mac) _WindowButtons(ink: ink) else const SizedBox(width: 8),
          ],
        ),
      ),
    );
  }

  /// What the command bar says at rest: the open event's name and code, or the page.
  String _pageTitle() {
    switch (AppPages.active()) {
      case AppPages.host:
        final code = AppPages.hostCode.value;
        if (code == null) return 'Host page';
        final ev = HereStore.listHosted().where((e) => e.code == code).firstOrNull;
        return ev == null || ev.title.isEmpty ? 'Event $code' : '${ev.title} · $code';
      case AppPages.join:
        final code = AppPages.joinCode.value;
        return code == null ? 'Check in' : 'Check in · $code';
    }
    return 'uwuHere';
  }

  Widget _commandBar(UwuColors c, Color ink, Color bg) {
    final rest = _message.isNotEmpty ? _message : _pageTitle();
    // A capsule on Tahoe, Fluent's 4 px search box, a rounded field on Linux, the site's 8 px.
    final r = BorderRadius.circular(c.capsule ? 14 : (c.native ? math.min(c.controlRadius, 8) : 8));
    final restFill = c.native ? c.surface : Colors.black.withValues(alpha: 0.08);
    final restEdge = c.native ? BorderSide(color: c.rimShade) : BorderSide.none;
    return CompositedTransformTarget(
      link: _layer,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, minWidth: 160),
        child: SizedBox(
          height: 28,
          child: ListenableBuilder(
            listenable: Listenable.merge([_focus, AppPages.current, AppPages.hostCode, AppPages.joinCode]),
            builder: (context, _) => Named(
              'Search',
              child: TextField(
                controller: _search,
                focusNode: _focus,
                onSubmitted: _submit,
                textAlign: _focus.hasFocus ? TextAlign.start : TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  color: _focus.hasFocus ? c.ink : ink,
                ),
                cursorColor: c.brandInk,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: _focus.hasFocus ? c.surfaceStrong : restFill,
                  hintText: _focus.hasFocus
                      ? 'Search your events and commands, type an event code, or paste a link'
                      : rest,
                  hintStyle: TextStyle(
                    fontSize: 13,
                    color: _focus.hasFocus
                        ? c.muted
                        : ink.withValues(alpha: 0.85),
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 8, right: 6),
                    child: AppIcon(
                      'search',
                      size: 14,
                      color: _focus.hasFocus
                          ? c.muted
                          : ink.withValues(alpha: 0.7),
                    ),
                  ),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 28,
                    minHeight: 0,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 6,
                  ),
                  border: OutlineInputBorder(
                    borderRadius: r,
                    borderSide: restEdge,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: r,
                    borderSide: restEdge,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: r,
                    borderSide: BorderSide(color: c.brandInk, width: 1.5),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Minimise, maximise or restore, and close (which keeps the app in the tray): full bar height,
/// 46 px wide each, close turning red on hover.
class _WindowButtons extends StatelessWidget {
  const _WindowButtons({required this.ink});
  final Color ink;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Desktop.maximized,
      builder: (context, max, _) => Row(
        children: [
          _WinButton(
            icon: 'minimise',
            label: 'Minimise',
            ink: ink,
            onTap: windowManager.minimize,
          ),
          _WinButton(
            icon: max ? 'restore' : 'maximise',
            label: max ? 'Restore' : 'Maximise',
            ink: ink,
            onTap: () async =>
                max ? windowManager.unmaximize() : windowManager.maximize(),
          ),
          _WinButton(
            icon: 'close',
            label: 'Close',
            ink: ink,
            close: true,
            onTap: Desktop.hide,
          ),
        ],
      ),
    );
  }
}

class _WinButton extends StatefulWidget {
  const _WinButton({
    required this.icon,
    required this.label,
    required this.ink,
    required this.onTap,
    this.close = false,
  });
  final String icon;
  final String label;
  final Color ink;
  final Future<void> Function() onTap;
  final bool close;

  @override
  State<_WinButton> createState() => _WinButtonState();
}

class _WinButtonState extends State<_WinButton> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final hover = widget.close
        ? const Color(0xFFE81123)
        : widget.ink.withValues(alpha: 0.12);
    return Semantics(
      button: true,
      label: widget.label,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 46,
            height: titleBarHeight,
            color: _over ? hover : Colors.transparent,
            child: Center(
              child: AppIcon(
                widget.icon,
                size: 14,
                stroke: 1.4,
                color: _over && widget.close ? Colors.white : widget.ink,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The macOS menu bar: App, File, Edit, View, Window and Help, wired to the app's actions.
class _MacMenus extends StatelessWidget {
  const _MacMenus({required this.chrome, required this.child});
  final _DesktopChromeState chrome;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ctx = AppNav.context;
    PlatformMenuItem item(
      String label,
      VoidCallback onTap, [
      MenuSerializableShortcut? key,
    ]) => PlatformMenuItem(label: label, onSelected: onTap, shortcut: key);
    return PlatformMenuBar(
      menus: [
        PlatformMenu(
          label: 'uwuHere',
          menus: [
            PlatformMenuItemGroup(
              members: [
                item(
                  'Settings…',
                  chrome._settings,
                  const SingleActivator(LogicalKeyboardKey.comma, meta: true),
                ),
                item('Check for Updates…', Updater.checkNow),
              ],
            ),
            if (PlatformProvidedMenuItem.hasMenu(
              PlatformProvidedMenuItemType.hide,
            ))
              const PlatformProvidedMenuItem(
                type: PlatformProvidedMenuItemType.hide,
              ),
            item(
              'Quit uwuHere',
              Desktop.quit,
              const SingleActivator(LogicalKeyboardKey.keyQ, meta: true),
            ),
          ],
        ),
        PlatformMenu(
          label: 'File',
          menus: [
            item(
              'New Event',
              () => Links.open('uwu://here/#host'),
              const SingleActivator(LogicalKeyboardKey.keyN, meta: true),
            ),
            item(
              'Close',
              chrome._closeTop,
              const SingleActivator(LogicalKeyboardKey.keyW, meta: true),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Edit',
          menus: [
            item(
              'Find…',
              chrome._focusSearch,
              const SingleActivator(LogicalKeyboardKey.keyF, meta: true),
            ),
            item(
              'Copy Link',
              chrome._copyLink,
              const SingleActivator(
                LogicalKeyboardKey.keyC,
                meta: true,
                shift: true,
              ),
            ),
          ],
        ),
        PlatformMenu(
          label: 'View',
          menus: [
            item(
              'Reload',
              chrome._reload,
              const SingleActivator(LogicalKeyboardKey.keyR, meta: true),
            ),
            item(
              'Back',
              ViewHistory.back,
              const SingleActivator(LogicalKeyboardKey.bracketLeft, meta: true),
            ),
            item(
              'Forward',
              ViewHistory.forward,
              const SingleActivator(
                LogicalKeyboardKey.bracketRight,
                meta: true,
              ),
            ),
            item(
              'Toggle Full Screen',
              () => Desktop.setFullScreen(!Desktop.fullScreen.value),
              const SingleActivator(
                LogicalKeyboardKey.keyF,
                meta: true,
                control: true,
              ),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Window',
          menus: [
            item(
              'Minimise',
              () => windowManager.minimize(),
              const SingleActivator(LogicalKeyboardKey.keyM, meta: true),
            ),
          ],
        ),
        PlatformMenu(
          label: 'Help',
          menus: [
            item(
              'Show Me Around',
              () => ctx == null ? null : openTourPicker(ctx),
            ),
            item(
              'Report a Bug…',
              () => ctx == null ? null : openBugReport(ctx),
            ),
            item(
              'uwuHere on the Web',
              () => Desktop.openExternal(Desktop.site),
            ),
          ],
        ),
      ],
      child: child,
    );
  }
}
