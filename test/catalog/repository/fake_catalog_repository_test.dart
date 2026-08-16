import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';

void main() {
  group('FakeCatalogRepository', () {
    const repository = FakeCatalogRepository();

    /// Every id the catalog exposes. Now that the repository answers by id
    /// rather than handing over everything, a test that wants "all of it" has
    /// to say so -- which is the honest shape: this is what the app itself does
    /// when it resolves a liked or recently-played id.
    Future<Set<String>> allItemIds() async {
      final sections = await repository.fetchHomeSections();
      return sections.expand((section) => section.items).map((item) => item.id).toSet();
    }

    Future<Set<String>> allTrackIds() async {
      final ids = <String>{};
      for (final itemId in await allItemIds()) {
        final detail = await repository.fetchDetail(itemId);
        ids.addAll(detail.tracks.map((track) => track.id));
      }
      return ids;
    }

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

    test('fetchItemsByIds returns exactly the items asked for, de-duplicated', () async {
      final ids = await allItemIds();

      final found = await repository.fetchItemsByIds([...ids, ...ids]);
      final foundIds = found.map((i) => i.id).toList();

      expect(found, isNotEmpty);
      expect(foundIds.toSet(), ids);
      // An id asked for twice yields one item.
      expect(foundIds.toSet().length, foundIds.length);
    });

    test('fetchItemsByIds drops ids the catalog does not have', () async {
      // An id outlives the thing it points at: a playlist removed since it was
      // liked simply stops appearing, rather than raising.
      final found = await repository.fetchItemsByIds(['dm1', 'no-such-id', 'ab2']);

      expect(found.map((i) => i.id), ['dm1', 'ab2']);
    });

    test('fetchItemsByIds given nothing returns nothing', () async {
      expect(await repository.fetchItemsByIds(const []), isEmpty);
    });

    test('every item has cover artwork', () async {
      final all = await repository.fetchItemsByIds(await allItemIds());

      for (final item in all) {
        expect(item.coverUrls, isNotEmpty, reason: item.id);
        expect(item.coverUrls.single, startsWith('https://'), reason: item.id);
        // Deterministic per item: the same seed always returns the same photo,
        // so a cover never changes between runs.
        expect(item.coverUrls.single, contains(item.id), reason: item.id);
      }
    });

    test('items have distinct covers', () async {
      final all = await repository.fetchItemsByIds(await allItemIds());

      expect(all.map((i) => i.coverUrls.single).toSet(), hasLength(all.length));
    });

    // The player only ever holds a queue of Tracks, so a track has to carry its
    // album's cover for the Now Playing screen and the lock screen to show one.
    test('every track carries its album cover', () async {
      final hits = await repository.fetchTracksByIds(await allTrackIds());

      expect(hits, isNotEmpty);
      for (final hit in hits) {
        expect(hit.track.coverUrls, hit.album.coverUrls, reason: hit.track.id);
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

    test('fetchTracksByIds pairs every track with its album', () async {
      final tracks = await repository.fetchTracksByIds(await allTrackIds());
      final itemIds = await allItemIds();

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
      expect(
        byArtist.tracks.every((h) => h.track.artist.toLowerCase().contains('miles davis')),
        isTrue,
      );
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
