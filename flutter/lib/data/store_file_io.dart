// The store's big values, each in a file of its own in the app's support folder, read into
// memory as the app opens so reading stays as immediate as localStorage's (store.dart).
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BigValues {
  BigValues._(this._dir, this._names);

  final Directory _dir;
  final Set<String> _names;
  final Map<String, String> _values = {};
  Future<void> _writing = Future.value();

  static Future<BigValues?> open(Set<String> keys) async {
    try {
      final base = await getApplicationSupportDirectory();
      final dir = Directory('${base.path}${Platform.pathSeparator}store');
      await dir.create(recursive: true);
      final b = BigValues._(dir, keys);
      await b.reload();
      return b;
    } catch (_) {
      // No folder to write to: the key falls back to shared_preferences.
      return null;
    }
  }

  File _file(String key) => File('${_dir.path}${Platform.pathSeparator}$key.json');

  Future<void> reload() async {
    for (final key in _names) {
      try {
        final f = _file(key);
        if (await f.exists()) {
          _values[key] = await f.readAsString();
        } else {
          _values.remove(key);
        }
      } catch (_) {
        // Unreadable: as if it weren't there.
      }
    }
  }

  String? get(String key) => _values[key];

  Iterable<String> get keys => _values.keys;

  // One write at a time, each to a temporary file moved into place, so a crash mid-write
  // never leaves half a file.
  void put(String key, String? value) {
    if (value == null) {
      _values.remove(key);
    } else {
      _values[key] = value;
    }
    _writing = _writing.then((_) async {
      try {
        final f = _file(key);
        if (value == null) {
          if (await f.exists()) await f.delete();
          return;
        }
        final tmp = File('${f.path}.tmp');
        await tmp.writeAsString(value, flush: true);
        await tmp.rename(f.path);
      } catch (_) {
        // Kept in memory for this run.
      }
    });
  }
}
