import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/repository/catalog_repository.dart';
import 'search_state.dart';

/// Loads the full catalog once, then filters it client-side as the user types.
/// Screen-local (created per visit by SearchPage). Client-side filtering is a
/// fine fit for a small local catalog; a real backend would expose a search
/// endpoint on the repository instead.
class SearchCubit extends Cubit<SearchState> {
  SearchCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const SearchState());

  final CatalogRepository _catalogRepository;

  Future<void> loadCatalog() async {
    emit(state.copyWith(status: SearchStatus.loading));
    try {
      final items = await _catalogRepository.fetchAllItems();
      emit(state.copyWith(status: SearchStatus.success, allItems: items));
    } catch (_) {
      emit(state.copyWith(
        status: SearchStatus.failure,
        errorMessage: 'Could not load the catalog. Please try again.',
      ));
    }
  }

  /// Filters the loaded catalog (title or subtitle contains [query],
  /// case-insensitive). An empty query yields no results -- the view shows a
  /// prompt rather than the whole catalog.
  void queryChanged(String query) {
    final needle = query.trim().toLowerCase();
    final results = needle.isEmpty
        ? const <CatalogItem>[]
        : state.allItems
            .where((item) =>
                item.title.toLowerCase().contains(needle) ||
                item.subtitle.toLowerCase().contains(needle))
            .toList();
    emit(state.copyWith(query: query, results: results));
  }
}
