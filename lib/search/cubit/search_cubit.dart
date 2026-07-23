import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'search_state.dart';

/// Drives the Search screen. Screen-local (created per visit by SearchPage).
///
/// The one new idea here is *debouncing*: the field calls [queryChanged] on
/// every keystroke, but we don't want to fire a repository search that often
/// (each is a real, latency-bearing call). So each keystroke cancels and
/// restarts a [Timer]; only when the user pauses for [_debounceDuration] does
/// the search actually run. Typing "radiohead" hits the repository once, not
/// nine times.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const SearchState());

  final CatalogRepository _catalogRepository;

  /// The pending debounce timer, if the user is mid-type. Cancelled and
  /// replaced on every keystroke, and cancelled on [close].
  Timer? _debounce;

  static const Duration _debounceDuration = Duration(milliseconds: 350);

  /// Called on every keystroke. Records the typed text immediately (so the
  /// field stays responsive) but restarts the debounce timer rather than
  /// searching right away.
  void queryChanged(String query) {
    _debounce?.cancel();

    if (query.trim().isEmpty) {
      // Blank query: abandon any pending search and fall back to the prompt.
      emit(state.copyWith(query: query, status: SearchStatus.initial, results: const []));
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
      // The user may have kept typing while this call was in flight; if the
      // query has since moved on, drop this now-stale response so a slow
      // earlier search can't clobber the results for what's now on screen.
      if (query != state.query.trim()) return;
      emit(state.copyWith(status: SearchStatus.success, results: results));
    } catch (_) {
      if (query != state.query.trim()) return;
      emit(state.copyWith(
        status: SearchStatus.failure,
        errorMessage: 'Search failed. Please try again.',
      ));
    }
  }

  @override
  Future<void> close() {
    _debounce?.cancel();
    return super.close();
  }
}
