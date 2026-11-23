// The host page (main-site/host.html, js/host.js): no event, the password to open it here, or the
// event itself: its code, QR and link, how check-ins are arriving, and the live list. On a wide
// window the list stands beside the code rather than under it.
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../app/env.dart';
import '../../app/nav.dart';
import '../../app/pages.dart';
import '../../data/format.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/edge_tray.dart';
import '../../widgets/page_frame.dart';
import '../../widgets/sheet.dart';
import '../tour/tour.dart';
import 'host_controller.dart';
import 'host_sheets.dart';

class HostScreen extends StatefulWidget {
  const HostScreen({super.key});

  @override
  State<HostScreen> createState() => _HostScreenState();
}

class _HostScreenState extends State<HostScreen> {
  HostController? _c;
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    AppPages.hostCode.addListener(_codeChanged);
    AppPages.current.addListener(_actions);
    AppPages.refreshers[AppPages.host] = () async => _c?.refresh();
    _codeChanged();
  }

  @override
  void dispose() {
    AppPages.hostCode.removeListener(_codeChanged);
    AppPages.current.removeListener(_actions);
    _c?.hotspotSheetOpen.removeListener(_hotspotSheet);
    _c?.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A new event on this page: the last one's check-ins stop, this one's start.
  void _codeChanged() {
    final code = AppPages.hostCode.value;
    if (_c?.code == code) return;
    _c?.hotspotSheetOpen.removeListener(_hotspotSheet);
    _c?.removeListener(_actions);
    _c?.dispose();
    _c = null;
    if (code != null) {
      final c = HostController(code);
      c.hotspotSheetOpen.addListener(_hotspotSheet);
      c.addListener(_actions);
      _c = c;
      c.boot();
    }
    if (mounted) setState(() {});
    _actions();
  }

  bool _hotspotShown = false;

  void _hotspotSheet() {
    final c = _c;
    if (c == null) return;
    if (c.hotspotSheetOpen.value && !_hotspotShown) {
      _hotspotShown = true;
      showHotspotSheet(context, c).whenComplete(() {
        _hotspotShown = false;
        c.hotspotSheetOpen.value = false;
        c.brightness(false);
      });
    } else if (!c.hotspotSheetOpen.value && _hotspotShown) {
      AppSheet.closeId('hotspot');
    }
  }

  /// The Edge Tray's (and the desktop title bar's) buttons for this page: the big QR code,
  /// settings and the CSV while it's an event this device hosts.
  void _actions() {
    if (AppPages.active() != AppPages.host) return;
    final c = _c;
    final hosting = c != null && c.view == 'host' && c.event != null;
    final live = hosting && !c.ended;
    final items = <TrayItem>[
      TrayItem(icon: 'home', label: 'Home', onTap: () => AppPages.open(AppPages.home)),
      if (live) TrayItem(icon: 'qr', label: 'Show the QR code', onTap: () => showQrSheet(context, c), tourId: 'tray-qr'),
      if (live) TrayItem(icon: 'settings', label: 'Event settings', onTap: () => showSettingsSheet(context, c), tourId: 'tray-settings'),
      if (hosting) TrayItem(icon: 'download', label: 'Download the list as CSV', onTap: c.downloadCsv),
    ];
    final same =
        PageActions.items.value.length == items.length &&
        [for (var i = 0; i < items.length; i++) PageActions.items.value[i].label == items[i].label].every((b) => b);
    if (!same) PageActions.items.value = items;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null) {
      return PageFrame(
        page: AppPages.host,
        children: [
          Card2(
            title: 'No event here',
            big: true,
            children: [
              const Text('This link has no event code. Make an event from the home page.'),
              const SizedBox(height: 14),
              FilledButton(onPressed: () => AppPages.open(AppPages.home), child: const IconLabel('home', 'Go home')),
            ],
          ),
        ],
      );
    }
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        switch (c.view) {
          case 'loading':
            return PageFrame(
              page: AppPages.host,
              children: [SizedBox(height: 120, child: Center(child: CircularProgressIndicator()))],
            );
          case 'missing':
            return PageFrame(
              page: AppPages.host,
              children: [
                Card2(
                  title: c.missingTitle,
                  big: true,
                  children: [
                    Text(c.missingText),
                    const SizedBox(height: 14),
                    FilledButton(onPressed: () => AppPages.open(AppPages.home), child: const IconLabel('home', 'Go home')),
                  ],
                ),
              ],
            );
          case 'locked':
            return PageFrame(
              page: AppPages.host,
              children: [_Locked(c: c)],
            );
        }
        final wide = MediaQuery.sizeOf(context).width > Env.splitWidth;
        final share = _ShareCard(c: c);
        final list = _ListCard(c: c);
        if (wide) {
          return PageFrame(
            page: AppPages.host,
            controller: _scroll,
            maxWidth: 1100,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 420, child: share),
                  const SizedBox(width: 16),
                  Expanded(child: list),
                ],
              ),
            ],
          );
        }
        return PageFrame(page: AppPages.host, controller: _scroll, children: [share, list]);
      },
    );
  }
}

