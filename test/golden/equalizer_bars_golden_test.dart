@TestOn('vm')
@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/widgets/equalizer_bars.dart';

import 'golden_harness.dart';

/// A [CustomPainter] is the one place a golden is not merely convenient but
/// close to the only option.
///
/// Everywhere else the widget tree is the specification: a test can find a
/// `Padding` and read its inset. A painter has no tree. Its whole output is a
/// sequence of canvas calls, and the alternatives to a picture are asserting on
/// a recorded call list -- which pins the implementation rather than the result
/// -- or testing `equalizerLevels` alone, which is already done and says nothing
/// about how those numbers become rectangles.
///
/// Drawn far larger than the 18x11 it ships at. At shipping size the bars are a
/// couple of pixels wide and a one-pixel change is both invisible to a reviewer
/// and a large fraction of the image; scaled up, the geometry is legible and the
/// same proportions are under test.
void main() {
  setUpAll(setUpGoldens);

  group('EqualizerBars', () {
    testWidgets('at rest, when nothing is playing', (tester) async {
      // isActive false settles the bars down and then stops the ticker
      // entirely, so this one really does reach a still frame -- no pumpFor
      // needed, and pumpAndSettle returning at all is itself the proof that the
      // ticker was disposed rather than left spinning behind a paused player.
      await expectGolden(
        tester,
        'equalizer_bars_at_rest',
        size: const GoldenSize(200, 140),
        child: const EqualizerBars(isActive: false, width: 160, height: 100),
      );
    });

    testWidgets('mid-cycle, while sound is coming out', (tester) async {
      // 750ms into a 3s cycle: past the 400ms rise, and a quarter of the way
      // round, so the bars are at four visibly different heights rather than
      // the near-equal ones at 0 or half a cycle.
      await expectGolden(
        tester,
        'equalizer_bars_active',
        size: const GoldenSize(200, 140),
        pumpFor: const Duration(milliseconds: 750),
        child: const EqualizerBars(isActive: true, width: 160, height: 100),
      );
    });

    testWidgets('with more bars than the four it ships with', (tester) async {
      // barCount is a parameter, so the spacing arithmetic has to hold for
      // values other than the default. Cheap to pin, and the kind of thing that
      // breaks when someone tunes the look for the default and stops there.
      await expectGolden(
        tester,
        'equalizer_bars_many',
        size: const GoldenSize(200, 140),
        pumpFor: const Duration(milliseconds: 750),
        child: const EqualizerBars(isActive: true, width: 160, height: 100, barCount: 9),
      );
    });
  });
}
