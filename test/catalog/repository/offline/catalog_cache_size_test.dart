import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/audius/audius_playlist_dto.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_cache_store.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_json.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_catalog_repository.dart';

import '../../../helpers/fixtures.dart';

/// How much room the offline cache actually takes, measured on real payloads.
///
/// The cache is kept in shared_preferences, which is not a database: the whole
/// file is held in memory and rewritten when it changes. That makes size a
/// correctness concern rather than a housekeeping one, and it is the sort of
/// number that is quietly guessed once and then relied on for years. So it is
/// measured here, from the same captured Audius responses the parser is tested
/// against, and asserted -- loosely, because the point is not to police a few
/// hundred bytes but to notice the day a model starts carrying something big.
///
/// The bounds below are roughly 1.5x what was measured. A field added to [Track]
/// will not fail this; a [CatalogSection] that starts embedding tracklists will.
///
/// The numbers, and they are the reason both caps are what they are -- the first
/// guess at them was three to five times too small, and the caps that guess
/// justified were correspondingly too generous:
///
/// | what                            |  bytes | per entity |
/// | ------------------------------- | ------ | ---------- |
/// | a home screen, 4 rows x 10      |  23 KB |     573 B  |
/// | one 100-track album             |  58 KB |     576 B  |
/// | 64 remembered items             |  37 KB |     578 B  |
/// | 64 remembered track hits        |  73 KB |    1140 B  |
///
/// Around 70% of every entity is cover urls: each carries a primary and three
/// mirrors (see [AudiusArtwork]) at roughly 100 characters apiece. A track hit is
/// double everything else because it carries a whole stand-in album next to its
/// track, each with its own set.
///
/// Trimming the mirrors was considered and rejected. It would save a third of the
/// space and cost the one thing the alternates are for: a saved page is *most*
/// likely to be shown while something is unreachable, which is exactly when a
/// cover's host being unreachable too is worth having an answer for.
/// Read from the shipped default rather than copied, so the measurement can only
/// ever describe the cache the app actually keeps.
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
