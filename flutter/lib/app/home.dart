// The app's one screen: home, the host page and the check-in page, each kept (an IndexedStack),
// with the update bar above them on Android and the Edge Tray over their top right. On the desktop
// from 1024 px wide, the events this computer hosts and the code box stay in a pane on the left
// (master), and the open page fills the right (detail): picking an event opens it there.
import 'package:flutter/material.dart';

import '../api/api.dart';
import '../data/codes.dart';
import '../data/format.dart';
import '../data/here_store.dart';
import '../features/bug/bug_report.dart';
import '../features/home/home_screen.dart';
import '../features/host/host_screen.dart';
import '../features/join/join_screen.dart';
import '../features/notify/notify_sheet.dart';
import '../features/theme/theme_sheet.dart';
import '../features/tour/tour.dart';
import '../features/update/update_bar.dart';
import '../native/bridge.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/common.dart';
import '../widgets/edge_tray.dart';
import '../widgets/page_frame.dart';
import 'env.dart';
import 'fullscreen.dart';
import 'nav.dart';
import 'pages.dart';

/// The app's own buttons, after the page's: in the Edge Tray, and in the desktop's title bar.
/// The app's own buttons, for the Edge Tray and the desktop's title bar. Each opens its sheet from
/// the Navigator's context when there is one: the title bar sits above the Navigator, and a sheet
/// opened from its own context has no route to go on, so nothing would open.
List<TrayItem> appTrayItems(BuildContext context) {
  BuildContext at() => AppNav.context ?? context;
  return [
    if (Native.has('push') || Env.desktop) TrayItem(icon: 'bell', label: 'Notifications', onTap: () => openNotifySheet(at())),
    if (Env.android && !isPlayBuild) TrayItem(icon: 'appUpdate', label: 'Check for updates', onTap: () => openUpdates(check: true)),
    TrayItem(icon: 'bug', label: 'Report a bug', onTap: () => openBugReport(at()), tourId: 'tray-bug'),
    TrayItem(icon: 'help', label: 'Show me around', onTap: () => openTourPicker(at()), tourId: 'tray-tour'),
    TrayItem(icon: ThemeController.I.brightness == Brightness.dark ? 'moon' : 'sun', label: 'Theme', onTap: () => openThemeSheet(at()), tourId: 'tray-theme'),
  ];
}

class Home extends StatefulWidget {
  const Home({super.key});

  @override
  State<Home> createState() => _HomeState();
}

class _HomeState extends State<Home> {
  static final _pagesKey = GlobalKey(debugLabel: 'pages');

  @override
  void initState() {
    super.initState();
    AppPages.current.addListener(_pageChanged);
    _pageChanged();
    WidgetsBinding.instance.addPostFrameCallback((_) => Tour.init());
  }

  @override
  void dispose() {
    AppPages.current.removeListener(_pageChanged);
    super.dispose();
  }

