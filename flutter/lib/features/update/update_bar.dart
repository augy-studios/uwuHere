// The Android app updating itself from GitHub Releases (docs/flutter-android-app-spec.md §8):
// the site's /api/app-release names the newest release and every one before it; a newer one
// shows in a bar at the top, and the Updates page (always in Material You, whichever look the
// app is in) says what's new in each version, newest first, downloads the APK, checks it
// against GitHub's SHA-256, and hands it to Android's installer. Looked up as the app opens and
// again on coming back to it after an hour. "Not now" lasts until the app's next opened.
//
// "New versions of the app" on the same page joins the FCM topic the site pushes to the moment
// a release is published (main-site/api/push/release.js, flutter/FIREBASE-SETUP.md); tapping
// that notification opens this page. Only where the APK was built with Firebase in it.
//
// The Play build has no updater of its own (Play updates it): its page shows the versions and
// sends the person to Play.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../app/env.dart';
import '../../app/nav.dart';
import '../../data/store.dart';
import '../../native/bridge.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/wavy_progress.dart';
import 'release_notes.dart';

// Kept beside the native switch (MainActivity's topic.releases), as the last answer it gave.
const _releasesKey = 'uwuhere.releaseAlerts';
const playListing = 'https://play.google.com/store/apps/details?id=org.uwuapps.here';

/// Whether `version` comes after `otherVersion`, number by number: 1.10.0 after 1.9.0. The same
/// as newer() in main-site/api/app-release.js.
bool newerVersion(String version, String otherVersion) {
  final versionNumbers = _versionNumbers(version);
  final otherNumbers = _versionNumbers(otherVersion);
  for (var index = 0; index < versionNumbers.length || index < otherNumbers.length; index = index + 1) {
    // A version with fewer parts counts its missing parts as 0: 1.2 is the same as 1.2.0.
    var versionNumber = 0;
    if (index < versionNumbers.length) {
      versionNumber = versionNumbers[index];
    }
    var otherNumber = 0;
    if (index < otherNumbers.length) {
      otherNumber = otherNumbers[index];
    }
    final difference = versionNumber - otherNumber;
    if (difference != 0) {
      return difference > 0;
    }
  }
  return false;
}

/// A version's numbers, one for each part between the dots, with anything that isn't a digit
/// taken out first ("0-beta" is 0), and 0 for a part with no digits at all.
List<int> _versionNumbers(String version) {
  final numbers = <int>[];
  for (final part in version.split('.')) {
    final parsed = int.tryParse(part.replaceAll(RegExp(r'\D'), ''));
    if (parsed == null) {
      numbers.add(0);
    } else {
      numbers.add(parsed);
    }
  }
  return numbers;
}

/// Everything the updater knows and does: the site's list of releases, whether a newer one is
/// out, downloading and installing it, and the "New versions of the app" notifications switch.
/// One for the whole app, which the bar and the Updates page both listen to.
class AndroidUpdates extends ChangeNotifier with WidgetsBindingObserver {
  AndroidUpdates._();
  static final AndroidUpdates I = AndroidUpdates._();

  /// The site's whole answer: the newest release, and `history`, every release newest first.
  Map<String, dynamic>? latest;
  bool loading = false;
  bool failed = false;
  bool dismissed = false;
  DateTime? _checkedAt;

  /// Downloading: 0 to 1, or null.
  double? progress;
  String? error;

  /// "New versions of the app": on, off, or null while it's being changed.
  bool? notices;

  bool _started = false;

  /// The version of this copy of the app, as the native side reports it, or else as it was built.
  String get installedVersion {
    final nativeVersion = Native.version;
    if (nativeVersion != null) {
      return nativeVersion;
    }
    return Env.version;
  }

  /// The newest release, when it's newer than this copy.
  Map<String, dynamic>? get newerRelease {
    final newest = latest;
    if (newest == null || newest['version'] is! String) {
      return null;
    }
    if (newerVersion(newest['version'] as String, installedVersion)) {
      return newest;
    }
    return null;
  }

