import 'package:equatable/equatable.dart';

import '../../catalog/models/track.dart';

/// What was playing when the app was last closed.
///
/// Both orders are carried. Storing the shuffle as a permutation of one list
/// would be smaller and wrong: appending mid-session changes one list and not the
/// other, so afterwards they are related but not a permutation.
///
/// No repeat mode, deliberately. [isShuffled] is here because without it a
/// restored shuffled queue would be presented as the natural order and the
/// shuffle button would lie; repeat changes nothing about how this is read.
class SavedQueue extends Equatable {
  const SavedQueue({
    required this.queue,
    this.sourceQueue,
    this.currentIndex = 0,
    this.position = Duration.zero,
    this.isShuffled = false,
  });

  /// Never empty: an empty queue is cleared, not saved.
  final List<Track> queue;

  /// The order before shuffling, or null when it is the same list -- so the
  /// common case is not written to disk twice.
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

/// Where the player leaves its queue, so closing the app is not the same as
/// stopping. Per account, like the rest of the playback state.
///
/// One read, two writes, deliberately: the tracklist is tens of kilobytes and
/// changes rarely, the position changes four times a second. [savePosition]
/// exists so a number does not rewrite a tracklist.
abstract class PlaybackQueueRepository {
  /// The saved session for [userId], or null if there is none.
  Future<SavedQueue?> fetchQueue(String userId);

  /// Replaces the tracklist only; callers that changed both also call
  /// [savePosition].
  Future<void> saveQueue(String userId, SavedQueue queue);

  Future<void> savePosition(String userId, {required int currentIndex, required Duration position});

  /// For playback stopped, as opposed to merely left.
  Future<void> clear(String userId);
}
