// The host page's windows (host.html's modals): the QR code as large as the screen allows, the
// event's settings and password, the hotspot's two codes, and ending the event.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/nav.dart';
import '../../data/geo.dart';
import '../../data/here_store.dart';
import '../../data/password.dart';
import '../../theme/theme.dart';
import '../../widgets/colour_picker.dart';
import '../../widgets/here_button.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/sheet.dart';
import '../home/event_fields.dart';
import 'host_controller.dart';

Widget _qr(String data, double size, String label) => Container(
  padding: const EdgeInsets.all(12),
  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
  child: QrImageView(data: data, size: size, padding: EdgeInsets.zero, semanticsLabel: label),
);

/// The QR code, as large as the screen allows, for turning towards a room, at full brightness on
/// Android while it's up.
Future<void> showQrSheet(BuildContext context, HostController c) async {
  if (c.event == null || c.ended) return;
  c.brightness(true);
  await AppSheet.show(
    context,
    id: 'qr',
    width: 640,
    builder: (context) {
      final col = UwuColors.of(context);
      final s = MediaQuery.sizeOf(context);
      final size = math.max(160.0, math.min(s.width - 80, s.height - 300).clamp(160.0, 520.0));
      return SheetFrame(
        title: 'Scan to check in',
        children: [
          if (c.title.isNotEmpty)
            Text(
              c.title,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 20, color: col.ink),
            ),
          const SizedBox(height: 10),
          Center(child: _qr(c.joinLink, size, 'QR code for ${c.joinLink}')),
          const SizedBox(height: 10),
          Text(
            c.code,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 40, letterSpacing: 8, color: col.ink, fontFamily: 'Jua'),
          ),
          Text(
            c.joinLink,
            textAlign: TextAlign.center,
            style: TextStyle(color: col.muted, fontSize: 13),
          ),
        ],
      );
    },
  );
  c.brightness(false);
}

/// The hotspot's two codes: join this phone's wifi, then open its check-in page.
Future<void> showHotspotSheet(BuildContext context, HostController c) {
  return AppSheet.show(
    context,
    id: 'hotspot',
    width: 560,
    builder: (context) {
      final col = UwuColors.of(context);
      final h = c.hotspot;
      final nopass = h['security'] == 'nopass';
      return SheetFrame(
        title: 'Check in without internet',
        children: [
          const Text('1. Scan to join this phone\'s wifi.'),
          const SizedBox(height: 8),
          Center(child: _qr(c.wifiQrText, 200, 'QR code to join the wifi ${h['ssid']}')),
          const SizedBox(height: 6),
          Text(
            nopass ? 'Wifi: ${h['ssid']}' : 'Wifi: ${h['ssid']}, password ${h['password']}',
            textAlign: TextAlign.center,
            style: TextStyle(color: col.muted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Text('2. Then scan to check in.'),
          const SizedBox(height: 8),
          Center(child: _qr('${h['url']}', 200, 'QR code for ${h['url']}')),
          const SizedBox(height: 6),
          Text(
            '${h['url']}',
            textAlign: TextAlign.center,
            style: TextStyle(color: col.muted, fontSize: 13),
          ),
          const Hint(
            'Phones may say this wifi has no internet: stay connected. Check-ins land in the list here, and reach uwuHere once this phone is back online. Keep this page open.',
          ),
          const SizedBox(height: 12),
          OutlinedButton(
            // Stopping closes this window too (the host page listens to hotspotSheetOpen).
            onPressed: c.stopHotspot,
            child: const IconLabel('stop', 'Stop the hotspot'),
          ),
        ],
      );
    },
  );
}

/// End this event?
Future<void> showEndSheet(BuildContext context, HostController c) {
  final pending = c.pendingCount;
  final text =
      'Check-ins close for everyone and the attendee page stops working. The list stays downloadable here for $purgeAfterEndDays days, then it is deleted.'
      '${pending > 0 ? ' $pending check-in${pending == 1 ? ' is' : 's are'} still waiting to be sent from this device.' : ''}';
  return AppSheet.show(
    context,
    id: 'end',
    width: 460,
    builder: (context) => _EndSheet(c: c, text: text),
  );
}

class _EndSheet extends StatefulWidget {
  const _EndSheet({required this.c, required this.text});
  final HostController c;
  final String text;

  @override
  State<_EndSheet> createState() => _EndSheetState();
}

class _EndSheetState extends State<_EndSheet> {
  String _error = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    final col = UwuColors.of(context);
    return SheetFrame(
      title: 'End this event?',
      footer: [
        OutlinedButton(onPressed: () => AppSheet.close(context), child: const Text('Cancel')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: col.errorFill, foregroundColor: col.error),
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final err = await widget.c.end();
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (err != null) {
                    setState(() => _error = err);
                    return;
                  }
                  AppSheet.close(context);
                  AppNav.toast('Event ended');
                },
          child: IconLabel('stop', 'End event', color: col.error),
        ),
      ],
      children: [
        Text(widget.text),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: widget.c.downloadCsv, child: const IconLabel('download', 'Download the list first')),
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Banner2(_error, tone: 'error')],
      ],
    );
  }
}

