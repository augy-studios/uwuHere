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

/// Whether version a comes after version b, number by number: 1.10.0 after 1.9.0. The same as
/// newer() in main-site/api/app-release.js.
bool newerVersion(String a, String b) {
  List<int> parts(String v) => v.split('.').map((n) => int.tryParse(n.replaceAll(RegExp(r'\D'), '')) ?? 0).toList();
  final x = parts(a), y = parts(b);
  for (var i = 0; i < x.length || i < y.length; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d > 0;
  }
  return false;
}

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

  String get mine => Native.version ?? Env.version;

  /// The newest release, when it's newer than this copy.
  Map<String, dynamic>? get newer {
    final l = latest;
    if (l == null || l['version'] is! String) return null;
    return newerVersion(l['version'] as String, mine) ? l : null;
  }

  /// The Play build: Play updates it, so no updater of its own.
  bool get play => isPlayBuild || Native.info?['play'] == true;

  bool get offered => newer != null && !dismissed && !play;

  List<Map<String, dynamic>> get history => [
    for (final h in (latest?['history'] as List? ?? const []))
      if (h is Map) Map<String, dynamic>.from(h),
  ];

  void start() {
    if (_started || !Env.android) return;
    _started = true;
    WidgetsBinding.instance.addObserver(this);
    notices = Store.I.get(_releasesKey) == '1';
    // The Notifications window's switch and this one are the same topic: read where it's kept.
    Native.tryCall('Here', 'topics').then((t) {
      if (t == null) return;
      notices = t['releases'] == true;
      notifyListeners();
    });
    // The notification "x.y.z is out", tapped: this page.
    Native.on('App', 'openUpdates', (_) => openUpdates());
    check();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) return;
    final at = _checkedAt;
    if (at == null || DateTime.now().difference(at) > const Duration(hours: 1)) check();
  }

  /// Whether the check running now was asked for (the bar says so), rather than the quiet one.
  bool asked = false;

  /// `fresh` asks past the site's cache, for a release published a moment ago.
  Future<void> check({bool fresh = false, bool asked = false}) async {
    _checkedAt = DateTime.now();
    loading = true;
    this.asked = asked;
    notifyListeners();
    try {
      final uri = Api.uri('/app-release${fresh ? '?v=${DateTime.now().millisecondsSinceEpoch}' : ''}');
      final res = await Api.client.get(uri).timeout(const Duration(seconds: 20));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final data = jsonDecode(res.body);
      if (data is Map) latest = Map<String, dynamic>.from(data);
      failed = false;
    } catch (_) {
      failed = latest == null;
    }
    loading = false;
    if (this.asked && newer == null && !failed) AppNav.toast('You have the newest version, ${mine.isEmpty ? 'already' : mine}.');
    this.asked = false;
    notifyListeners();
  }

  void dismiss() {
    dismissed = true;
    notifyListeners();
  }

  Future<void> install() async {
    final r = newer;
    if (r == null || progress != null) return;
    error = null;
    progress = 0;
    notifyListeners();
    try {
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}${Platform.pathSeparator}uwuhere-${r['version']}.apk');
      final res = await Api.client.send(http.Request('GET', Uri.parse('${r['apk']}')));
      if (res.statusCode != 200) throw StateError('HTTP ${res.statusCode}');
      final total = (r['size'] as num?)?.toInt() ?? res.contentLength ?? 0;
      final sink = file.openWrite();
      var got = 0;
      await for (final chunk in res.stream) {
        sink.add(chunk);
        got += chunk.length;
        if (total > 0) {
          progress = got / total;
          notifyListeners();
        }
      }
      await sink.close();
      final sum = (await sha256.bind(file.openRead()).first).toString();
      final expected = r['sha256'];
      if (expected is String && expected.isNotEmpty && expected.toLowerCase() != sum) {
        await file.delete();
        throw StateError('checksum');
      }
      progress = 1;
      notifyListeners();
      await Native.call('App', 'installApk', {'path': file.path});
      progress = null;
    } catch (e) {
      progress = null;
      error = e is StateError && e.message == 'checksum'
          ? 'The download didn’t match GitHub’s checksum, so it wasn’t installed. Try again.'
          : (e is NativeError && e.code == 'permission'
                ? 'Allow uwuHere to install apps, then press Update again.'
                : 'Couldn’t download the update. Check your connection and try again.');
    }
    notifyListeners();
  }

  /// Joins or leaves the release topic (Firebase), asking for notifications first.
  Future<void> setNotices(bool on) async {
    final was = notices;
    notices = null;
    notifyListeners();
    try {
      await Native.call('App', 'setReleases', {'on': on});
      notices = on;
      Store.I.put(_releasesKey, on ? '1' : '0');
      AppNav.toast(on ? 'You’ll get a notification the moment a new version is out.' : 'No more notifications of new versions.');
    } on NativeError catch (e) {
      notices = was;
      AppNav.toast(
        e.code == 'permission'
            ? 'Notifications are off for uwuHere. Turn them on in Android’s settings, then try again.'
            : 'Couldn’t reach Firebase. Check your connection and try again.',
        error: true,
      );
      if (e.code == 'permission') Native.tryCall('App', 'openSettings', {'page': 'notifications'});
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
        final u = AndroidUpdates.I;
        final c = UwuColors.of(context);
        Widget bar(Widget child) => Material(
          color: c.brandFill,
          child: SafeArea(bottom: false, child: Padding(padding: const EdgeInsets.fromLTRB(16, 8, 8, 8), child: child)),
        );
        if (u.progress != null) {
          final pct = ((u.progress ?? 0) * 100).round();
          return bar(
            Semantics(
              liveRegion: true,
              label: 'Updating to ${u.newer?['version'] ?? 'the new version'}, $pct percent',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Updating to ${u.newer?['version'] ?? 'the new version'}… $pct%', style: TextStyle(color: c.onBrand, fontSize: 14)),
                    const SizedBox(height: 6),
                    WavyProgress(value: u.progress, label: 'Updating'),
                  ],
                ),
              ),
            ),
          );
        }
        if (u.asked && u.loading) {
          return bar(
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
                    Text('Checking for updates…', style: TextStyle(color: c.onBrand, fontSize: 14)),
                    const SizedBox(height: 6),
                    WavyProgress(label: 'Checking for updates'),
                  ],
                ),
              ),
            ),
          );
        }
        if (!u.offered) return const SizedBox.shrink();
        return bar(
          Row(
            children: [
              Expanded(
                child: Semantics(
                  liveRegion: true,
                  child: Text('uwuHere ${u.newer!['version']} is out.', style: TextStyle(color: c.onBrand, fontSize: 14)),
                ),
              ),
              FilledButton(
                style: FilledButton.styleFrom(backgroundColor: c.surfaceStrong, foregroundColor: c.ink),
                onPressed: openUpdates,
                child: const Text('Update'),
              ),
              TextButton(
                onPressed: u.dismiss,
                style: TextButton.styleFrom(foregroundColor: c.onBrand),
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
  final nav = AppNav.navigatorKey.currentState;
  if (nav == null) return;
  AndroidUpdates.I.check(fresh: true, asked: check);
  await nav.push(
    MaterialPageRoute<void>(
      builder: (_) => const UpdatesPage(),
      settings: const RouteSettings(name: 'updates'),
    ),
  );
}

/// The Updates page: this version, the newest and its Update button, the release notifications
/// switch, and what's new in every version, newest first.
class UpdatesPage extends StatelessWidget {
  const UpdatesPage({super.key});

  @override
  Widget build(BuildContext context) {
    final brightness = ThemeController.I.brightness;
    final dyn = brightness == Brightness.dark ? darkDynamicScheme : lightDynamicScheme;
    final theme = buildTheme(look: lookMaterial, brightness: brightness, brand: ThemeController.I.colorTheme.color, dynamicScheme: dyn);
    return Theme(data: theme, child: const _UpdatesBody());
  }
}

class _UpdatesBody extends StatelessWidget {
  const _UpdatesBody();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: AndroidUpdates.I,
      builder: (context, _) {
        final u = AndroidUpdates.I;
        final newer = u.newer;
        final history = u.history;
        return Scaffold(
          backgroundColor: s.surface,
          body: RefreshIndicator(
            onRefresh: () => u.check(fresh: true),
            child: CustomScrollView(
              slivers: [
                SliverAppBar.large(
                  backgroundColor: s.surface,
                  surfaceTintColor: s.surfaceTint,
                  leading: IconButton(
                    tooltip: 'Back',
                    onPressed: () => Navigator.pop(context),
                    icon: AppIcon('arrow-left', color: s.onSurface),
                  ),
                  title: const Text('Updates'),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                  sliver: SliverList.list(
                    children: [
                      _statusCard(context, u, newer),
                      if (Native.has('push')) ...[
                        const SizedBox(height: 12),
                        Card.filled(
                          color: s.surfaceContainer,
                          child: SwitchListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            secondary: AppIcon('bell', color: s.onSurfaceVariant),
                            title: const Text('New versions of the app'),
                            subtitle: const Text('A notification the moment a new version is out, even with the app closed.'),
                            value: u.notices ?? false,
                            onChanged: u.notices == null ? null : u.setNotices,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text('Every version', style: t.titleMedium?.copyWith(color: s.primary)),
                      ),
                      const SizedBox(height: 8),
                      if (history.isEmpty && u.loading)
                        const Padding(
                          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 24),
                          child: WavyProgress(label: 'Loading the versions'),
                        ),
                      if (history.isEmpty && !u.loading)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Text(
                            u.failed ? 'Couldn’t load the versions. Pull down to try again.' : 'No versions published yet.',
                            style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant),
                          ),
                        ),
                    ],
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                  sliver: SliverToBoxAdapter(
                    child: _Timeline(history: history, mine: u.mine),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _statusCard(BuildContext context, AndroidUpdates u, Map<String, dynamic>? newer) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final up = newer == null;
    return Card.filled(
      color: up ? s.surfaceContainerHigh : s.primaryContainer,
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
                        up ? 'You’re up to date' : 'uwuHere ${newer['version']} is out',
                        style: t.titleLarge?.copyWith(color: up ? s.onSurface : s.onPrimaryContainer),
                      ),
                      const SizedBox(height: 2),
                      Text('This is version ${u.mine}.', style: t.bodyMedium?.copyWith(color: up ? s.onSurfaceVariant : s.onPrimaryContainer)),
                    ],
                  ),
                ),
              ],
            ),
            if (!up) ...[
              const SizedBox(height: 16),
              if (u.progress != null) ...[
                WavyProgress(value: u.progress, label: 'Downloading'),
                const SizedBox(height: 8),
                Text('Downloading… ${((u.progress ?? 0) * 100).round()}%', style: t.bodySmall?.copyWith(color: s.onPrimaryContainer)),
              ] else if (u.play)
                FilledButton.icon(
                  onPressed: () => launchUrl(Uri.parse(playListing), mode: LaunchMode.externalApplication),
                  icon: AppIcon('appUpdate', size: 18, color: s.onPrimary),
                  label: const Text('Update on Google Play'),
                )
              else
                FilledButton.icon(
                  onPressed: u.install,
                  icon: AppIcon('appUpdate', size: 18, color: s.onPrimary),
                  label: Text(_size(newer['size']).isEmpty ? 'Update' : 'Update (${_size(newer['size'])})'),
                ),
              if (u.error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Text(u.error!, style: TextStyle(color: s.error)),
                ),
            ] else ...[
              const SizedBox(height: 12),
              if (u.loading) ...[
                const WavyProgress(label: 'Checking for updates'),
                const SizedBox(height: 8),
                Text('Checking for updates…', style: t.bodySmall?.copyWith(color: s.onSurfaceVariant)),
              ] else
                OutlinedButton.icon(
                  onPressed: () => u.check(fresh: true),
                  icon: AppIcon('refresh', size: 16, color: s.primary),
                  label: const Text('Check for updates'),
                ),
            ],
          ],
        ),
      ),
    );
  }

  static String _size(Object? bytes) => bytes is num && bytes > 0 ? '${(bytes / 1e6).toStringAsFixed(1)} MB' : '';
}

