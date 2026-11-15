// The check-in page (main-site/join.html, js/join.js): the code box when there's no code, a
// message for an event that isn't there or has ended, or the big button with the name above it
// and "I'm leaving early" under it.
import 'package:flutter/material.dart';

import '../../app/pages.dart';
import '../../data/codes.dart';
import '../../data/format.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/edge_tray.dart';
import '../../widgets/here_button.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';
import 'join_controller.dart';

class JoinScreen extends StatefulWidget {
  const JoinScreen({super.key});

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  JoinController? _c;
  final _nameFocus = FocusNode();
  final _code = TextEditingController();
  String _codeError = '';

  @override
  void initState() {
    super.initState();
    AppPages.joinOpened.addListener(_opened);
    AppPages.current.addListener(_actions);
    AppPages.refreshers[AppPages.join] = () async => _c?.load();
    _opened();
  }

  @override
  void dispose() {
    AppPages.joinOpened.removeListener(_opened);
    AppPages.current.removeListener(_actions);
    _c?.focusName.removeListener(_focusName);
    _c?.dispose();
    _nameFocus.dispose();
    _code.dispose();
    super.dispose();
  }

  void _focusName() => _nameFocus.requestFocus();

  /// The page opened by a link or the code box: the same event takes a new tap; another event
  /// starts again.
  void _opened() {
    final code = AppPages.joinCode.value ?? '';
    final tap = AppPages.joinTap;
    AppPages.joinTap = null;
    if (_c != null && _c!.code == code) {
      if (tap != null) _c!.takeTap(tap);
      return;
    }
    _c?.focusName.removeListener(_focusName);
    _c?.dispose();
    final c = JoinController(code, tap: tap);
    c.focusName.addListener(_focusName);
    _c = c;
    c.boot();
    if (mounted) setState(() {});
    _actions();
  }

  void _actions() {
    if (AppPages.active() != AppPages.join) return;
    if (PageActions.items.value.length == 1 && PageActions.items.value.first.label == 'Home') return;
    PageActions.items.value = [TrayItem(icon: 'home', label: 'Home', onTap: () => AppPages.open(AppPages.home))];
  }