/// Event settings: everything the home page's form set, the spot, and the password.
Future<void> showSettingsSheet(BuildContext context, HostController c) {
  if (c.event == null) return Future.value();
  return AppSheet.show(
    context,
    id: 'settings',
    width: 560,
    kind: SheetKind.drawer,
    builder: (context) => _SettingsSheet(c: c),
  );
}

class _SettingsSheet extends StatefulWidget {
  const _SettingsSheet({required this.c});
  final HostController c;

  @override
  State<_SettingsSheet> createState() => _SettingsSheetState();
}

class _SettingsSheetState extends State<_SettingsSheet> {
  late final Map<String, dynamic> e = widget.c.event!;
  late final _title = TextEditingController(text: '${e['title'] ?? ''}');
  late final _label = TextEditingController(text: '${e['buttonLabel'] ?? ''}');
  late final _note = TextEditingController(text: '${e['noteLabel'] ?? ''}');
  final _password = TextEditingController();
  late String _colour = '${e['buttonColor'] ?? '#ccffcc'}';
  late final _methods = Methods(
    p2p: e['allowP2p'] == true,
    location: e['allowLocation'] == true,
    tap: e['allowTap'] == true,
    bluetooth: e['allowBluetooth'] == true,
  );
  late int _radius = (e['radius'] as num?)?.toInt() ?? 100;
  Position2? _spot;
  String _spotText = '';
  String _error = '';
  String _pwError = '';
  bool _busy = false;
  bool _pwArmed = false;

  @override
  void initState() {
    super.initState();
    _spotText = e['hasLocation'] == true ? 'Move the spot to where I am now' : 'Set the spot to where I am now';
  }

