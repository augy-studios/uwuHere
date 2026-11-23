// System notifications on the desktop (docs/desktop-features-spec.md §7), with the app's name and
// icon, each carrying what its click does. Windows registers the app under its AppUserModelID so
// toasts work unpackaged; macOS asks once; Linux uses the freedesktop service.
import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'desk.dart';

class DeskNotify {
  DeskNotify._();

  static final _plugin = FlutterLocalNotificationsPlugin();

  /// What a click on each notification with its own action does, by its payload ('click:<id>').
  static final Map<String, void Function()> _clickActions = {};
  static bool _ready = false;
  static int _nextId = 1;

  /// Sets up the system's notifications, handles a click that started the app, and gives the
  /// window's close button its "still running" notice.
  static Future<void> initialize() async {
    try {
      final initialized = await _plugin.initialize(
        settings: const InitializationSettings(
          macOS: DarwinInitializationSettings(requestAlertPermission: true, requestBadgePermission: true, requestSoundPermission: false),
          linux: LinuxInitializationSettings(defaultActionName: 'Open uwuHere'),
          windows: WindowsInitializationSettings(appName: Desktop.name, appUserModelId: 'org.uwuapps.here', guid: '01b4b0a4-3cdd-4422-801c-96590a04a18f'),
        ),
        onDidReceiveNotificationResponse: (response) {
          _clicked(response.payload);
        },
      );
      if (initialized == null) {
        _ready = true;
      } else {
        _ready = initialized;
      }
      // A click that started the app.
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch != null && launch.didNotificationLaunchApp == true) {
        final launchResponse = launch.notificationResponse;
        String? launchPayload;
        if (launchResponse != null) launchPayload = launchResponse.payload;
        _clicked(launchPayload);
      }
    } catch (_) {
      _ready = false;
    }
    Desktop.stillRunning = () {
      String body;
      if (Platform.isMacOS) {
        body = 'It keeps checking for updates from the menu bar. Quit it from the menu bar icon, or with ⌘Q.';
      } else {
        body = 'It keeps checking for updates from the tray. Quit it from the tray icon.';
      }
      show(title: '${Desktop.name} is still running', body: body);
    };
  }

  /// A notification was clicked: its own action if it has one, otherwise the window comes
  /// forward, on the notification's link if it carries one.
  static void _clicked(String? payload) {
    void Function()? action;
    if (payload != null) action = _clickActions[payload];
    if (action != null) {
      action();
    } else {
      String? link;
      if (payload != null && payload.startsWith('uwu://')) link = payload;
      Desktop.show(link);
    }
  }

  /// Shows one. `onClick` runs on a click; without it the click brings the window forward, on
  /// `link` if there's one.
  static Future<void> show({required String title, String body = '', String? link, void Function()? onClick}) async {
    if (!_ready) return;
    final id = _nextId;
    _nextId = _nextId + 1;
    String? payload;
    if (onClick != null) {
      payload = 'click:$id';
    } else {
      payload = link;
    }
    if (onClick != null) _clickActions['click:$id'] = onClick;
    try {
      await _plugin.show(id: id, title: title, body: body, payload: payload);
    } catch (_) {}
  }
}
