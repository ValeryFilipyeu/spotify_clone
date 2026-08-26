// Also run compiled to JavaScript in CI. This is a codec, and the web is where a
// codec is most likely to disagree with itself: `int` is a JavaScript double
// there, so a duration in milliseconds and an ARGB colour are stored in a type
// that does not exist on the platform reading them back. Reads no fixtures, which
// is what keeps it runnable there.
@Tags(['web'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/models/catalog_json.dart';
import 'package:spotify_clone/network/json_reader.dart';

const _item = CatalogItem(
  id: 'pl1',
  title: 'Late Night Tapes',
  subtitle: 'By Someone',
  coverColor: 0xFF1DB954,
  coverUrls: [
    'https://node1.example/content/abc/480x480.jpg',
    'https://node2.example/content/abc/480x480.jpg',
  ],
);

const _track = Track(
  id: 'tr1',
  title: 'First Light',
  artist: 'Nobody In Particular',
  duration: Duration(minutes: 3, seconds: 41),
  audioUrl: 'https://api.example/v1/tracks/tr1/stream',
  coverUrls: ['https://node1.example/content/def/480x480.jpg'],
);

/// Every test here goes through `jsonEncode`/`jsonDecode` rather than handing the
/// encoder's map straight back to the decoder.
///
/// That round trip is most of the value. A map in memory can hold anything --
/// a `Duration`, a `Set`, an int too large for a double -- and pass a test that
/// never serialises it, then fail on a device the first time it is written to
/// disk. Going through the text also proves each field survives a decoder that
/// answers `Map<String, dynamic>` and hands back `double` where an `int` went in.
Map<String, Object?> _roundTrip(Map<String, Object?> json) =>
    jsonDecode(jsonEncode(json)) as Map<String, Object?>;

void main() {
  group('items', () {
    test('survives a round trip through text', () {
      expect(decodeItem(_roundTrip(encodeItem(_item))), _item);
    });

    test('keeps an item with no artwork distinguishable from one with some', () {
      const bare = CatalogItem(id: 'p', title: 'T', subtitle: 's', coverColor: 1);
      final decoded = decodeItem(_roundTrip(encodeItem(bare)));

      expect(decoded.coverUrls, isEmpty);
      expect(decoded, bare);
    });

    test('keeps an empty subtitle empty rather than rejecting the entry', () {
      // The lenient half of the codec. `subtitle` is non-nullable in the model and
      // may legitimately be '', so reading it strictly -- the way a title is read
      // -- would turn a faithfully stored blank into a miss for the whole item.
      const blank = CatalogItem(id: 'p', title: 'T', subtitle: '', coverColor: 1);
      expect(decodeItem(_roundTrip(encodeItem(blank))), blank);
    });

    test('refuses an item with no id', () {
      final json = _roundTrip(encodeItem(_item))..remove('id');
      expect(() => decodeItem(json), throwsA(isA<JsonFormatError>()));
    });

    test('refuses an item whose title was stored as something other than text', () {
      final json = _roundTrip(encodeItem(_item))..['title'] = 42;
      expect(
        () => decodeItem(json),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'title')),
      );
    });

    test('refuses an artwork field that is not a list at all', () {
      final json = _roundTrip(encodeItem(_item))..['coverUrls'] = 'https://one.example/a.jpg';
      expect(
        () => decodeItem(json),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'coverUrls')),
      );
    });

    test('refuses an artwork list holding something that is not a url', () {
      final json = _roundTrip(encodeItem(_item))..['coverUrls'] = ['ok', 7];
      expect(
        () => decodeItem(json),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'coverUrls[1]')),
      );
    });

    test('names where in the payload the problem was', () {
      // The reason `at` is threaded through every function here: a home snapshot
      // holds forty items, and "expected a non-empty string" on its own does not
      // say which one.
      final json = _roundTrip(encodeItem(_item))..remove('title');
      expect(
        () => decodeItem(json, at: 'sections[2].items[7]'),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'sections[2].items[7].title')),
      );
    });
  });

  group('tracks', () {
    test('survives a round trip through text', () {
      expect(decodeTrack(_roundTrip(encodeTrack(_track))), _track);
    });

    test('keeps the duration to the millisecond', () {
      const odd = Track(
        id: 't',
        title: 'T',
        artist: 'A',
        duration: Duration(minutes: 4, seconds: 7, milliseconds: 123),
        audioUrl: 'url',
      );
      expect(decodeTrack(_roundTrip(encodeTrack(odd))).duration, odd.duration);
    });

    test('reads a duration a decoder handed back as a double', () {
      // JSON has one number type. A stored `221000` may come back as `221000.0`
      // depending on who decoded it, and `as int` would throw on that. This is
      // why the reader goes through `num`.
      final json = _roundTrip(encodeTrack(_track))..['durationMs'] = 221000.0;
      expect(decodeTrack(json).duration, const Duration(milliseconds: 221000));
    });

    test('refuses a track with no audio url', () {
      // Strict on purpose: a track with nothing to play is not a degraded row,
      // it is a row that does nothing when tapped.
      final json = _roundTrip(encodeTrack(_track))..remove('audioUrl');
      expect(() => decodeTrack(json), throwsA(isA<JsonFormatError>()));
    });

    test('refuses a track with no duration', () {
      final json = _roundTrip(encodeTrack(_track))..remove('durationMs');
      expect(() => decodeTrack(json), throwsA(isA<JsonFormatError>()));
    });
  });

  group('home sections', () {
    final sections = [
      CatalogSection(title: 'Trending', items: [_item]),
      const CatalogSection(title: 'Empty row', items: []),
    ];

    test('survives a round trip through text', () {
      expect(decodeSections(_roundTrip(encodeSections(sections))), sections);
    });

    test('refuses the lot when one item deep inside is unreadable', () {
      // All-or-nothing rather than dropping the bad item. A partially decoded
      // home screen is a screen with a hole in it and no explanation for the
      // hole; a rejected payload is a cache miss, which the layer above already
      // knows how to handle.
      final json = _roundTrip(encodeSections(sections));
      ((json['sections']! as List).first as Map)['items'] = [
        {'id': 'x'},
      ];

      expect(() => decodeSections(json), throwsA(isA<JsonFormatError>()));
    });
  });

  group('album detail', () {
    final detail = CatalogDetail(item: _item, tracks: [_track]);

    test('survives a round trip through text', () {
      expect(decodeDetail(_roundTrip(encodeDetail(detail))), detail);
    });

    test('keeps an album with no tracks', () {
      final empty = CatalogDetail(item: _item, tracks: const []);
      expect(decodeDetail(_roundTrip(encodeDetail(empty))), empty);
    });

    test('refuses an album with no header item', () {
      final json = _roundTrip(encodeDetail(detail))..remove('item');
      expect(() => decodeDetail(json), throwsA(isA<JsonFormatError>()));
    });
  });

  group('id-keyed collections', () {
    test('items survive a round trip, keyed by their own ids', () {
      const other = CatalogItem(id: 'pl2', title: 'Second', subtitle: 's', coverColor: 2);
      final decoded = decodeItemsById(_roundTrip(encodeItemsById([_item, other])));

      expect(decoded.keys, unorderedEquals(['pl1', 'pl2']));
      expect(decoded['pl1'], _item);
      expect(decoded['pl2'], other);
    });

    test('hits are keyed by the track id, not the stand-in album id', () {
      // The two are the same string for an Audius upload, which is exactly why
      // this is worth pinning: nothing in the code would look wrong if the album's
      // id were used, right up until a source appears where they differ.
      const hit = TrackHit(track: _track, album: _item);
      final decoded = decodeHitsById(_roundTrip(encodeHitsById([hit])));

      expect(decoded.keys, ['tr1']);
      expect(decoded['tr1'], hit);
    });

    test('refuses a collection holding something that is not an entity', () {
      expect(
        () => decodeItemsById({'pl1': 'not an object'}),
        throwsA(isA<JsonFormatError>().having((e) => e.path, 'path', 'pl1')),
      );
    });

    test('an empty collection is a valid one', () {
      expect(decodeItemsById(_roundTrip(encodeItemsById([]))), isEmpty);
    });
  });
}
