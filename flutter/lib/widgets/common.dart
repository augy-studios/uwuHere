// Small pieces the screens share, after the site's (main-site/css/app.css): glass panels and
// buttons, a control with its keyboard shortcut under it, a banner, a status light, and a
// field's label.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../theme/icons.dart';
import '../theme/theme.dart';

/// The site's .glass: a see-through panel with a soft edge, solid in Material You, and the
/// system's own glass in that look (NativeGlass).
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius,
    this.padding,
    this.strong = false,
    this.blur = true,
    this.border,
  });

  final Widget child;

  /// The corners: the look's own for panels when not given.
  final double? radius;
  final EdgeInsets? padding;
  final bool strong;
  final bool blur;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    if (c.native) {
      return NativeGlass(
        radius: radius ?? c.panelRadius,
        fill: strong ? c.surfaceStrong : c.surface,
        blur: blur,
        border: border,
        padding: padding,
        child: child,
      );
    }
    final r = radius ?? 18;
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? c.surfaceStrong : c.surface,
        borderRadius: r == 0 ? null : BorderRadius.circular(r),
        border: border ?? Border.all(color: c.border),
        boxShadow: c.glass
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ]
            : null,
      ),
      child: child,
    );
    if (!c.glass || !blur) return box;
    return ClipRRect(
      borderRadius: BorderRadius.circular(r),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: box,
      ),
    );
  }
}

/// A colour matrix that brightens colours by [s] (1 leaves them), as Apple's materials and
/// Fluent's Acrylic do to what they blur.
List<double> saturationMatrix(double s) {
  const lr = 0.2126, lg = 0.7152, lb = 0.0722;
  final r = (1 - s) * lr, g = (1 - s) * lg, b = (1 - s) * lb;
  return [r + s, g, b, 0, 0, r, g + s, b, 0, 0, r, g, b + s, 0, 0, 0, 0, 0, 1, 0];
}

/// The blur behind the systems' glass: what's behind, its colours brightened, then blurred.
ImageFilter glassFilter(UwuColors c, {double? blur}) {
  final sigma = blur ?? c.blur;
  final soft = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror);
  if (c.saturate == 1) return soft;
  return ImageFilter.compose(outer: soft, inner: ColorFilter.matrix(saturationMatrix(c.saturate)));
}

/// The systems' glass (lib/theme/theme.dart): a see-through fill over a blur of what's behind it,
/// and its edge as each system draws one.
///   Fluent 2       Acrylic: a fine edge, darker along the bottom where the panel lifts off
///   macOS Tahoe    Liquid Glass: a band of light across the top, and a bright rim, brightest
///                  where the light catches the top left corner and again at the bottom right
///   Frosted Glass  a frosted fill with a bright top edge fading down the sides
/// Its shadow is drawn outside it only, so the glass isn't darkened by its own shadow.
class NativeGlass extends StatelessWidget {
  const NativeGlass({
    super.key,
    required this.child,
    this.radius,
    this.shape,
    this.fill,
    this.blur = true,
    this.shadow = true,
    this.border,
    this.padding,
  });

  final Widget child;

  /// The corners: the look's own for panels when neither this nor [shape] is given.
  final double? radius;

  /// In place of [radius]: a capsule or a circle, say.
  final ShapeBorder? shape;
  final Color? fill;
  final bool blur;
  final bool shadow;

  /// A plain edge in place of the glass's own.
  final Border? border;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final outline = shape ?? RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius ?? c.panelRadius));
    final dark = c.ink.computeLuminance() > 0.5;
    Widget body = CustomPaint(
      painter: _GlassFillPainter(outline, fill ?? c.surface, c.kind, dark),
      foregroundPainter: border == null ? _GlassRimPainter(outline, c.kind, c.rim, c.rimShade) : null,
      child: Container(
        padding: padding,
        decoration: border == null ? null : ShapeDecoration(shape: outline.copyWith(side: border!.top)),
        child: child,
      ),
    );
    if (blur) {
      body = ClipPath(
        clipper: ShapeBorderClipper(shape: outline),
        child: BackdropFilter(filter: glassFilter(c), child: body),
      );
    } else {
      body = ClipPath(clipper: ShapeBorderClipper(shape: outline), child: body);
    }
    if (!shadow) return body;
    return CustomPaint(painter: _OuterShadowPainter(outline, c.kind, dark), child: body);
  }
}

