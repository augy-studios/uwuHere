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
  String toString() {
    if (code == null) {
      return message;
    }
    return '$message ($code)';
  }
}

/// One listener added with [Native.on]; [cancel] stops it.
class NativeListener {
  NativeListener._(this._key, this._callback);

  /// "plugin.event".
  final String _key;
  final void Function(Map<String, dynamic>) _callback;

  void cancel() {
    Native._remove(this);
  }
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

  /// Connects the bridge once: to the Android channel (with events coming back through [emit]),
  /// or to the Dart [host]; then asks the App plugin what this build can do.
  static Future<void> start() async {
    if (_started) return;
    _started = true;
    final isAndroid = !kIsWeb && defaultTargetPlatform == TargetPlatform.android;
    if (host == null && !isAndroid) {
      available = false;
    }
    if (host == null && available) {
      _channel.setMethodCallHandler((methodCall) async {
        if (methodCall.method != 'event') return null;
        final callArguments = Map<String, dynamic>.from(methodCall.arguments as Map);
        var eventData = _decode(callArguments['data'] as String?);
        if (eventData == null) {
          eventData = <String, dynamic>{};
        }
        emit('${callArguments['plugin']}', '${callArguments['event']}', eventData);
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
      if (available) {
        _info = await call('App', 'info');
      }
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
  static bool has(String feature) {
    final info = _info;
    List? features;
    if (info != null) {
      features = info['features'] as List?;
    }
    if (features == null) {
      return false;
    }
    return features.contains(feature);
  }

  static Map<String, dynamic>? get info {
    return _info;
  }

  static String? get version {
    final info = _info;
    if (info == null) {
      return null;
    }
    return info['version'] as String?;
  }

  /// 'android', 'desktop', or null where there's no native side.
  static String? get platform {
    final info = _info;
    if (info == null) {
      return null;
    }
    return info['platform'] as String?;
  }

  /// Calls one method of one plugin, through the Dart [host] if there is one, else the channel.
  /// Throws a [NativeError] when it fails or there's nothing behind the bridge.
  static Future<Map<String, dynamic>?> call(String plugin, String method, [Map<String, dynamic>? options]) async {
    if (!available) throw NativeError('Not in the app', code: 'unavailable');
    final dartHost = host;
    Map<String, dynamic> givenOptions;
    if (options == null) {
      givenOptions = const {};
    } else {
      givenOptions = options;
    }
    if (dartHost != null) return dartHost.call(plugin, method, givenOptions);
    try {
      final json = await _channel.invokeMethod<String>('call', {'plugin': plugin, 'method': method, 'options': jsonEncode(givenOptions)});
      return _decode(json);
    } on PlatformException catch (error) {
      String errorMessage;
      if (error.message == null) {
        errorMessage = 'Failed';
      } else {
        errorMessage = error.message!;
      }
      Map<String, dynamic>? errorData;
      if (error.details is String) {
        errorData = _decode(error.details as String);
      } else {
        errorData = null;
      }
      throw NativeError(errorMessage, code: error.code, data: errorData);
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

  /// Listens for one plugin's event. The first listener for an event asks the channel to start
  /// sending it.
  static NativeListener on(String plugin, String event, void Function(Map<String, dynamic>) callback) {
    final key = '$plugin.$event';
    final listener = NativeListener._(key, callback);
    final list = _listeners.putIfAbsent(key, () {
      return [];
    });
    list.add(listener);
    if (list.length == 1 && available && host == null) {
      _channel.invokeMethod('listen', {'plugin': plugin, 'event': event}).catchError((_) {
        return null;
      });
    }
    return listener;
  }

  /// An event, to everything listening for it: from the channel, a host or a fake.
  static void emit(String plugin, String event, Map<String, dynamic> data) {
    var listening = _listeners['$plugin.$event'];
    if (listening == null) {
      listening = const <NativeListener>[];
    }
    for (final listener in List.of(listening)) {
      try {
        listener._callback(data);
      } catch (_) {
        // One listener's trouble isn't the others'.
      }
    }
  }

  /// Takes a listener away; when it was the last for its event, the channel stops sending it.
  static void _remove(NativeListener listener) {
    final list = _listeners[listener._key];
    if (list == null) return;
    final wasListening = list.remove(listener);
    if (!wasListening) return;
    if (list.isNotEmpty || !available || host != null) return;
    final parts = listener._key.split('.');
    _channel.invokeMethod('unlisten', {'plugin': parts[0], 'event': parts[1]}).catchError((_) {
      return null;
    });
  }

  /// A JSON string from the native side as a map, or null when it's empty or not a JSON object.
  static Map<String, dynamic>? _decode(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    } catch (_) {
      return null;
    }
  }
}
