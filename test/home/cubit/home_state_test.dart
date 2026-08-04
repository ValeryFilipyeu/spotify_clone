import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/home/cubit/home_state.dart';

CatalogItem _item(String id) =>
    CatalogItem(id: id, title: id.toUpperCase(), subtitle: 's', coverColor: 0xFF000000);

final _catalog = [_item('dm1'), _item('lofi'), _item('ab1')];

final _state = HomeState(
  status: HomeStatus.success,
  sections: const [CatalogSection(title: 'Made for you', items: [])],
  itemsById: {for (final item in _catalog) item.id: item},
);

void main() {
  group('HomeState.sectionsFor', () {
    test('shows no personal row for an account that has played nothing', () {
      final sections = _state.sectionsFor(const []);

      expect(sections.map((s) => s.title), ['Made for you']);
    });

    test('puts recently played above the catalog rows', () {
      final sections = _state.sectionsFor(const ['lofi']);

      expect(sections.map((s) => s.title), ['Recently played', 'Made for you']);
    });

    test('keeps history order, which is most-recent-first', () {
      final sections = _state.sectionsFor(const ['ab1', 'dm1', 'lofi']);

      expect(sections.first.items.map((i) => i.id), ['ab1', 'dm1', 'lofi']);
    });

    // History outlives the catalog it points into, so an id with nothing behind
    // it has to disappear rather than render as a blank card.
    test('drops ids the catalog no longer has', () {
      final sections = _state.sectionsFor(const ['dm1', 'deleted-playlist', 'ab1']);

      expect(sections.first.items.map((i) => i.id), ['dm1', 'ab1']);
    });

    test('and drops the whole row when none of them resolve', () {
      final sections = _state.sectionsFor(const ['gone', 'also-gone']);

      expect(sections.map((s) => s.title), ['Made for you']);
    });

    test('resolves nothing before the catalog has loaded', () {
      expect(const HomeState().sectionsFor(const ['dm1']), isEmpty);
    });
  });
}
