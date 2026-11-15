// The check-in page's state and what it does (main-site/js/join.js), for one event code.
//
// One big button. Pressing it proves the attendee is near the host, by the first way the event
// allows that works:
//
//   1. Tapping phones. Touching the host's phone hands over a link with a one-time token
//      (api/_lib/tap.js), which Android opens here (the app answers the site's links and NFC
//      tags). It checks in at once with the name already typed. With no connection, the tap is
//      kept on this device and sent once there is one, marked as sent late.
//   2. Bluetooth, only in the Android app: phone to phone with the host's app over Nearby
//      Connections (Mesh.java), no internet needed on either. Asks for "Nearby devices" the
//      first time.
//   3. Same wifi. A direct P2P channel to the host's open page. No permission prompt, and almost
//      always means the same network.
//   4. Location. One reading, sent to the server, which checks the distance and keeps only that.
//
// **Once per device.** A check-in that succeeded is remembered here and the button stays done,
// whatever happens later. The server also refuses a second row from the same device. A failed
// attempt doesn't use the tap up. "I'm leaving early" unlocks after check-in, and works once.
import 'dart:async';

import 'package:flutter/widgets.dart';

import '../../api/api.dart';
import '../../app/nav.dart';
import '../../data/codes.dart';
import '../../data/format.dart';
import '../../data/geo.dart';
import '../../data/here_store.dart';
import '../../native/bridge.dart';
import '../../p2p/here_p2p.dart';

const tapHow = "Hold the top of your phone against the back of the host's phone.";
const _offlineTap = "You're offline. Press the button and your tap is kept, then sent once you're back online.";
const _answerTimeout = Duration(seconds: 12);
const pausedText = 'The host has paused check-ins for now.';
const _unreachable = "Could not reach the host's screen. Join the same wifi as the host, or their phone's hotspot, then try again.";

class Outcome {
  const Outcome({required this.ok, this.at, this.method, this.message = '', this.fallback = true, this.held = false});
  final bool ok;
  final String? at;
  final String? method;
  final String message;
  final bool fallback;
  final bool held;
}

class JoinController extends ChangeNotifier with WidgetsBindingObserver {
  JoinController(this.code, {String? tap}) : tapToken = tap, _autoTap = tap != null {
    WidgetsBinding.instance.addObserver(this);
    _offOnline = Api.onOnline(_online);
    final p = HereStore.profile();
    nameField.text = p.name;
    noteField.text = p.note;
    nameField.addListener(_saveProfile);
    noteField.addListener(_saveProfile);
    attendance = isValidCode(code) ? HereStore.attendance(code) : null;
    _attendSub = HereStore.changes('attend.$code').listen((_) => _otherCheckin());
  }

  final String code;
  String? tapToken;
  bool _autoTap;
  bool _disposed = false;
  late final void Function() _offOnline;

  final nameField = TextEditingController();
  final noteField = TextEditingController();
  StreamSubscription<String?>? _attendSub;

  /// "code", "message" or "checkin" (the site's three views), or "loading".
  String view = 'loading';
  String messageTitle = '';
  String messageText = '';

  /// "another" (try another code), "reload" (try again) or null for none.
  String? messageAction = 'another';

  Map<String, dynamic>? event;
  Map<String, dynamic>? attendance;
  bool busy = false;
  String status = '';

  /// "", "ok" or "error".
  String tone = '';

  /// Set when the name box wants the focus ("Type your name first").
  final ValueNotifier<int> focusName = ValueNotifier(0);

