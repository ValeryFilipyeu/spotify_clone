import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/widgets/cover_art.dart';

import '../../helpers/fake_image_network.dart';

const _url = 'https://example.test/cover.png';

/// A cover at a known size, so the decode assertions have something to compare
/// against.
Widget _sized(Widget child, {double size = 48}) => MaterialApp(
      home: Center(child: SizedBox(width: size, height: size, child: child)),
    );

void main() {
  group('CoverArt', () {
    testWidgets('draws only the placeholder for something with no artwork', (tester) async {
      await tester.pumpWidget(_sized(const CoverArt(color: 0xFF1DB954)));

      expect(find.byType(Image), findsNothing, reason: 'nothing to fetch');
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('treats an empty url as no artwork', (tester) async {
      await tester.pumpWidget(_sized(const CoverArt(url: '', color: 0xFF1DB954)));

      expect(find.byType(Image), findsNothing);
    });

    testWidgets('keeps the placeholder behind the cover', (tester) async {
      await pumpWithNetworkImages(tester, _sized(const CoverArt(url: _url, color: 0xFF1DB954)));

      expect(find.byType(Image), findsOneWidget);
      // Fully faded in, which only happens once a frame has really decoded -- so
      // this doubles as proof the cover loaded, rather than the assertions here
      // passing over a silently failed image.
      expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1.0);
      // And the placeholder is still behind it: never swapped out, which is what
      // makes this widget stateless.
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('decodes at the size it is painted, not the size it was sent', (tester) async {
      await pumpWithNetworkImages(tester, _sized(const CoverArt(url: _url), size: 48));

      final image = tester.widget<Image>(find.byType(Image));
      final resized = image.image as ResizeImage;
      expect(
        resized.width,
        (48 * tester.view.devicePixelRatio).round(),
        reason: 'a 600px cover in a 48px tile must not hold 600px of pixels',
      );
      expect((resized.imageProvider as NetworkImage).url, _url);
    });

    // A cover that is refused once is not a cover that does not exist: hosts
    // rate-limit bursts (Home asks for a dozen at once), phones lose packets.
    // Before the retry, one refusal blanked that cover for the whole session.
    //
    // Note what is and is not wrapped in runAsync below. A REFUSED fetch never
    // decodes, so it finishes on microtasks alone and fake time is enough --
    // which matters, because a timer created inside runAsync is a real timer
    // that a pumped Duration would never fire. Only the successful attempt
    // needs real time, for the decode.
    testWidgets('retries a refused cover, and shows it when it arrives', (tester) async {
      final network = installFakeImageNetwork(failFirst: 1);
      try {
        await tester.pumpWidget(_sized(const CoverArt(url: _url, color: 0xFF1DB954)));
        await tester.pump();

        expect(network.requests, 1);
        expect(find.byType(AnimatedOpacity), findsNothing, reason: 'first try refused');

        await tester.pump(const Duration(milliseconds: 300)); // the backoff
        expect(network.requests, 2, reason: 'the retry went back to the network');

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });
        await tester.pumpAndSettle();

        expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1.0);
      } finally {
        network.restore();
      }
    });

    testWidgets('retries a cover whose request just hangs', (tester) async {
      // The web case: no bytes, no error, for ever. errorBuilder is never
      // called there, so only the stall watchdog can rescue this one.
      final network = installFakeImageNetwork(hangFirst: 1);
      try {
        await tester.pumpWidget(_sized(const CoverArt(url: _url, color: 0xFF1DB954)));
        await tester.pump();

        expect(network.requests, 1);
        await tester.pump(const Duration(seconds: 5));
        expect(network.requests, 1, reason: 'still inside the stall timeout');

        await tester.pump(const Duration(seconds: 2)); // trips the watchdog
        await tester.pump(const Duration(milliseconds: 300)); // the backoff
        expect(network.requests, 2, reason: 'the stall was noticed and retried');

        await tester.runAsync(() async {
          await Future<void>.delayed(const Duration(milliseconds: 50));
          await tester.pump();
        });
        await tester.pumpAndSettle();

        expect(tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity, 1.0);
      } finally {
        network.restore();
      }
    });

    testWidgets('gives up on a cover that keeps being refused', (tester) async {
      // The budget has to be finite: a dead url must not retry for ever, and it
      // must leave no timer behind -- flutter_test fails a test that does.
      final network = installFakeImageNetwork(failFirst: 99);
      try {
        await tester.pumpWidget(_sized(const CoverArt(url: _url, color: 0xFF1DB954)));
        await tester.pump();

        // Stepped by hand rather than pumpAndSettle, which only keeps going
        // while FRAMES are scheduled -- a plain Timer is not a frame, so it
        // would return with the backoff still pending.
        for (final backoff in [300, 1000, 3000]) {
          await tester.pump(Duration(milliseconds: backoff));
          await tester.pump();
        }
        // Let every watchdog that armed along the way expire too.
        await tester.pump(const Duration(seconds: 7));
        // One more than the budget would leave a timer behind, and flutter_test
        // fails the test if one is still pending when the body ends.
        await tester.pump(const Duration(seconds: 5));

        expect(network.requests, 4, reason: 'one attempt plus a budget of three');
        expect(find.byIcon(Icons.music_note), findsOneWidget);
      } finally {
        network.restore();
      }
    });

    testWidgets('a cover that never arrives leaves the placeholder standing', (tester) async {
      // No fake network here on purpose: flutter_test's own client answers 400,
      // which is exactly the dead-url / offline case. It must not throw, and it
      // must not leave a hole where the cover was. Its own url, so a cover
      // another test loaded successfully can never stand in for it.
      await tester.pumpWidget(
        _sized(const CoverArt(url: 'https://example.test/missing.png', color: 0xFF1DB954)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });
  });
}
