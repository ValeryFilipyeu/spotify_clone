import 'package:equatable/equatable.dart';

import '../../catalog/models/track.dart';

sealed class PlayerEvent extends Equatable {
  const PlayerEvent();

  @override
  List<Object?> get props => [];
}

// --- User-driven events ---

/// Start playing [queue] from [startIndex] (dispatched when a track is tapped).
class PlayerTrackStarted extends PlayerEvent {
  const PlayerTrackStarted({required this.queue, required this.startIndex});

  final List<Track> queue;
  final int startIndex;

  @override
  List<Object?> get props => [queue, startIndex];
}

class PlayerPlayPauseToggled extends PlayerEvent {
  const PlayerPlayPauseToggled();
}

class PlayerNextRequested extends PlayerEvent {
  const PlayerNextRequested();
}

class PlayerPreviousRequested extends PlayerEvent {
  const PlayerPreviousRequested();
}

class PlayerSeekRequested extends PlayerEvent {
  const PlayerSeekRequested(this.position);

  final Duration position;

  @override
  List<Object?> get props => [position];
}

/// Clears the queue and stops audio (e.g. on logout).
class PlayerStopped extends PlayerEvent {
  const PlayerStopped();
}

// --- Internal events, dispatched by the bloc from AudioController streams ---

class PlayerPositionChanged extends PlayerEvent {
  const PlayerPositionChanged(this.position);

  final Duration position;

  @override
  List<Object?> get props => [position];
}

class PlayerDurationChanged extends PlayerEvent {
  const PlayerDurationChanged(this.duration);

  final Duration duration;

  @override
  List<Object?> get props => [duration];
}

class PlayerPlayingChanged extends PlayerEvent {
  const PlayerPlayingChanged(this.isPlaying);

  final bool isPlaying;

  @override
  List<Object?> get props => [isPlaying];
}

class PlayerBufferingChanged extends PlayerEvent {
  const PlayerBufferingChanged(this.isBuffering);

  final bool isBuffering;

  @override
  List<Object?> get props => [isBuffering];
}

class PlayerCompleted extends PlayerEvent {
  const PlayerCompleted();
}