/// Every release on a timeline, newest first, as sgbus-timings' updater has them: the ones newer
/// than this copy marked New, this one Installed, and "Earlier releases" before the rest. The one
/// you'd get opens by itself, or this one when there's nothing newer.
class _Timeline extends StatelessWidget {
  const _Timeline({required this.history, required this.mine});
  final List<Map<String, dynamic>> history;
  final String mine;

  @override
  Widget build(BuildContext context) {
    var open = -1;
    if (history.isNotEmpty && newerVersion('${history.first['version']}', mine)) {
      open = 0;
    } else {
      open = history.indexWhere((r) => !newerVersion('${r['version']}', mine));
    }
    final children = <Widget>[];
    var labelled = false;
    for (var i = 0; i < history.length; i++) {
      final v = '${history[i]['version']}';
      final isNew = newerVersion(v, mine);
      final installed = v == mine;
      if (!isNew && !installed && !labelled) {
        labelled = true;
        children.add(const _EarlierLabel());
      }
      children.add(_Release(key: ValueKey(v), release: history[i], isNew: isNew, installed: installed, openAtFirst: i == open, last: i == history.length - 1));
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
  }
}

class _EarlierLabel extends StatelessWidget {
  const _EarlierLabel();

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 24,
            child: Center(child: Container(width: 2, color: s.outlineVariant)),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 0, 24),
              child: Text('Earlier releases', style: t.titleSmall?.copyWith(color: s.onSurfaceVariant)),
            ),
          ),
        ],
      ),
    );
  }
}

