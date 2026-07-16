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
