import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/library/cubit/library_cubit.dart';
import 'package:spotify_clone/library/cubit/library_state.dart';

class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  Future<List<CatalogItem>> fetchAllItems() async => throw Exception('down');

  @override
  Future<SearchResults> search(String query) => throw UnimplementedError();

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

void main() {
  group('LibraryCubit', () {
    test('initial state is LibraryStatus.initial with no items', () {
      final cubit = LibraryCubit(catalogRepository: const FakeCatalogRepository());
      expect(cubit.state, const LibraryState());
      cubit.close();
    });

    blocTest<LibraryCubit, LibraryState>(
      'emits [loading, success] with items from the real fake catalog',
      build: () => LibraryCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) => cubit.loadLibrary(),
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.success)
            .having((s) => s.items, 'items', isNotEmpty),
      ],
    );

    blocTest<LibraryCubit, LibraryState>(
      'emits [loading, failure] with a message when the repository throws',
      build: () => LibraryCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.loadLibrary(),
      expect: () => [
        const LibraryState(status: LibraryStatus.loading),
        isA<LibraryState>()
            .having((s) => s.status, 'status', LibraryStatus.failure)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
