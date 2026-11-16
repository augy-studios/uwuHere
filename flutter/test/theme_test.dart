// The looks (lib/theme/theme.dart): which one each platform opens in and offers second, and the
// system's glass on the desktop keeping the contrast the other looks keep, in any accent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuhere/data/store.dart';
import 'package:uwuhere/theme/theme.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

void main() {
  tearDown(() {
    ThemeController.isAndroid = () => false;
    ThemeController.isDesktop = () => false;
  });

  test('the desktop offers the system\'s glass second, and reads a kept Material You as it', () {
    Store.memory();
    ThemeController.isAndroid = () => false;
    ThemeController.isDesktop = () => true;
    final t = ThemeController.I;
    expect(t.look, lookUwuApps);
    t.setLook(lookNative);
    expect(t.look, lookNative);
    expect(Store.I.get(keyLook), lookNative);
    Store.memory({keyLook: lookMaterial});
    expect(t.look, lookNative);
    expect(t.isMaterial, isFalse);
  });

  test('Android offers Material You second, and reads the desktop\'s glass as it', () {
    Store.memory({keyLook: lookNative});
    ThemeController.isAndroid = () => true;
    ThemeController.isDesktop = () => false;
    expect(ThemeController.I.look, lookMaterial);
    ThemeController.I.setLook(lookNative);
    expect(Store.I.get(keyLook), lookMaterial);
  });

  test('each system\'s glass: writing at 4.5:1 and control edges at 3:1, in any accent', () {
    const accents = [Color(0xFF0078D4), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFFFF2D55), Color(0xFF8E8E93), Color(0xFFFFFFFF)];
    for (final style in NativeStyle.values) {
      for (final b in Brightness.values) {
        for (final accent in accents) {
          final c = nativeColors(style, b, accent);
          final why = '${style.name} ${b.name} $accent';
          for (final surface in [c.bg, Color.alphaBlend(c.surface, c.bg), Color.alphaBlend(c.surfaceStrong, c.bg)]) {
            for (final ink in [c.ink, c.muted, c.brandInk, c.error, c.ok, c.warn]) {
              expect(contrast(ink, surface), greaterThanOrEqualTo(4.5), reason: '$why: $ink on $surface');
            }
          }
          expect(contrast(c.border, c.bg), greaterThanOrEqualTo(3), reason: '$why: edge');
          expect(contrast(c.onBrand, c.brandFill), greaterThanOrEqualTo(4.5), reason: '$why: on the accent');
          expect(c.native, isTrue);
        }
      }
    }
  });

  test('the system\'s glass builds a theme for each system, the page see-through', () {
    for (final style in NativeStyle.values) {
      final theme = buildTheme(look: lookNative, brightness: Brightness.light, brand: colorThemes.first.color, nativeStyle: style, desktop: true);
      expect(theme.scaffoldBackgroundColor, Colors.transparent);
      expect(theme.extension<UwuColors>()!.kind, isNot(GlassKind.uwu));
    }
    expect(nativeFont(NativeStyle.fluent).$1, 'Segoe UI Variable Text');
  });
}