  /// The Play build: Play updates it, so no updater of its own.
  bool get updatedByPlay {
    if (isPlayBuild) {
      return true;
    }
    final info = Native.info;
    if (info == null) {
      return false;
    }
    return info['play'] == true;
  }

  bool get offered {
    return newerRelease != null && !dismissed && !updatedByPlay;
  }

  /// Every release the site listed, newest first, each as a map (anything else in the list skipped).
  List<Map<String, dynamic>> get history {
    List<dynamic> everyRelease = const [];
    final newest = latest;
    if (newest != null) {
      final listed = newest['history'] as List?;
      if (listed != null) {
        everyRelease = listed;
      }
    }
    return [
      for (final release in everyRelease)
        if (release is Map) Map<String, dynamic>.from(release),
    ];
  }

  void start() {
    if (_started || !Env.android) {
      return;
    }
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    notices = Store.I.get(_releasesKey) == '1';
    readNotices();
    // The notification "x.y.z is out", tapped: this page.
    Native.on('App', 'openUpdates', (_) {
      openUpdates();
    });
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      return;
    }
    final lastChecked = _checkedAt;
    if (lastChecked == null || DateTime.now().difference(lastChecked) > const Duration(hours: 1)) {
      check();
    }
  }

  /// Whether the check running now was asked for (the bar says so), rather than the quiet one.
  bool asked = false;

  /// Asks the site for its releases. `fresh` asks past the site's cache, for a release published
  /// a moment ago; `asked` means someone asked, so the bar shows the check and a toast says when
  /// there's nothing newer.
  Future<void> check({bool fresh = false, bool asked = false}) async {
    _checkedAt = DateTime.now();
    loading = true;
    this.asked = asked;
    notifyListeners();
    try {
      var path = '/app-release';
      if (fresh) {
        path = '$path?v=${DateTime.now().millisecondsSinceEpoch}';
      }
      final uri = Api.uri(path);
      final response = await Api.client.get(uri).timeout(const Duration(seconds: 20));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      final data = jsonDecode(response.body);
      if (data is Map) {
        latest = Map<String, dynamic>.from(data);
      }
      failed = false;
    } catch (_) {
      failed = latest == null;
    }
    loading = false;
    if (this.asked && newerRelease == null && !failed) {
      var versionText = installedVersion;
      if (versionText.isEmpty) {
        versionText = 'already';
      }
      AppNav.toast('You have the newest version, $versionText.');
    }
    this.asked = false;
    notifyListeners();
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  /// Downloads the newer release's APK to the temporary folder, showing its progress, checks it
  /// against the SHA-256 GitHub gave, and hands it to Android's installer. Says what went wrong
  /// in `error` when it couldn't.
  Future<void> install() async {
    final release = newerRelease;
    if (release == null || progress != null) {
      return;
    }
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}${Platform.pathSeparator}uwuhere-${release['version']}.apk');
      final response = await Api.client.send(http.Request('GET', Uri.parse('${release['apk']}')));
      if (response.statusCode != 200) {
        throw StateError('HTTP ${response.statusCode}');
      }
      // The size the site gave, or else the size the download says it is, or else unknown (0).
      var totalBytes = 0;
      final listedSize = release['size'] as num?;
      if (listedSize != null) {
        totalBytes = listedSize.toInt();
      } else {
        final contentLength = response.contentLength;
        if (contentLength != null) {
          totalBytes = contentLength;
        }
      }
      final sink = file.openWrite();
      var receivedBytes = 0;
      await for (final chunk in response.stream) {
        sink.add(chunk);
        receivedBytes = receivedBytes + chunk.length;
        if (totalBytes > 0) {
          progress = receivedBytes / totalBytes;
          notifyListeners();
        }
      }
      await sink.close();
      final checksum = (await sha256.bind(file.openRead()).first).toString();
      final expected = release['sha256'];
      if (expected is String && expected.isNotEmpty && expected.toLowerCase() != checksum) {
        await file.delete();
        throw StateError('checksum');
      }
      progress = 1;
      notifyListeners();
      await Native.call('App', 'installApk', {'path': file.path});
      progress = null;
    } catch (exception) {
      progress = null;
      if (exception is StateError && exception.message == 'checksum') {
        error = 'The download didn’t match GitHub’s checksum, so it wasn’t installed. Try again.';
      } else if (exception is NativeError && exception.code == 'permission') {
        error = 'Allow uwuHere to install apps, then press Update again.';
      } else {
        error = 'Couldn’t download the update. Check your connection and try again.';
      }
    }
    notifyListeners();
  }

  /// The Notifications sheet's switch and this one are the same topic: read where it's kept, as
  /// the app starts, each time the Updates page opens, and after the sheet changes it.
  Future<void> readNotices() async {
    final topics = await Native.tryCall('Here', 'topics');
    if (topics == null || notices == null) {
      return;
    }
    notices = topics['releases'] == true;
    var storedValue = '0';
    if (notices!) {
      storedValue = '1';
    }
    Store.I.put(_releasesKey, storedValue);
    notifyListeners();
  }

  /// Joins or leaves the release topic (Firebase), asking for notifications first.
  Future<void> setNotices(bool on) async {
    final previous = notices;
    notices = null;
    notifyListeners();
    try {
      await Native.call('App', 'setReleases', {'on': on});
      notices = on;
      if (on) {
        Store.I.put(_releasesKey, '1');
        AppNav.toast('You’ll get a notification the moment a new version is out.');
      } else {
        Store.I.put(_releasesKey, '0');
        AppNav.toast('No more notifications of new versions.');
      }
    } on NativeError catch (nativeError) {
      notices = previous;
      String message;
      if (nativeError.code == 'permission') {
        message = 'Notifications are off for uwuHere. Turn them on in Android’s settings, then try again.';
      } else {
        message = 'Couldn’t reach Firebase. Check your connection and try again.';
      }
      AppNav.toast(message, error: true);
      if (nativeError.code == 'permission') {
        Native.tryCall('App', 'openSettings', {'page': 'notifications'});
      }
    }
    notifyListeners();
  }
}

