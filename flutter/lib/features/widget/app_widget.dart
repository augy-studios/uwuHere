// The "Your event" home screen widget, in the Android app only (EventWidget.java): the event this
// phone hosts, with how many are here, who checked in last, and its code, drawn with the app
// closed (main-site/js/app-widget.js). The host page tells the app what it has each time it has
// the event from the server, and the widget refreshes itself from /api/host with the same host
// key from then on (WidgetData.java). Once the page no longer has the event, forget() takes it off.
import 'dart:convert';

import '../../native/bridge.dart';

class AppWidgetData {
  AppWidgetData._();

  // Said again once a minute even when nothing changed, so the widget's "Updated" time keeps up.
  static const _resay = Duration(seconds: 60);
  static String _lastSaid = '';
  static DateTime _lastSaidAt = DateTime.fromMillisecondsSinceEpoch(0);

  /// The numbers the widget shows (WidgetData.summarise works out the same).
  static Map<String, Object?> summary(String code, String hostKey, Map<String, dynamic> event, List<dynamic> attendees) {
    Map? latest;
    for (final a in attendees) {
      if (a is! Map) continue;
      if (latest == null || '${a['checkedInAt']}'.compareTo('${latest['checkedInAt']}') > 0) latest = a;
    }
    return {
      'code': code,
      'hostKey': hostKey,
      'title': '${event['title'] ?? ''}',
      'paused': event['paused'] == true,
      'ended': event['ended'] == true,
      'count': attendees.length,
      'left': attendees.where((a) => a is Map && a['leftEarlyAt'] != null).length,
      'latestName': latest?['name'],
      'latestAt': latest?['checkedInAt'],
    };
  }

  static void tell(String code, String hostKey, Map<String, dynamic> event, List<dynamic> attendees) {
    if (!Native.has('widget')) return;
    final said = summary(code, hostKey, event, attendees);
    final key = jsonEncode(said);
    if (key == _lastSaid && DateTime.now().difference(_lastSaidAt) < _resay) return;
    _lastSaid = key;
    _lastSaidAt = DateTime.now();
    Native.call('Here', 'widget', said).catchError((Object _) {
      _lastSaid = '';
      return null;
    });
  }

  static void forget(String code) {
    _lastSaid = '';
    if (!Native.has('widget')) return;
    Native.tryCall('Here', 'widget', {'code': code, 'clear': true});
  }
}
