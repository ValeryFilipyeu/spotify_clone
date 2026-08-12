import '../../catalog/models/track.dart';
import '../bloc/player_state.dart';

/// The seam over the OS media session -- the lock screen, the Android
/// notification, the iOS Control Center / CarPlay panel, headset buttons.
///
/// Same idea as [AudioController] over just_audio: [PlayerBloc] never imports
/// audio_service, so it stays unit-testable with no platform channels. Traffic
/// runs both ways here, which is what makes it worth its own abstraction:
///   * OUT -- [update] tells the OS what to draw and whether we are playing.
///   * IN  -- [commands] carries taps the user made *outside* the app.
///
/// The bloc stays the single source of truth for the queue; the OS is just
/// another remote control pointed at it.
abstract class MediaSession {
  /// Commands originating outside the app. Broadcast: the bloc is the only
  /// listener today, but a stream that drops events when nobody is attached
  /// yet would silently lose the very first lock-screen tap.
  Stream<MediaSessionCommand> get commands;

  /// Publishes what should be shown and how playback is behaving.
  Future<void> update(NowPlaying nowPlaying);

  /// Tears the session down -- nothing is playing any more, so the notification
  /// and lock-screen controls must go away rather than linger on a dead queue.
  Future<void> clear();
}

/// A remote-control action. Sealed so the bloc's `switch` over it is checked at
/// compile time: adding a command here is a compile error until it is handled.
sealed class MediaSessionCommand {
  const MediaSessionCommand();
}

/// Distinct from [MediaSessionPause] on purpose. The OS sends an explicit
/// intent, so mapping both onto a single "toggle" would invert the state
/// whenever the two sides briefly disagreed (a stale lock-screen button, say).
class MediaSessionPlayRequested extends MediaSessionCommand {
  const MediaSessionPlayRequested();
}

class MediaSessionPauseRequested extends MediaSessionCommand {
  const MediaSessionPauseRequested();
}

class MediaSessionNextRequested extends MediaSessionCommand {
  const MediaSessionNextRequested();
}

class MediaSessionPreviousRequested extends MediaSessionCommand {
  const MediaSessionPreviousRequested();
}

/// Dismissing the notification (Android) or stopping from the OS. Ends the
/// listening session, exactly like the mini-player's X.
class MediaSessionStopRequested extends MediaSessionCommand {
  const MediaSessionStopRequested();
}

class MediaSessionSeekRequested extends MediaSessionCommand {
  const MediaSessionSeekRequested(this.position);

  final Duration position;
}

/// An immutable snapshot of what the OS should display. A plain value object
/// rather than [PlayerState] itself, so the session layer depends on a handful
/// of fields instead of the player's whole shape.
class NowPlaying {
  const NowPlaying({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.position,
    required this.isPlaying,
    required this.isLoading,
    required this.hasNext,
    required this.hasPrevious,
    this.artUrl,
  });

  /// Built from the state the bloc already holds. [hasNext]/[hasPrevious] come
  /// from the state's own getters, so repeat mode opening up the queue edges is
  /// reflected in which buttons the OS offers.
  factory NowPlaying.from(PlayerState state, Track track) => NowPlaying(
    id: track.id,
    title: track.title,
    artist: track.artist,
    duration: state.duration,
    position: state.position,
    isPlaying: state.isPlaying,
    isLoading: state.isLoading,
    hasNext: state.hasNext,
    hasPrevious: state.hasPrevious,
    artUrl: track.coverUrl,
  );

  final String id;
  final String title;
  final String artist;
  final Duration duration;
  final Duration position;
  final bool isPlaying;
  final bool isLoading;
  final bool hasNext;
  final bool hasPrevious;

  /// Cover art for the lock screen / notification, or null for a track with no
  /// artwork. Left out of [signature] on purpose: artwork only ever changes when
  /// the track does, and [id] already covers that.
  final String? artUrl;

  /// Everything except [position]. Position advances four times a second, and
  /// the OS extrapolates it from the last value it was given -- so a change in
  /// position alone is not a reason to cross a platform channel. See
  /// PlayerBloc's publishing logic, which compares this and treats a *jump* in
  /// position (a seek, a track change) separately from ordinary drift.
  String get signature =>
      '$id|$title|$artist|${duration.inMilliseconds}|'
      '$isPlaying|$isLoading|$hasNext|$hasPrevious';
}

/// Used when there is no OS session to talk to: unit tests, and platforms where
/// a media session is meaningless. Every call is a no-op and [commands] never
/// emits, so PlayerBloc behaves exactly as it did before this feature existed.
class NoopMediaSession implements MediaSession {
  const NoopMediaSession();

  @override
  Stream<MediaSessionCommand> get commands => const Stream.empty();

  @override
  Future<void> update(NowPlaying nowPlaying) async {}

  @override
  Future<void> clear() async {}
}
