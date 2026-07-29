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

  // --- Manual stream drivers for tests ---
  void emitPlaying(bool playing) => _playing.add(playing);
  void emitBuffering(bool buffering) => _buffering.add(buffering);
  void emitPosition(Duration position) => _position.add(position);
  void emitDuration(Duration duration) => _duration.add(duration);
  void emitCompleted() => _completed.add(null);

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

  @override
  Future<Duration?> setUrl(String url) async {
    setUrls.add(url);
    if (loadDelay > Duration.zero) await Future<void>.delayed(loadDelay);
    return _durationFor(url);
  }

  /// Reproduces just_audio's real contract: [play]'s future completes only when
  /// the track ENDS, so anything that awaits it stalls for the whole track.
  /// Off by default to keep the simple tests simple.
  bool playCompletesOnlyWhenTrackEnds = false;

  @override
  Future<void> play() {
    playCount++;
    if (playCompletesOnlyWhenTrackEnds) return Completer<void>().future;
    return Future<void>.value();
  }

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);

  @override
  Future<void> stop() async => stopCount++;

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
