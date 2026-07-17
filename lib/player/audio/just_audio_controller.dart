import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:just_audio/just_audio.dart';

import 'audio_controller.dart';

/// The real audio engine, wrapping just_audio's [AudioPlayer]. This is the
/// only file (besides main.dart's composition point) that imports just_audio.
class JustAudioController implements AudioController {
  JustAudioController() : _player = AudioPlayer();

  final AudioPlayer _player;

  @override
  Stream<Duration> get positionStream => _player.positionStream;

  @override
  Stream<Duration?> get durationStream => _player.durationStream;

  @override
  Stream<bool> get playingStream => _player.playingStream;

  @override
  Stream<bool> get bufferingStream => _player.processingStateStream
      .map((state) => state == ProcessingState.loading || state == ProcessingState.buffering);

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
    return _player.setUrl(url);
  }

  @override
  Future<void> play() => _player.play();

  @override
  Future<void> pause() => _player.pause();

  @override
  Future<void> seek(Duration position) => _player.seek(position);

  @override
  Future<void> stop() => _player.stop();

  @override
  Future<void> dispose() => _player.dispose();
}
