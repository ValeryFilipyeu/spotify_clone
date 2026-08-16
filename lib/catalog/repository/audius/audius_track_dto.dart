import '../../../network/json_reader.dart';
import '../../models/track.dart';
import 'audius_artwork.dart';

/// One track as Audius sends it, reduced to the handful of fields this app can
/// use.
///
/// A wire type of its own rather than a `Track.fromJson`, and that separation is
/// the point: [Track] is consumed by the player, the queue, the likes feature,
/// the lock-screen session and the semantics tests. Teaching it to parse one
/// vendor's JSON would couple all of those to that vendor, and swapping backends
/// would then be a change to the domain rather than to one file.
class AudiusTrackDto {
  const AudiusTrackDto({
    required this.id,
    required this.title,
    required this.artist,
    required this.durationSeconds,
    required this.artworkUrls,
    required this.isStreamable,
  });

  /// Audius' short hash id (`ng9rl`), not the numeric `track_id`. It is what
  /// every other endpoint takes.
  final String id;

  final String title;

  /// The uploading account's display name. Audius has no separate artist entity
  /// -- the uploader *is* the credited artist.
  final String artist;

  final int durationSeconds;

  /// Every host that will serve this track's square cover, best first, or empty
  /// when the payload carries no usable artwork. See [AudiusArtwork].
  final List<String> artworkUrls;

  /// Whether this track can actually be streamed by an anonymous listener.
  final bool isStreamable;

  /// Reads a track out of [json].
  ///
  /// [at] is the path this object sits at in the payload, used only to make a
  /// [JsonFormatError] say where it happened.
  factory AudiusTrackDto.fromJson(Map<String, Object?> json, {String at = ''}) {
    return AudiusTrackDto(
      id: json.string('id', at: at),
      title: json.string('title', at: at),
      // Required: a track with no creator name has nothing to show in the row's
      // second line, and every payload observed carries one.
      artist: json.object('user', at: at).string('name', at: '$at.user'),
      durationSeconds: json.integer('duration', at: at),
      artworkUrls: AudiusArtwork.urlsFrom(json.objectOrNull('artwork')),
      isStreamable: _readStreamable(json),
    );
  }

  /// Whether an anonymous listener may stream this.
  ///
  /// Reads `access.stream` and pointedly ignores the top-level `is_streamable`,
  /// which does not mean what its name suggests: the live API returns
  /// `is_streamable: false` alongside `access: {stream: true}` on tracks that
  /// stream perfectly well (`95wro` in the fixtures is a real example). Trusting
  /// the obvious field would silently drop playable music.
  ///
  /// Defaults to true when `access` is absent, so an unexpectedly slim payload
  /// under-filters rather than emptying the app.
  static bool _readStreamable(Map<String, Object?> json) =>
      json.objectOrNull('access')?.boolean('stream', orElse: true) ?? true;

  /// Converts to the domain type.
  ///
  /// [streamUrl] must be the *stable* endpoint for this track, not the `stream`
  /// object's url from the payload. That one is pre-signed and carries a
  /// timestamp, so it expires -- and since a [Track] is held in the play queue,
  /// persisted through history and handed to the OS media session, storing an
  /// expiring url would mean a queue that plays now and 404s in an hour.
  Track toDomain({required Uri streamUrl}) => Track(
    id: id,
    title: title,
    artist: artist,
    duration: Duration(seconds: durationSeconds),
    audioUrl: streamUrl.toString(),
    coverUrls: artworkUrls,
  );
}
