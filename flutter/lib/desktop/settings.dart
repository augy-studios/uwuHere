// The desktop app's own settings (docs/desktop-features-spec.md §20): one small JSON file in the
// app's per-user folder, read and merged on every write, so two parts of the app writing
// different keys never undo each other. A failed read is an empty map and a failed write is
// ignored. Nothing secret is ever kept here.
//
// Keys: bounds, maximized, trayHintShown (desk.dart); loginChosen, linkHandoff (desk.dart);
// updateNotices (updater.dart); alertsCheckins (alerts_poll.dart); setupDone, pendingLook,
// useSystemAccent (welcome.dart); widgets (widgets_window.dart); trayStop, favourites (glance.dart).
import 'dart:convert';
import 'dart:io';

class DeskSettings {
  DeskSettings._();

  /// The app's name as its folder has it, on every system.
  static const folderName = 'uwuHere';

  /// %APPDATA%\uwuHere, ~/Library/Application Support/uwuHere, or ~/.config/uwuHere.
  static String get directory {
    final environment = Platform.environment;
    if (Platform.isWindows) {
      String appDataFolder;
      final appDataVariable = environment['APPDATA'];
      if (appDataVariable == null) {
        appDataFolder = '${environment['USERPROFILE']}\\AppData\\Roaming';
      } else {
        appDataFolder = appDataVariable;
      }
      return '$appDataFolder\\$folderName';
    }
    String home;
    final homeVariable = environment['HOME'];
    if (homeVariable == null) {
      home = '';
    } else {
      home = homeVariable;
    }
    if (Platform.isMacOS) return '$home/Library/Application Support/$folderName';
    String configFolder;
    final configVariable = environment['XDG_CONFIG_HOME'];
    if (configVariable == null) {
      configFolder = '$home/.config';
    } else {
      configFolder = configVariable;
    }
    return '$configFolder/$folderName';
  }

  /// For tests: another folder.
  static String? override;

  /// The folder in use: the test's [override] if there is one, otherwise the system's [directory].
  static String get folder {
    final overrideFolder = override;
    if (overrideFolder != null) return overrideFolder;
    return directory;
  }

  static File get _file {
    return File('$folder${Platform.pathSeparator}settings.json');
  }

  static Map<String, dynamic> read() {
    try {
      final decoded = jsonDecode(_file.readAsStringSync());
      if (decoded is Map<String, dynamic>) return decoded;
      return {};
    } catch (_) {
      return {};
    }
  }

  static ValueType? get<ValueType>(String key) {
    final value = read()[key];
    if (value is ValueType) return value;
    return null;
  }

  /// Merges [changes] into what's kept (a null value removes its key), written to a temporary
  /// file first and then moved into place, so a half-written file is never left behind.
  static void write(Map<String, dynamic> changes) {
    try {
      _file.parent.createSync(recursive: true);
      final merged = {...read(), ...changes}
        ..removeWhere((key, value) {
          return value == null;
        });
      final temporaryFile = File('${_file.path}.tmp');
      temporaryFile.writeAsStringSync(jsonEncode(merged));
      temporaryFile.renameSync(_file.path);
    } catch (_) {
      // Not kept: the default comes back next time.
    }
  }
}
