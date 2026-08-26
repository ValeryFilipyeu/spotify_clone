import 'dart:async';

import 'package:flutter_bloc/flutter_bloc.dart';

import '../../auth/models/app_user.dart';
import '../repository/play_history_repository.dart';
import 'play_history_state.dart';

/// The account's recently-played items, app-wide, so starting playback anywhere
/// reaches Home at once. Same shape as [LikesCubit], and per account for the
/// same reason.
///
/// Recorded from the places that *start* playback, because they are the only
/// ones that know which catalog item the queue came from -- PlayerBloc sees
/// only a list of tracks.
class PlayHistoryCubit extends Cubit<PlayHistoryState> {
  PlayHistoryCubit({required this._repository, required Stream<AppUser?> authStateChanges})
    : super(const PlayHistoryState()) {
    _authSub = authStateChanges.listen(_onUserChanged);
  }

  final PlayHistoryRepository _repository;
  late final StreamSubscription<AppUser?> _authSub;

  /// The account whose history is loaded, or null when signed out.
  String? _userId;

  Future<void> _onUserChanged(AppUser? user) async {
    if (user == null) {
      // Don't leave it on screen for whoever signs in next.
      _userId = null;
      emit(const PlayHistoryState());
      return;
    }

    final userId = user.email;
    if (userId == _userId) return; // already loaded

    _userId = userId;
    final ids = await _repository.fetchRecentIds(userId);
    // A fast account switch: those ids belong to somebody else now.
    if (_userId != userId) return;
    emit(PlayHistoryState(recentIds: ids));
  }

  /// Notes that playback started from [itemId], optimistically so Home reorders
  /// at once. A failed write reverts.
  Future<void> record(String itemId) async {
    final userId = _userId;
    if (userId == null) return; // nobody signed in -> nothing to attribute it to

    final previous = state.recentIds;
    // Replaying the same playlist twice should not cost a storage write.
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
