// The theme, built in one place for every look and both modes.
//
//   The UwU Apps look   the site's own (main-site/css/theme.css and js/theme.js): seven brand
//                       swatches, the Jua font, flat tinted pages and glass panels.
//   Material You        the Android app's second look: the device's palette and fonts. On by
//                       default on Android 12+, where the system has a palette to give.
//   The system's glass  the desktop apps' second look, in Material You's place: each system's own
//                       design at its glassiest, the nearest each gets to iOS's Liquid Glass.
//                         Windows  Fluent 2: Mica behind the window, Acrylic on what floats,
//                                  Segoe UI Variable, 4 and 8 px corners
//                         macOS    macOS Tahoe: Liquid Glass, with a bright rim where light
//                                  catches the edge, capsule buttons and round corners
//                         Linux    the frosted glass of Deepin (DDE) and COSMIC
//                       In the system's accent colour. Where the system can show its own material
//                       behind the window (lib/desktop/backdrop.dart) the page lets it through;
//                       elsewhere soft glows in the accent stand in for the wallpaper, so the
//                       glass has something to blur. The desktop apps still open in the UwU Apps
//                       look.
//
// Mode is the site's: light, dark, or time-based (light from 09:00 to 18:00), kept under the
// site's keys so a theme brought over from the old app means the same here. Colours reach widgets as
// tokens (UwuColors), never as literals.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../data/store.dart';

class ColorTheme {
  const ColorTheme(this.id, this.label, this.hex);
  final String id;
  final String label;
  final int hex;
  Color get color => Color(0xFF000000 | hex);
}

/// The site's swatches, by the site's ids and names.
const colorThemes = [
  ColorTheme('classic', 'Classic', 0xccffcc),
  ColorTheme('not-green-1', 'Not green 1', 0xffcccc),
  ColorTheme('not-green-2', 'Not green 2', 0xccccff),
  ColorTheme('not-green-3', 'Not green 3', 0xffffcc),
  ColorTheme('not-green-4', 'Not green 4', 0xffccff),
  ColorTheme('not-green-5', 'Not green 5', 0xccffff),
  ColorTheme('really-light-green', 'Really really light green', 0xffffff),
];

const modePreferences = ['light', 'dark', 'time'];
const lightFromHour = 9;
const lightUntilHour = 18;

const _keyColor = 'uwuhere.colorTheme';
const _keyMode = 'uwuhere.mode';

/// The app's own key: which look, 'material', 'native' or 'uwuapps'. Unset follows the platform.
/// The second look is Material You on Android and the system's glass on the desktop, and each
/// reads the other's value as itself: a desktop that kept 'material' (which it offered before)
/// opens in the system's glass.
const keyLook = 'app.look';
const lookMaterial = 'material';
const lookNative = 'native';
const lookUwuApps = 'uwuapps';

/// The desktop's second look: each system's own glass.
enum NativeStyle {
  /// Windows 11: Fluent 2, with Mica behind the window and Acrylic on what floats over it.
  fluent('Fluent 2', 'Acrylic & Mica', Color(0xFF0078D4)),

  /// macOS 26: Liquid Glass.
  tahoe('macOS Tahoe', 'Liquid Glass', Color(0xFF007AFF)),

  /// Linux: the frosted glass of Deepin (DDE) and COSMIC.
  frosted('Frosted Glass', 'Deepin & COSMIC', Color(0xFF0081FF));

  const NativeStyle(this.label, this.detail, this.defaultAccent);

  /// The look's name, in the Theme window.
  final String label;

  /// What it's made of, under the name.
  final String detail;

  /// The system's own accent, for when it can't be read.
  final Color defaultAccent;

  /// This computer's.
  static NativeStyle get current {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.macOS) return tahoe;
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.linux) return frosted;
    return fluent;
  }
}

/// How panels are drawn: solid (Material You), the site's glass, or one of the systems'.
enum GlassKind { solid, uwu, fluent, liquid, frosted }

bool isDaylightHours([DateTime? now]) {
  final h = (now ?? DateTime.now()).hour;
  return h >= lightFromHour && h < lightUntilHour;
}

String resolveMode(String preference, [DateTime? now]) {
  if (preference == 'time') return isDaylightHours(now) ? 'light' : 'dark';
  return preference == 'dark' ? 'dark' : 'light';
}

