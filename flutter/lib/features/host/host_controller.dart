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

const _pollEvery = Duration(seconds: 5);
const _maxTakenRetries = 3;
const _takenRetryAfter = Duration(seconds: 4);

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

({String icon, String label}) methodOf(String? m) => methodInfo[m] ?? methodInfo['manual']!;

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

  static Attendee from(Map m) => Attendee(
    id: '${m['id']}',
    name: '${m['name'] ?? ''}',
    note: m['note'] as String?,
    method: '${m['method'] ?? 'manual'}',
    distance: m['distance'] as num?,
    checkedInAt: '${m['checkedInAt'] ?? ''}',
    leftEarlyAt: m['leftEarlyAt'] as String?,
  );
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
      Native.on('Here', 'tapped', (_) => AppNav.toast('Phone tapped. They finish on their phone.')),
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
    _offOnline = Api.onOnline(_online);
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
  Timer? _poll;
  bool _flushing = false;
  bool _disposed = false;
  late final void Function() _offOnline;

  P2pHost? _host;
  P2pStatus p2p = const P2pStatus('idle');
  int _takenRetries = 0;
  Timer? _retryTimer;

  /// What the app last said about tapping phones: "idle", "ready", "nfc-off", "unsupported" or "error".
  String tapState = 'idle';
  bool _tapWanted = false;

  /// About Bluetooth: "idle", "ready", "needs-permission", "denied", "bt-off", "unsupported", or
  /// "failed" with btFailed.
  String btState = 'idle';
  String btFailed = '';
  bool _btWanted = false;

  /// { status: "off" | "starting" | "on" | "failed", ssid, password, security, url, message }.
  Map<String, dynamic> hotspot = {'status': 'off'};

  /// Set while the hotspot's codes are up, for the screen to show and close them.
  final ValueNotifier<bool> hotspotSheetOpen = ValueNotifier(false);

  bool _awake = false;
  bool _resumed = true;

  bool get ended => event?['ended'] == true;
  bool get paused => event?['paused'] == true;
  String get title => '${event?['title'] ?? ''}';
  String? get noteLabel {
    final n = event?['noteLabel'];
    return n is String && n.isNotEmpty ? n : null;
  }

  String get joinLink => '$siteOrigin/join?id=$code';

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  // ------------------------------------------------------------------ boot

  Future<void> boot() async {
    hostKey = HereStore.hostKey(code);
    if (hostKey == null) {
      _showLocked(null);
      return;
    }
    final cache = HereStore.hostCache(code);
    if (cache?['event'] is Map) _applySnapshot(cache!, fromCache: true);
    await refresh();
    if (event == null && connection != 'ok') {
      _showMissing('Not available offline', 'This event has not been opened on this device before. Connect to the internet and try again.');
      return;
    }
    _startPolling();
  }

  void _showMissing(String t, String text) {
    missingTitle = t;
    missingText = text;
    view = 'missing';
    _changed();
  }

  void _showLocked(String? message) {
    lockedText = message ?? 'Enter the password set when this event was made.';
    view = 'locked';
    _changed();
  }

  void _startPolling() {
    _poll?.cancel();
    _poll = Timer.periodic(_pollEvery, (_) {
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
  static String? _failure(ApiResult r) {
    if (r.offline) return 'offline';
    if (r.status >= 500) return 'unavailable';
    return null;
  }

  void _applySnapshot(Map<String, dynamic> snapshot, {bool fromCache = false}) {
    event = Map<String, dynamic>.from(snapshot['event'] as Map);
    final list = snapshot['attendees'];
    attendees = [
      if (list is List)
        for (final a in list)
          if (a is Map) Attendee.from(a),
    ];
    savedAt = fromCache ? snapshot['savedAt'] as String? : DateTime.now().toUtc().toIso8601String();
    if (!fromCache) {
      _persist();
      HereStore.saveHosted(code, hostKey!, event);
      // Check-ins by location reach this phone while the app is closed, until the event ends.
      HostAlerts.watch(hostKey!, !ended);
      AppWidgetData.tell(code, hostKey!, event!, (list as List?) ?? const []);
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
    HereStore.saveHostCache(code, event!, [for (final a in attendees) _attendeeJson(a)]);
  }

  static Map<String, dynamic> _attendeeJson(Attendee a) => {
    'id': a.id,
    'name': a.name,
    'note': a.note,
    'method': a.method,
    'distance': a.distance,
    'checkedInAt': a.checkedInAt,
    'leftEarlyAt': a.leftEarlyAt,
  };

  void _upsert(Map attendee) {
    final a = Attendee.from(attendee);
    final i = attendees.indexWhere((x) => x.id == a.id);
    if (i == -1) {
      attendees.add(a);
    } else {
      attendees[i] = a;
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

  Future<void> refresh() async {
    if (hostKey == null || _disposed) return;
    await flushOutbox();
    final r = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'get'});
    if (_disposed) return;
    if (r.ok) {
      _setConnection('ok');
      _applySnapshot(r.map);
      return;
    }
    final f = _failure(r);
    if (f != null) return _setConnection(f);
    if (r.reason == 'not-host') return _loseAccess();
    if (r.reason == 'not-found') return _eventGone();
  }

  /// A host action that answers with the whole snapshot: null when it worked, else what to say.
  Future<String?> mutate(String action, Map<String, dynamic> extra, String offlineMessage) async {
    final r = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': action, ...extra});
    if (r.ok) {
      _setConnection('ok');
      _applySnapshot(r.map);
      return null;
    }
    final f = _failure(r);
    if (f != null) {
      _setConnection(f);
      return f == 'offline' ? offlineMessage : r.error;
    }
    if (r.reason == 'not-host') {
      _loseAccess();
      return r.error;
    }
    if (r.reason == 'ended') {
      await refresh();
      return 'This event has already ended.';
    }
    return r.error;
  }

  // ---- the outbox: check-ins taken while the server was out of reach ----

  String _localId() {
    final r = math.Random.secure();
    return 'local-${List.generate(16, (_) => r.nextInt(256).toRadixString(16).padLeft(2, '0')).join()}';
  }

  void _queue(String kind, Map<String, dynamic> payload) {
    final items = HereStore.outbox(code)..add({'localId': _localId(), 'kind': kind, 'payload': payload});
    HereStore.saveOutbox(code, items);
    _changed();
  }

  int get pendingCount => HereStore.outbox(code).length;

  Future<void> flushOutbox() async {
    if (_flushing || hostKey == null) return;
    _flushing = true;
    try {
      var items = HereStore.outbox(code);
      while (items.isNotEmpty) {
        final item = items.first;
        final payload = Map<String, dynamic>.from(item['payload'] as Map);
        final r = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': item['kind'], ...payload});
        // Still unreachable, or this device lost its key: keep everything for the next attempt
        // rather than dropping somebody's check-in.
        if (!r.ok && (_failure(r) != null || r.reason == 'not-host')) break;
        if (r.ok) {
          _upsert(r.map['attendee'] as Map);
        } else if (r.reason != 'ended') {
          AppNav.toast('Could not save ${payload['name']}: ${r.error}');
        }
        items = HereStore.outbox(code).where((i) => i['localId'] != item['localId']).toList();
        HereStore.saveOutbox(code, items);
      }
    } finally {
      _flushing = false;
      _changed();
    }
  }

  // ------------------------------------------------------------------ the list

  List<Attendee> displayList() {
    final pending = [
      for (final item in HereStore.outbox(code))
        Attendee(
          id: '${item['localId']}',
          name: '${(item['payload'] as Map)['name'] ?? ''}',
          note: (item['payload'] as Map)['note'] as String?,
          method: item['kind'] == 'record' ? '${(item['payload'] as Map)['method'] ?? 'p2p'}' : 'manual',
          checkedInAt: '${(item['payload'] as Map)['at'] ?? ''}',
          pending: true,
        ),
    ];
    return [...attendees, ...pending]..sort((a, b) => b.checkedInAt.compareTo(a.checkedInAt));
  }

  /// The sync banner's sentence and whether it's a warning, or null for none.
  ({String text, bool warn})? get syncBanner {
    final pending = pendingCount;
    final s = pending == 1 ? '' : 's';
    final waiting = pending > 0 ? ' $pending check-in$s saved on this device will be sent when the connection is back.' : '';
    if (connection == 'offline') return (text: 'Offline. Showing the list from ${formatTime(savedAt)}.$waiting', warn: true);
    if (connection == 'unavailable') {
      return (text: 'Cannot reach uwuHere right now. Showing the list from ${formatTime(savedAt)}.$waiting', warn: true);
    }
    if (pending > 0) return (text: 'Sending $pending saved check-in$s.', warn: false);
    return null;
  }

  String get endedBanner {
    final at = '${event?['endedAt'] ?? ''}';
    final end = parseTime(at);
    final purge = end == null ? '' : formatDateTime(end.add(const Duration(days: purgeAfterEndDays)).toUtc().toIso8601String());
    return 'Ended ${formatDateTime(at)}. The list can be downloaded here until $purge, then it is deleted.';
  }

  String get locationText => event?['hasLocation'] == true
      ? "Location check-in within ${event?['radius']} m of this event's spot."
      : 'Location check-in is on, but no spot is set. Set one in Event settings.';

  // ------------------------------------------------------------------ same wifi

  bool get _wantP2p => event != null && event!['allowP2p'] == true && !ended && hostKey != null;

  void syncP2p() {
    if (_wantP2p && _host == null && _retryTimer == null) _startP2p();
    if (!_wantP2p && (_host != null || _retryTimer != null)) _stopP2p();
    _changed();
  }

  Future<void> _startP2p() async {
    late final P2pHost mine;
    mine = P2pHost(
      maxGuests: 40,
      onStatus: (s) {
        if (_host != mine) return;
        // Something else holds this code: usually this same page a moment ago, while the broker
        // hasn't let the id go yet. The code can't change, so wait and try again a few times.
        if (s.taken && _takenRetries < _maxTakenRetries) {
          _takenRetries += 1;
          _host = null;
          mine.close();
          p2p = const P2pStatus('connecting');
          _retryTimer = Timer(_takenRetryAfter, () {
            _retryTimer = null;
            syncP2p();
          });
          _changed();
          return;
        }
        if (s.status == 'waiting' || s.status == 'connected') _takenRetries = 0;
        p2p = s.taken ? const P2pStatus('error', message: 'This event is already open on another screen. Same-wifi check-ins go to that one.') : s;
        _changed();
        updateWakeLock();
      },
      onMessage: (m, from) => _onPeerMessage(m, from, mine),
    );
    _host = mine;
    p2p = const P2pStatus('connecting');
    _changed();
    try {
      await mine.start(code);
    } catch (_) {
      if (_host != mine) return;
      _host = null;
      p2p = const P2pStatus('error', message: 'Could not load same-wifi check-in. Check your connection.');
      _changed();
    }
  }

  void _stopP2p() {
    _retryTimer?.cancel();
    _retryTimer = null;
    final old = _host;
    _host = null;
    old?.close();
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
        final off = Api.offline.value;
        return StatusRow(off ? 'warn' : '', off ? 'Same-wifi check-in needs a connection to start.' : 'Starting same-wifi check-in.');
      case 'error':
        return StatusRow('error', p2p.message.isEmpty ? 'Same-wifi check-in stopped.' : p2p.message, action: 'Retry', onAction: restartP2p);
      default:
        return StatusRow('', 'Same-wifi check-in is not running.', action: _wantP2p ? 'Retry' : null, onAction: _wantP2p ? restartP2p : null);
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

    final dh = message['deviceHash'];
    final deviceHash = dh is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(dh) ? dh : null;
    final name = cleanLine(message['name'], limitName);
    final note = noteLabel != null ? cleanLine(message['note'] ?? '', limitNote) : '';
    if (deviceHash == null || name == null || name.isEmpty || note == null) {
      return {'type': 'refused', 'reason': 'invalid', 'message': 'That check-in was missing a name.'};
    }

    // Already waiting in the outbox from this device: the same answer again.
    for (final i in HereStore.outbox(code)) {
      if (i['kind'] == 'record' && (i['payload'] as Map)['deviceHash'] == deviceHash) {
        return {'type': 'checked-in', 'at': (i['payload'] as Map)['at']};
      }
    }

    final payload = <String, dynamic>{
      'deviceHash': deviceHash,
      'name': name,
      'note': note.isEmpty ? null : note,
      'at': DateTime.now().toUtc().toIso8601String(),
      'method': method,
    };
    final r = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'record', ...payload});
    if (r.ok) {
      _setConnection('ok');
      final a = r.map['attendee'] as Map;
      _upsert(a);
      _changed();
      return {'type': 'checked-in', 'at': a['checkedInAt']};
    }
    final f = _failure(r);
    if (f != null) {
      _setConnection(f);
      _queue('record', payload);
      return {'type': 'checked-in', 'at': payload['at']};
    }
    return {'type': 'refused', 'reason': r.reason, 'message': r.error};
  }

  // ------------------------------------------------------------------ tapping phones

  bool get _wantTap => event != null && event!['allowTap'] == true && !ended && hostKey != null && Native.has('tap');

  /// Tells the app whether to answer taps, and with which event's key. Asked again with force
  /// when the app comes back, as NFC may have been switched on meanwhile.
  Future<void> syncTap({bool force = false}) async {
    final want = _wantTap;
    if (want == _tapWanted && !force) return;
    _tapWanted = want;
    try {
      final a = await Native.call('Here', 'tap', want ? {'on': true, 'code': code, 'hostKey': hostKey} : {'on': false});
      tapState = '${a?['state'] ?? 'idle'}';
    } catch (_) {
      tapState = want ? 'error' : 'idle';
    }
    _changed();
    updateWakeLock();
  }

  StatusRow? get tapRow {
    if (event == null || event!['allowTap'] != true || ended) return null;
    if (!Native.has('tap')) {
      return StatusRow(
        'warn',
        Native.platform == 'android'
            ? 'Update the uwuHere app to take taps.'
            : 'Tapping phones works in the uwuHere app on an Android phone with NFC. Open this event there.',
      );
    }
    switch (tapState) {
      case 'ready':
        return const StatusRow('ok', 'Ready for taps. People hold their phone against the back of this one.');
      case 'nfc-off':
        return StatusRow(
          'warn',
          'NFC is off on this phone. Turn it on to take taps.',
          action: 'Turn on',
          onAction: () => Native.tryCall('Here', 'openSettings', {'what': 'nfc'}),
        );
      case 'unsupported':
        return const StatusRow('error', "This phone can't take taps: it has no NFC. Open this event in the app on a phone that has it.");
      case 'error':
        return StatusRow('error', "Tapping phones didn't start.", action: 'Retry', onAction: () => syncTap(force: true));
      default:
        return const StatusRow('', 'Starting tap check-in.');
    }
  }

  // ------------------------------------------------------------------ Bluetooth

  bool get _wantBluetooth => event != null && event!['allowBluetooth'] == true && !ended && hostKey != null && Native.has('mesh');

  /// Advertises this event to attendees' apps, or stops. Without `ask` it never shows a permission
  /// prompt by itself: it says "needs-permission", and the row's button asks.
  Future<void> syncBluetooth({bool force = false, bool ask = false}) async {
    final want = _wantBluetooth;
    if (want == _btWanted && !force && !ask) return;
    _btWanted = want;
    try {
      final a = await Native.call('Here', 'bluetooth', want ? {'on': true, 'code': code, 'ask': ask} : {'on': false});
      btState = '${a?['state'] ?? 'idle'}';
      btFailed = '${a?['message'] ?? ''}';
    } catch (_) {
      btState = want ? 'failed' : 'idle';
      btFailed = '';
    }
    _changed();
    updateWakeLock();
  }

  StatusRow? get btRow {
    if (event == null || event!['allowBluetooth'] != true || ended) return null;
    if (Native.platform != 'android') {
      return const StatusRow('warn', 'Bluetooth check-in works with this event open in the uwuHere app on Android.');
    }
    if (!Native.has('mesh')) {
      return const StatusRow('error', 'This phone has no Google Play services, which Bluetooth check-in needs.');
    }
    switch (btState) {
      case 'ready':
        return const StatusRow('ok', 'Ready for Bluetooth. Attendees with the uwuHere app check in phone to phone. Keep this page open.');
      case 'needs-permission':
        return StatusRow('warn', 'Bluetooth check-in needs "Nearby devices" on this phone.', action: 'Allow', onAction: () => syncBluetooth(ask: true));
      case 'denied':
        return StatusRow(
          'error',
          '"Nearby devices" isn\'t allowed for uwuHere. Allow it in the app\'s settings.',
          action: 'Settings',
          onAction: () => Native.tryCall('Here', 'openSettings', {'what': 'app'}),
        );
      case 'bt-off':
        return StatusRow(
          'warn',
          'Bluetooth is off on this phone. Turn it on to take Bluetooth check-ins.',
          action: 'Turn on',
          onAction: () => Native.tryCall('Here', 'openSettings', {'what': 'bluetooth'}),
        );
      case 'failed':
        return StatusRow(
          'error',
          btFailed.isEmpty ? "Bluetooth check-in didn't start." : btFailed,
          action: 'Retry',
          onAction: () => syncBluetooth(force: true),
        );
      default:
        return const StatusRow('', 'Starting Bluetooth check-in.');
    }
  }

  // ------------------------------------------------------------------ the hotspot

  bool get hotspotAvailable => Native.has('hotspot');

  StatusRow? get hotspotRow {
    if (event == null || ended || !hotspotAvailable) return null;
    switch (hotspot['status']) {
      case 'on':
        return StatusRow('ok', 'Hotspot on: ${hotspot['ssid']}. Keep this page open.', action: 'Show codes', onAction: showHotspot);
      case 'starting':
        return const StatusRow('', 'Starting the hotspot.', action: 'Start');
      case 'failed':
        return StatusRow('error', '${hotspot['message'] ?? "The hotspot didn't start."}', action: 'Try again', onAction: startHotspot);
      default:
        return StatusRow('none', 'No internet for attendees? This phone can be their wifi.', action: 'Start', onAction: startHotspot);
    }
  }

  /// WIFI:T:WPA;S:name;P:password;; is what phone cameras read as "join this wifi".
  String get wifiQrText {
    String esc(Object? s) => '${s ?? ''}'.replaceAllMapped(RegExp(r'([\\;,:"])'), (m) => '\\${m[1]}');
    return hotspot['security'] == 'nopass'
        ? 'WIFI:T:nopass;S:${esc(hotspot['ssid'])};;'
        : 'WIFI:T:${hotspot['security'] ?? 'WPA'};S:${esc(hotspot['ssid'])};P:${esc(hotspot['password'])};;';
  }

  void showHotspot() {
    if (hotspot['status'] != 'on') return;
    hotspotSheetOpen.value = true;
    brightness(true);
  }

  Future<void> startHotspot() async {
    if (event == null || ended || hotspot['status'] == 'starting') return;
    hotspot = {'status': 'starting'};
    _changed();
    try {
      final a = await Native.call('Here', 'hotspot', {
        'on': true,
        'code': code,
        'title': title,
        'buttonLabel': event!['buttonLabel'],
        'buttonColor': event!['buttonColor'],
        'noteLabel': noteLabel ?? '',
      });
      hotspot = a?['state'] == 'on' ? {...a!, 'status': 'on'} : {'status': 'failed', 'message': a?['message']};
    } on NativeError catch (e) {
      hotspot = {'status': 'failed', 'message': e.message};
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
        ((_host != null && (p2p.status == 'waiting' || p2p.status == 'connected')) || tapState == 'ready' || btState == 'ready' || hotspot['status'] == 'on') &&
        _resumed &&
        AppPages.active() == AppPages.host;
    if (want == _awake) return;
    _awake = want;
    // Refused (battery saver, a browser without a user's press): the page still works.
    (want ? WakelockPlus.enable() : WakelockPlus.disable()).catchError((Object _) {});
  }

  /// The screen at full brightness while a code is up, so the back of a room can scan it. The
  /// phone's own setting is left alone.
  void brightness(bool max) {
    if (Native.has('brightness')) Native.tryCall('Here', 'brightness', {'max': max});
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
    final err = await mutate(paused ? 'resume' : 'pause', const {}, 'Pausing needs a connection.');
    if (err != null) AppNav.toast(err);
  }

  /// Removes someone: null when done.
  Future<String?> remove(Attendee a) async {
    if (a.pending) {
      HereStore.saveOutbox(code, HereStore.outbox(code).where((i) => i['localId'] != a.id).toList());
      _changed();
      return null;
    }
    return mutate('remove', {'attendeeId': a.id}, 'Removing someone needs a connection.');
  }

  /// Adds someone by hand: true when added or saved for later.
  Future<bool> add(String name, String note) async {
    final payload = {'name': name, 'note': noteLabel != null && note.isNotEmpty ? note : null, 'at': DateTime.now().toUtc().toIso8601String()};
    final r = await Api.post('host', {'code': code, 'hostKey': hostKey, 'action': 'add', ...payload});
    if (r.ok) {
      _setConnection('ok');
      _upsert(r.map['attendee'] as Map);
      _changed();
      return true;
    }
    final f = _failure(r);
    if (f != null) {
      _setConnection(f);
      _queue('add', payload);
      AppNav.toast('Saved on this device. It is sent when the connection is back.');
      return true;
    }
    AppNav.toast(r.error);
    return false;
  }

  /// The list as a CSV, with the byte order mark that makes Excel read it as UTF-8.
  String csv() {
    final rows = <List<Object?>>[
      ['Name', noteLabel ?? 'Note', 'Checked in', 'How', 'Distance (m)', 'Left early'],
    ];
    for (final a in displayList().reversed) {
      rows.add([a.name, a.note ?? '', stamp(a.checkedInAt), methodOf(a.method).label, a.distance ?? '', stamp(a.leftEarlyAt)]);
    }
    return '﻿${rows.map((r) => r.map(csvCell).join(',')).join('\r\n')}';
  }

  String get csvName => 'uwuhere-$code-${stamp(DateTime.now().toUtc().toIso8601String()).substring(0, 10)}.csv';

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
  Future<String?> saveSettings(Map<String, dynamic> settings) => mutate('update', {'settings': settings}, 'Changing settings needs a connection.');

  Future<String?> setPassword(String password) =>
      mutate('password', {'password': password}, password.isEmpty ? 'Removing the password needs a connection.' : 'Setting a password needs a connection.');

  /// Opens the event with its password, on a device that didn't make it: null when open.
  Future<String?> unlock(String password) async {
    final r = await Api.post('unlock', {'code': code, 'password': password});
    if (!r.ok) {
      if (r.reason == 'not-found') {
        _eventGone();
        return null;
      }
      return r.offline ? 'Opening an event here needs a connection.' : r.error;
    }
    hostKey = '${r.map['hostKey']}';
    HereStore.saveHosted(code, hostKey!, Map<String, dynamic>.from(r.map['event'] as Map));
    _applySnapshot(r.map);
    _startPolling();
    return null;
  }

  /// A spot for location check-in, from this device.
  Future<Position2> takeSpot() => Geo.getPosition();

  @override
  void dispose() {
    _disposed = true;
    _offOnline();
    WidgetsBinding.instance.removeObserver(this);
    AppPages.current.removeListener(updateWakeLock);
    _poll?.cancel();
    _retryTimer?.cancel();
    _host?.close();
    _host = null;
    for (final l in _listeners) {
      l.cancel();
    }
    if (_tapWanted) Native.tryCall('Here', 'tap', {'on': false});
    if (_btWanted) Native.tryCall('Here', 'bluetooth', {'on': false});
    if (hotspot['status'] == 'on' || hotspot['status'] == 'starting') Native.tryCall('Here', 'hotspot', {'on': false});
    if (_awake) WakelockPlus.disable().catchError((Object _) {});
    super.dispose();
  }
}