extension on ShapeBorder {
  ShapeBorder copyWith({required BorderSide side}) => switch (this) {
    final RoundedRectangleBorder b => b.copyWith(side: side),
    final StadiumBorder b => b.copyWith(side: side),
    final CircleBorder b => b.copyWith(side: side),
    _ => this,
  };
}

class _GlassFillPainter extends CustomPainter {
  _GlassFillPainter(this.shape, this.fill, this.kind, this.dark);
  final ShapeBorder shape;
  final Color fill;
  final GlassKind kind;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    canvas.drawPath(path, Paint()..color = fill);
    switch (kind) {
      case GlassKind.liquid:
        // The light lying across the top of the glass, thinning to nothing by the middle, and a
        // little gathered at the bottom where it comes out again.
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                Colors.white.withValues(alpha: dark ? 0.10 : 0.34),
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: 0),
                Colors.white.withValues(alpha: dark ? 0.04 : 0.12),
              ],
              stops: const [0, 0.42, 0.8, 1],
            ).createShader(rect),
        );
      case GlassKind.fluent:
        // Acrylic's luminosity: an even veil, a touch lighter at the top.
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Colors.white.withValues(alpha: dark ? 0.025 : 0.10), Colors.white.withValues(alpha: 0)],
            ).createShader(rect),
        );
      case GlassKind.frosted:
        canvas.drawPath(
          path,
          Paint()
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [Colors.white.withValues(alpha: dark ? 0.05 : 0.18), Colors.white.withValues(alpha: 0)],
            ).createShader(rect),
        );
      default:
    }
  }

  @override
  bool shouldRepaint(_GlassFillPainter old) => old.shape != shape || old.fill != fill || old.kind != kind || old.dark != dark;
}

class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter(this.shape, this.kind, this.rim, this.shade);
  final ShapeBorder shape;
  final GlassKind kind;
  final Color rim;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    Path inset(double by) => shape.getOuterPath(rect.deflate(by));
    switch (kind) {
      case GlassKind.liquid:
        // A fine dark line round the outside, so light glass still shows on a light page, then the
        // rim: bright at the top left, faint down the sides, bright again at the bottom right.
        canvas.drawPath(inset(0.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = shade);
        canvas.drawPath(
          inset(1.1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.4
            ..shader = LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [rim, rim.withValues(alpha: rim.a * 0.22), rim.withValues(alpha: rim.a * 0.12), rim.withValues(alpha: rim.a * 0.7)],
              stops: const [0, 0.35, 0.65, 1],
            ).createShader(rect),
        );
        // The glass's thickness: a softer line just inside, along the top.
        canvas.drawPath(
          inset(2.4),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.2
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rim.withValues(alpha: rim.a * 0.35), rim.withValues(alpha: 0)],
              stops: const [0, 0.25],
            ).createShader(rect),
        );
      case GlassKind.fluent:
        canvas.drawPath(
          inset(0.5),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rim, rim, shade],
              stops: const [0, 0.88, 1],
            ).createShader(rect),
        );
      case GlassKind.frosted:
        canvas.drawPath(inset(0.5), Paint()..style = PaintingStyle.stroke..strokeWidth = 1..color = shade);
        canvas.drawPath(
          inset(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1
            ..shader = LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [rim, rim.withValues(alpha: 0)],
              stops: const [0, 0.4],
            ).createShader(rect),
        );
      default:
    }
  }

  @override
  bool shouldRepaint(_GlassRimPainter old) => old.shape != shape || old.kind != kind || old.rim != rim || old.shade != shade;
}

class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.shape, this.kind, this.dark);
  final ShapeBorder shape;
  final GlassKind kind;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);
    final (alpha, blur, dy) = switch (kind) {
      GlassKind.liquid => (dark ? 0.32 : 0.10, 22.0, 8.0),
      GlassKind.fluent => (dark ? 0.26 : 0.06, 8.0, 2.0),
      _ => (dark ? 0.30 : 0.08, 16.0, 6.0),
    };
    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(blur * 3))
      ..addPath(path, Offset.zero));
    canvas.drawPath(
      path.shift(Offset(0, dy)),
      Paint()
        ..color = Colors.black.withValues(alpha: alpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blur / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter old) => old.shape != shape || old.kind != kind || old.dark != dark;
}

