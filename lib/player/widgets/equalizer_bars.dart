import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/spotify_colors.dart';

/// A row of bars bouncing to imply audio, drawn straight onto a [Canvas].
///
/// There is no real audio analysis behind this: just_audio exposes no FFT or
/// waveform data, and nothing on the platform side hands us amplitude for a
/// remote stream. So the motion is synthesized -- see [equalizerLevels], which
/// is the entire behaviour of this widget as one pure function.
///
/// Sizes itself from [width]/[height] rather than filling its parent, so it can
/// be dropped into a [Stack] or a [Row] without a wrapping [SizedBox].
///
/// Decorative, and deliberately invisible to semantics: [CustomPaint] adds no
/// semantics node unless given a `semanticsBuilder`, and the mini-player already
/// announces what is playing through its live region. A screen reader has no use
/// for four bouncing rectangles.
class EqualizerBars extends StatefulWidget {
  const EqualizerBars({
    super.key,
    required this.isActive,
    this.width = 18,
    this.height = 11,
    this.barCount = 4,
    this.spacing = 2,
    this.color = SpotifyColors.green,
    this.cycle = const Duration(seconds: 3),
    this.settle = const Duration(milliseconds: 400),
  });

  /// Whether audio is actually sounding. False settles the bars down to a
  /// resting line over [settle] and then stops the ticker entirely -- a paused
  /// player should not cost 60 repaints a second.
  final bool isActive;

  final double width;
  final double height;
  final int barCount;

  /// Gap between bars, in logical pixels.
  final double spacing;

  final Color color;

  /// How long the wave takes to come back around to where it started. Every
  /// bar's motion is built from whole-number harmonics of this period, so the
  /// loop is seamless (see [equalizerLevels]).
  final Duration cycle;

  /// How long the bars take to rise on start and fall back on pause.
  final Duration settle;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with TickerProviderStateMixin {
  /// The master clock: repeats 0 -> 1 over [EqualizerBars.cycle] forever, and is
  /// the only input to the wave. Not an `Animation` of anything visible; it is
  /// just "where in the cycle are we".
  late final AnimationController _phase;

  /// How switched-on the bars are, 0 (resting) to 1 (full swing). Separate from
  /// [_phase] so pausing damps the wave instead of freezing it mid-air.
  late final AnimationController _energy;

  /// What the painter listens to. Held here rather than merged inside `build`
  /// so the painter can be handed a stable object: the mini-player rebuilds
  /// several times a second from position ticks, and each rebuild would
  /// otherwise re-subscribe the render object to a brand-new listenable.
  late final Listenable _repaint;

  @override
  void initState() {
    super.initState();
    _phase = AnimationController(vsync: this, duration: widget.cycle);
    _energy = AnimationController(
      vsync: this,
      duration: widget.settle,
      value: widget.isActive ? 1 : 0,
    );
    _repaint = Listenable.merge([_phase, _energy]);
    if (widget.isActive) _phase.repeat();
  }

  @override
  void didUpdateWidget(EqualizerBars oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.cycle != oldWidget.cycle) _phase.duration = widget.cycle;
    if (widget.settle != oldWidget.settle) _energy.duration = widget.settle;
    if (widget.isActive != oldWidget.isActive) _sync();
  }

  @override
  void dispose() {
    _phase.dispose();
    _energy.dispose();
    super.dispose();
  }

  void _sync() {
    if (widget.isActive) {
      if (!_phase.isAnimating) _phase.repeat();
      _energy.forward();
      return;
    }
    // Fade the bars down first and stop the clock only once they have landed.
    // Stopping it up front would freeze the wave mid-swing, and the settle would
    // read as a straight-line collapse rather than the sound dying away.
    _energy.reverse().then((_) {
      // TickerFuture completes on cancellation too, so this can fire because
      // playback resumed a moment later -- in which case the clock must keep
      // running.
      if (mounted && !widget.isActive) _phase.stop();
    });
  }

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(widget.width, widget.height),
      painter: _EqualizerPainter(
        phase: _phase,
        energy: _energy,
        repaint: _repaint,
        color: widget.color,
        barCount: widget.barCount,
        spacing: widget.spacing,
      ),
    );
  }
}

