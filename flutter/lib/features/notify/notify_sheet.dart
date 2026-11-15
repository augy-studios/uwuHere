// Notifications (main-site/js/app-notify.js): the bell in the Edge Tray opens a window with three
// switches, each a set of FCM topics the app joins on Android (the Here plugin's setTopic), so the
// server keeps no list of phones:
//
//   checkins  "Alex checked in", "Sam left early", for location check-ins and early leavers at
//             events this device hosts (one topic per event, host_alerts.dart)
//   releases  a new version of the app, pushed when a release is published on GitHub
//   news      sent by hand from the Firebase console (flutter/FIREBASE-SETUP.md)
//
// Turning a switch on asks Android's notification permission first (13 and later). On the
// desktop there's no push: check-ins are polled while the app runs, and new versions come from
// its updater, so the same switches answer from the desktop's host (lib/desktop/host.dart).
import 'package:flutter/material.dart';

import '../../native/bridge.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';
import '../update/update_bar.dart';

const _switches = [
  (topic: 'checkins', label: 'Check-ins to my events', hint: 'Who checks in by location or leaves early, at events this device hosts'),
  (topic: 'releases', label: 'New versions of the app', hint: 'When an update is ready to install'),
  (topic: 'news', label: 'News from uwuHere', hint: 'Now and then: new features, and other news'),
];

const _denied = "Notifications are off for uwuHere in Android's settings. Turn them on there, then come back.";
const _offline = "Couldn't reach Firebase. Check you're online, then try again.";

Future<void> openNotifySheet(BuildContext context) =>
    AppSheet.show(context, id: 'notify', width: 460, builder: (context) => const _NotifySheet());

class _NotifySheet extends StatefulWidget {
  const _NotifySheet();

  @override
  State<_NotifySheet> createState() => _NotifySheetState();
}

class _NotifySheetState extends State<_NotifySheet> with WidgetsBindingObserver {
  Map<String, bool> _on = {};
  final Set<String> _busy = {};
  String _note = '';
  bool _settings = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refresh();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // Back from Android's settings with the window still open.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _refresh();
  }

  Future<void> _refresh() async {
    try {
      final t = await Native.call('Here', 'topics');
      if (!mounted) return;
      setState(() {
        // A switch still being changed keeps where it was put: Android's permission dialog
        // brings the app back (and here) before the change is stored.
        _on = {for (final s in _switches) s.topic: _busy.contains(s.topic) ? (_on[s.topic] ?? false) : t?[s.topic] == true};
        // Turned on here, then switched off in Android's settings: say why nothing arrives.
        final denied = t?['permission'] == 'denied';
        if (_on.values.any((v) => v) && denied) {
          _note = _denied;
          _settings = true;
        } else {
          _note = '';
          _settings = false;
        }
      });
    } catch (_) {
      // The switches stay as drawn.
    }
  }

  Future<void> _toggle(String topic, bool on) async {
    setState(() {
      _busy.add(topic);
      _on[topic] = on;
      _note = '';
      _settings = false;
    });
    try {
      await Native.call('Here', 'setTopic', {'topic': topic, 'on': on});
      if (mounted) setState(() => _on[topic] = on);
      // The Updates page has the same switch for new versions.
      if (topic == 'releases') AndroidUpdates.I.readNotices();
    } on NativeError catch (e) {
      if (!mounted) return;
      setState(() {
        _on[topic] = !on;
        if (e.code == 'permission') {
          _note = _denied;
          _settings = true;
        } else {
          _note = e.message.isEmpty ? _offline : e.message;
        }
      });
    } finally {
      if (mounted) setState(() => _busy.remove(topic));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return SheetFrame(
      title: 'Notifications',
      children: [
        for (final s in _switches)
          if (s.topic != 'news' || Native.has('push'))
            MergeSemantics(
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(s.label, style: TextStyle(color: c.ink, fontSize: 15)),
                subtitle: Text(s.hint, style: TextStyle(color: c.muted, fontSize: 12.5)),
                value: _on[s.topic] ?? false,
                onChanged: _busy.contains(s.topic) ? null : (v) => _toggle(s.topic, v),
              ),
            ),
        if (_note.isNotEmpty) Note(_note),
        if (_settings) ...[
          const SizedBox(height: 10),
          OutlinedButton(
            onPressed: () => Native.tryCall('Here', 'openSettings', {'what': 'notifications'}),
            child: const Text("Open Android's settings"),
          ),
        ],
      ],
    );
  }
}
