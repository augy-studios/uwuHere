// The Edge Tray (docs/edge-tray-spec.md, the site's js/tray.js): the column of buttons pinned top
// right, tucked off the edge by its arrow tab and remembered (uwuhere.trayOpen, as the site keeps
// it). The phone's; the desktop has its title bar instead.
//
// As the spec draws it: the tab, a pill, to the left of the column of rounded-square buttons.
// Collapsing slides the whole tray right until only the tab is left, flush with the edge and flat
// on that side, its chevron turned round; the buttons fade, shrink and slide out together, and on
// opening unroll top to bottom, 18 ms apart. 44 px buttons 16 px from the edge, 40 and 10 on a
// phone up to 480 px wide.
//
// The page's own buttons come first (Home, and on a host page its QR code, settings and CSV), then
// a rule, then the app's: Notifications (Android, built with Firebase), Check for updates (the
// GitHub APK), Report a bug, Show me around, Theme.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../data/store.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';

class TrayItem {
  const TrayItem({required this.icon, required this.label, required this.onTap, this.tourId});
  final String icon;
  final String label;
  final VoidCallback onTap;

  /// A tour stop's id (lib/features/tour/tour.dart), for the tours that point at it.
  final String? tourId;
}

class EdgeTray extends StatefulWidget {
  const EdgeTray({super.key, required this.page, required this.app, this.wrapTarget});

  /// The page's own buttons, then the app's, with a rule between.
  final List<TrayItem> page;
  final List<TrayItem> app;

  /// Wraps a button that's a tour stop (TourTargets.key), so a tour can find it.
  final Widget Function(String id, Widget child)? wrapTarget;

  static const storeKey = 'uwuhere.trayOpen';

  /// Whether it's out, for the page to make room for it (the site's body.tray-open).
  static final open = ValueNotifier<bool>(true);

  /// The spec's --tray-time and --tray-ease.
  static const time = Duration(milliseconds: 340);
  static const ease = Cubic(0.2, 0.8, 0.2, 1);

  static const _tabWidth = 24.0;
  static const _gap = 8.0;

  /// The spec's --glass-btn: 44 px, 40 on a phone up to 480 px wide.
  static double buttonSize(BuildContext context) => MediaQuery.sizeOf(context).width <= 480 ? 40 : 44;

  /// The spec's --edge: 16 px from the right edge (10 on a phone), clear of a landscape notch.
  static double edge(BuildContext context) {
    final inset = MediaQuery.sizeOf(context).width <= 480 ? 10.0 : 16.0;
    return math.max(inset, MediaQuery.paddingOf(context).right + inset);
  }

  /// Up to here the page's column would meet the tray (app.css's breakpoint).
  static bool _narrow(BuildContext context) => MediaQuery.sizeOf(context).width <= 760;

  /// The page's right padding while the tray's out on a narrow screen: the buttons, their edge
  /// and a 12 px gap. None when it's tucked away or the screen is wide.
  static double roomFor(BuildContext context) => open.value && _narrow(context) ? buttonSize(context) + edge(context) + 12 : 0;

  @override
  State<EdgeTray> createState() => _EdgeTrayState();
}

class _EdgeTrayState extends State<EdgeTray> {
  @override
  void initState() {
    super.initState();
    EdgeTray.open.value = Store.I.get(EdgeTray.storeKey) != '0';
  }

  bool get _open => EdgeTray.open.value;

  void _toggle() => setState(() {
    EdgeTray.open.value = !_open;
    Store.I.put(EdgeTray.storeKey, _open ? '1' : '0');
  });

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final open = _open;
    final time = MediaQuery.of(context).disableAnimations ? Duration.zero : EdgeTray.time;
    final size = EdgeTray.buttonSize(context);
    final edge = EdgeTray.edge(context);
    // Far enough that the tab's right side lands on the edge, and 1 px more so its right border
    // goes past it: at the edge it's flat on that side, with no border there.
    final shift = size + EdgeTray._gap + edge + 1;

    Widget button(TrayItem t) {
      final b = _Glass(width: size, height: size, label: t.label, lift: true, onTap: t.onTap, child: AppIcon(t.icon, size: size * 0.45, color: c.ink));
      final wrap = widget.wrapTarget;
      return t.tourId != null && wrap != null ? wrap(t.tourId!, b) : b;
    }

    final items = <Widget>[
      for (final t in widget.page) button(t),
      Container(width: 24, height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: c.ink.withValues(alpha: 0.25)),
      for (final t in widget.app) button(t),
    ];

