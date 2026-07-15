import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'home_state.dart';

/// Loads the home screen's catalog sections. Screen-local (created per visit
/// by HomePage), delegating the actual fetch to the injected repository -- it
/// knows nothing about where the data comes from, only how to reflect the
/// load's status.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const HomeState());

  final CatalogRepository _catalogRepository;

  Future<void> loadSections() async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      final sections = await _catalogRepository.fetchHomeSections();
      emit(state.copyWith(status: HomeStatus.success, sections: sections));
    } catch (_) {
      emit(state.copyWith(status: HomeStatus.failure, errorMessage: 'Could not load your music. Please try again.'));
    }
  }
}
