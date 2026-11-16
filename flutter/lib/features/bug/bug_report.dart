// Report a bug (the site's js/bug-report.js, and SG Bus Timings' own): what went wrong, a way to
// be reached if they'd like an answer, up to three pictures (from the device, or a screenshot of a
// page of the app), and what helps find it (the app's version, the device and the page on show:
// home, a host page or a check-in page and the window open, never an event's code, name or list),
// sent to Augy on Telegram by /api/bug-report. What's typed stays until it's sent, closed or not.
//
// Screenshot a page puts the report away and leaves you in the app, to go to the page you want
// (or a window over it), with Screenshot this page floating at the bottom. With no window open it
// takes the whole page, top to bottom, not just what's on screen (lib/widgets/page_frame.dart's
// PageShots); with a window open, the screen as it is. Then it brings you back to the report. The
// bar floats outside the part of the screen that's taken, so it isn't in the picture. A whole
// page goes marked `full`, so it also reaches Augy as a file, at its full size.
//
// Once it's sent, the report says its ID (main-site/api/bug-report.js, reportId), to quote.
import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:image/image.dart' as img;
import 'package:url_launcher/url_launcher.dart';

import '../../api/api.dart';
import '../../app/env.dart';
import '../../app/files.dart';
import '../../app/nav.dart';
import '../../app/pages.dart';
import '../../data/store.dart';
import '../../native/bridge.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sheet.dart';
import '../../widgets/page_frame.dart';

const _email = 'augy@augystudios.com';
const _draftKey = 'uwuhere.bugDraft';
const _maxShots = 3;

Future<void> openBugReport(BuildContext context) => AppSheet.show(context, id: 'bug', width: 480, builder: (context) => const BugReport());

/// A report's pictures, which outlive its window while you go and find a page to take.
class BugPictures {
  BugPictures._();
  static final List<String> shots = []; // JPEG data URLs
  static final Set<int> full = {}; // whole pages among them: each also goes as a file, at its full size

  static void clear() {
    shots.clear();
    full.clear();
  }

  static void removeAt(int i) {
    shots.removeAt(i);
    final moved = {
      for (final n in full)
        if (n != i) n > i ? n - 1 : n,
    };
    full
      ..clear()
      ..addAll(moved);
  }
}

// ---------- pictures, made away from the screen's thread ----------

/// An image as a JPEG data URL, at most 1600 pixels a side and about 900 KB.
String? bugPhotoJpeg(Uint8List bytes) {
  var image = img.decodeImage(bytes);
  if (image == null) return null;
  final side = math.max(image.width, image.height);
  if (side > 1600) image = img.copyResize(image, width: (image.width * 1600 / side).round(), height: (image.height * 1600 / side).round());
  for (final q in [82, 70, 55, 40]) {
    final out = img.encodeJpg(image, quality: q);
    if (out.length <= 900 * 1024 || q == 40) return 'data:image/jpeg;base64,${base64Encode(out)}';
  }
  return null;
}

/// A whole page as a JPEG data URL that Telegram takes as a photo: no more than 1080 pixels across
/// its shorter side, its longer side no more than 20 times that (any more is cut off at the bottom
/// or the right), its sides adding up to at most 9998, and about 900 KB, rougher and then smaller
/// till it is.
String? bugPageJpeg(Uint8List bytes) {
  final image = img.decodeImage(bytes);
  if (image == null) return null;
  final short = math.min(image.width, image.height);
  final w = math.min(image.width, short * 20);
  final h = math.min(image.height, short * 20);
  var k = math.min(1.0, math.min(1080 / short, 9998 / (w + h)));
  final page = w == image.width && h == image.height ? image : img.copyCrop(image, x: 0, y: 0, width: w, height: h);
  for (var tries = 0; tries < 8; tries++) {
    final out = img.encodeJpg(
      k >= 1 ? page : img.copyResize(page, width: math.max(1, (w * k).floor()), height: math.max(1, (h * k).floor()), interpolation: img.Interpolation.average),
      quality: tries < 2 ? 80 : 68,
    );
    if (out.length <= 900 * 1024 || tries == 7) return 'data:image/jpeg;base64,${base64Encode(out)}';
    if (tries >= 1) k *= 0.82;
  }
  return null;
}

// ---------- Screenshot a page ----------

