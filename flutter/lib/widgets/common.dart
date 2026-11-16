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

  /// In the systems' glass this hands over to NativeGlass. Otherwise it draws a tinted box with
  /// a border (and, in the glass look, a soft shadow and a blur of what's behind it).
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    if (colors.native) {
      double nativeRadius;
      if (radius == null) {
        nativeRadius = colors.panelRadius;
      } else {
        nativeRadius = radius!;
      }
      Color nativeFill;
      if (strong) {
        nativeFill = colors.surfaceStrong;
      } else {
        nativeFill = colors.surface;
      }
      return NativeGlass(
        radius: nativeRadius,
        fill: nativeFill,
        blur: blur,
        border: border,
        padding: padding,
        child: child,
      );
    }

    double cornerRadius;
    if (radius == null) {
      cornerRadius = 18;
    } else {
      cornerRadius = radius!;
    }

    Color fillColour;
    if (strong) {
      fillColour = colors.surfaceStrong;
    } else {
      fillColour = colors.surface;
    }

    BorderRadius? boxBorderRadius;
    if (cornerRadius == 0) {
      boxBorderRadius = null;
    } else {
      boxBorderRadius = BorderRadius.circular(cornerRadius);
    }

    Border boxBorder;
    if (border == null) {
      boxBorder = Border.all(color: colors.border);
    } else {
      boxBorder = border!;
    }

    List<BoxShadow>? boxShadows;
    if (colors.glass) {
      boxShadows = [
        BoxShadow(
          color: Colors.black.withValues(alpha: 0.08),
          blurRadius: 24,
          offset: const Offset(0, 8),
        ),
      ];
    } else {
      boxShadows = null;
    }

    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: fillColour,
        borderRadius: boxBorderRadius,
        border: boxBorder,
        boxShadow: boxShadows,
      ),
      child: child,
    );
    if (!colors.glass || !blur) {
      return box;
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(cornerRadius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: box,
      ),
    );
  }
}

/// A colour matrix that brightens colours by [saturation] (1 leaves them), as Apple's materials
/// and Fluent's Acrylic do to what they blur.
List<double> saturationMatrix(double saturation) {
  // How much each of red, green and blue counts towards how bright a colour looks.
  const redLuminanceWeight = 0.2126, greenLuminanceWeight = 0.7152, blueLuminanceWeight = 0.0722;
  final redShare = (1 - saturation) * redLuminanceWeight;
  final greenShare = (1 - saturation) * greenLuminanceWeight;
  final blueShare = (1 - saturation) * blueLuminanceWeight;
  return [
    redShare + saturation, greenShare, blueShare, 0, 0,
    redShare, greenShare + saturation, blueShare, 0, 0,
    redShare, greenShare, blueShare + saturation, 0, 0,
    0, 0, 0, 1, 0,
  ];
}

/// The blur behind the systems' glass: what's behind, its colours brightened, then blurred.
ImageFilter glassFilter(UwuColors colors, {double? blur}) {
  double sigma;
  if (blur == null) {
    sigma = colors.blur;
  } else {
    sigma = blur;
  }
  final softBlur = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma, tileMode: TileMode.mirror);
  if (colors.saturate == 1) {
    return softBlur;
  }
  return ImageFilter.compose(outer: softBlur, inner: ColorFilter.matrix(saturationMatrix(colors.saturate)));
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

  /// Layers, from the bottom: the shadow outside the shape, the blur of what's behind, the fill
  /// and its light, the child, and on top the rim (or the plain [border] in its place).
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);

    ShapeBorder outline;
    if (shape == null) {
      double cornerRadius;
      if (radius == null) {
        cornerRadius = colors.panelRadius;
      } else {
        cornerRadius = radius!;
      }
      outline = RoundedRectangleBorder(borderRadius: BorderRadius.circular(cornerRadius));
    } else {
      outline = shape!;
    }

    // Light ink means a dark page.
    final dark = colors.ink.computeLuminance() > 0.5;

    Color fillColour;
    if (fill == null) {
      fillColour = colors.surface;
    } else {
      fillColour = fill!;
    }

    CustomPainter? rimPainter;
    ShapeDecoration? plainEdgeDecoration;
    if (border == null) {
      rimPainter = _GlassRimPainter(outline, colors.kind, colors.rim, colors.rimShade);
      plainEdgeDecoration = null;
    } else {
      rimPainter = null;
      plainEdgeDecoration = ShapeDecoration(shape: outline.copyWith(side: border!.top));
    }

    Widget body = CustomPaint(
      painter: _GlassFillPainter(outline, fillColour, colors.kind, dark),
      foregroundPainter: rimPainter,
      child: Container(
        padding: padding,
        decoration: plainEdgeDecoration,
        child: child,
      ),
    );
    if (blur) {
      body = ClipPath(
        clipper: ShapeBorderClipper(shape: outline),
        child: BackdropFilter(filter: glassFilter(colors), child: body),
      );
    } else {
      body = ClipPath(clipper: ShapeBorderClipper(shape: outline), child: body);
    }
    if (!shadow) {
      return body;
    }
    return CustomPaint(painter: _OuterShadowPainter(outline, colors.kind, dark), child: body);
  }
}

