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

  /// A streamable audio source. The fake repository assigns royalty-free demo
  /// samples, unrelated to the track's fictional metadata.
  final String audioUrl;

  /// The containing item's cover, denormalised onto every track as real music
  /// APIs do -- so the player, which holds only a queue of [Track]s, can show
  /// artwork without knowing where the queue came from.
  ///
  /// Several urls, best first: see [CatalogItem.coverUrls].
  final List<String> coverUrls;

  /// For the one consumer that cannot take a list: the OS media session fetches
  /// lock-screen art itself. Named for what it is, so reusing the old `coverUrl`
  /// where failover *is* possible stays a compile error.
  String? get primaryCoverUrl => coverUrls.isEmpty ? null : coverUrls.first;

  @override
  List<Object?> get props => [id, title, artist, duration, audioUrl, coverUrls];
}