class _Locked extends StatefulWidget {
  const _Locked({required this.c});
  final HostController c;

  @override
  State<_Locked> createState() => _LockedState();
}

class _LockedState extends State<_Locked> {
  final _pw = TextEditingController();
  String _error = '';
  bool _busy = false;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _open() async {
    setState(() {
      _busy = true;
      _error = '';
    });
    final err = await widget.c.unlock(_pw.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _error = err ?? '';
    });
    if (err == null) _pw.clear();
  }

  @override
  Widget build(BuildContext context) {
    return Card2(
      title: 'Open this event',
      big: true,
      children: [
        Text(widget.c.lockedText),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Named(
                'Event password',
                child: TextField(
                  controller: _pw,
                  obscureText: true,
                  autofillHints: const [AutofillHints.password],
                  decoration: const InputDecoration(hintText: 'Password'),
                  onSubmitted: (_) => _open(),
                ),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(onPressed: _busy ? null : _open, child: const IconLabel('lock', 'Open')),
          ],
        ),
        if (_error.isNotEmpty) ...[const SizedBox(height: 10), Banner2(_error, tone: 'error')],
      ],
    );
  }
}

/// The event's card: its title, the code, the QR and link, how check-ins are arriving, and the
/// buttons that change it.
class _ShareCard extends StatelessWidget {
  const _ShareCard({required this.c});
  final HostController c;

