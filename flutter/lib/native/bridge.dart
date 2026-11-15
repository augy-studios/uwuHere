// The one way to platform code (docs/flutter-android-app-spec.md §4):
//
//   Native.call('App', 'info')                  → Bridge → Plugin.method(call) → resolve(JSON)
//   Native.on('App', 'link', (data) {...})      ← Bridge ← plugin.notifyListeners('link', JSON)
//   Native.has('update')                        ← info().features, listed by the App plugin
//
// Options and answers are JSON strings, so the native side needs no codec of its own. On
// Android the channel reaches the Java plugins in android/app/src/main/java/org/uwuapps/board/.
// The desktop apps install a Dart host instead (lib/desktop/host.dart), and tests a fake.
// Without either, the bridge is unavailable and every call fails fast, so features fall back
// to their plain path.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A plugin call that failed: its message, a code ("permission", "cancelled", "unavailable"…)
/// and whatever data came with it.
class NativeError implements Exception {
  NativeError(this.message, {this.code, this.data});
  final String message;
  final String? code;
  final Map<String, dynamic>? data;

  @override
  String toString() => code == null ? message : '$message ($code)';
}

class NativeListener {
  NativeListener._(this._key, this._fn);
  final String _key;
  final void Function(Map<String, dynamic>) _fn;

  void cancel() => Native._remove(this);
}

/// Stands in for platform code: the desktop's host, or a fake in tests and screenshots.
abstract class NativeHost {
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options);
}

class Native {
  Native._();

  static const _channel = MethodChannel('org.uwuapps.here/bridge');
  static final Map<String, List<NativeListener>> _listeners = {};
  static bool _started = false;
  static Map<String, dynamic>? _info;

  /// Set before start() to answer calls in Dart.
  static NativeHost? host;

  /// Whether there's anything behind the bridge at all.
  static bool available = true;

  static Future<void> start() async {
    if (_started) return;
    _started = true;
    final android = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (host == null && !android) available = false;
    if (host == null && available) {
      _channel.setMethodCallHandler((call) async {
        if (call.method != 'event') return null;
        final args = Map<String, dynamic>.from(call.arguments as Map);
        emit('${args['plugin']}', '${args['event']}', _decode(args['data'] as String?) ?? <String, dynamic>{});
        return null;
      });
      try {
        await _channel.invokeMethod('hello');
      } on MissingPluginException {
        available = false;
      } catch (_) {
        // Answered below, if at all.
      }
    }
    try {
      if (available) _info = await call('App', 'info');
    } catch (_) {
      _info = null;
    }
  }

  /// For tests: as if never started.
  @visibleForTesting
  static void reset() {
    _started = false;
    _info = null;
    host = null;
    available = true;
    _listeners.clear();
  }

  /// What this build and device can do, as the App plugin lists it. The only switch features
  /// use to show a native-only button.
  static bool has(String feature) => ((_info?['features'] as List?) ?? const []).contains(feature);
  static Map<String, dynamic>? get info => _info;
  static String? get version => _info?['version'] as String?;

  /// 'android', 'desktop', or null where there's no native side.
  static String? get platform => _info?['platform'] as String?;

  static Future<Map<String, dynamic>?> call(String plugin, String method, [Map<String, dynamic>? options]) async {
    if (!available) throw NativeError('Not in the app', code: 'unavailable');
    final h = host;
    if (h != null) return h.call(plugin, method, options ?? const {});
    try {
      final json = await _channel.invokeMethod<String>('call', {'plugin': plugin, 'method': method, 'options': jsonEncode(options ?? const {})});
      return _decode(json);
    } on PlatformException catch (e) {
      throw NativeError(e.message ?? 'Failed', code: e.code, data: e.details is String ? _decode(e.details as String) : null);
    } on MissingPluginException {
      available = false;
      throw NativeError('Not in the app', code: 'unavailable');
    }
  }

  /// A call whose failure doesn't matter to the caller.
  static Future<Map<String, dynamic>?> tryCall(String plugin, String method, [Map<String, dynamic>? options]) async {
    try {
      return await call(plugin, method, options);
    } catch (_) {
      return null;
    }
  }

  static NativeListener on(String plugin, String event, void Function(Map<String, dynamic>) fn) {
    final key = '$plugin.$event';
    final l = NativeListener._(key, fn);
    final list = _listeners.putIfAbsent(key, () => []);
    list.add(l);
    if (list.length == 1 && available && host == null) {
      _channel.invokeMethod('listen', {'plugin': plugin, 'event': event}).catchError((_) => null);
    }
    return l;
  }

  /// An event, to everything listening for it: from the channel, a host or a fake.
  static void emit(String plugin, String event, Map<String, dynamic> data) {
    for (final l in List.of(_listeners['$plugin.$event'] ?? const <NativeListener>[])) {
      try {
        l._fn(data);
      } catch (_) {
        // One listener's trouble isn't the others'.
      }
    }
  }

  static void _remove(NativeListener l) {
    final list = _listeners[l._key];
    if (list == null || !list.remove(l) || list.isNotEmpty || !available || host != null) return;
    final parts = l._key.split('.');
    _channel.invokeMethod('unlisten', {'plugin': parts[0], 'event': parts[1]}).catchError((_) => null);
  }

  static Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final v = jsonDecode(json);
      return v is Map ? Map<String, dynamic>.from(v) : null;
    } catch (_) {
      return null;
    }
  }
}
