import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotify_clone/catalog/models/catalog_failure.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_catalog_repository.dart';
import 'package:spotify_clone/network/api_client.dart';
import 'package:spotify_clone/network/api_failure.dart';

import '../../../helpers/fixtures.dart';

/// Builds a repository whose HTTP layer replays recorded payloads.
///
/// [routes] maps a path fragment to the fixture answering it, so a test says
/// which endpoint returns what and nothing else. Anything unrouted 404s, which
/// makes an unexpected request loud instead of silent.
({AudiusCatalogRepository repository, List<Uri> requested}) repositoryWith(
  Map<String, String> routes, {
  Map<String, int> statuses = const {},
}) {
  final requested = <Uri>[];
  final client = ApiClient(
    baseUrl: AudiusCatalogRepository.baseUrl,
    defaultQuery: const {'app_name': AudiusCatalogRepository.appName},
    httpClient: MockClient((request) async {
      requested.add(request.url);
      for (final entry in routes.entries) {
        if (request.url.path.contains(entry.key)) {
          final status = statuses[entry.key] ?? 200;
          return http.Response(jsonEncode(fixture(entry.value)), status);
        }
      }
      return http.Response(jsonEncode({'code': 404, 'error': 'no route'}), 404);
    }),
  );
  addTearDown(client.close);
  return (repository: AudiusCatalogRepository(client: client), requested: requested);
}

