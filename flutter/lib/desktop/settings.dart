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
  static String get dir {
    final env = Platform.environment;
    if (Platform.isWindows) return '${env['APPDATA'] ?? '${env['USERPROFILE']}\\AppData\\Roaming'}\\$folderName';
    final home = env['HOME'] ?? '';
    if (Platform.isMacOS) return '$home/Library/Application Support/$folderName';
    return '${env['XDG_CONFIG_HOME'] ?? '$home/.config'}/$folderName';
  }

  /// For tests: another folder.
  static String? override;

  static String get folder => override ?? dir;
  static File get _file => File('$folder${Platform.pathSeparator}settings.json');

  static Map<String, dynamic> read() {
    try {
      final v = jsonDecode(_file.readAsStringSync());
      return v is Map<String, dynamic> ? v : {};
    } catch (_) {
      return {};
    }
  }

  static T? get<T>(String key) {
    final v = read()[key];
    return v is T ? v : null;
  }

  static void write(Map<String, dynamic> changes) {
    try {
      _file.parent.createSync(recursive: true);
      final now = {...read(), ...changes}..removeWhere((k, v) => v == null);
      final tmp = File('${_file.path}.tmp');
      tmp.writeAsStringSync(jsonEncode(now));
      tmp.renameSync(_file.path);
    } catch (_) {
      // Not kept: the default comes back next time.
    }
  }
}
