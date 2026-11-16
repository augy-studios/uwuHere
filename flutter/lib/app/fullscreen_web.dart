// The browser build's fullscreen (the Playwright suite's), through the page's Fullscreen API.
import 'dart:js_interop';

import 'package:web/web.dart' as web;

void browserFullscreen(bool on) {
  try {
    if (on) {
      final documentElement = web.document.documentElement;
      if (documentElement != null) {
        documentElement.requestFullscreen().toDart.catchError((Object error) {
          return null;
        });
      }
    } else if (web.document.fullscreenElement != null) {
      web.document.exitFullscreen().toDart.catchError((Object error) {
        return null;
      });
    }
  } catch (_) {
    // Refused, or not here: nothing else changes.
  }
}