  void _submitCode() {
    final typed = normaliseCode(_code.text);
    if (!isValidCode(typed)) {
      setState(() => _codeError = badCodeMessage);
      return;
    }
    _code.clear();
    AppPages.openJoin(typed);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c!;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        switch (c.view) {
          case 'loading':
            return PageFrame(
              page: AppPages.join,
              children: [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))],
            );
          case 'code':
            return PageFrame(page: AppPages.join, children: [_codeCard(context)]);
          case 'message':
            return PageFrame(
              page: AppPages.join,
              children: [
                Card2(
                  title: c.messageTitle,
                  big: true,
                  children: [
                    Text(c.messageText),
                    if (c.messageAction != null) ...[
                      const SizedBox(height: 14),
                      OutlinedButton(
                        onPressed: () => c.messageAction == 'reload' ? c.load() : AppPages.openJoin(null),
                        child: IconLabel('refresh', c.messageAction == 'reload' ? 'Try again' : 'Try another code'),
                      ),
                    ],
                  ],
                ),
              ],
            );
        }
        return _checkin(context, c);
      },
    );
  }

  Widget _codeCard(BuildContext context) {
    final col = UwuColors.of(context);
    return Card2(
      title: 'Enter the event code',
      big: true,
      children: [
        Text("It is on the host's screen, under the QR code.", style: TextStyle(color: col.muted)),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Named(
                'Event code',
                child: TextField(
                  controller: _code,
                  maxLength: 7,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.characters,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 20, letterSpacing: 4, color: col.ink, fontFamily: 'Jua'),
                  decoration: const InputDecoration(hintText: 'CODE', counterText: ''),
                  onChanged: (v) {
                    final up = v.toUpperCase();
                    if (up != v) _code.value = _code.value.copyWith(text: up);
                    if (_codeError.isNotEmpty) setState(() => _codeError = '');
                  },
                  onSubmitted: (_) => _submitCode(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _submitCode, child: const Text('Join')),
          ],
        ),
        if (_codeError.isNotEmpty) ...[const SizedBox(height: 8), Banner2(_codeError, tone: 'error')],
      ],
    );
  }

  Widget _checkin(BuildContext context, JoinController c) {
    final col = UwuColors.of(context);
    final e = c.event!;
    final checked = c.checkedIn;
    final a = c.attendance;
    final held = a?['held'] == true;
    final left = a?['leftEarlyAt'] as String?;
    final title = '${e['title'] ?? ''}';
    final note = c.noteLabel;
    final width = MediaQuery.sizeOf(context).width;
    return PageFrame(
      page: AppPages.join,
      children: [
        Column(
          children: [
            Semantics(
              header: true,
              child: Text(
                title.isEmpty ? 'Check in' : title,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 26, color: col.ink, fontWeight: FontWeight.w600),
              ),
            ),
            const SizedBox(height: 4),
            Text('Event ${e['code'] ?? c.code}', style: TextStyle(color: col.muted, letterSpacing: 1)),
          ],
        ),
        if (!checked)
          KeyedSubtree(
            key: TourTargets.key('join-name'),
            child: GlassPanel(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const FieldHead('Your name'),
                  Named(
                    'Your name',
                    child: TextField(
                      key: const ValueKey('join-name'),
                      controller: c.nameField,
                      focusNode: _nameFocus,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      autofillHints: const [AutofillHints.name],
                      decoration: const InputDecoration(counterText: ''),
                    ),
                  ),
                  if (note != null) ...[
                    const SizedBox(height: 12),
                    FieldHead(note),
                    Named(
                      note,
                      child: TextField(
                        controller: c.noteField,
                        maxLength: 120,
                        decoration: const InputDecoration(counterText: ''),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        if (checked && '${a?['name'] ?? ''}'.isNotEmpty)
          Banner2(held ? "Tapped as ${a!['name']}. It's sent as soon as this phone is back online." : 'Checked in as ${a!['name']}.'),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 18),
          child: Center(
            child: KeyedSubtree(
              key: TourTargets.key('here-btn'),
              child: HereButton(
                key: const ValueKey('here-btn'),
                colour: '${e['buttonColor'] ?? '#ccffcc'}',
                label: '${e['buttonLabel'] ?? "I'm here"}',
                size: width * 0.72 < 280 ? width * 0.72 : 280,
                done: checked,
                busy: c.busy,
                paused: c.paused,
                sub: checked
                    ? (held
                          ? 'Tapped at ${formatTime(a!['checkedInAt'] as String?)}, not sent yet'
                          : 'Checked in at ${formatTime(a!['checkedInAt'] as String?)}')
                    : null,
                onPressed: c.checkIn,
              ),
            ),
          ),
        ),
        Semantics(
          liveRegion: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Text(
              c.status,
              key: const ValueKey('here-status'),
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 15, height: 1.4, color: c.tone == 'error' ? col.error : (c.tone == 'ok' ? col.ok : col.muted)),
            ),
          ),
        ),
        Center(
          child: KeyedSubtree(
            key: TourTargets.key('leave-btn'),
            child: OutlinedButton(
              onPressed: !checked || held || left != null || c.busy ? null : () => _leave(context, c),
              child: IconLabel('door', left != null ? 'Left at ${formatTime(left)}' : "I'm leaving early"),
            ),
          ),
        ),
        if (c.methodNote.isNotEmpty)
          Text(
            c.methodNote,
            textAlign: TextAlign.center,
            style: TextStyle(color: col.muted, fontSize: 13, height: 1.4),
          ),
      ],
    );
  }

  Future<void> _leave(BuildContext context, JoinController c) {
    return AppSheet.show(
      context,
      id: 'leave',
      width: 420,
      builder: (context) => _LeaveSheet(c: c),
    );
  }
}

class _LeaveSheet extends StatefulWidget {
  const _LeaveSheet({required this.c});
  final JoinController c;

  @override
  State<_LeaveSheet> createState() => _LeaveSheetState();
}

class _LeaveSheetState extends State<_LeaveSheet> {
  String _error = '';
  bool _busy = false;

  @override
  Widget build(BuildContext context) {
    return SheetFrame(
      title: 'Leaving early?',
      footer: [
        OutlinedButton(onPressed: () => AppSheet.close(context), child: const Text('Stay')),
        FilledButton(
          onPressed: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  final err = await widget.c.leave();
                  if (!context.mounted) return;
                  setState(() => _busy = false);
                  if (err == null || err.isEmpty) {
                    AppSheet.close(context);
                    return;
                  }
                  setState(() => _error = err);
                },
          child: const IconLabel('door', "I'm leaving"),
        ),
      ],
      children: [
        const Text('The host sees the time you left. This can only be done once.'),
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Banner2(_error, tone: 'error')],
      ],
    );
  }
}
