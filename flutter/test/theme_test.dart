// The looks (lib/theme/theme.dart): which one each platform opens in and offers second, and the
// system's glass on the desktop keeping the contrast the other looks keep, in any accent.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uwuhere/data/store.dart';
import 'package:uwuhere/theme/theme.dart';

/// The WCAG contrast ratio between two colours: the lighter one's luminance plus 0.05, over the
/// darker one's luminance plus 0.05.
double contrast(Color firstColor, Color secondColor) {
  final firstLuminance = firstColor.computeLuminance();
  final secondLuminance = secondColor.computeLuminance();
  double lighterLuminance;
  double darkerLuminance;
  if (firstLuminance > secondLuminance) {
    lighterLuminance = firstLuminance;
    darkerLuminance = secondLuminance;
  } else {
    lighterLuminance = secondLuminance;
    darkerLuminance = firstLuminance;
  }
  return (lighterLuminance + 0.05) / (darkerLuminance + 0.05);
}

void main() {
  tearDown(() {
    ThemeController.isAndroid = () {
      return false;
    };
    ThemeController.isDesktop = () {
      return false;
    };
  });

  test('the desktop offers the system\'s glass second, and reads a kept Material You as it', () {
    Store.memory();
    ThemeController.isAndroid = () {
      return false;
    };
    ThemeController.isDesktop = () {
      return true;
    };
    final themeController = ThemeController.I;
    expect(themeController.look, lookUwuApps);
    themeController.setLook(lookNative);
    expect(themeController.look, lookNative);
    expect(Store.I.get(keyLook), lookNative);
    Store.memory({keyLook: lookMaterial});
    expect(themeController.look, lookNative);
    expect(themeController.isMaterial, isFalse);
  });

  test('Android offers Material You second, and reads the desktop\'s glass as it', () {
    Store.memory({keyLook: lookNative});
    ThemeController.isAndroid = () {
      return true;
    };
    ThemeController.isDesktop = () {
      return false;
    };
    expect(ThemeController.I.look, lookMaterial);
    ThemeController.I.setLook(lookNative);
    expect(Store.I.get(keyLook), lookMaterial);
  });

  test('each system\'s glass: writing at 4.5:1 and control edges at 3:1, in any accent', () {
    const accents = [Color(0xFF0078D4), Color(0xFFFFCC00), Color(0xFF34C759), Color(0xFFFF2D55), Color(0xFF8E8E93), Color(0xFFFFFFFF)];
    for (final style in NativeStyle.values) {
      for (final brightness in Brightness.values) {
        for (final accent in accents) {
          final colors = nativeColors(style, brightness, accent);
          final description = '${style.name} ${brightness.name} $accent';
          for (final surface in [colors.bg, Color.alphaBlend(colors.surface, colors.bg), Color.alphaBlend(colors.surfaceStrong, colors.bg)]) {
            for (final ink in [colors.ink, colors.muted, colors.brandInk, colors.error, colors.ok, colors.warn]) {
              expect(contrast(ink, surface), greaterThanOrEqualTo(4.5), reason: '$description: $ink on $surface');
            }
          }
          expect(contrast(colors.border, colors.bg), greaterThanOrEqualTo(3), reason: '$description: edge');
          expect(contrast(colors.onBrand, colors.brandFill), greaterThanOrEqualTo(4.5), reason: '$description: on the accent');
          expect(colors.native, isTrue);
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
