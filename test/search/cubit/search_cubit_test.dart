import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/search/cubit/search_cubit.dart';
import 'package:spotify_clone/search/cubit/search_state.dart';

/// A tiny deterministic stub -- same "small stub as its own test double"
/// approach used elsewhere. Only fetchAllItems is exercised here.
class _StubCatalogRepository implements CatalogRepository {
  const _StubCatalogRepository(this.items);

  final List<CatalogItem> items;

  @override
  Future<List<CatalogItem>> fetchAllItems() async => items;

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogItem>> fetchAllItems() async => throw Exception('down');

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

const _items = [
  CatalogItem(id: 'a', title: 'Currents', subtitle: 'Tame Impala', coverColor: 0),
  CatalogItem(id: 'b', title: 'In Rainbows', subtitle: 'Radiohead', coverColor: 0),
  CatalogItem(id: 'c', title: 'Jazz Vibes', subtitle: 'Chill backdrop', coverColor: 0),
];

void main() {
  group('SearchCubit', () {
    blocTest<SearchCubit, SearchState>(
      'loadCatalog emits [loading, success] with all items',
      build: () => SearchCubit(catalogRepository: const _StubCatalogRepository(_items)),
      act: (cubit) => cubit.loadCatalog(),
      expect: () => [
        const SearchState(status: SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.allItems, 'allItems', _items),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'loadCatalog emits [loading, failure] when the repository throws',
      build: () => SearchCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.loadCatalog(),
      expect: () => [
        const SearchState(status: SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.failure)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'an empty query yields no results (prompt state), not the whole catalog',
      build: () => SearchCubit(catalogRepository: const _StubCatalogRepository(_items)),
      act: (cubit) async {
        await cubit.loadCatalog();
        cubit.queryChanged('   ');
      },
      skip: 2, // the two loadCatalog emissions
      expect: () => [
        isA<SearchState>()
            .having((s) => s.query, 'query', '   ')
            .having((s) => s.results, 'results', isEmpty),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'filters by title or subtitle, case-insensitively',
      build: () => SearchCubit(catalogRepository: const _StubCatalogRepository(_items)),
      act: (cubit) async {
        await cubit.loadCatalog();
        cubit.queryChanged('radio'); // matches "Radiohead" subtitle
      },
      skip: 2,
      expect: () => [
        isA<SearchState>().having((s) => s.results.map((i) => i.id).toList(), 'result ids', ['b']),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'a query with no matches yields empty results',
      build: () => SearchCubit(catalogRepository: const _StubCatalogRepository(_items)),
      act: (cubit) async {
        await cubit.loadCatalog();
        cubit.queryChanged('zzzzz');
      },
      skip: 2,
      expect: () => [
        isA<SearchState>()
            .having((s) => s.query, 'query', 'zzzzz')
            .having((s) => s.results, 'results', isEmpty),
      ],
    );
  });
}
