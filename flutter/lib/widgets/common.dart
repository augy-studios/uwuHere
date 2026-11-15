// Small pieces the screens share, after the site's (main-site/css/app.css): glass panels and
// buttons, a control with its keyboard shortcut under it, a banner, a status light, and a
// field's label.
import 'dart:ui';

import 'package:flutter/material.dart';

import '../theme/icons.dart';
import '../theme/theme.dart';

/// The site's .glass: a see-through panel with a soft edge, solid in Material You.
class GlassPanel extends StatelessWidget {
  const GlassPanel({
    super.key,
    required this.child,
    this.radius = 18,
    this.padding,
    this.strong = false,
    this.blur = true,
    this.border,
  });

  final Widget child;
  final double radius;
  final EdgeInsets? padding;
  final bool strong;
  final bool blur;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final box = Container(
      padding: padding,
      decoration: BoxDecoration(
        color: strong ? c.surfaceStrong : c.surface,
        borderRadius: radius == 0 ? null : BorderRadius.circular(radius),
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
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: box,
      ),
    );
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
          shape: RoundedRectangleBorder(
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
          shape: CircleBorder(side: BorderSide(color: c.border)),
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
