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

/// How far one arrow key press turns the hue, in degrees.
const _keyboardHueStep = 5.0;

/// How far one arrow key press changes the saturation, from 0 to 1.
const _keyboardSaturationStep = 0.05;

/// A hex colour code as its hue (0 to 360 degrees), saturation (0 to 1) and value, which is its
/// brightness (0 to 1). A code that doesn't parse reads as the default pale green, #CCFFCC.
({double hue, double saturation, double value}) hexToHsv(String hex) {
  final parsedColour = colourOf(hex);
  Color colour;
  if (parsedColour == null) {
    colour = const Color(0xFFCCFFCC);
  } else {
    colour = parsedColour;
  }
  final red = colour.r, green = colour.g, blue = colour.b;
  final brightestChannel = math.max(red, math.max(green, blue));
  final channelRange = brightestChannel - math.min(red, math.min(green, blue));
  var hue = 0.0;
  if (channelRange > 0) {
    if (brightestChannel == red) {
      hue = ((green - blue) / channelRange) % 6;
    } else if (brightestChannel == green) {
      hue = (blue - red) / channelRange + 2;
    } else {
      hue = (red - green) / channelRange + 4;
    }
    hue = hue * 60;
    if (hue < 0) {
      hue = hue + 360;
    }
  }
  double saturation;
  if (brightestChannel > 0) {
    saturation = channelRange / brightestChannel;
  } else {
    saturation = 0;
  }
  return (hue: hue, saturation: saturation, value: brightestChannel);
}

/// A hue (0 to 360 degrees), saturation and value (each 0 to 1) as a lower-case hex colour code,
/// such as '#ccffcc'.
String hsvToHex(double hue, double saturation, double value) {
  // One of red (offset 5), green (3) or blue (1), from 0 to 255, by the standard HSV formula.
  int channel(int offset) {
    final position = (offset + hue / 60) % 6;
    return ((value - value * saturation * math.max(0, math.min(position, math.min(4 - position, 1)))) * 255).round();
  }

  final hexPairs = [channel(5), channel(3), channel(1)].map((channelValue) {
    return channelValue.toRadixString(16).padLeft(2, '0');
  });
  return '#${hexPairs.join()}';
}

class ColourPicker extends StatefulWidget {
  const ColourPicker({super.key, required this.value, required this.onChanged, this.label = 'Button colour'});
  final String value;
  final ValueChanged<String> onChanged;
  final String label;

  @override
  State<ColourPicker> createState() {
    return _ColourPickerState();
  }
}

class _ColourPickerState extends State<ColourPicker> {
  double _hue = 0;
  late double _saturation, _brightness;
  late String _current;
  final _hexController = TextEditingController();
  final _hexFocus = FocusNode();
  final _wheelFocus = FocusNode();
  String _error = '';
  ui.Image? _wheelImage;

  /// Which size and brightness [_wheelImage] was drawn for (or is being drawn for), so it's
  /// only drawn again when one of them changes.
  String _wheelImageKey = '';

  @override
  void initState() {
    super.initState();
    _setFromHex(widget.value, quiet: true);
    _hexFocus.addListener(() {
      if (!_hexFocus.hasFocus) {
        _commitText();
      }
    });
  }

