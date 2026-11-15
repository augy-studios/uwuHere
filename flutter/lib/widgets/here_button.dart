// The big round button (the site's .here-btn): the host's colour, with black or white words
// whichever contrasts more, a soft ring of the same colour, and a ring that breathes while it's
// working. Also the small preview of it beside the colour picker.
import 'package:flutter/material.dart';

import '../data/format.dart';
import '../theme/icons.dart';
import '../theme/theme.dart';

class HereButton extends StatefulWidget {
  const HereButton({
    super.key,
    required this.colour,
    required this.label,
    this.sub,
    this.done = false,
    this.busy = false,
    this.paused = false,
    this.onPressed,
    this.size = 280,
    this.preview = false,
    this.semanticsHint,
  });

  final String colour;
  final String label;
  final String? sub;
  final bool done;
  final bool busy;
  final bool paused;
  final VoidCallback? onPressed;
  final double size;
  final bool preview;
  final String? semanticsHint;

  @override
  State<HereButton> createState() => _HereButtonState();
}

class _HereButtonState extends State<HereButton> with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));
  bool _down = false;
  bool _over = false;

  @override
  void didUpdateWidget(HereButton old) {
    super.didUpdateWidget(old);
    _sync();
  }

  @override
  void initState() {
    super.initState();
    _sync();
  }

  void _sync() {
    // Reduced motion stills it, as the site's theme.css does.
    final still = WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;
    if (widget.busy && !still) {
      if (!_breath.isAnimating) _breath.repeat(reverse: true);
    } else {
      _breath.stop();
      _breath.value = 0;
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = UwuColors.of(context);
    final colour = colourOf(widget.colour) ?? c.brand;
    final ink = inkFor(colour);
    final blocked = widget.done || widget.busy || widget.paused || widget.onPressed == null;
    final size = widget.size;
    final fontSize = widget.preview ? 16.8 : (widget.done ? 27.2 : hereLabelSize(widget.label));
    final face = AnimatedBuilder(
      animation: _breath,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_breath.value);
        final ring = widget.preview ? 0.0 : 10 + 12 * t;
        return Container(
          width: size,
          height: size,
          padding: EdgeInsets.all(widget.preview ? 16 : 30),
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(color: c.ink.withValues(alpha: 0.18)),
            boxShadow: [
              if (!widget.preview) BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 24, offset: const Offset(0, 8)),
              if (!widget.preview) BoxShadow(color: colour.withValues(alpha: 0.30 - 0.18 * t), spreadRadius: ring),
            ],
          ),
          child: child,
        );
      },
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (widget.done) ...[AppIcon('check', size: 40, color: ink), const SizedBox(height: 6)],
          Text(
            widget.done ? "You're here" : widget.label,
            textAlign: TextAlign.center,
            style: TextStyle(color: ink, fontSize: fontSize, height: 1.1, fontFamily: 'Jua'),
          ),
          if (widget.sub != null) ...[
            const SizedBox(height: 6),
            Text(widget.sub!, textAlign: TextAlign.center, style: TextStyle(color: ink.withValues(alpha: 0.85), fontSize: 13.6)),
          ],
        ],
      ),
    );
    if (widget.preview) return ExcludeSemantics(child: face);
    final scale = blocked ? 1.0 : (_down ? 0.97 : 1.0);
    final lift = blocked || !_over ? 0.0 : -2.0;
    return Semantics(
      button: true,
      enabled: !blocked,
      label: widget.done ? "You're here${widget.sub == null ? '' : ', ${widget.sub}'}" : widget.label,
      hint: widget.semanticsHint,
      excludeSemantics: true,
      child: MouseRegion(
        cursor: blocked ? SystemMouseCursors.basic : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _over = true),
        onExit: (_) => setState(() => _over = false),
        child: GestureDetector(
          onTapDown: blocked ? null : (_) => setState(() => _down = true),
          onTapCancel: () => setState(() => _down = false),
          onTapUp: (_) => setState(() => _down = false),
          onTap: blocked ? null : widget.onPressed,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: widget.paused && !widget.done ? 0.55 : 1,
            child: AnimatedSlide(
              duration: const Duration(milliseconds: 150),
              offset: Offset(0, lift / size),
              child: AnimatedScale(duration: const Duration(milliseconds: 150), scale: scale, child: face),
            ),
          ),
        ),
      ),
    );
  }
}
