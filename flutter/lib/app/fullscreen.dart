// Fullscreen (F, or the side tray's button): on Android the navigation bar hides as well as the
// status bar (the app's own immersive mode, as the old app did it); on the desktop the window goes
// full screen and the title bar hides; in a browser, the page asks for it.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'env.dart';
import 'fullscreen_stub.dart' if (dart.library.js_interop) 'fullscreen_web.dart';

class Fullscreen {
  Fullscreen._();

  static final ValueNotifier<bool> on = ValueNotifier(false);

  /// Set by the desktop layer: the window, full screen or not.
  static Future<void> Function(bool on)? desktop;

  static Future<void> toggle() => set(!on.value);

  static Future<void> set(bool value) async {
    on.value = value;
    if (Env.desktop && desktop != null) {
      await desktop!(value);
    } else if (kIsWeb) {
      browserFullscreen(value);
    } else if (Env.android) {
      await applySystemBars();
    }
  }

  /// Android: the status bar always hidden (a swipe shows it for a moment), and in fullscreen the
  /// navigation bar with it.
  static Future<void> applySystemBars() async {
    if (!Env.android) return;
    await SystemChrome.setEnabledSystemUIMode(
      on.value ? SystemUiMode.immersiveSticky : SystemUiMode.manual,
      overlays: on.value ? const [] : const [SystemUiOverlay.bottom],
    );
  }
}
