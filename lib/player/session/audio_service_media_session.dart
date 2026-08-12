import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'media_session.dart';

/// The real OS media session, backed by audio_service. This is the only file
/// that imports audio_service -- exactly like [JustAudioController] is the only
/// file that imports just_audio.
///
/// It is deliberately dumb: it translates [NowPlaying] into audio_service's
/// [PlaybackState]/[MediaItem] and turns the handler callbacks the OS invokes
/// back into [MediaSessionCommand]s. No queue, no decisions -- PlayerBloc keeps
/// all of that.
///
/// Note on the alternative: just_audio_background is the lighter drop-in for
/// this, but it attaches itself to a single AudioPlayer, and crossfade means we
/// run two (see CrossfadeAudioController). Driving audio_service directly is
/// what lets the session follow *our* notion of the current track rather than
/// one particular engine's.
class AudioServiceMediaSession extends BaseAudioHandler implements MediaSession {
  final _commands = StreamController<MediaSessionCommand>.broadcast();

  @override
  Stream<MediaSessionCommand> get commands => _commands.stream;

  // --- OS -> app. Each of these is invoked by audio_service when the user taps
  // a lock-screen/notification button, presses a headset button, or asks Siri.
  // They only forward: acting on them is the bloc's job.

  @override
  Future<void> play() async => _commands.add(const MediaSessionPlayRequested());

  @override
  Future<void> pause() async => _commands.add(const MediaSessionPauseRequested());

  @override
  Future<void> skipToNext() async => _commands.add(const MediaSessionNextRequested());

  @override
  Future<void> skipToPrevious() async => _commands.add(const MediaSessionPreviousRequested());

  @override
  Future<void> stop() async => _commands.add(const MediaSessionStopRequested());

  @override
  Future<void> seek(Duration position) async => _commands.add(MediaSessionSeekRequested(position));

  // --- app -> OS ---

  @override
  Future<void> update(NowPlaying nowPlaying) async {
    // Drives the title/artist/scrubber length on the lock screen. A duration of
    // zero is left off entirely: audio_service hides the seek bar when the
    // duration is unknown, which is better than drawing one of length 0.
    final artUrl = nowPlaying.artUrl;
    mediaItem.add(
      MediaItem(
        id: nowPlaying.id,
        title: nowPlaying.title,
        artist: nowPlaying.artist,
        duration: nowPlaying.duration > Duration.zero ? nowPlaying.duration : null,
        // audio_service downloads and caches this itself, then hands it to
        // MPNowPlayingInfoCenter / the Android notification. tryParse, not parse:
        // a malformed url must cost us the artwork, not the whole session update.
        artUri: artUrl == null ? null : Uri.tryParse(artUrl),
      ),
    );

    // Only offer buttons that would actually do something -- on the first track
    // of a queue there is nothing to skip back to.
    final controls = <MediaControl>[
      if (nowPlaying.hasPrevious) MediaControl.skipToPrevious,
      if (nowPlaying.isPlaying) MediaControl.pause else MediaControl.play,
      if (nowPlaying.hasNext) MediaControl.skipToNext,
    ];

    playbackState.add(
      PlaybackState(
        controls: controls,
        // Android's collapsed notification shows at most three.
        androidCompactActionIndices: List.generate(controls.length, (i) => i),
        systemActions: const {
          MediaAction.seek,
          // On iOS these turn the skip buttons into press-and-hold seek as well.
          MediaAction.seekForward,
          MediaAction.seekBackward,
        },
        processingState: nowPlaying.isLoading
            ? AudioProcessingState.loading
            : AudioProcessingState.ready,
        playing: nowPlaying.isPlaying,
        // The OS extrapolates from here using its own clock while `playing` is
        // true, which is why we do not have to publish on every position tick.
        updatePosition: nowPlaying.position,
      ),
    );
  }

  @override
  Future<void> clear() async {
    mediaItem.add(null);
    playbackState.add(
      PlaybackState(controls: const [], processingState: AudioProcessingState.idle, playing: false),
    );
  }

  Future<void> dispose() => _commands.close();
}
