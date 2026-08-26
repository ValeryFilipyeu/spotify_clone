import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/search_results.dart';
import '../../catalog/repository/catalog_repository.dart';
import '../../likes/models/liked_id.dart';
import 'library_state.dart';

/// Resolves liked entries into the items and tracks "Your Library" draws.
/// Screen-local; what is liked is passed in, so this knows nothing about
/// accounts or persistence.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({required this._catalogRepository}) : super(const LibraryState());

  final CatalogRepository _catalogRepository;

  /// What the current state was loaded for, so a likes change that alters
  /// nothing costs no round trip.
  Set<LikedId> _loadedFor = const {};

  /// Loads the catalog entries for [liked].
  ///
  /// Each lookup is asked only about ids of its own kind. Passing the whole set
  /// to both and keeping whatever each recognised holds only if an id cannot name
  /// both a playlist and a song -- and it can. See [LikedId].
  Future<void> loadLibrary([Set<LikedId> liked = const {}]) async {
    _loadedFor = liked;

    if (liked.isEmpty) {
      // Nothing liked: an empty library is a successful load, not a request.
      emit(const LibraryState(status: LibraryStatus.success));
      return;
    }

    emit(state.copyWith(status: LibraryStatus.loading));
    final resolved = await _resolve(liked);
    if (isClosed) return;

    emit(
      resolved == null
          ? state.copyWith(
              status: LibraryStatus.failure,
              errorMessage: 'Could not load your library. Please try again.',
            )
          : state.copyWith(
              status: LibraryStatus.success,
              items: resolved.items,
              tracks: resolved.tracks,
            ),
    );
  }

  /// Reloads the same set, discarding anything cached. No loading state and no
  /// failure state, as HomeCubit.refresh: a bad refresh leaves the list alone.
  Future<bool> refresh() async {
    _catalogRepository.invalidate();
    if (_loadedFor.isEmpty) return true; // nothing liked, nothing to fetch

    final resolved = await _resolve(_loadedFor);
    if (isClosed || resolved == null) return false;
    emit(
      state.copyWith(status: LibraryStatus.success, items: resolved.items, tracks: resolved.tracks),
    );
    return true;
  }

  /// Reloads only if [liked] differs from what is loaded. Liking something new
  /// has to fetch it; unliking is handled in the view.
  Future<void> syncWith(Set<LikedId> liked) async {
    if (_setEquals(liked, _loadedFor)) return;
    // A set that only shrank is already covered by what is loaded.
    if (liked.difference(_loadedFor).isEmpty) {
      _loadedFor = liked;
      return;
    }
    await loadLibrary(liked);
  }

  /// Both halves of the library, or null if none of it could be had.
  ///
  /// The lookups may disagree. Awaited together with `.wait` they cannot: offline
  /// with songs saved and no albums, the album lookup rethrows and takes the
  /// songs down with it. Half a library beats an error page over tracks that are
  /// sitting on the device.
  ///
  /// Null is kept for the case with genuinely nothing to show -- every lookup
  /// made failed -- so "nothing liked yet" is never drawn over a library that is
  /// merely unreachable.
  Future<({List<CatalogItem> items, List<TrackHit> tracks})?> _resolve(Set<LikedId> liked) async {
    final itemIds = _idsOf(liked, LikeKind.item);
    final trackIds = _idsOf(liked, LikeKind.track);

    final (items, tracks) = await (
      _ask(itemIds, _catalogRepository.fetchItemsByIds),
      _ask(trackIds, _catalogRepository.fetchTracksByIds),
    ).wait;

    // Only halves actually asked about count: a library of songs alone is not a
    // failed album lookup.
    final answers = [if (itemIds.isNotEmpty) items, if (trackIds.isNotEmpty) tracks];
    if (answers.every((answer) => answer == null)) return null;

    return (items: items ?? const [], tracks: tracks ?? const []);
  }

  /// [fetch] applied to [ids], or null if it failed. Never asks for nothing.
  ///
  /// try/catch, not `.then(onError:)`, which only sees a rejected *future*: an
  /// implementation that throws before returning one sails straight past it.
  ///
  /// Still concurrent -- an async body runs to its first await synchronously, so
  /// both fetches are in flight before either is awaited.
  Future<List<T>?> _ask<T>(Set<String> ids, Future<List<T>> Function(Set<String>) fetch) async {
    if (ids.isEmpty) return const [];
    try {
      return await fetch(ids);
    } on Object {
      return null;
    }
  }

  static Set<String> _idsOf(Set<LikedId> liked, LikeKind kind) => {
    for (final entry in liked)
      if (entry.kind == kind) entry.id,
  };

  static bool _setEquals(Set<LikedId> a, Set<LikedId> b) =>
      a.length == b.length && a.containsAll(b);
}
