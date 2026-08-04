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
