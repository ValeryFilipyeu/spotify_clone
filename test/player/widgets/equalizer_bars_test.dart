import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/widgets/equalizer_bars.dart';

/// Levels for the standard four bars at [phase].
List<double> _levels(double phase, {double energy = 1}) =>
    equalizerLevels(barCount: 4, phase: phase, energy: energy);

/// [samples] evenly spaced phases across one full cycle, 0 inclusive, 1
/// exclusive.
Iterable<double> _cycle({int samples = 240}) =>
    Iterable.generate(samples, (index) => index / samples);

/// Repaints the equalizer's render object into a recording canvas and returns
/// the bars it drew, left to right.
///
/// Scoped to a descendant of [EqualizerBars]: Scaffold and Material paint
/// through [CustomPaint] too, so an unqualified byType finder matches several.
List<RRect> _paintedBars(WidgetTester tester) {
  final canvas = TestRecordingCanvas();
  final finder = find.descendant(
    of: find.byType(EqualizerBars),
    matching: find.byType(CustomPaint),
  );
  tester.renderObject<RenderBox>(finder).paint(TestRecordingPaintingContext(canvas), Offset.zero);
  return [
    for (final recorded in canvas.invocations)
      if (recorded.invocation.memberName == #drawRRect)
        recorded.invocation.positionalArguments.first as RRect,
  ];
}

Widget _host(EqualizerBars bars) => MaterialApp(home: Scaffold(body: Center(child: bars)));

void main() {
  group('the wave', () {
    test('never leaves the box', () {
      for (final phase in _cycle()) {
        for (final level in _levels(phase)) {
          expect(level, inInclusiveRange(kEqualizerRestingFraction, 1.0),
              reason: 'a bar at phase $phase would be drawn outside its bounds');
        }
      }
    });

    test('loops seamlessly', () {
      // The clock wraps 1.0 -> 0.0 forever, so the wave has to have a period of
      // exactly 1 or the bars lurch once per cycle. This is what pins the
      // harmonics to whole numbers -- and it has to be checked across the cycle,
      // not just at the wrap: a half-integer harmonic still happens to return to
      // the same *value* at phase 1, it just arrives travelling the wrong way.
      for (final phase in _cycle(samples: 60)) {
        final here = _levels(phase);
        final aCycleLater = _levels(phase + 1);
        for (var bar = 0; bar < here.length; bar++) {
          expect(aCycleLater[bar], closeTo(here[bar], 1e-9),
              reason: 'bar $bar does not repeat at phase $phase');
        }
      }
    });

    test('moves every bar independently', () {
      final atStart = _levels(0.0);
      expect(atStart.toSet(), hasLength(atStart.length), reason: 'bars are in unison');

      // Not just offset from each other at one instant: each bar traces its own
      // path through the whole cycle.
      final paths = [
        for (var bar = 0; bar < 4; bar++)
          [for (final phase in _cycle(samples: 60)) _levels(phase)[bar]],
      ];
      for (var bar = 1; bar < paths.length; bar++) {
        expect(paths[bar], isNot(orderedEquals(paths[0])));
      }
    });

    test('swings every bar across most of the box', () {
      for (var bar = 0; bar < 4; bar++) {
        final heights = [for (final phase in _cycle()) _levels(phase)[bar]];
        expect(heights.reduce((a, b) => a > b ? a : b), greaterThan(0.8));
        expect(heights.reduce((a, b) => a < b ? a : b), lessThan(0.35));
      }
    });

    test('rests flat with no energy, whatever the phase', () {
      for (final phase in _cycle(samples: 24)) {
        expect(
          _levels(phase, energy: 0),
          everyElement(closeTo(kEqualizerRestingFraction, 1e-9)),
        );
      }
    });

    test('treats over-full energy as full', () {
      expect(_levels(0.3, energy: 2), _levels(0.3, energy: 1));
    });
  });

  group('painting', () {
    testWidgets('draws one rounded bar per bar, sitting on the baseline',
        (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));

      final bars = _paintedBars(tester);
      expect(bars, hasLength(4));

      for (final bar in bars) {
        // Grows upward: the bottom edge never moves.
        expect(bar.bottom, closeTo(11, 0.001));
        expect(bar.top, greaterThanOrEqualTo(0));
        expect(bar.height, greaterThan(0));
        expect(bar.blRadiusX, greaterThan(0), reason: 'ends should be rounded');
      }

      // Four 3px bars with 2px gaps across 18px, in order, no overlap.
      for (var index = 1; index < bars.length; index++) {
        expect(bars[index].left, closeTo(bars[index - 1].right + 2, 0.001));
      }
      expect(bars.first.left, closeTo(0, 0.001));
      expect(bars.last.right, closeTo(18, 0.001));
    });

    testWidgets('paused, every bar is painted at the same resting height',
        (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: false)));

      final heights = _paintedBars(tester).map((bar) => bar.height);
      expect(heights, everyElement(closeTo(11 * kEqualizerRestingFraction, 0.001)));
    });

    testWidgets('repaints straight off the ticker, rebuilding nothing',
        (tester) async {
      // The whole point of handing the painter a repaint Listenable: the render
      // object subscribes to the ticker itself, so a frame costs a paint and
      // nothing else. Two independent things are checked, because
      // [_paintedBars] paints on demand and so would happily report movement
      // from a widget that never actually repaints on screen:
      //
      //  * builds stays at 1 -- no setState, no AnimatedBuilder above the paint;
      //  * the boundary's asymmetric paint count climbs, which is the framework
      //    recording "this layer repainted while its parent did not". Nothing
      //    above the equalizer is dirty in this test, so every increment is the
      //    equalizer marking itself for paint and no-one else.
      var builds = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(
              key: const ValueKey('boundary'),
              child: Builder(builder: (context) {
                builds++;
                return const EqualizerBars(isActive: true);
              }),
            ),
          ),
        ),
      ));

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('boundary')),
      )..debugResetMetrics();
      final before = _paintedBars(tester).map((bar) => bar.height).toList();

      const frames = 6;
      for (var frame = 0; frame < frames; frame++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(boundary.debugAsymmetricPaintCount, frames);
      expect(builds, 1);
      expect(
        _paintedBars(tester).map((bar) => bar.height).toList(),
        isNot(orderedEquals(before)),
        reason: 'the bars did not move',
      );
    });

    testWidgets('rises from rest when playback starts', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: false)));
      final resting = _paintedBars(tester).first.height;

      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      await tester.pump(const Duration(milliseconds: 400)); // the settle

      final tallest = _paintedBars(tester)
          .map((bar) => bar.height)
          .reduce((a, b) => a > b ? a : b);
      expect(tallest, greaterThan(resting));
    });
  });

  group('the ticker', () {
    // transientCallbackCount is the number of live frame callbacks -- i.e. how
    // many tickers are running. A decorative widget has no business holding one
    // open while nothing is playing.
    testWidgets('never starts while inactive', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: false)));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('runs while active', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      expect(tester.binding.transientCallbackCount, greaterThan(0));
    });

    testWidgets('stops once the bars have settled after a pause', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      await tester.pumpWidget(_host(const EqualizerBars(isActive: false)));

      // Still ticking: the wave keeps moving while the bars fall, otherwise the
      // settle looks like a collapse.
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.binding.transientCallbackCount, greaterThan(0));

      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.binding.transientCallbackCount, 0);
    });

    testWidgets('picks back up when playback resumes mid-settle', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      await tester.pumpWidget(_host(const EqualizerBars(isActive: false)));
      await tester.pump(const Duration(milliseconds: 100));

      // The pending stop-the-clock callback fires when the fade-out ticker
      // finishes, cancelled or not -- it must not take the resumed clock down
      // with it.
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      await tester.pump(const Duration(milliseconds: 500));

      expect(tester.binding.transientCallbackCount, greaterThan(0));

      final before = _paintedBars(tester).map((bar) => bar.height).toList();
      await tester.pump(const Duration(milliseconds: 200));
      expect(
        _paintedBars(tester).map((bar) => bar.height).toList(),
        isNot(orderedEquals(before)),
      );
    });

    testWidgets('leaves nothing running once disposed', (tester) async {
      await tester.pumpWidget(_host(const EqualizerBars(isActive: true)));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));

      expect(find.byType(EqualizerBars), findsNothing);
      expect(tester.binding.transientCallbackCount, 0);
    });
  });
}
