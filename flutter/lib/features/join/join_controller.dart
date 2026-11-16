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

const tapInstructions = "Hold the top of your phone against the back of the host's phone.";
const _offlineTapText = "You're offline. Press the button and your tap is kept, then sent once you're back online.";
const _answerTimeout = Duration(seconds: 12);
const pausedText = 'The host has paused check-ins for now.';
const _unreachableText = "Could not reach the host's screen. Join the same wifi as the host, or their phone's hotspot, then try again.";

/// How one way of checking in went.
class Outcome {
  const Outcome({
    required this.succeeded,
    this.checkedInAt,
    this.method,
    this.message = '',
    this.tryOtherWays = true,
    this.held = false,
  });

  /// True when this way checked the attendee in (or kept their tap to send later).
  final bool succeeded;

  /// When they were checked in, as an ISO 8601 time.
  final String? checkedInAt;

  /// Which way worked: "tap", "mesh", "p2p" or "location".
  final String? method;

  /// What to tell the attendee when it failed.
  final String message;

  /// False when the next way would be refused just the same, so there's no point trying it.
  final bool tryOtherWays;

  /// True when the tap was kept on this device because there was no connection.
  final bool held;
}

/// Everything the check-in page knows and does for one event code. The page listens to it and
/// redraws whenever it changes.
class JoinController extends ChangeNotifier with WidgetsBindingObserver {
  JoinController(this.code, {this.tapToken}) : _automaticTapPending = tapToken != null {
    WidgetsBinding.instance.addObserver(this);
    _stopListeningForOnline = Api.onOnline(_onBackOnline);
    final profile = HereStore.profile();
    nameField.text = profile.name;
    noteField.text = profile.note;
    nameField.addListener(_saveProfile);
    noteField.addListener(_saveProfile);
    if (isValidCode(code)) {
      attendance = HereStore.attendance(code);
    } else {
      attendance = null;
    }
    _attendanceSubscription = HereStore.changes('attend.$code').listen((_) {
      _otherCheckin();
    });
  }

  final String code;
  String? tapToken;

  /// True when the page was opened by a tap and hasn't yet tried checking in by itself.
  bool _automaticTapPending;
  bool _disposed = false;
  late final void Function() _stopListeningForOnline;

  final nameField = TextEditingController();
  final noteField = TextEditingController();
  StreamSubscription<String?>? _attendanceSubscription;

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

  /// One value from the event, or null when there's no event yet.
  dynamic _eventField(String key) {
    final currentEvent = event;
    if (currentEvent == null) {
      return null;
    }
    return currentEvent[key];
  }

  /// Sets one of the event's flags (such as "paused" or "ended") to true, if there is an event.
  void _setEventFlag(String key) {
    final currentEvent = event;
    if (currentEvent != null) {
      currentEvent[key] = true;
    }
  }

  /// One value from this device's check-in record, or null when there's no record.
  dynamic _attendanceField(String key) {
    final currentAttendance = attendance;
    if (currentAttendance == null) {
      return null;
    }
    return currentAttendance[key];
  }

  /// This device's check-in record so far, or an empty one when there's none.
  Map<String, dynamic> _attendanceSoFar() {
    final currentAttendance = attendance;
    if (currentAttendance == null) {
      return <String, dynamic>{};
    }
    return currentAttendance;
  }

  /// The note as it's sent: null when it's empty.
  static String? _noteOrNull(String note) {
    if (note.isEmpty) {
      return null;
    }
    return note;
  }

  /// The time the host's device sent, when it's a real time, else now.
  static String _sentTimeOrNow(Object? sentTime) {
    if (sentTime is String && DateTime.tryParse(sentTime) != null) {
      return sentTime;
    }
    return DateTime.now().toUtc().toIso8601String();
  }

  bool get checkedIn {
    return _attendanceField('checkedInAt') != null;
  }

  bool get ended {
    return _eventField('ended') == true;
  }

  bool get paused {
    return _eventField('paused') == true;
  }

  String? get noteLabel {
    final label = _eventField('noteLabel');
    if (label is String && label.isNotEmpty) {
      return label;
    }
    return null;
  }

  void _changed() {
    if (!_disposed) notifyListeners();
  }

  void setStatus(String message, [String newTone = '']) {
    status = message;
    tone = newTone;
    _changed();
  }