/// The bar at the top: "Checking for updates" while a check someone asked for runs, "Updating"
/// with its progress while a new version downloads, and otherwise "x.y.z is out" while a newer
/// version is out. The first two with Material You's wavy line, as sgbus-timings' updater has them.
class UpdateBar extends StatelessWidget {
  const UpdateBar({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, _) {
        final updates = AndroidUpdates.I;
        final colors = UwuColors.of(context);
        // The bar's own look, around whichever of the three it's showing.
        Widget wrapInBar(Widget child) {
          return Material(
            color: colors.brandFill,
            child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: child)),
          );
        }

        final progress = updates.progress;
        if (progress != null) {
          final percent = (progress * 100).round();
          var targetVersion = 'the new version';
          final newer = updates.newerRelease;
          if (newer != null && newer['version'] != null) {
            targetVersion = '${newer['version']}';
          }
          return wrapInBar(
            Semantics(
              liveRegion: true,
              label: 'Updating to $targetVersion, $percent percent',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Updating to $targetVersion… $percent%', style: TextStyle(color: colors.onBrand, fontSize: 14)),
                    const SizedBox(height: 6),
                    WavyProgress(value: progress, label: 'Updating'),
                  ],
                ),
              ),
            ),
          );
        }
        if (updates.asked && updates.loading) {
          return wrapInBar(
            Semantics(
              liveRegion: true,
              label: 'Checking for updates',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Checking for updates…', style: TextStyle(color: colors.onBrand, fontSize: 14)),
                    const SizedBox(height: 6),
                    WavyProgress(label: 'Checking for updates'),
                  ],
                ),
              ),
            ),
          );
        }
        if (!updates.offered) {
          return const SizedBox.shrink();
        }
        return wrapInBar(
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text('uwuHere ${updates.newerRelease!['version']} is out.', style: TextStyle(color: colors.onBrand, fontSize: 14)),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: colors.surfaceStrong, foregroundColor: colors.ink),
                onPressed: openUpdates,
                child: const Text('Update'),
              ),
              TextButton(
                onPressed: updates.dismiss,
                style: TextButton.styleFrom(foregroundColor: colors.onBrand),
                child: const Text('Not now'),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The device's Material You schemes, as the app's root last had them (app.dart), for the
/// Updates page, which is always in Material You.
ColorScheme? lightDynamicScheme;
ColorScheme? darkDynamicScheme;

/// The Updates page. `check` is the Edge Tray's Check for updates: the bar says it's looking.
Future<void> openUpdates({bool check = false}) async {
  final navigator = AppNav.navigatorKey.currentState;
  if (navigator == null) {
    return;
  }
  AndroidUpdates.I.check(fresh: true, asked: check);
  AndroidUpdates.I.readNotices();
  await navigator.push(
    MaterialPageRoute<void>(
      builder: (_) {
        return const UpdatesPage();
      },
      settings: const RouteSettings(name: 'updates'),
    ),
  );
}

/// A text theme's style in another colour (and weight, when one's given), or no style when the
/// theme has none for it.
TextStyle? _styleWith(TextStyle? style, {required Color color, FontWeight? fontWeight}) {
  if (style == null) {
    return null;
  }
  return style.copyWith(color: color, fontWeight: fontWeight);
}

/// The Updates page: this version, the newest and its Update button, the release notifications
/// switch, and what's new in every version, newest first.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeController.I.brightness;
    ColorScheme? dynamicScheme;
    if (brightness == Brightness.dark) {
      dynamicScheme = darkDynamicScheme;
    } else {
      dynamicScheme = lightDynamicScheme;
    }
    final theme = buildTheme(look: lookMaterial, brightness: brightness, brand: ThemeController.I.colorTheme.color, dynamicScheme: dynamicScheme);
    return Theme(data: theme, child: const _UpdatesBody());
  }
}

