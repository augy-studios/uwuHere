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
  // The second line: how many came, or how many are here (and who left early, and whether
  // check-in is paused).
  String countLine;
  if (ended) {
    countLine = 'Ended: $count checked in';
  } else {
    String leftEarlyNote = '';
    if (left > 0) {
      leftEarlyNote = ', $left left early';
    }
    String pausedNote = '';
    if (paused) {
      pausedNote = ' (paused)';
    }
    countLine = '$count here$leftEarlyNote$pausedNote';
  }
  final lines = [
    name,
    countLine,
    if (latestName != null && !ended) 'Last: $latestName at ${formatTime(latestAt)}',
  ];
  final text = lines.join('\n');
  if (text.length <= 127) {
    return text;
  }
  return '${text.substring(0, 126)}…';
}

class Glance {
  Glance._();

  static Timer? _refreshTimer;

  /// Set by tray.dart: puts a new tooltip and title up.
  static void Function(String tooltip, String title)? onTray;
  static final ValueNotifier<Map<String, dynamic>?> followed = ValueNotifier(null);

  /// Picks the followed event back up from settings, keeps the favourites in step with your
  /// events, and refreshes the tray every 30 seconds.
  static void start() {
    final savedFollowedEvent = DeskSettings.get<Map<String, dynamic>>('trayStop');
    if (savedFollowedEvent != null) {
      followed.value = savedFollowedEvent;
    }
    HereStore.changes('hosted').listen((_) {
      favouritesChanged();
    });
    favouritesChanged();
    if (_refreshTimer != null) {
      _refreshTimer!.cancel();
    }
    _refreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      refreshTray();
    });
    refreshTray();
  }

  static String _lastFavouritesKey = '';

  /// Your events, open ones first, as the Jump List, thumbnail buttons and Dock menu.
  static List<Map<String, Object?>> favourites() {
    final hosted = HereStore.listHosted();
    final openEvents = hosted.where((event) {
      return !event.ended;
    });
    final endedEvents = hosted.where((event) {
      return event.ended;
    });
    final ordered = [...openEvents, ...endedEvents];
    final favouriteList = <Map<String, Object?>>[];
    for (final event in ordered.take(10)) {
      String title = event.title;
      if (title.isEmpty) {
        title = 'Untitled event';
      }
      favouriteList.add({'code': event.code, 'name': '$title (${event.code})'});
    }
    return favouriteList;
  }

  /// Saves the favourites and hands them to the runner, but only when they've changed.
  static void favouritesChanged() {
    final favouriteEvents = favourites();
    final key = favouriteEvents.toString();
    if (key == _lastFavouritesKey) {
      return;
    }
    _lastFavouritesKey = key;
    DeskSettings.write({'favourites': favouriteEvents});
    Runner.setFavourites(favouriteEvents);
  }

  /// Follows an event in the tray, or stops (null).
  static void follow(String? code, [String? name]) {
    Map<String, String>? followedEvent;
    if (code != null) {
      String eventName;
      if (name == null) {
        eventName = 'Event $code';
      } else {
        eventName = name;
      }
      followedEvent = {'code': code, 'name': eventName};
    }
    DeskSettings.write({'trayStop': followedEvent});
    followed.value = followedEvent;
    refreshTray();
  }

  /// Fetches the followed event's list and puts its name, count and latest arrival in the tray's
  /// tooltip, title and badge. With nothing followed, the tray just shows the app's name.
  static Future<void> refreshTray() async {
    final followedEvent = followed.value;
    if (followedEvent == null) {
      final trayCallback = onTray;
      if (trayCallback != null) {
        trayCallback(Desktop.name, '');
      }
      Runner.setBadge('');
      return;
    }
    final code = '${followedEvent['code']}';
    final hostKey = HereStore.hostKey(code);
    ApiResult? response;
    if (hostKey != null) {
      response = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'get'});
    }
    if (response == null || !response.ok) {
      final trayCallback = onTray;
      if (trayCallback != null) {
        trayCallback('${followedEvent['name']}: couldn\'t get the list just now', '');
      }
      Runner.setBadge('');
      return;
    }
    final event = Map<String, dynamic>.from(response.map['event'] as Map);
    final attendeesValue = response.map['attendees'] as List?;
    final List<dynamic> attendees;
    if (attendeesValue == null) {
      attendees = const [];
    } else {
      attendees = attendeesValue;
    }
    // Whoever checked in most recently.
    Map? latest;
    for (final attendee in attendees) {
      if (attendee is Map && (latest == null || '${attendee['checkedInAt']}'.compareTo('${latest['checkedInAt']}') > 0)) {
        latest = attendee;
      }
    }
    final titleValue = event['title'];
    String titleText = '';
    if (titleValue != null) {
      titleText = '$titleValue';
    }
    String eventName;
    if (titleText.isEmpty) {
      eventName = 'Event $code';
    } else {
      eventName = titleText;
    }
    final trayCallback = onTray;
    if (trayCallback != null) {
      final leftEarlyCount = attendees.where((attendee) {
        return attendee is Map && attendee['leftEarlyAt'] != null;
      }).length;
      String? latestName;
      String? latestAt;
      if (latest != null) {
        latestName = latest['name'] as String?;
        latestAt = latest['checkedInAt'] as String?;
      }
      trayCallback(
        trayText(
          name: eventName,
          count: attendees.length,
          left: leftEarlyCount,
          latestName: latestName,
          latestAt: latestAt,
          paused: event['paused'] == true,
          ended: event['ended'] == true,
        ),
        ' ${attendees.length} here',
      );
    }
    Runner.setBadge('${attendees.length}');
  }
}
