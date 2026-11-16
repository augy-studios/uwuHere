// Where the app is running, asked in one place.
import 'package:flutter/foundation.dart';

class Env {
  Env._();

  /// For tests and screenshots: draw as the desktop apps do (or don't), whatever the machine.
  static bool? desktopOverride;

  /// The Windows, macOS and Linux apps: mouse and keyboard, dialogs and drawers.
  static bool get desktop {
    final override = desktopOverride;
    if (override != null) return override;
    return !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.windows || defaultTargetPlatform == TargetPlatform.macOS || defaultTargetPlatform == TargetPlatform.linux);
  }

  /// For the Playwright suite's browser build: draw as the Android app does.
  static bool? androidOverride;

  static bool get android {
    final override = androidOverride;
    if (override != null) return override;
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
  }

  static bool get macOS {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;
  }

  static bool get windows {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.windows;
  }

  static bool get linux {
    return !kIsWeb && defaultTargetPlatform == TargetPlatform.linux;
  }

  /// The app's version, as pubspec.yaml has it. Set as the app opens.
  static String version = '';

  /// The site's phone width: below it the sidebar slides over the page.
  static const phoneWidth = 720.0;

  /// From here up the desktop shows the boards beside the open one.
  static const splitWidth = 1024.0;
}
