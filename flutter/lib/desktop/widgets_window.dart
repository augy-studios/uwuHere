// Desktop widgets (docs/desktop-features-spec.md §8), for uwuHere: "Your event", a small frameless
// window showing one event this computer hosts (how many are here, how many left early, who
// checked in last, paused or ended), as the Android app's home screen widget does, because a
// third-party desktop app can't add to the system's widget board. Each is its own window and
// Flutter engine (desktop_multi_window), started from main(args) with { kind: 'widget', id }.
//
// - Added from the tray (Add a widget) or an event's right-click menu (Pin to Desktop Widget). A
//   new one opens in its setup state: pick one of your events, or type its code; Save.
// - Refreshed from the server every 30 s with the event's host key (read from the shared store);
//   the "Updated" time counts on between.
// - Its own buttons: refresh now, change what it shows, pin on top, remove (×).
// - Clicking it opens the event's host page in the main window.
// - Moved by dragging its top; resized from any edge, down to 200 × 110. Default 320 × 220.
// - Kept: each one's event, name, pin and place, reopened where it was when the app starts.
//   Removing one with × forgets it; quitting keeps them all. Not in the taskbar or Alt+Tab.
//
// Keys: widgets: [{ id, code, name, items: [], onTop, bounds }] (the spec's field names).
import 'dart:async';
import 'dart:convert';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../api/api.dart';
import '../data/codes.dart';
import '../data/format.dart';
import '../data/here_store.dart';
import '../data/store.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';
import 'settings.dart';

const widgetChannel = WindowMethodChannel('org.uwuapps.here/widgets', mode: ChannelMode.unidirectional);

class DeskWidgets {
  DeskWidgets._();

  static List<Map<String, dynamic>> all() => [
    for (final w in (DeskSettings.get<List<dynamic>>('widgets') ?? const []))
      if (w is Map) Map<String, dynamic>.from(w),
  ];

  static void save(List<Map<String, dynamic>> list) => DeskSettings.write({'widgets': list});

  static Future<void> _open(Map<String, dynamic> w) async {
    try {
      final c = await WindowController.create(WindowConfiguration(hiddenAtLaunch: true, arguments: jsonEncode({'kind': 'widget', 'id': w['id']})));
      await c.show();
    } catch (_) {
      // No second window on this system.
    }
  }

  /// A new widget, on an event if one's given (else in its setup state).
  static Future<void> add([String? code, String? name]) async {
    final id = 'w${DateTime.now().millisecondsSinceEpoch.toRadixString(36)}';
    final w = <String, dynamic>{'id': id, 'code': code, 'name': name ?? 'Your event', 'items': <dynamic>[], 'onTop': false, 'bounds': null};
    save([...all(), w]);
    await _open(w);
  }

  /// Every kept widget, where it was, as the app starts.
  static Future<void> reopenAll() async {
    for (final w in all()) {
      await _open(w);
    }
  }

  /// The main window answers its widgets: open a link.
  static void listen(void Function(String? link) open) {
    widgetChannel.setMethodCallHandler((call) async {
      if (call.method == 'open') open(call.arguments is String ? call.arguments as String : null);
      return null;
    });
  }
}

/// A widget's own engine: its window set up, then its screen.
Future<void> runWidgetWindow(String id) async {
  await Store.open();
  ThemeController.I.init();
  await windowManager.ensureInitialized();
  final w = DeskWidgets.all().where((x) => x['id'] == id).firstOrNull;
  if (w == null) return;
  final b = w['bounds'];
  await windowManager.waitUntilReadyToShow(
    WindowOptions(
      size: b is Map ? Size((b['width'] as num).toDouble(), (b['height'] as num).toDouble()) : const Size(320, 220),
      minimumSize: const Size(200, 110),
      skipTaskbar: true,
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
      alwaysOnTop: w['onTop'] == true,
      backgroundColor: Colors.transparent,
    ),
  );
  if (b is Map) await windowManager.setPosition(Offset((b['x'] as num).toDouble(), (b['y'] as num).toDouble()));
  await windowManager.setAsFrameless();
  await windowManager.show();
  runApp(_WidgetApp(id: id));
}

