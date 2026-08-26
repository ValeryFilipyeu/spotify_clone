import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_playlist_dto.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_cache_store.dart';
import 'package:spotify_clone/catalog/models/catalog_json.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_catalog_repository.dart';

import '../../../helpers/fixtures.dart';

/// How much room the offline cache takes, measured on real payloads.
///
/// shared_preferences rewrites its whole file on every change, so size is a
/// correctness concern -- and the sort of number that gets guessed once and
/// relied on for years. Measured from the captured Audius responses the parser is
/// tested against, and asserted loosely: the point is to notice the day a model
/// starts carrying something big, not to police a few hundred bytes.
///
/// | what                       |  bytes | per entity |
/// | -------------------------- | ------ | ---------- |
/// | a home screen, 4 rows x 10 |  23 KB |     573 B  |
/// | one 100-track album        |  58 KB |     576 B  |
/// | 64 remembered items        |  37 KB |     578 B  |
/// | 64 remembered track hits   |  73 KB |    1140 B  |
///
/// The first guess at these was three to five times too small, which is why both
/// caps moved. About 70% of each entity is cover urls -- a primary and three
/// mirrors at ~100 characters each -- and a track hit doubles that by carrying a
/// stand-in album beside its track.
///
/// Dropping the mirrors would save a third and cost the one thing they are for: a
/// saved page is most likely to be read while something is unreachable.
/// Read from the shipped default, so this can only describe the real cache.
const int _entityCap = OfflineCatalogRepository.defaultMaxEntities;

void main() {
  /// Real items off the wire. The search fixture holds two, which is not a row,
  /// so they are repeated under fresh ids to make one up -- real field values at
  /// a realistic count, rather than a row of `'title'`.
  List<CatalogItem> realItems(int count) {
    final parsed = [
      for (final json in fixtureData('audius/playlist_search'))
        AudiusPlaylistDto.fromJson(json).toDomain(),
    ];

    return [
      for (var index = 0; index < count; index++)
        _withId(parsed[index % parsed.length], 'item$index'),
    ];
  }

  List<Track> realTracks(int count) {
    final parsed = AudiusPlaylistDto.fromJson(fixtureData('audius/playlist_by_id').first).tracks
        .map(
          (dto) => dto.toDomain(streamUrl: Uri.parse('https://api.audius.co/v1/tracks/x/stream')),
        )
        .toList();

    return [
      for (var index = 0; index < count; index++)
        _withTrackId(parsed[index % parsed.length], 'track$index'),
    ];
  }

  int bytesOf(Map<String, Object?> json) => utf8.encode(jsonEncode(json)).length;

  test('a whole home screen', () {
    final sections = [
      for (final title in ['Trending playlists', 'Lo-fi & chill', 'Jazz', 'Electronic'])
        CatalogSection(title: title, items: realItems(10)),
    ];

    final bytes = bytesOf(encodeSections(sections));
    printOnFailure('home snapshot: $bytes bytes');
    expect(bytes, lessThan(36 * 1024), reason: 'measured 23 KB');
  });

  test('a long album', () {
    // A hundred tracks is a generous album and a plausible playlist, and this is
    // the only entry whose size is driven by something a user chooses.
    final detail = CatalogDetail(item: realItems(1).single, tracks: realTracks(100));

    final bytes = bytesOf(encodeDetail(detail));
    printOnFailure('100-track album: $bytes bytes');
    expect(bytes, lessThan(88 * 1024), reason: 'measured 58 KB');

    // What the cap is really about: twelve of these is the pathological end of
    // the budget, and the number was chosen knowing it.
    printOnFailure(
      'a full album cache: ${bytes * CatalogCacheStore.defaultMaxEvictableEntries ~/ 1024} KB',
    );
  });

  test('a full collection of remembered items', () {
    final bytes = bytesOf(encodeItemsById(realItems(_entityCap)));
    printOnFailure('$_entityCap items: $bytes bytes');
    expect(bytes, lessThan(56 * 1024), reason: 'measured 37 KB');
  });

  test('a full collection of remembered track hits', () {
    // The largest of the fixed keys, because a hit carries a whole stand-in album
    // alongside its track.
    final hits = [
      for (final (index, track) in realTracks(_entityCap).indexed)
        TrackHit(track: track, album: _withId(realItems(1).single, 'album$index')),
    ];

    final bytes = bytesOf(encodeHitsById(hits));
    printOnFailure('$_entityCap track hits: $bytes bytes');
    expect(bytes, lessThan(112 * 1024), reason: 'measured 73 KB');
  });
}

CatalogItem _withId(CatalogItem item, String id) => CatalogItem(
  id: id,
  title: item.title,
  subtitle: item.subtitle,
  coverColor: item.coverColor,
  coverUrls: item.coverUrls,
);

Track _withTrackId(Track track, String id) => Track(
  id: id,
  title: track.title,
  artist: track.artist,
  duration: track.duration,
  audioUrl: track.audioUrl,
  coverUrls: track.coverUrls,
);
