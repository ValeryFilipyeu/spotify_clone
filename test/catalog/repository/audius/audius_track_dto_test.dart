import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_track_dto.dart';
import 'package:spotify_clone/network/json_reader.dart';

import '../../../helpers/fixtures.dart';

void main() {
  group('parsing a real search payload', () {
    test('reads every track', () {
      final tracks = [
        for (final json in fixtureData('audius/track_search'))
          AudiusTrackDto.fromJson(json),
      ];

      expect(tracks.map((t) => t.id), ['95wro', 'ng9rl', '8ME7P']);
      expect(tracks.map((t) => t.durationSeconds), [71, 334, 10940]);
    });

    test('takes the artist from the uploading account', () {
      final track = AudiusTrackDto.fromJson(fixtureData('audius/track_search')[1]);

      expect(track.title, 'lofi type beat');
      expect(track.artist, '[bsdu]');
    });

    test('prefers the 480px artwork', () {
      final track = AudiusTrackDto.fromJson(fixtureData('audius/track_search').first);

      expect(track.artworkUrl, endsWith('/480x480.jpg'));
    });

    test('a track with no artwork parses, with a null cover', () {
      // Not an error: CatalogItem.coverUrl and CoverArt both handle it, and the
      // gradient placeholder shows through.
      final track = AudiusTrackDto.fromJson(fixtureData('audius/track_without_artwork').first);

      expect(track.artworkUrl, isNull);
      expect(track.title, isNotEmpty);
    });
  });

  group('streamability', () {
    test('trusts access.stream over is_streamable', () {
      // `95wro` is a real record with is_streamable:false and access.stream:true
      // that streams perfectly well. Reading the obvious field would silently
      // drop playable music.
      final raw = fixtureData('audius/track_search').first;
      expect(raw['is_streamable'], isFalse, reason: 'fixture no longer exercises the quirk');

      expect(AudiusTrackDto.fromJson(raw).isStreamable, isTrue);
    });

    test('a gated track is not streamable', () {
      final raw = {...fixtureData('audius/track_search')[1], 'access': {'stream': false}};

      expect(AudiusTrackDto.fromJson(raw).isStreamable, isFalse);
    });

    test('a payload with no access object is assumed streamable', () {
      // Under-filter rather than empty the app if the shape ever slims down.
      final raw = {...fixtureData('audius/track_search')[1]}..remove('access');

      expect(AudiusTrackDto.fromJson(raw).isStreamable, isTrue);
    });
  });

  group('toDomain', () {
    test('uses the stable stream url, not the signed one in the payload', () {
      // The payload's own stream.url is pre-signed and timestamped, so it
      // expires -- and a Track is held in the queue, persisted through history
      // and handed to the OS media session. Storing that url would give us a
      // queue that plays now and fails in an hour.
      final raw = fixtureData('audius/track_search')[1];
      final signed = (raw['stream']! as Map<String, Object?>)['url']! as String;
      expect(signed, contains('signature='), reason: 'fixture no longer exercises the quirk');

      final stable = Uri.parse('https://api.audius.co/v1/tracks/ng9rl/stream?app_name=Test');
      final track = AudiusTrackDto.fromJson(raw).toDomain(streamUrl: stable);

      expect(track.audioUrl, stable.toString());
      expect(track.audioUrl, isNot(contains('signature=')));
    });

    test('carries the metadata across', () {
      final track = AudiusTrackDto.fromJson(fixtureData('audius/track_search')[1])
          .toDomain(streamUrl: Uri.parse('https://example.test/stream'));

      expect(track.id, 'ng9rl');
      expect(track.title, 'lofi type beat');
      expect(track.artist, '[bsdu]');
      expect(track.duration, const Duration(seconds: 334));
      expect(track.coverUrl, endsWith('/480x480.jpg'));
    });
  });

  group('malformed payloads', () {
    test('a missing title says which field, and where', () {
      final raw = {...fixtureData('audius/track_search').first}..remove('title');

      expect(
        () => AudiusTrackDto.fromJson(raw, at: 'data[0]'),
        throwsA(isA<JsonFormatError>()
            .having((e) => e.path, 'path', 'data[0].title')
            .having((e) => e.reason, 'reason', contains('non-empty string'))),
      );
    });

    test('a nested missing field names the nested path', () {
      final raw = {...fixtureData('audius/track_search').first, 'user': <String, Object?>{}};

      expect(
        () => AudiusTrackDto.fromJson(raw, at: 'data[3]'),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'data[3].user.name')),
      );
    });

    test('a duration sent as a string is rejected rather than silently zero', () {
      final raw = {...fixtureData('audius/track_search').first, 'duration': '334'};

      expect(
        () => AudiusTrackDto.fromJson(raw),
        throwsA(isA<JsonFormatError>().having((e) => e.reason, 'reason', contains('number'))),
      );
    });

    test('an empty title counts as missing', () {
      // A track titled "" is no more displayable than one with no title key.
      final raw = {...fixtureData('audius/track_search').first, 'title': ''};

      expect(() => AudiusTrackDto.fromJson(raw), throwsA(isA<JsonFormatError>()));
    });
  });
}
