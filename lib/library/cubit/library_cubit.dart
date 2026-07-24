import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'library_state.dart';

/// Loads the full catalog (items and tracks) that the "Your Library" tab draws
/// its liked subset from. Screen-local (created per visit by LibraryPage); the
/// actual liked-vs-not filtering happens in the view against the app-wide
/// LikesCubit, so this cubit is only responsible for the catalog fetch.
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
      final tracks = await _catalogRepository.fetchAllTracks();
      emit(state.copyWith(status: LibraryStatus.success, allItems: items, allTracks: tracks));
    } catch (_) {
      emit(state.copyWith(
        status: LibraryStatus.failure,
        errorMessage: 'Could not load your library. Please try again.',
      ));
    }
  }
}
