import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/app_user.dart';
import '../../catalog/repository/catalog_repository.dart';
import '../models/liked_id.dart';
import '../repository/likes_repository.dart';
import 'likes_state.dart';

/// The liked set for the whole app, provided once above the tab shell so every
/// heart reads the same state.
///
/// Per-account: follows the auth stream, so switching users never shows the
/// previous one's library.
class LikesCubit extends Cubit<LikesState> {
  LikesCubit({
    required this._repository,
    required Stream<AppUser?> authStateChanges,
    this._catalogRepository,
  }) : super(const LikesState()) {
    _authSub = authStateChanges.listen(_onUserChanged);
  }

  final LikesRepository _repository;

  /// Only for keeping a new like reachable offline. Optional.
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

  /// Flips [likedId] for the signed-in user, optimistically -- a heart must feel
  /// instant -- and reverts if the write fails, so it never lies.
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
      // Only on the same account; a mid-flight switch already replaced the set.
      if (_userId == userId) emit(state.copyWith(likedIds: previous));
    }
  }

  /// Asks the catalog for the thing just liked, purely so the offline layer
  /// writes it down.
  ///
  /// Otherwise "your library works offline" is true only by luck: nothing puts a
  /// liked entry on disk except a Library load, so liking on Home and boarding a
  /// plane loses it. Liking is the last moment the network is known to be there.
  ///
  /// Almost always free -- the thing was on screen, so a layer down this is a
  /// memory-cache hit, which the offline layer still writes to disk.
  ///
  /// Failure is ignored: the like is saved either way.
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
