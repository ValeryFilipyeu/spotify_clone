import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';

void main() {
  group('FakeCatalogRepository.fetchDetail', () {
    const repository = FakeCatalogRepository();

    test('returns the matching item plus a non-empty tracklist for a known id', () async {
      final detail = await repository.fetchDetail('ab1');
      expect(detail.item.id, 'ab1');
      expect(detail.item.title, 'Currents');
      expect(detail.tracks, isNotEmpty);
    });

    test('throws CatalogItemNotFound for an unknown id', () async {
      expect(
        () => repository.fetchDetail('does-not-exist'),
        throwsA(isA<CatalogItemNotFound>()),
      );
    });

    test('totalDuration equals the sum of the track durations', () async {
      final detail = await repository.fetchDetail('ab1');
      final expected = detail.tracks.fold(Duration.zero, (sum, track) => sum + track.duration);
      expect(detail.totalDuration, expected);
    });

    test('every track across a detail has a unique id', () async {
      final detail = await repository.fetchDetail('jazz');
      final ids = detail.tracks.map((track) => track.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('different playlists use different audio (not all the same sample)', () async {
      final ab1 = await repository.fetchDetail('ab1');
      final ab2 = await repository.fetchDetail('ab2');
      final ab1Urls = ab1.tracks.map((t) => t.audioUrl).toList();
      final ab2Urls = ab2.tracks.map((t) => t.audioUrl).toList();
      expect(ab1Urls, isNot(equals(ab2Urls)));
    });

    test('each track duration is the real (short demo) length, not an invented one', () async {
      final detail = await repository.fetchDetail('dm1');
      // Real demo clips are all well under 5 minutes; the old invented
      // durations (e.g. 4:21) did not match the audio.
      for (final track in detail.tracks) {
        expect(track.duration.inMinutes, lessThan(5));
        expect(track.duration, greaterThan(Duration.zero));
      }
    });

    // Guards against a home card that would open to an empty/erroring screen:
    // every item shown on the home screen must resolve to a real detail.
    test('every home item id resolves to a detail with tracks', () async {
      final sections = await repository.fetchHomeSections();
      final itemIds = sections.expand((section) => section.items).map((item) => item.id);
      for (final id in itemIds) {
        final detail = await repository.fetchDetail(id);
        expect(detail.tracks, isNotEmpty, reason: 'item "$id" had no tracks');
      }
    });
  });
}
