// The store's big values, each in a file of its own in the app's support folder, read into
// memory as the app opens so reading stays as immediate as localStorage's (store.dart).
import 'dart:io';

import 'package:path_provider/path_provider.dart';

class BigValues {
  BigValues._(this._directory, this._keys);

  final Directory _directory;
  final Set<String> _keys;
  final Map<String, String> _values = {};
  Future<void> _writing = Future.value();

  /// The folder for [keys], made if needed, with what's in it read; null when there's no folder.
  static Future<BigValues?> open(Set<String> keys) async {
    try {
      final supportDirectory = await getApplicationSupportDirectory();
      final directory = Directory('${supportDirectory.path}${Platform.pathSeparator}store');
      await directory.create(recursive: true);
      final bigValues = BigValues._(directory, keys);
      await bigValues.reload();
      return bigValues;
    } catch (_) {
      // No folder to write to: the key falls back to shared_preferences.
      return null;
    }
  }

  File _file(String key) {
    return File('${_directory.path}${Platform.pathSeparator}$key.json');
  }

  /// Reads every key's file again into memory.
  Future<void> reload() async {
    for (final key in _keys) {
      try {
        final file = _file(key);
        if (await file.exists()) {
          _values[key] = await file.readAsString();
        } else {
          _values.remove(key);
        }
      } catch (_) {
        // Unreadable: as if it weren't there.
      }
    }
  }

  String? get(String key) {
    return _values[key];
  }

  Iterable<String> get keys {
    return _values.keys;
  }

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
        final file = _file(key);
        if (value == null) {
          if (await file.exists()) {
            await file.delete();
          }
          return;
        }
        final temporaryFile = File('${file.path}.tmp');
        await temporaryFile.writeAsString(value, flush: true);
        await temporaryFile.rename(file.path);
      } catch (_) {
        // Kept in memory for this run.
      }
    });
  }
}
