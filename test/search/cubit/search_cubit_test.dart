import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/search/cubit/search_cubit.dart';
import 'package:spotify_clone/search/cubit/search_state.dart';

const _items = [
  CatalogItem(id: 'a', title: 'Currents', subtitle: 'Tame Impala', coverColor: 0),
  CatalogItem(id: 'b', title: 'In Rainbows', subtitle: 'Radiohead', coverColor: 0),
  CatalogItem(id: 'c', title: 'Jazz Vibes', subtitle: 'Chill backdrop', coverColor: 0),
];

/// Filters like the real fake, and records every query it was actually asked to
/// search -- so a test can assert debouncing collapsed a burst of keystrokes
/// into a single call.
class _RecordingCatalogRepository implements CatalogRepository {
  _RecordingCatalogRepository(this.items);

  final List<CatalogItem> items;
  final List<String> queries = [];

  @override
  Future<List<CatalogItem>> search(String query) async {
    queries.add(query);
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const [];
    return items
        .where((i) => i.title.toLowerCase().contains(needle) || i.subtitle.toLowerCase().contains(needle))
        .toList();
  }

  @override
  Future<List<CatalogItem>> fetchAllItems() async => items;

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogItem>> search(String query) async => throw Exception('down');

  @override
  Future<List<CatalogItem>> fetchAllItems() => throw UnimplementedError();

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

// Comfortably past the 350ms debounce so the timer fires within the test.
const _pastDebounce = Duration(milliseconds: 500);

void main() {
  group('SearchCubit', () {
    late _RecordingCatalogRepository repo;

    blocTest<SearchCubit, SearchState>(
      'a blank query returns to the prompt and never hits the repository',
      setUp: () => repo = _RecordingCatalogRepository(_items),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('   '),
      wait: _pastDebounce,
      expect: () => [
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.initial)
            .having((s) => s.results, 'results', isEmpty),
      ],
      verify: (_) => expect(repo.queries, isEmpty),
    );

    blocTest<SearchCubit, SearchState>(
      'debounces a burst of keystrokes into a single search for the final query',
      setUp: () => repo = _RecordingCatalogRepository(_items),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) {
        cubit.queryChanged('r');
        cubit.queryChanged('ra');
        cubit.queryChanged('rad');
      },
      wait: _pastDebounce,
      verify: (_) => expect(repo.queries, ['rad']),
    );

    blocTest<SearchCubit, SearchState>(
      'a settled query emits [loading, success] with the matches',
      setUp: () => repo = _RecordingCatalogRepository(_items),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('radio'), // matches "Radiohead"
      wait: _pastDebounce,
      skip: 1, // the immediate query echo
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.results.map((i) => i.id).toList(), 'result ids', ['b']),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'a query with no matches settles on success with empty results',
      setUp: () => repo = _RecordingCatalogRepository(_items),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('zzzzz'),
      wait: _pastDebounce,
      skip: 1,
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.results, 'results', isEmpty),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'emits [loading, failure] when the search call throws',
      build: () => SearchCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.queryChanged('radio'),
      wait: _pastDebounce,
      skip: 1,
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.failure)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
