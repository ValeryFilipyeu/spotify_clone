import 'dart:async';

import 'package:audio_service/audio_service.dart';

import 'media_session.dart';

/// The real OS media session, and the only file that imports audio_service.
/// Purely a translator: [NowPlaying] out, [MediaSessionCommand] in. No queue and
/// no decisions.
///
/// Not just_audio_background, the lighter drop-in: it attaches to a single
/// AudioPlayer and crossfade runs two, so the session has to follow *our* notion
/// of the current track rather than one engine's.
class AudioServiceMediaSession extends BaseAudioHandler implements MediaSession {
  final _commands = StreamController<MediaSessionCommand>.broadcast();

  @override
  Stream<MediaSessionCommand> get commands => _commands.stream;

  // --- OS -> app. Forwarding only; acting on them is the bloc's job.

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
    // A zero duration is left off: audio_service then hides the seek bar, which
    // beats drawing one of length 0.
    final artUrl = nowPlaying.artUrl;
    mediaItem.add(
      MediaItem(
        id: nowPlaying.id,
        title: nowPlaying.title,
        artist: nowPlaying.artist,
        duration: nowPlaying.duration > Duration.zero ? nowPlaying.duration : null,
        // tryParse: a malformed url should cost the artwork, not the update.
        artUri: artUrl == null ? null : Uri.tryParse(artUrl),
      ),
    );

    // Only buttons that would do something.
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
        // The OS extrapolates from here while `playing`, which is why this is
        // not published on every tick.
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