    // Tucked away, the buttons are inert: no focus, no taps, nothing for a screen reader.
    final column = Padding(
      padding: EdgeInsets.only(right: edge),
      child: ExcludeFocus(
        excluding: !open,
        child: IgnorePointer(
          ignoring: !open,
          child: ExcludeSemantics(
            excluding: !open,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  if (i > 0) const SizedBox(height: EdgeTray._gap),
                  _Unroll(open: open, delay: Duration(milliseconds: 18 * i), time: time, child: items[i]),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    // k runs 0 (out) to 1 (tucked away): the slide, the tab's flat side and its chevron.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: open ? 0 : 1),
      duration: time,
      curve: EdgeTray.ease,
      child: column,
      builder: (context, k, column) => Transform.translate(
        offset: Offset(shift * k, 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Glass(
              width: EdgeTray._tabWidth,
              height: size,
              radius: BorderRadius.horizontal(left: const Radius.circular(12), right: Radius.circular(12 * (1 - k))),
              label: open ? 'Hide menu' : 'Show menu',
              expanded: open,
              onTap: _toggle,
              child: Transform.rotate(angle: math.pi * k, child: AppIcon('chevronRight', size: 16, color: c.ink)),
            ),
            const SizedBox(width: EdgeTray._gap),
            column!,
          ],
        ),
      ),
    );
  }
}

/// One of the tray's glass pieces: a button, or the tab. The spec's .glass-btn: a rounded square
/// on the surface colour with its border and shadow, lifting 1 px on hover ([lift]), with a
/// visible outline on keyboard focus.
class _Glass extends StatefulWidget {
  const _Glass({
    required this.width,
    required this.height,
    required this.label,
    required this.onTap,
    required this.child,
    this.radius = const BorderRadius.all(Radius.circular(14)),
    this.lift = false,
    this.expanded,
  });

  final double width, height;
  final String label;
  final VoidCallback onTap;
  final Widget child;
  final BorderRadius radius;
  final bool lift;
  final bool? expanded;

  @override
  State<_Glass> createState() => _GlassState();
}

class _GlassState extends State<_Glass> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hover = _hover && widget.lift;
    final keyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Tooltip(
      message: widget.label,
      excludeFromSemantics: true,
      child: Semantics(
        button: true,
        label: widget.label,
        expanded: widget.expanded,
        excludeSemantics: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, hover ? -1 : 0, 0),
            width: widget.width,
            height: widget.height,
            foregroundDecoration: _focus && keyboard
                ? BoxDecoration(
                    borderRadius: widget.radius,
                    border: Border.all(color: c.ink, width: 2, strokeAlign: 4),
                  )
                : null,
            decoration: BoxDecoration(
              color: hover ? c.surfaceStrong : (c.glass ? c.surface : c.surfaceStrong),
              borderRadius: widget.radius,
              border: c.glass ? Border.all(color: c.border) : null,
              boxShadow: c.glass
                  ? [dark ? const BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 10)) : const BoxShadow(color: Color(0x1A14281E), blurRadius: 30, offset: Offset(0, 10))]
                  : null,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: widget.radius,
                onTap: widget.onTap,
                onFocusChange: (f) => setState(() => _focus = f),
                child: Center(child: widget.child),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A tray item's part in the tray opening and closing. Opening, it fades in, slides 12 px back
/// from the edge and grows from 85 % scale, [delay] after the tray starts; closing, it goes at
/// once, with the others. The fade takes 80 % of the time.
class _Unroll extends StatefulWidget {
  const _Unroll({required this.open, required this.delay, required this.time, required this.child});
  final bool open;
  final Duration delay, time;
  final Widget child;

  @override
  State<_Unroll> createState() => _UnrollState();
}

class _UnrollState extends State<_Unroll> with SingleTickerProviderStateMixin {
  late final _c = AnimationController(vsync: this, duration: widget.time, value: widget.open ? 1 : 0);
  Timer? _wait;

  @override
  void didUpdateWidget(_Unroll old) {
    super.didUpdateWidget(old);
    _c.duration = widget.time;
    if (widget.open == old.open) return;
    _wait?.cancel();
    if (!widget.open) {
      _c.reverse();
    } else if (widget.time == Duration.zero) {
      _c.value = 1;
    } else {
      _wait = Timer(widget.delay, _c.forward);
    }
  }

  @override
  void dispose() {
    _wait?.cancel();
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
    animation: _c,
    child: widget.child,
    builder: (context, child) {
      final v = _c.value;
      final opening = _c.status == AnimationStatus.forward || _c.status == AnimationStatus.completed;
      final move = opening ? EdgeTray.ease.transform(v) : 1 - EdgeTray.ease.transform(1 - v);
      final fade = opening ? Curves.ease.transform(math.min(1, v / 0.8)) : 1 - Curves.ease.transform(math.min(1, (1 - v) / 0.8));
      return Opacity(
        opacity: fade,
        child: Transform.translate(
          offset: Offset(12 * (1 - move), 0),
          child: Transform.scale(scale: 0.85 + 0.15 * move, child: child),
        ),
      );
    },
  );
}
