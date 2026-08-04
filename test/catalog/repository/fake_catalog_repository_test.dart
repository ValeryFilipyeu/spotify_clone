import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';

void main() {
  group('FakeCatalogRepository', () {
    const repository = FakeCatalogRepository();

    test('returns a non-empty list of sections', () async {
      final sections = await repository.fetchHomeSections();
      expect(sections, isNotEmpty);
    });

    test('every section has a title and at least one item', () async {
      final sections = await repository.fetchHomeSections();
      for (final section in sections) {
        expect(section.title, isNotEmpty);
        expect(section.items, isNotEmpty);
      }
    });

    test('every item id is unique across all sections', () async {
      final sections = await repository.fetchHomeSections();
      final ids = sections.expand((section) => section.items).map((item) => item.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('is deterministic across calls', () async {
      final first = await repository.fetchHomeSections();
      final second = await repository.fetchHomeSections();
      expect(first, second);
    });

    test('fetchAllItems returns every section item, de-duplicated', () async {
      final sections = await repository.fetchHomeSections();
      final all = await repository.fetchAllItems();

      final expectedIds = sections.expand((s) => s.items).map((i) => i.id).toSet();
      final actualIds = all.map((i) => i.id).toList();

      expect(all, isNotEmpty);
      expect(actualIds.toSet(), expectedIds); // same set of ids
      expect(actualIds.toSet().length, actualIds.length); // no duplicates
    });

    test('every item has cover artwork', () async {
      final all = await repository.fetchAllItems();

      for (final item in all) {
        expect(item.coverUrl, isNotNull, reason: item.id);
        expect(item.coverUrl, startsWith('https://'), reason: item.id);
        // Deterministic per item: the same seed always returns the same photo,
        // so a cover never changes between runs.
        expect(item.coverUrl, contains(item.id), reason: item.id);
      }
    });

    test('items have distinct covers', () async {
      final all = await repository.fetchAllItems();

      expect(all.map((i) => i.coverUrl).toSet(), hasLength(all.length));
    });

    // The player only ever holds a queue of Tracks, so a track has to carry its
    // album's cover for the Now Playing screen and the lock screen to show one.
    test('every track carries its album cover', () async {
      final hits = await repository.fetchAllTracks();

      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(hit.track.coverUrl, hit.album.coverUrl, reason: hit.track.id);
      }
    });

    test('search matches album title or subtitle, case-insensitively', () async {
      final byTitle = await repository.search('rainbows'); // "In Rainbows" title
      final bySubtitle = await repository.search('radiohead'); // a subtitle
      final byUpper = await repository.search('RADIOHEAD'); // case-insensitive

      expect(byTitle.items.map((i) => i.id), contains('ab2'));
      expect(bySubtitle.items.map((i) => i.id), contains('ab2'));
      expect(byUpper.items.map((i) => i.id), bySubtitle.items.map((i) => i.id));
    });

    test('fetchAllTracks returns every track paired with its album', () async {
      final tracks = await repository.fetchAllTracks();
      final items = await repository.fetchAllItems();
      final itemIds = items.map((i) => i.id).toSet();

      expect(tracks, isNotEmpty);
      // Every track's album is a real catalog item.
      expect(tracks.every((h) => itemIds.contains(h.album.id)), isTrue);
      // The specific "Karma Police" song is attributed to Daily Mix 2.
      final karma = tracks.firstWhere((h) => h.track.title == 'Karma Police');
      expect(karma.album.id, 'dm2');
    });

    test('search matches individual songs by title or artist', () async {
      // "Karma Police" is a track on Daily Mix 2 (dm2); no album title/subtitle
      // contains "karma", so this only surfaces via the tracklist scan.
      final byTitle = await repository.search('karma police');
      expect(byTitle.items, isEmpty);
      expect(byTitle.tracks.map((h) => h.track.title), contains('Karma Police'));

      // Each song hit carries the album/playlist it belongs to.
      final karma = byTitle.tracks.firstWhere((h) => h.track.title == 'Karma Police');
      expect(karma.album.id, 'dm2');

      // Matching an artist surfaces that artist's songs from across catalogs.
      final byArtist = await repository.search('miles davis');
      expect(byArtist.tracks, isNotEmpty);
      expect(byArtist.tracks.every((h) => h.track.artist.toLowerCase().contains('miles davis')), isTrue);
    });

    test('search returns empty results for a blank query', () async {
      expect((await repository.search('')).isEmpty, isTrue);
      expect((await repository.search('   ')).isEmpty, isTrue);
    });

    test('search returns empty results when nothing matches', () async {
      expect((await repository.search('zzzzz')).isEmpty, isTrue);
    });
  });
}
