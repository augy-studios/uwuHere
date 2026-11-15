// The big button's colour picker, for making an event and its settings
// (main-site/js/colour-picker.js): a hue and saturation wheel, a brightness slider, and a hex code
// box, so any colour can be reached by eye or typed exactly. Drag or tap the wheel, or focus it
// and use the arrow keys: left and right turn the hue, up and down change the saturation. The
// wheel and the marker show colours for what they are, a fixed-meaning exception to the theme's
// tokens, like the button itself.
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';


import '../data/format.dart';
import '../theme/theme.dart';
import 'common.dart';

const _keyHue = 5.0;
const _keySat = 0.05;

({double h, double s, double v}) hexToHsv(String hex) {
  final c = colourOf(hex) ?? const Color(0xFFCCFFCC);
  final r = c.r, g = c.g, b = c.b;
  final mx = math.max(r, math.max(g, b));
  final d = mx - math.min(r, math.min(g, b));
  var h = 0.0;
  if (d > 0) {
    if (mx == r) {
      h = ((g - b) / d) % 6;
    } else if (mx == g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    h *= 60;
    if (h < 0) h += 360;
  }
  return (h: h, s: mx > 0 ? d / mx : 0, v: mx);
}

String hsvToHex(double h, double s, double v) {
  int f(int k) {
    final x = (k + h / 60) % 6;
    return ((v - v * s * math.max(0, math.min(x, math.min(4 - x, 1)))) * 255).round();
  }

  return '#${[f(5), f(3), f(1)].map((c) => c.toRadixString(16).padLeft(2, '0')).join()}';
}

class ColourPicker extends StatefulWidget {
  const ColourPicker({super.key, required this.value, required this.onChanged, this.label = 'Button colour'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  State<ColourPicker> createState() => _ColourPickerState();
}

class _ColourPickerState extends State<ColourPicker> {
  double _h = 0;
  late double _s, _v;
  late String _current;
  final _hex = TextEditingController();
  final _hexFocus = FocusNode();
  final _wheelFocus = FocusNode();
  String _error = '';
  ui.Image? _wheel;
  String _wheelFor = '';

  @override
  void initState() {
    super.initState();
    _set(widget.value, quiet: true);
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) _commitText();
    });
  }

  @override
  void didUpdateWidget(ColourPicker old) {
    super.didUpdateWidget(old);
    if (widget.value != _current) _set(widget.value, quiet: true);
  }

  @override
  void dispose() {
    _hex.dispose();
    _hexFocus.dispose();
    _wheelFocus.dispose();
    _wheel?.dispose();
    super.dispose();
  }

  void _set(String hex, {bool quiet = false, bool keepText = false}) {
    final parsed = parseHex(hex) ?? '#ccffcc';
    _current = parsed;
    final hsv = hexToHsv(parsed);
    // A grey has no hue of its own: keep the one the wheel was on.
    if (hsv.s > 0) _h = hsv.h;
    _s = hsv.s;
    _v = hsv.v;
    if (!keepText) _hex.text = parsed.toUpperCase();
    if (!quiet) widget.onChanged(parsed);
    if (mounted) setState(() {});
  }

  void _fromHsv() {
    _current = hsvToHex(_h, _s, _v);
    _error = '';
    _hex.text = _current.toUpperCase();
    widget.onChanged(_current);
    setState(() {});
  }

  void _pointAt(Offset local, double size) {
    final r = size / 2;
    final x = (local.dx - r) / r;
    final y = (r - local.dy) / r;
    _h = (math.atan2(y, x) * 180 / math.pi + 360) % 360;
    _s = math.min(1, math.sqrt(x * x + y * y));
    // Picking on the wheel at no brightness would change nothing visible.
    if (_v < 0.05) _v = 1;
    _fromHsv();
  }

  void _commitText() {
    final parsed = parseHex(_hex.text);
    if (parsed == null) {
      setState(() => _error = 'A hex code is 6 digits and letters A to F, like CCFFCC.');
      return;
    }
    _error = '';
    _set(parsed);
  }

  Future<void> _draw(int px) async {
    final key = '$px|${_v.toStringAsFixed(2)}';
    if (_wheelFor == key) return;
    _wheelFor = key;
    final bytes = List<int>.filled(px * px * 4, 0);
    final r = px / 2;
    for (var py = 0; py < px; py++) {
      for (var qx = 0; qx < px; qx++) {
        final x = (qx + 0.5 - r) / r;
        final y = (r - py - 0.5) / r;
        final d = math.sqrt(x * x + y * y);
        final alpha = ((1 - d) * r).clamp(0.0, 1.0);
        if (alpha == 0) continue;
        final c = colourOf(hsvToHex((math.atan2(y, x) * 180 / math.pi + 360) % 360, math.min(1, d), _v))!;
        final i = (py * px + qx) * 4;
        bytes[i] = (c.r * 255).round();
        bytes[i + 1] = (c.g * 255).round();
        bytes[i + 2] = (c.b * 255).round();
        bytes[i + 3] = (alpha * 255).round();
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    final desc = ui.ImageDescriptor.raw(buffer, width: px, height: px, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await desc.instantiateCodec();
    final frame = await codec.getNextFrame();
    if (!mounted || _wheelFor != key) return;
    setState(() {
      _wheel?.dispose();
      _wheel = frame.image;
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    const size = 132.0;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    _draw((size * dpr).round().clamp(64, 400));
    final a = _h * math.pi / 180;
    final marker = Offset(size / 2 + size / 2 * _s * math.cos(a), size / 2 - size / 2 * _s * math.sin(a));
    final wheel = Focus(
      focusNode: _wheelFocus,
      onKeyEvent: (node, e) {
        if (e is! KeyDownEvent && e is! KeyRepeatEvent) return KeyEventResult.ignored;
        final turn = {LogicalKeyboardKey.arrowLeft: _keyHue, LogicalKeyboardKey.arrowRight: -_keyHue}[e.logicalKey];
        final sat = {LogicalKeyboardKey.arrowUp: _keySat, LogicalKeyboardKey.arrowDown: -_keySat}[e.logicalKey];
        if (turn == null && sat == null) return KeyEventResult.ignored;
        if (turn != null) _h = (_h + turn + 360) % 360;
        if (sat != null) _s = (_s + sat).clamp(0.0, 1.0);
        _fromHsv();
        return KeyEventResult.handled;
      },
      child: Semantics(
        slider: true,
        label: '${widget.label} wheel. Left and right arrows turn the hue, up and down change the saturation.',
        value: '${_current.toUpperCase()}: hue ${_h.round()} degrees, saturation ${(_s * 100).round()} percent, brightness ${(_v * 100).round()} percent',
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            onPanDown: (d) {
              _wheelFocus.requestFocus();
              _pointAt(d.localPosition, size);
            },
            onPanUpdate: (d) => _pointAt(d.localPosition, size),
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(
                    child: _wheel == null
                        ? DecoratedBox(
                            decoration: BoxDecoration(shape: BoxShape.circle, color: c.surfaceStrong),
                          )
                        : RawImage(image: _wheel, fit: BoxFit.fill),
                  ),
                  Positioned(
                    left: marker.dx - 9,
                    top: marker.dy - 9,
                    child: IgnorePointer(
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: colourOf(_current),
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 3),
                          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 4)],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Brightness', style: TextStyle(color: c.muted, fontSize: 12)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            activeTrackColor: colourOf(hsvToHex(_h, _s, 1)),
            inactiveTrackColor: Colors.black87,
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Semantics(
            label: 'Brightness',
            child: Slider(
              value: (_v * 100).roundToDouble(),
              max: 100,
              onChanged: (x) {
                _v = x / 100;
                _fromHsv();
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Hex code', style: TextStyle(color: c.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Named(
          'Hex code',
          child: TextField(
            controller: _hex,
            focusNode: _hexFocus,
            maxLength: 7,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(counterText: '', errorText: _error.isEmpty ? null : _error, errorMaxLines: 3),
            onChanged: (t) {
              final parsed = parseHex(t);
              // Three digits are a whole colour too, but somebody typing six passes through three
              // on the way: only a full six applies as they type.
              if (parsed != null && t.replaceAll('#', '').length == 6) {
                _error = '';
                _set(parsed, keepText: true);
              }
            },
            onSubmitted: (_) => _commitText(),
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, box) {
        if (box.maxWidth < 300) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [wheel, const SizedBox(height: 12), side]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            wheel,
            const SizedBox(width: 16),
            Expanded(child: side),
          ],
        );
      },
    );
  }
}
