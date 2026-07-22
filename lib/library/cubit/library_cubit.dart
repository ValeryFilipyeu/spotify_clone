import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'library_state.dart';

/// Loads every catalog item for the "Your Library" tab. Screen-local (created
/// per visit by LibraryPage); the fetch is delegated to the repository.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({required CatalogRepository catalogRepository})
      // ignore: prefer_initializing_formals -- keeps the public param name.
      : _catalogRepository = catalogRepository,
        super(const LibraryState());

  final CatalogRepository _catalogRepository;

  Future<void> loadLibrary() async {
    emit(state.copyWith(status: LibraryStatus.loading));
    try {
      final items = await _catalogRepository.fetchAllItems();
      emit(state.copyWith(status: LibraryStatus.success, items: items));
    } catch (_) {
      emit(state.copyWith(
        status: LibraryStatus.failure,
        errorMessage: 'Could not load your library. Please try again.',
      ));
    }
  }
}
