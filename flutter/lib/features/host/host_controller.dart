// The host page's state and everything it does (main-site/js/host.js), for one event code:
//
// Shows the code and QR, takes same-wifi check-ins over P2P while it's open, and keeps the list.
// The server is the source of truth; this polls it, and keeps its last copy so the list still
// opens with no connection. A check-in that arrives while the server can't be reached isn't lost:
// it goes into an outbox on this device, the attendee is told they're in, and the outbox is sent
// when the connection comes back. People added by hand offline go the same way.
//
// On Android a few things go through the app's own code (lib/native/bridge.dart, the Here
// plugin): tapping phones (this phone answers as an NFC tag, TapService.java), Bluetooth
// check-ins app to app (Mesh.java), the hotspot for no internet (Hotspot.java), the QR code at
// full brightness, the CSV into Downloads, this event's check-in notifications and the home
// screen widget. Each is behind Native.has(), so a device without it shows the site's words.
import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../../api/api.dart';
import '../../app/nav.dart';
import '../../app/pages.dart';
import '../../data/format.dart';
import '../../data/geo.dart';
import '../../data/here_store.dart';
import '../../native/bridge.dart';
import '../../p2p/here_p2p.dart';
import '../../p2p/peer.dart' show ShareLink;
import '../notify/host_alerts.dart';
import '../widget/app_widget.dart';
import 'save_file.dart';

const _pollInterval = Duration(seconds: 5);
const _maximumTakenRetries = 3;
const _takenRetryDelay = Duration(seconds: 4);

const limitTitle = 80;
const limitButtonLabel = 20;
const limitNoteLabel = 40;
const limitName = 60;
const limitNote = 120;

/// How each check-in came, as the list shows it.
const methodInfo = <String, ({String icon, String label})>{
  'p2p': (icon: 'wifi', label: 'Same wifi'),
  'location': (icon: 'pin', label: 'Location'),
  'manual': (icon: 'hand', label: 'Added by hand'),
  'tap': (icon: 'tap', label: 'Tapped phones'),
  'tap_late': (icon: 'tap', label: 'Tapped, sent later'),
  'mesh': (icon: 'bluetooth', label: 'Bluetooth'),
  'hotspot': (icon: 'hotspot', label: "Host's hotspot"),
};

/// The icon and label for a check-in [method]; one the list doesn't know shows as "Added by hand".
({String icon, String label}) methodOf(String? method) {
  final details = methodInfo[method];
  if (details == null) {
    return methodInfo['manual']!;
  }
  return details;
}

/// [value] as text, or [fallback] when there is no value at all.
String _textOrDefault(Object? value, String fallback) {
  if (value == null) {
    return fallback;
  }
  return '$value';
}

/// One row of the list: from the server, or waiting in the outbox.
class Attendee {
  Attendee({
    required this.id,
    required this.name,
    this.note,
    required this.method,
    this.distance,
    required this.checkedInAt,
    this.leftEarlyAt,
    this.pending = false,
  });

  final String id;
  final String name;
  final String? note;
  final String method;
  final num? distance;
  final String checkedInAt;
  final String? leftEarlyAt;
  final bool pending;

  /// An attendee as the server (or this device's saved copy) describes one.
  static Attendee from(Map fields) {
    return Attendee(
      id: '${fields['id']}',
      name: _textOrDefault(fields['name'], ''),
      note: fields['note'] as String?,
      method: _textOrDefault(fields['method'], 'manual'),
      distance: fields['distance'] as num?,
      checkedInAt: _textOrDefault(fields['checkedInAt'], ''),
      leftEarlyAt: fields['leftEarlyAt'] as String?,
    );
  }
}

/// What a status row shows: its light, its sentence, and its button, if any.
class StatusRow {
  const StatusRow(this.light, this.text, {this.action, this.onAction});
  final String light;
  final String text;
  final String? action;
  final VoidCallback? onAction;
}

class HostController extends ChangeNotifier with WidgetsBindingObserver {
  HostController(this.code) {
    WidgetsBinding.instance.addObserver(this);
    _listeners = [
      Native.on('Here', 'tapped', (_) {
        AppNav.toast('Phone tapped. They finish on their phone.');
      }),
      Native.on('Here', 'meshCheckin', (data) async {
        final answer = await takeCheckin(data, 'mesh');
        Native.tryCall('Here', 'meshAnswer', {'id': data['id'], 'ok': answer['type'] == 'checked-in', 'at': answer['at'], 'message': answer['message']});
      }),
      Native.on('Here', 'hotspotCheckin', (data) async {
        final answer = await takeCheckin(data, 'hotspot');
        Native.tryCall('Here', 'hotspotAnswer', {'id': data['id'], 'ok': answer['type'] == 'checked-in', 'at': answer['at'], 'message': answer['message']});
      }),
      Native.on('Here', 'hotspotStopped', (_) {
        hotspot = {'status': 'failed', 'message': 'The hotspot stopped. Start it again if people still need it.'};
        hotspotSheetOpen.value = false;
        _changed();
        updateWakeLock();
      }),
    ];
    _stopListeningForOnline = Api.onOnline(_online);
    AppPages.current.addListener(updateWakeLock);
  }

