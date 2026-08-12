import 'dart:async';

import 'package:spotify_clone/player/audio/audio_controller.dart';

/// A crossfade request the fake was given, for assertions.
typedef CrossfadeCall = ({String url, Duration fade});

/// A test double for [AudioController] with no real audio engine. Records the
/// URLs it was asked to play and lets tests drive its streams manually, so
/// PlayerBloc can be tested deterministically without just_audio.
class FakeAudioController implements AudioController {
  FakeAudioController({this.supportsCrossfade = false});

  /// Off by default so existing tests see plain cuts; the crossfade tests turn
  /// it on.
  @override
  final bool supportsCrossfade;

  final List<CrossfadeCall> crossfades = [];

  /// Urls handed to [preload], in order. Deduped the way a real controller
  /// does, so tests can assert "buffered exactly once".
  final List<String> preloads = [];

  @override
  Future<void> preload(String url) async {
    if (preloads.isNotEmpty && preloads.last == url) return;
    preloads.add(url);
  }

  /// Simulates a slow network load, so tests can exercise what happens *during*
  /// a load (the real ones take seconds).
  Duration loadDelay = Duration.zero;

  @override
  Future<Duration?> crossfadeTo(String url, {required Duration fade}) async {
    crossfades.add((url: url, fade: fade));
    setUrls.add(url);
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    return _durationFor(url);
  }

  final _position = StreamController<Duration>.broadcast();
  final _duration = StreamController<Duration?>.broadcast();
  final _playing = StreamController<bool>.broadcast();
  final _buffering = StreamController<bool>.broadcast();
  final _completed = StreamController<void>.broadcast();

  final List<String> setUrls = [];
  int playCount = 0;
  int pauseCount = 0;
  int stopCount = 0;
  final List<Duration> seeks = [];
  final List<double> volumes = [];
  bool disposed = false;

  /// Value returned by [setUrl] (simulating the engine reporting duration at
  /// load time). Null by default.
  Duration? loadedDuration;

  /// Per-url durations, as a real engine reports: each source has its own
  /// length. Falls back to [loadedDuration].
  final Map<String, Duration> durationsByUrl = {};

  Duration? _durationFor(String url) => durationsByUrl[url] ?? loadedDuration;

  /// Reproduces just_audio's real playing contract, which is subtle enough to
  /// have shipped a bug: `playing` is play INTENT, not "audio is coming out".
  /// So it survives a track reaching its end; play() returns immediately while
  /// it is already set; and loading a new source while it is set starts that
  /// source with NO event on playingStream at all. In this mode the fake drives
  /// playingStream itself, the way a real engine does.
  ///
  /// Opt-in: most tests drive the stream by hand, which is fine for everything
  /// that does not hinge on the engine's own bookkeeping.
  bool strictPlayingContract = false;
  bool _intendsToPlay = false;

  // --- Manual stream drivers for tests ---
  void emitPlaying(bool playing) => _playing.add(playing);
  void emitBuffering(bool buffering) => _buffering.add(buffering);
  void emitPosition(Duration position) => _position.add(position);
  void emitDuration(Duration duration) => _duration.add(duration);

  /// Note what this deliberately does NOT do under [strictPlayingContract]:
  /// clear the play intent. A real engine keeps it, which is the whole hazard.
  void emitCompleted() => _completed.add(null);

  /// Drops the play intent and reports it, as pause()/stop() do on a real
  /// engine. A no-op when the intent was not set -- just_audio's `if (!playing)
  /// return;`.
  void _releasePlayIntent() {
    if (!strictPlayingContract || !_intendsToPlay) return;
    _intendsToPlay = false;
    _playing.add(false);
  }

  @override
  Stream<Duration> get positionStream => _position.stream;

  @override
  Stream<Duration?> get durationStream => _duration.stream;

  @override
  Stream<bool> get playingStream => _playing.stream;

  @override
  Stream<bool> get bufferingStream => _buffering.stream;

  @override
  Stream<void> get completedStream => _completed.stream;

  /// Makes the next [setUrl] throw, as a dead url or a dropped connection does.
  /// One-shot, so a test can fail a single track change.
  bool failNextLoad = false;

  @override
  Future<Duration?> setUrl(String url) async {
    setUrls.add(url);
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    if (failNextLoad) {
      failNextLoad = false;
      throw StateError('load failed: $url');
    }
    // No playingStream event under strictPlayingContract even though a still-set
    // play intent means this source begins sounding: the SILENCE is the faithful
    // part, since there is no change for the engine to report.
    return _durationFor(url);
  }

  /// Reproduces just_audio's real contract: [play]'s future completes only when
  /// the track ENDS, so anything that awaits it stalls for the whole track.
  /// Off by default to keep the simple tests simple.
  bool playCompletesOnlyWhenTrackEnds = false;

  @override
  Future<void> play() {
    playCount++;
    if (strictPlayingContract && !_intendsToPlay) {
      _intendsToPlay = true;
      _playing.add(true);
    }
    if (playCompletesOnlyWhenTrackEnds) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> pause() async {
    pauseCount++;
    _releasePlayIntent();
  }

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> stop() async {
    stopCount++;
    _releasePlayIntent();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
    await _position.close();
    await _duration.close();
    await _playing.close();
    await _buffering.close();
    await _completed.close();
  }
}
