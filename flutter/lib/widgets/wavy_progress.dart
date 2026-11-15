// A progress bar as Material 3 Expressive draws one, the way Android's own updater and apps in
// Material You do: the part done as a wave in the theme's primary colour, drifting, then a gap and
// the rest of the way flat in its secondary container colour, with a dot at the end. With no
// telling how far it's got (value null), a wavy stretch sweeps across instead. The same as
// sgbus-timings' WavyProgressView.java, to the same measures: a 4 px line, waves 40 px long and
// 3 px high (half as long while sweeping), flat near the start and the end. Keeps still with
// animations turned off.
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

class WavyProgress extends StatefulWidget {
  const WavyProgress({super.key, this.value, this.label});

  /// 0 to 1, or null while there's no telling.
  final double? value;

  /// What a screen reader says it is, such as "Downloading".
  final String? label;

  @override
  State<WavyProgress> createState() => _WavyProgressState();
}

class _WavyProgressState extends State<WavyProgress>
    with SingleTickerProviderStateMixin {
  // How long a wave takes to drift by its own length, and the sweep to cross once.
  static const _driftMs = 1000;
  static const _sweepMs = 1800;

  late final Ticker _ticker = createTicker(_tick);
  Duration _last = Duration.zero;
  double _phase = 0;
  double _sweep = 0;
  // Shown, chasing widget.value a little each frame, so a download's many small steps glide.
  double _shown = 0;

  @override
  void initState() {
    super.initState();
    _shown = widget.value ?? 0;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still && _ticker.isActive) {
      _ticker.stop();
      _shown = widget.value ?? 0;
    } else if (!still && !_ticker.isActive) {
      _last = Duration.zero;
      _ticker.start();
    }
  }

  @override
  void didUpdateWidget(WavyProgress old) {
    super.didUpdateWidget(old);
    if (widget.value == null || old.value == null || !_ticker.isActive)
      _shown = widget.value ?? 0;
  }

  void _tick(Duration at) {
    final ms = at.inMilliseconds;
    final step = (at - _last).inMicroseconds / 1000;
    _last = at;
    setState(() {
      _phase = 2 * math.pi * (ms % _driftMs) / _driftMs;
      _sweep = (ms % _sweepMs) / _sweepMs;
      final target = widget.value;
      if (target != null) {
        // A fifth of the way there every 30 ms or so, whatever the frame rate.
        final k = 1 - math.pow(0.8, step / 30).toDouble();
        _shown += (target - _shown) * k.clamp(0, 1);
        if ((target - _shown).abs() < 0.001) _shown = target;
      }
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final v = widget.value;
    return Semantics(
      label: widget.label,
      value: v == null ? null : '${(v * 100).round()}%',
      child: SizedBox(
        height: _WavePainter.thickness + 2 * _WavePainter.amplitude,
        width: double.infinity,
        child: CustomPaint(
          painter: _WavePainter(
            progress: v == null ? null : _shown.clamp(0, 1),
            phase: _phase,
            sweep: _sweep,
            active: s.primary,
            track: s.secondaryContainer,
          ),
        ),
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter({
    required this.progress,
    required this.phase,
    required this.sweep,
    required this.active,
    required this.track,
  });
  final double? progress;
  final double phase;
  final double sweep;
  final Color active;
  final Color track;

  static const thickness = 4.0;
  static const amplitude = 3.0;
  static const wavelength = 40.0;
  static const gap = 4.0;

  @override
  void paint(Canvas canvas, Size size) {
    const half = thickness / 2;
    const left = half;
    final right = size.width - half;
    final cy = size.height / 2;
    if (right <= left) return;
    final width = right - left;
    Paint line(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = thickness
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final trackPaint = line(track);

    final p = progress;
    if (p == null) {
      // A stretch 40% as long as the bar, its front easing in from the left and out past the
      // right, with the track either side of it.
      final eased = 0.5 - math.cos(math.pi * sweep) / 2;
      final head = left + width * 1.4 * eased;
      final tail = head - width * 0.4;
      final from = math.max(left, tail);
      final to = math.min(right, head);
      if (to > from)
        _wave(canvas, from, to, cy, amplitude, wavelength / 2, line(active));
      if (from - gap - thickness > left)
        canvas.drawLine(
          Offset(left, cy),
          Offset(from - gap - thickness, cy),
          trackPaint,
        );
      if (to + gap + thickness < right)
        canvas.drawLine(
          Offset(to + gap + thickness, cy),
          Offset(right, cy),
          trackPaint,
        );
      return;
    }

    final end = left + width * p;
    // Flat at the very start and as it finishes, as Material's does.
    final amp = amplitude * math.min(p / 0.1, (1 - p) / 0.05).clamp(0.0, 1.0);
    if (end > left) _wave(canvas, left, end, cy, amp, wavelength, line(active));
    final trackFrom = p > 0 ? end + gap + thickness : left;
    if (trackFrom < right)
      canvas.drawLine(Offset(trackFrom, cy), Offset(right, cy), trackPaint);
    // The stop dot at the end, till the wave reaches it.
    if (p < 1)
      canvas.drawCircle(Offset(right, cy), half, Paint()..color = active);
  }

  // A wave from x `from` to `to`, its phase fixed to the bar so it drifts rather than slides.
  void _wave(
    Canvas canvas,
    double from,
    double to,
    double cy,
    double amp,
    double length,
    Paint paint,
  ) {
    final path = Path();
    final step = math.max(1.0, length / 24);
    for (var x = from; ; x = math.min(to, x + step)) {
      final y = cy + amp * math.sin(2 * math.pi * x / length - phase);
      if (x == from) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
      if (x >= to) break;
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.progress != progress ||
      old.phase != phase ||
      old.sweep != sweep ||
      old.active != active ||
      old.track != track;
}