  bool get checkedIn => attendance?['checkedInAt'] != null;
  bool get ended => event?['ended'] == true;
  bool get paused => event?['paused'] == true;
  String? get noteLabel {
    final n = event?['noteLabel'];
    return n is String && n.isNotEmpty ? n : null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void setStatus(String message, [String t = '']) {
    status = message;
    tone = t;
    _changed();
  }

  void _saveProfile() => HereStore.saveProfile(squeeze(nameField.text), squeeze(noteField.text));

  // A check-in made elsewhere on this device, such as a tap that opened the app again.
  void _otherCheckin() {
    final theirs = HereStore.attendance(code);
    if (theirs?['checkedInAt'] == null || checkedIn) return;
    attendance = theirs;
    setStatus("You're checked in.", 'ok');
  }

  // ------------------------------------------------------------------ boot

  void boot() {
    if (!isValidCode(code)) {
      view = 'code';
      _changed();
      return;
    }
    event = HereStore.eventCache(code);
    if (event != null) _showEvent();
    if (tapToken != null && !checkedIn) setStatus('Tapped. Press the button to check in.');
    load();
  }

  /// A new tap on the page already open (the host's phone touched again).
  void takeTap(String token) {
    tapToken = token;
    if (checkedIn || busy) return;
    if (squeeze(nameField.text).isEmpty) {
      setStatus('Tapped. Type your name, then press the button.');
      focusName.value++;
      return;
    }
    checkIn();
  }

  void showMessage(String title, String text, {String? action = 'another'}) {
    messageTitle = title;
    messageText = text;
    messageAction = action;
    view = 'message';
    _changed();
  }

  void _showEvent() {
    if (event == null) return;
    if (ended) {
      final mine = checkedIn
          ? ' You checked in at ${formatTime(attendance!['checkedInAt'] as String?)}'
                '${attendance!['leftEarlyAt'] != null ? ' and left at ${formatTime(attendance!['leftEarlyAt'] as String?)}.' : '.'}'
          : '';
      showMessage('This event has ended', 'Check-ins are closed.$mine', action: null);
      return;
    }
    view = 'checkin';
    // The paused notice comes and goes with the host; any other status stays.
    if (paused && !checkedIn && !busy) {
      status = pausedText;
      tone = '';
    } else if (status == pausedText) {
      status = '';
    }
    _changed();
  }

  /// "Checks that you are here by …", or empty once checked in.
  String get methodNote {
    if (event == null || checkedIn || event!['offlineStub'] == true) return '';
    final ways = <String>[
      if (event!['allowTap'] == true) "tapping your phone on the host's phone",
      if (event!['allowBluetooth'] == true && Native.has('mesh')) 'Bluetooth, phone to phone with the host',
      if (event!['allowP2p'] == true) 'being on the same wifi as the host',
      if (event!['allowLocation'] == true) 'being within ${event!['radius']} m of the host (your location is used once, and only the distance is kept)',
    ];
    return 'Checks that you are here by ${ways.join(', or by ')}.';
  }

  /// The server's record fills in what this device doesn't know, such as a check-in made before
  /// its data was cleared. It never unlocks the button: a host removing somebody doesn't hand them
  /// a second tap.
  void _reconcile(Object? me) {
    if (me is! Map) return;
    attendance = {
      ...?attendance,
      'checkedInAt': attendance?['checkedInAt'] ?? me['checkedInAt'],
      'leftEarlyAt': me['leftEarlyAt'] ?? attendance?['leftEarlyAt'],
    };
    HereStore.saveAttendance(code, attendance);
  }

  Future<void> load() async {
    final r = await Api.call('event?code=$code', headers: {'X-Uwuhere-Device': HereStore.deviceId()});
    if (_disposed) return;
    if (r.ok) {
      final data = Map<String, dynamic>.from(r.map);
      final me = data.remove('me');
      event = data;
      HereStore.saveEventCache(code, event);
      _reconcile(me);
      _showEvent();
      sendHeldTap();
      _runAutoTap();
      return;
    }
    if (r.reason == 'not-found') {
      HereStore.saveEventCache(code, null);
      event = null;
      showMessage('No event with that code', "Check the code on the host's screen and try again.");
      return;
    }
    if (event != null) {
      // A cached copy is on screen already; say why it may be out of date.
      if (r.offline && !busy && !checkedIn) {
        setStatus(tapToken != null ? _offlineTap : "You're offline. Checking in needs a connection.");
      }
      if (r.offline) _runAutoTap();
      return;
    }
    // Opened by a tap with no connection, at an event this device hasn't seen, or with Bluetooth,
    // which needs no connection: enough of a page to take the name and check in.
    if (r.offline && (tapToken != null || Native.has('mesh'))) {
      event = {
        'code': code,
        'title': '',
        'buttonLabel': "I'm here",
        'buttonColor': '#ccffcc',
        'noteLabel': null,
        'allowTap': tapToken != null,
        'allowBluetooth': Native.has('mesh'),
        'allowP2p': false,
        'allowLocation': false,
        'radius': 0,
        'paused': false,
        'ended': false,
        'offlineStub': true,
      };
      _showEvent();
      setStatus(tapToken != null ? _offlineTap : "You're offline. Press the button to check in by Bluetooth with the host's phone.");
      _runAutoTap();
      return;
    }
    if (r.offline) {
      showMessage("You're offline", 'Connect to the internet, then try again.', action: 'reload');
      return;
    }
    showMessage('Something went wrong', r.error, action: 'reload');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from another app: the host may have paused or ended meanwhile.
    if (state == AppLifecycleState.resumed && event != null && !busy) load();
  }

  void _online() {
    if (!_disposed) sendHeldTap();
  }

  // ------------------------------------------------------------------ checking in

  /// The time a tap token says it was made, from its first part.
  static String tapTime(String token) {
    final s = int.tryParse(token.split('.').first);
    return (s != null && s > 0 ? DateTime.fromMillisecondsSinceEpoch(s * 1000, isUtc: true) : DateTime.now().toUtc()).toIso8601String();
  }

  Future<Outcome> _viaP2p(String name, String note) {
    final done = Completer<Outcome>();
    Timer? answerTimer;
    late final P2pGuest guest;
    void finish(Outcome o) {
      if (done.isCompleted) return;
      answerTimer?.cancel();
      // Leaving on purpose sends bye; a failure just hangs up.
      if (o.ok) {
        guest.leave();
      } else {
        guest.close();
      }
      done.complete(o);
    }

    guest = P2pGuest(
      onStatus: (s) {
        switch (s.status) {
          case 'connected':
            setStatus('Found the host. Checking you in.');
            guest.send({'type': 'checkin', 'v': protocolVersion, 'deviceHash': HereStore.deviceHash(), 'name': name, 'note': note.isEmpty ? null : note});
            answerTimer = Timer(_answerTimeout, () => finish(const Outcome(ok: false, message: "The host's screen did not answer. Try again.")));
          case 'unreachable':
            finish(const Outcome(ok: false, message: _unreachable));
          case 'dropped':
            finish(const Outcome(ok: false, message: 'The connection to the host dropped. Try again.'));
          case 'error':
            finish(Outcome(ok: false, message: s.type == 'peer-unavailable' ? '${s.message} Ask the host to open their page.' : s.message));
        }
      },
      onMessage: (m) {
        if (m['type'] == 'checked-in') {
          final at = m['at'] is String && DateTime.tryParse(m['at'] as String) != null ? m['at'] as String : DateTime.now().toUtc().toIso8601String();
          finish(Outcome(ok: true, at: at, method: 'p2p'));
        } else if (m['type'] == 'refused') {
          final reason = m['reason'] is String ? m['reason'] as String : '';
          if (reason == 'paused') event?['paused'] = true;
          if (reason == 'ended') event?['ended'] = true;
          final msg = m['message'] is String ? m['message'] as String : 'The host could not check you in.';
          finish(
            Outcome(
              ok: false,
              // Shown as it is, but capped: it came from another device.
              message: msg.length > 200 ? msg.substring(0, 200) : msg,
              // These would fail by location just the same.
              fallback: !const ['paused', 'ended', 'version', 'invalid'].contains(reason),
            ),
          );
        } else if (m['type'] == 'full') {
          finish(const Outcome(ok: false, message: "The host's screen is busy. Try again in a moment."));
        }
      },
    );
    guest.connect(code).catchError((Object _) => finish(const Outcome(ok: false, message: 'Could not load same-wifi check-in. Check your connection.')));
    return done.future;
  }

  Future<Outcome> _viaTap(String name, String note) async {
    setStatus('Checking you in with the tap.');
    final token = tapToken!;
    final r = await Api.post('checkin', {'code': code, 'deviceId': HereStore.deviceId(), 'name': name, 'note': note.isEmpty ? null : note, 'tap': token});
    if (r.ok) return Outcome(ok: true, at: '${(r.map['attendee'] as Map)['checkedInAt']}', method: 'tap');
    // No connection: the tap is kept, and sent when there is one.
    if (r.offline) {
      final held = {'token': token, 'name': name, 'note': note.isEmpty ? null : note, 'tappedAt': tapTime(token)};
      HereStore.saveHeldTap(code, held);
      tapToken = null;
      return Outcome(ok: true, held: true, at: held['tappedAt'], method: 'tap');
    }
    // Spent, stale or broken: no use trying it again.
    if (const ['tap-bad', 'tap-old', 'tap-used'].contains(r.reason)) tapToken = null;
    if (r.reason == 'ended') event?['ended'] = true;
    if (r.reason == 'paused') event?['paused'] = true;
    return Outcome(ok: false, message: r.error, fallback: !const ['ended', 'paused', 'invalid'].contains(r.reason));
  }

  bool _sendingHeld = false;

  /// A tap kept while offline, sent now if there's a connection.
  Future<void> sendHeldTap() async {
    final held = HereStore.heldTap(code);
    if (held == null || _sendingHeld) return;
    _sendingHeld = true;
    try {
      final r = await Api.post('checkin', {
        'code': code,
        'deviceId': HereStore.deviceId(),
        'name': held['name'],
        'note': held['note'],
        'tap': held['token'],
        'late': true,
      });
      if (r.offline) return;
      HereStore.saveHeldTap(code, null);
      final when = formatTime(held['tappedAt'] as String?);
      if (r.ok) {
        attendance = {...?attendance, 'checkedInAt': (r.map['attendee'] as Map)['checkedInAt'], 'held': false, 'name': held['name']};
        HereStore.saveAttendance(code, attendance);
        setStatus("Your tap from $when was sent. You're checked in.", 'ok');
      } else {
        // Refused for good, such as an event that ended meanwhile: the button is free again,
        // unless this device checked in some other way.
        if (attendance?['held'] == true) {
          attendance = null;
          HereStore.saveAttendance(code, null);
        }
        if (r.reason == 'ended') event?['ended'] = true;
        setStatus("Your tap from $when couldn't be sent: ${r.error}", 'error');
      }
      _showEvent();
    } finally {
      _sendingHeld = false;
    }
  }

  // Opened by a tap: check in by itself if the name is already filled in.
  void _runAutoTap() {
    if (!_autoTap || event == null) return;
    _autoTap = false;
    if (squeeze(nameField.text).isNotEmpty && event!['allowTap'] == true && !checkedIn) checkIn();
  }

  Future<Outcome> _viaMesh(String name, String note) async {
    setStatus("Looking for the host's phone by Bluetooth.");
    Map<String, dynamic>? a;
    try {
      a = await Native.call('Here', 'meshCheckIn', {'code': code, 'name': name, 'note': note.isEmpty ? null : note, 'deviceHash': HereStore.deviceHash()});
    } on NativeError catch (e) {
      return Outcome(ok: false, message: e.message.isEmpty ? "Bluetooth check-in didn't work. Try again." : e.message);
    }
    if (a?['ok'] == true) {
      final at = a!['at'] is String && DateTime.tryParse(a['at'] as String) != null ? a['at'] as String : DateTime.now().toUtc().toIso8601String();
      return Outcome(ok: true, at: at, method: 'mesh');
    }
    if (a?['reason'] == 'refused' && RegExp('paused', caseSensitive: false).hasMatch('${a?['message'] ?? ''}')) event?['paused'] = true;
    return Outcome(
      ok: false,
      message: '${a?['message'] ?? "Bluetooth check-in didn't work. Try again."}',
      // Refused by the host: the other ways would be refused too.
      fallback: a?['reason'] != 'refused',
    );
  }

  Future<Outcome> _viaLocation(String name, String note) async {
    Position2 position;
    try {
      position = await Geo.getPosition();
    } on GeoError catch (e) {
      return Outcome(ok: false, message: e.message);
    }
    setStatus('Checking your distance from the host.');
    final r = await Api.post('checkin', {
      'code': code,
      'deviceId': HereStore.deviceId(),
      'name': name,
      'note': note.isEmpty ? null : note,
      'position': position.toJson(),
    });
    if (r.ok) return Outcome(ok: true, at: '${(r.map['attendee'] as Map)['checkedInAt']}', method: 'location');
    if (r.reason == 'ended') event?['ended'] = true;
    if (r.reason == 'paused') event?['paused'] = true;
    return Outcome(ok: false, message: r.offline ? "You're offline. Checking in needs a connection." : r.error);
  }

  Future<void> checkIn() async {
    if (busy || event == null || ended || checkedIn) return;
    if (paused) return setStatus(pausedText);

    final name = squeeze(nameField.text);
    final note = noteLabel != null ? squeeze(noteField.text) : '';
    if (name.isEmpty) {
      setStatus('Type your name first.', 'error');
      focusName.value++;
      return;
    }
    if (charCount(name) > 60) return setStatus('Your name can be at most 60 characters.', 'error');
    if (charCount(note) > 120) return setStatus('$noteLabel can be at most 120 characters.', 'error');
    // No way in that works here: Bluetooth needs the app, and a tap the phone.
    final bluetoothHere = event!['allowBluetooth'] == true && Native.has('mesh');
    if (event!['allowP2p'] != true && event!['allowLocation'] != true && !bluetoothHere && !(event!['allowTap'] == true && tapToken != null)) {
      if (event!['allowTap'] == true) return setStatus(tapHow);
      return setStatus('This event checks people in by Bluetooth with the uwuHere app for Android. Install it, or ask the host.', 'error');
    }
    HereStore.saveProfile(name, note);

    busy = true;
    _changed();
    try {
      var o = const Outcome(ok: false);
      if (event!['allowTap'] == true && tapToken != null) o = await _viaTap(name, note);
      if (!o.ok && bluetoothHere && o.fallback && !ended) o = await _viaMesh(name, note);
      if (!o.ok && event!['allowP2p'] == true && o.fallback && !ended) {
        setStatus("Looking for the host's screen on this wifi.");
        o = await _viaP2p(name, note);
      }
      if (!o.ok && event!['allowLocation'] == true && o.fallback && !ended) {
        setStatus(event!['allowP2p'] == true ? "Not on the host's wifi. Checking your location instead." : 'Checking your location.');
        o = await _viaLocation(name, note);
      }
      if (o.ok) {
        attendance = {'checkedInAt': o.at, 'method': o.method, 'leftEarlyAt': null, 'name': name, 'held': o.held};
        HereStore.saveAttendance(code, attendance);
        setStatus(o.held ? "Tap kept. It's sent as soon as this phone is back online." : "You're checked in.", 'ok');
      } else {
        setStatus(o.message.isEmpty ? 'Could not check you in. Try again.' : o.message, 'error');
      }
    } finally {
      busy = false;
      _showEvent();
    }
  }

  /// Leaving early: null when done, else what to say.
  Future<String?> leave() async {
    final r = await Api.post('leave', {'code': code, 'deviceId': HereStore.deviceId()});
    if (!r.ok) {
      if (r.reason == 'ended') {
        event?['ended'] = true;
        _showEvent();
        return '';
      }
      return r.offline ? "You're offline. Leaving early needs a connection." : r.error;
    }
    attendance = {...?attendance, 'leftEarlyAt': (r.map['attendee'] as Map)['leftEarlyAt']};
    HereStore.saveAttendance(code, attendance);
    _showEvent();
    AppNav.toast('The host can see you left early');
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _offOnline();
    WidgetsBinding.instance.removeObserver(this);
    _attendSub?.cancel();
    nameField.dispose();
    noteField.dispose();
    super.dispose();
  }
}
