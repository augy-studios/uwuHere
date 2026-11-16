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
import 'desk.dart';
import 'runner.dart';

class Backdrop {
  Backdrop._();

  /// The last request sent to the runner ('kind:dark'), so the same one isn't sent twice.
  static String? _asked;

  static void start() {
    ThemeController.I.addListener(_apply);
    // window_manager's setTitleBarStyle (as the window first opens, after the splash) and full
    // screen put the window's frame back to its own, which takes Mica's area away: the pane stayed
    // black until the look was changed. So it's asked for again after each.
    Desktop.onShown.add(_applyAgain);
    Desktop.fullScreen.addListener(_applyAgain);
    _apply();
  }

  static void _applyAgain() {
    _asked = null;
    _apply();
  }

  /// The material the current look asks for: 'mica', 'vibrancy', 'blur', or 'none'.
  static String _kindFor(ThemeController theme) {
    if (!theme.isNative) return 'none';
    switch (theme.nativeStyle) {
      case NativeStyle.fluent:
        return 'mica';
      case NativeStyle.tahoe:
        return 'vibrancy';
      case NativeStyle.frosted:
        return 'blur';
    }
  }

  static Future<void> _apply() async {
    final theme = ThemeController.I;
    final kind = _kindFor(theme);
    final isDark = theme.brightness == Brightness.dark;
    final request = '$kind:$isDark';
    if (request == _asked) return;
    _asked = request;
    final shown = await Runner.setBackdrop(kind, dark: isDark);
    // A later change has asked since: its answer stands.
    if (_asked != request) return;
    theme.setNativeBackdrop(kind != 'none' && shown);
  }
}
