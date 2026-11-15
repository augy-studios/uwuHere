// At a glance, outside the window (docs/desktop-features-spec.md §9). The spec's "live item" is an
// event this computer hosts: how many are here, and who came last.
//
// - The tray glance: switched on from an event's right-click menu, its page or the tray, the
//   event followed outside the window: its name, how many are here and who checked in last, in
//   the tray icon's tooltip (Windows, Linux), and the count beside the menu bar icon and on the
//   Dock's badge (macOS), fetched every 30 seconds.
// - Favourites: your events (up to 10, open ones first) as the Windows Jump List, the taskbar's
//   thumbnail buttons (previous event, refresh, next event) and the macOS Dock menu, through the
//   runner's channel (runner.dart).
//
// Keys: trayStop ({ code, name }: the event followed, or null), favourites.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api.dart';
import '../data/format.dart';
import '../data/here_store.dart';
import 'desk.dart';
import 'runner.dart';
import 'settings.dart';

/// The tray tooltip: the event's name, then how many are here and who came last, cut to 127
/// characters (Windows' most) with an ellipsis.
String trayText({required String name, required int count, required int left, String? latestName, String? latestAt, bool paused = false, bool ended = false}) {
  final lines = [
    name,
    ended ? 'Ended: $count checked in' : '$count here${left > 0 ? ', $left left early' : ''}${paused ? ' (paused)' : ''}',
    if (latestName != null && !ended) 'Last: $latestName at ${formatTime(latestAt)}',
  ];
  final text = lines.join('\n');
  return text.length <= 127 ? text : '${text.substring(0, 126)}…';
}

class Glance {
  Glance._();

  static Timer? _tick;

  /// Set by tray.dart: puts a new tooltip and title up.
  static void Function(String tooltip, String title)? onTray;
  static final ValueNotifier<Map<String, dynamic>?> followed = ValueNotifier(null);

  static void start() {
    final stop = DeskSettings.get<Map<String, dynamic>>('trayStop');
    if (stop != null) followed.value = stop;
    HereStore.changes('hosted').listen((_) => favouritesChanged());
    favouritesChanged();
    _tick?.cancel();
    _tick = Timer.periodic(const Duration(seconds: 30), (_) => refreshTray());
    refreshTray();
  }

  static String _lastFavs = '';

  /// Your events, open ones first, as the Jump List, thumbnail buttons and Dock menu.
  static List<Map<String, Object?>> favourites() {
    final hosted = HereStore.listHosted();
    final ordered = [...hosted.where((e) => !e.ended), ...hosted.where((e) => e.ended)];
    return [
      for (final e in ordered.take(10)) {'code': e.code, 'name': '${e.title.isEmpty ? 'Untitled event' : e.title} (${e.code})'},
    ];
  }

  static void favouritesChanged() {
    final favs = favourites();
    final key = favs.toString();
    if (key == _lastFavs) return;
    _lastFavs = key;
    DeskSettings.write({'favourites': favs});
    Runner.setFavourites(favs);
  }

  /// Follows an event in the tray, or stops (null).
  static void follow(String? code, [String? name]) {
    final v = code == null ? null : {'code': code, 'name': name ?? 'Event $code'};
    DeskSettings.write({'trayStop': v});
    followed.value = v;
    refreshTray();
  }

  static Future<void> refreshTray() async {
    final f = followed.value;
    if (f == null) {
      onTray?.call(Desktop.name, '');
      Runner.setBadge('');
      return;
    }
    final code = '${f['code']}';
    final key = HereStore.hostKey(code);
    final r = key == null ? null : await Api.post('host', {'code': code, 'hostKey': key, 'action': 'get'});
    if (r == null || !r.ok) {
      onTray?.call('${f['name']}: couldn\'t get the list just now', '');
      Runner.setBadge('');
      return;
    }
    final e = Map<String, dynamic>.from(r.map['event'] as Map);
    final list = (r.map['attendees'] as List?) ?? const [];
    Map? latest;
    for (final a in list) {
      if (a is Map && (latest == null || '${a['checkedInAt']}'.compareTo('${latest['checkedInAt']}') > 0)) latest = a;
    }
    final name = '${e['title'] ?? ''}'.isEmpty ? 'Event $code' : '${e['title']}';
    onTray?.call(
      trayText(
        name: name,
        count: list.length,
        left: list.where((a) => a is Map && a['leftEarlyAt'] != null).length,
        latestName: latest?['name'] as String?,
        latestAt: latest?['checkedInAt'] as String?,
        paused: e['paused'] == true,
        ended: e['ended'] == true,
      ),
      ' ${list.length} here',
    );
    Runner.setBadge('${list.length}');
  }
}
