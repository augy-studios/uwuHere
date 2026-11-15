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

  static bool get on => DeskSettings.get<bool>('alertsCheckins') ?? true;

  static void start() {
    _timer?.cancel();
    if (!on) return;
    _check();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) => _check());
  }

  static void restart() {
    _seen.clear();
    start();
  }

  static Future<void> _check() async {
    if (!on) return;
    for (final ev in HereStore.listHosted()) {
      if (ev.ended || ev.hostKey.isEmpty) continue;
      final r = await Api.post('host', {'code': ev.code, 'hostKey': ev.hostKey, 'action': 'get'});
      if (!r.ok) continue;
      final event = r.map['event'];
      final list = r.map['attendees'];
      if (event is! Map || list is! List) continue;
      final first = !_seen.containsKey(ev.code);
      final seen = _seen.putIfAbsent(ev.code, () => <String>{});
      final news = <String>[];
      for (final a in list) {
        if (a is! Map) continue;
        final id = '${a['id']}';
        if (a['method'] == 'location' && seen.add('in:$id') && !first) news.add('${a['name']} checked in by location.');
        if (a['leftEarlyAt'] != null && seen.add('left:$id') && !first) news.add('${a['name']} left early.');
      }
      if (news.isEmpty) continue;
      final title = '${event['title'] ?? ''}'.isEmpty ? 'Event ${ev.code}' : '${event['title']}';
      final body = news.length == 1 ? '${news.first} ${list.length} checked in so far.' : '${news.first} And ${news.length - 1} more…';
      await DeskNotify.show(title: title, body: body, link: 'uwu://here/host?id=${ev.code}');
    }
  }
}
