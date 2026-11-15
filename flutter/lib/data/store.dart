// What the app keeps, under the same keys and in the same shapes the site keeps in localStorage
// (main-site/js/store.js, theme.js, tray.js, tour.js):
// every value a string, JSON where the site's is JSON. So a feature ported from the site reads
// what it always did, and what the old WebView app kept comes across as it was (migrate.dart).
//
// One key-value store (shared_preferences) under a prefix that keeps the app's keys apart from
// plugins'. Off the web, any key listed in bigKeys lives in a file of its own (store_file_io.dart).
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'store_file_stub.dart' if (dart.library.io) 'store_file_io.dart';

class Store {
  Store._(this._prefs, this._files);

  static Store? _instance;
  static Store get I => _instance!;
  static bool get isOpen => _instance != null;

  final SharedPreferences? _prefs;
  final BigValues? _files;
  // Tests and screenshots: kept in memory only, so nothing touches the device.
  final Map<String, String> _memory = {};
  final Map<String, StreamController<String?>> _changes = {};

  static const _prefix = 'ls.';

  /// Keys too big for the platform's preferences.
  static const bigKeys = <String>{};

  static Future<Store> open() async {
    final prefs = await SharedPreferences.getInstance();
    final files = kIsWeb ? null : await BigValues.open(bigKeys);
    return _instance = Store._(prefs, files);
  }

  /// A store with these values and nothing written to the device.
  static Store memory([Map<String, String> values = const {}]) {
    final s = Store._(null, null);
    s._memory.addAll(values);
    return _instance = s;
  }

  String? get(String key) {
    if (_prefs == null) return _memory[key];
    if (_files != null && bigKeys.contains(key)) return _files.get(key);
    return _prefs.getString('$_prefix$key');
  }

  bool has(String key) => get(key) != null;

  void put(String key, String? value) {
    if (_prefs == null) {
      if (value == null) {
        _memory.remove(key);
      } else {
        _memory[key] = value;
      }
    } else if (_files != null && bigKeys.contains(key)) {
      _files.put(key, value);
    } else if (value == null) {
      _prefs.remove('$_prefix$key');
    } else {
      _prefs.setString('$_prefix$key', value);
    }
    _changes[key]?.add(value);
  }

  void remove(String key) => put(key, null);

  /// Every change to one key, as localStorage's `storage` event would say it.
  Stream<String?> changes(String key) => (_changes[key] ??= StreamController<String?>.broadcast()).stream;

  /// Every key the app holds (without the prefix): for the web-parity test.
  Iterable<String> get keys {
    if (_prefs == null) return _memory.keys;
    return [..._prefs.getKeys().where((k) => k.startsWith(_prefix)).map((k) => k.substring(_prefix.length)), ...?_files?.keys];
  }

  /// Reads again what another window wrote (the desktop's widget windows share the store).
  Future<void> reload() async {
    await _prefs?.reload();
    await _files?.reload();
  }
}
