import 'package:equatable/equatable.dart';

/// A single song within an album or playlist.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
    required this.audioUrl,
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

  @override
  List<Object?> get props => [id, title, artist, duration, audioUrl];
}