class _Release extends StatefulWidget {
  const _Release({super.key, required this.release, required this.isNew, required this.installed, required this.openAtFirst, required this.last});
  final Map<String, dynamic> release;
  final bool isNew;
  final bool installed;
  final bool openAtFirst;
  final bool last;

  @override
  State<_Release> createState() => _ReleaseState();
}

class _ReleaseState extends State<_Release> {
  late bool _open = widget.openAtFirst;

  static const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

  /// Today, Yesterday, 3 days ago, or 23 Oct 2026.
  static String? _when(Object? iso) {
    final d = DateTime.tryParse('${iso ?? ''}')?.toLocal();
    if (d == null) return null;
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day).difference(DateTime(d.year, d.month, d.day)).inDays;
    if (days <= 0) return 'Today';
    if (days == 1) return 'Yesterday';
    if (days < 7) return '$days days ago';
    return '${d.day} ${_months[d.month - 1]} ${d.year}';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final r = widget.release;
    final v = '${r['version']}';
    final notes = ReleaseNotes.parse(r['notes'] as String?);
    final count = notes.count;
    final when = _when(r['date']);
    final much = count == 0 ? null : '$count ${count == 1 ? 'change' : 'changes'}';
    final meta = [?when, ?much].join(' · ');
    final anything = notes.groups.isNotEmpty || notes.summary.isNotEmpty;
    final ring = widget.isNew || widget.installed;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final page = r['page'];

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
                if (!widget.last) Positioned(top: 10, bottom: 0, child: Container(width: 2, color: s.outlineVariant)),
                Padding(
                  padding: EdgeInsets.only(top: ring ? 7 : 10),
                  child: Container(
                    width: ring ? 16 : 10,
                    height: ring ? 16 : 10,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: ring ? s.surface : s.outline,
                      border: ring ? Border.all(color: s.primary, width: 3) : null,
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
                    button: anything,
                    expanded: anything ? _open : null,
                    label: 'Version $v',
                    child: InkWell(
                      mouseCursor: WidgetStateMouseCursor.clickable,
                      borderRadius: BorderRadius.circular(16),
                      onTap: anything ? () => setState(() => _open = !_open) : null,
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
                                        'v$v',
                                        style: t.titleLarge?.copyWith(color: s.onSurface, fontWeight: FontWeight.bold),
                                      ),
                                      if (ring)
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: widget.isNew ? s.primary : s.primaryContainer,
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Text(
                                            widget.isNew ? 'New' : 'Installed',
                                            style: t.labelLarge?.copyWith(color: widget.isNew ? s.onPrimary : s.onPrimaryContainer),
                                          ),
                                        ),
                                    ],
                                  ),
                                  if (meta.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 4),
                                      child: Text(meta, style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                                    ),
                                ],
                              ),
                            ),
                            if (anything)
                              Padding(
                                padding: const EdgeInsets.only(left: 8),
                                child: AnimatedRotation(
                                  turns: _open ? 0.5 : 0,
                                  duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
                                  child: AppIcon('chevron-down', size: 24, color: s.onSurfaceVariant),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  AnimatedSize(
                    duration: reduce ? Duration.zero : const Duration(milliseconds: 200),
                    alignment: Alignment.topCenter,
                    child: !_open
                        ? const SizedBox(width: double.infinity)
                        : Padding(
                            padding: const EdgeInsets.only(left: 12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                if (notes.summary.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: Text(notes.summary, style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                                  ),
                                for (var g = 0; g < notes.groups.length; g++) _GroupCard(group: notes.groups[g], index: g),
                                if (page is String && page.isNotEmpty)
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: const EdgeInsets.only(top: 8),
                                      child: TextButton.icon(
                                        onPressed: () => launchUrl(Uri.parse(page), mode: LaunchMode.externalApplication),
                                        icon: AppIcon('link', size: 16, color: s.primary),
                                        label: const Text('On GitHub'),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                  ),
                ],
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
  State<_GroupCard> createState() => _GroupCardState();
}

class _GroupCardState extends State<_GroupCard> {
  static const _first = 4;
  bool _all = false;

  static String _icon(String title) {
    final t = title.toLowerCase();
    if (t.contains('android') || t.contains('phone')) return 'phone';
    if (t.contains('windows') || t.contains('mac') || t.contains('linux') || t.contains('desktop')) return 'monitor';
    if (t.contains('everywhere') || t.contains('website')) return 'globe';
    if (t.contains('host')) return 'users';
    if (t.contains('check') && t.contains('in')) return 'check';
    if (t.contains('wifi') || t.contains('offline')) return 'wifi';
    if (t.contains('tap') || t.contains('nfc')) return 'tap';
    if (t.contains('bluetooth')) return 'bluetooth';
    if (t.contains('look') || t.contains('theme')) return 'sun';
    if (t.contains('fix') || t.contains('easier')) return 'check';
    return 'star';
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final t = Theme.of(context).textTheme;
    final g = widget.group;
    // Its colours by its place: primary, tertiary, then secondary, round again.
    final tones = [
      (s.primaryContainer, s.onPrimaryContainer, s.primary),
      (s.tertiaryContainer, s.onTertiaryContainer, s.tertiary),
      (s.secondaryContainer, s.onSecondaryContainer, s.secondary),
    ];
    final (tile, onTile, accent) = tones[widget.index % tones.length];
    final shown = _all ? g.items : g.items.take(_first).toList();
    return Card.outlined(
      margin: const EdgeInsets.only(top: 12),
      color: s.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: s.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            color: s.surfaceContainerHigh,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(color: tile, borderRadius: BorderRadius.circular(10)),
                  child: Center(child: AppIcon(_icon(g.title), size: 20, color: onTile)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Text(
                    g.title,
                    style: t.titleMedium?.copyWith(color: s.onSurface, fontWeight: FontWeight.bold),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  constraints: const BoxConstraints(minWidth: 32),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: s.surfaceContainerHighest, borderRadius: BorderRadius.circular(14)),
                  child: Text(
                    '${g.items.length}',
                    textAlign: TextAlign.center,
                    style: t.labelLarge?.copyWith(color: s.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ),
          for (final item in shown) ...[
            Divider(height: 1, thickness: 1, color: s.outlineVariant),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    margin: const EdgeInsets.only(top: 7),
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_capital(item.title.isEmpty ? item.text : item.title), style: t.titleSmall?.copyWith(color: s.onSurface)),
                        if (item.title.isNotEmpty && item.text.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Text(_capital(item.text), style: t.bodyMedium?.copyWith(color: s.onSurfaceVariant)),
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!_all && g.items.length > _first) ...[
            Divider(height: 1, thickness: 1, color: s.outlineVariant),
            InkWell(
              mouseCursor: WidgetStateMouseCursor.clickable,
              onTap: () => setState(() => _all = true),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text('Show all (${g.items.length})', style: t.labelLarge?.copyWith(color: s.primary)),
                    ),
                    AppIcon('chevron-down', size: 20, color: s.primary),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _capital(String s) => s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
