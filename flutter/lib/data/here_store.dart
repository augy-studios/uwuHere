// Everything uwuHere keeps, under the site's "uwuhere." keys and in its JSON shapes
// (main-site/js/store.js), so what the old WebView app kept comes across as it was (migrate.dart)
// and a host's events are still theirs:
//
//   uwuhere.deviceId        this device's random check-in id
//   uwuhere.profile         the name (and note) last typed, to prefill
//   uwuhere.hosted          events this device manages: code -> { hostKey, title, createdAt, ended }
//   uwuhere.host.CODE       the host page's last copy of an event and list
//   uwuhere.outbox.CODE     host changes made offline, waiting to be sent
//   uwuhere.event.CODE      the attendee page's last copy of an event
//   uwuhere.attend.CODE     this device's own check-in to an event
//   uwuhere.heldtap.CODE    a tap made with no connection, to send later
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';

import 'store.dart';

/// How long the server keeps an event, repeated from migrations/0002_uwuhere_purge.sql for the
/// words on screen; change together.
const purgeAfterEndDays = 7;
const purgeUnendedDays = 30;

const _prefix = 'uwuhere.';

class HostedEvent {
  const HostedEvent({required this.code, required this.hostKey, required this.title, required this.createdAt, required this.ended});
  final String code;
  final String hostKey;
  final String title;
  final String createdAt;
  final bool ended;
}

class HereStore {
  HereStore._();

  static Object? read(String key, [Object? fallback]) {
    final raw = Store.I.get('$_prefix$key');
    if (raw == null) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  static void write(String key, Object? value) {
    Store.I.put('$_prefix$key', value == null ? null : jsonEncode(value));
  }

  static Stream<String?> changes(String key) => Store.I.changes('$_prefix$key');

  static Map<String, dynamic> _map(Object? v) => v is Map ? Map<String, dynamic>.from(v) : <String, dynamic>{};

  // ---- device ----

  static String? _memoryDeviceId;

  static String _uuid() {
    final r = math.Random.secure();
    final b = List<int>.generate(16, (_) => r.nextInt(256));
    b[6] = (b[6] & 0x0f) | 0x40;
    b[8] = (b[8] & 0x3f) | 0x80;
    final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
    return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
  }

  static String deviceId() {
    var id = read('deviceId');
    if (id is! String || !RegExp(r'^[A-Za-z0-9-]{16,64}$').hasMatch(id)) {
      id = _memoryDeviceId ?? _uuid();
      _memoryDeviceId = id;
      write('deviceId', id);
    }
    return id;
  }

  /// SHA-256 of the device id, hex. What the host is given, never the id.
  static String deviceHash() => sha256.convert(utf8.encode(deviceId())).toString();

  static ({String name, String note}) profile() {
    final p = _map(read('profile'));
    return (name: '${p['name'] ?? ''}', note: '${p['note'] ?? ''}');
  }

  static void saveProfile(String name, String note) => write('profile', {'name': name, 'note': note});

  // ---- hosting ----

  static List<HostedEvent> listHosted() {
    final all = _map(read('hosted', {}));
    final list = [
      for (final e in all.entries)
        if (e.value is Map)
          HostedEvent(
            code: e.key,
            hostKey: '${(e.value as Map)['hostKey'] ?? ''}',
            title: '${(e.value as Map)['title'] ?? ''}',
            createdAt: '${(e.value as Map)['createdAt'] ?? ''}',
            ended: (e.value as Map)['ended'] == true,
          ),
    ];
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  static String? hostKey(String code) {
    final e = _map(read('hosted', {}))[code];
    return e is Map && e['hostKey'] is String ? e['hostKey'] as String : null;
  }

  static void saveHosted(String code, String hostKey, Map<String, dynamic>? event) {
    final all = _map(read('hosted', {}));
    final before = _map(all[code]);
    all[code] = {
      'hostKey': hostKey,
      'title': event?['title'] ?? before['title'] ?? '',
      'createdAt': event?['createdAt'] ?? before['createdAt'] ?? DateTime.now().toUtc().toIso8601String(),
      'ended': event?['ended'] == true,
    };
    write('hosted', all);
  }

  static void forgetHosted(String code) {
    final all = _map(read('hosted', {}));
    all.remove(code);
    write('hosted', all);
    write('host.$code', null);
    write('outbox.$code', null);
  }

  static Map<String, dynamic>? hostCache(String code) {
    final v = read('host.$code');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  static void saveHostCache(String code, Map<String, dynamic> event, List<dynamic> attendees) =>
      write('host.$code', {'event': event, 'attendees': attendees, 'savedAt': DateTime.now().toUtc().toIso8601String()});

  static List<Map<String, dynamic>> outbox(String code) {
    final v = read('outbox.$code', []);
    return [
      if (v is List)
        for (final i in v)
          if (i is Map) Map<String, dynamic>.from(i),
    ];
  }

  static void saveOutbox(String code, List<Map<String, dynamic>> items) => write('outbox.$code', items.isEmpty ? null : items);

  // ---- attending ----

  static Map<String, dynamic>? eventCache(String code) {
    final v = read('event.$code');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  static void saveEventCache(String code, Map<String, dynamic>? event) => write('event.$code', event);

  static Map<String, dynamic>? attendance(String code) {
    final v = read('attend.$code');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  static void saveAttendance(String code, Map<String, dynamic>? attendance) => write('attend.$code', attendance);

  /// { token, name, note, tappedAt }, or null.
  static Map<String, dynamic>? heldTap(String code) {
    final v = read('heldtap.$code');
    return v is Map ? Map<String, dynamic>.from(v) : null;
  }

  static void saveHeldTap(String code, Map<String, dynamic>? held) => write('heldtap.$code', held);
}
