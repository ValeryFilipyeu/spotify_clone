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

/// Resume / pause as *explicit* intents rather than a toggle. The OS media
/// session sends one or the other (lock screen, headset button, Siri), and
/// folding those onto [PlayerPlayPauseToggled] would do the opposite of what was
/// asked whenever the two sides briefly disagreed about who is playing.
class PlayerResumeRequested extends PlayerEvent {
  const PlayerResumeRequested();
}

class PlayerPauseRequested extends PlayerEvent {
  const PlayerPauseRequested();
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

/// Clears the queue and stops audio (e.g. on logout). Playback *preferences*
/// (volume, shuffle, repeat) survive -- only the listening session is cleared.
class PlayerStopped extends PlayerEvent {
  const PlayerStopped();
}

/// Turns shuffle on (current track first, the rest randomised) or off
/// (restoring the original order). The current track keeps playing either way.
class PlayerShuffleToggled extends PlayerEvent {
  const PlayerShuffleToggled();
}

/// Cycles [PlayerRepeatMode]: off -> all -> one -> off.
class PlayerRepeatModeCycled extends PlayerEvent {
  const PlayerRepeatModeCycled();
}

class PlayerVolumeChanged extends PlayerEvent {
  const PlayerVolumeChanged(this.volume);

  /// Clamped to 0.0..1.0 by the bloc.
  final double volume;

  @override
  List<Object?> get props => [volume];
}

/// Sets how long tracks overlap on a change; [Duration.zero] turns crossfade
/// off. Persisted per account.
class PlayerCrossfadeDurationChanged extends PlayerEvent {
  const PlayerCrossfadeDurationChanged(this.duration);

  final Duration duration;

  @override
  List<Object?> get props => [duration];
}

// --- Queue editing ("Up next") ---

/// Jumps straight to [index] in the current queue (tapping a row in Up next).
class PlayerQueueIndexSelected extends PlayerEvent {
  const PlayerQueueIndexSelected(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

/// Drag-to-reorder within the queue. Both are absolute indices into
/// `state.queue` -- [newIndex] is the slot the track ends up at, so the view
/// translates from its own (sublist) coordinates before dispatching.
class PlayerQueueReordered extends PlayerEvent {
  const PlayerQueueReordered({required this.oldIndex, required this.newIndex});

  final int oldIndex;
  final int newIndex;

  @override
  List<Object?> get props => [oldIndex, newIndex];
}

/// Removes the queue entry at [index]. Removing the *playing* track advances to
/// whatever shifts into its slot.
class PlayerQueueItemRemoved extends PlayerEvent {
  const PlayerQueueItemRemoved(this.index);

  final int index;

  @override
  List<Object?> get props => [index];
}

/// "Add to queue" -- appends [track] to the end. Starts playback if the queue
/// is currently empty.
class PlayerQueueAppended extends PlayerEvent {
  const PlayerQueueAppended(this.track);

  final Track track;

  @override
  List<Object?> get props => [track];
}

/// "Play next" -- inserts [track] directly after the current track. Starts
/// playback if the queue is currently empty.
class PlayerPlayNextEnqueued extends PlayerEvent {
  const PlayerPlayNextEnqueued(this.track);

  final Track track;

  @override
  List<Object?> get props => [track];
}

// --- Internal events, dispatched by the bloc from its own streams ---

/// The signed-in account changed (null when signed out), so this account's
/// persisted playback preferences must be loaded and applied. Carries a plain
/// id rather than an AppUser so the player stays independent of the auth models.
class PlayerUserChanged extends PlayerEvent {
  const PlayerUserChanged(this.userId);

  final String? userId;

  @override
  List<Object?> get props => [userId];
}

/// The OS handed our audio device to something else -- a call, Siri, a
/// navigation prompt. [duck] means we may keep playing, quietly; otherwise
/// playback has to stop for the duration. See [AudioInterruptions].
class PlayerInterruptionBegan extends PlayerEvent {
  const PlayerInterruptionBegan({required this.duck});

  final bool duck;

  @override
  List<Object?> get props => [duck];
}

/// We have the audio device back. [shouldResume] is the platform's opinion, and
/// is only honoured if the interruption is what stopped us in the first place.
class PlayerInterruptionEnded extends PlayerEvent {
  const PlayerInterruptionEnded({required this.shouldResume});

  final bool shouldResume;

  @override
  List<Object?> get props => [shouldResume];
}

/// Headphones unplugged / Bluetooth gone. Pauses, and never auto-resumes.
class PlayerOutputDisconnected extends PlayerEvent {
  const PlayerOutputDisconnected();
}

/// Emitted by PlayerBloc's own wall-clock ticker (~4x/sec while playing) to
/// advance the displayed position. We use a ticker rather than the engine's
/// position stream because that stream is unusable on some platforms (iOS pins
/// it to 0:00; web either freezes or drifts).
class PlayerPositionTicked extends PlayerEvent {
  const PlayerPositionTicked();
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
