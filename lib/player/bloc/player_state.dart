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

/// One evolving state class, as AuthState and HomeState. Queue plus index give
/// the current track and drive next/previous.
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
    this.unplayableTrack,
  });

  /// The longest crossfade the settings UI offers.
  static const Duration maxCrossfadeDuration = Duration(seconds: 12);

  /// Play order: what "Up next" lists and what [currentIndex] points into.
  final List<Track> queue;

  /// The order it was started from, kept so shuffle can be turned back off. See
  /// PlayerBloc for how later additions, which this never saw, are folded in.
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

  /// Overlap on a track change; [Duration.zero] (the default) means none.
  final Duration crossfadeDuration;

  /// The track whose load failed, kept until another load is attempted.
  ///
  /// Persistent, unlike the message it also triggers: a track that cannot be
  /// loaded cannot be played, paused or scrubbed either, and the transport has
  /// to stay disabled the whole time it is the current track.
  final Track? unplayableTrack;

  bool get isCrossfadeEnabled => crossfadeDuration > Duration.zero;

  Track? get currentTrack =>
      currentIndex >= 0 && currentIndex < queue.length ? queue[currentIndex] : null;

  bool get hasTrack => currentTrack != null;

  /// Whether the track on screen is the one that would not load. Matched by id
  /// rather than cleared on every queue move, so moving on is enough.
  bool get isUnplayable => unplayableTrack != null && unplayableTrack!.id == currentTrack?.id;

  /// Whether [PlayerNextRequested] would go anywhere -- a later track, or
  /// [PlayerRepeatMode.all] wrapping to the front.
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
    Track? unplayableTrack,
    bool clearUnplayable = false,
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
      // Carried by default and dropped only on request, so a position tick
      // cannot quietly re-enable a track that will not play.
      unplayableTrack: clearUnplayable ? null : (unplayableTrack ?? this.unplayableTrack),
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
    unplayableTrack,
  ];
}
