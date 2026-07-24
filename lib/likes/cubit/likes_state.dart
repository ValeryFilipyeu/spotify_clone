import 'package:equatable/equatable.dart';

enum LikesStatus { loading, ready }

/// App-wide liked state. [likedIds] is the single source of truth every heart
/// reads from; [status] is only [LikesStatus.loading] until the persisted set
/// has been restored (so the Library tab can show a spinner rather than a
/// misleading "nothing liked yet").
class LikesState extends Equatable {
  const LikesState({
    this.status = LikesStatus.loading,
    this.likedIds = const {},
  });

  final LikesStatus status;
  final Set<String> likedIds;

  bool isLiked(String id) => likedIds.contains(id);

  LikesState copyWith({
    LikesStatus? status,
    Set<String>? likedIds,
  }) {
    return LikesState(
      status: status ?? this.status,
      likedIds: likedIds ?? this.likedIds,
    );
  }

  @override
  List<Object?> get props => [status, likedIds];
}