/// The bar over the app while you find the page to take. Shown by the app's root (app.dart),
/// outside the part of the screen that's taken.
class BugShot {
  BugShot._();
  static final ValueNotifier<bool> shooting = ValueNotifier(false);

  /// Off to the app to find the page to take: the report's window closed, what's typed kept.
  static void start() {
    shooting.value = true;
    AppNav.closeSheets();
  }

  static void back() {
    shooting.value = false;
    final ctx = AppNav.context;
    if (ctx != null) openBugReport(ctx);
  }

  /// The page as it is: with no window open, the whole page drawn top to bottom; otherwise the
  /// screen. Returns the picture and whether it's a whole page (bigger than the screen).
  static Future<(String, bool)?> take(BuildContext context) async {
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final screen = MediaQuery.sizeOf(context) * ratio;
    ui.Image? shot;
    var whole = false;
    if (!AppSheet.anyOpen) {
      shot = await PageShots.whole(AppPages.active(), ratio: math.min(2, ratio), maxHeight: 16000);
      whole = shot != null && (shot.height > screen.height + 4 || shot.width > screen.width + 4);
    }
    if (shot == null) {
      final box = AppNav.repaintKey.currentContext?.findRenderObject();
      if (box is! RenderRepaintBoundary) return null;
      shot = await box.toImage(pixelRatio: math.min(2, ratio));
      if (context.mounted) shot = await PageShots.solid(shot, UwuColors.of(context));
    }
    final png = await shot.toByteData(format: ui.ImageByteFormat.png);
    shot.dispose();
    if (png == null) return null;
    final bytes = png.buffer.asUint8List();
    final jpeg = await compute(whole ? bugPageJpeg : bugPhotoJpeg, bytes);
    return jpeg == null ? null : (jpeg, whole);
  }
}

class BugShotBar extends StatefulWidget {
  const BugShotBar({super.key});

  @override
  State<BugShotBar> createState() => _BugShotBarState();
}

class _BugShotBarState extends State<BugShotBar> {
  bool _busy = false;

