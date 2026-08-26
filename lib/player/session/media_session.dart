import '../../catalog/models/track.dart';
import '../bloc/player_state.dart';

/// The lock screen, Android notification, Control Center and headset buttons.
///
/// Traffic runs both ways, which is what makes it worth its own seam: [update]
/// tells the OS what to draw, [commands] carries taps made outside the app. The
/// bloc stays the source of truth; the OS is another remote control.
abstract class MediaSession {
  /// Commands from outside the app. Broadcast, so the first lock-screen tap is
  /// not lost before anything has subscribed.
  Stream<MediaSessionCommand> get commands;

  /// Publishes what should be shown and how playback is behaving.
  Future<void> update(NowPlaying nowPlaying);

  /// Tears the session down, so the controls do not linger on a dead queue.
  Future<void> clear();
}

/// A remote-control action. Sealed so the bloc's `switch` over it is checked at
/// compile time: adding a command here is a compile error until it is handled.
sealed class MediaSessionCommand {
  const MediaSessionCommand();
}

/// Distinct from [MediaSessionPauseRequested]: the OS sends an explicit intent,
/// and a single "toggle" would invert the state whenever the two sides briefly
/// disagreed.
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

/// What the OS should display. A value object rather than [PlayerState] itself,
/// so the session layer depends on a handful of fields.
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

  /// [hasNext]/[hasPrevious] come from the state's own getters, so repeat mode
  /// opening up the queue edges reaches the OS's buttons.
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
    artUrl: track.primaryCoverUrl,
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

  /// Left out of [signature]: artwork changes only when the track does, and
  /// [id] already covers that.
  final String? artUrl;

  /// Everything except [position], which the OS extrapolates on its own -- so
  /// ordinary drift is not a reason to cross a platform channel. PlayerBloc
  /// handles a *jump* separately.
  String get signature =>
      '$id|$title|$artist|${duration.inMilliseconds}|'
      '$isPlaying|$isLoading|$hasNext|$hasPrevious';
}

/// For unit tests and platforms with no media session. Every call is a no-op.
class NoopMediaSession implements MediaSession {
  const NoopMediaSession();

  @override
  Stream<MediaSessionCommand> get commands => const Stream.empty();

  @override
  Future<void> update(NowPlaying nowPlaying) async {}

  @override
  Future<void> clear() async {}
}
