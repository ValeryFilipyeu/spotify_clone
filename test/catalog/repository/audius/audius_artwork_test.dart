import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_artwork.dart';

import '../../../helpers/fixtures.dart';

/// The shape Audius sends: sized keys holding full urls on whichever node the
/// API picked, and `mirrors` holding bare origins for nodes with the same bytes.
Map<String, Object?> artwork({
  String? primary = 'https://primary.test/content/Qm1/480x480.jpg',
  Object? mirrors = const ['https://one.test', 'https://two.test'],
  Map<String, Object?> extraSizes = const {},
}) => {'480x480': ?primary, ...extraSizes, 'mirrors': ?mirrors};

void main() {
  group('AudiusArtwork.urlsFrom', () {
    test('puts the host the API named first', () {
      // It is the one the API chose for this response, so it is the best guess
      // available at zero cost. The mirrors are what to do when it is wrong.
      expect(
        AudiusArtwork.urlsFrom(artwork()).first,
        'https://primary.test/content/Qm1/480x480.jpg',
      );
    });

    test('grafts the primary path onto every mirror', () {
      // The whole trick. Audius storage is content-addressed -- the Qm... is a
      // hash of the bytes -- so the same path resolves on any node holding them,
      // and reaching a mirror costs a string operation rather than a request.
      expect(AudiusArtwork.urlsFrom(artwork()), [
        'https://primary.test/content/Qm1/480x480.jpg',
        'https://one.test/content/Qm1/480x480.jpg',
        'https://two.test/content/Qm1/480x480.jpg',
      ]);
    });

    test('keeps a mirror that names a port or a non-https scheme', () {
      expect(
        AudiusArtwork.urlsFrom(artwork(mirrors: const ['http://plain.test:8080'])).last,
        'http://plain.test:8080/content/Qm1/480x480.jpg',
      );
    });

    test('carries a query string across, rather than dropping it', () {
      // Nothing observed uses one, but silently losing part of a url would be a
      // hard bug to see: the mirror would 404 while the primary worked.
      final urls = AudiusArtwork.urlsFrom(
        artwork(primary: 'https://primary.test/content/Qm1/480x480.jpg?v=2'),
      );

      expect(urls.last, 'https://two.test/content/Qm1/480x480.jpg?v=2');
    });

    test('a mirror pointing at the host we already have is not a second attempt', () {
      // Trying the node that just failed, twice in a row, is exactly what this
      // whole change exists to stop.
      final urls = AudiusArtwork.urlsFrom(
        artwork(mirrors: const ['https://primary.test', 'https://one.test']),
      );

      expect(urls, [
        'https://primary.test/content/Qm1/480x480.jpg',
        'https://one.test/content/Qm1/480x480.jpg',
      ]);
    });

    group('sizes', () {
      test('prefers 480, which is large enough for the biggest cover drawn', () {
        final urls = AudiusArtwork.urlsFrom(
          artwork(
            extraSizes: const {'1000x1000': 'https://primary.test/content/Qm1/1000x1000.jpg'},
          ),
        );

        expect(urls.first, endsWith('/480x480.jpg'));
      });

      test('falls back through the other sizes for an upload missing 480', () {
        // A smaller cover beats the gradient placeholder.
        final urls = AudiusArtwork.urlsFrom(
          artwork(
            primary: null,
            extraSizes: const {'150x150': 'https://primary.test/content/Qm1/150x150.jpg'},
          ),
        );

        expect(urls.first, endsWith('/150x150.jpg'));
        expect(
          urls.last,
          'https://two.test/content/Qm1/150x150.jpg',
          reason: 'mirrors still apply',
        );
      });
    });

    group('nothing usable', () {
      test('no artwork object at all', () {
        expect(AudiusArtwork.urlsFrom(null), isEmpty);
      });

      test('an artwork object with no sizes, only mirrors', () {
        // Mirrors are origins. With no primary there is no path to graft onto
        // them, so they are not somewhere a cover can be fetched from.
        expect(AudiusArtwork.urlsFrom(artwork(primary: null)), isEmpty);
      });

      test('an empty string where a url should be', () {
        expect(AudiusArtwork.urlsFrom(artwork(primary: '')), isEmpty);
      });
    });

    group('junk in the mirrors list', () {
      // Lenient where the rest of the parsing is strict: artwork is decoration,
      // and failing the whole screen over one bad entry in a list of alternates
      // would be a worse outcome than showing the cover from the primary.
      test('a mirror that is not a string is skipped, and the rest still work', () {
        final urls = AudiusArtwork.urlsFrom(artwork(mirrors: const [42, 'https://one.test', null]));

        expect(urls, [
          'https://primary.test/content/Qm1/480x480.jpg',
          'https://one.test/content/Qm1/480x480.jpg',
        ]);
      });

      test('a mirror with no host is skipped', () {
        // It would otherwise resolve to a relative uri and fetch nothing.
        final urls = AudiusArtwork.urlsFrom(artwork(mirrors: const ['not-a-url', '']));

        expect(urls, ['https://primary.test/content/Qm1/480x480.jpg']);
      });

      test('mirrors being an object instead of a list does not throw', () {
        expect(AudiusArtwork.urlsFrom(artwork(mirrors: const {'0': 'https://one.test'})), [
          'https://primary.test/content/Qm1/480x480.jpg',
        ]);
      });
    });

    group('against real captured payloads', () {
      test('a track offers its primary plus three mirrors', () {
        final artwork =
            fixtureData('audius/track_search').first['artwork']! as Map<String, Object?>;

        final urls = AudiusArtwork.urlsFrom(artwork);

        expect(urls, hasLength(4), reason: 'Audius sends three mirrors per image');
        // Same content hash on every one of them, which is what makes them
        // interchangeable rather than merely similar.
        for (final url in urls) {
          expect(url, endsWith('/QmVqupGHZuhjxAgePsiZYyRFkvPUMrzsHMkDVaaGrGUzDK/480x480.jpg'));
        }
        expect(urls.map(Uri.parse).map((u) => u.host).toSet(), hasLength(4), reason: 'four hosts');
      });

      test('a playlist offers the same', () {
        final artwork =
            fixtureData('audius/playlist_by_id').first['artwork']! as Map<String, Object?>;

        expect(AudiusArtwork.urlsFrom(artwork), hasLength(4));
      });
    });
  });
}
