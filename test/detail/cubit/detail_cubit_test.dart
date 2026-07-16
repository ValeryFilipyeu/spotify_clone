import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/detail/cubit/detail_cubit.dart';
import 'package:spotify_clone/detail/cubit/detail_state.dart';

void main() {
  group('DetailCubit', () {
    test('initial state is DetailStatus.initial with no detail', () {
      final cubit = DetailCubit(catalogRepository: const FakeCatalogRepository());
      expect(cubit.state, const DetailState());
      cubit.close();
    });

    blocTest<DetailCubit, DetailState>(
      'emits [loading, success] with the detail for a known id',
      build: () => DetailCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) => cubit.loadDetail('ab2'),
      expect: () => [
        const DetailState(status: DetailStatus.loading),
        isA<DetailState>()
            .having((state) => state.status, 'status', DetailStatus.success)
            .having((state) => state.detail?.item.id, 'item id', 'ab2')
            .having((state) => state.detail?.tracks, 'tracks', isNotEmpty),
      ],
    );

    blocTest<DetailCubit, DetailState>(
      'emits [loading, failure] for an unknown id',
      build: () => DetailCubit(catalogRepository: const FakeCatalogRepository()),
      act: (cubit) => cubit.loadDetail('nope'),
      expect: () => [
        const DetailState(status: DetailStatus.loading),
        isA<DetailState>()
            .having((state) => state.status, 'status', DetailStatus.failure)
            .having((state) => state.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
