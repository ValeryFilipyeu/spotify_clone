import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'home_state.dart';

/// Loads the home sections plus an id-keyed index the personal rows resolve
/// against. Screen-local, created per visit by HomePage.
///
/// Knows nothing about *whose* home this is: the view composes it with the
/// app-wide [PlayHistoryCubit], so the catalog reloads without re-reading history
/// and history stays live without reloading the catalog.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit({required this._catalogRepository}) : super(const HomeState());

  final CatalogRepository _catalogRepository;

  /// Ids already looked for, found or not. An id the catalog has dropped never
  /// lands in [HomeState.itemsById], so without this it is requested on every
  /// rebuild for ever.
  final Set<String> _attempted = {};

  /// Loads the rows, then fills in any of [recentIds] they did not cover.
  ///
  /// After the sections rather than alongside them: most recently-played items
  /// are Home's own rows, and asking first cannot tell which.
  Future<void> loadSections([Iterable<String> recentIds = const []]) async {
    emit(state.copyWith(status: HomeStatus.loading));
    try {
      final sections = await _catalogRepository.fetchHomeSections();
      if (isClosed) return;
      emit(
        state.copyWith(
          status: HomeStatus.success,
          sections: sections,
          // Home's rows are most of what anyone recently played, so indexing
          // them resolves most of the personal row with no second request.
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

  /// Reloads from the source, discarding anything cached.
  ///
  /// No loading state and no failure state: pull-to-refresh draws its own
  /// spinner, and a failed refresh should leave the good rows alone rather than
  /// replacing them with an error page. The view decides how to mention it.
  Future<bool> refresh([Iterable<String> recentIds = const []]) async {
    _catalogRepository.invalidate();
    try {
      final sections = await _catalogRepository.fetchHomeSections();
      if (isClosed) return false;
      emit(
        state.copyWith(
          status: HomeStatus.success,
          sections: sections,
          itemsById: {
            for (final section in sections)
              for (final item in section.items) item.id: item,
          },
        ),
      );
      // A refresh retries everything, including what quietly failed.
      _attempted.clear();
      await resolveMissing(recentIds);
      return true;
    } catch (_) {
      return false;
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