  void _saveProfile() {
    HereStore.saveProfile(squeeze(nameField.text), squeeze(noteField.text));
  }

  // A check-in made elsewhere on this device, such as a tap that opened the app again.
  void _otherCheckin() {
    final theirs = HereStore.attendance(code);
    if (theirs == null || theirs['checkedInAt'] == null || checkedIn) return;
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
      focusName.value = focusName.value + 1;
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

  /// Shows the event: a message once it has ended (with this device's times, if it checked in),
  /// else the check-in view, with the paused notice when the host has paused it.
  void _showEvent() {
    if (event == null) return;
    if (ended) {
      String yourTimes = '';
      if (checkedIn) {
        final currentAttendance = attendance!;
        final checkedInText = ' You checked in at ${formatTime(currentAttendance['checkedInAt'] as String?)}';
        String leftText;
        if (currentAttendance['leftEarlyAt'] != null) {
          leftText = ' and left at ${formatTime(currentAttendance['leftEarlyAt'] as String?)}.';
        } else {
          leftText = '.';
        }
        yourTimes = '$checkedInText$leftText';
      }
      showMessage('This event has ended', 'Check-ins are closed.$yourTimes', action: null);
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
  void _reconcile(Object? serverRecord) {
    if (serverRecord is! Map) return;
    // This device's check-in time wins; the server's leaving time wins.
    var checkedInAt = _attendanceField('checkedInAt');
    if (checkedInAt == null) {
      checkedInAt = serverRecord['checkedInAt'];
    }
    var leftEarlyAt = serverRecord['leftEarlyAt'];
    if (leftEarlyAt == null) {
      leftEarlyAt = _attendanceField('leftEarlyAt');
    }
    attendance = {
      ..._attendanceSoFar(),
      'checkedInAt': checkedInAt,
      'leftEarlyAt': leftEarlyAt,
    };
    HereStore.saveAttendance(code, attendance);
  }

  /// Fetches the event from the server and shows it. Without a connection it keeps the cached
  /// copy on screen, or makes a bare page that can still check in by tap or Bluetooth.
  Future<void> load() async {
    final response = await Api.call('event?code=$code', headers: {'X-Uwuhere-Device': HereStore.deviceId()});
    if (_disposed) return;
    if (response.ok) {
      final data = Map<String, dynamic>.from(response.map);
      final serverRecord = data.remove('me');
      event = data;
      HereStore.saveEventCache(code, event);
      _reconcile(serverRecord);
      _showEvent();
      sendHeldTap();
      _runAutomaticTap();
      return;
    }
    if (response.reason == 'not-found') {
      HereStore.saveEventCache(code, null);
      event = null;
      showMessage('No event with that code', "Check the code on the host's screen and try again.");
      return;
    }
    if (event != null) {
      // A cached copy is on screen already; say why it may be out of date.
      if (response.offline && !busy && !checkedIn) {
        if (tapToken != null) {
          setStatus(_offlineTapText);
        } else {
          setStatus("You're offline. Checking in needs a connection.");
        }
      }
      if (response.offline) _runAutomaticTap();
      return;
    }
    // Opened by a tap with no connection, at an event this device hasn't seen, or with Bluetooth,
    // which needs no connection: enough of a page to take the name and check in.
    if (response.offline && (tapToken != null || Native.has('mesh'))) {
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
      if (tapToken != null) {
        setStatus(_offlineTapText);
      } else {
        setStatus("You're offline. Press the button to check in by Bluetooth with the host's phone.");
      }
      _runAutomaticTap();
      return;
    }
    if (response.offline) {
      showMessage("You're offline", 'Connect to the internet, then try again.', action: 'reload');
      return;
    }
    showMessage('Something went wrong', response.error, action: 'reload');
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Back from another app: the host may have paused or ended meanwhile.
    if (state == AppLifecycleState.resumed && event != null && !busy) load();
  }

  void _onBackOnline() {
    if (!_disposed) sendHeldTap();
  }

  // ------------------------------------------------------------------ checking in

  /// The time a tap token says it was made, from its first part.
  static String tapTime(String token) {
    final seconds = int.tryParse(token.split('.').first);
    DateTime madeAt;
    if (seconds != null && seconds > 0) {
      madeAt = DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
    } else {
      madeAt = DateTime.now().toUtc();
    }
    return madeAt.toIso8601String();
  }

  /// Checks in over a direct P2P channel to the host's open page, on the same wifi. Finishes when
  /// the host answers, refuses, the connection fails, or the host takes too long to answer.
  Future<Outcome> _viaP2p(String name, String note) {
    final done = Completer<Outcome>();
    Timer? answerTimer;
    late final P2pGuest guest;
    void finish(Outcome outcome) {
      if (done.isCompleted) return;
      final timer = answerTimer;
      if (timer != null) {
        timer.cancel();
      }
      // Leaving on purpose sends bye; a failure just hangs up.
      if (outcome.succeeded) {
        guest.leave();
      } else {
        guest.close();
      }
      done.complete(outcome);
    }

    guest = P2pGuest(
      onStatus: (statusUpdate) {
        switch (statusUpdate.status) {
          case 'connected':
            setStatus('Found the host. Checking you in.');
            guest.send({'type': 'checkin', 'v': protocolVersion, 'deviceHash': HereStore.deviceHash(), 'name': name, 'note': _noteOrNull(note)});
            answerTimer = Timer(_answerTimeout, () {
              finish(const Outcome(succeeded: false, message: "The host's screen did not answer. Try again."));
            });
          case 'unreachable':
            finish(const Outcome(succeeded: false, message: _unreachableText));
          case 'dropped':
            finish(const Outcome(succeeded: false, message: 'The connection to the host dropped. Try again.'));
          case 'error':
            {
              String errorText;
              if (statusUpdate.type == 'peer-unavailable') {
                errorText = '${statusUpdate.message} Ask the host to open their page.';
              } else {
                errorText = statusUpdate.message;
              }
              finish(Outcome(succeeded: false, message: errorText));
            }
        }
      },
      onMessage: (incoming) {
        if (incoming['type'] == 'checked-in') {
          final checkedInAt = _sentTimeOrNow(incoming['at']);
          finish(Outcome(succeeded: true, checkedInAt: checkedInAt, method: 'p2p'));
        } else if (incoming['type'] == 'refused') {
          String reason = '';
          if (incoming['reason'] is String) {
            reason = incoming['reason'] as String;
          }
          if (reason == 'paused') _setEventFlag('paused');
          if (reason == 'ended') _setEventFlag('ended');
          String hostMessage = 'The host could not check you in.';
          if (incoming['message'] is String) {
            hostMessage = incoming['message'] as String;
          }
          // Shown as it is, but capped: it came from another device.
          if (hostMessage.length > 200) {
            hostMessage = hostMessage.substring(0, 200);
          }
          finish(
            Outcome(
              succeeded: false,
              message: hostMessage,
              // These would fail by location just the same.
              tryOtherWays: !const ['paused', 'ended', 'version', 'invalid'].contains(reason),
            ),
          );
        } else if (incoming['type'] == 'full') {
          finish(const Outcome(succeeded: false, message: "The host's screen is busy. Try again in a moment."));
        }
      },
    );
    guest.connect(code).catchError((Object _) {
      finish(const Outcome(succeeded: false, message: 'Could not load same-wifi check-in. Check your connection.'));
    });
    return done.future;
  }

  /// Checks in with the tap's one-time token. With no connection the tap is kept on this device
  /// and counts as done; it's sent later by [sendHeldTap].
  Future<Outcome> _viaTap(String name, String note) async {
    setStatus('Checking you in with the tap.');
    final token = tapToken!;
    final response = await Api.post('checkin', {'code': code, 'deviceId': HereStore.deviceId(), 'name': name, 'note': _noteOrNull(note), 'tap': token});
    if (response.ok) {
      return Outcome(succeeded: true, checkedInAt: '${(response.map['attendee'] as Map)['checkedInAt']}', method: 'tap');
    }
    // No connection: the tap is kept, and sent when there is one.
    if (response.offline) {
      final held = {'token': token, 'name': name, 'note': _noteOrNull(note), 'tappedAt': tapTime(token)};
      HereStore.saveHeldTap(code, held);
      tapToken = null;
      return Outcome(succeeded: true, held: true, checkedInAt: held['tappedAt'], method: 'tap');
    }
    // Spent, stale or broken: no use trying it again.
    if (const ['tap-bad', 'tap-old', 'tap-used'].contains(response.reason)) tapToken = null;
    if (response.reason == 'ended') _setEventFlag('ended');
    if (response.reason == 'paused') _setEventFlag('paused');
    return Outcome(succeeded: false, message: response.error, tryOtherWays: !const ['ended', 'paused', 'invalid'].contains(response.reason));
  }

  bool _sendingHeldTap = false;

  /// A tap kept while offline, sent now if there's a connection.
  Future<void> sendHeldTap() async {
    final held = HereStore.heldTap(code);
    if (held == null || _sendingHeldTap) return;
    _sendingHeldTap = true;
    try {
      final response = await Api.post('checkin', {
        'code': code,
        'deviceId': HereStore.deviceId(),
        'name': held['name'],
        'note': held['note'],
        'tap': held['token'],
        'late': true,
      });
      if (response.offline) return;
      HereStore.saveHeldTap(code, null);
      final tappedAtText = formatTime(held['tappedAt'] as String?);
      if (response.ok) {
        attendance = {
          ..._attendanceSoFar(),
          'checkedInAt': (response.map['attendee'] as Map)['checkedInAt'],
          'held': false,
          'name': held['name'],
        };
        HereStore.saveAttendance(code, attendance);
        setStatus("Your tap from $tappedAtText was sent. You're checked in.", 'ok');
      } else {
        // Refused for good, such as an event that ended meanwhile: the button is free again,
        // unless this device checked in some other way.
        if (_attendanceField('held') == true) {
          attendance = null;
          HereStore.saveAttendance(code, null);
        }
        if (response.reason == 'ended') _setEventFlag('ended');
        setStatus("Your tap from $tappedAtText couldn't be sent: ${response.error}", 'error');
      }
      _showEvent();
    } finally {
      _sendingHeldTap = false;
    }
  }

  // Opened by a tap: check in by itself if the name is already filled in.
  void _runAutomaticTap() {
    if (!_automaticTapPending || event == null) return;
    _automaticTapPending = false;
    if (squeeze(nameField.text).isNotEmpty && event!['allowTap'] == true && !checkedIn) checkIn();
  }

  /// Checks in by Bluetooth, phone to phone with the host's app (only in the Android app).
  Future<Outcome> _viaMesh(String name, String note) async {
    setStatus("Looking for the host's phone by Bluetooth.");
    Map<String, dynamic>? answer;
    try {
      answer = await Native.call('Here', 'meshCheckIn', {'code': code, 'name': name, 'note': _noteOrNull(note), 'deviceHash': HereStore.deviceHash()});
    } on NativeError catch (error) {
      String failureText;
      if (error.message.isEmpty) {
        failureText = "Bluetooth check-in didn't work. Try again.";
      } else {
        failureText = error.message;
      }
      return Outcome(succeeded: false, message: failureText);
    }
    // No answer at all reads the same as an empty one.
    Map<String, dynamic> answerFields = <String, dynamic>{};
    if (answer != null) {
      answerFields = answer;
    }
    if (answerFields['ok'] == true) {
      final checkedInAt = _sentTimeOrNow(answerFields['at']);
      return Outcome(succeeded: true, checkedInAt: checkedInAt, method: 'mesh');
    }
    final hostMessage = answerFields['message'];
    String hostMessageText = '';
    if (hostMessage != null) {
      hostMessageText = '$hostMessage';
    }
    if (answerFields['reason'] == 'refused' && RegExp('paused', caseSensitive: false).hasMatch(hostMessageText)) {
      _setEventFlag('paused');
    }
    String failureText = "Bluetooth check-in didn't work. Try again.";
    if (hostMessage != null) {
      failureText = '$hostMessage';
    }
    return Outcome(
      succeeded: false,
      message: failureText,
      // Refused by the host: the other ways would be refused too.
      tryOtherWays: answerFields['reason'] != 'refused',
    );
  }

  /// Checks in by location: one reading, sent to the server, which checks the distance.
  Future<Outcome> _viaLocation(String name, String note) async {
    Position2 position;
    try {
      position = await Geo.getPosition();
    } on GeoError catch (error) {
      return Outcome(succeeded: false, message: error.message);
    }
    setStatus('Checking your distance from the host.');
    final response = await Api.post('checkin', {
      'code': code,
      'deviceId': HereStore.deviceId(),
      'name': name,
      'note': _noteOrNull(note),
      'position': position.toJson(),
    });
    if (response.ok) {
      return Outcome(succeeded: true, checkedInAt: '${(response.map['attendee'] as Map)['checkedInAt']}', method: 'location');
    }
    if (response.reason == 'ended') _setEventFlag('ended');
    if (response.reason == 'paused') _setEventFlag('paused');
    if (response.offline) {
      return const Outcome(succeeded: false, message: "You're offline. Checking in needs a connection.");
    }
    return Outcome(succeeded: false, message: response.error);
  }

  /// The big button: checks the name and note, then tries each way the event allows in turn
  /// (tap, Bluetooth, same wifi, location) until one works or one says the rest would fail too.
  Future<void> checkIn() async {
    if (busy || event == null || ended || checkedIn) return;
    if (paused) {
      setStatus(pausedText);
      return;
    }

    final name = squeeze(nameField.text);
    String note = '';
    if (noteLabel != null) {
      note = squeeze(noteField.text);
    }
    if (name.isEmpty) {
      setStatus('Type your name first.', 'error');
      focusName.value = focusName.value + 1;
      return;
    }
    if (charCount(name) > 60) {
      setStatus('Your name can be at most 60 characters.', 'error');
      return;
    }
    if (charCount(note) > 120) {
      setStatus('$noteLabel can be at most 120 characters.', 'error');
      return;
    }
    // No way in that works here: Bluetooth needs the app, and a tap the phone.
    final bluetoothHere = event!['allowBluetooth'] == true && Native.has('mesh');
    if (event!['allowP2p'] != true && event!['allowLocation'] != true && !bluetoothHere && !(event!['allowTap'] == true && tapToken != null)) {
      if (event!['allowTap'] == true) {
        setStatus(tapInstructions);
        return;
      }
      setStatus('This event checks people in by Bluetooth with the uwuHere app for Android. Install it, or ask the host.', 'error');
      return;
    }
    HereStore.saveProfile(name, note);

    busy = true;
    _changed();
    try {
      var outcome = const Outcome(succeeded: false);
      if (event!['allowTap'] == true && tapToken != null) {
        outcome = await _viaTap(name, note);
      }
      if (!outcome.succeeded && bluetoothHere && outcome.tryOtherWays && !ended) {
        outcome = await _viaMesh(name, note);
      }
      if (!outcome.succeeded && event!['allowP2p'] == true && outcome.tryOtherWays && !ended) {
        setStatus("Looking for the host's screen on this wifi.");
        outcome = await _viaP2p(name, note);
      }
      if (!outcome.succeeded && event!['allowLocation'] == true && outcome.tryOtherWays && !ended) {
        if (event!['allowP2p'] == true) {
          setStatus("Not on the host's wifi. Checking your location instead.");
        } else {
          setStatus('Checking your location.');
        }
        outcome = await _viaLocation(name, note);
      }
      if (outcome.succeeded) {
        attendance = {'checkedInAt': outcome.checkedInAt, 'method': outcome.method, 'leftEarlyAt': null, 'name': name, 'held': outcome.held};
        HereStore.saveAttendance(code, attendance);
        if (outcome.held) {
          setStatus("Tap kept. It's sent as soon as this phone is back online.", 'ok');
        } else {
          setStatus("You're checked in.", 'ok');
        }
      } else {
        if (outcome.message.isEmpty) {
          setStatus('Could not check you in. Try again.', 'error');
        } else {
          setStatus(outcome.message, 'error');
        }
      }
    } finally {
      busy = false;
      _showEvent();
    }
  }

  /// Leaving early: null when done, else what to say.
  Future<String?> leave() async {
    final response = await Api.post('leave', {'code': code, 'deviceId': HereStore.deviceId()});
    if (!response.ok) {
      if (response.reason == 'ended') {
        _setEventFlag('ended');
        _showEvent();
        return '';
      }
      if (response.offline) {
        return "You're offline. Leaving early needs a connection.";
      }
      return response.error;
    }
    attendance = {..._attendanceSoFar(), 'leftEarlyAt': (response.map['attendee'] as Map)['leftEarlyAt']};
    HereStore.saveAttendance(code, attendance);
    _showEvent();
    AppNav.toast('The host can see you left early');
    return null;
  }

  @override
  void dispose() {
    _disposed = true;
    _stopListeningForOnline();
    WidgetsBinding.instance.removeObserver(this);
    final subscription = _attendanceSubscription;
    if (subscription != null) {
      subscription.cancel();
    }
    nameField.dispose();
    noteField.dispose();
    super.dispose();
  }
}
