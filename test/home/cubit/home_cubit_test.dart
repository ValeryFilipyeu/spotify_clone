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
  Future<List<CatalogItem>> fetchAllItems() async {
    throw Exception('network down');
  }

  @override
  Future<List<TrackHit>> fetchAllTracks() async {
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

void main() {
  group('HomeCubit', () {
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