  @override
  void dispose() {
    for (final c in [_title, _label, _note, _password]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<bool> _takeSpot() async {
    setState(() => _spotText = 'Finding your location');
    try {
      _spot = await widget.c.takeSpot();
      setState(() => _spotText = 'Spot set to here, within about ${_spot!.accuracy.round()} m');
      return true;
    } on GeoError catch (err) {
      setState(() {
        _spotText = 'Set the spot to where I am now';
        _error = err.message;
      });
      return false;
    }
  }

  Future<void> _save() async {
    setState(() => _error = '');
    final buttonLabel = _label.text.trim();
    if (buttonLabel.isEmpty) return setState(() => _error = 'The button needs some text.');
    if (!_methods.any) return setState(() => _error = 'Pick at least one way for people to check in.');
    if (_methods.location && e['hasLocation'] != true && _spot == null && !await _takeSpot()) return;
    setState(() => _busy = true);
    final err = await widget.c.saveSettings({
      'title': _title.text,
      'buttonLabel': buttonLabel,
      'buttonColor': _colour,
      'noteLabel': _note.text,
      'allowP2p': _methods.p2p,
      'allowLocation': _methods.location,
      'allowTap': _methods.tap,
      'allowBluetooth': _methods.bluetooth,
      'radius': _radius,
      if (_spot != null) 'location': _spot!.toJson(),
    });
    if (!mounted) return;
    setState(() => _busy = false);
    if (err != null) return setState(() => _error = err);
    AppSheet.close(context);
    AppNav.toast('Saved');
  }

  Future<void> _setPassword() async {
    final pw = _password.text;
    if (!checkPassword(pw, title: widget.c.title, code: widget.c.code).ok) {
      return setState(() => _pwError = 'That password is not strong enough yet. See the checklist under it.');
    }
    final err = await widget.c.setPassword(pw);
    if (!mounted) return;
    if (err != null) return setState(() => _pwError = err);
    _password.clear();
    setState(() => _pwError = '');
    AppNav.toast('Password set');
  }

  Future<void> _clearPassword() async {
    if (!_pwArmed) {
      setState(() => _pwArmed = true);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _pwArmed = false);
      return;
    }
    final err = await widget.c.setPassword('');
    if (!mounted) return;
    if (err != null) return setState(() => _pwError = err);
    setState(() => _pwArmed = false);
    AppNav.toast('Password removed');
  }

  @override
  Widget build(BuildContext context) {
    final col = UwuColors.of(context);
    final hasPassword = widget.c.event?['hasPassword'] == true;
    return SheetFrame(
      title: 'Event settings',
      children: [
        CountedField(label: 'Event name', controller: _title, max: 80),
        const SizedBox(height: 12),
        CountedField(label: 'Button text', controller: _label, max: 20, onChanged: () => setState(() {})),
        const SizedBox(height: 12),
        const FieldHead('Button colour'),
        ColourPicker(value: _colour, onChanged: (v) => setState(() => _colour = v)),
        const SizedBox(height: 10),
        Center(
          child: HereButton(colour: _colour, label: _label.text.trim().isEmpty ? "I'm here" : _label.text.trim(), size: 140, preview: true),
        ),
        const SizedBox(height: 12),
        CountedField(label: 'Extra field for attendees', controller: _note, max: 40, hint: 'Optional, e.g. Student ID'),
        const SizedBox(height: 12),
        const FieldHead('How people prove they are here'),
        MethodToggles(methods: _methods, onChanged: () => setState(() {})),
        if (_methods.location) ...[
          const SizedBox(height: 12),
          const FieldHead('Within'),
          RadiusPicker(value: _radius, onChanged: (v) => setState(() => _radius = v)),
          const SizedBox(height: 8),
          OutlinedButton(onPressed: _takeSpot, child: IconLabel('pin', _spotText)),
        ],
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Banner2(_error, tone: 'error')],
        const SizedBox(height: 12),
        FilledButton(onPressed: _busy ? null : _save, child: const IconLabel('check', 'Save')),
        const SizedBox(height: 20),
        Text(
          'Password',
          style: TextStyle(fontSize: 13, color: col.muted, fontWeight: FontWeight.w600),
        ),
        Hint(
          hasPassword ? 'A password is set. Anyone with it can manage this event from another device.' : 'No password. Only this device can manage this event.',
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _password,
                obscureText: true,
                maxLength: 128,
                decoration: const InputDecoration(hintText: 'New password', counterText: ''),
                onChanged: (_) => setState(() {}),
                onSubmitted: (_) => _setPassword(),
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _setPassword, child: const Text('Set')),
          ],
        ),
        PasswordChecks(password: _password.text, title: widget.c.title, code: widget.c.code),
        if (hasPassword)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              onPressed: _clearPassword,
              child: Text(
                _pwArmed ? 'Remove it? Only this device will manage the event' : 'Remove the password',
                style: TextStyle(color: _pwArmed ? col.error : null),
              ),
            ),
          ),
        if (_pwError.isNotEmpty) ...[const SizedBox(height: 8), Banner2(_pwError, tone: 'error')],
      ],
    );
  }
}
