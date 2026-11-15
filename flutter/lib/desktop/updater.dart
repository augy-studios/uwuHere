// The desktop app updating itself (docs/desktop-features-spec.md §2, §3): as it opens, in the
// update window (splash.dart, up to 10 seconds), 30 seconds after the main window, then every
// hour, soon after the computer wakes, and when the tray's "Check for updates..." asks, which
// says what it found either way.
//
// It reads latest.yml (Windows), latest-mac.yml (macOS), latest-linux.yml or
// latest-linux-arm64.yml (Linux, by processor) from the newest GitHub release
// (releases/latest/download/ always points at it): the version, the file and its SHA-512, checked
// before anything's installed. installers/write-latest-yml.mjs writes them, in electron-updater's
// format.
//
//   Windows .exe (NSIS), Linux .AppImage,   downloaded in the background; a notification, the tray
//   macOS in a folder it can write to       and the title bar offer Restart to update, and it's
//                                           installed on quit anyway.
//   Windows .msi, Linux .deb or .rpm,       told only, with a link to the release to download it.
//   a Mac app it can't write to, a copy
//   run from source
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:yaml/yaml.dart';

import '../app/env.dart';
import 'desk.dart';
import 'notify.dart';
import 'settings.dart';

/// What the update window says: its line, a smaller line under it, how far (0 to 100, -1 for no
/// telling, null for no bar), and whether Later's offered.
class SplashStatus {
  const SplashStatus(this.text, {this.detail = '', this.percent, this.later = false});
  final String text;
  final String detail;
  final int? percent;
  final bool later;
}

class UpdateInfo {
  UpdateInfo({required this.version, required this.file, required this.sha512, required this.size});
  final String version;
  final String file;
  final String sha512;
  final int size;

  static UpdateInfo? parse(String text, {bool arm64 = false}) {
    Object? doc;
    try {
      doc = loadYaml(text);
    } catch (_) {
      return null;
    }
    if (doc is! YamlMap || doc['version'] == null) return null;
    final files = (doc['files'] is YamlList ? doc['files'] as YamlList : const []).whereType<YamlMap>().toList();
    YamlMap? pick;
    if (files.isNotEmpty) {
      // macOS lists a .zip and a .dmg for each processor: the .zip for this one.
      final zips = files.where((f) => '${f['url']}'.endsWith('.zip')).toList();
      final from = zips.isNotEmpty ? zips : files;
      pick = from.where((f) => '${f['url']}'.contains('arm64') == arm64).firstOrNull ?? (zips.isEmpty ? from.first : null);
    }
    final file = '${pick?['url'] ?? doc['path'] ?? ''}';
    final sha = '${pick?['sha512'] ?? doc['sha512'] ?? ''}';
    if (file.isEmpty || sha.isEmpty) return null;
    return UpdateInfo(version: '${doc['version']}', file: file, sha512: sha, size: (pick?['size'] as num?)?.toInt() ?? 0);
  }
}

class Updater {
  Updater._();

  static const _base = 'https://github.com/augy-studios/uwuHere/releases/latest/download';
  static const startupWait = Duration(seconds: 10);
  static String get userAgent => 'uwuHereDesktop/${Env.version}';

  static final available = ValueNotifier<String?>(null);
  static final ready = ValueNotifier<String?>(null);
  static final checking = ValueNotifier<bool>(false);
  static final splash = ValueNotifier<SplashStatus>(const SplashStatus('Starting…'));
  static Completer<void>? _later;

  static String? _notifiedFor;
  static String? _failedFor;
  static String? _downloading;
  static File? _file;
  static Directory? _macStaged;
  static bool _asked = false;
  static Timer? _timer;
  static DateTime _lastTick = DateTime.now();
  static DateTime _checkedAt = DateTime.now();

  /// An Arm processor: Dart names it at the end of its version, as in `on "windows_arm64"`.
  static bool get arm64 => RegExp(r'_arm64"?\s*$').hasMatch(Platform.version.trim());

  static String get ymlName {
    if (Desktop.windows) return 'latest.yml';
    if (Desktop.mac) return 'latest-mac.yml';
    return arm64 ? 'latest-linux-arm64.yml' : 'latest-linux.yml';
  }

  static bool get _wanted => DeskSettings.get<bool>('updateNotices') != false;

