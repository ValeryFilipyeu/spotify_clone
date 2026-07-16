import 'package:equatable/equatable.dart';

/// A single song within an album or playlist.
class Track extends Equatable {
  const Track({
    required this.id,
    required this.title,
    required this.artist,
    required this.duration,
  });

  final String id;
  final String title;
  final String artist;
  final Duration duration;

  @override
  List<Object?> get props => [id, title, artist, duration];
}