extension on ShapeBorder {
  /// The same shape with the given edge, for the shapes the glass comes in; any other is left
  /// as it is.
  ShapeBorder copyWith({required BorderSide side}) {
    return switch (this) {
      final RoundedRectangleBorder roundedRectangle => roundedRectangle.copyWith(side: side),
      final StadiumBorder stadium => stadium.copyWith(side: side),
      final CircleBorder circle => circle.copyWith(side: side),
      _ => this,
    };
  }
}

/// The glass's fill: the see-through colour, then a veil of light that differs by system.
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
        _paintLiquidLight(canvas, path, rect);
      case GlassKind.fluent:
        _paintFluentLight(canvas, path, rect);
      case GlassKind.frosted:
        _paintFrostedLight(canvas, path, rect);
      default:
    }
  }

  /// The light lying across the top of the glass, thinning to nothing by the middle, and a
  /// little gathered at the bottom where it comes out again.
  void _paintLiquidLight(Canvas canvas, Path path, Rect rect) {
    double topAlpha;
    double bottomAlpha;
    if (dark) {
      topAlpha = 0.10;
      bottomAlpha = 0.04;
    } else {
      topAlpha = 0.34;
      bottomAlpha = 0.12;
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Colors.white.withValues(alpha: topAlpha),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: 0),
            Colors.white.withValues(alpha: bottomAlpha),
          ],
          stops: const [0, 0.42, 0.8, 1],
        ).createShader(rect),
    );
  }

  /// Acrylic's luminosity: an even veil, a touch lighter at the top.
  void _paintFluentLight(Canvas canvas, Path path, Rect rect) {
    double topAlpha;
    if (dark) {
      topAlpha = 0.025;
    } else {
      topAlpha = 0.10;
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.white.withValues(alpha: topAlpha), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  /// Frosted glass: a sheen from the top left corner, fading towards the bottom right.
  void _paintFrostedLight(Canvas canvas, Path path, Rect rect) {
    double cornerAlpha;
    if (dark) {
      cornerAlpha = 0.05;
    } else {
      cornerAlpha = 0.18;
    }
    canvas.drawPath(
      path,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white.withValues(alpha: cornerAlpha), Colors.white.withValues(alpha: 0)],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(_GlassFillPainter oldPainter) {
    return oldPainter.shape != shape || oldPainter.fill != fill || oldPainter.kind != kind || oldPainter.dark != dark;
  }
}

/// The glass's edge, drawn over its content, as each system draws it.
class _GlassRimPainter extends CustomPainter {
  _GlassRimPainter(this.shape, this.kind, this.rim, this.shade);
  final ShapeBorder shape;
  final GlassKind kind;
  final Color rim;
  final Color shade;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    // The shape's outline, pulled in by the given distance on every side.
    Path inset(double distance) {
      return shape.getOuterPath(rect.deflate(distance));
    }

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
  bool shouldRepaint(_GlassRimPainter oldPainter) {
    return oldPainter.shape != shape || oldPainter.kind != kind || oldPainter.rim != rim || oldPainter.shade != shade;
  }
}

/// The glass's shadow, drawn only outside its shape (the inside is clipped away), so the
/// see-through glass isn't darkened by its own shadow.
class _OuterShadowPainter extends CustomPainter {
  _OuterShadowPainter(this.shape, this.kind, this.dark);
  final ShapeBorder shape;
  final GlassKind kind;
  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final path = shape.getOuterPath(rect);

    // How dark the shadow is, how soft, and how far down it falls, by system.
    double shadowAlpha;
    double blurRadius;
    double dropDistance;
    switch (kind) {
      case GlassKind.liquid:
        if (dark) {
          shadowAlpha = 0.32;
        } else {
          shadowAlpha = 0.10;
        }
        blurRadius = 22.0;
        dropDistance = 8.0;
      case GlassKind.fluent:
        if (dark) {
          shadowAlpha = 0.26;
        } else {
          shadowAlpha = 0.06;
        }
        blurRadius = 8.0;
        dropDistance = 2.0;
      default:
        if (dark) {
          shadowAlpha = 0.30;
        } else {
          shadowAlpha = 0.08;
        }
        blurRadius = 16.0;
        dropDistance = 6.0;
    }

    canvas.save();
    canvas.clipPath(Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(rect.inflate(blurRadius * 3))
      ..addPath(path, Offset.zero));
    canvas.drawPath(
      path.shift(Offset(0, dropDistance)),
      Paint()
        ..color = Colors.black.withValues(alpha: shadowAlpha)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, blurRadius / 2),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_OuterShadowPainter oldPainter) {
    return oldPainter.shape != shape || oldPainter.kind != kind || oldPainter.dark != dark;
  }
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
    final colors = UwuColors.of(context);
    if (!colors.native) {
      return const SizedBox.shrink();
    }
    if (ThemeController.I.nativeBackdrop) {
      final tint = switch (colors.kind) {
        GlassKind.fluent => 0.0,
        GlassKind.liquid => 0.35,
        _ => 0.62,
      };
      return ColoredBox(color: colors.bg.withValues(alpha: tint));
    }
    return RepaintBoundary(
      child: CustomPaint(isComplex: true, painter: _GlowPainter(colors.bg, colors.glow), child: const SizedBox.expand()),
    );
  }
}

