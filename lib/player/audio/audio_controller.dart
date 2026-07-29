/// The seam over the audio engine, so [PlayerBloc] never imports just_audio
/// directly and can be unit-tested with a fake -- same repository-style
/// abstraction used for auth and catalog.
abstract class AudioController {
  /// Current playback position, emitted continuously while playing.
  Stream<Duration> get positionStream;

  /// Total duration of the loaded track (emits once known; may be null before).
  Stream<Duration?> get durationStream;

  /// Whether audio is currently playing (vs paused). Note this reflects play
  /// *intent* -- it does NOT flip to false when a track ends, so it must not
  /// be used to infer "finished loading" (that is what [bufferingStream] is
  /// for).
  Stream<bool> get playingStream;

  /// True while the current source is loading/buffering, false once it is
  /// ready (or idle). This is the correct signal for a loading spinner --
  /// unlike playingStream, it fires on every track change including
  /// auto-advance.
  Stream<bool> get bufferingStream;

  /// Emits once each time the current track plays to its end.
  Stream<void> get completedStream;

  /// Loads [url] as the current source (does not start playback). Returns the
  /// track's duration if the engine reports it at load time (just_audio does),
  /// so the UI has a duration even if durationStream is slow to emit.
  Future<Duration?> setUrl(String url);

  /// Whether this controller can have two sources sounding at once. When false,
  /// [PlayerBloc] never asks for a crossfade and lets tracks change on a cut.
  bool get supportsCrossfade;

  /// Pre-buffers [url] so a following [crossfadeTo] can begin fading
  /// immediately instead of spending the first part of the fade loading.
  ///
  /// Without this the load happens *inside* the fade window: the outgoing track
  /// keeps playing alone until it lands, so a 3s fade over a 2s load leaves only
  /// 1s of overlap -- and a load slower than the fade removes the crossfade
  /// altogether. Must stay silent and must not start playback. Calling it
  /// repeatedly with the same [url] is cheap (implementations dedupe), so the
  /// caller can drive it straight from its position ticker. A no-op for engines
  /// that cannot hold a second source.
  Future<void> preload(String url);

  /// Starts [url] while fading the currently-playing source out over [fade],
  /// returning the new source's duration exactly like [setUrl].
  ///
  /// When [url] was already handed to [preload] and finished loading, the fade
  /// starts at once and runs for its full length.
  ///
  /// From the caller's point of view the current source has already changed to
  /// [url] when this returns -- the outgoing audio finishing its fade is an
  /// implementation detail, and its natural completion must NOT be reported on
  /// [completedStream] (that would skip a track). Controllers that cannot
  /// overlap sources degrade to a plain [setUrl].
  Future<Duration?> crossfadeTo(String url, {required Duration fade});

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Sets output volume, 0.0 (silent) .. 1.0 (full).
  Future<void> setVolume(double volume);

  /// Stops playback and releases the current source.
  Future<void> stop();

  Future<void> dispose();
}
