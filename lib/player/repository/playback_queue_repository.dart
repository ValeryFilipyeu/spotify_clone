import 'package:equatable/equatable.dart';

import '../../catalog/models/track.dart';

/// What was playing when the app was last closed.
///
/// Both orders are carried, because the player keeps both: [queue] is what plays
/// next and [sourceQueue] is the order it was in before shuffle rearranged it.
/// Storing the shuffle as a permutation of one list would be smaller and would be
/// wrong -- appending to the queue mid-session changes one list and not the
/// other, so after that they are related but not a permutation.
///
/// What is deliberately *not* here is repeat mode. The line is whether the field
/// is needed to make sense of the rest: [isShuffled] is, because without it a
/// restored queue in shuffled order would be presented as the natural one and the
/// shuffle button would lie. Repeat changes nothing about how this is read, so it
/// belongs with the other playback preferences if it is ever wanted.
class SavedQueue extends Equatable {
  const SavedQueue({
    required this.queue,
    this.sourceQueue,
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.isShuffled = false,
  });

  /// The playing order. Never empty -- an empty queue is not saved, it is
  /// cleared.
  final List<Track> queue;

  /// The order before shuffling, or null when it is the same list.
  ///
  /// Null rather than a copy so the common case -- no shuffle -- is not written
  /// to disk twice.
  final List<Track>? sourceQueue;

  /// Into [queue].
  final int currentIndex;

  final Duration position;
  final bool isShuffled;

  /// The unshuffled order, which is [queue] itself when nothing shuffled it.
  List<Track> get effectiveSourceQueue => sourceQueue ?? queue;

  @override
  List<Object?> get props => [queue, sourceQueue, currentIndex, position, isShuffled];
}

/// Where the player leaves its queue so that closing the app is not the same as
/// stopping.
///
/// Per account, like the other playback state: two people sharing a device do not
/// share a place in a playlist.
///
/// Reading is one call and writing is two, which is not an oversight. The
/// tracklist changes when someone starts something new or edits the queue -- rare,
/// and tens of kilobytes. The position changes four times a second. Writing them
/// together would mean rewriting the whole tracklist every few seconds for the
/// sake of a number, so [savePosition] exists to move only the number.
abstract class PlaybackQueueRepository {
  /// The saved session for [userId], or null if there is none.
  Future<SavedQueue?> fetchQueue(String userId);

  /// Replaces the saved tracklist. Does not touch the position -- callers that
  /// have changed both call [savePosition] as well.
  Future<void> saveQueue(String userId, SavedQueue queue);

  Future<void> savePosition(String userId, {required int currentIndex, required Duration position});

  /// Forgets the session entirely, for when playback is stopped rather than
  /// merely left.
  Future<void> clear(String userId);
}