/// What's behind the whole window in the systems' glass. Where the system shows its own material
/// there (Mica, the vibrancy, the compositor's blur; ThemeController.nativeBackdrop), only the
/// page's tint over it, for the words to read at the contrast measured. Elsewhere, the page's
/// colour with soft glows in the accent and its neighbours standing in for the wallpaper, so the
/// glass over it has something to blur. Nothing in the other looks.
class NativeBackdrop extends StatelessWidget {
  const NativeBackdrop({super.key});

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    if (!c.native) return const SizedBox.shrink();
    if (ThemeController.I.nativeBackdrop) {
      final tint = switch (c.kind) {
        GlassKind.fluent => 0.0,
        GlassKind.liquid => 0.35,
        _ => 0.62,
      };
      return ColoredBox(color: c.bg.withValues(alpha: tint));
    }
    return RepaintBoundary(
      child: CustomPaint(isComplex: true, painter: _GlowPainter(c.bg, c.glow), child: const SizedBox.expand()),
    );
  }
}

class _GlowPainter extends CustomPainter {
  _GlowPainter(this.bg, this.glow);
  final Color bg;
  final List<Color> glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = bg);
    final m = math.max(size.width, size.height);
    const spots = [(0.10, 0.02, 0.80), (0.96, 0.92, 0.75), (0.78, 0.12, 0.50)];
    for (var i = 0; i < glow.length && i < spots.length; i++) {
      final (x, y, r) = spots[i];
      final centre = Offset(size.width * x, size.height * y);
      canvas.drawRect(
        rect,
        Paint()..shader = RadialGradient(colors: [glow[i], glow[i].withValues(alpha: 0)]).createShader(Rect.fromCircle(center: centre, radius: m * r)),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter old) => old.bg != bg || !listEquals(old.glow, glow);
}

/// The site's .glass-btn: a rounded square icon button, labelled for screen readers, its label on
/// hover and (in the edge tray) on a long press. `active` is the site's aria-pressed.
class GlassButton extends StatelessWidget {
  const GlassButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.danger = false,
    this.size = 44,
    this.active,
    this.longPressLabel = false,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final bool danger;
  final double size;