  void _pageChanged() {
    // Home's own button: back to home, from anywhere but home.
    if (AppPages.active() == AppPages.home) {
      PageActions.items.value = const [];
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final page = AppPages.active();
    final index = AppPages.all.indexOf(page);
    // A page not on show takes no focus: it isn't laid out, so it has nowhere to be.
    final pages = IndexedStack(
      key: _pagesKey,
      index: index < 0 ? 0 : index,
      children: [
        for (final id in AppPages.all)
          ExcludeFocus(
            excluding: id != page,
            child: switch (id) {
              AppPages.host => const HostScreen(),
              AppPages.join => const JoinScreen(),
              _ => const HomeScreen(),
            },
          ),
      ],
    );
    Widget body = pages;
    if (Env.desktop) {
      body = ValueListenableBuilder<bool>(
        valueListenable: Fullscreen.on,
        builder: (context, full, _) => full ? pages : _DesktopShell(child: pages),
      );
    } else {
      body = Stack(
        children: [
          Positioned.fill(child: pages),
          Positioned(
            top: MediaQuery.paddingOf(context).top + 12,
            right: 0,
            child: ListenableBuilder(
              listenable: Listenable.merge([PageActions.items, ThemeController.I]),
              builder: (context, _) => EdgeTray(
                page: page == AppPages.home ? [TrayItem(icon: 'home', label: 'Home', onTap: () => AppPages.open(AppPages.home))] : PageActions.items.value,
                app: appTrayItems(context),
                wrapTarget: (id, child) => KeyedSubtree(key: TourTargets.key(id), child: child),
              ),
            ),
          ),
        ],
      );
    }
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Column(
          children: [
            if (Env.android) const UpdateBar(),
            const _OfflineBar(),
            Expanded(child: body),
          ],
        ),
      ),
    );
  }

  DateTime? _backAt;

  /// Back (docs/flutter-android-app-spec.md §5): a host or check-in page goes back home, then
  /// "Press back again to exit", and the second press sends the app to the background rather
  /// than closing it, so a host page keeps taking check-ins.
  void _back() {
    if (AppPages.active() != AppPages.home) {
      AppPages.open(AppPages.home);
      return;
    }
    final now = DateTime.now();
    if (_backAt != null && now.difference(_backAt!) < const Duration(seconds: 2)) {
      _backAt = null;
      Native.tryCall('App', 'background');
      return;
    }
    _backAt = now;
    AppNav.toast('Press back again to exit');
  }
}

/// "You're offline" while the network's gone (docs/flutter-android-app-spec.md §5).
class _OfflineBar extends StatelessWidget {
  const _OfflineBar();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Api.offline,
      builder: (context, off, _) {
        if (!off) return const SizedBox.shrink();
        final c = UwuColors.of(context);
        return Material(
          color: c.warn.withValues(alpha: 0.16),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Row(
                children: [
                  AppIcon('wifi', size: 16, color: c.warn),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Semantics(
                      liveRegion: true,
                      child: Text("You're offline. What's saved on this device still works.", style: TextStyle(color: c.ink, fontSize: 13)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// From 1024 px wide: your events and the code box on the left, the open page on the right.
class _DesktopShell extends StatelessWidget {
  const _DesktopShell({required this.child});
  final Widget child;

  static const paneWidth = 380.0;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final w = MediaQuery.sizeOf(context).width;
    if (w <= Env.splitWidth) return child;
    final pane = KeyedSubtree(key: TourTargets.key('events-pane'), child: const EventsPane());
    switch (c.kind) {
      case GlassKind.fluent:
        // Fluent 2's navigation view: the pane on the window's Mica, the page on a layer over it
        // with a rounded top left corner and a fine edge.
        return Row(
          children: [
            SizedBox(width: paneWidth, child: pane),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: c.ink.computeLuminance() > 0.5 ? Colors.white.withValues(alpha: 0.03) : Colors.white.withValues(alpha: 0.5),
                  borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)),
                  border: Border(top: BorderSide(color: c.rimShade), left: BorderSide(color: c.rimShade)),
                ),
                child: ClipRRect(borderRadius: const BorderRadius.only(topLeft: Radius.circular(8)), child: child),
              ),
            ),
          ],
        );
      case GlassKind.liquid:
      case GlassKind.frosted:
        // Tahoe's sidebar, and COSMIC's: a pane of glass standing off the window's edges.
        return Row(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 0, 0, 8),
              child: SizedBox(width: paneWidth - 8, child: NativeGlass(child: pane)),
            ),
            Expanded(child: child),
          ],
        );
      default:
    }
    return Row(
      children: [
        SizedBox(width: paneWidth, child: pane),
        VerticalDivider(width: 1, color: c.border),
        Expanded(child: child),
      ],
    );
  }
}

/// Whether the desktop's events pane is showing (the home page then leaves out what it holds).
bool eventsPaneShown(BuildContext context) => Env.desktop && !Fullscreen.on.value && MediaQuery.sizeOf(context).width > Env.splitWidth;

