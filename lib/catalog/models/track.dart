import 'package:equatable/equatable.dart';

/// A single song within an album or playlist.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.audioUrl,
    this.coverUrl,
  });

  final String id;
  final String title;
  final String artist;
  final Duration duration;

  /// A streamable audio source. There is no real music database, so the fake
  /// repository assigns each track a royalty-free demo sample (SoundHelix) --
  /// the audio is a stand-in and intentionally unrelated to the track's
  /// (fictional) metadata.
  final String audioUrl;

  /// The containing album/playlist's cover, copied onto every track rather than
  /// looked up through a reference. Denormalised on purpose: it is what real
  /// music APIs do (Spotify embeds `album.images` in each track object), and it
  /// means the player -- which only ever holds a queue of [Track]s -- can show
  /// artwork, on its own screens and on the lock screen, without knowing which
  /// catalog item the queue came from.
  final String? coverUrl;

  @override
  List<Object?> get props => [id, title, artist, duration, audioUrl, coverUrl];
}
