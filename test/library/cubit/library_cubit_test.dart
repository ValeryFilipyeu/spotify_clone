import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/likes/models/liked_id.dart';
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

/// Only the item lookup is down. Stands in for being offline with songs saved
/// and no albums saved: the offline layer has nothing to recall for the items,
/// so it rethrows, while the tracks come back off the disk.
class _ItemsDownCatalog extends FakeCatalogRepository {
  const _ItemsDownCatalog();

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async => throw Exception('down');
}

/// Records which ids each lookup was asked about.
class _RecordingCatalog extends FakeCatalogRepository {
  _RecordingCatalog();

  final List<Set<String>> itemIdsAsked = [];
  final List<Set<String>> trackIdsAsked = [];

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    itemIdsAsked.add(ids.toSet());
    return super.fetchItemsByIds(ids);
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) {
    trackIdsAsked.add(ids.toSet());
    return super.fetchTracksByIds(ids);
  }
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
        final detail = await const FakeCatalogRepository().fetchDetail('dm1');
        await cubit.loadLibrary({const LikedId.item('dm1'), LikedId.track(detail.tracks.first.id)});
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
      act: (cubit) => cubit.loadLibrary({const LikedId.item('dm1')}),
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
      act: (cubit) => cubit.loadLibrary(const {}),
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
        await cubit.loadLibrary({const LikedId.item('dm1')});
        await cubit.syncWith({const LikedId.item('dm1'), const LikedId.item('ab2')});
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
        await cubit.loadLibrary({const LikedId.item('dm1'), const LikedId.item('ab2')});
        await cubit.syncWith({const LikedId.item('dm1')});
      },
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>().having((s) => s.status, 'status', LibraryStatus.success),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'shows the half it could resolve when the other half is unreachable',
      // Offline with songs saved and no albums saved. The item lookup has
      // nothing to recall and rethrows; awaiting the pair together used to make
      // that take the songs down with it and draw an error page over tracks
      // sitting on the device.
      build: () => LibraryCubit(catalogRepository: const _ItemsDownCatalog()),
      act: (cubit) async {
        final detail = await const FakeCatalogRepository().fetchDetail('dm1');
        await cubit.loadLibrary({const LikedId.item('dm1'), LikedId.track(detail.tracks.first.id)});
      },
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.success)
            .having((s) => s.items, 'items', isEmpty)
            .having((s) => s.tracks, 'tracks', isNotEmpty),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'a library of albums alone fails when the album lookup does',
      // The other side of the rule above: with no songs liked, the track lookup
      // is never made, so its vacuous success must not be read as "half of it
      // worked" and turn an unreachable library into an empty one.
      build: () => LibraryCubit(catalogRepository: const _ItemsDownCatalog()),
      act: (cubit) => cubit.loadLibrary({const LikedId.item('dm1')}),
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>().having((s) => s.status, 'status', LibraryStatus.failure),
      ],
    );

    test('asks each lookup only about ids of its own kind', () async {
      // An id can name both a playlist and a song (see LikedId). Passing the
      // whole liked set to both lookups is what made one like show up as two
      // rows in Your Library.
      final catalog = _RecordingCatalog();
      final cubit = LibraryCubit(catalogRepository: catalog);
      addTearDown(cubit.close);

      await cubit.loadLibrary({const LikedId.item('aA8xa'), const LikedId.track('other')});

      expect(catalog.itemIdsAsked, [
        {'aA8xa'},
      ]);
      expect(catalog.trackIdsAsked, [
        {'other'},
      ]);
    });

    test('a kind nobody liked is not asked about at all', () async {
      final catalog = _RecordingCatalog();
      final cubit = LibraryCubit(catalogRepository: catalog);
      addTearDown(cubit.close);

      await cubit.loadLibrary({const LikedId.item('dm1')});

      expect(catalog.trackIdsAsked, isEmpty);
    });

    group('refresh', () {
      test('discards the cache and reloads the same liked set', () async {
        final catalog = _RefreshableCatalog();
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary({const LikedId.item('dm1')});
        expect(await cubit.refresh(), isTrue);

        expect(catalog.invalidations, 1);
        expect(catalog.itemLoads, 2);
      });

      test('with nothing liked there is nothing to fetch', () async {
        final catalog = _RefreshableCatalog();
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary(const {});
        expect(await cubit.refresh(), isTrue);

        expect(catalog.itemLoads, 0);
      });

      test('a failed refresh keeps the list and reports the failure', () async {
        final catalog = _RefreshableCatalog(failFrom: 2);
        final cubit = LibraryCubit(catalogRepository: catalog);
        addTearDown(cubit.close);

        await cubit.loadLibrary({const LikedId.item('dm1')});
        final before = cubit.state.items;

        expect(await cubit.refresh(), isFalse);
        expect(cubit.state.status, LibraryStatus.success);
        expect(cubit.state.items, before);
      });
    });
  });
}
