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

/// One button in the tray: its icon, its name, and what it does.
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
  static double buttonSize(BuildContext context) {
    if (MediaQuery.sizeOf(context).width <= 480) {
      return 40;
    }
    return 44;
  }

  /// The spec's --edge: 16 px from the right edge (10 on a phone), clear of a landscape notch.
  static double edge(BuildContext context) {
    double inset;
    if (MediaQuery.sizeOf(context).width <= 480) {
      inset = 10.0;
    } else {
      inset = 16.0;
    }
    return math.max(inset, MediaQuery.paddingOf(context).right + inset);
  }

  /// Up to here the page's column would meet the tray (app.css's breakpoint).
  static bool _isNarrow(BuildContext context) {
    return MediaQuery.sizeOf(context).width <= 760;
  }

  /// The page's right padding while the tray's out on a narrow screen: the buttons, their edge
  /// and a 12 px gap. None when it's tucked away or the screen is wide.
  static double roomFor(BuildContext context) {
    if (open.value && _isNarrow(context)) {
      return buttonSize(context) + edge(context) + 12;
    }
    return 0;
  }

  @override
  State<EdgeTray> createState() {
    return _EdgeTrayState();
  }
}

class _EdgeTrayState extends State<EdgeTray> {
  @override
  void initState() {
    super.initState();
    EdgeTray.open.value = Store.I.get(EdgeTray.storeKey) != '0';
  }

  bool get _open {
    return EdgeTray.open.value;
  }

  /// Opens or tucks away the tray, and remembers which ('1' out, '0' tucked away).
  void _toggle() {
    setState(() {
      EdgeTray.open.value = !_open;
      String storedValue;
      if (_open) {
        storedValue = '1';
      } else {
        storedValue = '0';
      }
      Store.I.put(EdgeTray.storeKey, storedValue);
    });
  }

  /// The tab and the column of buttons side by side, slid right by the open/closed animation so
  /// only the tab is left showing when it's tucked away.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final open = _open;

    Duration animationTime;
    if (MediaQuery.of(context).disableAnimations) {
      animationTime = Duration.zero;
    } else {
      animationTime = EdgeTray.time;
    }

    final size = EdgeTray.buttonSize(context);
    final edge = EdgeTray.edge(context);
    // Far enough that the tab's right side lands on the edge, and 1 px more so its right border
    // goes past it: at the edge it's flat on that side, with no border there.
    final shift = size + EdgeTray._gap + edge + 1;

    // One tray button, wrapped as a tour stop when it is one.
    Widget buildButton(TrayItem item) {
      final glassButton = _Glass(
        width: size,
        height: size,
        label: item.label,
        lift: true,
        onTap: item.onTap,
        child: AppIcon(item.icon, size: size * 0.45, color: colors.ink),
      );
      final wrapTarget = widget.wrapTarget;
      if (item.tourId != null && wrapTarget != null) {
        return wrapTarget(item.tourId!, glassButton);
      }
      return glassButton;
    }

    final items = <Widget>[
      for (final item in widget.page) buildButton(item),
      Container(width: 24, height: 1, margin: const EdgeInsets.symmetric(vertical: 2), color: colors.ink.withValues(alpha: 0.25)),
      for (final item in widget.app) buildButton(item),
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
                for (var index = 0; index < items.length; index = index + 1) ...[
                  if (index > 0) const SizedBox(height: EdgeTray._gap),
                  _Unroll(open: open, delay: Duration(milliseconds: 18 * index), time: animationTime, child: items[index]),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    double tuckedTarget;
    String tabLabel;
    if (open) {
      tuckedTarget = 0;
      tabLabel = 'Hide menu';
    } else {
      tuckedTarget = 1;
      tabLabel = 'Show menu';
    }

    // tuckedAmount runs 0 (out) to 1 (tucked away): the slide, the tab's flat side and its chevron.
    return TweenAnimationBuilder<double>(
      tween: Tween(end: tuckedTarget),
      duration: animationTime,
      curve: EdgeTray.ease,
      child: column,
      builder: (context, tuckedAmount, column) {
        return Transform.translate(
          offset: Offset(shift * tuckedAmount, 0),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _Glass(
                width: EdgeTray._tabWidth,
                height: size,
                radius: BorderRadius.horizontal(left: const Radius.circular(12), right: Radius.circular(12 * (1 - tuckedAmount))),
                label: tabLabel,
                expanded: open,
                onTap: _toggle,
                child: Transform.rotate(angle: math.pi * tuckedAmount, child: AppIcon('chevronRight', size: 16, color: colors.ink)),
              ),
              const SizedBox(width: EdgeTray._gap),
              column!,
            ],
          ),
        );
      },
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
  State<_Glass> createState() {
    return _GlassState();
  }
}

class _GlassState extends State<_Glass> {
  bool _hovered = false;
  bool _focused = false;

