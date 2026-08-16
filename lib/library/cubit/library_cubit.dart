import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/repository/catalog_repository.dart';
import 'library_state.dart';

/// Resolves the ids the user has liked into the items and tracks the "Your
/// Library" tab draws. Screen-local (created per visit by LibraryPage).
///
/// Which ids are liked is app-wide state ([LikesCubit]) and is passed in, so
/// this cubit stays a plain catalog-fetching cubit and knows nothing about
/// accounts or persistence.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({required this._catalogRepository}) : super(const LibraryState());

  final CatalogRepository _catalogRepository;

  /// The set the current state was loaded for, so a likes change that does not
  /// actually alter the set (a re-emit, or liking then unliking the same thing)
  /// does not trigger a round trip.
  Set<String> _loadedFor = const {};

  /// Loads the catalog entries for [likedIds].
  ///
  /// The same set goes to both calls because likes are not typed: a liked id may
  /// name a playlist or a song, and only the catalog knows which. Each call
  /// returns the ids it recognises and ignores the rest, so between them they
  /// partition the set without the app having to track what kind of thing it
  /// liked.
  Future<void> loadLibrary([Iterable<String> likedIds = const []]) async {
    final wanted = likedIds.toSet();
    _loadedFor = wanted;

    if (wanted.isEmpty) {
      // Nothing liked: an empty library is a successful load, not a request.
      emit(const LibraryState(status: LibraryStatus.success));
      return;
    }

    emit(state.copyWith(status: LibraryStatus.loading));
    try {
      final (items, tracks) = await (
        _catalogRepository.fetchItemsByIds(wanted),
        _catalogRepository.fetchTracksByIds(wanted),
      ).wait;
      if (isClosed) return;
      emit(state.copyWith(status: LibraryStatus.success, items: items, tracks: tracks));
    } catch (_) {
      if (isClosed) return;
      emit(
        state.copyWith(
          status: LibraryStatus.failure,
          errorMessage: 'Could not load your library. Please try again.',
        ),
      );
    }
  }

  /// Reloads the same liked set from the source, discarding anything cached.
  ///
  /// Like HomeCubit.refresh: no loading state, because the pull-to-refresh draws
  /// its own, and a failure is reported back rather than emitted, so a bad
  /// refresh leaves the working list alone.
  Future<bool> refresh() async {
    _catalogRepository.invalidate();
    if (_loadedFor.isEmpty) return true; // nothing liked, nothing to fetch

    try {
      final (items, tracks) = await (
        _catalogRepository.fetchItemsByIds(_loadedFor),
        _catalogRepository.fetchTracksByIds(_loadedFor),
      ).wait;
      if (isClosed) return false;
      emit(state.copyWith(status: LibraryStatus.success, items: items, tracks: tracks));
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Reloads only if [likedIds] differs from what is already loaded. Driven by
  /// the view as the liked set changes -- liking something new has to fetch it,
  /// while unliking is handled in the view without a round trip.
  Future<void> syncWith(Iterable<String> likedIds) async {
    final wanted = likedIds.toSet();
    if (_setEquals(wanted, _loadedFor)) return;
    // Only a *new* id needs fetching. If the set has merely shrunk, the view
    // already filters the removed one out and the data on hand still covers it.
    if (wanted.difference(_loadedFor).isEmpty) {
      _loadedFor = wanted;
      return;
    }
    await loadLibrary(wanted);
  }

  static bool _setEquals(Set<String> a, Set<String> b) => a.length == b.length && a.containsAll(b);
}