  /// Null for a plain button; true or false for a toggle.
  final bool? active;
  final bool longPressLabel;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final on = active == true;
    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      triggerMode: longPressLabel ? TooltipTriggerMode.longPress : null,
      child: Semantics(
        button: true,
        toggled: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: on ? c.brandFill : c.surfaceStrong,
          // The systems' glass: a circle of glass on Tahoe, a rounded square elsewhere, with the
          // glass's fine edge.
          shape: c.native
              ? (c.capsule
                    ? CircleBorder(side: BorderSide(color: c.rimShade))
                    : RoundedRectangleBorder(borderRadius: BorderRadius.circular(c.controlRadius + 2), side: BorderSide(color: c.rimShade)))
              : RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: BorderSide(color: c.border),
                ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: AppIcon(
                  icon,
                  size: size * 0.45,
                  color: danger ? c.error : (on ? c.onBrand : c.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A round icon button (the site's .icon-btn).
class IconBtn extends StatelessWidget {
  const IconBtn({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.size = 40,
    this.color,
    this.badge,
  });

  final String icon;
  final String label;
  final VoidCallback? onPressed;
  final double size;
  final Color? color;

  /// A status light over the top right corner (the remote button's).
  final Color? badge;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final button = Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: c.surfaceStrong,
          // Fluent's icon buttons are rounded squares; the other systems' glass ones round.
          shape: c.kind == GlassKind.fluent
              ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(c.controlRadius), side: BorderSide(color: c.rimShade))
              : CircleBorder(side: BorderSide(color: c.native ? c.rimShade : c.border)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: onPressed,
            child: SizedBox(
              width: size,
              height: size,
              child: Center(
                child: AppIcon(
                  icon,
                  size: size * 0.45,
                  color: onPressed == null ? c.muted : (color ?? c.ink),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (badge == null) return button;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        button,
        Positioned(
          right: -1,
          top: -1,
          child: IgnorePointer(
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: badge,
                shape: BoxShape.circle,
                border: Border.all(color: c.bg, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// A control with its keyboard shortcut printed under it (the site's .key-action). The hint is a
/// caption, hidden from screen readers: the control's name already ends in the same keys.
class KeyAction extends StatelessWidget {
  const KeyAction({
    super.key,
    required this.hint,
    required this.child,
    this.show = true,
  });
  final String hint;
  final Widget child;
  final bool show;

  @override
  Widget build(BuildContext context) {
    if (!show) return child;
    final c = UwuColors.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        const SizedBox(height: 3),
        ExcludeSemantics(
          child: Text(
            hint,
            style: TextStyle(
              fontSize: 10,
              height: 1,
              color: c.muted,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ],
    );
  }
}

/// The site's .banner: a note in a tinted box, warning or error.
class NoteBanner extends StatelessWidget {
  const NoteBanner(this.text, {super.key, this.error = false});
  final String text;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final ink = error ? c.error : c.warn;
    return Semantics(
      liveRegion: error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(ink.withValues(alpha: 0.12), c.surfaceStrong),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(color: c.ink, fontSize: 13, height: 1.35),
        ),
      ),
    );
  }
}

/// A status light and its sentence (the site's .remote-status).
class StatusLine extends StatelessWidget {
  const StatusLine({super.key, required this.light, required this.text});

  /// 'ok', 'warn', 'error' or '' for grey.
  final String light;
  final String text;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final colour = switch (light) {
      'ok' => c.ok,
      'warn' => c.warn,
      'error' => c.error,
      _ => c.busy,
    };
    return Semantics(
      liveRegion: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: c.ink, fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// A form field's or section's label (the site's .modal-section-label).
/// A text field's name for a screen reader, kept once it holds text (a hint goes when it's typed
/// over, and with it the field's name).
class Named extends StatelessWidget {
  const Named(this.name, {super.key, required this.child});
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Semantics(label: name, child: child),
  );
}

class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.note, this.top = 12});
  final String text;
  final String? note;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: 6, top: top),
      child: Semantics(
        header: true,
        child: Text.rich(
          TextSpan(
            children: [
              TextSpan(
                text: text,
                style: TextStyle(
                  fontSize: 12.5,
                  color: c.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (note != null)
                TextSpan(
                  text: ' $note',
                  style: TextStyle(fontSize: 12, color: c.muted),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A quiet note (the site's .mode-note).
class Note extends StatelessWidget {
  const Note(this.text, {super.key, this.top = 6});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        text,
        style: TextStyle(color: c.muted, fontSize: 12.5, height: 1.35),
      ),
    );
  }
}

/// A toggle as the site's .toggle-btn: an icon and a label, pressed or not.
class ToggleChip extends StatelessWidget {
  const ToggleChip({
    super.key,
    required this.icon,
    required this.label,
    required this.on,
    required this.onTap,
  });
  final String icon;
  final String label;
  final bool on;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: on ? c.brandFill : c.surfaceStrong,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                AppIcon(icon, size: 16, color: on ? c.onBrand : c.ink),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: on ? c.onBrand : c.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Two columns of toggles, as the site's .toggle-grid.
class ToggleGrid extends StatelessWidget {
  const ToggleGrid({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = (box.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final c in children) SizedBox(width: w, child: c)],
        );
      },
    );
  }
}

/// A keyboard shortcut's row, as the site's .shortcut-row.
class ShortcutRow extends StatelessWidget {
  const ShortcutRow(this.label, this.keys, {super.key});
  final String label;
  final List<String> keys;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Semantics(
      label: '$label: ${keys.join(' ')}',
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: TextStyle(color: c.ink, fontSize: 13.5),
              ),
            ),
            for (final k in keys)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: c.surfaceStrong,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: c.border),
                ),
                child: Text(k, style: TextStyle(color: c.ink, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
