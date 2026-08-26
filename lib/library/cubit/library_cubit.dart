import 'package:flutter_bloc/flutter_bloc.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/search_results.dart';
import '../../catalog/repository/catalog_repository.dart';
import '../../likes/models/liked_id.dart';
import 'library_state.dart';

/// Resolves the entries the user has liked into the items and tracks the "Your
/// Library" tab draws. Screen-local (created per visit by LibraryPage).
///
/// What is liked is app-wide state ([LikesCubit]) and is passed in, so this
/// cubit stays a plain catalog-fetching cubit and knows nothing about accounts
/// or persistence.
class LibraryCubit extends Cubit<LibraryState> {
  LibraryCubit({required this._catalogRepository}) : super(const LibraryState());

  final CatalogRepository _catalogRepository;

  /// The set the current state was loaded for, so a likes change that does not
  /// actually alter it (a re-emit, or liking then unliking the same thing) does
  /// not trigger a round trip.
  Set<LikedId> _loadedFor = const {};

  /// Loads the catalog entries for [liked].
  ///
  /// Each lookup is asked only about ids of its own kind. It used to get the
  /// whole set on the theory that "each call returns the ids it recognises and
  /// ignores the rest, so between them they partition the set" -- which holds
  /// only if an id cannot name both a playlist and a song. Against the real
  /// catalog it can, and that theory put a song nobody liked in the library. See
  /// [LikedId].
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

  /// Reloads the same liked set from the source, discarding anything cached.
  ///
  /// Like HomeCubit.refresh: no loading state, because the pull-to-refresh draws
  /// its own, and a failure is reported back rather than emitted, so a bad
  /// refresh leaves the working list alone.
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

  /// Reloads only if [liked] differs from what is already loaded. Driven by the
  /// view as the liked set changes -- liking something new has to fetch it,
  /// while unliking is handled in the view without a round trip.
  Future<void> syncWith(Set<LikedId> liked) async {
    if (_setEquals(liked, _loadedFor)) return;
    // Only a *new* entry needs fetching. If the set has merely shrunk, the view
    // already filters the removed one out and the data on hand still covers it.
    if (liked.difference(_loadedFor).isEmpty) {
      _loadedFor = liked;
      return;
    }
    await loadLibrary(liked);
  }

  /// Both halves of the library, or null if none of it could be had.
  ///
  /// The two lookups are allowed to disagree. They used to be awaited together
  /// with `.wait`, which fails the pair if either throws -- so a user offline
  /// with songs saved and no albums saved got an error page over tracks that
  /// were sitting on the device: the album lookup had nothing to recall, so it
  /// rethrew, and took the half that worked down with it. Half a library beats
  /// none, and the offline banner already explains why it is half.
  ///
  /// Null is kept for the case that genuinely has nothing to show: every lookup
  /// that was made failed. Returning empty lists there would draw "nothing liked
  /// yet" over a library that is merely unreachable.
  Future<({List<CatalogItem> items, List<TrackHit> tracks})?> _resolve(Set<LikedId> liked) async {
    final itemIds = _idsOf(liked, LikeKind.item);
    final trackIds = _idsOf(liked, LikeKind.track);

    final (items, tracks) = await (
      _ask(itemIds, _catalogRepository.fetchItemsByIds),
      _ask(trackIds, _catalogRepository.fetchTracksByIds),
    ).wait;

    // Only the halves actually asked about count towards the verdict: a library
    // of songs alone is not a failed album lookup, it is a library of songs.
    final answers = [if (itemIds.isNotEmpty) items, if (trackIds.isNotEmpty) tracks];
    if (answers.every((answer) => answer == null)) return null;

    return (items: items ?? const [], tracks: tracks ?? const []);
  }

  /// [fetch] applied to [ids], or null if it failed. Never asks for nothing.
  ///
  /// try/catch rather than `.then(onError:)`, which only sees a *rejected
  /// future*: a repository that throws before returning one -- as a fake with a
  /// plain `if (down) throw` does, and as any non-async implementation may --
  /// would sail straight past it and out of [_resolve].
  ///
  /// Still runs both lookups at once. An async body executes up to its first
  /// await synchronously, so [fetch] is called before this returns, and the
  /// caller has both in flight before it awaits either.
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
