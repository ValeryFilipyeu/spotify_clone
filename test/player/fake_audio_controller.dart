import 'dart:async';

import 'package:spotify_clone/player/audio/audio_controller.dart';

/// A test double for [AudioController] with no real audio engine. Records the
/// URLs it was asked to play and lets tests drive its streams manually, so
/// PlayerBloc can be tested deterministically without just_audio.
class FakeAudioController implements AudioController {
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
  bool disposed = false;

  /// Value returned by [setUrl] (simulating the engine reporting duration at
  /// load time). Null by default.
  Duration? loadedDuration;

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
    return loadedDuration;
  }

  @override
  Future<void> play() async => playCount++;

  @override
  Future<void> pause() async => pauseCount++;

  @override
  Future<void> seek(Duration position) async => seeks.add(position);

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