/// The resting height of a bar, as a fraction of the box. Not zero: bars that
/// collapse to nothing look like a rendering failure, whereas a low flat line
/// reads as "loaded, not playing".
const double kEqualizerRestingFraction = 0.16;

/// One bar's motion: two whole-number harmonics of the master cycle, and a
/// phase offset that sets this bar apart from its neighbours.
typedef _Wave = ({int fast, int slow, double offset});

/// Whole numbers on purpose. A harmonic of 5.5 would be mid-swing when the
/// clock wraps from 1.0 back to 0.0, and the bars would visibly jump once per
/// cycle; whole numbers land exactly where they started. The pairs are coprime
/// so the two waves only line up again at the end of a full cycle, which is what
/// keeps a 3-second loop from reading as a 3-second loop.
const List<_Wave> _waves = [
  (fast: 5, slow: 3, offset: 0.00),
  (fast: 7, slow: 4, offset: 0.35),
  (fast: 4, slow: 9, offset: 0.65),
  (fast: 6, slow: 5, offset: 0.15),
];

/// The height of each of [barCount] bars, as a fraction of the box, at [phase]
/// (0..1 through the master cycle) with [energy] (0 resting, 1 full swing).
///
/// Pure, deterministic, and the whole of what this widget does -- which means
/// the interesting half can be asserted on directly, with no canvas and no
/// pumped frames. Guaranteed to land within
/// `[kEqualizerRestingFraction, 1.0]`, so the caller never has to clamp
/// geometry.
List<double> equalizerLevels({
  required int barCount,
  required double phase,
  required double energy,
  double restingFraction = kEqualizerRestingFraction,
}) {
  final swing = energy.clamp(0.0, 1.0) * (1 - restingFraction);
  return [
    for (var index = 0; index < barCount; index++) restingFraction + swing * _swingAt(index, phase),
  ];
}

/// Where bar [index] sits in its swing at [phase], 0..1.
double _swingAt(int index, double phase) {
  final wave = _waves[index % _waves.length];
  final fast = math.sin(2 * math.pi * (wave.fast * phase + wave.offset));
  final slow = math.sin(2 * math.pi * (wave.slow * phase + wave.offset * 2));
  // Two waves rather than one: a lone sine reads as a mechanical pulse. The
  // weights sum to 0.5, so the result spans exactly 0..1 and needs no clamp.
  return 0.5 + 0.35 * fast + 0.15 * slow;
}

class _EqualizerPainter extends CustomPainter {
  _EqualizerPainter({
    required this.phase,
    required this.energy,
    required Listenable repaint,
    required this.color,
    required this.barCount,
    required this.spacing,
  }) : _fill = Paint()..color = color,
       super(repaint: repaint);

  /// Held as animations, not as the doubles they currently read, so [paint] can
  /// sample them live. That is the point of `super(repaint:)`: the render object
  /// subscribes to the ticker and re-runs *only* the paint phase, so the bars
  /// animate at 60fps without a single widget rebuild or relayout.
  final Animation<double> phase;
  final Animation<double> energy;

  final Color color;
  final int barCount;
  final double spacing;

  final Paint _fill;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || barCount <= 0) return;

    final barWidth = (size.width - spacing * (barCount - 1)) / barCount;
    if (barWidth <= 0) return;

    // Fully rounded ends. Where a bar is shorter than it is wide, RRect scales
    // the radii down for us rather than drawing something self-intersecting.
    final radius = Radius.circular(barWidth / 2);
    final levels = equalizerLevels(barCount: barCount, phase: phase.value, energy: energy.value);

    for (var index = 0; index < barCount; index++) {
      final left = index * (barWidth + spacing);
      final top = size.height * (1 - levels[index]);
      // Bars grow upward from the bottom edge, so the baseline stays put.
      canvas.drawRRect(RRect.fromLTRBR(left, top, left + barWidth, size.height, radius), _fill);
    }
  }

  @override
  bool shouldRepaint(_EqualizerPainter oldDelegate) {
    // Configuration only. The animations are deliberately not compared: this is
    // asked only when the widget rebuilds, and by then the ticker has already
    // been repainting every frame on its own.
    return oldDelegate.color != color ||
        oldDelegate.barCount != barCount ||
        oldDelegate.spacing != spacing;
  }
}
