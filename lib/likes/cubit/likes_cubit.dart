import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/app_user.dart';
import '../../catalog/repository/catalog_repository.dart';
import '../models/liked_id.dart';
import '../repository/likes_repository.dart';
import 'likes_state.dart';

/// Holds the liked set for the whole app (provided once at the root, above
/// the tab shell) so a heart tapped on any screen is reflected everywhere --
/// the detail tracklist, the home cards, the Now Playing screen and the Library
/// tab all read the same state.
///
/// Likes are per-account: the cubit follows the auth stream, loading the
/// signed-in user's set on login and clearing it on logout, so switching
/// accounts never shows the previous user's library.
class LikesCubit extends Cubit<LikesState> {
  // Callers still pass `repository:`: Dart derives the public argument name from
  // the private field, which is what the `// ignore: prefer_initializing_formals`
  // that used to sit here was working around.
  LikesCubit({
    required this._repository,
    required Stream<AppUser?> authStateChanges,
    this._catalogRepository,
  }) : super(const LikesState()) {
    _authSub = authStateChanges.listen(_onUserChanged);
  }

  final LikesRepository _repository;

  /// Used for one thing only: making sure a newly liked thing can still be shown
  /// when there is no network. Optional, and nothing here fails without it.
  final CatalogRepository? _catalogRepository;

  late final StreamSubscription<AppUser?> _authSub;

  /// The account whose likes are currently loaded, or null when signed out.
  String? _userId;

  bool isLiked(LikedId likedId) => state.isLiked(likedId);

  Future<void> _onUserChanged(AppUser? user) async {
    if (user == null) {
      // Signed out: forget the previous account's likes entirely.
      _userId = null;
      emit(const LikesState(status: LikesStatus.ready));
      return;
    }

    final userId = user.email;
    if (userId == _userId && state.status == LikesStatus.ready) return; // already loaded

    _userId = userId;
    emit(const LikesState(status: LikesStatus.loading));
    final ids = await _repository.fetchLikedIds(userId);
    // Guard against a fast account switch while the load was in flight.
    if (_userId != userId) return;
    emit(LikesState(status: LikesStatus.ready, likedIds: ids));
  }

  /// Flips [likedId]'s state for the signed-in user. Updates the UI
  /// optimistically (a heart must feel instant), then persists; if persistence
  /// throws, reverts to the previous set so the heart never lies about what's
  /// saved.
  Future<void> toggle(LikedId likedId) async {
    final userId = _userId;
    if (userId == null) return; // no signed-in user -> nothing to like

    final previous = state.likedIds;
    final willLike = !previous.contains(likedId);
    final next = {...previous};
    if (willLike) {
      next.add(likedId);
    } else {
      next.remove(likedId);
    }
    emit(state.copyWith(likedIds: next));

    try {
      if (willLike) {
        await _repository.like(userId, likedId);
        unawaited(_keepForOffline(likedId));
      } else {
        await _repository.unlike(userId, likedId);
      }
    } catch (_) {
      // Only revert if we're still on the same account (a mid-flight logout/
      // switch would already have replaced the set).
      if (_userId == userId) emit(state.copyWith(likedIds: previous));
    }
  }

  /// Asks the catalog for the thing just liked, purely so the offline layer
  /// writes it down.
  ///
  /// Without this, "your library works offline" is true only by luck. Nothing
  /// puts a liked entry on disk except a successful Library load, so liking an
  /// album on Home and boarding a plane leaves it missing from the one screen
  /// that promised to have it -- and the app has no way to fetch it by then.
  /// Liking is the last moment the network is known to have been there a second
  /// ago, so it is the moment to spend a request.
  ///
  /// Almost always free: the thing was on screen when its heart was pressed, so
  /// the answer is still in the memory cache a layer down. That is not a
  /// wasted round trip but the point -- the offline layer writes memory-cache
  /// hits to disk too, because from out there a hit and a fetch look the same.
  ///
  /// Failure is ignored on purpose. The like itself is already saved; all that
  /// is lost is being able to see it without a network, and the next Library
  /// visit fixes that.
  Future<void> _keepForOffline(LikedId likedId) async {
    final catalog = _catalogRepository;
    if (catalog == null) return;
    try {
      switch (likedId.kind) {
        case LikeKind.item:
          await catalog.fetchItemsByIds({likedId.id});
        case LikeKind.track:
          await catalog.fetchTracksByIds({likedId.id});
      }
    } on Object {
      // Best effort by construction -- see above.
    }
  }

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }
}
