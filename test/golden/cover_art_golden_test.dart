import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/widgets/cover_art.dart';

import 'golden_harness.dart';

/// [CoverArt] is the one widget in the app whose *whole job* is visual, and the
/// state pinned here is the one users see most: the gradient placeholder.
///
/// It is not a loading spinner that goes away. It is painted underneath the
/// image and never removed, so it is what shows while a cover downloads, when a
/// content node is down, and for an item that has no artwork at all. A unit test
/// can assert the gradient widget exists; only a golden says whether it looks
/// like a cover or like a bug.
void main() {
  setUpAll(setUpGoldens);

  group('CoverArt', () {
    testWidgets('the tinted placeholder a catalog item gets', (tester) async {
      await expectGolden(
        tester,
        'cover_art_placeholder',
        size: const GoldenSize(180, 180),
        child: const SizedBox(width: 150, height: 150, child: CoverArt(color: 0xFF1DB954)),
      );
    });

    testWidgets('the neutral one the player screens get', (tester) async {
      // A track carries no colour of its own, so `color` is null and the
      // gradient falls back to the surface tint. Worth its own golden because
      // the two are easy to confuse in code and unmistakable side by side.
      await expectGolden(
        tester,
        'cover_art_placeholder_neutral',
        size: const GoldenSize(180, 180),
        child: const SizedBox(width: 150, height: 150, child: CoverArt()),
      );
    });

    testWidgets('the three sizes it is actually used at', (tester) async {
      // One image rather than three, because what matters here is the
      // relationship: the glyph and the corner radius are meant to scale with
      // the cover, and a change that breaks that is only visible in comparison.
      await expectGolden(
        tester,
        'cover_art_scales',
        size: const GoldenSize(300, 140),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // The list tile.
            SizedBox(
              width: 48,
              height: 48,
              child: CoverArt(color: 0xFF7358FF, borderRadius: 4, iconSize: 22),
            ),
            SizedBox(width: 12),
            // The mini-player.
            SizedBox(
              width: 44,
              height: 44,
              child: CoverArt(color: 0xFFE13300, borderRadius: 4, iconSize: 22),
            ),
            SizedBox(width: 12),
            // A home card.
            SizedBox(width: 110, height: 110, child: CoverArt(color: 0xFF1DB954)),
          ],
        ),
      );
    });
  });
}
