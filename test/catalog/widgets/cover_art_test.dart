import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/widgets/cover_art.dart';

import '../../helpers/fake_image_network.dart';

const _url = 'https://example.test/cover.png';

/// Three hosts serving the same path, as a content-addressed catalog hands them
/// over: the node the API named, then its mirrors.
const _dead = 'https://dead.test/content/Qm1/480x480.jpg';
const _alsoDead = 'https://also-dead.test/content/Qm1/480x480.jpg';
const _live = 'https://live.test/content/Qm1/480x480.jpg';

/// A cover at a known size, so the decode assertions have something to compare
/// against.
Widget _sized(Widget child, {double size = 48}) => MaterialApp(
  home: Center(
    child: SizedBox(width: size, height: size, child: child),
  ),
);

/// Carries the widget from one attempt to the next, on the fake clock.
///
/// Two pumps, and both are needed. The first fires the timer holding the queued
/// attempt, whose callback evicts the failed provider and calls setState -- by
/// which point this frame is already drawn. The second is the frame that
/// actually rebuilds with the new attempt, and building is what resolves the
/// provider and puts the request on the wire.
///
/// [delay] is how far to move the clock for that first pump: zero while the
/// widget still has untried hosts, one of the backoff steps once it does not.
///
/// Outside [WidgetTester.runAsync] on purpose -- these are fake-clock timers,
/// and a pumped Duration is the only thing that fires them.
Future<void> advanceToNextAttempt(WidgetTester tester, {Duration delay = Duration.zero}) async {
  await tester.pump(delay);
  await tester.pump();
}

/// Runs the fetch and decode on real time -- neither happens on the fake clock,
/// because both finish on the engine's own threads. The attempt being waited on
/// must already have been put on the wire by a pump above; real time here does
/// not advance the fake clock, so it will not start one.
Future<void> letTheImageLoad(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await tester.pump();
  });
  await tester.pumpAndSettle();
}

double? opacityOf(WidgetTester tester) =>
    tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity)).opacity;

