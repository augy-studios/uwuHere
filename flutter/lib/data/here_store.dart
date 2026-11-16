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

/// The "uwuhere." keys above, read and written as the site's JSON.
class HereStore {
  HereStore._();

  /// The decoded JSON under one key, or [fallback] when it's missing or isn't JSON.
  static Object? read(String key, [Object? fallback]) {
    final raw = Store.I.get('$_prefix$key');
    if (raw == null) return fallback;
    try {
      return jsonDecode(raw);
    } catch (_) {
      return fallback;
    }
  }

  /// Saves a value as JSON under one key; null removes the key.
  static void write(String key, Object? value) {
    if (value == null) {
      Store.I.put('$_prefix$key', null);
    } else {
      Store.I.put('$_prefix$key', jsonEncode(value));
    }
  }

  static Stream<String?> changes(String key) {
    return Store.I.changes('$_prefix$key');
  }

  /// A decoded value as a map, or an empty map when it isn't one.
  static Map<String, dynamic> _asMap(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return <String, dynamic>{};
  }

  /// A decoded value as a map, or null when it isn't one.
  static Map<String, dynamic>? _asMapOrNull(Object? value) {
    if (value is Map) {
      return Map<String, dynamic>.from(value);
    }
    return null;
  }

  /// A stored value as text, or empty text when it's missing.
  static String _textOf(Object? value) {
    if (value == null) {
      return '';
    }
    return '$value';
  }

  // ---- device ----

  static String? _memoryDeviceId;

  /// A random version 4 UUID, "xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx", as crypto.randomUUID makes.
  static String _uuid() {
    final random = math.Random.secure();
    final bytes = List<int>.generate(16, (_) {
      return random.nextInt(256);
    });
    // The version (4) and variant bits the UUID format fixes.
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = bytes.map((byte) {
      return byte.toRadixString(16).padLeft(2, '0');
    }).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  /// This device's check-in id: the stored one, or a new one made and saved. Should saving fail,
  /// the same new id is kept in memory for the rest of this run.
  static String deviceId() {
    var id = read('deviceId');
    if (id is! String || !RegExp(r'^[A-Za-z0-9-]{16,64}$').hasMatch(id)) {
      final rememberedId = _memoryDeviceId;
      if (rememberedId == null) {
        id = _uuid();
      } else {
        id = rememberedId;
      }
      _memoryDeviceId = id;
      write('deviceId', id);
    }
    return id;
  }

  /// SHA-256 of the device id, hex. What the host is given, never the id.
  static String deviceHash() {
    return sha256.convert(utf8.encode(deviceId())).toString();
  }

  static ({String name, String note}) profile() {
    final savedProfile = _asMap(read('profile'));
    return (name: _textOf(savedProfile['name']), note: _textOf(savedProfile['note']));
  }

  static void saveProfile(String name, String note) {
    write('profile', {'name': name, 'note': note});
  }

  // ---- hosting ----

  /// Every event this device manages, newest first.
  static List<HostedEvent> listHosted() {
    final all = _asMap(read('hosted', {}));
    final list = <HostedEvent>[];
    for (final entry in all.entries) {
      final saved = entry.value;
      if (saved is Map) {
        list.add(
          HostedEvent(
            code: entry.key,
            hostKey: _textOf(saved['hostKey']),
            title: _textOf(saved['title']),
            createdAt: _textOf(saved['createdAt']),
            ended: saved['ended'] == true,
          ),
        );
      }
    }
    list.sort((first, second) {
      return second.createdAt.compareTo(first.createdAt);
    });
    return list;
  }

  static String? hostKey(String code) {
    final saved = _asMap(read('hosted', {}))[code];
    if (saved is Map && saved['hostKey'] is String) {
      return saved['hostKey'] as String;
    }
    return null;
  }

  /// Remembers an event this device manages. The title and creation time come from [event] when
  /// it has them, else from what was saved before.
  static void saveHosted(String code, String hostKey, Map<String, dynamic>? event) {
    final all = _asMap(read('hosted', {}));
    final before = _asMap(all[code]);

    Object? title;
    if (event != null) {
      title = event['title'];
    }
    if (title == null) {
      title = before['title'];
    }
    if (title == null) {
      title = '';
    }

    Object? createdAt;
    if (event != null) {
      createdAt = event['createdAt'];
    }
    if (createdAt == null) {
      createdAt = before['createdAt'];
    }
    if (createdAt == null) {
      createdAt = DateTime.now().toUtc().toIso8601String();
    }

    var ended = false;
    if (event != null) {
      ended = event['ended'] == true;
    }

    all[code] = {
      'hostKey': hostKey,
      'title': title,
      'createdAt': createdAt,
      'ended': ended,
    };
    write('hosted', all);
  }

  static void forgetHosted(String code) {
    final all = _asMap(read('hosted', {}));
    all.remove(code);
    write('hosted', all);
    write('host.$code', null);
    write('outbox.$code', null);
  }

  static Map<String, dynamic>? hostCache(String code) {
    return _asMapOrNull(read('host.$code'));
  }

  static void saveHostCache(String code, Map<String, dynamic> event, List<dynamic> attendees) {
    write('host.$code', {'event': event, 'attendees': attendees, 'savedAt': DateTime.now().toUtc().toIso8601String()});
  }

  static List<Map<String, dynamic>> outbox(String code) {
    final stored = read('outbox.$code', []);
    final items = <Map<String, dynamic>>[];
    if (stored is List) {
      for (final item in stored) {
        if (item is Map) {
          items.add(Map<String, dynamic>.from(item));
        }
      }
    }
    return items;
  }

  /// Saves the waiting changes; an empty list removes the key.
  static void saveOutbox(String code, List<Map<String, dynamic>> items) {
    if (items.isEmpty) {
      write('outbox.$code', null);
    } else {
      write('outbox.$code', items);
    }
  }

  // ---- attending ----

  static Map<String, dynamic>? eventCache(String code) {
    return _asMapOrNull(read('event.$code'));
  }

  static void saveEventCache(String code, Map<String, dynamic>? event) {
    write('event.$code', event);
  }

  static Map<String, dynamic>? attendance(String code) {
    return _asMapOrNull(read('attend.$code'));
  }

  static void saveAttendance(String code, Map<String, dynamic>? attendance) {
    write('attend.$code', attendance);
  }

  /// { token, name, note, tappedAt }, or null.
  static Map<String, dynamic>? heldTap(String code) {
    return _asMapOrNull(read('heldtap.$code'));
  }

  static void saveHeldTap(String code, Map<String, dynamic>? held) {
    write('heldtap.$code', held);
  }
}
