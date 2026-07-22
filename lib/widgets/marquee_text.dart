import 'package:flutter/material.dart';

/// A single line of text that scrolls horizontally back and forth ONLY when it
/// is too wide to fit its box, so long titles/artist names can be read in full;
/// when it fits it is shown statically (left-aligned) with no animation.
///
/// Hand-rolled (no marquee package). It measures the text with a [TextPainter]
/// against the box width, and when it overflows drives a [Transform.translate]
/// from a repeating [AnimationController] through four phases: hold at start,
/// scroll to end, hold at end, scroll back. Being ticker-based (not timer-
/// based), it disposes cleanly and never leaves a pending timer in tests.
class MarqueeText extends StatefulWidget {
  const MarqueeText(
    this.text, {
    super.key,
    this.style,
    this.velocity = 45, // logical pixels per second
    this.pause = const Duration(milliseconds: 1200),
  });

  final String text;
  final TextStyle? style;

  /// Scroll speed in logical px/s. A distance-proportional duration keeps long
  /// and short overflows moving at the same visual pace.
  final double velocity;

  /// How long to hold still at each end before reversing.
  final Duration pause;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  /// The overflow distance the controller is currently animating, or null when
  /// stopped (text fits). Guards against restarting on every rebuild.
  double? _activeOverflow;

  @override
  void initState() {
    super.initState();
    // Created eagerly (not lazily) so the ticker is set up while the element is
    // active; a lazy `late` field could otherwise initialize inside dispose()
    // for text that never overflowed, which crashes the ticker lookup.
    _controller = AnimationController(vsync: this);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Starts/stops/reconfigures the animation for [overflow]. Must run after the
  /// frame (it mutates the controller), and is a no-op when nothing changed.
  void _sync(double overflow) {
    if (overflow > 0.5) {
      if (_activeOverflow != null && (_activeOverflow! - overflow).abs() < 1.0) return;
      _activeOverflow = overflow;
      _controller
        ..duration = _cycleDuration(overflow)
        ..repeat();
    } else {
      if (_activeOverflow == null) return;
      _activeOverflow = null;
      _controller
        ..stop()
        ..value = 0;
    }
  }

  Duration _cycleDuration(double overflow) {
    final scrollMs = overflow / widget.velocity * 1000;
    return Duration(milliseconds: (2 * widget.pause.inMilliseconds + 2 * scrollMs).round());
  }

  /// Maps the controller's 0..1 progress to a scroll offset across the four
  /// phases (hold start / scroll out / hold end / scroll back).
  double _offsetFor(double overflow) {
    final scrollMs = overflow / widget.velocity * 1000;
    final pauseMs = widget.pause.inMilliseconds.toDouble();
    final total = 2 * pauseMs + 2 * scrollMs;
    if (total <= 0) return 0;
    final t = _controller.value * total;
    if (t < pauseMs) return 0; // hold at start
    if (t < pauseMs + scrollMs) {
      return overflow * Curves.easeInOut.transform(((t - pauseMs) / scrollMs).clamp(0.0, 1.0)); // out
    }
    if (t < 2 * pauseMs + scrollMs) return overflow; // hold at end
    return overflow * (1 - Curves.easeInOut.transform(((t - 2 * pauseMs - scrollMs) / scrollMs).clamp(0.0, 1.0))); // back
  }

  @override
  Widget build(BuildContext context) {
    final style = widget.style ?? DefaultTextStyle.of(context).style;
    final text = Text(widget.text, maxLines: 1, softWrap: false, overflow: TextOverflow.visible, style: style);

    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: style),
          maxLines: 1,
          textScaler: MediaQuery.textScalerOf(context),
          textDirection: Directionality.of(context),
        )..layout();
        final overflow = painter.width - constraints.maxWidth;

        // Reconcile the animation to the measured overflow after this frame
        // (can't touch the controller during build).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _sync(overflow);
        });

        if (overflow <= 0.5) {
          // Fits: static, left-aligned -- identical to a plain Text.
          return SizedBox(width: double.infinity, child: text);
        }

        return ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            child: text,
            builder: (context, child) => Align(
              alignment: Alignment.centerLeft,
              child: Transform.translate(offset: Offset(-_offsetFor(overflow), 0), child: child),
            ),
          ),
        );
      },
    );
  }
}