class _WidgetApp extends StatefulWidget {
  const _WidgetApp({required this.id});
  final String id;

  @override
  State<_WidgetApp> createState() => _WidgetAppState();
}

class _WidgetAppState extends State<_WidgetApp> with WindowListener {
  Map<String, dynamic> _w = {};
  Map<String, dynamic>? _event;
  List<dynamic> _attendees = const [];
  String _error = '';
  DateTime? _at;
  bool _setup = false;
  final _code = TextEditingController();
  Timer? _poll;
  Timer? _tick;
  Timer? _keep;

  @override
  void initState() {
    super.initState();
    _w = DeskWidgets.all().firstWhere((x) => x['id'] == widget.id, orElse: () => {'id': widget.id});
    _setup = _w['code'] == null;
    windowManager.addListener(this);
    _fetch();
    _poll = Timer.periodic(const Duration(seconds: 30), (_) => _fetch());
    _tick = Timer.periodic(const Duration(seconds: 15), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    _tick?.cancel();
    _code.dispose();
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _fetch() async {
    final code = _w['code'] as String?;
    if (code == null) return;
    // The main window may have opened the event since: its key is in the shared store.
    await Store.I.reload();
    final key = HereStore.hostKey(code);
    if (key == null) {
      if (mounted) setState(() => _error = 'Open $code in uwuHere on this computer first.');
      return;
    }
    final r = await Api.post('host', {'code': code, 'hostKey': key, 'action': 'get'});
    if (!mounted) return;
    setState(() {
      if (r.ok) {
        _event = Map<String, dynamic>.from(r.map['event'] as Map);
        _attendees = (r.map['attendees'] as List?) ?? const [];
        _at = DateTime.now();
        _error = '';
      } else if (r.reason == 'not-found') {
        _event = null;
        _error = 'This event is gone.';
      } else {
        _error = r.offline ? "Couldn't get the list just now." : r.error;
      }
    });
  }

  void _update(Map<String, dynamic> changes) {
    final list = DeskWidgets.all();
    final i = list.indexWhere((x) => x['id'] == widget.id);
    if (i < 0) return;
    list[i] = {...list[i], ...changes};
    _w = list[i];
    DeskWidgets.save(list);
  }

  void _pick(String code, String name) {
    _update({'code': code, 'name': name});
    setState(() {
      _setup = false;
      _event = null;
      _error = '';
    });
    _fetch();
  }

  Future<void> _togglePin() async {
    final on = _w['onTop'] != true;
    _update({'onTop': on});
    await windowManager.setAlwaysOnTop(on);
    setState(() {});
  }

  Future<void> _remove() async {
    DeskWidgets.save(DeskWidgets.all().where((x) => x['id'] != widget.id).toList());
    await windowManager.close();
  }

  void _keepBounds() {
    _keep?.cancel();
    _keep = Timer(const Duration(milliseconds: 500), () async {
      final r = await windowManager.getBounds();
      _update({
        'bounds': {'x': r.left.round(), 'y': r.top.round(), 'width': r.width.round(), 'height': r.height.round()},
      });
    });
  }

  @override
  void onWindowMoved() => _keepBounds();

  @override
  void onWindowResized() => _keepBounds();

  @override
  Widget build(BuildContext context) {
    final t = ThemeController.I;
    final theme = buildTheme(look: lookUwuApps, brightness: t.brightness, brand: t.colorTheme.color, desktop: true);
    return MaterialApp(debugShowCheckedModeBanner: false, theme: theme, home: Builder(builder: _body));
  }

  Widget _body(BuildContext context) {
    final c = UwuColors.of(context);
    Widget small(String icon, String label, VoidCallback onTap, {bool on = false}) => Tooltip(
      message: label,
      child: InkWell(
        mouseCursor: WidgetStateMouseCursor.clickable,
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Padding(padding: const EdgeInsets.all(5), child: AppIcon(icon, size: 14, color: on ? c.brandInk : c.muted)),
      ),
    );
    final e = _event;
    final title = e == null ? '${_w['name'] ?? 'Your event'}' : ('${e['title'] ?? ''}'.isEmpty ? 'Event ${_w['code']}' : '${e['title']}');
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(color: c.bg, borderRadius: BorderRadius.circular(14), border: Border.all(color: c.border)),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DragToMoveArea(
              child: Container(
                color: c.surfaceStrong,
                padding: const EdgeInsets.fromLTRB(10, 4, 4, 4),
                child: Row(
                  children: [
                    Expanded(child: Text(_setup ? 'Your event' : title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.ink, fontSize: 13))),
                    if (!_setup) small('refresh', 'Refresh now', _fetch),
                    if (!_setup) small('edit', 'Change what it shows', () => setState(() => _setup = true)),
                    small('pushpin', 'Keep on top', _togglePin, on: _w['onTop'] == true),
                    small('close', 'Remove', _remove),
                  ],
                ),
              ),
            ),
            Expanded(child: _setup ? _setupView(context) : _eventView(context)),
          ],
        ),
      ),
    );
  }

  Widget _setupView(BuildContext context) {
    final c = UwuColors.of(context);
    final hosted = HereStore.listHosted().where((e) => !e.ended).toList();
    return ListView(
      padding: const EdgeInsets.all(10),
      children: [
        Text('Show one of your events:', style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 6),
        for (final ev in hosted.take(8))
          InkWell(
            mouseCursor: WidgetStateMouseCursor.clickable,
            onTap: () => _pick(ev.code, ev.title.isEmpty ? 'Event ${ev.code}' : ev.title),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text('${ev.title.isEmpty ? 'Untitled event' : ev.title} · ${ev.code}', style: TextStyle(color: c.ink, fontSize: 13)),
            ),
          ),
        if (hosted.isEmpty) Text('No events on this computer yet.', style: TextStyle(color: c.ink, fontSize: 13)),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _code,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(hintText: 'Or its code'),
                onSubmitted: (_) => _save(),
              ),
            ),
            const SizedBox(width: 6),
            FilledButton(onPressed: _save, child: const Text('Save')),
          ],
        ),
      ],
    );
  }

  void _save() {
    final code = normaliseCode(_code.text);
    if (!isValidCode(code)) return;
    _pick(code, 'Event $code');
  }

  Widget _eventView(BuildContext context) {
    final c = UwuColors.of(context);
    final e = _event;
    final left = _attendees.where((a) => a is Map && a['leftEarlyAt'] != null).length;
    Map? latest;
    for (final a in _attendees) {
      if (a is Map && (latest == null || '${a['checkedInAt']}'.compareTo('${latest['checkedInAt']}') > 0)) latest = a;
    }
    final ago = _at == null ? '' : DateTime.now().difference(_at!).inMinutes;
    return InkWell(
      mouseCursor: WidgetStateMouseCursor.clickable,
      onTap: () => widgetChannel.invokeMethod('open', 'uwu://here/host?id=${_w['code']}').catchError((Object _) => null),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (e == null)
              Text(_error.isEmpty ? 'Getting the list…' : _error, style: TextStyle(color: c.muted, fontSize: 13))
            else ...[
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('${_attendees.length}', style: TextStyle(color: c.ink, fontSize: 34, fontFamily: 'Jua', height: 1)),
                  const SizedBox(width: 8),
                  Expanded(child: Text('here${left > 0 ? ', $left left early' : ''}', style: TextStyle(color: c.muted, fontSize: 13))),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                e['ended'] == true ? 'Ended' : (e['paused'] == true ? 'Check-ins paused' : (latest == null ? 'Nobody yet' : 'Last: ${latest['name']} at ${formatTime(latest['checkedInAt'] as String?)}')),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c.ink, fontSize: 13),
              ),
              const Spacer(),
              Text('${_w['code']}${ago == '' ? '' : ' · Updated ${ago == 0 ? 'just now' : '$ago min ago'}'}${_error.isEmpty ? '' : ' · $_error'}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: c.muted, fontSize: 11)),
            ],
          ],
        ),
      ),
    );
  }
}
