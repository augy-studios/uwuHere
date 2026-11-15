// The home page (main-site/index.html, js/home.js): join by code, the events this device hosts
// (and opening one from another device by its code), and making an event.
import 'package:flutter/material.dart';

import '../../api/api.dart';
import '../../app/env.dart';
import '../../app/fullscreen.dart';
import '../../app/nav.dart';
import '../../app/pages.dart';
import '../../data/codes.dart';
import '../../data/format.dart';
import '../../data/geo.dart';
import '../../data/here_store.dart';
import '../../data/password.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/colour_picker.dart';
import '../../widgets/common.dart';
import '../../widgets/here_button.dart';
import '../../widgets/page_frame.dart';
import '../tour/tour.dart';
import '../widget/app_widget.dart';
import 'event_fields.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _scroll = ScrollController();
  final _joinCode = TextEditingController();
  final _openCode = TextEditingController();
  String _joinError = '';
  String _openError = '';

  final _title = TextEditingController();
  final _label = TextEditingController(text: "I'm here");
  final _note = TextEditingController();
  final _password = TextEditingController();
  final _titleFocus = FocusNode();
  final _joinFocus = FocusNode();
  String _colour = '#ccffcc';
  final _methods = Methods();
  int _radius = 100;
  String _createError = '';
  String? _creating;
  bool _showPassword = false;

  @override
  void initState() {
    super.initState();
    AppPages.homeFocus.addListener(_jump);
    HereStore.changes('hosted').listen((_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    AppPages.homeFocus.removeListener(_jump);
    _scroll.dispose();
    for (final c in [_joinCode, _openCode, _title, _label, _note, _password]) {
      c.dispose();
    }
    _titleFocus.dispose();
    _joinFocus.dispose();
    super.dispose();
  }

  /// Straight to a box: #join and #host, from the widgets and the launcher's shortcuts.
  void _jump() {
    final where = AppPages.homeFocus.value;
    if (where == null) return;
    AppPages.homeFocus.value = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = TourTargets.key(where == 'join' ? 'join-code' : 'host-form').currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, duration: const Duration(milliseconds: 250), alignment: 0.05);
      (where == 'join' ? _joinFocus : _titleFocus).requestFocus();
    });
  }

  void _go(TextEditingController field, void Function(String) setError, bool host) {
    final code = normaliseCode(field.text);
    if (!isValidCode(code)) {
      setState(() => setError(badCodeMessage));
      return;
    }
    field.clear();
    if (host) {
      AppPages.openHost(code);
    } else {
      AppPages.openJoin(code);
    }
  }

  Future<void> _create() async {
    setState(() => _createError = '');
    final buttonLabel = _label.text.trim();
    final password = _password.text;
    void fail(String m) => setState(() => _createError = m);
    if (buttonLabel.isEmpty) return fail('The button needs some text.');
    if (charCount(buttonLabel) > 20) return fail('The button text can be at most 20 characters.');
    if (!_methods.any) return fail('Pick at least one way for people to check in.');
    if (password.isNotEmpty && !checkPassword(password, title: _title.text).ok) {
      return fail('That password is not strong enough yet. See the checklist under it.');
    }
    Position2? position;
    try {
      if (_methods.location) {
        setState(() => _creating = 'Finding your location');
        try {
          position = await Geo.getPosition();
        } on GeoError catch (e) {
          return fail(e.message);
        }
      }
      setState(() => _creating = 'Creating');
      final r = await Api.post('events', {
        'title': _title.text,
        'buttonLabel': buttonLabel,
        'buttonColor': _colour,
        'noteLabel': _note.text,
        'allowP2p': _methods.p2p,
        'allowLocation': _methods.location,
        'allowTap': _methods.tap,
        'allowBluetooth': _methods.bluetooth,
        'radius': _radius,
        'location': position?.toJson(),
        if (password.isNotEmpty) 'password': password,
      });
      if (!r.ok) return fail(r.offline ? 'Making an event needs a connection.' : r.error);
      final code = '${r.map['code']}';
      final event = Map<String, dynamic>.from(r.map['event'] as Map);
      HereStore.saveHosted(code, '${r.map['hostKey']}', event);
      HereStore.saveHostCache(code, event, (r.map['attendees'] as List?) ?? const []);
      _title.clear();
      _password.clear();
      AppPages.openHost(code);
    } finally {
      if (mounted) setState(() => _creating = null);
    }
  }

  Widget _codeForm({
    required TextEditingController field,
    required String error,
    required void Function(String) setError,
    required String label,
    required String button,
    required bool host,
    FocusNode? focus,
    Key? key,
  }) {
    final c = UwuColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Named(
                label,
                child: TextField(
                  key: key,
                  controller: field,
                  focusNode: focus,
                  maxLength: 7,
                  autocorrect: false,
                  enableSuggestions: false,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, letterSpacing: 4, color: c.ink, fontFamily: 'Jua'),
                  decoration: const InputDecoration(hintText: 'CODE', counterText: ''),
                  onChanged: (v) {
                    final up = v.toUpperCase();
                    if (up != v) field.value = field.value.copyWith(text: up);
                    if (error.isNotEmpty) setState(() => setError(''));
                  },
                  onSubmitted: (_) => _go(field, setError, host),
                ),
              ),
            ),
            const SizedBox(width: 8),
            host
                ? OutlinedButton(onPressed: () => _go(field, setError, host), child: IconLabel('lock', button))
                : FilledButton(onPressed: () => _go(field, setError, host), child: Text(button)),
          ],
        ),
        if (error.isNotEmpty) ...[const SizedBox(height: 8), Banner2(error, tone: 'error')],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final hosted = HereStore.listHosted();
    // The desktop's events pane holds the code box and the events, from 1024 px wide.
    final pane = Env.desktop && !Fullscreen.on.value && MediaQuery.sizeOf(context).width > Env.splitWidth;
    return PageFrame(
      page: AppPages.home,
      controller: _scroll,
      children: [
        if (!pane)
        Card2(
          title: 'Checking in?',
          children: [
            KeyedSubtree(
              key: TourTargets.key('join-code'),
              child: _codeForm(
                field: _joinCode,
                error: _joinError,
                setError: (e) => _joinError = e,
                label: 'Event code',
                button: 'Join',
                host: false,
                focus: _joinFocus,
                key: const ValueKey('join-code'),
              ),
            ),
          ],
        ),
        if (!pane)
        KeyedSubtree(
          key: TourTargets.key('hosted'),
          child: Card2(
            title: 'Your events',
            children: [
              for (final ev in hosted) _HostedRow(ev: ev, onForget: () => setState(() {})),
              if (hosted.isNotEmpty) const SizedBox(height: 10),
              _codeForm(field: _openCode, error: _openError, setError: (e) => _openError = e, label: 'Code of an event you host', button: 'Open', host: true),
              const Hint('Hosting from another device? Enter the code to open its host page.'),
            ],
          ),
        ),
        KeyedSubtree(
          key: TourTargets.key('host-form'),
          child: Card2(
            title: 'Host an event',
            children: [
              CountedField(label: 'Event name', controller: _title, max: 80, hint: 'Weekly meetup', focusNode: _titleFocus, onChanged: () => setState(() {})),
              const SizedBox(height: 14),
              CountedField(label: 'Button text', controller: _label, max: 20, onChanged: () => setState(() {})),
              const SizedBox(height: 14),
              const FieldHead('Button colour'),
              ColourPicker(value: _colour, onChanged: (v) => setState(() => _colour = v)),
              const SizedBox(height: 12),
              Center(
                child: HereButton(colour: _colour, label: _label.text.trim().isEmpty ? "I'm here" : _label.text.trim(), size: 150, preview: true),
              ),
              const SizedBox(height: 14),
              CountedField(label: 'Extra field for attendees', controller: _note, max: 40, hint: 'Optional, e.g. Student ID'),
              const SizedBox(height: 14),
              const FieldHead('How people prove they are here'),
              KeyedSubtree(
                key: TourTargets.key('methods'),
                child: MethodToggles(methods: _methods, onChanged: () => setState(() {})),
              ),
              Hint(_methods.hint()),
              if (_methods.location) ...[
                const SizedBox(height: 14),
                const FieldHead('Within'),
                RadiusPicker(value: _radius, onChanged: (v) => setState(() => _radius = v)),
              ],
              const SizedBox(height: 14),
              const FieldHead('Password'),
              Named(
                'Password',
                child: TextField(
                  controller: _password,
                  obscureText: !_showPassword,
                  maxLength: 128,
                  autocorrect: false,
                  enableSuggestions: false,
                  autofillHints: const [AutofillHints.newPassword],
                  decoration: InputDecoration(
                    hintText: 'Optional',
                    counterText: '',
                    suffixIcon: IconButton(
                      tooltip: _showPassword ? 'Hide the password' : 'Show the password',
                      onPressed: () => setState(() => _showPassword = !_showPassword),
                      icon: AppIcon(_showPassword ? 'close' : 'lock', size: 18, color: c.muted),
                    ),
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const Hint('Lets you open the host page again on another device. A few random words make a strong one.'),
              PasswordChecks(password: _password.text, title: _title.text),
              if (_createError.isNotEmpty) ...[const SizedBox(height: 12), Banner2(_createError, tone: 'error')],
              const SizedBox(height: 14),
              FilledButton(key: const ValueKey('create'), onPressed: _creating == null ? _create : null, child: IconLabel('plus', _creating ?? 'Create event')),
            ],
          ),
        ),
        Center(
          child: TextButton(onPressed: () => openPrivacy(), child: const Text('Privacy')),
        ),
      ],
    );
  }
}

/// One event this device hosts: open it, or forget it here (two presses, as the site's armed()).
class _HostedRow extends StatefulWidget {
  const _HostedRow({required this.ev, required this.onForget});
  final HostedEvent ev;
  final VoidCallback onForget;

  @override
  State<_HostedRow> createState() => _HostedRowState();
}

class _HostedRowState extends State<_HostedRow> {
  bool _armed = false;

  Future<void> _forget() async {
    if (!_armed) {
      setState(() => _armed = true);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted) setState(() => _armed = false);
      return;
    }
    HereStore.forgetHosted(widget.ev.code);
    AppWidgetData.forget(widget.ev.code);
    widget.onForget();
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final ev = widget.ev;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          mouseCursor: WidgetStateMouseCursor.clickable,
          onTap: () => AppPages.openHost(ev.code),
          onSecondaryTapUp: (d) => desktopEventMenu?.call(context, d.globalPosition, ev.code, ev.title.isEmpty ? 'Event ${ev.code}' : ev.title),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 6, 10),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        ev.title.isEmpty ? 'Untitled event' : ev.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: c.ink, fontSize: 15),
                      ),
                      Text('${ev.code} · ${formatDateTime(ev.createdAt)}${ev.ended ? ' · Ended' : ''}', style: TextStyle(color: c.muted, fontSize: 12.5)),
                    ],
                  ),
                ),
                _armed
                    ? TextButton(
                        onPressed: _forget,
                        child: Text('Forget?', style: TextStyle(color: c.error)),
                      )
                    : IconButton(
                        tooltip: 'Forget ${ev.code} on this device. Without a password you cannot get it back.',
                        onPressed: _forget,
                        icon: AppIcon('close', size: 18, color: c.muted),
                      ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The site's Privacy page, in the browser.
Future<void> openPrivacy() async {
  final ok = await openOutside(Uri.parse('$siteOrigin/privacy'));
  if (!ok) AppNav.toast('Could not open the Privacy page');
}