/// The page's colour with up to three soft round glows over it, standing in for a wallpaper.
class _GlowPainter extends CustomPainter {
  _GlowPainter(this.background, this.glow);
  final Color background;
  final List<Color> glow;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    canvas.drawRect(rect, Paint()..color = background);
    final longestSide = math.max(size.width, size.height);
    // Each glow's centre, as fractions of the width and height, and its radius, as a fraction of
    // the longest side.
    const spots = [(0.10, 0.02, 0.80), (0.96, 0.92, 0.75), (0.78, 0.12, 0.50)];
    for (var index = 0; index < glow.length && index < spots.length; index = index + 1) {
      final (horizontalFraction, verticalFraction, radiusFraction) = spots[index];
      final centre = Offset(size.width * horizontalFraction, size.height * verticalFraction);
      canvas.drawRect(
        rect,
        Paint()
          ..shader = RadialGradient(
            colors: [glow[index], glow[index].withValues(alpha: 0)],
          ).createShader(Rect.fromCircle(center: centre, radius: longestSide * radiusFraction)),
      );
    }
  }

  @override
  bool shouldRepaint(_GlowPainter oldPainter) {
    return oldPainter.background != background || !listEquals(oldPainter.glow, glow);
  }
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

  /// The button's outline. The systems' glass: a circle of glass on Tahoe, a rounded square
  /// elsewhere, with the glass's fine edge. The other looks: a rounded square with a border.
  ShapeBorder _shape(UwuColors colors) {
    if (colors.native) {
      if (colors.capsule) {
        return CircleBorder(side: BorderSide(color: colors.rimShade));
      }
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(colors.controlRadius + 2),
        side: BorderSide(color: colors.rimShade),
      );
    }
    return RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(14),
      side: BorderSide(color: colors.border),
    );
  }

  /// The icon's colour: the error colour for a dangerous action, else the brand's ink when
  /// pressed and the page's ink when not.
  Color _iconColour(UwuColors colors, bool pressed) {
    if (danger) {
      return colors.error;
    }
    if (pressed) {
      return colors.onBrand;
    }
    return colors.ink;
  }

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final pressed = active == true;

    TooltipTriggerMode? tooltipTrigger;
    if (longPressLabel) {
      tooltipTrigger = TooltipTriggerMode.longPress;
    } else {
      tooltipTrigger = null;
    }

    Color background;
    if (pressed) {
      background = colors.brandFill;
    } else {
      background = colors.surfaceStrong;
    }

    return Tooltip(
      excludeFromSemantics: true,
      message: label,
      triggerMode: tooltipTrigger,
      child: Semantics(
        button: true,
        toggled: active,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: background,
          shape: _shape(colors),
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
                  color: _iconColour(colors, pressed),
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
class RoundIconButton extends StatelessWidget {
  const RoundIconButton({
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

  /// Fluent's icon buttons are rounded squares; the other systems' glass ones round.
  ShapeBorder _shape(UwuColors colors) {
    if (colors.kind == GlassKind.fluent) {
      return RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(colors.controlRadius),
        side: BorderSide(color: colors.rimShade),
      );
    }
    Color edgeColour;
    if (colors.native) {
      edgeColour = colors.rimShade;
    } else {
      edgeColour = colors.border;
    }
    return CircleBorder(side: BorderSide(color: edgeColour));
  }

  /// The icon's colour: muted when the button can't be pressed, else [color] or the page's ink.
  Color _iconColour(UwuColors colors) {
    if (onPressed == null) {
      return colors.muted;
    }
    if (color == null) {
      return colors.ink;
    }
    return color!;
  }

  /// The button itself, and, when there's a [badge], its status light pinned over the corner.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    final button = Tooltip(
      excludeFromSemantics: true,
      message: label,
      child: Semantics(
        button: true,
        enabled: onPressed != null,
        label: label,
        excludeSemantics: true,
        child: Material(
          color: colors.surfaceStrong,
          shape: _shape(colors),
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
                  color: _iconColour(colors),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    if (badge == null) {
      return button;
    }
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
                border: Border.all(color: colors.bg, width: 2),
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
    if (!show) {
      return child;
    }
    final colors = UwuColors.of(context);
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
              color: colors.muted,
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
    final colors = UwuColors.of(context);
    Color ink;
    if (error) {
      ink = colors.error;
    } else {
      ink = colors.warn;
    }
    return Semantics(
      liveRegion: error,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: Color.alphaBlend(ink.withValues(alpha: 0.12), colors.surfaceStrong),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: ink.withValues(alpha: 0.5)),
        ),
        child: Text(
          text,
          style: TextStyle(color: colors.ink, fontSize: 13, height: 1.35),
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
    final colors = UwuColors.of(context);
    final colour = switch (light) {
      'ok' => colors.ok,
      'warn' => colors.warn,
      'error' => colors.error,
      _ => colors.busy,
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
              style: TextStyle(color: colors.ink, fontSize: 13.5, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }
}

/// A text field's name for a screen reader, kept once it holds text (a hint goes when it's typed
/// over, and with it the field's name).
class Named extends StatelessWidget {
  const Named(this.name, {super.key, required this.child});
  final String name;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return MergeSemantics(
      child: Semantics(label: name, child: child),
    );
  }
}

/// A form field's or section's label (the site's .modal-section-label).
class FieldLabel extends StatelessWidget {
  const FieldLabel(this.text, {super.key, this.note, this.top = 12});
  final String text;
  final String? note;
  final double top;

  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
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
                  color: colors.muted,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (note != null)
                TextSpan(
                  text: ' $note',
                  style: TextStyle(fontSize: 12, color: colors.muted),
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
    final colors = UwuColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: top),
      child: Text(
        text,
        style: TextStyle(color: colors.muted, fontSize: 12.5, height: 1.35),
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
    final colors = UwuColors.of(context);

    // Pressed, it takes the brand's fill and ink; not pressed, the surface and the page's ink.
    Color background;
    Color foreground;
    if (on) {
      background = colors.brandFill;
      foreground = colors.onBrand;
    } else {
      background = colors.surfaceStrong;
      foreground = colors.ink;
    }

    return Semantics(
      button: true,
      toggled: on,
      label: label,
      excludeSemantics: true,
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: colors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            child: Row(
              children: [
                AppIcon(icon, size: 16, color: foreground),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      color: foreground,
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
      builder: (context, constraints) {
        // Half the width, less half the 8 px gap between the two columns.
        final columnWidth = (constraints.maxWidth - 8) / 2;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [for (final child in children) SizedBox(width: columnWidth, child: child)],
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
    final colors = UwuColors.of(context);
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
                style: TextStyle(color: colors.ink, fontSize: 13.5),
              ),
            ),
            for (final keyName in keys)
              Container(
                margin: const EdgeInsets.only(left: 6),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.surfaceStrong,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: colors.border),
                ),
                child: Text(keyName, style: TextStyle(color: colors.ink, fontSize: 12)),
              ),
          ],
        ),
      ),
    );
  }
}
