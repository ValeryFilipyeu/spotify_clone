import 'package:equatable/equatable.dart';

/// The signed-in account's recently-played item ids, most recent first.
///
/// No status enum here, unlike [LikesState]: the only thing that reads this is
/// Home's "Recently played" row, which is absent when the list is empty. An
/// empty state during the initial load therefore renders as "no row yet", which
/// is exactly right -- there is nothing a loading flag could improve.
class PlayHistoryState extends Equatable {
  const PlayHistoryState({this.recentIds = const []});

  final List<String> recentIds;

  @override
  List<Object?> get props => [recentIds];
}
