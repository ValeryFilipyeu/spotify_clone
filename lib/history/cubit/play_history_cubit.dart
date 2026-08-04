import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/app_user.dart';
import '../repository/play_history_repository.dart';
import 'play_history_state.dart';

/// Holds the signed-in account's recently-played items for the whole app, so
/// starting playback anywhere is reflected on Home immediately -- the same
/// app-wide-cubit-following-the-auth-stream shape as [LikesCubit], and per
/// account for the same reason: one user's history must never show up under
/// another's.
///
/// Recording is driven from the places that *start* playback (a tracklist row, a
/// song in search results), because those are the only places that know which
/// catalog item the queue came from. PlayerBloc only ever sees a list of tracks.
class PlayHistoryCubit extends Cubit<PlayHistoryState> {
  PlayHistoryCubit({
    required PlayHistoryRepository repository,
    required Stream<AppUser?> authStateChanges,
  })  : _repository = repository, // ignore: prefer_initializing_formals -- keeps the public param name.
        super(const PlayHistoryState()) {
    _authSub = authStateChanges.listen(_onUserChanged);
  }

  final PlayHistoryRepository _repository;
  late final StreamSubscription<AppUser?> _authSub;

  /// The account whose history is loaded, or null when signed out.
  String? _userId;

  Future<void> _onUserChanged(AppUser? user) async {
    if (user == null) {
      // Signed out: forget the previous account's history rather than leaving it
      // on screen for whoever signs in next.
      _userId = null;
      emit(const PlayHistoryState());
      return;
    }

    final userId = user.email;
    if (userId == _userId) return; // already loaded

    _userId = userId;
    final ids = await _repository.fetchRecentIds(userId);
    // A fast account switch while the load was in flight: those ids belong to
    // somebody else now.
    if (_userId != userId) return;
    emit(PlayHistoryState(recentIds: ids));
  }

  /// Notes that playback started from [itemId]. Updates state optimistically so
  /// Home reorders at once, then persists; a failed write reverts, so the row
  /// never claims something was saved that was not.
  Future<void> record(String itemId) async {
    final userId = _userId;
    if (userId == null) return; // nobody signed in -> nothing to attribute it to

    final previous = state.recentIds;
    // Already at the front, so moving it there would rewrite the same list --
    // replaying a playlist twice in a row should not cost a storage write.
    if (previous.isNotEmpty && previous.first == itemId) return;
    emit(PlayHistoryState(recentIds: withMostRecent(previous, itemId)));

    try {
      await _repository.record(userId, itemId);
    } catch (_) {
      if (_userId == userId) emit(PlayHistoryState(recentIds: previous));
    }
  }

  @override
  Future<void> close() {
    _authSub.cancel();
    return super.close();
  }
}
