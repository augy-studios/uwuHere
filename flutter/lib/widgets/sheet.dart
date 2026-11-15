// The app's windows over the page: the site's modals. Features never call
// showModalBottomSheet themselves; they call AppSheet.show(), which opens a bottom sheet on a
// phone and, on the desktop, a centred dialog or a slide-over panel from the right
// (lib/desktop/adaptive.dart).
import 'package:flutter/material.dart';

import '../app/env.dart';
import '../desktop/adaptive.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';

/// How a sheet shows on the desktop: in the middle (confirmations, pickers, settings), or as a
/// panel down the right-hand side (details and longer lists).
enum SheetKind { dialog, drawer }

class AppSheet {
  AppSheet._();

  /// The ids of the sheets open now, oldest first. The tours and the Back button read it.
  static final ValueNotifier<List<String>> open = ValueNotifier(const []);

  static bool isOpen(String id) => open.value.contains(id);
  static bool get anyOpen => open.value.isNotEmpty;

  static final Map<String, NavigatorState> _navigators = {};

  static Future<T?> show<T>(
    BuildContext context, {
    required String id,
    required WidgetBuilder builder,
    SheetKind kind = SheetKind.dialog,
    double width = 480,
    bool dismissible = true,
  }) async {
    if (isOpen(id)) return null;
    final nav = Navigator.of(context, rootNavigator: true);
    open.value = [...open.value, id];
    _navigators[id] = nav;
    try {
      final wide =
          Env.desktop || MediaQuery.sizeOf(context).width > Env.phoneWidth;
      if (wide) {
        return await showDesktopSheet<T>(
          context,
          builder: builder,
          kind: Env.desktop ? kind : SheetKind.dialog,
          width: width,
          dismissible: dismissible,
        );
      }
      return await showModalBottomSheet<T>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        useRootNavigator: true,
        isDismissible: dismissible,
        enableDrag: dismissible,
        backgroundColor: Colors.transparent,
        builder: (context) => Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Material(
            color: Theme.of(context).bottomSheetTheme.backgroundColor,
            shape: Theme.of(context).bottomSheetTheme.shape,
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * 0.92,
              ),
              child: builder(context),
            ),
          ),
        ),
      );
    } finally {
      open.value = [...open.value]..remove(id);
      _navigators.remove(id);
    }
  }

  /// Closes one sheet by id, wherever it is in the stack: only if it's on top.
  static void close(BuildContext context, [Object? result]) =>
      Navigator.of(context, rootNavigator: true).pop(result);

  /// Closes the window `id` if it's the one on top.
  static void closeId(String id) {
    if (open.value.isEmpty || open.value.last != id) return;
    _navigators[id]?.pop();
  }

  static void closeAll() {
    // The navigator's popUntil has already taken them; this is for the ones it hadn't.
    for (final nav in _navigators.values.toSet()) {
      nav.popUntil((r) => r.isFirst);
    }
  }
}

/// The inside of a sheet: a heading and a close button, a body that scrolls, and a row of
/// buttons that stays put.
class SheetFrame extends StatelessWidget {
  const SheetFrame({
    super.key,
    this.title,
    this.header,
    required this.children,
    this.footer,
    this.padding = const EdgeInsets.fromLTRB(20, 4, 20, 20),
  });

  final String? title;

  /// In place of the title: the card window's title is a field.
  final Widget? header;
  final List<Widget> children;
  final List<Widget>? footer;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 10, 6),
          child: Row(
            children: [
              Expanded(
                child:
                    header ??
                    Semantics(
                      header: true,
                      child: Text(
                        title ?? '',
                        style: TextStyle(
                          fontSize: 18,
                          color: c.ink,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
              ),
              IconButton(
                tooltip: 'Close',
                onPressed: () => AppSheet.close(context),
                icon: AppIcon('close', color: c.muted, size: 18),
              ),
            ],
          ),
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: padding,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: children,
            ),
          ),
        ),
        if (footer != null)
          Container(
            decoration: BoxDecoration(
              border: Border(top: BorderSide(color: c.border)),
            ),
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: footer!,
            ),
          ),
      ],
    );
  }
}

/// A window's shortcut pressed: shut if it's the one open, else open, with anything else open shut
/// first so two never stack (app.js's toggleModalShortcut).
void toggleSheet(
  BuildContext context,
  String id,
  Future<void> Function() show,
) {
  if (AppSheet.isOpen(id)) {
    AppSheet.closeId(id);
    return;
  }
  AppSheet.closeAll();
  show();
}
