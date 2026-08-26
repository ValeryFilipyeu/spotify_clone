import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';
import 'audio_controller.dart';

/// The real audio engine, wrapping just_audio's [AudioPlayer]. This is the
/// only file (besides main.dart's composition point) that imports just_audio.
class JustAudioController implements AudioController {
  JustAudioController({this._audioCache})
    : _player = AudioPlayer(
        // ExoPlayer keeps no back-buffer by default, so a backwards seek falls
        // outside it and re-fetches -- a buffering spinner over audio already
        // loaded. Android-only; everything else already retains played audio.
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(backBufferDuration: Duration(minutes: 10)),
        ),
      );

  final AudioPlayer _player;

  /// Null on the web and in tests, where this streams as it always did.
  final AudioCache? _audioCache;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<bool> get bufferingStream => _player.processingStateStream.map(
    (state) => state == ProcessingState.loading || state == ProcessingState.buffering,
  );

  @override
  Stream<void> get completedStream => _player.processingStateStream
      .where((state) => state == ProcessingState.completed)
      .map((_) {});

  @override
  Future<Duration?> setUrl(String url) async {
    // Web-only workaround. just_audio_web caches the root playlist's player by
    // an id it hard-codes to the empty string and never rebuilds, so every
    // setUrl after the first replays the FIRST track. stop() deactivates the
    // platform; reactivating on the next setUrl builds a fresh player with an
    // empty source cache. Native engines rebuild correctly, hence the gate.
    if (kIsWeb) {
      await _player.stop();
    }

    final cache = _audioCache;
    if (cache == null) return _player.setUrl(url);
    // setAudioSource, because the cache decides what kind of source comes back.
    return _player.setAudioSource(await cache.sourceFor(url));
  }

  // One AudioPlayer sounds one source, so crossfade is composed on top: see
  // CrossfadeAudioController, which drives two of these.
  @override
  bool get supportsCrossfade => false;

  // Nothing to pre-buffer into: the only source is the one sounding.
  @override
  Future<void> preload(String url) async {}

  @override
  Future<Duration?> crossfadeTo(String url, {required Duration fade}) => setUrl(url);

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> setVolume(double volume) => _player.setVolume(volume);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