/// The desktop's left pane: check in by code, the events this computer hosts, and a new one.
class EventsPane extends StatefulWidget {
  const EventsPane({super.key});

  @override
  State<EventsPane> createState() => _EventsPaneState();
}

class _EventsPaneState extends State<EventsPane> {
  final _code = TextEditingController();
  String _error = '';

  @override
  void initState() {
    super.initState();
    HereStore.changes('hosted').listen((_) {
      if (mounted) setState(() {});
    });
    AppPages.current.addListener(_redraw);
    AppPages.hostCode.addListener(_redraw);
  }

  @override
  void dispose() {
    AppPages.current.removeListener(_redraw);
    AppPages.hostCode.removeListener(_redraw);
    _code.dispose();
    super.dispose();
  }

  void _redraw() {
    if (mounted) setState(() {});
  }

  void _join() {
    final code = normaliseCode(_code.text);
    if (!isValidCode(code)) return setState(() => _error = badCodeMessage);
    _code.clear();
    setState(() => _error = '');
    AppPages.openJoin(code);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final hosted = HereStore.listHosted();
    final open = AppPages.active() == AppPages.host ? AppPages.hostCode.value : null;
    return Material(
      // The systems' glass: the pane is the window's backdrop, or the glass round it.
      color: c.native ? Colors.transparent : c.surface,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
        children: [
          Semantics(header: true, headingLevel: 2, child: Text('Checking in?', style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600))),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _code,
                  maxLength: 7,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'CODE', counterText: ''),
                  onChanged: (v) {
                    final up = v.toUpperCase();
                    if (up != v) _code.value = _code.value.copyWith(text: up);
                  },
                  onSubmitted: (_) => _join(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton(onPressed: _join, child: const Text('Join')),
            ],
          ),
          if (_error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(_error, style: TextStyle(color: c.error, fontSize: 12.5))),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: Semantics(header: true, headingLevel: 2, child: Text('Your events', style: TextStyle(color: c.ink, fontSize: 16, fontWeight: FontWeight.w600)))),
              TextButton(onPressed: () => AppPages.open(AppPages.home), child: const Text('New event')),
            ],
          ),
          const SizedBox(height: 6),
          if (hosted.isEmpty) Text('Events you make on this computer are listed here.', style: TextStyle(color: c.muted, fontSize: 13)),
          for (final ev in hosted)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: _EventRow(ev: ev, open: ev.code == open),
            ),
        ],
      ),
    );
  }
}

/// One of your events in the pane. Fluent 2 marks the open one as its navigation does, with a
/// light fill and a short accent bar at the left; the other looks fill it with the accent.
class _EventRow extends StatelessWidget {
  const _EventRow({required this.ev, required this.open});
  final HostedEvent ev;
  final bool open;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final fluent = c.kind == GlassKind.fluent;
    final filled = open && !fluent;
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(c.native ? c.controlRadius + 2 : 12),
      side: BorderSide(color: c.native ? (fluent ? Colors.transparent : c.rimShade) : c.border),
    );
    return Material(
      color: filled ? c.brandFill : (fluent ? (open ? c.surfaceStrong : Colors.transparent) : c.surfaceStrong),
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        onTap: () => AppPages.openHost(ev.code),
        onSecondaryTapUp: (d) => desktopEventMenu?.call(context, d.globalPosition, ev.code, ev.title.isEmpty ? 'Event ${ev.code}' : ev.title),
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ev.title.isEmpty ? 'Untitled event' : ev.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: filled ? c.onBrand : c.ink)),
                  Text(
                    '${ev.code} · ${formatDateTime(ev.createdAt)}${ev.ended ? ' · Ended' : ''}',
                    style: TextStyle(color: filled ? c.onBrand : c.muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            if (fluent && open)
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                child: Center(
                  child: Container(
                    width: 3,
                    height: 18,
                    decoration: BoxDecoration(color: c.brandInk, borderRadius: BorderRadius.circular(2)),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
