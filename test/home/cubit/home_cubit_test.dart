import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/home/cubit/home_cubit.dart';
import 'package:spotify_clone/home/cubit/home_state.dart';

/// A repository that always throws, to exercise the failure branch without a
/// mocking package -- same "small deterministic stub as its own test double"
/// approach used for the auth tests.
class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    throw Exception('network down');
  }

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async {
    throw Exception('network down');
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) async {
    throw Exception('network down');
  }

  @override
  Future<SearchResults> search(String query) async {
    throw Exception('network down');
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) async {
    throw Exception('network down');
  }
}

/// Serves sections, but cannot look an id up. Home's catalog rows do not depend
/// on that lookup -- only the "Recently played" row does -- so the screen must
/// survive it failing.
class _NoItemLookupRepository extends FakeCatalogRepository {
  const _NoItemLookupRepository();

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async =>
      throw Exception('network down');
}

/// Counts id lookups, to prove an unresolvable id is not asked for repeatedly.
class _CountingLookupRepository extends FakeCatalogRepository {
  const _CountingLookupRepository();

  static int lookups = 0;

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async {
    lookups++;
    return const [];
  }
}

void main() {
  group('HomeCubit', () {
    setUp(() => _CountingLookupRepository.lookups = 0);
    test('initial state is HomeStatus.initial with no sections', () {
      final cubit = HomeCubit(catalogRepository: const FakeCatalogRepository());
      expect(cubit.state, const HomeState());
      cubit.close();
    });

    blocTest<HomeCubit, HomeState>(
      'emits [loading, success] with sections on a successful load',
      build: () => HomeCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) => cubit.loadSections(),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        isA<HomeState>()
            .having((state) => state.status, 'status', HomeStatus.success)
            .having((state) => state.sections, 'sections', isNotEmpty),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'indexes the items its own rows contain, for the personal rows to resolve against',
      build: () => HomeCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) => cubit.loadSections(),
      verify: (cubit) async {
        final sections = await const FakeCatalogRepository().fetchHomeSections();
        final expected = {
          for (final section in sections)
            for (final item in section.items) item.id: item,
        };

        expect(cubit.state.itemsById, expected);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'resolves a recently-played id that none of its rows contain',
      build: () => HomeCubit(catalogRepository: const FakeCatalogRepository()),
      // 'ab4' is a real catalog item that no home section lists.
      act: (cubit) => cubit.loadSections(const ['ab4']),
      verify: (cubit) {
        expect(cubit.state.itemsById.containsKey('ab4'), isTrue);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'asks only once for an id the catalog does not have',
      // Otherwise every rebuild of the view that wants it starts another
      // request: it never lands in the index, so it stays "missing" for ever.
      build: () => HomeCubit(catalogRepository: const _CountingLookupRepository()),
      act: (cubit) async {
        await cubit.loadSections();
        await cubit.resolveMissing(const ['ghost']);
        await cubit.resolveMissing(const ['ghost']);
        await cubit.resolveMissing(const ['ghost']);
      },
      verify: (cubit) {
        expect(_CountingLookupRepository.lookups, 1);
      },
    );

    blocTest<HomeCubit, HomeState>(
      'keeps the screen when a recently-played id cannot be resolved',
      // Home is already on screen with its catalog rows. Losing the personal
      // row is not worth replacing all of that with an error page.
      build: () => HomeCubit(catalogRepository: const _NoItemLookupRepository()),
      act: (cubit) => cubit.loadSections(const ['ab4']),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        isA<HomeState>().having((state) => state.status, 'status', HomeStatus.success),
      ],
    );

    blocTest<HomeCubit, HomeState>(
      'emits [loading, failure] with an error message when the repository throws',
      build: () => HomeCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.loadSections(),
      expect: () => [
        const HomeState(status: HomeStatus.loading),
        isA<HomeState>()
            .having((state) => state.status, 'status', HomeStatus.failure)
            .having((state) => state.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
