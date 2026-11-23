// The runner's own channel (docs/flutter-desktop-app-spec.md §2.7), for what no package does:
//   Windows  the Jump List (the events this computer hosts) and the taskbar's thumbnail buttons
//            (previous event, refresh, next event) (windows/runner/flutter_window.cpp)
//   macOS    the Dock menu and badge (macos/Runner/AppDelegate.swift)
//   all      the system's own material behind the window, for the system's glass look
//            (Mica on Windows 11, the vibrancy on macOS, the compositor's blur on Linux)
// Events back: 'thumb' with 'toggle' (refresh), 'previous' or 'next', 'dock' with an event code, 'open' with a
// link and 'activate' (macOS). Where the runner doesn't answer a call (Linux has only
// setBackdrop), it's quietly nothing.
import 'package:flutter/services.dart';

class Runner {
  Runner._();

  static const _channel = MethodChannel('org.uwuapps.here/desktop');

  /// Set by desktop_main.dart: a taskbar thumbnail button was clicked ('toggle', 'previous' or
  /// 'next').
  static void Function(String id)? onThumbnailButton;

  /// Set by desktop_main.dart: an event was picked from the Dock menu.
  static void Function(String code)? onDock;

  /// A link opened from elsewhere (macOS), or a click on the Dock icon (`null`).
  static void Function(String? link)? onOpen;

  /// Answers the runner's events by passing each to its handler above, where one is set.
  static void listen() {
    _channel.setMethodCallHandler((call) async {
      final callArguments = call.arguments;
      switch (call.method) {
        case 'thumb':
          final thumbnailHandler = onThumbnailButton;
          if (thumbnailHandler != null) thumbnailHandler('$callArguments');
        case 'dock':
          final dockHandler = onDock;
          if (dockHandler != null) dockHandler('$callArguments');
        case 'open':
          final openHandler = onOpen;
          if (openHandler != null) {
            String? link;
            if (callArguments is String) link = callArguments;
            openHandler(link);
          }
        case 'activate':
          final openHandler = onOpen;
          if (openHandler != null) openHandler(null);
      }
      return null;
    });
  }

  static Future<void> _call(String method, [Object? arguments]) async {
    try {
      await _channel.invokeMethod(method, arguments);
    } catch (_) {
      // Not on this system.
    }
  }

  /// Your events, [{ code, name }], for the Jump List, thumbnail buttons and Dock menu.
  static Future<void> setFavourites(List<Map<String, Object?>> favourites) {
    return _call('setFavourites', {
      'items': [
        for (final favourite in favourites) {'id': '${favourite['code']}', 'name': '${favourite['name']}', 'link': 'uwu://here/host?id=${favourite['code']}'},
      ],
    });
  }

  /// The Dock's badge (macOS): a few characters, or '' for none.
  static Future<void> setBadge(String text) {
    return _call('setBadge', text);
  }

  /// The system's own material behind the window (lib/desktop/backdrop.dart): 'mica' or 'acrylic'
  /// (Windows 11), 'vibrancy' (macOS), 'blur' (Linux, where the compositor blurs), or 'none'.
  /// Whether the system shows it now: false where it can't, and on a runner without it.
  static Future<bool> setBackdrop(String kind, {required bool dark}) async {
    try {
      final shown = await _channel.invokeMethod<bool>('setBackdrop', {'kind': kind, 'dark': dark});
      if (shown == null) return false;
      return shown;
    } catch (_) {
      return false;
    }
  }
}
