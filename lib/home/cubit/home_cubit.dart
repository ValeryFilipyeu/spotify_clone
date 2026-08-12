import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'home_state.dart';

/// Loads the home screen's catalog sections, plus an id-keyed index the personal
/// rows resolve against. Screen-local (created per visit by HomePage),
/// delegating the actual fetch to the injected repository -- it knows nothing
/// about where the data comes from, only how to reflect the load's status.
///
/// It deliberately knows nothing about *whose* home this is. Personalisation is
/// composed in the view from the app-wide [PlayHistoryCubit], the way LibraryView
/// composes its catalog with LikesCubit -- which keeps this cubit reloadable
/// without re-reading history, and history live without reloading the catalog.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({required this._catalogRepository}) : super(const HomeState());

  final CatalogRepository _catalogRepository;

  /// Ids [resolveMissing] has already gone looking for, whether or not it found
  /// anything. Without this, an id the catalog no longer has would be requested
  /// again on every rebuild of the view that asks for it -- it never lands in
  /// [HomeState.itemsById], so "is it missing?" stays true for ever.
  final Set<String> _attempted = {};

  /// Loads the catalog rows, then fills in any of [recentIds] they did not
  /// already cover.
  ///
  /// The ids are passed in rather than fetched here because this cubit does not
  /// know whose home it is -- and they are handled *after* the sections rather
  /// than alongside them, since most recently-played items are Home's own rows,
  /// and asking for them before the sections arrive cannot tell which.
  Future<void> loadSections([Iterable<String> recentIds = const []]) async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      final sections = await _catalogRepository.fetchHomeSections();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.success,
          sections: sections,
          // Indexed straight off the sections. Home's rows are the overwhelming
          // majority of what a user has recently played, so this alone resolves
          // most of the personal row without a second request.
          itemsById: {
            for (final section in sections)
              for (final item in section.items) item.id: item,
          },
        ),
      );
      await resolveMissing(recentIds);
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.failure,
          errorMessage: 'Could not load your music. Please try again.',
        ),
      );
    }
  }

  /// Fetches whichever of [ids] the index does not already hold, and merges them
  /// in. Driven by the view when the play history arrives or changes.
  ///
  /// Previously the whole catalog was downloaded up front so that any id could
  /// be resolved. That is not something a real backend can offer, and it was
  /// never what the screen needed: what it wants is a handful of specific ids.
  ///
  /// A failure here is swallowed on purpose. Home is already on screen with its
  /// catalog rows; losing the "Recently played" row is not worth replacing all
  /// of that with an error, and the next history change tries again.
  Future<void> resolveMissing(Iterable<String> ids) async {
    final missing = {
      for (final id in ids)
        if (!state.itemsById.containsKey(id) && !_attempted.contains(id)) id,
    };
    if (missing.isEmpty) return;
    _attempted.addAll(missing);

    try {
      final items = await _catalogRepository.fetchItemsByIds(missing);
      if (isClosed || items.isEmpty) return;
      emit(
        state.copyWith(itemsById: {...state.itemsById, for (final item in items) item.id: item}),
      );
    } catch (_) {
      // Retried on the next history change: drop these from the attempted set
      // so a transient failure is not permanent.
      _attempted.removeAll(missing);
    }
  }
}