  final String code;
  late final List<NativeListener> _listeners;

  /// "loading", "missing", "locked" or "host".
  String view = 'loading';
  String missingTitle = '';
  String missingText = '';
  String lockedText = 'Enter the password set when this event was made.';

  String? hostKey;
  Map<String, dynamic>? event;
  List<Attendee> attendees = [];
  String? savedAt;

  /// "ok", "offline" or "unavailable".
  String connection = 'ok';
  Timer? _pollTimer;
  bool _flushing = false;
  bool _disposed = false;
  late final void Function() _stopListeningForOnline;

  P2pHost? _p2pHost;
  P2pStatus p2p = const P2pStatus('idle');
  int _takenRetries = 0;
  Timer? _retryTimer;

  /// What the app last said about tapping phones: "idle", "ready", "nfc-off", "unsupported" or "error".
  String tapState = 'idle';
  bool _tapWanted = false;

  /// About Bluetooth: "idle", "ready", "needs-permission", "denied", "bt-off", "unsupported", or
  /// "failed" with bluetoothFailure.
  String bluetoothState = 'idle';
  String bluetoothFailure = '';
  bool _bluetoothWanted = false;

  /// { status: "off" | "starting" | "on" | "failed", ssid, password, security, url, message }.
  Map<String, dynamic> hotspot = {'status': 'off'};

  /// Set while the hotspot's codes are up, for the screen to show and close them.
  final ValueNotifier<bool> hotspotSheetOpen = ValueNotifier(false);

  bool _awake = false;
  bool _resumed = true;

  /// One of the event's own values, or null while there is no event.
  Object? _eventValue(String key) {
    final currentEvent = event;
    if (currentEvent == null) {
      return null;
    }
    return currentEvent[key];
  }

  bool get ended {
    return _eventValue('ended') == true;
  }

  bool get paused {
    return _eventValue('paused') == true;
  }

  String get title {
    return _textOrDefault(_eventValue('title'), '');
  }

  String? get noteLabel {
    final label = _eventValue('noteLabel');
    if (label is String && label.isNotEmpty) {
      return label;
    }
    return null;
  }

