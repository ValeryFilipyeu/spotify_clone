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

  Future<void> play();

  Future<void> pause();

  Future<void> seek(Duration position);

  /// Stops playback and releases the current source.
  Future<void> stop();

  Future<void> dispose();
}
