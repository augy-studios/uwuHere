// A page as the site lays one out (main-site/css/app.css's main): the brand line, then glass cards
// in one centred column, scrolling, clear of the Edge Tray on a phone and of the system's bars.
// Its whole content, not just what's on screen, can be drawn as one picture (PageShots), for
// Report a bug's Screenshot a page and the desktop's long screenshot.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../app/env.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import 'common.dart';
import 'edge_tray.dart';

/// Which page's buttons go in the Edge Tray, and in the desktop's title bar.
class PageActions {
  PageActions._();
  static final ValueNotifier<List<TrayItem>> items = ValueNotifier(const []);
}

/// Each page's whole content, as a picture.
class PageShots {
  PageShots._();
  static final Map<String, GlobalKey> _keys = {};
  static GlobalKey key(String page) => _keys.putIfAbsent(page, () => GlobalKey(debugLabel: 'shot:$page'));

  /// The page drawn top to bottom, up to [maxHeight] pixels tall, or null if it isn't on screen.
  static Future<ui.Image?> whole(String page, {required double ratio, double maxHeight = 16384}) async {
    final box = _keys[page]?.currentContext?.findRenderObject();
    if (box is! RenderRepaintBoundary || !box.attached || !box.hasSize) return null;
    if (box.debugNeedsPaint) await Future<void>.delayed(const Duration(milliseconds: 40));
    final r = math.min(ratio, maxHeight / math.max(1, box.size.height));
    return box.toImage(pixelRatio: r);
  }
}

class PageFrame extends StatelessWidget {
  const PageFrame({super.key, required this.page, required this.children, this.controller, this.maxWidth = 560});

  /// The page's id (AppPages), for its picture.
  final String page;
  final List<Widget> children;
  final ScrollController? controller;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final pad = MediaQuery.paddingOf(context);
    return ValueListenableBuilder<bool>(
      valueListenable: EdgeTray.open,
      builder: (context, _, _) {
        final room = Env.desktop ? 0.0 : EdgeTray.roomFor(context);
        final side = MediaQuery.sizeOf(context).width <= 480 ? 14.0 : 20.0;
        return Scrollbar(
          controller: controller,
          child: SingleChildScrollView(
            controller: controller,
            padding: EdgeInsets.fromLTRB(side + pad.left, (Env.desktop ? 16 : 14) + pad.top, (room > 0 ? room : side) + pad.right, 32 + pad.bottom),
            child: RepaintBoundary(
              key: PageShots.key(page),
              child: ColoredBox(
                color: c.bg,
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: maxWidth),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (!Env.desktop)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 14, top: 4),
                            child: Row(
                              children: [
                                ClipRRect(borderRadius: BorderRadius.circular(8), child: Image.asset('assets/images/icon-256.png', width: 30, height: 30)),
                                const SizedBox(width: 10),
                                Text(
                                  'uwuHere',
                                  style: TextStyle(fontSize: 20, color: c.ink, fontFamily: 'Jua'),
                                ),
                              ],
                            ),
                          ),
                        for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: 14), children[i]],
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// The site's .glass.card: a panel with a heading.
class Card2 extends StatelessWidget {
  const Card2({super.key, this.title, this.titleKey, required this.children, this.big = false});
  final String? title;
  final Key? titleKey;
  final List<Widget> children;

  /// An h1 (the page's own heading) rather than an h2.
  final bool big;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Semantics(
                header: true,
                child: Text(
                  title!,
                  key: titleKey,
                  style: TextStyle(fontSize: big ? 24 : 19, color: c.ink, fontWeight: FontWeight.w600, height: 1.2),
                ),
              ),
            ),
          ...children,
        ],
      ),
    );
  }
}

/// The site's .banner: a sentence in a tinted box, plain, warning or error.
class Banner2 extends StatelessWidget {
  const Banner2(this.text, {super.key, this.tone = ''});
  final String text;

  /// '', 'warn' or 'error'.
  final String tone;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final ink = switch (tone) {
      'warn' => c.warn,
      'error' => c.error,
      _ => c.brandInk,
    };
    return Semantics(
      liveRegion: true,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(ink.withValues(alpha: 0.10), c.surfaceStrong),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink.withValues(alpha: 0.45)),
        ),
        child: Text(text, style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.35)),
      ),
    );
  }
}

/// A form field's label with its character counter (the site's .field-head and .counter).
class FieldHead extends StatelessWidget {
  const FieldHead(this.label, {super.key, this.count, this.max});
  final String label;
  final int? count;
  final int? max;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final full = count != null && max != null && count! >= max!;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 13, color: c.muted, fontWeight: FontWeight.w600),
            ),
          ),
          if (count != null && max != null)
            ExcludeSemantics(
              child: Text('$count/$max', style: TextStyle(fontSize: 12, color: full ? c.warn : c.muted)),
            ),
        ],
      ),
    );
  }
}

/// A quiet sentence under a field (the site's .hint).
class Hint extends StatelessWidget {
  const Hint(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(text, style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35)),
    );
  }
}

/// A button with an icon before its words.
class IconLabel extends StatelessWidget {
  const IconLabel(this.icon, this.label, {super.key, this.color});
  final String icon;
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final ink = color ?? DefaultTextStyle.of(context).style.color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        AppIcon(icon, size: 18, color: ink),
        const SizedBox(width: 8),
        Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
      ],
    );
  }
}