  @override
  Widget build(BuildContext context) {
    final col = UwuColors.of(context);
    final ended = c.ended;
    final rows = [c.p2pRow, c.tapRow, c.bluetoothRow, c.hotspotRow].whereType<StatusRow>().toList();
    final sync = c.syncBanner;
    return Card2(
      title: c.title.isEmpty ? 'Untitled event' : c.title,
      big: true,
      children: [
        if (ended) ...[Banner2(c.endedBanner), const SizedBox(height: 12)],
        if (!ended) ...[
          Text('People check in at this link, or by scanning the code.', style: TextStyle(color: col.muted, fontSize: 14)),
          const SizedBox(height: 12),
          KeyedSubtree(
            key: TourTargets.key('host-code'),
            child: Tooltip(
              message: 'Tap to copy the link',
              excludeFromSemantics: true,
              child: Semantics(
                button: true,
                label: 'Event code ${c.code.split('').join(' ')}, tap to copy the link',
                excludeSemantics: true,
                child: Material(
                  color: col.brandFill,
                  borderRadius: BorderRadius.circular(16),
                  child: InkWell(
                    mouseCursor: WidgetStateMouseCursor.clickable,
                    borderRadius: BorderRadius.circular(16),
                    onTap: c.copyLink,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Center(
                        child: Text(
                          c.code,
                          style: TextStyle(fontSize: 40, letterSpacing: 8, color: col.onBrand, fontFamily: 'Jua'),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: KeyedSubtree(
              key: TourTargets.key('host-qr'),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12)),
                child: QrImageView(data: c.joinLink, size: 200, padding: EdgeInsets.zero, semanticsLabel: 'QR code for ${c.joinLink}'),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            c.joinLink,
            textAlign: TextAlign.center,
            style: TextStyle(color: col.muted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          FilledButton(key: TourTargets.key('qr-big'), onPressed: () => showQrSheet(context, c), child: const IconLabel('qr', 'Show the QR code big')),
          if (rows.isNotEmpty || c.event?['allowLocation'] == true) const SizedBox(height: 14),
          KeyedSubtree(
            key: TourTargets.key('host-status'),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final r in rows) _StatusRowView(row: r),
                if (c.event?['allowLocation'] == true)
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        AppIcon('pin', size: 16, color: col.muted),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(c.locationText, style: TextStyle(color: col.ink, fontSize: 13.5)),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          if (c.paused) ...[const SizedBox(height: 12), const Banner2('Check-ins are paused. Nobody new can check in until you resume.', tone: 'warn')],
        ],
        if (sync != null) ...[const SizedBox(height: 12), Banner2(sync.text, tone: sync.warn ? 'warn' : '')],
        const SizedBox(height: 14),
        KeyedSubtree(
          key: TourTargets.key('host-actions'),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              if (!ended)
                OutlinedButton(
                  key: const ValueKey('pause'),
                  onPressed: c.togglePause,
                  child: IconLabel(c.paused ? 'play' : 'pause', c.paused ? 'Resume' : 'Pause'),
                ),
              OutlinedButton(onPressed: c.downloadCsv, child: const IconLabel('download', 'CSV')),
              // The desktop has no Edge Tray: its settings are here and in the title bar.
              if (!ended && Env.desktop) OutlinedButton(onPressed: () => showSettingsSheet(context, c), child: const IconLabel('settings', 'Settings')),
              if (!ended)
                FilledButton(
                  style: FilledButton.styleFrom(backgroundColor: col.errorFill, foregroundColor: col.error),
                  onPressed: () => showEndSheet(context, c),
                  child: IconLabel('stop', 'End event', color: col.error),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StatusRowView extends StatelessWidget {
  const _StatusRowView({required this.row});
  final StatusRow row;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: row.light == 'none'
                ? Text(row.text, style: TextStyle(color: UwuColors.of(context).ink, fontSize: 13.5, height: 1.35))
                : StatusLine(light: row.light, text: row.text),
          ),
          if (row.action != null) ...[const SizedBox(width: 8), OutlinedButton(onPressed: row.onAction, child: Text(row.action!))],
        ],
      ),
    );
  }
}

/// "Here": everyone checked in, newest first, and adding someone by hand.
class _ListCard extends StatefulWidget {
  const _ListCard({required this.c});
  final HostController c;

  @override
  State<_ListCard> createState() => _ListCardState();
}

class _ListCardState extends State<_ListCard> {
  final _name = TextEditingController();
  final _note = TextEditingController();
  final _nameFocus = FocusNode();

  @override
  void dispose() {
    _name.dispose();
    _note.dispose();
    _nameFocus.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final name = _name.text.trim();
    if (name.isEmpty) {
      _nameFocus.requestFocus();
      return;
    }
    if (await widget.c.add(name, _note.text.trim())) {
      _name.clear();
      _note.clear();
      _nameFocus.requestFocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final col = UwuColors.of(context);
    final c = widget.c;
    final list = c.displayList();
    final left = list.where((a) => a.leftEarlyAt != null).length;
    final noteLabel = c.noteLabel;
    return KeyedSubtree(
      key: TourTargets.key('host-list'),
      child: GlassPanel(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Semantics(
                  header: true,
                  child: Text(
                    'Here',
                    style: TextStyle(fontSize: 19, color: col.ink, fontWeight: FontWeight.w600),
                  ),
                ),
                const Spacer(),
                Semantics(
                  liveRegion: true,
                  child: Text(
                    list.isEmpty ? '' : '${list.length} checked in${left > 0 ? ', $left left early' : ''}',
                    style: TextStyle(color: col.muted, fontSize: 13),
                  ),
                ),
              ],
            ),
            if (!c.ended) ...[
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, box) {
                  final name = Named(
                    'Name to add by hand',
                    child: TextField(
                      controller: _name,
                      focusNode: _nameFocus,
                      maxLength: 60,
                      textCapitalization: TextCapitalization.words,
                      decoration: const InputDecoration(hintText: 'Add someone by hand', counterText: ''),
                      onSubmitted: (_) => _add(),
                    ),
                  );
                  final note = noteLabel == null
                      ? null
                      : Named(
                          noteLabel,
                          child: TextField(
                            controller: _note,
                            maxLength: 120,
                            decoration: InputDecoration(hintText: noteLabel, counterText: ''),
                            onSubmitted: (_) => _add(),
                          ),
                        );
                  final add = OutlinedButton(onPressed: _add, child: const IconLabel('plus', 'Add'));
                  // Narrow, with an extra field: the name on its own line, the field and Add under it.
                  if (note != null && box.maxWidth < 480) {
                    return Column(
                      children: [
                        name,
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(child: note),
                            const SizedBox(width: 8),
                            add,
                          ],
                        ),
                      ],
                    );
                  }
                  return Row(
                    children: [
                      Expanded(child: name),
                      if (note != null) ...[const SizedBox(width: 8), Expanded(child: note)],
                      const SizedBox(width: 8),
                      add,
                    ],
                  );
                },
              ),
            ],
            const SizedBox(height: 10),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 14),
                child: Text(
                  'Nobody yet.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: col.muted),
                ),
              ),
            for (final a in list) _AttendeeRow(c: c, a: a),
          ],
        ),
      ),
    );
  }
}