  Future<void> _take() async {
    setState(() => _busy = true);
    // The button's press drawn and gone before the page is.
    await WidgetsBinding.instance.endOfFrame;
    try {
      final got = mounted ? await BugShot.take(context) : null;
      if (got == null) throw StateError('no picture');
      if (BugPictures.shots.length < _maxShots) {
        BugPictures.shots.add(got.$1);
        if (got.$2) BugPictures.full.add(BugPictures.shots.length - 1);
      }
    } catch (_) {
      AppNav.toast('Couldn’t take a screenshot here. Take one with your device and add it instead.', error: true);
    }
    if (mounted) setState(() => _busy = false);
    BugShot.back();
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Center(
            child: Material(
              color: c.surfaceStrong,
              elevation: 6,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(18),
                side: BorderSide(color: c.border),
              ),
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: FilledButton.icon(
                        key: const ValueKey('bug-shot-take'),
                        onPressed: _busy ? null : _take,
                        icon: _busy
                            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                            : AppIcon('screenshot', size: 16, color: c.onBrand),
                        label: Text(_busy ? 'Taking a screenshot…' : 'Screenshot this page', overflow: TextOverflow.ellipsis),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Cancel',
                      excludeSemantics: true,
                      child: IconButton(
                        key: const ValueKey('bug-shot-cancel'),
                        onPressed: _busy ? null : BugShot.back,
                        icon: AppIcon('close', size: 18, color: c.ink),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------- the report ----------

/// The windows that can be open over the page (AppSheet ids), by what they're called.
const _windows = {
  'qr': 'QR code',
  'settings': 'Event settings',
  'hotspot': 'Hotspot',
  'end': 'End event',
  'leave': 'Leaving early',
  'notify': 'Notifications',
  'theme': 'Theme',
  'tour': 'Show me around',
};

class BugReport extends StatefulWidget {
  const BugReport({super.key});

  /// What's sent with it, as the site's form sends it.
  static Map<String, String> details(BuildContext context) {
    final info = Native.info;
    final size = MediaQuery.sizeOf(context);
    final screen = '${size.width.round()}×${size.height.round()}';
    final String platform;
    final String device;
    if (Env.android) {
      platform = 'android';
      final release = info?['release'] ?? '';
      device = [
        'Android $release'.trim(),
        if (info?['model'] != null) '${info!['model']}',
        if (info?['sdk'] != null) 'API ${info!['sdk']}',
        screen,
      ].join(' · ');
    } else if (Env.desktop) {
      platform = 'desktop';
      final os = '${info?['os'] ?? ''}'.trim();
      device = [os.isNotEmpty ? os : defaultTargetPlatform.name, screen].join(' · ');
    } else {
      platform = 'web';
      device = ['Flutter web', screen].join(' · ');
    }
    return {'version': Native.version ?? Env.version, 'platform': platform, 'device': device, 'page': page()};
  }

  /// The page on show, and the windows open over it, except this one: never a name.
  static String page() {
    final parts = <String>[
      switch (AppPages.active()) {
        AppPages.host => 'Host page',
        AppPages.join => 'Check-in page',
        _ => 'Home',
      },
    ];
    for (final id in AppSheet.open.value) {
      final name = _windows[id];
      if (name != null) parts.add(name);
    }
    return parts.join(', ');
  }

  static const _platformNames = {'android': 'Android app', 'desktop': 'Desktop app', 'web': 'Web'};

  static String detailsText(Map<String, String> d) =>
      [_platformNames[d['platform']], d['version'], d['device'], d['page']].where((s) => s != null && s.isNotEmpty).join(' · ');

  @override
  State<BugReport> createState() => _BugReportState();
}

/// What a failed send said, and its HTTP status (0 when the server was never reached).
class ApiError implements Exception {
  ApiError(this.message, {this.status = 0});
  final String message;
  final int status;
}

class _BugReportState extends State<BugReport> {
  late final Map<String, dynamic> _draft = _readDraft();
  late final _text = TextEditingController(text: _draft['text'] as String? ?? '');
  late final _contact = TextEditingController(text: _draft['contact'] as String? ?? '');
  // What it adds, as the window opened: the page under it, not this window.
  Map<String, String>? _details;
  List<String> get _shots => BugPictures.shots;
  bool _sending = false;
  String _status = '';
  bool _offerEmail = false;

  static Map<String, dynamic> _readDraft() {
    try {
      final v = jsonDecode(Store.I.get(_draftKey) ?? '{}');
      return v is Map ? Map<String, dynamic>.from(v) : {};
    } catch (_) {
      return {};
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _details ??= BugReport.details(context);
  }

  @override
  void dispose() {
    _text.dispose();
    _contact.dispose();
    super.dispose();
  }

  void _keep() => Store.I.put(_draftKey, jsonEncode({'text': _text.text, 'contact': _contact.text}));

  Future<void> _pick() async {
    final files = await pickImages();
    for (final f in files.take(_maxShots - _shots.length)) {
      final s = await compute(bugPhotoJpeg, await f.readAsBytes()).catchError((_) => null);
      if (s != null) {
        _shots.add(s);
      } else if (mounted) {
        setState(() => _status = 'Couldn’t add that picture.');
      }
    }
    if (mounted) setState(() {});
  }

  void _screenshot() {
    _keep();
    BugShot.start();
  }

  Future<void> _send() async {
    final text = _text.text.trim();
    if (text.length < 5) return setState(() => _status = 'Please say what went wrong first.');
    if (Api.offline.value) return setState(() => _status = 'You’re offline. It’s kept here: send it once you’re back online.');
    setState(() {
      _sending = true;
      _status = 'Sending…';
      _offerEmail = false;
    });
    try {
      final res = await Api.raw(
        '/bug-report',
        method: 'POST',
        body: {..._details!, 'text': text, 'contact': _contact.text.trim(), 'website': '', 'images': _shots, 'full': (BugPictures.full.toList()..sort())},
      );
      if (res == null) throw ApiError('', status: 0);
      if (res.status < 200 || res.status >= 300) throw ApiError('${res.json['error'] ?? ''}', status: res.status);
      final r = res.json;
      final id = r['id'] is String ? r['id'] as String : null;
      _text.clear();
      _contact.clear();
      BugPictures.clear();
      Store.I.put(_draftKey, null);
      _status = id != null ? 'Sent as report $id. Thank you! Augy will look into it.' : 'Sent. Thank you! Augy will look into it.';
    } on ApiError catch (e) {
      // Something about what was typed, or too many at once: said as it is. Otherwise, email.
      if (e.status == 400 || e.status == 413 || e.status == 429) {
        _status = e.message.isNotEmpty ? e.message : 'Couldn’t send it right now.';
      } else {
        _status = e.status == 503 ? 'Bug reports can’t be sent from the app yet.' : 'Couldn’t send it right now.';
        _offerEmail = true;
      }
    } catch (_) {
      _status = 'Couldn’t send it right now.';
      _offerEmail = true;
    }
    if (mounted) setState(() => _sending = false);
  }

  void _emailInstead() {
    final body = '${_text.text.trim()}\n\n${BugReport.detailsText(_details!)}';
    final uri = Uri.parse('mailto:$_email?subject=${Uri.encodeComponent('uwuHere bug report')}&body=${Uri.encodeComponent(body)}');
    launchUrl(uri, mode: LaunchMode.externalApplication).catchError((_) => false);
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final full = _shots.length >= _maxShots;
    final note = TextStyle(color: c.muted, fontSize: 12.5);
    return SheetFrame(
      title: 'Report a bug',
      footer: [
        const SizedBox.shrink(),
        FilledButton.icon(
          key: const ValueKey('bug-send'),
          onPressed: _sending ? null : _send,
          icon: AppIcon('send', size: 16, color: c.onBrand),
          label: const Text('Send'),
        ),
      ],
      children: [
        const FieldLabel('What went wrong?'),
        Named(
          'What went wrong?',
          child: TextField(
            key: const ValueKey('bug-text'),
            controller: _text,
            minLines: 4,
            maxLines: 10,
            maxLength: 2000,
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) => _keep(),
            decoration: const InputDecoration(hintText: 'What you did, what happened, and what you expected', counterText: ''),
          ),
        ),
        const FieldLabel('How to reach you', note: '(optional)'),
        Named(
          'How to reach you',
          child: TextField(
            key: const ValueKey('bug-contact'),
            controller: _contact,
            maxLength: 200,
            autocorrect: false,
            onChanged: (_) => _keep(),
            decoration: const InputDecoration(hintText: 'Telegram @name or email, for an answer', counterText: ''),
          ),
        ),
        const FieldLabel('Pictures', note: '(optional)'),
        if (_shots.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (i, s) in _shots.indexed)
                  Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.memory(
                          base64Decode(s.split(',').last),
                          width: 72,
                          height: 96,
                          fit: BoxFit.cover,
                          alignment: Alignment.topCenter,
                          semanticLabel: 'Picture ${i + 1}',
                        ),
                      ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: Semantics(
                          button: true,
                          label: 'Remove picture ${i + 1}',
                          excludeSemantics: true,
                          child: InkWell(
                            mouseCursor: WidgetStateMouseCursor.clickable,
                            customBorder: const CircleBorder(),
                            onTap: () => setState(() => BugPictures.removeAt(i)),
                            child: Container(
                              width: 24,
                              height: 24,
                              decoration: const BoxDecoration(color: Color(0xA6000000), shape: BoxShape.circle),
                              child: const Center(child: AppIcon('close', size: 14, color: Colors.white)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('bug-add-pictures'),
              onPressed: full ? null : _pick,
              icon: AppIcon('image', size: 16, color: full ? c.muted : c.ink),
              label: const Text('Add pictures'),
            ),
            OutlinedButton.icon(
              key: const ValueKey('bug-screenshot'),
              onPressed: full ? null : _screenshot,
              icon: AppIcon('screenshot', size: 16, color: full ? c.muted : c.ink),
              label: const Text('Screenshot a page'),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Up to 3. Screenshot a page puts this away: go to the page you want, or open a window, '
            'then press Screenshot this page. It takes the whole page, top to bottom, and brings you back here.',
            style: note,
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text('Sent with it, to help find the bug: ${BugReport.detailsText(_details!)}.', style: note),
        ),
        if (_status.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _status,
                key: const ValueKey('bug-status'),
                style: TextStyle(color: c.ink, fontWeight: FontWeight.w600, fontSize: 13),
              ),
            ),
          ),
        if (_offerEmail)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(onPressed: _emailInstead, child: const Text('Email it instead.')),
          ),
      ],
    );
  }
}