class _UpdatesBody extends StatelessWidget {
  const _UpdatesBody();

  /// The page itself: a large title bar, the status card, the notifications switch (where the
  /// APK has Firebase), then every version on a timeline. Pull down to look again.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, _) {
        final updates = AndroidUpdates.I;
        final newer = updates.newerRelease;
        final history = updates.history;

        // The switch shows off while its state is unknown, and can't be pressed while it changes.
        final notices = updates.notices;
        var switchValue = false;
        ValueChanged<bool>? onSwitchChanged;
        if (notices != null) {
          switchValue = notices;
          onSwitchChanged = updates.setNotices;
        }

        String emptyMessage;
        if (updates.failed) {
          emptyMessage = 'Couldn’t load the versions. Pull down to try again.';
        } else {
          emptyMessage = 'No versions published yet.';
        }

        return Scaffold(
          backgroundColor: scheme.surface,
          body: RefreshIndicator(
            onRefresh: () {
              return updates.check(fresh: true);
            },
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  backgroundColor: scheme.surface,
                  surfaceTintColor: scheme.surfaceTint,
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () {
                      Navigator.pop(context);
                    },
                    icon: AppIcon('arrow-left', color: scheme.onSurface),
                  ),
                  title: const Text('Updates'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      _statusCard(context, updates, newer),
                      if (Native.has('push')) ...[
                        const SizedBox(height: 12),
                        Card.filled(
                          color: scheme.surfaceContainer,
                          child: SwitchListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            secondary: AppIcon('bell', color: scheme.onSurfaceVariant),
                            title: const Text('New versions of the app'),
                            subtitle: const Text('A notification the moment a new version is out, even with the app closed.'),
                            value: switchValue,
                            onChanged: onSwitchChanged,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Every version', style: _styleWith(textTheme.titleMedium, color: scheme.primary)),
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty && updates.loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
                          child: WavyProgress(label: 'Loading the versions'),
                        ),
                      if (history.isEmpty && !updates.loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            emptyMessage,
                            style: _styleWith(textTheme.bodyMedium, color: scheme.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: _Timeline(history: history, installedVersion: updates.installedVersion),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  /// The card at the top: up to date (with Check for updates), or the newer version that's out
  /// with its Update button, its download's progress, or what went wrong.
  Widget _statusCard(BuildContext context, AndroidUpdates updates, Map<String, dynamic>? newer) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final upToDate = newer == null;
    final progress = updates.progress;
    final error = updates.error;

    Color cardColor;
    String headline;
    Color headlineColor;
    Color versionColor;
    var updateLabel = 'Update';
    if (upToDate) {
      cardColor = scheme.surfaceContainerHigh;
      headline = 'You’re up to date';
      headlineColor = scheme.onSurface;
      versionColor = scheme.onSurfaceVariant;
    } else {
      cardColor = scheme.primaryContainer;
      headline = 'uwuHere ${newer['version']} is out';
      headlineColor = scheme.onPrimaryContainer;
      versionColor = scheme.onPrimaryContainer;
      final sizeText = _sizeText(newer['size']);
      if (sizeText.isNotEmpty) {
        updateLabel = 'Update ($sizeText)';
      }
    }

    return Card.filled(
      color: cardColor,
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.asset('assets/images/icon-512.png', width: 52, height: 52, excludeFromSemantics: true),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: _styleWith(textTheme.titleLarge, color: headlineColor),
                      ),
                      const SizedBox(height: 2),
                      Text('This is version ${updates.installedVersion}.', style: _styleWith(textTheme.bodyMedium, color: versionColor)),
                    ],
                  ),
                ),
              ],
            ),
            if (!upToDate) ...[
              const SizedBox(height: 16),
              if (progress != null) ...[
                WavyProgress(value: progress, label: 'Downloading'),
                const SizedBox(height: 8),
                Text('Downloading… ${(progress * 100).round()}%', style: _styleWith(textTheme.bodySmall, color: scheme.onPrimaryContainer)),
              ] else if (updates.updatedByPlay)
                FilledButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse(playListing), mode: LaunchMode.externalApplication);
                  },
                  icon: AppIcon('appUpdate', size: 18, color: scheme.onPrimary),
                  label: const Text('Update on Google Play'),
                )
              else
                FilledButton.icon(
                  onPressed: updates.install,
                  icon: AppIcon('appUpdate', size: 18, color: scheme.onPrimary),
                  label: Text(updateLabel),
                ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(error, style: TextStyle(color: scheme.error)),
                ),
            ] else ...[
              const SizedBox(height: 12),
              if (updates.loading) ...[
                const WavyProgress(label: 'Checking for updates'),
                const SizedBox(height: 8),
                Text('Checking for updates…', style: _styleWith(textTheme.bodySmall, color: scheme.onSurfaceVariant)),
              ] else
                OutlinedButton.icon(
                  onPressed: () {
                    updates.check(fresh: true);
                  },
                  icon: AppIcon('refresh', size: 16, color: scheme.primary),
                  label: const Text('Check for updates'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  /// A download's size in megabytes, "12.3 MB", or nothing when the size isn't known.
  static String _sizeText(Object? bytes) {
    if (bytes is num && bytes > 0) {
      return '${(bytes / 1e6).toStringAsFixed(1)} MB';
    }
    return '';
  }
}

/// Every release on a timeline, newest first, as sgbus-timings' updater has them: the ones newer
/// than this copy marked New, this one Installed, and "Earlier releases" before the rest. The one
/// you'd get opens by itself, or this one when there's nothing newer.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.history, required this.installedVersion});
  final List<Map<String, dynamic>> history;
  final String installedVersion;

  @override
  Widget build(BuildContext context) {
    // Which release starts open: the newest when it's newer than this copy, otherwise the first
    // that isn't newer (this one, usually).
    var openIndex = -1;
    if (history.isNotEmpty && newerVersion('${history.first['version']}', installedVersion)) {
      openIndex = 0;
    } else {
      openIndex = history.indexWhere((release) {
        return !newerVersion('${release['version']}', installedVersion);
      });
    }
    final children = <Widget>[];
    var labelled = false;
    for (var index = 0; index < history.length; index = index + 1) {
      final version = '${history[index]['version']}';
      final isNew = newerVersion(version, installedVersion);
      final installed = version == installedVersion;
      if (!isNew && !installed && !labelled) {
        labelled = true;
        children.add(const _EarlierLabel());
      }
      children.add(
        _Release(
          key: ValueKey(version),
          release: history[index],
          isNew: isNew,
          installed: installed,
          openAtFirst: index == openIndex,
          isLast: index == history.length - 1,
        ),
      );
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _EarlierLabel extends StatelessWidget {
  const _EarlierLabel();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Center(child: Container(width: 2, color: scheme.outlineVariant)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 24),
              child: Text('Earlier releases', style: _styleWith(textTheme.titleSmall, color: scheme.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Release extends StatefulWidget {
  const _Release({super.key, required this.release, required this.isNew, required this.installed, required this.openAtFirst, required this.isLast});
  final Map<String, dynamic> release;
  final bool isNew;
  final bool installed;
  final bool openAtFirst;
  final bool isLast;

  @override
  State<_Release> createState() {
    return _ReleaseState();
  }
}

class _ReleaseState extends State<_Release> {
  late bool _open = widget.openAtFirst;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Today, Yesterday, 3 days ago, or 23 Oct 2026.
  static String? _relativeDate(Object? isoDate) {
    var dateText = '';
    if (isoDate != null) {
      dateText = '$isoDate';
    }
    final parsed = DateTime.tryParse(dateText);
    if (parsed == null) {
      return null;
    }
    final date = parsed.toLocal();
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(date.year, date.month, date.day)).inDays;
    if (days <= 0) {
      return 'Today';
    }
    if (days == 1) {
      return 'Yesterday';
    }
    if (days < 7) {
      return '$days days ago';
    }
    return '${date.day} ${_months[date.month - 1]} ${date.year}';
  }

  void _toggleOpen() {
    setState(() {
      _open = !_open;
    });
  }

  /// One release on the timeline: its dot or ring, its version (with New or Installed), when it
  /// came out and how many changes, and, opened, its summary, its groups of changes and a link to
  /// it on GitHub.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final release = widget.release;
    final version = '${release['version']}';
    final notes = ReleaseNotes.parse(release['notes'] as String?);
    final count = notes.count;
    final whenReleased = _relativeDate(release['date']);
    String? changesText;
    if (count != 0) {
      if (count == 1) {
        changesText = '$count change';
      } else {
        changesText = '$count changes';
      }
    }
    final meta = [
      if (whenReleased != null) whenReleased,
      if (changesText != null) changesText,
    ].join(' · ');
    final hasAnything = notes.groups.isNotEmpty || notes.summary.isNotEmpty;
    final showRing = widget.isNew || widget.installed;
    var reduceMotion = false;
    final disableAnimations = MediaQuery.maybeDisableAnimationsOf(context);
    if (disableAnimations != null) {
      reduceMotion = disableAnimations;
    }
    final page = release['page'];

    // The timeline's marker: a ring for the release you'd get or have, a dot for the rest.
    double markerTop;
    double markerSize;
    Color markerColor;
    BoxBorder? markerBorder;
    if (showRing) {
      markerTop = 7;
      markerSize = 16;
      markerColor = scheme.surface;
      markerBorder = Border.all(color: scheme.primary, width: 3);
    } else {
      markerTop = 10;
      markerSize = 10;
      markerColor = scheme.outline;
      markerBorder = null;
    }

    // Only a release with notes opens and closes.
    bool? expandedState;
    VoidCallback? onHeaderTap;
    if (hasAnything) {
      expandedState = _open;
      onHeaderTap = _toggleOpen;
    }

    Color badgeColor;
    String badgeText;
    Color badgeTextColor;
    if (widget.isNew) {
      badgeColor = scheme.primary;
      badgeText = 'New';
      badgeTextColor = scheme.onPrimary;
    } else {
      badgeColor = scheme.primaryContainer;
      badgeText = 'Installed';
      badgeTextColor = scheme.onPrimaryContainer;
    }

    double chevronTurns = 0;
    if (_open) {
      chevronTurns = 0.5;
    }
    Duration animationDuration;
    if (reduceMotion) {
      animationDuration = Duration.zero;
    } else {
      animationDuration = const Duration(milliseconds: 200);
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The timeline: a ring for the release you'd get or have, a dot for the rest.
          SizedBox(
            width: 24,
            child: Stack(
              alignment: Alignment.topCenter,
              children: [
                if (!widget.isLast) Positioned(top: 10, bottom: 0, child: Container(width: 2, color: scheme.outlineVariant)),
                Padding(
                  padding: EdgeInsets.only(top: markerTop),
                  child: Container(
                    width: markerSize,
                    height: markerSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: markerColor,
                      border: markerBorder,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(bottom: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Semantics(
                    button: hasAnything,
                    expanded: expandedState,
                    label: 'Version $version',
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(16),
                      onTap: onHeaderTap,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 0, 4, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Wrap(
                                    crossAxisAlignment: WrapCrossAlignment.center,
                                    spacing: 10,
                                    children: [
                                      Text(
                                        'v$version',
                                        style: _styleWith(textTheme.titleLarge, color: scheme.onSurface, fontWeight: FontWeight.bold),
                                      ),
                                      if (showRing)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: badgeColor,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            badgeText,
                                            style: _styleWith(textTheme.labelLarge, color: badgeTextColor),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (meta.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(meta, style: _styleWith(textTheme.bodyMedium, color: scheme.onSurfaceVariant)),
                                    ),
                                ],
                              ),
                            ),
                            if (hasAnything)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: AnimatedRotation(
                                  turns: chevronTurns,
                                  duration: animationDuration,
                                  child: AppIcon('chevron-down', size: 24, color: scheme.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: animationDuration,
                    alignment: Alignment.topCenter,
                    child: _details(scheme, textTheme, notes, page),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// What's under a release's heading: nothing while it's closed; opened, its summary, its groups
  /// of changes, and a link to it on GitHub when there is one.
  Widget _details(ColorScheme scheme, TextTheme textTheme, ReleaseNotes notes, Object? page) {
    if (!_open) {
      return const SizedBox(width: double.infinity);
    }
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (notes.summary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: Text(notes.summary, style: _styleWith(textTheme.bodyMedium, color: scheme.onSurfaceVariant)),
            ),
          for (var groupIndex = 0; groupIndex < notes.groups.length; groupIndex = groupIndex + 1)
            _GroupCard(group: notes.groups[groupIndex], index: groupIndex),
          if (page is String && page.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(top: 8),
                child: TextButton.icon(
                  onPressed: () {
                    launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication);
                  },
                  icon: AppIcon('link', size: 16, color: scheme.primary),
                  label: const Text('On GitHub'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A group of what's new in a release (a "###" heading in its notes): its icon on a tile of its
/// colour, its name and how many, then its items, the first few with Show all for the rest.
class _GroupCard extends StatefulWidget {
  const _GroupCard({required this.group, required this.index});
  final ReleaseGroup group;
  final int index;

  @override
  State<_GroupCard> createState() {
    return _GroupCardState();
  }
}

class _GroupCardState extends State<_GroupCard> {
  static const _shownAtFirst = 4;
  bool _showAll = false;

  /// The icon for a group, from the words in its title: a phone for Android, a monitor for the
  /// desktop, and so on, or a star when none fits.
  static String _icon(String title) {
    final lowerTitle = title.toLowerCase();
    if (lowerTitle.contains('android') || lowerTitle.contains('phone')) {
      return 'phone';
    }
    if (lowerTitle.contains('windows') || lowerTitle.contains('mac') || lowerTitle.contains('linux') || lowerTitle.contains('desktop')) {
      return 'monitor';
    }
    if (lowerTitle.contains('everywhere') || lowerTitle.contains('website')) {
      return 'globe';
    }
    if (lowerTitle.contains('host')) {
      return 'users';
    }
    if (lowerTitle.contains('check') && lowerTitle.contains('in')) {
      return 'check';
    }
    if (lowerTitle.contains('wifi') || lowerTitle.contains('offline')) {
      return 'wifi';
    }
    if (lowerTitle.contains('tap') || lowerTitle.contains('nfc')) {
      return 'tap';
    }
    if (lowerTitle.contains('bluetooth')) {
      return 'bluetooth';
    }
    if (lowerTitle.contains('look') || lowerTitle.contains('theme')) {
      return 'sun';
    }
    if (lowerTitle.contains('fix') || lowerTitle.contains('easier')) {
      return 'check';
    }
    return 'star';
  }

  void _showEverything() {
    setState(() {
      _showAll = true;
    });
  }

  /// The card: a header with the group's icon tile, title and count, then each item shown (with
  /// its title in bold and its text under it), then Show all while some are still hidden.
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final group = widget.group;
    // Its colours by its place: primary, tertiary, then secondary, round again.
    final tones = [
      (scheme.primaryContainer, scheme.onPrimaryContainer, scheme.primary),
      (scheme.tertiaryContainer, scheme.onTertiaryContainer, scheme.tertiary),
      (scheme.secondaryContainer, scheme.onSecondaryContainer, scheme.secondary),
    ];
    final (tileColor, tileIconColor, accentColor) = tones[widget.index % tones.length];
    List<ReleaseItem> shownItems;
    if (_showAll) {
      shownItems = group.items;
    } else {
      shownItems = group.items.take(_shownAtFirst).toList();
    }
    return Card.outlined(
      margin: const EdgeInsets.only(top: 12),
      color: scheme.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: scheme.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: tileColor, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: AppIcon(_icon(group.title), size: 20, color: tileIconColor)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    group.title,
                    style: _styleWith(textTheme.titleMedium, color: scheme.onSurface, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    '${group.items.length}',
                    textAlign: TextAlign.center,
                    style: _styleWith(textTheme.labelLarge, color: scheme.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          for (final item in shownItems) ...[
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accentColor, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_itemHeadline(item), style: _styleWith(textTheme.titleSmall, color: scheme.onSurface)),
                        if (item.title.isNotEmpty && item.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_capitalised(item.text), style: _styleWith(textTheme.bodyMedium, color: scheme.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_showAll && group.items.length > _shownAtFirst) ...[
            Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: _showEverything,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Show all (${group.items.length})', style: _styleWith(textTheme.labelLarge, color: scheme.primary)),
                    ),
                    AppIcon('chevron-down', size: 20, color: scheme.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// An item's first line: its title, or its text when it has no title, with a capital first.
  static String _itemHeadline(ReleaseItem item) {
    if (item.title.isEmpty) {
      return _capitalised(item.text);
    }
    return _capitalised(item.title);
  }

  /// The text with its first letter a capital.
  static String _capitalised(String text) {
    if (text.isEmpty) {
      return text;
    }
    return text[0].toUpperCase() + text.substring(1);
  }
}
