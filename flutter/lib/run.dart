// uwuHere's apps: start-up (main.dart runs it). The store, what the old Capacitor app kept brought
// across once, the native bridge (or the desktop's host in its place), the theme, then the app.
// The desktop's extra windows (its welcome window, update window and widgets) start here too,
// from their arguments.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'api/api.dart';
import 'app/app.dart';
import 'app/env.dart';
import 'app/fullscreen.dart';
import 'app/links.dart';
import 'app/nav.dart';
import 'data/migrate.dart';
import 'data/store.dart';
import 'desktop/desktop_main_stub.dart' if (dart.library.io) 'desktop/desktop_main.dart';
import 'features/update/update_bar.dart';
import 'native/bridge.dart';
import 'theme/theme.dart';

/// The app's start-up, for main() and the Playwright suite's entry point (e2e/main_e2e.dart).
Future<void> runUwuHere(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  // A desktop widget's own window runs only its small screen.
  if (Env.desktop && await runDesktopSubWindow(arguments)) return;

  await Store.open();
  try {
    Env.version = (await PackageInfo.fromPlatform()).version;
  } catch (_) {
    Env.version = '';
  }

  final desktop = Env.desktop && !kIsWeb;
  if (desktop) await desktopBeforeApp(arguments);
  await Native.start();

  // The first launch after the WebView app: the events this phone hosts and the rest, brought
  // across once.
  final movedCount = await Migrate.run(Store.I);

  ThemeController.isAndroid = () {
    return Env.android;
  };
  ThemeController.isDesktop = () {
    return Env.desktop;
  };
  ThemeController.I.init();
  Api.watchOffline();
  await Fullscreen.applySystemBars();

  // Links from the platform: the one that opened the app, and any that come after.
  Native.on('App', 'link', (data) {
    final url = data['url'];
    if (url is String) Links.open(url);
  });
  final launch = await Native.tryCall('App', 'launchLink');
  String? firstLink;
  if (launch != null) {
    firstLink = launch['url'] as String?;
  }
  // In the browser (the Playwright suite's build), the page's own address.
  if (kIsWeb && firstLink == null) {
    final pageAddress = Uri.base;
    final page = pageAddress.queryParameters['page'];
    final id = pageAddress.queryParameters['id'];
    if (page == 'host' || page == 'join') {
      String query = '';
      if (id != null) {
        query = '?id=$id';
      }
      firstLink = '$siteOrigin/$page$query';
    }
  }
  if (firstLink != null) Links.open(firstLink);

  runApp(const UwuHereApp());

  // Once the app is on screen (its first frame is drawn empty, app.dart): a link that opened it,
  // and a word about what came across from the old app.
  WidgetsBinding.instance.addPostFrameCallback((_) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Links.appShown();
      if (movedCount > 0) AppNav.toast('Your events and settings are here from before.');
    });
  });
  if (Env.android) AndroidUpdates.I.start();
  if (desktop) await desktopAfterApp(arguments);
}