  /// The piece's box: lifted on hover, outlined on keyboard focus, and in the glass look a
  /// see-through fill with a border and a soft shadow.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    final hovered = _hovered && widget.lift;
    final usingKeyboard = FocusManager.instance.highlightMode == FocusHighlightMode.traditional;

    double liftOffset;
    if (hovered) {
      liftOffset = -1;
    } else {
      liftOffset = 0;
    }

    BoxDecoration? focusOutline;
    if (_focused && usingKeyboard) {
      focusOutline = BoxDecoration(
        borderRadius: widget.radius,
        border: Border.all(color: colors.ink, width: 2, strokeAlign: 4),
      );
    } else {
      focusOutline = null;
    }

    Color fillColour;
    if (hovered) {
      fillColour = colors.surfaceStrong;
    } else if (colors.glass) {
      fillColour = colors.surface;
    } else {
      fillColour = colors.surfaceStrong;
    }

    Border? glassBorder;
    List<BoxShadow>? glassShadows;
    if (colors.glass) {
      glassBorder = Border.all(color: colors.border);
      if (dark) {
        glassShadows = [const BoxShadow(color: Color(0x80000000), blurRadius: 34, offset: Offset(0, 10))];
      } else {
        glassShadows = [const BoxShadow(color: Color(0x1A14281E), blurRadius: 30, offset: Offset(0, 10))];
      }
    } else {
      glassBorder = null;
      glassShadows = null;
    }

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
          onEnter: (_) {
            setState(() {
              _hovered = true;
            });
          },
          onExit: (_) {
            setState(() {
              _hovered = false;
            });
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            transform: Matrix4.translationValues(0, liftOffset, 0),
            width: widget.width,
            height: widget.height,
            foregroundDecoration: focusOutline,
            decoration: BoxDecoration(
              color: fillColour,
              borderRadius: widget.radius,
              border: glassBorder,
              boxShadow: glassShadows,
            ),
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                mouseCursor: SystemMouseCursors.click,
                borderRadius: widget.radius,
                onTap: widget.onTap,
                onFocusChange: (hasFocus) {
                  setState(() {
                    _focused = hasFocus;
                  });
                },
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
  State<_Unroll> createState() {
    return _UnrollState();
  }
}

class _UnrollState extends State<_Unroll> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = _createController();
  Timer? _delayTimer;

  /// The animation, starting at its end (1) if the tray is out and at its start (0) if not.
  AnimationController _createController() {
    double startValue;
    if (widget.open) {
      startValue = 1;
    } else {
      startValue = 0;
    }
    return AnimationController(vsync: this, duration: widget.time, value: startValue);
  }

  @override
  void didUpdateWidget(_Unroll oldWidget) {
    super.didUpdateWidget(oldWidget);
    _controller.duration = widget.time;
    if (widget.open == oldWidget.open) {
      return;
    }
    final delayTimer = _delayTimer;
    if (delayTimer != null) {
      delayTimer.cancel();
    }
    if (!widget.open) {
      _controller.reverse();
    } else if (widget.time == Duration.zero) {
      _controller.value = 1;
    } else {
      _delayTimer = Timer(widget.delay, _controller.forward);
    }
  }

  @override
  void dispose() {
    final delayTimer = _delayTimer;
    if (delayTimer != null) {
      delayTimer.cancel();
    }
    _controller.dispose();
    super.dispose();
  }

  /// Fades, slides and scales the item by the animation's progress, with the curves running
  /// forwards while opening and mirrored while closing.
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      child: widget.child,
      builder: (context, child) {
        final progress = _controller.value;
        final opening = _controller.status == AnimationStatus.forward || _controller.status == AnimationStatus.completed;
        double move;
        double fade;
        if (opening) {
          move = EdgeTray.ease.transform(progress);
          fade = Curves.ease.transform(math.min(1, progress / 0.8));
        } else {
          move = 1 - EdgeTray.ease.transform(1 - progress);
          fade = 1 - Curves.ease.transform(math.min(1, (1 - progress) / 0.8));
        }
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
}
