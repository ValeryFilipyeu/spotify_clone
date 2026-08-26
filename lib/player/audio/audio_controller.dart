/// The seam over the audio engine, so [PlayerBloc] never imports just_audio and
/// can be unit-tested with a fake.
abstract class AudioController {
  /// Current playback position, emitted continuously while playing.
  Stream<Duration> get positionStream;

  /// Total duration of the loaded track (emits once known; may be null before).
  Stream<Duration?> get durationStream;

  /// Play *intent*: it does not flip to false when a track ends, so it cannot
  /// tell you a load finished. Use [bufferingStream] for that.
  Stream<bool> get playingStream;

  /// The signal for a loading spinner: unlike [playingStream] it fires on every
  /// track change, auto-advance included.
  Stream<bool> get bufferingStream;

  /// Emits once each time the current track plays to its end.
  Stream<void> get completedStream;

  /// Loads [url] without starting playback, returning the duration if the engine
  /// knows it at load time -- so the UI has one before [durationStream] emits.
  Future<Duration?> setUrl(String url);

  /// Whether this controller can have two sources sounding at once. When false,
  /// [PlayerBloc] never asks for a crossfade and lets tracks change on a cut.
  bool get supportsCrossfade;

  /// Pre-buffers [url] so a following [crossfadeTo] fades immediately instead of
  /// spending the first part of the fade loading -- a 3s fade over a 2s load
  /// leaves 1s of overlap, and a slower load removes the crossfade entirely.
  ///
  /// Must stay silent. Implementations dedupe by url, so the caller can drive
  /// this from its position ticker. A no-op where a second source is impossible.
  Future<void> preload(String url);

  /// Starts [url] while fading the current source out over [fade], returning the
  /// duration as [setUrl] does. A [preload]ed url fades at once, for its full
  /// length.
  ///
  /// The current source has already changed when this returns; the outgoing
  /// audio finishing is an implementation detail, and its completion must NOT
  /// reach [completedStream] or a track is skipped. Degrades to [setUrl].
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
