import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_playlist_dto.dart';
import 'package:spotify_clone/theme/cover_palette.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('parsing a real playlist', () {
    test('reads the header fields', () {
      final playlist = AudiusPlaylistDto.fromJson(fixtureData('audius/playlist_by_id').first);

      expect(playlist.id, 'RKxOQ');
      expect(playlist.name, 'Lofi Space inspired');
      expect(playlist.ownerName, 'Lofi Army');
      expect(playlist.isAlbum, isFalse);
      expect(playlist.artworkUrls.first, endsWith('/480x480.jpg'));
    });

    test('reads the embedded tracklist, so detail costs one request', () {
      final playlist = AudiusPlaylistDto.fromJson(fixtureData('audius/playlist_by_id').first);

      expect(playlist.tracks.map((t) => t.id), [
        'Xb48b',
        '1gwBr',
        '1gpdX',
        'ml8yw',
        '3OA5k',
        'JB53Z',
      ]);
    });

    test('a search result carries no tracks, and that is not an error', () {
      // /playlists/search sends `tracks: []`. Only /playlists/{id} fills it in.
      final results = fixtureData('audius/playlist_search');

      for (final json in results) {
        expect(AudiusPlaylistDto.fromJson(json).tracks, isEmpty);
      }
      expect(results, hasLength(2));
    });

    test('an absent tracks key parses as empty rather than throwing', () {
      final raw = {...fixtureData('audius/playlist_by_id').first}..remove('tracks');

      expect(AudiusPlaylistDto.fromJson(raw).tracks, isEmpty);
    });
  });

  group('subtitle', () {
    test('an album is credited to its artist', () {
      final raw = {...fixtureData('audius/playlist_by_id').first, 'is_album': true};

      expect(AudiusPlaylistDto.fromJson(raw).subtitle, 'Lofi Army');
    });

    test('a playlist with a description shows it', () {
      final withDescription = fixtureData('audius/playlist_search')[1];

      final playlist = AudiusPlaylistDto.fromJson(withDescription);
      expect(playlist.description, isNotNull);
      expect(playlist.subtitle, playlist.description);
    });

    test('a playlist without one names the curator instead of showing a blank line', () {
      // Most real playlists have no description, and an empty second line reads
      // as a loading glitch.
      final raw = fixtureData('audius/playlist_by_id').first;
      expect(raw['description'], isNull, reason: 'fixture no longer exercises the case');

      expect(AudiusPlaylistDto.fromJson(raw).subtitle, 'By Lofi Army');
    });
  });

  group('toDomain', () {
    test('derives a stable cover tint from the id', () {
      final item = AudiusPlaylistDto.fromJson(
        fixtureData('audius/playlist_by_id').first,
      ).toDomain();

      expect(item.coverColor, CoverPalette.forSeed('RKxOQ'));
      expect(CoverPalette.colors, contains(item.coverColor));
    });

    test('maps onto the domain item the UI already draws', () {
      final item = AudiusPlaylistDto.fromJson(
        fixtureData('audius/playlist_by_id').first,
      ).toDomain();

      expect(item.id, 'RKxOQ');
      expect(item.title, 'Lofi Space inspired');
      expect(item.subtitle, 'By Lofi Army');
      expect(item.coverUrls.first, endsWith('/480x480.jpg'));
    });
  });
}
