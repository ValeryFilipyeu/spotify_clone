import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/library/cubit/library_cubit.dart';
import 'package:spotify_clone/library/cubit/library_state.dart';

class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  void invalidate() {}

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async => throw Exception('down');

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) async => throw Exception('down');

  @override
  Future<SearchResults> search(String query) => throw UnimplementedError();

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

/// Counts loads and invalidations, for the refresh tests.
class _RefreshableCatalog extends FakeCatalogRepository {
  _RefreshableCatalog({this.failFrom});

  final int? failFrom;
  int itemLoads = 0;
  int invalidations = 0;

  @override
  void invalidate() => invalidations++;

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    itemLoads++;
    if (failFrom != null && itemLoads >= failFrom!) throw Exception('down');
    return super.fetchItemsByIds(ids);
  }
}

void main() {
  group('LibraryCubit', () {
    test('initial state is LibraryStatus.initial with no items', () {
      final cubit = LibraryCubit(catalogRepository: const FakeCatalogRepository());
      expect(cubit.state, const LibraryState());
      cubit.close();
    });

    blocTest<LibraryCubit, LibraryState>(
      'emits [loading, success] with the liked items and tracks resolved',
      build: () => LibraryCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) async {
        // Likes are untyped: one set holds both playlist ids and song ids, and
        // only the catalog knows which is which.
        final detail = await const FakeCatalogRepository().fetchDetail('dm1');
        await cubit.loadLibrary(['dm1', detail.tracks.first.id]);
      },
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.success)
            .having((s) => s.items, 'items', isNotEmpty)
            .having((s) => s.tracks, 'tracks', isNotEmpty),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'emits [loading, failure] with a message when the repository throws',
      build: () => LibraryCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.loadLibrary(const ['dm1']),
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.failure)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'nothing liked is a successful empty library, not a request',
      // Going through a loading state to fetch an empty set would flash a
      // spinner before the "nothing liked yet" message.
      build: () => LibraryCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.loadLibrary(const []),
      expect: () => [
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.success)
            .having((s) => s.items, 'items', isEmpty)
            .having((s) => s.tracks, 'tracks', isEmpty),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'syncWith refetches when something new is liked',
      build: () => LibraryCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) async {
        await cubit.loadLibrary(const ['dm1']);
        await cubit.syncWith(const ['dm1', 'ab2']);
      },
      verify: (cubit) {
        expect(cubit.state.items.map((i) => i.id), containsAll(['dm1', 'ab2']));
      },
    );

    blocTest<LibraryCubit, LibraryState>(
      'syncWith does not refetch when something is merely unliked',
      // The view filters the removed one out of what is already loaded, so a
      // round trip would buy nothing.
      build: () => LibraryCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) async {
        await cubit.loadLibrary(const ['dm1', 'ab2']);
        await cubit.syncWith(const ['dm1']);
      },
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>().having((s) => s.status, 'status', LibraryStatus.success),
      ],
    );

    group('refresh', () {
      test('discards the cache and reloads the same liked set', () async {
        final catalog = _RefreshableCatalog();
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary(const ['dm1']);
        expect(await cubit.refresh(), isTrue);

        expect(catalog.invalidations, 1);
        expect(catalog.itemLoads, 2);
      });

      test('with nothing liked there is nothing to fetch', () async {
        final catalog = _RefreshableCatalog();
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary(const []);
        expect(await cubit.refresh(), isTrue);

        expect(catalog.itemLoads, 0);
      });

      test('a failed refresh keeps the list and reports the failure', () async {
        final catalog = _RefreshableCatalog(failFrom: 2);
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary(const ['dm1']);
        final before = cubit.state.items;

        expect(await cubit.refresh(), isFalse);
        expect(cubit.state.status, LibraryStatus.success);
        expect(cubit.state.items, before);
      });
    });
  });
}
