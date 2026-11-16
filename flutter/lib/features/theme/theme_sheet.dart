// The Theme window (the site's #themeModal): light, dark or time-based, and the brand colour.
// The app adds the look. On Android: Material You (the device's own colours, the default on
// Android 12+) or the UwU Apps look (the site's swatches and font). On the desktop, whose default
// is the UwU Apps look: that first, then the system's own glass in Material You's place (Fluent 2
// on Windows, macOS Tahoe on a Mac, Deepin's and COSMIC's frosted glass on Linux; theme.dart). In
// the UwU Apps look the desktop's accent colour can stand in for the brand colour; the system's
// glass is always in it.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/env.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/sheet.dart';

/// Set by the desktop layer: whether "Use system accent colour" is on, and how to change it.
bool Function()? desktopAccentGet;
void Function(bool on)? desktopAccentSet;

Future<void> openThemeSheet(BuildContext context) => AppSheet.show(context, id: 'theme', width: 460, builder: (context) => const ThemeSheet());

class ThemeSheet extends StatelessWidget {
  const ThemeSheet({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ThemeController.I,
      builder: (context, _) {
        final t = ThemeController.I;
        final c = UwuColors.of(context);
        final material = t.isMaterial;
        final native = t.isNative;
        final style = t.nativeStyle;
        final accent = desktopAccentGet?.call() ?? false;

        Widget section(String text) => Padding(
          padding: const EdgeInsets.only(top: 16, bottom: 8),
          child: Text(
            text,
            style: TextStyle(color: c.muted, fontSize: 12.5, fontWeight: FontWeight.w600),
          ),
        );

        // The corners: a capsule on Tahoe, the look's own round a control elsewhere. Tahoe's picked
        // segment is a raised pane of brighter glass, as iOS's is, not the accent.
        final outer = c.capsule ? 22.0 : (c.native ? c.controlRadius + 4 : 12.0);
        final inner = math.max(2.0, outer - 3);
        final liquid = c.kind == GlassKind.liquid;
        final pickedFill = liquid ? Color.alphaBlend(Colors.white.withValues(alpha: c.ink.computeLuminance() > 0.5 ? 0.16 : 0.92), c.bg) : c.brandFill;
        final pickedInk = liquid ? c.ink : c.onBrand;
        Widget seg<T>(List<(T, String, String)> options, T value, ValueChanged<T> pick, {String key = ''}) => Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: c.surface,
            borderRadius: BorderRadius.circular(outer),
            border: Border.all(color: c.border),
          ),
          child: Row(
            children: [
              for (final o in options)
                Expanded(
                  child: Semantics(
                    selected: o.$1 == value,
                    button: true,
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      key: ValueKey('$key-${o.$1}'),
                      borderRadius: BorderRadius.circular(inner),
                      onTap: () => pick(o.$1),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: o.$1 == value ? pickedFill : null,
                          borderRadius: BorderRadius.circular(inner),
                          boxShadow: liquid && o.$1 == value
                              ? [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 8, offset: const Offset(0, 2))]
                              : null,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AppIcon(o.$2, size: 16, color: o.$1 == value ? pickedInk : c.ink),
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                o.$3,
                                style: TextStyle(fontSize: 13, color: o.$1 == value ? pickedInk : c.ink, fontWeight: liquid && o.$1 == value ? FontWeight.w600 : null),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return SheetFrame(
          title: 'Theme',
          children: [
            section('Look'),
            seg<String>(
              Env.desktop
                  ? [(lookUwuApps, 'sun', 'UwU Apps'), (lookNative, 'monitor', style.label)]
                  : [(lookMaterial, 'palette', 'Material You'), (lookUwuApps, 'sun', 'UwU Apps')],
              t.look,
              t.setLook,
              key: 'look',
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                native
                    ? switch (style) {
                        NativeStyle.fluent => 'Windows 11’s Fluent 2: Mica behind the window, Acrylic glass on what floats over it, in your accent colour.',
                        NativeStyle.tahoe => 'macOS Tahoe’s Liquid Glass: see-through panels that catch the light at their edges, in your accent colour.',
                        NativeStyle.frosted => 'The frosted glass of Deepin (DDE) and COSMIC: blurred, see-through panels, in your accent colour.',
                      }
                    : material
                    ? (t.hasDynamic
                          ? 'Colours and fonts from your device.'
                          : 'Material You’s colours and fonts. This device has no palette of its own to share, so it uses uwuHere’s green.')
                    : 'uwuHere’s own colours and font, as on the website.',
                style: TextStyle(color: c.muted, fontSize: 12.5),
              ),
            ),
            section('Mode'),
            seg<String>([('light', 'sun', 'Light'), ('dark', 'moon', 'Dark'), ('time', 'clock', 'Time-based')], t.modePreference, t.setMode, key: 'mode'),
            if (t.modePreference == 'time')
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('Following the clock. Currently ${t.mode}.', style: TextStyle(color: c.muted, fontSize: 12.5)),
              ),
            if (!material && !native) ...[
              if (Env.desktop && desktopAccentSet != null) ...[
                section('System accent'),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text('Use system accent colour', style: TextStyle(color: c.ink, fontSize: 14)),
                  subtitle: Text(
                    'Your computer’s accent for highlights, with uwuHere’s own surfaces and font.',
                    style: TextStyle(color: c.muted, fontSize: 12),
                  ),
                  value: accent,
                  onChanged: (v) => desktopAccentSet!(v),
                ),
              ],
              section('Brand colour'),
              Opacity(
                opacity: accent ? 0.45 : 1,
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    for (final ct in colorThemes)
                      Tooltip(
                        excludeFromSemantics: true,
                        message: ct.label,
                        child: Semantics(
                          label: ct.label,
                          selected: ct.id == t.colorThemeId,
                          button: true,
                          excludeSemantics: true,
                          child: InkWell(
                            mouseCursor: WidgetStateMouseCursor.clickable,
                            key: ValueKey('swatch-${ct.id}'),
                            customBorder: const CircleBorder(),
                            onTap: accent ? null : () => t.setColorTheme(ct.id),
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: ct.color,
                                shape: BoxShape.circle,
                                border: Border.all(color: ct.id == t.colorThemeId ? c.brandInk : c.border, width: ct.id == t.colorThemeId ? 3 : 1),
                              ),
                              child: ct.id == t.colorThemeId ? const Center(child: AppIcon('check', size: 18, color: Color(0xFF121815))) : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
