// Host alerts: an event's own FCM topic (main-site/js/app-notify.js). "uwuhere-host-" and the
// first 40 hex digits of the SHA-256 of the event's host key: api/_lib/alerts.js works out the
// same from the event id, and the app's Java accepts nothing else. The host page names its event
// whenever it has it from the server, and takes it off when the event ends; the app joins the
// topic while "Check-ins to my events" is on.
//
// On the desktop there's no push: the events this computer hosts are polled instead
// (lib/desktop/alerts_poll.dart).
import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../native/bridge.dart';

class HostAlerts {
  HostAlerts._();

  static String topic(String hostKey) => 'uwuhere-host-${sha256.convert(utf8.encode(hostKey)).toString().substring(0, 40)}';

  // What's been told already, so a host page polling every few seconds asks once.
  static final Map<String, bool> _told = {};

  /// This device hosts the event with this key (on), or no longer does (off). Quietly nothing
  /// without push.
  static Future<void> watch(String? hostKey, bool on) async {
    if (hostKey == null || _told[hostKey] == on || !Native.has('push')) return;
    _told[hostKey] = on;
    try {
      await Native.call('Here', 'watchEvent', {'topic': topic(hostKey), 'on': on});
    } catch (_) {
      // Asked again the next time the host page opens.
      _told.remove(hostKey);
    }
  }
}
