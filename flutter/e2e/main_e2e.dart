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

class _FakeAndroid implements NativeHost {
  _FakeAndroid({required this.play, required this.nfc}) {
    globalContext.setProperty('e2eCalls'.toJS, <JSAny>[].toJS);
    globalContext.setProperty(
      'e2eEmit'.toJS,
      ((JSString plugin, JSString event, JSString json) {
        Native.emit(plugin.toDart, event.toDart, Map<String, dynamic>.from(jsonDecode(json.toDart) as Map));
      }).toJS,
    );
  }

  final bool play;
  final bool nfc;
  final Map<String, bool> _topics = {'checkins': false, 'releases': false, 'news': false};

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
          'play': play,
          'release': '16',
          'model': 'Google Pixel 9',
          'sdk': 36,
          'features': [
            'links', 'push', 'brightness', 'savefile', 'settings', 'tap', 'hotspot', 'mesh', 'widget',
            if (!play) 'update',
            if (!play) 'checkupdate',
          ],
        };
      case 'App.launchLink':
        return {};
      case 'Here.tap':
        return {'state': options['on'] == true ? (nfc ? 'ready' : 'unsupported') : 'idle'};
      case 'Here.bluetooth':
        return {'state': options['on'] == true ? 'ready' : 'idle'};
      case 'Here.hotspot':
        if (options['on'] != true) return {'state': 'off'};
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

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SemanticsBinding.instance.ensureSemantics();
  final q = Uri.base.queryParameters;
  if (q['notour'] == '1') Tour.off = true;
  if (q['android'] == '1') {
    Env.androidOverride = true;
    Native.host = _FakeAndroid(play: q['play'] == '1', nfc: q['nonfc'] != '1');
  }
  if (q['wallpaper'] == '1') {
    testLightDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2));
    testDarkDynamic = ColorScheme.fromSeed(seedColor: const Color(0xFF7B3FF2), brightness: Brightness.dark);
  }
  if (q['welcome'] == '1') {
    Env.desktopOverride = true;
    await Store.open();
    ThemeController.I.init();
    runApp(WelcomeApp(done: (_) {}));
    return;
  }
  final native = NativeStyle.values.where((v) => v.name == q['native']).firstOrNull;
  if (native != null) ThemeController.styleOverride = native;
  if (q['desktop'] == '1') {
    Env.desktopOverride = true;
    desktopChrome = (context, child) => DesktopChrome(child: child);
  }
  await runUwuHere(const []);
  if (q['desktop'] == '1') ViewHistory.start();
}
