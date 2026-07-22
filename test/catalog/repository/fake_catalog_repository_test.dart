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
  });
}