void main() {
  group('fetchDetail', () {
    test('reads the item and its embedded tracklist in one request', () async {
      final fake = repositoryWith({'playlists/': 'audius/playlist_by_id'});

      final detail = await fake.repository.fetchDetail('RKxOQ');

      expect(detail.item.title, 'Lofi Space inspired');
      expect(detail.tracks, isNotEmpty);
      expect(fake.requested, hasLength(1), reason: 'the tracklist came embedded');
    });

    test('builds the stable stream url for each track', () async {
      final fake = repositoryWith({'playlists/': 'audius/playlist_by_id'});

      final detail = await fake.repository.fetchDetail('RKxOQ');

      for (final track in detail.tracks) {
        expect(
          track.audioUrl,
          'https://api.audius.co/v1/tracks/${track.id}/stream'
          '?app_name=${AudiusCatalogRepository.appName}',
        );
      }
    });

    test('an unknown id becomes CatalogItemNotFound, not a raw HTTP failure', () async {
      // Audius answers a bad id with 400 "invalid playlistId" rather than 404.
      final fake = repositoryWith(
        {'playlists/': 'audius/error_invalid_id'},
        statuses: {'playlists/': 400},
      );

      await expectLater(fake.repository.fetchDetail('ZZZZZ'), throwsA(isA<CatalogItemNotFound>()));
    });

    test('an empty result is also not found', () async {
      final fake = repositoryWith({'playlists/': 'audius/empty_data'});

      await expectLater(fake.repository.fetchDetail('RKxOQ'), throwsA(isA<CatalogItemNotFound>()));
    });

    test('a server error is not disguised as a missing item', () async {
      // 500 means the catalog is broken, not that the playlist is gone.
      final fake = repositoryWith(
        {'playlists/': 'audius/empty_data'},
        statuses: {'playlists/': 500},
      );

      await expectLater(fake.repository.fetchDetail('RKxOQ'), throwsA(isA<HttpErrorStatus>()));
    });
  });

  group('track filtering', () {
    test('drops uploads too long to be songs', () async {
      // The search fixture holds a real 10,940-second "track" alongside normal
      // ones. One of those in a row of songs makes the screen look broken.
      final fake = repositoryWith({
        'tracks/search': 'audius/track_search',
        'playlists/search': 'audius/empty_data',
      });

      final results = await fake.repository.search('lofi');

      expect(results.tracks.map((h) => h.track.id), isNot(contains('8ME7P')));
      for (final hit in results.tracks) {
        expect(hit.track.duration, lessThanOrEqualTo(AudiusCatalogRepository.maxTrackDuration));
      }
    });

    test('keeps a track whose legacy is_streamable flag lies', () async {
      // `95wro` reports is_streamable:false with access.stream:true and plays
      // fine. Filtering on the obvious field would silently drop playable music.
      final fake = repositoryWith({
        'tracks/search': 'audius/track_search',
        'playlists/search': 'audius/empty_data',
      });

      final results = await fake.repository.search('lofi');

      expect(results.tracks.map((h) => h.track.id), contains('95wro'));
    });
  });

  group('search', () {
    test('asks both endpoints and returns both halves', () async {
      final fake = repositoryWith({
        'tracks/search': 'audius/track_search',
        'playlists/search': 'audius/playlist_search',
      });

      final results = await fake.repository.search('lofi');

      expect(results.tracks, isNotEmpty);
      expect(results.items.map((i) => i.id), ['RKxOQ', 'ebd1O']);
      expect(fake.requested, hasLength(2));
    });

    test('a blank query makes no request at all', () async {
      final fake = repositoryWith({'tracks/search': 'audius/track_search'});

      expect((await fake.repository.search('   ')).isEmpty, isTrue);
      expect(fake.requested, isEmpty);
    });

    test('pairs each song with something to show as its album', () async {
      // An Audius upload has no reliable album backlink, so the stand-in is
      // built from the track: the results row prints `artist - album`.
      final fake = repositoryWith({
        'tracks/search': 'audius/track_search',
        'playlists/search': 'audius/empty_data',
      });

      final hit = (await fake.repository.search('lofi')).tracks.first;

      expect(hit.album.title, hit.track.title);
      expect(hit.album.subtitle, hit.track.artist);
      expect(hit.album.coverUrl, hit.track.coverUrl);
    });
  });

  group('fetchItemsByIds', () {
    test('asks for every id in one request', () async {
      final fake = repositoryWith({'playlists': 'audius/playlist_search'});

      await fake.repository.fetchItemsByIds(['RKxOQ', 'ebd1O']);

      expect(fake.requested, hasLength(1));
      expect(fake.requested.single.queryParametersAll['id'], ['RKxOQ', 'ebd1O']);
    });

    test('an empty set makes no request', () async {
      final fake = repositoryWith({'playlists': 'audius/playlist_search'});

      expect(await fake.repository.fetchItemsByIds(const []), isEmpty);
      expect(fake.requested, isEmpty);
    });

    test('a duplicated id is asked for once', () async {
      final fake = repositoryWith({'playlists': 'audius/playlist_search'});

      await fake.repository.fetchItemsByIds(['RKxOQ', 'RKxOQ']);

      expect(fake.requested.single.queryParametersAll['id'], ['RKxOQ']);
    });
  });

  group('fetchHomeSections', () {
    test('composes several rows, since the API has no editorial home', () async {
      final fake = repositoryWith({
        'playlists/trending': 'audius/playlist_search',
        'playlists/search': 'audius/playlist_search',
      });

      final sections = await fake.repository.fetchHomeSections();

      expect(sections.map((s) => s.title), [
        'Trending playlists',
        'Lo-fi & chill',
        'Jazz',
        'Electronic',
      ]);
      for (final section in sections) {
        expect(section.items, isNotEmpty);
      }
    });

    test('a row that fails is dropped rather than taking the screen with it', () async {
      // Three rows out of four is still a home screen.
      final fake = repositoryWith(
        {'playlists/trending': 'audius/empty_data', 'playlists/search': 'audius/playlist_search'},
        statuses: {'playlists/trending': 503},
      );

      final sections = await fake.repository.fetchHomeSections();

      expect(sections.map((s) => s.title), ['Lo-fi & chill', 'Jazz', 'Electronic']);
    });

    test('every row failing is a failure, not a blank screen', () async {
      final fake = repositoryWith({'playlists': 'audius/empty_data'}, statuses: {'playlists': 503});

      await expectLater(fake.repository.fetchHomeSections(), throwsA(isA<ApiFailure>()));
    });

    test('an empty row is dropped rather than rendered as a bare heading', () async {
      final fake = repositoryWith({
        'playlists/trending': 'audius/empty_data',
        'playlists/search': 'audius/playlist_search',
      });

      final sections = await fake.repository.fetchHomeSections();

      expect(sections.map((s) => s.title), isNot(contains('Trending playlists')));
    });
  });

  group('malformed payloads', () {
    test('a response that is not the expected shape names the request', () async {
      final fake = repositoryWith({'playlists/': 'audius/error_invalid_id'});

      await expectLater(
        fake.repository.fetchDetail('RKxOQ'),
        throwsA(
          isA<MalformedResponse>().having(
            (f) => f.uri.path,
            'uri.path',
            contains('playlists/RKxOQ'),
          ),
        ),
      );
    });
  });
}
