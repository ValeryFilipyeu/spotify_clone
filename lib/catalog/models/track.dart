import 'package:equatable/equatable.dart';

/// A single song within an album or playlist.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.audioUrl,
    this.coverUrls = const [],
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
  ///
  /// Several urls for the same image, best first, for the reason described on
  /// [CatalogItem.coverUrls]: any one host can be down while the others hold the
  /// same bytes.
  final List<String> coverUrls;

  /// The first source to try, for the one consumer that cannot be handed a list.
  ///
  /// The OS media session fetches lock-screen art itself, through
  /// `audio_service`, so it takes a single url and there is nowhere to put the
  /// alternates. Named for what it is rather than `coverUrl`, so that reusing
  /// the old name somewhere that *can* fail over stays a compile error instead
  /// of quietly working on the first host and nowhere else.
  String? get primaryCoverUrl => coverUrls.isEmpty ? null : coverUrls.first;

  @override
  List<Object?> get props => [id, title, artist, duration, audioUrl, coverUrls];
}
