// What making an event and its settings share (index.html's form, host.html's settings): the
// four ways to prove someone's here, the radius, the password's live checklist, and a text field
// with its counter.
import 'package:flutter/material.dart';

import '../../data/format.dart';
import '../../data/password.dart';
import '../../theme/icons.dart';
import '../../theme/theme.dart';
import '../../widgets/common.dart';
import '../../widgets/page_frame.dart';

class Methods {
  Methods({this.p2p = true, this.location = false, this.tap = false, this.bluetooth = false});
  bool p2p, location, tap, bluetooth;
  bool get any => p2p || location || tap || bluetooth;

  /// The home page's hints, under the toggles.
  String hint() {
    final hints = <String>[
      if (p2p) "Same wifi: attendees' phones connect to this screen directly, so keep this page open.",
      if (location) 'Location: attendees share their location once and must be near where you are now.',
      if (tap) 'Tap phones: attendees touch their phone to yours. Needs this event open in the uwuHere app, on an Android phone with NFC.',
      if (bluetooth)
        'Bluetooth: attendees who have the uwuHere app on Android check in phone to phone, even with no internet. Needs this event open in the app.'
            '${p2p || location || tap ? '' : ' Turn on another way too, for everyone without the app.'}',
    ];
    return hints.isEmpty ? 'Pick at least one.' : hints.join(' ');
  }
}

/// The four toggles, in a grid of two (the site's .toggle-grid.four).
class MethodToggles extends StatelessWidget {
  const MethodToggles({super.key, required this.methods, required this.onChanged});
  final Methods methods;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return ToggleGrid(
      children: [
        ToggleChip(icon: 'wifi', label: 'Same wifi', on: methods.p2p, onTap: () => _flip(() => methods.p2p = !methods.p2p)),
        ToggleChip(icon: 'pin', label: 'Location', on: methods.location, onTap: () => _flip(() => methods.location = !methods.location)),
        ToggleChip(icon: 'tap', label: 'Tap phones', on: methods.tap, onTap: () => _flip(() => methods.tap = !methods.tap)),
        ToggleChip(icon: 'bluetooth', label: 'Bluetooth', on: methods.bluetooth, onTap: () => _flip(() => methods.bluetooth = !methods.bluetooth)),
      ],
    );
  }

  void _flip(VoidCallback f) {
    f();
    onChanged();
  }
}

const radii = [50, 100, 200, 500, 1000];
String radiusLabel(int m) => m >= 1000 ? '${m ~/ 1000} km' : '$m m';

class RadiusPicker extends StatelessWidget {
  const RadiusPicker({super.key, required this.value, required this.onChanged});
  final int value;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Named(
      'Within',
      child: DropdownButtonFormField<int>(
        initialValue: radii.contains(value) ? value : 100,
        mouseCursor: WidgetStateMouseCursor.clickable,
        items: [for (final r in radii) DropdownMenuItem(value: r, child: Text(radiusLabel(r)))],
        onChanged: (v) => onChanged(v ?? 100),
      ),
    );
  }
}

/// A text field with its label and counter above it.
class CountedField extends StatefulWidget {
  const CountedField({super.key, required this.label, required this.controller, required this.max, this.hint, this.onChanged, this.fieldKey, this.focusNode});
  final String label;
  final TextEditingController controller;
  final int max;
  final String? hint;
  final VoidCallback? onChanged;
  final Key? fieldKey;
  final FocusNode? focusNode;

  @override
  State<CountedField> createState() => _CountedFieldState();
}

class _CountedFieldState extends State<CountedField> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldHead(widget.label, count: charCount(widget.controller.text), max: widget.max),
        Named(
          widget.label,
          child: TextField(
            key: widget.fieldKey,
            focusNode: widget.focusNode,
            controller: widget.controller,
            maxLength: widget.max,
            decoration: InputDecoration(hintText: widget.hint, counterText: ''),
            textCapitalization: TextCapitalization.sentences,
            onChanged: (_) {
              setState(() {});
              widget.onChanged?.call();
            },
          ),
        ),
      ],
    );
  }
}

/// The password's live checklist (password.js's renderPasswordChecks). Hidden while it's empty.
class PasswordChecks extends StatelessWidget {
  const PasswordChecks({super.key, required this.password, this.title = '', this.code = ''});
  final String password;
  final String title;
  final String code;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) return const SizedBox.shrink();
    final c = UwuColors.of(context);
    final result = checkPassword(password, title: title, code: code);
    Widget row(String icon, String text, Color colour, {String? said}) => Semantics(
      label: said ?? text,
      excludeSemantics: true,
      child: Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: AppIcon(icon, size: 16, color: colour),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(text, style: TextStyle(color: colour, fontSize: 13)),
            ),
          ],
        ),
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final ch in result.checks) row(ch.ok ? 'check' : 'close', ch.text, ch.ok ? c.ok : c.muted, said: '${ch.text}, ${ch.ok ? 'done' : 'not yet'}'),
        row('lock', 'Checked against known data breaches when you save', c.muted),
      ],
    );
  }
}
