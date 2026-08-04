import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'home_state.dart';

/// Loads the home screen's catalog sections, plus an id-keyed index of every
/// item for the personal rows to resolve against. Screen-local (created per
/// visit by HomePage), delegating the actual fetch to the injected repository --
/// it knows nothing about where the data comes from, only how to reflect the
/// load's status.
///
/// It deliberately knows nothing about *whose* home this is. Personalisation is
/// composed in the view from the app-wide [PlayHistoryCubit], the way LibraryView
/// composes its catalog with LikesCubit -- which keeps this cubit reloadable
/// without re-reading history, and history live without reloading the catalog.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const HomeState());

  final CatalogRepository _catalogRepository;

  Future<void> loadSections() async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      // Concurrent, not sequential: the item index only exists to resolve the
      // personal rows' ids, and awaiting it after the sections would add its
      // latency to a screen the user is already staring at a spinner on.
      final (sections, items) = await (
        _catalogRepository.fetchHomeSections(),
        _catalogRepository.fetchAllItems(),
      ).wait;
      emit(state.copyWith(
        status: HomeStatus.success,
        sections: sections,
        itemsById: {for (final item in items) item.id: item},
      ));
    } catch (_) {
      emit(state.copyWith(status: HomeStatus.failure, errorMessage: 'Could not load your music. Please try again.'));
    }
  }
}