/// How long until the next 09:00 or 18:00, whichever comes first, with a second of slack.
Duration untilNextBoundary([DateTime? at]) {
  final now = at ?? DateTime.now();
  DateTime next;
  if (now.hour < lightFromHour) {
    next = DateTime(now.year, now.month, now.day, lightFromHour);
  } else if (now.hour < lightUntilHour) {
    next = DateTime(now.year, now.month, now.day, lightUntilHour);
  } else {
    next = DateTime(now.year, now.month, now.day + 1, lightFromHour);
  }
  final ms = next.difference(now).inMilliseconds + 1000;
  return Duration(milliseconds: ms < 1000 ? 1000 : ms);
}

class ThemeController extends ChangeNotifier with WidgetsBindingObserver {
  ThemeController._();
  static final ThemeController I = ThemeController._();

  Timer? _timer;
  bool _watching = false;

  /// Whether the device has a palette of its own to give (Android 12+). Set by the app's root
  /// once the system has answered.
  bool hasDynamic = false;

  /// The desktop's "Use system accent colour", kept in its settings file.
  bool systemAccent = false;

  /// Whether this is the Android app (Env.android, given here to keep the theme free of the app).
  static bool Function() isAndroid = () => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// Whether this is a desktop app (Env.desktop), whose second look is the system's glass.
  static bool Function() isDesktop = () =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux);

  /// For tests and screenshots: another system's glass.
  static NativeStyle? styleOverride;

  /// Which system's glass the desktop's second look is.
  NativeStyle get nativeStyle => styleOverride ?? NativeStyle.current;

  /// The system's accent colour, read by the desktop app; null until it has been.
  Color? systemAccentColor;

  /// The accent the system's glass is in.
  Color get nativeAccent => systemAccentColor ?? nativeStyle.defaultAccent;

  /// Whether the system's own material is behind the window now (Mica, the vibrancy, the
  /// compositor's blur), so the page lets it through. Set by lib/desktop/backdrop.dart.
  bool nativeBackdrop = false;

  /// For tests and screenshots: the clock the time-based mode reads.
  DateTime Function() clock = DateTime.now;

  void init() {
    _schedule();
    if (!_watching) {
      _watching = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  String get colorThemeId {
    final v = Store.I.get(_keyColor);
    return colorThemes.any((t) => t.id == v) ? v! : 'classic';
  }

  ColorTheme get colorTheme => colorThemes.firstWhere((t) => t.id == colorThemeId);

  /// What the person chose, which can be "time".
  String get modePreference {
    final v = Store.I.get(_keyMode);
    return modePreferences.contains(v) ? v! : 'light';
  }

  /// What the app is in right now: only ever light or dark.
  String get mode => resolveMode(modePreference, clock());
  Brightness get brightness => mode == 'dark' ? Brightness.dark : Brightness.light;

  /// The second look on this platform: the system's glass on the desktop, else Material You.
  String get secondLook => isDesktop() ? lookNative : lookMaterial;

  String get look {
    final v = Store.I.get(keyLook);
    if (v == lookUwuApps) return v!;
    if (v == lookMaterial || v == lookNative) return secondLook;
    return isAndroid() && hasDynamic ? lookMaterial : lookUwuApps;
  }

  bool get isMaterial => look == lookMaterial;
  bool get isNative => look == lookNative;

  void setColorTheme(String id) {
    if (!colorThemes.any((t) => t.id == id)) return;
    Store.I.put(_keyColor, id);
    notifyListeners();
  }

  void setMode(String preference) {
    Store.I.put(_keyMode, modePreferences.contains(preference) ? preference : 'light');
    _schedule();
    notifyListeners();
  }

  void setLook(String look) {
    Store.I.put(keyLook, look == lookMaterial || look == lookNative ? secondLook : lookUwuApps);
    notifyListeners();
  }

  void setSystemAccentColor(Color? colour) {
    if (systemAccentColor == colour) return;
    systemAccentColor = colour;
    notifyListeners();
  }

  void setNativeBackdrop(bool on) {
    if (nativeBackdrop == on) return;
    nativeBackdrop = on;
    notifyListeners();
  }

  void setSystemAccent(bool on) {
    systemAccent = on;
    notifyListeners();
  }

  void setHasDynamic(bool has) {
    if (hasDynamic == has) return;
    hasDynamic = has;
    // After this frame: it's learnt while building.
    scheduleMicrotask(notifyListeners);
  }

  /// Something else changed the stored theme (a sync, the welcome window).
  void refresh() {
    _schedule();
    notifyListeners();
  }

  // Keeping the time-based mode honest while the app stays open.
  void _schedule() {
    _timer?.cancel();
    _timer = null;
    if (modePreference != 'time') return;
    _timer = Timer(untilNextBoundary(clock()), () {
      _schedule();
      notifyListeners();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && modePreference == 'time') {
      _schedule();
      notifyListeners();
    }
  }
}

/// The colours widgets draw with, by what they're for.
@immutable
class UwuColors extends ThemeExtension<UwuColors> {
  const UwuColors({
    required this.bg,
    required this.surface,
    required this.surfaceStrong,
    required this.border,
    required this.ink,
    required this.muted,
    required this.brand,
    required this.brandInk,
    required this.brandFill,
    required this.brandFillStrong,
    required this.onBrand,
    required this.ok,
    required this.warn,
    required this.busy,
    required this.error,
    required this.errorFill,
    required this.scrim,
    required this.glass,
    this.kind = GlassKind.uwu,
    this.panelRadius = 18,
    this.controlRadius = 10,
    this.capsule = false,
    this.blur = 14,
    this.saturate = 1,
    this.rim = Colors.transparent,
    this.rimShade = Colors.transparent,
    this.glow = const [],
  });

  final Color bg;
  final Color surface;
  final Color surfaceStrong;
  final Color border;
  final Color ink;
  final Color muted;
  final Color brand;
  final Color brandInk;
  final Color brandFill;
  final Color brandFillStrong;
  final Color onBrand;
  final Color ok;
  final Color warn;
  final Color busy;
  final Color error;
  final Color errorFill;
  final Color scrim;

  /// Whether panels are glass (blurred, see-through) or solid.
  final bool glass;

  /// Which glass.
  final GlassKind kind;

  /// The corners of panels (cards, windows) and of controls (fields, buttons).
  final double panelRadius;
  final double controlRadius;

  /// Buttons as capsules, as macOS Tahoe has them.
  final bool capsule;

  /// How much the glass blurs what's behind it, and how much it brightens its colours.
  final double blur;
  final double saturate;

  /// The glass's edge where the light catches it (top left), and where it doesn't (bottom right).
  /// Transparent in the looks that draw a plain edge.
  final Color rim;
  final Color rimShade;

  /// The soft glows behind the page when the system shows nothing of its own there, for the glass
  /// to blur: none in the looks without the system's glass.
  final List<Color> glow;

  /// One of the systems' glass looks.
  bool get native => kind == GlassKind.fluent || kind == GlassKind.liquid || kind == GlassKind.frosted;

  /// A button's shape, by the look.
  OutlinedBorder buttonShape({BorderSide side = BorderSide.none}) =>
      capsule ? StadiumBorder(side: side) : RoundedRectangleBorder(borderRadius: BorderRadius.circular(controlRadius), side: side);

  static UwuColors of(BuildContext context) => Theme.of(context).extension<UwuColors>()!;

  @override
  UwuColors copyWith() => this;

  @override
  UwuColors lerp(ThemeExtension<UwuColors>? other, double t) => t < 0.5 || other is! UwuColors ? this : other;
}

Color _mix(Color a, double amount, Color b) => Color.lerp(b, a, amount)!;

const _ink = Color(0xFF121815);

/// The site's tokens, for one swatch and mode.
UwuColors uwuAppsColors(Color brand, Brightness brightness, {Color? accent}) {
  final dark = brightness == Brightness.dark;
  final base = dark ? const Color(0xFF0C100E) : const Color(0xFFEEF2F0);
  final bg = _mix(brand, 0.10, base);
  // The site's surfaces are white at an opacity over the page. Here they're laid over the page
  // colour once, so words on them keep the contrast the site measured.
  Color over(double a) => Color.alphaBlend(Colors.white.withValues(alpha: a), bg);
  final surface = over(dark ? 0.06 : 0.55);
  final surfaceStrong = over(dark ? 0.11 : 0.78);
  var brandInk = dark ? const Color(0xFFBFF5CF) : const Color(0xFF1F6B3D);
  if (accent != null) {
    final hsl = HSLColor.fromColor(accent);
    brandInk = hsl.withLightness(dark ? 0.82 : 0.28).withSaturation(hsl.saturation.clamp(0.3, 0.75)).toColor();
  }
  final tint = accent == null ? brand : HSLColor.fromColor(accent).withLightness(0.88).toColor();
  final error = dark ? const Color(0xFFFA9696) : const Color(0xFFB91C1C);
  return UwuColors(
    bg: bg,
    surface: surface,
    surfaceStrong: surfaceStrong,
    // Component edges at 3:1 or more against every surface, for all seven brand colours (WCAG
    // 1.4.11): the site's white-on-white glass edges vanish in light mode.
    border: dark ? const Color(0xFF84938A) : const Color(0xFF6F7E75),
    ink: dark ? const Color(0xFFEEF2EF) : _ink,
    muted: dark ? const Color(0xFFB4BEB8) : const Color(0xFF4A554E),
    brand: tint,
    brandInk: brandInk,
    brandFill: _mix(tint, 0.55, surfaceStrong),
    brandFillStrong: _mix(tint, 0.75, surfaceStrong),
    onBrand: _ink,
    ok: dark ? const Color(0xFF4ADE80) : const Color(0xFF0F7234),
    warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
    busy: dark ? const Color(0xFF94A3B8) : const Color(0xFF627288),
    error: error,
    errorFill: _mix(error, 0.14, bg),
    scrim: Colors.black.withValues(alpha: dark ? 0.6 : 0.35),
    glass: true,
  );
}

/// The same tokens from a Material colour scheme.
UwuColors materialColors(ColorScheme s) {
  final dark = s.brightness == Brightness.dark;
  return UwuColors(
    bg: s.surface,
    surface: s.surfaceContainerLow,
    surfaceStrong: s.surfaceContainerHigh,
    // outline, not outlineVariant: Material's outline is the one made for 3:1 edges (WCAG 1.4.11).
    border: s.outline,
    ink: s.onSurface,
    muted: s.onSurfaceVariant,
    brand: s.primaryContainer,
    brandInk: s.primary,
    brandFill: s.primaryContainer,
    brandFillStrong: _mix(s.primary, 0.18, s.primaryContainer),
    onBrand: s.onPrimaryContainer,
    ok: dark ? const Color(0xFF7DDC9A) : const Color(0xFF0F7234),
    warn: dark ? const Color(0xFFFBBF24) : const Color(0xFFA24B08),
    busy: s.onSurfaceVariant,
    error: s.error,
    errorFill: s.errorContainer,
    scrim: s.scrim.withValues(alpha: dark ? 0.6 : 0.4),
    glass: false,
  );
}

/// The colour [fg] moved lighter or darker, its hue kept, until it reads at [ratio]:1 on [bg].
Color readableOn(Color fg, Color bg, {double ratio = 4.5}) {
  double contrast(Color a) {
    final la = a.computeLuminance(), lb = bg.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  if (contrast(fg) >= ratio) return fg;
  final darker = bg.computeLuminance() > 0.4;
  var hsl = HSLColor.fromColor(fg);
  for (var i = 0; i < 50 && contrast(hsl.toColor()) < ratio; i++) {
    hsl = hsl.withLightness((hsl.lightness + (darker ? -0.02 : 0.02)).clamp(0.0, 1.0));
  }
  return hsl.toColor();
}

/// Black or white, whichever reads better on [bg], with [bg] nudged until it reads at 4.5:1.
(Color fill, Color ink) _fillAndInk(Color fill, {Color? prefer}) {
  const black = Color(0xFF000000), white = Color(0xFFFFFFFF);
  final ink = prefer ?? (fill.computeLuminance() > 0.22 ? black : white);
  // The fill moves, not the writing: the writing stays black or white, as each system has it.
  double contrast(Color a) {
    final la = a.computeLuminance(), lb = ink.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  var hsl = HSLColor.fromColor(fill);
  for (var i = 0; i < 50 && contrast(hsl.toColor()) < 4.5; i++) {
    hsl = hsl.withLightness((hsl.lightness + (ink == white ? -0.02 : 0.02)).clamp(0.0, 1.0));
  }
  return (hsl.toColor(), ink);
}

/// The tokens for one system's glass, in its accent. Each system's own colours where it publishes
/// them (Fluent 2's, Apple's, Deepin's and COSMIC's), with control edges kept at 3:1 and writing at
/// 4.5:1 on every surface, as the other looks have them.
UwuColors nativeColors(NativeStyle style, Brightness brightness, Color accent, {bool highContrast = false}) {
  final dark = brightness == Brightness.dark;
  final a = HSLColor.fromColor(accent);
  Color tone(double l) => a.withLightness(l).withSaturation(a.saturation.clamp(0.35, 1.0)).toColor();
  Color white(double o) => Colors.white.withValues(alpha: o);
  Color black(double o) => Colors.black.withValues(alpha: o);

  late Color base, surface, surfaceStrong, border, ink, muted, rim, rimShade;
  late double panelRadius, controlRadius, blur, saturate, glowStrength;
  var capsule = false;
  late GlassKind kind;
  Color? onFill;
  late double inkL, fillL;
  switch (style) {
    case NativeStyle.fluent:
      // Fluent 2's tokens: SolidBackgroundFillColorBase under Mica, CardBackgroundFillColorDefault,
      // ControlFillColorDefault, ControlStrongStrokeColorDefault for edges, TextFillColorPrimary
      // and Secondary; the accent's Dark 1 (light) and Light 2 (dark) for AccentFillColorDefault.
      kind = GlassKind.fluent;
      base = dark ? const Color(0xFF202020) : const Color(0xFFF3F3F3);
      surface = dark ? white(0.05) : white(0.70);
      surfaceStrong = dark ? white(0.085) : white(0.88);
      border = dark ? const Color(0xFF9A9A9A) : const Color(0xFF8A8A8A);
      ink = dark ? const Color(0xFFFFFFFF) : const Color(0xFF1B1B1B);
      muted = dark ? const Color(0xFFCFCFCF) : const Color(0xFF5D5D5D);
      rim = dark ? white(0.09) : black(0.05);
      rimShade = dark ? black(0.30) : black(0.11);
      panelRadius = 8;
      controlRadius = 4;
      blur = 30;
      saturate = 1.25;
      glowStrength = dark ? 0.16 : 0.20;
      inkL = dark ? 0.76 : 0.36;
      fillL = dark ? 0.76 : 0.38;
      onFill = dark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
    case NativeStyle.tahoe:
      // Apple's: systemGroupedBackground, label and secondaryLabel, systemGray for edges; Liquid
      // Glass's bright rim; white on the accent in both modes.
      kind = GlassKind.liquid;
      base = dark ? const Color(0xFF1C1C1E) : const Color(0xFFF2F2F7);
      surface = dark ? white(0.08) : white(0.52);
      surfaceStrong = dark ? white(0.14) : white(0.78);
      border = dark ? const Color(0xFF8E8E93) : const Color(0xFF86868B);
      ink = dark ? const Color(0xFFF5F5F7) : const Color(0xFF1D1D1F);
      muted = dark ? const Color(0xFFA1A1A6) : const Color(0xFF6E6E73);
      rim = dark ? white(0.30) : white(0.95);
      rimShade = dark ? white(0.12) : black(0.07);
      panelRadius = 22;
      controlRadius = 12;
      capsule = true;
      blur = 24;
      saturate = 1.8;
      glowStrength = dark ? 0.24 : 0.42;
      inkL = dark ? 0.66 : 0.42;
      fillL = 0.46;
      onFill = const Color(0xFFFFFFFF);
    case NativeStyle.frosted:
      // Deepin's and COSMIC's: a cool grey under frosted panels with a bright top edge, round
      // corners (COSMIC's "round"), and the accent as Deepin's default blue.
      kind = GlassKind.frosted;
      base = dark ? const Color(0xFF18191C) : const Color(0xFFEEF1F5);
      surface = dark ? white(0.06) : white(0.58);
      surfaceStrong = dark ? white(0.11) : white(0.82);
      border = dark ? const Color(0xFF8B9099) : const Color(0xFF7D838C);
      ink = dark ? const Color(0xFFECEFF3) : const Color(0xFF1E2126);
      muted = dark ? const Color(0xFFAEB3BA) : const Color(0xFF565B63);
      rim = dark ? white(0.16) : white(0.85);
      rimShade = dark ? black(0.35) : black(0.09);
      panelRadius = 16;
      controlRadius = 10;
      blur = 20;
      saturate = 1.3;
      glowStrength = dark ? 0.24 : 0.30;
      inkL = dark ? 0.70 : 0.40;
      fillL = dark ? 0.68 : 0.45;
  }

  final bg = _mix(accent, dark ? 0.03 : 0.025, base);
  // Words on the glass are measured on the glass over the page, its most see-through.
  final onGlass = Color.alphaBlend(surface, bg);
  final onStrong = Color.alphaBlend(surfaceStrong, bg);
  Color reads(Color c) => readableOn(readableOn(readableOn(c, bg), onGlass), onStrong);
  final brandInk = reads(tone(inkL));
  final (brandFill, onBrand) = _fillAndInk(tone(fillL), prefer: onFill);
  final error = reads(dark ? const Color(0xFFFF99A4) : const Color(0xFFC42B1C));
  final hue = a.hue;
  return UwuColors(
    bg: bg,
    surface: surface,
    surfaceStrong: surfaceStrong,
    border: highContrast ? ink : border,
    ink: ink,
    muted: reads(muted),
    brand: accent,
    brandInk: brandInk,
    brandFill: brandFill,
    brandFillStrong: _mix(dark ? Colors.white : Colors.black, 0.12, brandFill),
    onBrand: onBrand,
    ok: reads(dark ? const Color(0xFF6CCB5F) : const Color(0xFF0F7B0F)),
    warn: reads(dark ? const Color(0xFFFCE100) : const Color(0xFF9D5D00)),
    busy: reads(muted),
    error: error,
    errorFill: _mix(error, 0.14, bg),
    scrim: Colors.black.withValues(alpha: dark ? 0.45 : 0.18),
    glass: true,
    kind: kind,
    panelRadius: panelRadius,
    controlRadius: controlRadius,
    capsule: capsule,
    blur: blur,
    saturate: saturate,
    rim: highContrast ? ink : rim,
    rimShade: highContrast ? ink : rimShade,
    glow: [
      tone(dark ? 0.45 : 0.62).withValues(alpha: glowStrength),
      HSLColor.fromAHSL(1, (hue + 50) % 360, 0.75, dark ? 0.45 : 0.68).toColor().withValues(alpha: glowStrength * 0.85),
      HSLColor.fromAHSL(1, (hue + 320) % 360, 0.70, dark ? 0.42 : 0.70).toColor().withValues(alpha: glowStrength * 0.7),
    ],
  );
}

/// The family, and the ones after it, that each system's glass writes in: Segoe UI Variable on
/// Windows; the system's own on macOS (San Francisco); Deepin's and COSMIC's on Linux.
(String?, List<String>?) nativeFont(NativeStyle style) => switch (style) {
  NativeStyle.fluent => ('Segoe UI Variable Text', const ['Segoe UI Variable', 'Segoe UI']),
  NativeStyle.tahoe => (null, null),
  NativeStyle.frosted => ('Noto Sans', const ['Open Sans', 'Cantarell', 'Ubuntu', 'DejaVu Sans']),
};

/// The whole theme. `dynamicScheme` is the device's palette (Material You), or the desktop's
/// accent as a scheme, when there is one. The system's glass (`lookNative`) is drawn as
/// `nativeStyle` has it, in `accent`.
ThemeData buildTheme({
  required String look,
  required Brightness brightness,
  required Color brand,
  ColorScheme? dynamicScheme,
  bool systemAccent = false,
  bool highContrast = false,
  bool desktop = false,
  NativeStyle nativeStyle = NativeStyle.fluent,
  Color? accent,
}) {
  final material = look == lookMaterial;
  final native = look == lookNative;
  late final ColorScheme scheme;
  late final UwuColors colors;
  if (native) {
    colors = nativeColors(nativeStyle, brightness, accent ?? nativeStyle.defaultAccent, highContrast: highContrast);
    scheme = ColorScheme.fromSeed(seedColor: colors.brand, brightness: brightness, contrastLevel: highContrast ? 1.0 : 0.0).copyWith(
      primary: colors.brandInk,
      onPrimary: colors.bg,
      primaryContainer: colors.brandFill,
      onPrimaryContainer: colors.onBrand,
      secondaryContainer: colors.brandFill,
      onSecondaryContainer: colors.onBrand,
      surface: colors.bg,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      surfaceTint: Colors.transparent,
      outline: colors.muted,
      outlineVariant: colors.border,
      error: colors.error,
      onError: colors.bg,
      errorContainer: colors.errorFill,
      onErrorContainer: colors.error,
    );
  } else if (material) {
    scheme = (dynamicScheme ?? ColorScheme.fromSeed(seedColor: const Color(0xFF22A85A), brightness: brightness, contrastLevel: highContrast ? 1.0 : 0.0))
        .copyWith(brightness: brightness);
    colors = materialColors(scheme);
  } else {
    colors = uwuAppsColors(brand, brightness, accent: systemAccent ? dynamicScheme?.primary : null);
    scheme = ColorScheme.fromSeed(seedColor: colors.brandInk, brightness: brightness).copyWith(
      primary: colors.brandInk,
      onPrimary: colors.bg,
      primaryContainer: colors.brandFill,
      onPrimaryContainer: colors.onBrand,
      secondaryContainer: colors.brandFill,
      onSecondaryContainer: colors.onBrand,
      surface: colors.bg,
      onSurface: colors.ink,
      onSurfaceVariant: colors.muted,
      surfaceContainerLowest: colors.bg,
      surfaceContainerLow: colors.surface,
      surfaceContainer: colors.surface,
      surfaceContainerHigh: colors.surfaceStrong,
      surfaceContainerHighest: colors.surfaceStrong,
      outline: colors.muted,
      outlineVariant: colors.border,
      error: colors.error,
      onError: colors.bg,
      errorContainer: colors.errorFill,
      onErrorContainer: colors.error,
    );
  }

  final radius = BorderRadius.circular(native ? colors.controlRadius : (material ? 14 : 10));
  // The writing: the device's own in Material You, Jua in the UwU Apps look, the system's in its
  // glass. `family` is null where the theme's own default is meant.
  final (nativeFamily, fallback) = native ? nativeFont(nativeStyle) : (null, null);
  final family = native ? nativeFamily : (material ? null : 'Jua');
  // Plain filled and outlined buttons: Material's own in Material You.
  final themed = !material;
  final buttonShape = native ? colors.buttonShape() : RoundedRectangleBorder(borderRadius: radius);
  final buttonWeight = switch (nativeStyle) {
    _ when !native => material ? FontWeight.w600 : FontWeight.w400,
    NativeStyle.tahoe => FontWeight.w600,
    NativeStyle.frosted => FontWeight.w500,
    NativeStyle.fluent => FontWeight.w400,
  };
  final dialogRadius = native ? colors.panelRadius + (nativeStyle == NativeStyle.tahoe ? 4 : 0) : (material ? 28.0 : 18.0);
  // The pointing hand over anything that can be pressed, as on the website. Flutter shows it only
  // on the web by itself (WidgetStateMouseCursor.adaptiveClickable); disabled controls keep the arrow.
  const hand = WidgetStateMouseCursor.clickable;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: family,
    fontFamilyFallback: fallback,
    // The system's glass lets the page's backdrop through (NativeBackdrop, lib/widgets/common.dart).
    scaffoldBackgroundColor: native ? Colors.transparent : colors.bg,
    // A computer's rows and buttons are closer set than a phone's.
    visualDensity: desktop ? VisualDensity.compact : VisualDensity.standard,
    extensions: [colors],
  );
  return base.copyWith(
    textTheme: base.textTheme.apply(bodyColor: colors.ink, displayColor: colors.ink),
    iconTheme: IconThemeData(color: colors.ink, size: 20),
    dividerTheme: DividerThemeData(color: colors.border, space: 1, thickness: 1),
    tooltipTheme: TooltipThemeData(
      waitDuration: const Duration(milliseconds: 400),
      // Fluent's and Tahoe's tooltips are the glass's own colours, not the writing's turned over.
      decoration: native
          ? BoxDecoration(
              color: Color.alphaBlend(colors.surfaceStrong, colors.bg),
              borderRadius: BorderRadius.circular(colors.capsule ? 8 : colors.controlRadius),
              border: Border.all(color: colors.rimShade),
              boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.14), blurRadius: 12, offset: const Offset(0, 4))],
            )
          : BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: native ? colors.ink : colors.bg, fontSize: 12, fontFamily: family),
    ),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: colors.surfaceStrong,
      contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: desktop ? 10 : 13),
      hintStyle: TextStyle(color: colors.muted),
      border: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.border),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.border),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: radius,
        borderSide: BorderSide(color: colors.brandInk, width: 2),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: themed ? colors.brandFill : null,
        foregroundColor: themed ? colors.onBrand : null,
        // The systems' accent buttons have no drawn edge: the fill is the edge.
        shape: native
            ? buttonShape
            : RoundedRectangleBorder(
                borderRadius: radius,
                side: material ? BorderSide.none : BorderSide(color: colors.border),
              ),
        elevation: 0,
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: desktop ? 12 : 14),
        textStyle: TextStyle(fontFamily: family, fontSize: 14, fontWeight: buttonWeight),
      ).copyWith(mouseCursor: hand),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        backgroundColor: themed ? colors.surfaceStrong : null,
        // The systems' plain buttons: a glass fill with a fine edge (their names say what they are).
        side: BorderSide(color: native ? colors.rimShade : colors.border),
        shape: native ? buttonShape : RoundedRectangleBorder(borderRadius: radius),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: desktop ? 10 : 12),
        textStyle: TextStyle(fontFamily: family, fontSize: 13, fontWeight: native && nativeStyle == NativeStyle.tahoe ? FontWeight.w500 : null),
      ).copyWith(mouseCursor: hand),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.brandInk,
        shape: native ? buttonShape : null,
        textStyle: TextStyle(fontFamily: family, fontSize: 13, fontWeight: native && nativeStyle == NativeStyle.tahoe ? FontWeight.w500 : null),
      ).copyWith(mouseCursor: hand),
    ),
    elevatedButtonTheme: const ElevatedButtonThemeData(style: ButtonStyle(mouseCursor: hand)),
    iconButtonTheme: const IconButtonThemeData(style: ButtonStyle(mouseCursor: hand)),
    segmentedButtonTheme: const SegmentedButtonThemeData(style: ButtonStyle(mouseCursor: hand)),
    menuButtonTheme: const MenuButtonThemeData(style: ButtonStyle(mouseCursor: hand)),
    listTileTheme: const ListTileThemeData(mouseCursor: hand),
    sliderTheme: const SliderThemeData(mouseCursor: hand),
    popupMenuTheme: const PopupMenuThemeData(mouseCursor: hand),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.brandInk : null),
      checkColor: WidgetStatePropertyAll(colors.bg),
      side: BorderSide(color: native ? colors.border : colors.muted, width: native ? 1 : 1.5),
      shape: native ? RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)) : null,
      mouseCursor: hand,
    ),
    switchTheme: material
        ? const SwitchThemeData(mouseCursor: hand)
        : native
        // Fluent's toggle and Tahoe's and COSMIC's switches: the accent when on with a white
        // knob; when off, an outlined track (Fluent) or a grey one (the others).
        ? SwitchThemeData(
            mouseCursor: hand,
            trackColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected)
                  ? colors.brandFill
                  : (nativeStyle == NativeStyle.fluent ? Colors.transparent : (brightness == Brightness.dark ? const Color(0xFF48484D) : const Color(0xFFD5D5DA))),
            ),
            thumbColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? colors.onBrand : (nativeStyle == NativeStyle.fluent ? colors.muted : Colors.white),
            ),
            trackOutlineColor: WidgetStateProperty.resolveWith(
              (s) => s.contains(WidgetState.selected) ? Colors.transparent : (nativeStyle == NativeStyle.fluent ? colors.border : colors.border.withValues(alpha: 0.6)),
            ),
            thumbIcon: const WidgetStatePropertyAll(null),
          )
        : SwitchThemeData(
            mouseCursor: hand,
            trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.brandInk : colors.surfaceStrong),
            thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.bg : colors.muted),
            trackOutlineColor: WidgetStatePropertyAll(colors.border),
          ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.bg, fontFamily: family, fontSize: 14),
      shape: native && colors.capsule ? const StadiumBorder() : RoundedRectangleBorder(borderRadius: BorderRadius.circular(native ? colors.panelRadius : 12)),
    ),
    dialogTheme: DialogThemeData(
      // The systems' glass: see-through, over a blur of the page (showDesktopSheet).
      backgroundColor: native
          ? Color.alphaBlend(colors.surfaceStrong, colors.bg).withValues(alpha: nativeStyle == NativeStyle.fluent ? 0.84 : 0.74)
          : (colors.glass ? Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg) : scheme.surfaceContainerHigh),
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(dialogRadius),
        side: BorderSide(color: native ? colors.rimShade : colors.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.glass ? Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg) : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(material ? 28 : 18))),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.muted.withValues(alpha: 0.5)),
      thickness: WidgetStatePropertyAll(native ? 6 : 8),
      radius: const Radius.circular(4),
    ),
  );
}