void main() {
  group('CoverArt', () {
    testWidgets('draws only the placeholder for something with no artwork', (tester) async {
      await tester.pumpWidget(_sized(const CoverArt(color: 0xFF1DB954)));

      expect(find.byType(Image), findsNothing, reason: 'nothing to fetch');
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('treats an empty url as no artwork', (tester) async {
      await tester.pumpWidget(_sized(const CoverArt(urls: [''], color: 0xFF1DB954)));

      expect(find.byType(Image), findsNothing);
    });

    testWidgets('keeps the placeholder behind the cover', (tester) async {
      await pumpWithNetworkImages(tester, _sized(const CoverArt(urls: [_url], color: 0xFF1DB954)));

      expect(find.byType(Image), findsOneWidget);
      // Fully faded in, which only happens once a frame has really decoded -- so
      // this doubles as proof the cover loaded, rather than the assertions here
      // passing over a silently failed image.
      expect(opacityOf(tester), 1.0);
      // And the placeholder is still behind it: never swapped out, which is what
      // makes this widget stateless.
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    testWidgets('decodes at the size it is painted, not the size it was sent', (tester) async {
      await pumpWithNetworkImages(tester, _sized(const CoverArt(urls: [_url]), size: 48));

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
        await tester.pumpWidget(_sized(const CoverArt(urls: [_url], color: 0xFF1DB954)));
        await tester.pump();

        expect(network.requests, 1);
        expect(find.byType(AnimatedOpacity), findsNothing, reason: 'first try refused');

        await tester.pump(const Duration(milliseconds: 300)); // the backoff
        expect(network.requests, 2, reason: 'the retry went back to the network');

        await letTheImageLoad(tester);

        expect(opacityOf(tester), 1.0);
      } finally {
        network.restore();
      }
    });

    testWidgets('retries a cover whose request just hangs', (tester) async {
      // The web case: no bytes, no error, for ever. errorBuilder is never
      // called there, so only the stall watchdog can rescue this one.
      final network = installFakeImageNetwork(hangFirst: 1);
      try {
        await tester.pumpWidget(_sized(const CoverArt(urls: [_url], color: 0xFF1DB954)));
        await tester.pump();

        expect(network.requests, 1);
        await tester.pump(const Duration(seconds: 5));
        expect(network.requests, 1, reason: 'still inside the stall timeout');

        await tester.pump(const Duration(seconds: 2)); // trips the watchdog
        await tester.pump(const Duration(milliseconds: 300)); // the backoff
        expect(network.requests, 2, reason: 'the stall was noticed and retried');

        await letTheImageLoad(tester);

        expect(opacityOf(tester), 1.0);
      } finally {
        network.restore();
      }
    });

    testWidgets('gives up on a cover that keeps being refused', (tester) async {
      // The budget has to be finite: a dead url must not retry for ever, and it
      // must leave no timer behind -- flutter_test fails a test that does.
      final network = installFakeImageNetwork(failFirst: 99);
      try {
        await tester.pumpWidget(_sized(const CoverArt(urls: [_url], color: 0xFF1DB954)));
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
        _sized(const CoverArt(urls: ['https://example.test/missing.png'], color: 0xFF1DB954)),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byIcon(Icons.music_note), findsOneWidget);
    });

    // The catalog serves artwork from a network of independent nodes and names
    // several that hold the same bytes. Nodes go down one at a time -- measured
    // against the live API, one primary host in eight was answering 502 while
    // all three of its mirrors served the image -- so the useful response to a
    // failure is a different host, not the same one again.
    group('failing over to another host', () {
      testWidgets('asks the next host instead of the one that just failed', (tester) async {
        final network = installFakeImageNetwork(deadUrls: const {_dead});
        try {
          await tester.pumpWidget(_sized(const CoverArt(urls: [_dead, _live])));
          await tester.pump();
          expect(network.requestedUrls, [_dead]);

          await advanceToNextAttempt(tester);
          expect(
            network.requestedUrls,
            orderedEquals([_dead, _live]),
            reason: 'the second attempt must be a different node, not the dead one again',
          );

          await letTheImageLoad(tester);
          expect(opacityOf(tester), 1.0, reason: 'the mirror served the cover');
        } finally {
          network.restore();
        }
      });

      testWidgets('does not wait out a backoff before trying a fresh host', (tester) async {
        // The delay exists to stop a host being hammered. A host that has not
        // been asked yet has refused nothing, so there is nothing to wait for --
        // and waiting would leave the cover blank for 300ms it does not need to
        // be. Note that time never advances in this test: every pump below is a
        // zero-duration one.
        final network = installFakeImageNetwork(deadUrls: const {_dead, _alsoDead});
        try {
          await tester.pumpWidget(_sized(const CoverArt(urls: [_dead, _alsoDead, _live])));
          await tester.pump();
          await advanceToNextAttempt(tester);
          await advanceToNextAttempt(tester);

          expect(
            network.requestedUrls,
            orderedEquals([_dead, _alsoDead, _live]),
            reason: 'all three hosts tried without the clock moving at all',
          );
        } finally {
          network.restore();
        }
      });

      testWidgets('keeps walking past a mirror that is also down', (tester) async {
        // Two of the thirty-two hosts in the live sample were dead *as mirrors*.
        // Trying one alternate and giving up would not have been enough.
        final network = installFakeImageNetwork(deadUrls: const {_dead, _alsoDead});
        try {
          await tester.pumpWidget(_sized(const CoverArt(urls: [_dead, _alsoDead, _live])));
          await tester.pump();
          await advanceToNextAttempt(tester);
          await advanceToNextAttempt(tester);
          expect(network.requestedUrls.last, _live);

          await letTheImageLoad(tester);
          expect(opacityOf(tester), 1.0);
        } finally {
          network.restore();
        }
      });

      testWidgets('a host that hangs is walked past too', (tester) async {
        // On the web a dead node does not report an error, it simply never
        // answers -- so without the stall watchdog the walk would stop on the
        // first silent host and never reach the mirror holding the image.
        final network = installFakeImageNetwork(stalledUrls: const {_dead});
        try {
          await tester.pumpWidget(_sized(const CoverArt(urls: [_dead, _live])));
          await tester.pump();
          expect(network.requestedUrls, [_dead]);

          // The watchdog trips at six seconds and queues the next attempt; the
          // attempt itself still needs its two pumps to reach the wire.
          await advanceToNextAttempt(tester, delay: const Duration(seconds: 6));
          expect(network.requestedUrls, [_dead, _live]);

          await letTheImageLoad(tester);
          expect(opacityOf(tester), 1.0);
        } finally {
          network.restore();
        }
      });

      testWidgets('once every host has failed, it cycles back with a backoff', (tester) async {
        // Every node refusing at once is a different failure from one node being
        // down -- the network dropped, or a burst of a dozen covers hit a rate
        // limit. Another host is no help there and spacing the attempts out is,
        // so the delays start only after the list is spent.
        final network = installFakeImageNetwork(failFirst: 99);
        try {
          await tester.pumpWidget(_sized(const CoverArt(urls: [_dead, _live])));
          await tester.pump();
          await advanceToNextAttempt(tester);
          expect(network.requestedUrls, [_dead, _live], reason: 'the free pass through both');

          for (final backoff in [300, 1000, 3000]) {
            await advanceToNextAttempt(tester, delay: Duration(milliseconds: backoff));
          }
          await tester.pump(const Duration(seconds: 7));
          await tester.pump(const Duration(seconds: 5));

          expect(
            network.requestedUrls,
            orderedEquals([_dead, _live, _dead, _live, _dead]),
            reason: 'two hosts, then three delayed retries starting again from the best',
          );
          expect(find.byIcon(Icons.music_note), findsOneWidget);
        } finally {
          network.restore();
        }
      });

      testWidgets('a rebuild with the same hosts does not restart the walk', (tester) async {
        // CoverArt filters blanks out of its url list on every build, so the
        // list reaching the state is a new object each time even when it holds
        // the same strings. Comparing those by identity would count every parent
        // rebuild as a different cover, reset the walk, and send the widget
        // straight back to the host it had already ruled out.
        final network = installFakeImageNetwork(deadUrls: const {_dead});
        try {
          late StateSetter rebuild;
          await tester.pumpWidget(
            _sized(
              StatefulBuilder(
                builder: (context, setState) {
                  rebuild = setState;
                  // A fresh list literal per build, which is the point.
                  return CoverArt(urls: [_dead, _live]);
                },
              ),
            ),
          );
          await tester.pump();
          await advanceToNextAttempt(tester);
          await letTheImageLoad(tester);
          expect(network.requestedUrls, [_dead, _live]);

          rebuild(() {});
          await tester.pumpAndSettle();

          expect(
            network.requestedUrls,
            orderedEquals([_dead, _live]),
            reason: 'the rebuild must not send it back to the dead host',
          );
          expect(opacityOf(tester), 1.0, reason: 'and the cover is still on screen');
        } finally {
          network.restore();
        }
      });
    });
  });
}
