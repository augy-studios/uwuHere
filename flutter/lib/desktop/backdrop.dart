// The system's own material behind the window, for the desktop's second look, the system's glass
// (lib/theme/theme.dart): what makes the page see-through to the desktop, as the systems' own
// apps are.
//
//   Windows 11   Mica (DWMWA_SYSTEMBACKDROP_TYPE, from 22H2): the wallpaper's colours, blurred
//                and quiet, under the whole window. Windows 10 has none: the glows stand in.
//   macOS        the window's vibrancy (NSVisualEffectView, behind the window).
//   Linux        the compositor's blur behind the window, where it offers one (KWin's, which
//                Deepin's deepin-kwin is, on X11). COSMIC's and Wayland's have no way to ask yet:
//                the glows stand in.
//
// Asked again whenever the look or the mode changes; the runner says whether the system shows it
// (ThemeController.nativeBackdrop), and the page lets it through only then. Off in the other
// looks, whose pages are solid.
import 'package:flutter/material.dart';

import '../theme/theme.dart';
import 'runner.dart';

class Backdrop {
  Backdrop._();

  static String? _asked;

  static void start() {
    ThemeController.I.addListener(_apply);
    _apply();
  }

  static String _kind(ThemeController t) {
    if (!t.isNative) return 'none';
    return switch (t.nativeStyle) {
      NativeStyle.fluent => 'mica',
      NativeStyle.tahoe => 'vibrancy',
      NativeStyle.frosted => 'blur',
    };
  }

  static Future<void> _apply() async {
    final t = ThemeController.I;
    final kind = _kind(t);
    final dark = t.brightness == Brightness.dark;
    final ask = '$kind:$dark';
    if (ask == _asked) return;
    _asked = ask;
    final shown = await Runner.setBackdrop(kind, dark: dark);
    // A later change has asked since: its answer stands.
    if (_asked != ask) return;
    t.setNativeBackdrop(kind != 'none' && shown);
  }
}
