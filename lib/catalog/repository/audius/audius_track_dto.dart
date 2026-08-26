import '../../../network/json_reader.dart';
import '../../models/track.dart';
import 'audius_artwork.dart';

/// One track as Audius sends it, reduced to what this app uses.
///
/// A wire type rather than `Track.fromJson`: [Track] is consumed by the player,
/// the queue, likes and the lock screen, and teaching it one vendor's JSON would
/// couple all of them to that vendor.
class AudiusTrackDto {
  const AudiusTrackDto({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.artworkUrls,
    required this.isStreamable,
  });

  /// The short hash id (`ng9rl`), not the numeric `track_id`: it is what every
  /// other endpoint takes.
  final String id;

  final String title;

  /// The uploader: Audius has no separate artist entity.
  final String artist;

  final int durationSeconds;

  /// Hosts serving this track's cover, best first. See [AudiusArtwork].
  final List<String> artworkUrls;

  /// Whether this track can actually be streamed by an anonymous listener.
  final bool isStreamable;

  /// Reads a track out of [json]. [at] is its path in the payload, so a
  /// [JsonFormatError] can say where.
  factory AudiusTrackDto.fromJson(Map<String, Object?> json, {String at = ''}) {
    return AudiusTrackDto(
      id: json.string('id', at: at),
      title: json.string('title', at: at),
      // A row's second line, and every observed payload carries one.
      artist: json.object('user', at: at).string('name', at: '$at.user'),
      durationSeconds: json.integer('duration', at: at),
      artworkUrls: AudiusArtwork.urlsFrom(json.objectOrNull('artwork')),
      isStreamable: _readStreamable(json),
    );
  }

  /// Reads `access.stream`, ignoring the top-level `is_streamable`, which does
  /// not mean what it says: the live API sends `is_streamable: false` alongside
  /// `access: {stream: true}` on tracks that play fine (`95wro` in the fixtures).
  ///
  /// Defaults to true, so a slim payload under-filters rather than emptying the
  /// app.
  static bool _readStreamable(Map<String, Object?> json) =>
      json.objectOrNull('access')?.boolean('stream', orElse: true) ?? true;

  /// [streamUrl] must be the *stable* endpoint, not the payload's pre-signed
  /// `stream` url, which expires -- and a [Track] outlives it in the queue, in
  /// history and in the OS media session.
  Track toDomain({required Uri streamUrl}) => Track(
    id: id,
    title: title,
    artist: artist,
    duration: Duration(seconds: durationSeconds),
    audioUrl: streamUrl.toString(),
    coverUrls: artworkUrls,
  );
}
