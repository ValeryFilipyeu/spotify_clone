import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_failure.dart';
import '../../catalog/repository/catalog_repository.dart';
import 'detail_state.dart';

/// Loads one album/playlist by id. Screen-local (created per visit by
/// DetailPage), delegating the fetch to the injected repository.
class DetailCubit extends Cubit<DetailState> {
  DetailCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const DetailState());

  final CatalogRepository _catalogRepository;

  Future<void> loadDetail(String itemId) async {
    emit(state.copyWith(status: DetailStatus.loading));
    try {
      final detail = await _catalogRepository.fetchDetail(itemId);
      emit(state.copyWith(status: DetailStatus.success, detail: detail));
    } on CatalogItemNotFound {
      emit(state.copyWith(status: DetailStatus.failure, errorMessage: "We couldn't find that album."));
    } catch (_) {
      emit(state.copyWith(status: DetailStatus.failure, errorMessage: 'Could not load this album. Please try again.'));
    }
  }
}
