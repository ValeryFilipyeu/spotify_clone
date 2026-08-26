import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/search_results.dart';
import '../../catalog/repository/catalog_repository.dart';
import 'search_state.dart';

/// Drives the Search screen. Screen-local, created per visit.
///
/// Debounced: each keystroke restarts a timer, and only a pause runs the search,
/// so "radiohead" is one repository call rather than nine.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({required CatalogRepository catalogRepository})
    // ignore: prefer_initializing_formals -- keeps the public param name.
    : _catalogRepository = catalogRepository,
      super(const SearchState());

  final CatalogRepository _catalogRepository;

  /// Replaced on every keystroke, cancelled on [close].
  Timer? _debounce;

  static const Duration _debounceDuration = Duration(milliseconds: 350);

  /// Records the text immediately so the field stays responsive, and restarts
  /// the debounce rather than searching.
  void queryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      // Blank query: abandon any pending search and fall back to the prompt.
      emit(
        state.copyWith(query: query, status: SearchStatus.initial, results: const SearchResults()),
      );
      return;
    }

    emit(state.copyWith(query: query));
    _debounce = Timer(_debounceDuration, () => _runSearch(query.trim()));
  }

  /// Re-runs the current query, e.g. from the error screen's Retry button.
  void retry() {
    final query = state.query.trim();
    if (query.isNotEmpty) _runSearch(query);
  }

  Future<void> _runSearch(String query) async {
    emit(state.copyWith(status: SearchStatus.loading));
    try {
      final results = await _catalogRepository.search(query);
      // Dropped if the query moved on while this was in flight, so a slow
      // earlier search cannot clobber what is on screen.
      if (query != state.query.trim()) return;
      emit(state.copyWith(status: SearchStatus.success, results: results));
    } catch (_) {
      if (query != state.query.trim()) return;
      emit(
        state.copyWith(
          status: SearchStatus.failure,
          errorMessage: 'Search failed. Please try again.',
        ),
      );
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