  @override
  void didUpdateWidget(ColourPicker oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.value != _current) {
      _setFromHex(widget.value, quiet: true);
    }
  }

  @override
  void dispose() {
    _hexController.dispose();
    _hexFocus.dispose();
    _wheelFocus.dispose();
    final wheelImage = _wheelImage;
    if (wheelImage != null) {
      wheelImage.dispose();
    }
    super.dispose();
  }

  /// Takes the colour from a hex code (the default pale green if it doesn't parse). [quiet]
  /// leaves onChanged uncalled; [keepText] leaves the hex box as the person typed it.
  void _setFromHex(String hex, {bool quiet = false, bool keepText = false}) {
    final parsedHex = parseHex(hex);
    String parsed;
    if (parsedHex == null) {
      parsed = '#ccffcc';
    } else {
      parsed = parsedHex;
    }
    _current = parsed;
    final hsv = hexToHsv(parsed);
    // A grey has no hue of its own: keep the one the wheel was on.
    if (hsv.saturation > 0) {
      _hue = hsv.hue;
    }
    _saturation = hsv.saturation;
    _brightness = hsv.value;
    if (!keepText) {
      _hexController.text = parsed.toUpperCase();
    }
    if (!quiet) {
      widget.onChanged(parsed);
    }
    if (mounted) {
      setState(() {});
    }
  }

  /// Takes the colour from the wheel's and slider's hue, saturation and brightness.
  void _applyHsv() {
    _current = hsvToHex(_hue, _saturation, _brightness);
    _error = '';
    _hexController.text = _current.toUpperCase();
    widget.onChanged(_current);
    setState(() {});
  }

  /// A tap or drag at [localPosition] on a wheel [size] across: the angle from the centre is the
  /// hue, the distance out the saturation.
  void _pickAt(Offset localPosition, double size) {
    final wheelRadius = size / 2;
    // From -1 to 1 across the wheel, with up positive.
    final horizontal = (localPosition.dx - wheelRadius) / wheelRadius;
    final vertical = (wheelRadius - localPosition.dy) / wheelRadius;
    _hue = (math.atan2(vertical, horizontal) * 180 / math.pi + 360) % 360;
    _saturation = math.min(1, math.sqrt(horizontal * horizontal + vertical * vertical));
    // Picking on the wheel at no brightness would change nothing visible.
    if (_brightness < 0.05) {
      _brightness = 1;
    }
    _applyHsv();
  }

  /// Applies what's in the hex box, or explains what a hex code is if it isn't one.
  void _commitText() {
    final parsed = parseHex(_hexController.text);
    if (parsed == null) {
      setState(() {
        _error = 'A hex code is 6 digits and letters A to F, like CCFFCC.';
      });
      return;
    }
    _error = '';
    _setFromHex(parsed);
  }

  /// Draws the hue and saturation wheel at the current brightness, [pixelSize] pixels across, one
  /// pixel at a time, with a soft one-pixel edge. Skipped when it's already drawn for this size and
  /// brightness; a drawing overtaken by a newer one is thrown away.
  Future<void> _drawWheel(int pixelSize) async {
    final key = '$pixelSize|${_brightness.toStringAsFixed(2)}';
    if (_wheelImageKey == key) {
      return;
    }
    _wheelImageKey = key;
    final bytes = List<int>.filled(pixelSize * pixelSize * 4, 0);
    final wheelRadius = pixelSize / 2;
    for (var rowIndex = 0; rowIndex < pixelSize; rowIndex = rowIndex + 1) {
      for (var columnIndex = 0; columnIndex < pixelSize; columnIndex = columnIndex + 1) {
        // The pixel's centre, from -1 to 1 across the wheel, with up positive.
        final horizontal = (columnIndex + 0.5 - wheelRadius) / wheelRadius;
        final vertical = (wheelRadius - rowIndex - 0.5) / wheelRadius;
        final distanceFromCentre = math.sqrt(horizontal * horizontal + vertical * vertical);
        final alpha = ((1 - distanceFromCentre) * wheelRadius).clamp(0.0, 1.0);
        if (alpha == 0) {
          continue;
        }
        final pixelHue = (math.atan2(vertical, horizontal) * 180 / math.pi + 360) % 360;
        final pixelColour = colourOf(hsvToHex(pixelHue, math.min(1, distanceFromCentre), _brightness))!;
        final byteIndex = (rowIndex * pixelSize + columnIndex) * 4;
        bytes[byteIndex] = (pixelColour.r * 255).round();
        bytes[byteIndex + 1] = (pixelColour.g * 255).round();
        bytes[byteIndex + 2] = (pixelColour.b * 255).round();
        bytes[byteIndex + 3] = (alpha * 255).round();
      }
    }
    final buffer = await ui.ImmutableBuffer.fromUint8List(Uint8List.fromList(bytes));
    final descriptor = ui.ImageDescriptor.raw(buffer, width: pixelSize, height: pixelSize, pixelFormat: ui.PixelFormat.rgba8888);
    final codec = await descriptor.instantiateCodec();
    final frame = await codec.getNextFrame();
    if (!mounted || _wheelImageKey != key) {
      return;
    }
    setState(() {
      final oldImage = _wheelImage;
      if (oldImage != null) {
        oldImage.dispose();
      }
      _wheelImage = frame.image;
    });
  }

  /// Handles the arrow keys on the focused wheel: left and right turn the hue, up and down change
  /// the saturation.
  KeyEventResult _onWheelKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final hueChange = {
      LogicalKeyboardKey.arrowLeft: _keyboardHueStep,
      LogicalKeyboardKey.arrowRight: -_keyboardHueStep,
    }[event.logicalKey];
    final saturationChange = {
      LogicalKeyboardKey.arrowUp: _keyboardSaturationStep,
      LogicalKeyboardKey.arrowDown: -_keyboardSaturationStep,
    }[event.logicalKey];
    if (hueChange == null && saturationChange == null) {
      return KeyEventResult.ignored;
    }
    if (hueChange != null) {
      _hue = (_hue + hueChange + 360) % 360;
    }
    if (saturationChange != null) {
      _saturation = (_saturation + saturationChange).clamp(0.0, 1.0);
    }
    _applyHsv();
    return KeyEventResult.handled;
  }

  /// The wheel with its marker on the left (or on top when there isn't room), and beside it the
  /// brightness slider and the hex code box.
  @override
  Widget build(BuildContext context) {
    final colors = UwuColors.of(context);
    const size = 132.0;
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    _drawWheel((size * devicePixelRatio).round().clamp(64, 400));
    final hueRadians = _hue * math.pi / 180;
    final marker = Offset(
      size / 2 + size / 2 * _saturation * math.cos(hueRadians),
      size / 2 - size / 2 * _saturation * math.sin(hueRadians),
    );

    // Until the wheel's picture is ready, a plain circle stands in for it.
    Widget wheelFace;
    if (_wheelImage == null) {
      wheelFace = DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, color: colors.surfaceStrong),
      );
    } else {
      wheelFace = RawImage(image: _wheelImage, fit: BoxFit.fill);
    }

    final wheel = Focus(
      focusNode: _wheelFocus,
      onKeyEvent: _onWheelKey,
      child: Semantics(
        slider: true,
        label: '${widget.label} wheel. Left and right arrows turn the hue, up and down change the saturation.',
        value: '${_current.toUpperCase()}: hue ${_hue.round()} degrees, saturation ${(_saturation * 100).round()} percent, brightness ${(_brightness * 100).round()} percent',
        child: MouseRegion(
          cursor: SystemMouseCursors.precise,
          child: GestureDetector(
            onPanDown: (details) {
              _wheelFocus.requestFocus();
              _pickAt(details.localPosition, size);
            },
            onPanUpdate: (details) {
              _pickAt(details.localPosition, size);
            },
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned.fill(child: wheelFace),
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

    String? errorText;
    if (_error.isEmpty) {
      errorText = null;
    } else {
      errorText = _error;
    }

    final side = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Brightness', style: TextStyle(color: colors.muted, fontSize: 12)),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 10,
            activeTrackColor: colourOf(hsvToHex(_hue, _saturation, 1)),
            inactiveTrackColor: Colors.black87,
            thumbColor: Colors.white,
            overlayShape: SliderComponentShape.noOverlay,
          ),
          child: Semantics(
            label: 'Brightness',
            child: Slider(
              value: (_brightness * 100).roundToDouble(),
              max: 100,
              onChanged: (newValue) {
                _brightness = newValue / 100;
                _applyHsv();
              },
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text('Hex code', style: TextStyle(color: colors.muted, fontSize: 12)),
        const SizedBox(height: 4),
        Named(
          'Hex code',
          child: TextField(
            controller: _hexController,
            focusNode: _hexFocus,
            maxLength: 7,
            textCapitalization: TextCapitalization.characters,
            autocorrect: false,
            enableSuggestions: false,
            decoration: InputDecoration(counterText: '', errorText: errorText, errorMaxLines: 3),
            onChanged: (typedText) {
              final parsed = parseHex(typedText);
              // Three digits are a whole colour too, but somebody typing six passes through three
              // on the way: only a full six applies as they type.
              if (parsed != null && typedText.replaceAll('#', '').length == 6) {
                _error = '';
                _setFromHex(parsed, keepText: true);
              }
            },
            onSubmitted: (_) {
              _commitText();
            },
          ),
        ),
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 300) {
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
