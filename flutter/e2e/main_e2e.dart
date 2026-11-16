// The app as the Playwright suite runs it (README.md here): the real screens in a browser, with a
// stand-in for the Android side, so what only the phone can do (tapping phones, Bluetooth, the
// hotspot, the widget, notifications, the Updates page) is at least reached the right way. Every
// call to it lands in window.e2eCalls, and window.e2eEmit(plugin, event, json) says what Android
// would have said. Screen reader support is switched on: it's what the suite finds things by.
//
// Query parameters:
//   ?android=1     draw as the Android app does (its Updates page, Material You by default)
//   ?wallpaper=1   pretend the phone has wallpaper colours (a purple), for Material You
//   ?play=1        as the Google Play build: no updater of its own
//   ?nonfc=1       as a phone without NFC
//   ?desktop=1     drawn as the desktop apps are: their title bar, command bar and events pane
//   ?welcome=1     the desktop's Make it yours window
//   ?native=fluent|tahoe|frosted   with ?desktop=1, which system's glass the second look is
//                  (Windows', macOS's or Linux's), whatever the browser runs on
//   ?notour=1      no tours start by themselves
//   ?page=host|join&id=CODE   open on that page
import 'dart:convert';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:uwuhere/app/app.dart';
import 'package:uwuhere/app/env.dart';
import 'package:uwuhere/data/store.dart';
import 'package:uwuhere/desktop/chrome.dart';
import 'package:uwuhere/desktop/welcome.dart';
import 'package:uwuhere/features/tour/tour.dart';
import 'package:uwuhere/native/bridge.dart';
import 'package:uwuhere/run.dart';
import 'package:uwuhere/theme/theme.dart';

/// The stand-in for the Android side: answers each plugin call the way the phone would, records
/// every call in window.e2eCalls, and lets the tests push events in through window.e2eEmit.
class _FakeAndroid implements NativeHost {
  _FakeAndroid({required this.playBuild, required this.hasNfc}) {
    globalContext.setProperty('e2eCalls'.toJS, <JSAny>[].toJS);
    globalContext.setProperty(
      'e2eEmit'.toJS,
      ((JSString plugin, JSString event, JSString json) {
        Native.emit(plugin.toDart, event.toDart, Map<String, dynamic>.from(jsonDecode(json.toDart) as Map));
      }).toJS,
    );
  }

  /// Whether this pretends to be the Google Play build (no updater of its own).
  final bool playBuild;

  /// Whether this pretends the phone has NFC.
  final bool hasNfc;
  final Map<String, bool> _topics = {'checkins': false, 'releases': false, 'news': false};

  /// Records the call, then answers it as the Android app would for this plugin and method.
  @override
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options) async {
    (globalContext.getProperty('e2eCalls'.toJS) as JSObject)
        .callMethod('push'.toJS, jsonEncode({'plugin': plugin, 'method': method, 'options': options}).toJS);
    switch ('$plugin.$method') {
      case 'App.info':
        return {
          'platform': 'android',
          'version': '2.0.0',
          'build': 5,
          'play': playBuild,
          'release': '16',
          'model': 'Google Pixel 9',
          'sdk': 36,
          'features': [
            'links', 'push', 'brightness', 'savefile', 'settings', 'tap', 'hotspot', 'mesh', 'widget',
            if (!playBuild) 'update',
            if (!playBuild) 'checkupdate',
          ],
        };
      case 'App.launchLink':
        return {};
      case 'Here.tap':
        final String tapState;
        if (options['on'] == true) {
          if (hasNfc) {
            tapState = 'ready';
          } else {
            tapState = 'unsupported';
          }
        } else {
          tapState = 'idle';
        }
        return {'state': tapState};
      case 'Here.bluetooth':
        final String bluetoothState;
        if (options['on'] == true) {
          bluetoothState = 'ready';
        } else {
          bluetoothState = 'idle';
        }
        return {'state': bluetoothState};
      case 'Here.hotspot':
        if (options['on'] != true) {
          return {'state': 'off'};
        }
        return {'state': 'on', 'ssid': 'uwuHere-K7Q2', 'password': 'blue-otter-41', 'security': 'WPA', 'url': 'http://192.168.43.1:8080/'};
      case 'Here.meshCheckIn':
        return {'ok': true, 'at': DateTime.now().toUtc().toIso8601String()};
      case 'Here.saveFile':
        return {'saved': true, 'where': 'downloads'};
      case 'Here.topics':
        return {..._topics, 'permission': 'granted'};
      case 'Here.setTopic':
        _topics['${options['topic']}'] = options['on'] == true;
        return {'topic': options['topic'], 'on': options['on']};
      case 'App.setReleases':
        _topics['releases'] = options['on'] == true;
        return {};
      default:
        return {};
    }
  }
}

/// Reads the query parameters (listed at the top of this file), sets the app up to match them,
/// then starts it the same way the real app starts.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final queryParameters = Uri.base.queryParameters;
  if (queryParameters['notour'] == '1') {
    Tour.off = true;
  }
  if (queryParameters['android'] == '1') {
    Env.androidOverride = true;
    Native.host = _FakeAndroid(playBuild: queryParameters['play'] == '1', hasNfc: queryParameters['nonfc'] != '1');
  }
  if (queryParameters['wallpaper'] == '1') {
    testLightDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2));
    testDarkDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2), brightness: Brightness.dark);
  }
  if (queryParameters['welcome'] == '1') {
    Env.desktopOverride = true;
    await Store.open();
    ThemeController.I.init();
    runApp(WelcomeApp(done: (_) {}));
    return;
  }
  final nativeStyle = NativeStyle.values.where((style) {
    return style.name == queryParameters['native'];
  }).firstOrNull;
  if (nativeStyle != null) {
    ThemeController.styleOverride = nativeStyle;
  }
  if (queryParameters['desktop'] == '1') {
    Env.desktopOverride = true;
    desktopChrome = (context, child) {
      return DesktopChrome(child: child);
    };
  }
  await runUwuHere(const []);
  if (queryParameters['desktop'] == '1') {
    ViewHistory.start();
  }
}
