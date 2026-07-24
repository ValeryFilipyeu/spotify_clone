import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/app_user.dart';
import '../repository/likes_repository.dart';
import 'likes_state.dart';

/// Holds the liked-id set for the whole app (provided once at the root, above
/// the tab shell) so a heart tapped on any screen is reflected everywhere --
/// the detail tracklist, the home cards, the Now Playing screen and the Library
/// tab all read the same state.
///
/// Likes are per-account: the cubit follows the auth stream, loading the
/// signed-in user's set on login and clearing it on logout, so switching
/// accounts never shows the previous user's library.
class LikesCubit extends Cubit<LikesState> {
  LikesCubit({
    required LikesRepository repository,
    required Stream<AppUser?> authStateChanges,
  })  : _repository = repository, // ignore: prefer_initializing_formals -- keeps the public param name.
        super(const LikesState()) {
    _authSub = authStateChanges.listen(_onUserChanged);
  }

  final LikesRepository _repository;
  late final StreamSubscription<AppUser?> _authSub;

  /// The account whose likes are currently loaded, or null when signed out.
  String? _userId;

  bool isLiked(String id) => state.isLiked(id);

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

  /// Flips [id]'s liked state for the signed-in user. Updates the UI
  /// optimistically (a heart must feel instant), then persists; if persistence
  /// throws, reverts to the previous set so the heart never lies about what's
  /// saved.
  Future<void> toggle(String id) async {
    final userId = _userId;
    if (userId == null) return; // no signed-in user -> nothing to like

    final previous = state.likedIds;
    final willLike = !previous.contains(id);
    final next = {...previous};
    if (willLike) {
      next.add(id);
    } else {
      next.remove(id);
    }
    emit(state.copyWith(likedIds: next));

    try {
      if (willLike) {
        await _repository.like(userId, id);
      } else {
        await _repository.unlike(userId, id);
      }
    } catch (_) {
      // Only revert if we're still on the same account (a mid-flight logout/
      // switch would already have replaced the set).
      if (_userId == userId) emit(state.copyWith(likedIds: previous));
    }
  }

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }
}