  static String get exeDir => File(Platform.resolvedExecutable).parent.path;
  static String get macApp => File(Platform.resolvedExecutable).parent.parent.parent.path;

  static bool _writable(String path) {
    try {
      final probe = File('$path${Platform.pathSeparator}.uwuhere-write-test');
      probe.writeAsStringSync('');
      probe.deleteSync();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Whether this copy can install an update itself: the .exe install is told apart by the
  /// uninstaller beside it.
  static bool get canInstall {
    if (Desktop.fromSource) return false;
    if (Desktop.windows) return File('$exeDir\\Uninstall ${Desktop.name}.exe').existsSync();
    if (Desktop.linux) return Platform.environment['APPIMAGE']?.isNotEmpty == true;
    if (Desktop.mac) {
      final bundle = macApp;
      return bundle.endsWith('.app') &&
          !bundle.startsWith('/Volumes/') &&
          !bundle.contains('/AppTranslocation/') &&
          _writable(bundle) &&
          _writable(File(bundle).parent.path);
    }
    return false;
  }

  static bool newer(String a, String b) {
    List<int> parts(String v) => v.split(RegExp(r'[.+-]')).take(3).map((p) => int.tryParse(p) ?? 0).toList();
    final x = parts(a), y = parts(b);
    for (var i = 0; i < 3; i++) {
      final p = i < x.length ? x[i] : 0, q = i < y.length ? y[i] : 0;
      if (p != q) return p > q;
    }
    return false;
  }

  static Future<UpdateInfo?> find() async {
    final r = await http
        .get(Uri.parse('$_base/$ymlName?t=${DateTime.now().millisecondsSinceEpoch}'), headers: {'User-Agent': userAgent, 'Cache-Control': 'no-cache'})
        .timeout(const Duration(seconds: 20));
    if (r.statusCode != 200) throw HttpException('update file: ${r.statusCode}');
    final info = UpdateInfo.parse(utf8.decode(r.bodyBytes), arm64: arm64);
    if (info == null) throw const FormatException('update file');
    return newer(info.version, Env.version) ? info : null;
  }

  static Future<File> download(UpdateInfo info, {void Function(int got, int total)? progress}) async {
    final dir = Directory('${Directory.systemTemp.path}${Platform.pathSeparator}uwuhere-update')..createSync(recursive: true);
    final out = File('${dir.path}${Platform.pathSeparator}${info.file.split('/').last}');
    if (out.existsSync() && await _hash(out) == info.sha512) return out;
    final client = http.Client();
    try {
      final req = http.Request('GET', Uri.parse('$_base/${Uri.encodeComponent(info.file)}'))..headers['User-Agent'] = userAgent;
      final res = await client.send(req).timeout(const Duration(seconds: 30));
      if (res.statusCode != 200) throw HttpException('download: ${res.statusCode}');
      final total = res.contentLength ?? info.size;
      final sink = out.openWrite();
      var got = 0;
      await for (final chunk in res.stream.timeout(const Duration(seconds: 60))) {
        sink.add(chunk);
        got += chunk.length;
        progress?.call(got, total);
      }
      await sink.close();
    } finally {
      client.close();
    }
    if (await _hash(out) != info.sha512) {
      try {
        out.deleteSync();
      } catch (_) {}
      throw const FormatException("the download's SHA-512 doesn't match");
    }
    return out;
  }

  static Future<String> _hash(File f) async => base64.encode((await sha512.bind(f.openRead()).first).bytes);

  static Future<void> _stage(File file) async {
    _file = file;
    if (!Desktop.mac) return;
    final dir = Directory('${Directory.systemTemp.path}/uwuhere-staged');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    final r = await Process.run('/usr/bin/ditto', ['-x', '-k', file.path, dir.path]);
    if (r.exitCode != 0) throw ProcessException('ditto', [], '${r.stderr}', r.exitCode);
    final app = dir.listSync().whereType<Directory>().where((d) => d.path.endsWith('.app')).firstOrNull;
    if (app == null) throw const FormatException('no .app in the update');
    _macStaged = app;
  }

  // macOS: once this process has gone, swap the new app in for the old, keeping the old if the
  // swap fails part-way, clear the quarantine flag, then open it again if asked. Detached.
  static const _swap = r'''
while kill -0 "$1" 2>/dev/null; do sleep 0.2; done
old="$3.old-$$"
if mv "$3" "$old"; then
  if mv "$2" "$3"; then rm -rf "$old"; else mv "$old" "$3"; fi
fi
xattr -dr com.apple.quarantine "$3" 2>/dev/null
rm -rf "$4"
[ "$5" = 1 ] && open "$3"
''';

  static bool _installing = false;

  static Future<void> _installOnExit({required bool relaunch}) async {
    if (_installing || _file == null) return;
    _installing = true;
    final file = _file!;
    if (Desktop.windows) {
      // The installer closes this copy, installs over it and, with --force-run, opens it again.
      await Process.start(file.path, ['--updated', '/S', if (relaunch) '--force-run'], mode: ProcessStartMode.detached);
    } else if (Desktop.linux) {
      final target = Platform.environment['APPIMAGE']!;
      final next = File('$target.new');
      await file.copy(next.path);
      await Process.run('chmod', ['755', next.path]);
      next.renameSync(target);
      if (relaunch) await Process.start(target, const [], mode: ProcessStartMode.detached);
    } else if (Desktop.mac && _macStaged != null) {
      await Process.start('/bin/sh', [
        '-c',
        _swap,
        'uwuhere-update',
        '$pid',
        _macStaged!.path,
        macApp,
        _macStaged!.parent.path,
        relaunch ? '1' : '0',
      ], mode: ProcessStartMode.detached);
    }
  }

  /// Set by desktop_main.dart: puts the update window up over the app, for Restart to update.
  static Future<void> Function()? showSplash;

  static Future<void> restartToUpdate() async {
    if (ready.value == null) return;
    await showSplash?.call();
    splash.value = const SplashStatus('Installing update…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 800));
    await _installOnExit(relaunch: true);
    await Desktop.quit();
  }

  static void start() {
    if (Desktop.fromSource) return;
    Desktop.beforeQuit.add(() async {
      if (ready.value != null && !_installing && canInstall) await _installOnExit(relaunch: false);
    });
    Timer(const Duration(seconds: 30), check);
    _lastTick = DateTime.now();
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(minutes: 1), (_) {
      final now = DateTime.now();
      // Asleep overnight: the clock jumps. What came out meanwhile, soon after waking.
      final slept = now.difference(_lastTick) > const Duration(minutes: 5);
      _lastTick = now;
      if (slept) {
        Timer(const Duration(seconds: 20), check);
      } else if (now.difference(_checkedAt) >= const Duration(hours: 1)) {
        check();
      }
    });
  }

  static Future<void> check() async {
    if (checking.value) return;
    checking.value = true;
    _checkedAt = DateTime.now();
    final asked = _asked;
    try {
      final info = await find();
      if (info == null) {
        if (asked) DeskNotify.show(title: 'You’re up to date', body: '${Desktop.name} ${Env.version} is the newest version.');
        return;
      }
      _found(info, asked: asked);
    } catch (_) {
      if (asked) DeskNotify.show(title: 'Couldn’t check for updates', body: 'Check your connection and try again.');
    } finally {
      checking.value = false;
      _asked = false;
    }
  }

  static void _found(UpdateInfo info, {required bool asked}) {
    available.value = info.version;
    final install = canInstall;
    if (asked && install) {
      if (ready.value == info.version) {
        _sayReady(info.version, force: true);
      } else {
        DeskNotify.show(title: '${Desktop.name} ${info.version} is out', body: 'It’s downloading. You’ll be told when it’s ready to install.');
      }
    }
    if (!install) {
      if (_notifiedFor == info.version && !asked) return;
      if (!asked && !_wanted) return;
      _notifiedFor = info.version;
      DeskNotify.show(
        title: '${Desktop.name} ${info.version} is out',
        body: 'Click to download it from GitHub, then install it over this one.',
        onClick: () => Desktop.openExternal(Desktop.releases),
      );
      return;
    }
    if (ready.value == info.version || _downloading == info.version) return;
    _downloading = info.version;
    download(info)
        .then((file) async {
          await _stage(file);
          _downloading = null;
          ready.value = info.version;
          _sayReady(info.version);
        })
        .catchError((Object _) => _downloadFailed(info.version));
  }

  static void _sayReady(String version, {bool force = false}) {
    if (!force && (_notifiedFor == version || !_wanted)) return;
    _notifiedFor = version;
    DeskNotify.show(
      title: '${Desktop.name} $version is ready',
      body: 'Click to restart and update. Otherwise it updates the next time you quit.',
      onClick: restartToUpdate,
    );
  }

  static void _downloadFailed(String version) {
    _downloading = null;
    if (_failedFor == version || !_wanted) return;
    _failedFor = version;
    DeskNotify.show(
      title: 'Couldn’t download ${Desktop.name} $version',
      body: 'It tries again within the hour, or click to download it from GitHub.',
      onClick: () => Desktop.openExternal(Desktop.releases),
    );
  }

  /// The tray's "Check for updates...": a check now, and a notification of what it found.
  static void checkNow() {
    if (Desktop.fromSource) {
      DeskNotify.show(title: 'No updates to check for', body: 'Run from source, there is nothing to update. The installed app checks for itself.');
      return;
    }
    if (checking.value) return;
    _asked = true;
    check();
  }

  static void later() => _later?.complete();

  /// As the app opens: checks for an update, and downloads and installs one it can install itself.
  /// Completes once the app should open; never, if it's restarting into the new version. From
  /// source there's nothing to update, unless UWUHERE_SPLASH_DEMO=1 runs through the steps with
  /// made-up numbers.
  static Future<void> startup() async {
    final demo = Platform.environment['UWUHERE_SPLASH_DEMO'] == '1';
    if (Desktop.fromSource && !demo) return;
    if (demo) return _demo();
    splash.value = const SplashStatus('Checking for updates…', percent: -1);
    UpdateInfo? info;
    try {
      info = await find().timeout(startupWait);
    } catch (_) {
      info = null;
    }
    if (info == null || !canInstall) {
      final found = info;
      if (found != null) Timer(const Duration(seconds: 5), () => _found(found, asked: false));
      return _opening();
    }
    available.value = info.version;
    _downloading = info.version;
    splash.value = SplashStatus('Downloading update', detail: 'Version ${info.version}', percent: 0, later: true);
    _later = Completer<void>();
    final done = Completer<Object?>();
    download(
      info,
      progress: (got, total) {
        if (_later?.isCompleted ?? true) return;
        splash.value = SplashStatus(
          'Downloading update',
          detail: '${_mb(got)} of ${_mb(total)} MB',
          percent: total > 0 ? (got * 100 ~/ total) : -1,
          later: true,
        );
      },
    ).then((f) => done.isCompleted ? null : done.complete(f)).catchError((Object e) => done.isCompleted ? null : done.complete(e));
    final outcome = await Future.any<Object?>([done.future, _later!.future.then((_) => 'later')]);
    final version = info.version;
    if (outcome == 'later') {
      done.future.then((f) async {
        if (f is File) {
          try {
            await _stage(f);
            _downloading = null;
            ready.value = version;
            _sayReady(version);
          } catch (_) {
            _downloadFailed(version);
          }
        } else {
          _downloadFailed(version);
        }
      });
      return _opening();
    }
    if (outcome is! File) {
      _downloading = null;
      return _opening();
    }
    try {
      await _stage(outcome);
    } catch (_) {
      _downloading = null;
      return _opening();
    }
    _downloading = null;
    ready.value = version;
    await restartToUpdate();
    await Completer<void>().future;
  }

  static String _mb(int bytes) => (bytes / 1e6).toStringAsFixed(bytes < 10e6 ? 1 : 0);

  static Future<void> _opening() async {
    splash.value = const SplashStatus('Starting…');
    await Future<void>.delayed(const Duration(milliseconds: 500));
  }

  static Future<void> _demo() async {
    splash.value = const SplashStatus('Checking for updates…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    const total = 34600000;
    _later = Completer<void>();
    for (var p = 0; p <= 100; p += 4) {
      if (_later!.isCompleted) return _opening();
      splash.value = SplashStatus('Downloading update', detail: '${_mb(total * p ~/ 100)} of ${_mb(total)} MB', percent: p, later: true);
      await Future<void>.delayed(const Duration(milliseconds: 120));
    }
    splash.value = const SplashStatus('Installing update…', percent: -1);
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    return _opening();
  }
}