class _AttendeeRow extends StatefulWidget {
  const _AttendeeRow({required this.c, required this.a});
  final HostController c;
  final Attendee a;

  @override
  State<_AttendeeRow> createState() => _AttendeeRowState();
}

class _AttendeeRowState extends State<_AttendeeRow> {
  bool _armed = false;
  bool _busy = false;

  Future<void> _remove() async {
    if (!_armed) {
      setState(() => _armed = true);
      await Future<void>.delayed(const Duration(seconds: 3));
      if (mounted && !_busy) setState(() => _armed = false);
      return;
    }
    setState(() => _busy = true);
    final err = await widget.c.remove(widget.a);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _armed = false;
    });
    if (err != null) AppNav.toast(err);
  }

  Widget _chip(BuildContext context, String icon, String text, {Color? tone, String? said}) {
    final col = UwuColors.of(context);
    final ink = tone ?? col.ink;
    return Semantics(
      label: said ?? text,
      excludeSemantics: true,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Color.alphaBlend(ink.withValues(alpha: 0.08), col.surfaceStrong),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: ink.withValues(alpha: 0.35)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon.isNotEmpty) ...[AppIcon(icon, size: 13, color: ink), const SizedBox(width: 4)],
            Text(text, style: TextStyle(color: ink, fontSize: 12)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final col = UwuColors.of(context);
    final a = widget.a;
    final c = widget.c;
    final m = methodOf(a.method);
    final how = a.distance == null ? m.label : '${m.label}, ${a.distance} m away';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: col.border.withValues(alpha: 0.4))),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(a.name, style: TextStyle(color: col.ink, fontSize: 15.5)),
                if (a.note != null && a.note!.isNotEmpty)
                  Text('${c.noteLabel != null ? '${c.noteLabel}: ' : ''}${a.note}', style: TextStyle(color: col.muted, fontSize: 12.5)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    Tooltip(
                      message: how,
                      excludeFromSemantics: true,
                      child: _chip(context, m.icon, formatTime(a.checkedInAt), said: '${formatTime(a.checkedInAt)}, $how'),
                    ),
                    if (a.leftEarlyAt != null) _chip(context, 'door', 'Left ${formatTime(a.leftEarlyAt)}', tone: col.warn),
                    if (a.pending) _chip(context, '', 'Not sent yet', tone: col.busy),
                  ],
                ),
              ],
            ),
          ),
          if (!c.ended)
            _armed
                ? TextButton(
                    onPressed: _busy ? null : _remove,
                    child: Text('Remove?', style: TextStyle(color: col.error)),
                  )
                : IconButton(
                    tooltip: 'Remove ${a.name}',
                    onPressed: _remove,
                    icon: AppIcon('trash', size: 18, color: col.muted),
                  ),
        ],
      ),
    );
  }
}

/// For the tray's own spacing: the tray is laid over the page on a phone.
double trayRoom(BuildContext context) => Env.desktop ? 0 : EdgeTray.roomFor(context);
