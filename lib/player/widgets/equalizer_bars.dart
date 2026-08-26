import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/spotify_colors.dart';

/// A row of bars bouncing to imply audio, painted onto a [Canvas].
///
/// The motion is synthesized -- just_audio exposes no FFT or amplitude for a
/// remote stream. [equalizerLevels] is the whole behaviour, as a pure function.
///
/// Sizes itself from [width]/[height], and is invisible to semantics: the
/// mini-player already announces what is playing.
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

  /// False settles the bars to a resting line over [settle], then stops the
  /// ticker -- a paused player should not cost 60 repaints a second.
  final bool isActive;

  final double width;
  final double height;
  final int barCount;

  /// Gap between bars, in logical pixels.
  final double spacing;

  final Color color;

  /// The master period. Every bar is a whole-number harmonic of it, so the loop
  /// is seamless -- see [equalizerLevels].
  final Duration cycle;

  /// How long the bars take to rise on start and fall back on pause.
  final Duration settle;

  @override
  State<EqualizerBars> createState() => _EqualizerBarsState();
}

class _EqualizerBarsState extends State<EqualizerBars> with TickerProviderStateMixin {
  /// Repeats 0 -> 1 over [EqualizerBars.cycle], and is the only input to the
  /// wave. Not an animation of anything visible.
  late final AnimationController _phase;

  /// 0 (resting) to 1 (full swing). Separate from [_phase] so pausing damps the
  /// wave rather than freezing it mid-air.
  late final AnimationController _energy;

  /// Held here, not merged in `build`: the mini-player rebuilds on every
  /// position tick, and each one would re-subscribe the render object.
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
    // Stopping the clock first would freeze the wave mid-swing, and the settle
    // would read as a collapse rather than the sound dying away.
    _energy.reverse().then((_) {
      // TickerFuture completes on cancellation too, so playback may have
      // resumed -- in which case the clock must keep running.
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

/// The resting height of a bar. Not zero: a collapsed bar reads as a rendering
/// failure, a low flat line as "loaded, not playing".
const double kEqualizerRestingFraction = 0.16;

/// One bar's motion: two whole-number harmonics of the master cycle, and a
/// phase offset that sets this bar apart from its neighbours.
typedef _Wave = ({int fast, int slow, double offset});

/// Whole numbers, or the bars jump when the clock wraps. Coprime pairs, so the
/// two waves only realign at the end of a cycle -- which is what keeps a
/// 3-second loop from reading as one.
const List<_Wave> _waves = [
  (fast: 5, slow: 3, offset: 0.00),
  (fast: 7, slow: 4, offset: 0.35),
  (fast: 4, slow: 9, offset: 0.65),
  (fast: 6, slow: 5, offset: 0.15),
];

/// The height of each of [barCount] bars as a fraction of the box, at [phase]
/// (0..1) with [energy] (0 resting, 1 full swing).
///
/// Pure and deterministic, so the interesting half of this widget is assertable
/// with no canvas. Always within `[kEqualizerRestingFraction, 1.0]`, so callers
/// never clamp.
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
  // Two waves: a lone sine reads as a mechanical pulse. The weights sum to 0.5,
  // so this spans exactly 0..1 and needs no clamp.
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

  /// Animations rather than their current values, so [paint] samples them live.
  /// With `super(repaint:)` the render object re-runs only the paint phase --
  /// 60fps with no rebuild and no relayout.
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

    // RRect scales the radii down itself when a bar is shorter than it is wide.
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
    // Configuration only: the animations repaint on their own, and this is asked
    // only on rebuild.
    return oldDelegate.color != color ||
        oldDelegate.barCount != barCount ||
        oldDelegate.spacing != spacing;
  }
}
