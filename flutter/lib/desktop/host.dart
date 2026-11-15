// The bridge's host on the desktop (docs/flutter-desktop-app-spec.md §3): the shared screens ask
// Native.call / Native.has as they would on a phone, and this answers in Dart, so the screens
// need no desktop branches. Anything not here fails like an absent plugin ('unavailable'), and
// the screen's plain path runs. Never a phone-only feature (taps, Bluetooth, the hotspot, the
// home screen widget, brightness).
//
//   App   info, launchLink, openLink, notify, background
//   Here  topics / setTopic: the Notifications window's switches. No push on the desktop:
//         "Check-ins to my events" is the every-minute check (alerts_poll.dart), "New versions of
//         the app" the updater's notices (updater.dart), both kept in the settings file.
//         openSettings: the system's own page where there is one.
import 'dart:io';

import '../app/env.dart';
import '../native/bridge.dart';
import 'alerts_poll.dart';
import 'desk.dart';
import 'notify.dart';
import 'settings.dart';

class DesktopHost implements NativeHost {
  @override
  Future<Map<String, dynamic>?> call(String plugin, String method, Map<String, dynamic> options) async {
    if (plugin == 'Here') return _here(method, options);
    if (plugin != 'App') throw NativeError('No plugin $plugin', code: 'unavailable');
    switch (method) {
      case 'info':
        return {
          'platform': 'desktop',
          'version': Env.version,
          // For a bug report (lib/features/bug/bug_report.dart): the system and its version.
          'os': '${Platform.operatingSystem} ${Platform.operatingSystemVersion}',
          'features': ['notifications', 'links', 'glance', 'widgets', 'checkUpdate', 'keepAwake'],
        };
      case 'launchLink':
        final link = Desktop.linkIn(Desktop.launchArgs);
        return {'url': ?link};
      case 'openLink':
        await Desktop.openExternal('${options['url']}');
        return null;
      case 'notify':
        await DeskNotify.show(title: '${options['title'] ?? ''}', body: '${options['body'] ?? ''}', link: options['link'] as String?);
        return null;
      case 'background':
        await Desktop.hide();
        return {};
    }
    throw NativeError('No method $method', code: 'unavailable');
  }

  Future<Map<String, dynamic>?> _here(String method, Map<String, dynamic> o) async {
    switch (method) {
      case 'topics':
        return {
          'checkins': DeskSettings.get<bool>('alertsCheckins') ?? true,
          'releases': DeskSettings.get<bool>('updateNotices') ?? true,
          'news': false,
        };
      case 'setTopic':
        final on = o['on'] == true;
        switch (o['topic']) {
          case 'checkins':
            DeskSettings.write({'alertsCheckins': on});
            AlertsPoll.restart();
          case 'releases':
            DeskSettings.write({'updateNotices': on});
          default:
            throw NativeError('News comes to the Android app only', code: 'unavailable');
        }
        return {'topic': o['topic'], 'on': on};
      case 'openSettings':
        if (Platform.isWindows) await Desktop.openExternal('ms-settings:privacy-location');
        if (Platform.isMacOS) await Desktop.openExternal('x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices');
        return null;
    }
    throw NativeError('No method $method', code: 'unavailable');
  }
}
