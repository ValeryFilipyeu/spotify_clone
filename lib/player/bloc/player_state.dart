import 'package:equatable/equatable.dart';

import '../../catalog/models/track.dart';

/// What happens when the current track reaches its end.
enum PlayerRepeatMode {
  /// Stop once the last track in the queue finishes.
  off,

  /// Wrap back to the first track after the last one.
  all,

  /// Replay the current track indefinitely.
  one,
}

/// A single evolving state class (same choice as AuthState/HomeState). The
/// queue + index model which track is current and enable next/previous.
class PlayerState extends Equatable {
  const PlayerState({
    this.queue = const [],
    this.sourceQueue = const [],
    this.currentIndex = 0,
    this.isPlaying = false,
    this.isLoading = false,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.isShuffled = false,
    this.repeatMode = PlayerRepeatMode.off,
    this.volume = 1,
    this.crossfadeDuration = Duration.zero,
  });

  /// The longest crossfade the settings UI offers.
  static const Duration maxCrossfadeDuration = Duration(seconds: 12);

  /// The queue in PLAY order -- what "Up next" lists and what [currentIndex]
  /// points into. Shuffling, drag-reordering and queue edits all rewrite it.
  final List<Track> queue;

  /// The queue in the order it was originally started from (an album's
  /// tracklist, say). Kept untouched so turning shuffle back off can restore
  /// that order; see PlayerBloc's restore logic for how queue additions, which
  /// this list never saw, are folded back in.
  final List<Track> sourceQueue;

  final int currentIndex;
  final bool isPlaying;
  final bool isLoading;
  final Duration position;
  final Duration duration;

  /// Whether the queue is currently in shuffled order.
  final bool isShuffled;

  final PlayerRepeatMode repeatMode;

  /// Output volume, 0.0..1.0.
  final double volume;

  /// How long the outgoing and incoming tracks overlap on a track change.
  /// [Duration.zero] (the default, as in Spotify) means no crossfade.
  final Duration crossfadeDuration;

  bool get isCrossfadeEnabled => crossfadeDuration > Duration.zero;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  bool get hasTrack => currentTrack != null;

  /// True when [PlayerNextRequested] would go somewhere -- either a later track
  /// exists, or [PlayerRepeatMode.all] lets us wrap around to the front.
  bool get hasNext =>
      currentIndex < queue.length - 1 || (repeatMode == PlayerRepeatMode.all && queue.length > 1);

  /// Mirror of [hasNext] for the other direction.
  bool get hasPrevious =>
      currentIndex > 0 || (repeatMode == PlayerRepeatMode.all && queue.length > 1);

  /// The tracks queued after the current one, in play order.
  List<Track> get upNext =>
      hasTrack && currentIndex + 1 < queue.length ? queue.sublist(currentIndex + 1) : const [];

  PlayerState copyWith({
    List<Track>? queue,
    List<Track>? sourceQueue,
    int? currentIndex,
    bool? isPlaying,
    bool? isLoading,
    Duration? position,
    Duration? duration,
    bool? isShuffled,
    PlayerRepeatMode? repeatMode,
    double? volume,
    Duration? crossfadeDuration,
  }) {
    return PlayerState(
      queue: queue ?? this.queue,
      sourceQueue: sourceQueue ?? this.sourceQueue,
      currentIndex: currentIndex ?? this.currentIndex,
      isPlaying: isPlaying ?? this.isPlaying,
      isLoading: isLoading ?? this.isLoading,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      isShuffled: isShuffled ?? this.isShuffled,
      repeatMode: repeatMode ?? this.repeatMode,
      volume: volume ?? this.volume,
      crossfadeDuration: crossfadeDuration ?? this.crossfadeDuration,
    );
  }

  @override
  List<Object?> get props => [
        queue,
        sourceQueue,
        currentIndex,
        isPlaying,
        isLoading,
        position,
        duration,
        isShuffled,
        repeatMode,
        volume,
        crossfadeDuration,
      ];
}
