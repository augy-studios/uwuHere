// System notifications on the desktop (docs/desktop-features-spec.md §7), with the app's name and
// icon, each carrying what its click does. Windows registers the app under its AppUserModelID so
// toasts work unpackaged; macOS asks once; Linux uses the freedesktop service.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desk.dart';

class DeskNotify {
  DeskNotify._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static final Map<String, void Function()> _clicks = {};
  static bool _ready = false;
  static int _next = 1;

  static Future<void> init() async {
    try {
      final ok = await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: false),
          linux: LinuxInitializationSettings(defaultActionName: 'Open uwuHere'),
          windows: WindowsInitializationSettings(appName: Desktop.name, appUserModelId: 'org.uwuapps.here', guid: '01b4b0a4-3cdd-4422-801c-96590a04a18f'),
        ),
        onDidReceiveNotificationResponse: (r) => _clicked(r.payload),
      );
      _ready = ok ?? true;
      // A click that started the app.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) _clicked(launch!.notificationResponse?.payload);
    } catch (_) {
      _ready = false;
    }
    Desktop.stillRunning = () => show(
      title: '${Desktop.name} is still running',
      body: Platform.isMacOS
          ? 'It keeps checking for updates from the menu bar. Quit it from the menu bar icon, or with ⌘Q.'
          : 'It keeps checking for updates from the tray. Quit it from the tray icon.',
    );
  }

  static void _clicked(String? payload) {
    final f = payload == null ? null : _clicks[payload];
    if (f != null) {
      f();
    } else {
      Desktop.show(payload != null && payload.startsWith('uwu://') ? payload : null);
    }
  }

  /// Shows one. `onClick` runs on a click; without it the click brings the window forward, on
  /// `link` if there's one.
  static Future<void> show({required String title, String body = '', String? link, void Function()? onClick}) async {
    if (!_ready) return;
    final id = _next++;
    final payload = onClick != null ? 'click:$id' : link;
    if (onClick != null) _clicks['click:$id'] = onClick;
    try {
      await _plugin.show(id: id, title: title, body: body, payload: payload);
    } catch (_) {}
  }
}