  String get joinLink {
    return '$siteOrigin/join?id=$code';
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------------ boot

  /// Opens the event: the locked view without this device's key, else the saved copy at once,
  /// then the server's, then polling every few seconds.
  Future<void> boot() async {
    hostKey = HereStore.hostKey(code);
    if (hostKey == null) {
      _showLocked(null);
      return;
    }
    final cache = HereStore.hostCache(code);
    if (cache != null && cache['event'] is Map) _applySnapshot(cache, fromCache: true);
    await refresh();
    if (event == null && connection != 'ok') {
      _showMissing('Not available offline', 'This event has not been opened on this device before. Connect to the internet and try again.');
      return;
    }
    _startPolling();
  }

  void _showMissing(String missingHeading, String text) {
    missingTitle = missingHeading;
    missingText = text;
    view = 'missing';
    _changed();
  }

  void _showLocked(String? message) {
    if (message == null) {
      lockedText = 'Enter the password set when this event was made.';
    } else {
      lockedText = message;
    }
    view = 'locked';
    _changed();
  }

  void _startPolling() {
    final oldTimer = _pollTimer;
    if (oldTimer != null) {
      oldTimer.cancel();
    }
    _pollTimer = Timer.periodic(_pollInterval, (_) {
      if (_resumed && event != null && !ended) refresh();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final resumed = state == AppLifecycleState.resumed;
    if (resumed == _resumed) return;
    _resumed = resumed;
    if (!resumed || hostKey == null) {
      updateWakeLock();
      return;
    }
    refresh();
    // A phone that slept may have lost its peer.
    if (_wantP2p && (p2p.status == 'error' || p2p.status == 'idle')) restartP2p();
    syncTap(force: true);
    // Bluetooth may have been switched on, or allowed, meanwhile.
    syncBluetooth(force: true);
    updateWakeLock();
  }

  void _online() {
    if (_disposed) return;
    refresh();
    if (_wantP2p && p2p.status != 'waiting' && p2p.status != 'connected') restartP2p();
  }

  // ------------------------------------------------------------------ the server

  void _setConnection(String state) {
    connection = state;
    _changed();
  }

  /// Why a request didn't reach a usable answer, if that's what happened.
  static String? _failureOf(ApiResult result) {
    if (result.offline) return 'offline';
    if (result.status >= 500) return 'unavailable';
    return null;
  }

  /// Takes in the event and its list, from the server or (with [fromCache]) this device's saved
  /// copy. A fresh one is saved, and handed to notifications and the home screen widget.
  void _applySnapshot(Map<String, dynamic> snapshot, {bool fromCache = false}) {
    event = Map<String, dynamic>.from(snapshot['event'] as Map);
    final list = snapshot['attendees'];
    attendees = [
      if (list is List)
        for (final entry in list)
          if (entry is Map) Attendee.from(entry),
    ];
    if (fromCache) {
      savedAt = snapshot['savedAt'] as String?;
    } else {
      savedAt = DateTime.now().toUtc().toIso8601String();
    }
    if (!fromCache) {
      _persist();
      HereStore.saveHosted(code, hostKey!, event);
      // Check-ins by location reach this phone while the app is closed, until the event ends.
      HostAlerts.watch(hostKey!, !ended);
      List<dynamic> attendeeList;
      if (list == null) {
        attendeeList = const [];
      } else {
        attendeeList = list as List;
      }
      AppWidgetData.tell(code, hostKey!, event!, attendeeList);
    }
    view = 'host';
    _changed();
    syncP2p();
    syncTap();
    syncBluetooth();
    if (ended) stopHotspot();
  }

  void _persist() {
    if (event == null) return;
    HereStore.saveHostCache(code, event!, [for (final attendee in attendees) _attendeeJson(attendee)]);
  }

  static Map<String, dynamic> _attendeeJson(Attendee attendee) {
    return {
      'id': attendee.id,
      'name': attendee.name,
      'note': attendee.note,
      'method': attendee.method,
      'distance': attendee.distance,
      'checkedInAt': attendee.checkedInAt,
      'leftEarlyAt': attendee.leftEarlyAt,
    };
  }

  /// Adds this attendee to the list, or replaces the row with the same id.
  void _upsert(Map attendeeFields) {
    final attendee = Attendee.from(attendeeFields);
    final index = attendees.indexWhere((existing) {
      return existing.id == attendee.id;
    });
    if (index == -1) {
      attendees.add(attendee);
    } else {
      attendees[index] = attendee;
    }
    _persist();
  }

  void _loseAccess() {
    HostAlerts.watch(hostKey, false);
    AppWidgetData.forget(code);
    hostKey = null;
    HereStore.forgetHosted(code);
    _stopP2p();
    syncTap();
    syncBluetooth();
    _showLocked('This device can no longer manage this event. Enter its password to open it.');
  }

  void _eventGone() {
    HostAlerts.watch(hostKey, false);
    AppWidgetData.forget(code);
    HereStore.forgetHosted(code);
    _stopP2p();
    event = null;
    syncTap();
    syncBluetooth();
    stopHotspot();
    _showMissing(
      'This event is gone',
      'Events are deleted $purgeAfterEndDays days after they end, or $purgeUnendedDays days after they were made if nobody ends them.',
    );
  }

  /// Sends the outbox, then asks the server for the event and its list.
  Future<void> refresh() async {
    if (hostKey == null || _disposed) return;
    await flushOutbox();
    final result = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'get'});
    if (_disposed) return;
    if (result.ok) {
      _setConnection('ok');
      _applySnapshot(result.map);
      return;
    }
    final failure = _failureOf(result);
    if (failure != null) {
      _setConnection(failure);
      return;
    }
    if (result.reason == 'not-host') {
      _loseAccess();
      return;
    }
    if (result.reason == 'not-found') {
      _eventGone();
      return;
    }
  }

  /// A host action that answers with the whole snapshot: null when it worked, else what to say.
  Future<String?> mutate(String action, Map<String, dynamic> extra, String offlineMessage) async {
    final result = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': action, ...extra});
    if (result.ok) {
      _setConnection('ok');
      _applySnapshot(result.map);
      return null;
    }
    final failure = _failureOf(result);
    if (failure != null) {
      _setConnection(failure);
      if (failure == 'offline') {
        return offlineMessage;
      } else {
        return result.error;
      }
    }
    if (result.reason == 'not-host') {
      _loseAccess();
      return result.error;
    }
    if (result.reason == 'ended') {
      await refresh();
      return 'This event has already ended.';
    }
    return result.error;
  }

  // ---- the outbox: check-ins taken while the server was out of reach ----

  /// A random id for an outbox item: "local-" and 32 hexadecimal digits.
  String _localId() {
    final random = math.Random.secure();
    final hexadecimalPairs = List.generate(16, (_) {
      return random.nextInt(256).toRadixString(16).padLeft(2, '0');
    });
    return 'local-${hexadecimalPairs.join()}';
  }

  void _queue(String kind, Map<String, dynamic> payload) {
    final items = HereStore.outbox(code)..add({'localId': _localId(), 'kind': kind, 'payload': payload});
    HereStore.saveOutbox(code, items);
    _changed();
  }

  int get pendingCount {
    return HereStore.outbox(code).length;
  }

  /// Sends what's waiting in the outbox, oldest first, stopping at the first one that still
  /// can't get through.
  Future<void> flushOutbox() async {
    if (_flushing || hostKey == null) return;
    _flushing = true;
    try {
      var items = HereStore.outbox(code);
      while (items.isNotEmpty) {
        final item = items.first;
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        final result = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': item['kind'], ...payload});
        // Still unreachable, or this device lost its key: keep everything for the next attempt
        // rather than dropping somebody's check-in.
        if (!result.ok && (_failureOf(result) != null || result.reason == 'not-host')) break;
        if (result.ok) {
          _upsert(result.map['attendee'] as Map);
        } else if (result.reason != 'ended') {
          AppNav.toast('Could not save ${payload['name']}: ${result.error}');
        }
        items = HereStore.outbox(code).where((outboxItem) {
          return outboxItem['localId'] != item['localId'];
        }).toList();
        HereStore.saveOutbox(code, items);
      }
    } finally {
      _flushing = false;
      _changed();
    }
  }

  // ------------------------------------------------------------------ the list

  /// Everyone to show: the server's list and the outbox's, newest check-in first.
  List<Attendee> displayList() {
    final pending = <Attendee>[];
    for (final item in HereStore.outbox(code)) {
      final payload = item['payload'] as Map;
      String method;
      if (item['kind'] == 'record') {
        method = _textOrDefault(payload['method'], 'p2p');
      } else {
        method = 'manual';
      }
      pending.add(
        Attendee(
          id: '${item['localId']}',
          name: _textOrDefault(payload['name'], ''),
          note: payload['note'] as String?,
          method: method,
          checkedInAt: _textOrDefault(payload['at'], ''),
          pending: true,
        ),
      );
    }
    return [...attendees, ...pending]..sort((first, second) {
      return second.checkedInAt.compareTo(first.checkedInAt);
    });
  }

  /// The sync banner's sentence and whether it's a warning, or null for none.
  ({String text, bool warn})? get syncBanner {
    final pending = pendingCount;
    String pluralEnding;
    if (pending == 1) {
      pluralEnding = '';
    } else {
      pluralEnding = 's';
    }
    String waiting;
    if (pending > 0) {
      waiting = ' $pending check-in$pluralEnding saved on this device will be sent when the connection is back.';
    } else {
      waiting = '';
    }
    if (connection == 'offline') return (text: 'Offline. Showing the list from ${formatTime(savedAt)}.$waiting', warn: true);
    if (connection == 'unavailable') {
      return (text: 'Cannot reach uwuHere right now. Showing the list from ${formatTime(savedAt)}.$waiting', warn: true);
    }
    if (pending > 0) return (text: 'Sending $pending saved check-in$pluralEnding.', warn: false);
    return null;
  }

  String get endedBanner {
    final endedAtText = _textOrDefault(_eventValue('endedAt'), '');
    final endedAt = parseTime(endedAtText);
    String purgeDate;
    if (endedAt == null) {
      purgeDate = '';
    } else {
      purgeDate = formatDateTime(endedAt.add(const Duration(days: purgeAfterEndDays)).toUtc().toIso8601String());
    }
    return 'Ended ${formatDateTime(endedAtText)}. The list can be downloaded here until $purgeDate, then it is deleted.';
  }

  String get locationText {
    if (_eventValue('hasLocation') == true) {
      return "Location check-in within ${_eventValue('radius')} m of this event's spot.";
    } else {
      return 'Location check-in is on, but no spot is set. Set one in Event settings.';
    }
  }

  // ------------------------------------------------------------------ same wifi

  bool get _wantP2p {
    return event != null && event!['allowP2p'] == true && !ended && hostKey != null;
  }

  void syncP2p() {
    if (_wantP2p && _p2pHost == null && _retryTimer == null) _startP2p();
    if (!_wantP2p && (_p2pHost != null || _retryTimer != null)) _stopP2p();
    _changed();
  }

  /// Starts answering same-wifi check-ins under this event's code. When the code is still held
  /// (usually by this page a moment ago), waits and tries again a few times.
  Future<void> _startP2p() async {
    late final P2pHost newHost;
    newHost = P2pHost(
      maxGuests: 40,
      onStatus: (newStatus) {
        if (_p2pHost != newHost) return;
        // Something else holds this code: usually this same page a moment ago, while the broker
        // hasn't let the id go yet. The code can't change, so wait and try again a few times.
        if (newStatus.taken && _takenRetries < _maximumTakenRetries) {
          _takenRetries = _takenRetries + 1;
          _p2pHost = null;
          newHost.close();
          p2p = const P2pStatus('connecting');
          _retryTimer = Timer(_takenRetryDelay, () {
            _retryTimer = null;
            syncP2p();
          });
          _changed();
          return;
        }
        if (newStatus.status == 'waiting' || newStatus.status == 'connected') _takenRetries = 0;
        if (newStatus.taken) {
          p2p = const P2pStatus('error', message: 'This event is already open on another screen. Same-wifi check-ins go to that one.');
        } else {
          p2p = newStatus;
        }
        _changed();
        updateWakeLock();
      },
      onMessage: (message, from) {
        _onPeerMessage(message, from, newHost);
      },
    );
    _p2pHost = newHost;
    p2p = const P2pStatus('connecting');
    _changed();
    try {
      await newHost.start(code);
    } catch (_) {
      if (_p2pHost != newHost) return;
      _p2pHost = null;
      p2p = const P2pStatus('error', message: 'Could not load same-wifi check-in. Check your connection.');
      _changed();
    }
  }

  void _stopP2p() {
    final retryTimer = _retryTimer;
    if (retryTimer != null) {
      retryTimer.cancel();
    }
    _retryTimer = null;
    final oldHost = _p2pHost;
    _p2pHost = null;
    if (oldHost != null) {
      oldHost.close();
    }
    p2p = const P2pStatus('idle');
    _changed();
    updateWakeLock();
  }

  void restartP2p() {
    _stopP2p();
    _takenRetries = 0;
    syncP2p();
  }

  StatusRow? get p2pRow {
    if (event == null || event!['allowP2p'] != true || ended) return null;
    switch (p2p.status) {
      case 'waiting':
      case 'connected':
        return const StatusRow('ok', 'Ready for same-wifi check-ins. Keep this page open.');
      case 'connecting':
        final offline = Api.offline.value;
        if (offline) {
          return const StatusRow('warn', 'Same-wifi check-in needs a connection to start.');
        } else {
          return const StatusRow('', 'Starting same-wifi check-in.');
        }
      case 'error':
        String errorText;
        if (p2p.message.isEmpty) {
          errorText = 'Same-wifi check-in stopped.';
        } else {
          errorText = p2p.message;
        }
        return StatusRow('error', errorText, action: 'Retry', onAction: restartP2p);
      default:
        if (_wantP2p) {
          return StatusRow('', 'Same-wifi check-in is not running.', action: 'Retry', onAction: restartP2p);
        } else {
          return const StatusRow('', 'Same-wifi check-in is not running.');
        }
    }
  }

  Future<void> _onPeerMessage(Map<String, dynamic> message, ShareLink from, P2pHost host) async {
    // bye, and any type a newer build might send: nothing to do.
    if (message['type'] != 'checkin') return;
    if (message['v'] != protocolVersion) {
      host.send({'type': 'refused', 'reason': 'version', 'message': 'This page is out of date. Reload it and try again.'}, from);
      return;
    }
    host.send(await takeCheckin(message, 'p2p'), from);
  }

  /// A check-in this page received, by same wifi ("p2p"), the hotspot ("hotspot") or Bluetooth
  /// ("mesh"): to the server, or into the outbox if it can't be reached. Answers the same-wifi
  /// protocol's own answers.
  Future<Map<String, Object?>> takeCheckin(Map<String, dynamic> message, String method) async {
    if (event == null || ended) return {'type': 'refused', 'reason': 'ended', 'message': 'This event has ended.'};
    if (paused) return {'type': 'refused', 'reason': 'paused', 'message': 'The host has paused check-ins for now.'};

    final rawDeviceHash = message['deviceHash'];
    String? deviceHash;
    if (rawDeviceHash is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(rawDeviceHash)) {
      deviceHash = rawDeviceHash;
    } else {
      deviceHash = null;
    }
    final name = cleanLine(message['name'], limitName);
    String? note;
    if (noteLabel != null) {
      Object? rawNote = message['note'];
      if (rawNote == null) {
        rawNote = '';
      }
      note = cleanLine(rawNote, limitNote);
    } else {
      note = '';
    }
    if (deviceHash == null || name == null || name.isEmpty || note == null) {
      return {'type': 'refused', 'reason': 'invalid', 'message': 'That check-in was missing a name.'};
    }

    // Already waiting in the outbox from this device: the same answer again.
    for (final item in HereStore.outbox(code)) {
      if (item['kind'] == 'record' && (item['payload'] as Map)['deviceHash'] == deviceHash) {
        return {'type': 'checked-in', 'at': (item['payload'] as Map)['at']};
      }
    }

    String? noteToSend;
    if (note.isEmpty) {
      noteToSend = null;
    } else {
      noteToSend = note;
    }
    final payload = <String, dynamic>{
      'deviceHash': deviceHash,
      'name': name,
      'note': noteToSend,
      'at': DateTime.now().toUtc().toIso8601String(),
      'method': method,
    };
    final result = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'record', ...payload});
    if (result.ok) {
      _setConnection('ok');
      final attendeeFields = result.map['attendee'] as Map;
      _upsert(attendeeFields);
      _changed();
      return {'type': 'checked-in', 'at': attendeeFields['checkedInAt']};
    }
    final failure = _failureOf(result);
    if (failure != null) {
      _setConnection(failure);
      _queue('record', payload);
      return {'type': 'checked-in', 'at': payload['at']};
    }
    return {'type': 'refused', 'reason': result.reason, 'message': result.error};
  }

  // ------------------------------------------------------------------ tapping phones

  bool get _wantTap {
    return event != null && event!['allowTap'] == true && !ended && hostKey != null && Native.has('tap');
  }

  /// Tells the app whether to answer taps, and with which event's key. Asked again with force
  /// when the app comes back, as NFC may have been switched on meanwhile.
  Future<void> syncTap({bool force = false}) async {
    final want = _wantTap;
    if (want == _tapWanted && !force) return;
    _tapWanted = want;
    try {
      Map<String, dynamic> options;
      if (want) {
        options = {'on': true, 'code': code, 'hostKey': hostKey};
      } else {
        options = {'on': false};
      }
      final answer = await Native.call('Here', 'tap', options);
      Object? state;
      if (answer != null) {
        state = answer['state'];
      }
      tapState = _textOrDefault(state, 'idle');
    } catch (_) {
      if (want) {
        tapState = 'error';
      } else {
        tapState = 'idle';
      }
    }
    _changed();
    updateWakeLock();
  }

  StatusRow? get tapRow {
    if (event == null || event!['allowTap'] != true || ended) return null;
    if (!Native.has('tap')) {
      String text;
      if (Native.platform == 'android') {
        text = 'Update the uwuHere app to take taps.';
      } else {
        text = 'Tapping phones works in the uwuHere app on an Android phone with NFC. Open this event there.';
      }
      return StatusRow('warn', text);
    }
    switch (tapState) {
      case 'ready':
        return const StatusRow('ok', 'Ready for taps. People hold their phone against the back of this one.');
      case 'nfc-off':
        return StatusRow(
          'warn',
          'NFC is off on this phone. Turn it on to take taps.',
          action: 'Turn on',
          onAction: () {
            Native.tryCall('Here', 'openSettings', {'what': 'nfc'});
          },
        );
      case 'unsupported':
        return const StatusRow('error', "This phone can't take taps: it has no NFC. Open this event in the app on a phone that has it.");
      case 'error':
        return StatusRow(
          'error',
          "Tapping phones didn't start.",
          action: 'Retry',
          onAction: () {
            syncTap(force: true);
          },
        );
      default:
        return const StatusRow('', 'Starting tap check-in.');
    }
  }

  // ------------------------------------------------------------------ Bluetooth

  bool get _wantBluetooth {
    return event != null && event!['allowBluetooth'] == true && !ended && hostKey != null && Native.has('mesh');
  }

  /// Advertises this event to attendees' apps, or stops. Without `ask` it never shows a permission
  /// prompt by itself: it says "needs-permission", and the row's button asks.
  Future<void> syncBluetooth({bool force = false, bool ask = false}) async {
    final want = _wantBluetooth;
    if (want == _bluetoothWanted && !force && !ask) return;
    _bluetoothWanted = want;
    try {
      Map<String, dynamic> options;
      if (want) {
        options = {'on': true, 'code': code, 'ask': ask};
      } else {
        options = {'on': false};
      }
      final answer = await Native.call('Here', 'bluetooth', options);
      Object? state;
      Object? message;
      if (answer != null) {
        state = answer['state'];
        message = answer['message'];
      }
      bluetoothState = _textOrDefault(state, 'idle');
      bluetoothFailure = _textOrDefault(message, '');
    } catch (_) {
      if (want) {
        bluetoothState = 'failed';
      } else {
        bluetoothState = 'idle';
      }
      bluetoothFailure = '';
    }
    _changed();
    updateWakeLock();
  }

  StatusRow? get bluetoothRow {
    if (event == null || event!['allowBluetooth'] != true || ended) return null;
    if (Native.platform != 'android') {
      return const StatusRow('warn', 'Bluetooth check-in works with this event open in the uwuHere app on Android.');
    }
    if (!Native.has('mesh')) {
      return const StatusRow('error', 'This phone has no Google Play services, which Bluetooth check-in needs.');
    }
    switch (bluetoothState) {
      case 'ready':
        return const StatusRow('ok', 'Ready for Bluetooth. Attendees with the uwuHere app check in phone to phone. Keep this page open.');
      case 'needs-permission':
        return StatusRow(
          'warn',
          'Bluetooth check-in needs "Nearby devices" on this phone.',
          action: 'Allow',
          onAction: () {
            syncBluetooth(ask: true);
          },
        );
      case 'denied':
        return StatusRow(
          'error',
          '"Nearby devices" isn\'t allowed for uwuHere. Allow it in the app\'s settings.',
          action: 'Settings',
          onAction: () {
            Native.tryCall('Here', 'openSettings', {'what': 'app'});
          },
        );
      case 'bt-off':
        return StatusRow(
          'warn',
          'Bluetooth is off on this phone. Turn it on to take Bluetooth check-ins.',
          action: 'Turn on',
          onAction: () {
            Native.tryCall('Here', 'openSettings', {'what': 'bluetooth'});
          },
        );
      case 'failed':
        String failureText;
        if (bluetoothFailure.isEmpty) {
          failureText = "Bluetooth check-in didn't start.";
        } else {
          failureText = bluetoothFailure;
        }
        return StatusRow(
          'error',
          failureText,
          action: 'Retry',
          onAction: () {
            syncBluetooth(force: true);
          },
        );
      default:
        return const StatusRow('', 'Starting Bluetooth check-in.');
    }
  }

  // ------------------------------------------------------------------ the hotspot

  bool get hotspotAvailable {
    return Native.has('hotspot');
  }

  StatusRow? get hotspotRow {
    if (event == null || ended || !hotspotAvailable) return null;
    switch (hotspot['status']) {
      case 'on':
        return StatusRow('ok', 'Hotspot on: ${hotspot['ssid']}. Keep this page open.', action: 'Show codes', onAction: showHotspot);
      case 'starting':
        return const StatusRow('', 'Starting the hotspot.', action: 'Start');
      case 'failed':
        return StatusRow('error', _textOrDefault(hotspot['message'], "The hotspot didn't start."), action: 'Try again', onAction: startHotspot);
      default:
        return StatusRow('none', 'No internet for attendees? This phone can be their wifi.', action: 'Start', onAction: startHotspot);
    }
  }

  /// WIFI:T:WPA;S:name;P:password;; is what phone cameras read as "join this wifi".
  String get wifiQrText {
    // A backslash goes before each character that means something in that text.
    String escape(Object? value) {
      return _textOrDefault(value, '').replaceAllMapped(RegExp(r'([\\;,:"])'), (match) {
        return '\\${match[1]}';
      });
    }

    if (hotspot['security'] == 'nopass') {
      return 'WIFI:T:nopass;S:${escape(hotspot['ssid'])};;';
    } else {
      return 'WIFI:T:${_textOrDefault(hotspot['security'], 'WPA')};S:${escape(hotspot['ssid'])};P:${escape(hotspot['password'])};;';
    }
  }

  void showHotspot() {
    if (hotspot['status'] != 'on') return;
    hotspotSheetOpen.value = true;
    brightness(true);
  }

  /// Asks the app to start this phone's hotspot for the event, and shows its codes once it's on.
  Future<void> startHotspot() async {
    if (event == null || ended || hotspot['status'] == 'starting') return;
    hotspot = {'status': 'starting'};
    _changed();
    try {
      final currentNoteLabel = noteLabel;
      String noteLabelToSend;
      if (currentNoteLabel == null) {
        noteLabelToSend = '';
      } else {
        noteLabelToSend = currentNoteLabel;
      }
      final answer = await Native.call('Here', 'hotspot', {
        'on': true,
        'code': code,
        'title': title,
        'buttonLabel': event!['buttonLabel'],
        'buttonColor': event!['buttonColor'],
        'noteLabel': noteLabelToSend,
      });
      if (answer != null && answer['state'] == 'on') {
        hotspot = {...answer, 'status': 'on'};
      } else {
        Object? failureMessage;
        if (answer != null) {
          failureMessage = answer['message'];
        }
        hotspot = {'status': 'failed', 'message': failureMessage};
      }
    } on NativeError catch (error) {
      hotspot = {'status': 'failed', 'message': error.message};
    }
    _changed();
    updateWakeLock();
    if (hotspot['status'] == 'on') showHotspot();
  }

  void stopHotspot() {
    if (hotspot['status'] == 'off') return;
    hotspot = {'status': 'off'};
    Native.tryCall('Here', 'hotspot', {'on': false});
    hotspotSheetOpen.value = false;
    _changed();
    updateWakeLock();
  }

  // ------------------------------------------------------------------ the screen

  /// The screen has to stay on for same-wifi check-ins to reach it, for taps to be answered, and
  /// for hotspot and Bluetooth check-ins to be recorded: while this event's page is on show.
  void updateWakeLock() {
    if (_disposed) return;
    final want =
        ((_p2pHost != null && (p2p.status == 'waiting' || p2p.status == 'connected')) ||
            tapState == 'ready' ||
            bluetoothState == 'ready' ||
            hotspot['status'] == 'on') &&
        _resumed &&
        AppPages.active() == AppPages.host;
    if (want == _awake) return;
    _awake = want;
    // Refused (battery saver, a browser without a user's press): the page still works.
    if (want) {
      WakelockPlus.enable().catchError((Object _) {});
    } else {
      WakelockPlus.disable().catchError((Object _) {});
    }
  }

  /// The screen at full brightness while a code is up, so the back of a room can scan it. The
  /// phone's own setting is left alone.
  void brightness(bool maximum) {
    if (Native.has('brightness')) Native.tryCall('Here', 'brightness', {'max': maximum});
  }

  // ------------------------------------------------------------------ actions

  Future<void> copyLink() async {
    try {
      await copyText(joinLink);
      AppNav.toast('Link copied');
    } catch (_) {
      AppNav.toast('Copy the link under the code');
    }
  }

  Future<void> togglePause() async {
    String action;
    if (paused) {
      action = 'resume';
    } else {
      action = 'pause';
    }
    final errorMessage = await mutate(action, const {}, 'Pausing needs a connection.');
    if (errorMessage != null) AppNav.toast(errorMessage);
  }

  /// Removes someone: null when done.
  Future<String?> remove(Attendee attendee) async {
    if (attendee.pending) {
      final remaining = HereStore.outbox(code).where((item) {
        return item['localId'] != attendee.id;
      }).toList();
      HereStore.saveOutbox(code, remaining);
      _changed();
      return null;
    }
    return mutate('remove', {'attendeeId': attendee.id}, 'Removing someone needs a connection.');
  }

  /// Adds someone by hand: true when added or saved for later.
  Future<bool> add(String name, String note) async {
    String? noteToSend;
    if (noteLabel != null && note.isNotEmpty) {
      noteToSend = note;
    } else {
      noteToSend = null;
    }
    final payload = {'name': name, 'note': noteToSend, 'at': DateTime.now().toUtc().toIso8601String()};
    final result = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'add', ...payload});
    if (result.ok) {
      _setConnection('ok');
      _upsert(result.map['attendee'] as Map);
      _changed();
      return true;
    }
    final failure = _failureOf(result);
    if (failure != null) {
      _setConnection(failure);
      _queue('add', payload);
      AppNav.toast('Saved on this device. It is sent when the connection is back.');
      return true;
    }
    AppNav.toast(result.error);
    return false;
  }

  /// The list as a CSV, with the byte order mark that makes Excel read it as UTF-8.
  String csv() {
    final currentNoteLabel = noteLabel;
    String noteHeading;
    if (currentNoteLabel == null) {
      noteHeading = 'Note';
    } else {
      noteHeading = currentNoteLabel;
    }
    final rows = <List<Object?>>[
      ['Name', noteHeading, 'Checked in', 'How', 'Distance (m)', 'Left early'],
    ];
    for (final attendee in displayList().reversed) {
      String noteCell;
      if (attendee.note == null) {
        noteCell = '';
      } else {
        noteCell = attendee.note!;
      }
      Object distanceCell;
      if (attendee.distance == null) {
        distanceCell = '';
      } else {
        distanceCell = attendee.distance!;
      }
      rows.add([attendee.name, noteCell, stamp(attendee.checkedInAt), methodOf(attendee.method).label, distanceCell, stamp(attendee.leftEarlyAt)]);
    }
    final lines = rows.map((row) {
      return row.map(csvCell).join(',');
    });
    return '﻿${lines.join('\r\n')}';
  }

  String get csvName {
    return 'uwuhere-$code-${stamp(DateTime.now().toUtc().toIso8601String()).substring(0, 10)}.csv';
  }

  Future<void> downloadCsv() async {
    if (event == null) return;
    final name = csvName;
    final saved = await saveTextFile(name, csv(), 'text/csv');
    if (saved == null) return;
    AppNav.toast(saved);
  }

  /// Ends the event: null when it's ended.
  Future<String?> end() async {
    await flushOutbox();
    return mutate('end', const {}, 'Ending the event needs a connection.');
  }

  /// Saves the settings sheet: null when saved.
  Future<String?> saveSettings(Map<String, dynamic> settings) {
    return mutate('update', {'settings': settings}, 'Changing settings needs a connection.');
  }

  /// Sets the event's password, or removes it when [password] is empty: null when done.
  Future<String?> setPassword(String password) {
    String offlineMessage;
    if (password.isEmpty) {
      offlineMessage = 'Removing the password needs a connection.';
    } else {
      offlineMessage = 'Setting a password needs a connection.';
    }
    return mutate('password', {'password': password}, offlineMessage);
  }

  /// Opens the event with its password, on a device that didn't make it: null when open.
  Future<String?> unlock(String password) async {
    final result = await Api.post('unlock', {'code': code, 'password': password});
    if (!result.ok) {
      if (result.reason == 'not-found') {
        _eventGone();
        return null;
      }
      if (result.offline) {
        return 'Opening an event here needs a connection.';
      } else {
        return result.error;
      }
    }
    hostKey = '${result.map['hostKey']}';
    HereStore.saveHosted(code, hostKey!, Map<String, dynamic>.from(result.map['event'] as Map));
    _applySnapshot(result.map);
    _startPolling();
    return null;
  }

  /// A spot for location check-in, from this device.
  Future<Position2> takeSpot() {
    return Geo.getPosition();
  }

  /// Stops everything this event started: polling, same wifi, taps, Bluetooth, the hotspot and
  /// the screen staying on.
  @override
  void dispose() {
    _disposed = true;
    _stopListeningForOnline();
    WidgetsBinding.instance.removeObserver(this);
    AppPages.current.removeListener(updateWakeLock);
    final pollTimer = _pollTimer;
    if (pollTimer != null) {
      pollTimer.cancel();
    }
    final retryTimer = _retryTimer;
    if (retryTimer != null) {
      retryTimer.cancel();
    }
    final p2pHost = _p2pHost;
    if (p2pHost != null) {
      p2pHost.close();
    }
    _p2pHost = null;
    for (final listener in _listeners) {
      listener.cancel();
    }
    if (_tapWanted) Native.tryCall('Here', 'tap', {'on': false});
    if (_bluetoothWanted) Native.tryCall('Here', 'bluetooth', {'on': false});
    if (hotspot['status'] == 'on' || hotspot['status'] == 'starting') Native.tryCall('Here', 'hotspot', {'on': false});
    if (_awake) WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }
}
