// Check-in notifications on the desktop (docs/desktop-features-spec.md §7): there's no push here,
// so while the app runs, open or in the tray, it looks every minute at each event this computer
// hosts that hasn't ended, by the same rules the server uses for the phone's push
// (main-site/api/_lib/alerts.js): someone who checked in by location, and someone who left early.
// Same-wifi, tapped and hand-added check-ins arrive on the host page itself, so they don't notify.
// The first look only records what's there. One notification sums up a batch ("And 2 more…");
// clicking it opens the event's host page. Off with "Check-ins to my events" in Notifications.
//
// Keys: alertsCheckins (false when it's off; missing means on).
import 'dart:async';

import '../api/api.dart';
import '../data/here_store.dart';
import 'notify.dart';
import 'settings.dart';

class AlertsPoll {
  AlertsPoll._();

  static Timer? _timer;

  /// What's been seen, per event: attendee ids by location, and ids that had left early.
  static final Map<String, Set<String>> _seen = {};

  /// Whether "Check-ins to my events" is on (it is unless it was turned off).
  static bool get isOn {
    final setting = DeskSettings.get<bool>('alertsCheckins');
    if (setting == null) return true;
    return setting;
  }

  static void start() {
    if (_timer != null) _timer!.cancel();
    if (!isOn) return;
    _check();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      _check();
    });
  }

  static void restart() {
    _seen.clear();
    start();
  }

  /// One look at every hosted event that hasn't ended: anyone new by location or newly left
  /// early since the last look becomes one notification per event.
  static Future<void> _check() async {
    if (!isOn) return;
    for (final hostedEvent in HereStore.listHosted()) {
      if (hostedEvent.ended || hostedEvent.hostKey.isEmpty) continue;
      final response = await Api.post('host', {'code': hostedEvent.code, 'hostKey': hostedEvent.hostKey, 'action': 'get'});
      if (!response.ok) continue;
      final event = response.map['event'];
      final attendees = response.map['attendees'];
      if (event is! Map || attendees is! List) continue;
      final isFirstLook = !_seen.containsKey(hostedEvent.code);
      final seen = _seen.putIfAbsent(hostedEvent.code, () {
        return <String>{};
      });
      final newMessages = <String>[];
      for (final attendee in attendees) {
        if (attendee is! Map) continue;
        final id = '${attendee['id']}';
        if (attendee['method'] == 'location') {
          final isNewlySeen = seen.add('in:$id');
          if (isNewlySeen && !isFirstLook) newMessages.add('${attendee['name']} checked in by location.');
        }
        if (attendee['leftEarlyAt'] != null) {
          final isNewlySeen = seen.add('left:$id');
          if (isNewlySeen && !isFirstLook) newMessages.add('${attendee['name']} left early.');
        }
      }
      if (newMessages.isEmpty) continue;
      final eventTitle = event['title'];
      String title;
      if (eventTitle == null || '$eventTitle'.isEmpty) {
        title = 'Event ${hostedEvent.code}';
      } else {
        title = '$eventTitle';
      }
      String body;
      if (newMessages.length == 1) {
        body = '${newMessages.first} ${attendees.length} checked in so far.';
      } else {
        body = '${newMessages.first} And ${newMessages.length - 1} more…';
      }
      await DeskNotify.show(title: title, body: body, link: 'uwu://here/host?id=${hostedEvent.code}');
    }
  }
}
