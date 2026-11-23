// The app's three pages, as the site's three documents (index.html, host.html, join.html): home,
// an event's host page, and an event's check-in page. Each is kept (an IndexedStack), so switching
// back keeps its place, and a host page keeps taking check-ins while you look at home. Tours and
// bug reports read which is on show; links and the desktop's title bar switch between them.
import 'dart:async';

import 'package:flutter/foundation.dart';

class AppPages {
  AppPages._();

  static const home = 'home';
  static const host = 'host';
  static const join = 'join';
  static const all = [home, host, join];

  static final ValueNotifier<String> current = ValueNotifier(home);

  /// The event the host page shows, and the one the check-in page shows (null for none).
  static final ValueNotifier<String?> hostCode = ValueNotifier(null);
  static final ValueNotifier<String?> joinCode = ValueNotifier(null);

  /// Counts every opening of the check-in page by a link, the same event's included.
  static final ValueNotifier<int> joinOpened = ValueNotifier(0);

  /// A tap token, from a link a host's phone handed over, for the check-in page to use once.
  static String? joinTap;

  /// Where to scroll the home page to (#join or #host, from a widget or a shortcut).
  static final ValueNotifier<String?> homeFocus = ValueNotifier(null);

  static final StreamController<String> _changes = StreamController.broadcast();

  /// A page switch, after it's happened (the site's `pagechange`).
  static Stream<String> get changes {
    return _changes.stream;
  }

  /// The id of the page on show.
  static String active() {
    return current.value;
  }

  static void open(String id) {
    if (!all.contains(id)) return;
    if (current.value == id) {
      _changes.add(id);
      return;
    }
    current.value = id;
    _changes.add(id);
  }

  /// The host page for this event.
  static void openHost(String code) {
    hostCode.value = code;
    open(host);
  }

  /// The check-in page for this event (or the code box, for null).
  static void openJoin(String? code, {String? tap}) {
    joinTap = tap;
    joinCode.value = code;
    // The same event again still counts: the page takes the tap, if there's one.
    joinOpened.value = joinOpened.value + 1;
    open(join);
  }

  /// Something on the page changed that a tour might want (a window opened or closed).
  static void poke() {
    _changes.add(current.value);
  }

  /// Each page's reload (the host page's list, the check-in page's event), for the desktop's
  /// Reload, F5 and the taskbar's Refresh.
  static final Map<String, Future<void> Function()> refreshers = {};
}

/// Reloads the page on show, if it has anything to reload.
Future<void> refreshPage() async {
  final refresher = AppPages.refreshers[AppPages.active()];
  if (refresher != null) await refresher();
}

/// Set by the desktop layer: an event's right-click menu (Open in Split Pane, Pin to Desktop
/// Widget, Set as Tray Glance, Copy Link). Null on a phone.
void Function(dynamic context, dynamic position, String code, String name)? desktopEventMenu;
