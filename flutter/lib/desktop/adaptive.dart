// What a computer does differently from a phone, for the shared widgets
// (docs/flutter-desktop-app-spec.md §2.4): sheets as centred dialogs or a slide-over panel
// from the right, right-click menus, hover highlights with a pointer cursor, and scrolling
// without Android's stretch.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../app/env.dart';
import '../app/nav.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import '../widgets/sheet.dart';

Future<T?> showDesktopSheet<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  required SheetKind kind,
  required double width,
  bool dismissible = true,
}) {
  final reduce = MediaQuery.disableAnimationsOf(context);
  return showGeneralDialog<T>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: dismissible,
    barrierLabel: 'Close',
    barrierColor: UwuColors.of(context).scrim,
    transitionDuration: Duration(milliseconds: reduce ? 0 : 180),
    pageBuilder: (context, _, _) {
      final c = UwuColors.of(context);
      final size = MediaQuery.sizeOf(context);
      final panel = Material(
        color: Theme.of(context).dialogTheme.backgroundColor,
        shape: kind == SheetKind.drawer
            ? Border(left: BorderSide(color: c.border))
            : RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: c.border),
              ),
        clipBehavior: Clip.antiAlias,
        elevation: 12,
        child: builder(context),
      );
      if (kind == SheetKind.drawer) {
        return Align(
          alignment: Alignment.centerRight,
          child: SizedBox(
            width: (size.width - 60 < 320 ? size.width : width.clamp(320, size.width - 60)),
            height: double.infinity,
            child: SafeArea(left: false, child: panel),
          ),
        );
      }
      return SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: width, maxHeight: size.height * 0.9),
              child: panel,
            ),
          ),
        ),
      );
    },
    transitionBuilder: (context, anim, _, child) {
      final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic);
      if (kind == SheetKind.drawer) {
        return SlideTransition(
          position: Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
          child: child,
        );
      }
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(scale: Tween(begin: 0.97, end: 1.0).animate(curved), child: child),
      );
    },
  );
}

/// One line of a right-click menu.
class MenuAction {
  const MenuAction(this.label, this.onTap, {this.icon, this.danger = false, this.enabled = true});
  final String label;
  final VoidCallback onTap;
  final String? icon;
  final bool danger;
  final bool enabled;
}

Future<void> showContextMenu(BuildContext context, Offset position, List<MenuAction> actions) async {
  if (actions.isEmpty) return;
  final c = UwuColors.of(context);
  // The menu opens in the navigator's overlay, which starts below the desktop's title bar, so the
  // pointer's place in the window is turned into a place in that overlay.
  final overlay = (AppNav.navigatorKey.currentState?.overlay ?? Overlay.of(context)).context.findRenderObject() as RenderBox;
  final at = overlay.globalToLocal(position);
  final picked = await showMenu<int>(
    context: context,
    useRootNavigator: true,
    position: RelativeRect.fromRect(at & const Size(1, 1), Offset.zero & overlay.size),
    color: Color.alphaBlend(c.surfaceStrong, c.bg),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: c.border),
    ),
    items: [
      for (var i = 0; i < actions.length; i++)
        PopupMenuItem<int>(
          value: i,
          enabled: actions[i].enabled,
          height: 36,
          child: Row(
            children: [
              if (actions[i].icon != null) ...[AppIcon(actions[i].icon!, size: 16, color: actions[i].danger ? c.error : c.ink), const SizedBox(width: 10)],
              Text(actions[i].label, style: TextStyle(fontSize: 13, color: actions[i].danger ? c.error : c.ink)),
            ],
          ),
        ),
    ],
  );
  if (picked != null) actions[picked].onTap();
}

/// Wraps something that can be right-clicked (or, on a phone, pressed and held). `actions` is
/// asked for as the menu opens, so it says what's true then.
class ContextMenuRegion extends StatelessWidget {
  const ContextMenuRegion({super.key, required this.actions, required this.child, this.longPress = false});

  final List<MenuAction> Function() actions;
  final Widget child;

  /// Also on a long press: off where a long press already means something (dragging a card).
  final bool longPress;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.deferToChild,
      onSecondaryTapUp: (d) => showContextMenu(context, d.globalPosition, actions()),
      onLongPressStart: longPress ? (d) => showContextMenu(context, d.globalPosition, actions()) : null,
      child: child,
    );
  }
}

/// A pointer cursor and a soft highlight under the mouse, for anything that can be clicked.
class Hoverable extends StatefulWidget {
  const Hoverable({super.key, required this.child, this.onTap, this.radius = 10, this.selected = false, this.padding});

  final Widget child;
  final VoidCallback? onTap;
  final double radius;
  final bool selected;
  final EdgeInsets? padding;

  @override
  State<Hoverable> createState() => _HoverableState();
}

class _HoverableState extends State<Hoverable> {
  bool _over = false;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final fill = widget.selected ? c.brandFillStrong : (_over ? c.surfaceStrong : Colors.transparent);
    return MouseRegion(
      cursor: widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
      onEnter: (_) => setState(() => _over = true),
      onExit: (_) => setState(() => _over = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          padding: widget.padding,
          decoration: BoxDecoration(color: fill, borderRadius: BorderRadius.circular(widget.radius)),
          child: widget.child,
        ),
      ),
    );
  }
}

/// Scrolling as a computer does it: no stretch or glow at the ends, a scrollbar that stays, and
/// dragging with a mouse as well as a finger (the board's columns are dragged sideways).
class AppScrollBehavior extends MaterialScrollBehavior {
  const AppScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => {...super.dragDevices, PointerDeviceKind.mouse, PointerDeviceKind.trackpad, PointerDeviceKind.stylus};

  @override
  Widget buildOverscrollIndicator(BuildContext context, Widget child, ScrollableDetails details) =>
      Env.desktop ? child : super.buildOverscrollIndicator(context, child, details);

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) => Env.desktop ? const ClampingScrollPhysics() : super.getScrollPhysics(context);
}
