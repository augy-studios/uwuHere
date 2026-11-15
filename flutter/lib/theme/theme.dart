// The theme, built in one place for both looks and both modes.
//
//   The UwU Apps look   the site's own (main-site/css/theme.css and js/theme.js): seven brand
//                       swatches, the Jua font, flat tinted pages and glass panels.
//   Material You        the device's palette and fonts. On by default on Android 12+, where the
//                       system has a palette to give; the desktop apps default to the UwU Apps
//                       look and can borrow the system's accent colour instead.
//
// Mode is the site's: light, dark, or time-based (light from 09:00 to 18:00), kept under the
// site's keys so a theme brought over from the old app means the same here. Colours reach widgets as
// tokens (UwuColors), never as literals.
import 'dart:async';

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

/// The app's own key: which look, 'material' or 'uwuapps'. Unset follows the platform.
const keyLook = 'app.look';
const lookMaterial = 'material';
const lookUwuApps = 'uwuapps';

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

  String get look {
    final v = Store.I.get(keyLook);
    if (v == lookMaterial || v == lookUwuApps) return v!;
    return isAndroid() && hasDynamic ? lookMaterial : lookUwuApps;
  }

  bool get isMaterial => look == lookMaterial;

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
    Store.I.put(keyLook, look == lookMaterial ? lookMaterial : lookUwuApps);
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

/// The whole theme. `dynamicScheme` is the device's palette (Material You), or the desktop's
/// accent as a scheme, when there is one.
ThemeData buildTheme({
  required String look,
  required Brightness brightness,
  required Color brand,
  ColorScheme? dynamicScheme,
  bool systemAccent = false,
  bool highContrast = false,
  bool desktop = false,
}) {
  final material = look == lookMaterial;
  late final ColorScheme scheme;
  late final UwuColors colors;
  if (material) {
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

  final radius = BorderRadius.circular(material ? 14 : 10);
  // The pointing hand over anything that can be pressed, as on the website. Flutter shows it only
  // on the web by itself (WidgetStateMouseCursor.adaptiveClickable); disabled controls keep the arrow.
  const hand = WidgetStateMouseCursor.clickable;
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: material ? null : 'Jua',
    scaffoldBackgroundColor: colors.bg,
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
      decoration: BoxDecoration(color: colors.ink, borderRadius: BorderRadius.circular(8)),
      textStyle: TextStyle(color: colors.bg, fontSize: 12, fontFamily: material ? null : 'Jua'),
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
        backgroundColor: material ? null : colors.brandFill,
        foregroundColor: material ? null : colors.onBrand,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: material ? BorderSide.none : BorderSide(color: colors.border),
        ),
        padding: EdgeInsets.symmetric(horizontal: 18, vertical: desktop ? 12 : 14),
        textStyle: TextStyle(fontFamily: material ? null : 'Jua', fontSize: 14, fontWeight: material ? FontWeight.w600 : FontWeight.w400),
      ).copyWith(mouseCursor: hand),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: colors.ink,
        backgroundColor: material ? null : colors.surfaceStrong,
        side: BorderSide(color: colors.border),
        shape: RoundedRectangleBorder(borderRadius: radius),
        padding: EdgeInsets.symmetric(horizontal: 14, vertical: desktop ? 10 : 12),
        textStyle: TextStyle(fontFamily: material ? null : 'Jua', fontSize: 13),
      ).copyWith(mouseCursor: hand),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: colors.brandInk,
        textStyle: TextStyle(fontFamily: material ? null : 'Jua', fontSize: 13),
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
      side: BorderSide(color: colors.muted, width: 1.5),
      mouseCursor: hand,
    ),
    switchTheme: material
        ? const SwitchThemeData(mouseCursor: hand)
        : SwitchThemeData(
            mouseCursor: hand,
            trackColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.brandInk : colors.surfaceStrong),
            thumbColor: WidgetStateProperty.resolveWith((s) => s.contains(WidgetState.selected) ? colors.bg : colors.muted),
            trackOutlineColor: WidgetStatePropertyAll(colors.border),
          ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: colors.ink,
      contentTextStyle: TextStyle(color: colors.bg, fontFamily: material ? null : 'Jua', fontSize: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: colors.glass ? Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg) : scheme.surfaceContainerHigh,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(material ? 28 : 18),
        side: BorderSide(color: colors.border),
      ),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: colors.glass ? Color.alphaBlend(colors.surfaceStrong.withValues(alpha: 0.9), colors.bg) : scheme.surfaceContainerLow,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(material ? 28 : 18))),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thumbColor: WidgetStatePropertyAll(colors.muted.withValues(alpha: 0.5)),
      thickness: const WidgetStatePropertyAll(8),
      radius: const Radius.circular(4),
    ),
  );
}
