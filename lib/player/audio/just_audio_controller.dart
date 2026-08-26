import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

import 'audio_cache.dart';
import 'audio_controller.dart';

/// The real audio engine, wrapping just_audio's [AudioPlayer]. This is the
/// only file (besides main.dart's composition point) that imports just_audio.
class JustAudioController implements AudioController {
  /// Named `audioCache:` at the call site -- Dart derives the parameter name
  /// from the private field by stripping the underscore.
  JustAudioController({this._audioCache})
    : _player = AudioPlayer(
        // Android ExoPlayer keeps NO back-buffer by default
        // (backBufferDuration: 0), so a backwards seek falls outside the
        // buffer and forces a re-fetch -- which surfaces as a brief
        // "buffering" spinner even though the track is already loaded. Keeping
        // a back-buffer retains already-played audio in memory, so seeking
        // backwards lands in it and resumes instantly, with nothing to load.
        // Sized to comfortably cover these short demo tracks (longest ~7 min).
        // Android-only: iOS/macOS/web ignore it and already retain played
        // audio, so their behaviour is unchanged.
        audioLoadConfiguration: const AudioLoadConfiguration(
          androidLoadControl: AndroidLoadControl(backBufferDuration: Duration(minutes: 10)),
        ),
      );

  final AudioPlayer _player;

  /// Where played tracks are kept, or null where they are not kept at all -- on
  /// the web, and in every test. Without it this class streams exactly as it did
  /// before the cache existed.
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
    // WEB-ONLY WORKAROUND. just_audio_web caches the player for the root
    // playlist by its id -- which just_audio hard-codes to the empty string and
    // reuses for the app's whole lifetime -- and never rebuilds it. So every
    // setUrl after the first keeps the ORIGINAL source: it replays the first
    // track and reports the first track's duration. (Native ExoPlayer/AVPlayer
    // rebuild the source correctly, so this only bites on web.)
    //
    // stop() deactivates the platform; the setUrl below reactivates it, and on
    // reactivation just_audio disposes the old web player and creates a fresh
    // one with an empty source cache -- so the new url actually loads. Gated on
    // kIsWeb so native playback timing is byte-for-byte unchanged.
    if (kIsWeb) {
      await _player.stop();
    }

    final cache = _audioCache;
    if (cache == null) return _player.setUrl(url);
    // setAudioSource rather than setUrl, because what comes back may be a local
    // file, a caching stream, or a plain stream -- the cache decides, and this
    // does not need to know which it got.
    return _player.setAudioSource(await cache.sourceFor(url));
  }

  // A single AudioPlayer can only sound one source at a time, so crossfading is
  // composed on top of this class rather than built into it: see
  // CrossfadeAudioController, which drives two of these.
  @override
  bool get supportsCrossfade => false;

  // Nothing to pre-buffer into: this player's only source is the one that is
  // currently sounding. CrossfadeAudioController does the preloading, using its
  // spare instance of this class.
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
