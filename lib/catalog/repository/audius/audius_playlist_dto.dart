import '../../../network/json_reader.dart';
import '../../../theme/cover_palette.dart';
import '../../models/catalog_item.dart';
import 'audius_track_dto.dart';

/// One playlist or album as Audius sends it.
///
/// Both map onto the same domain [CatalogItem], exactly as they did in the
/// hardcoded catalog, where an album and a playlist differed only in what their
/// subtitle said. The `is_album` flag is kept because it decides that subtitle.
class AudiusPlaylistDto {
  const AudiusPlaylistDto({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.description,
    required this.isAlbum,
    required this.artworkUrl,
    required this.tracks,
  });

  final String id;
  final String name;

  /// The account that published it -- the credited artist for an album, the
  /// curator for a playlist.
  final String ownerName;

  /// The curator's blurb. Usually null: most playlists have none.
  final String? description;

  final bool isAlbum;

  final String? artworkUrl;

  /// The tracklist, which both `/playlists/{id}` and `/playlists/search` embed
  /// in full rather than making callers ask separately. Worth reading here
  /// instead of calling `/playlists/{id}/tracks`, because it turns opening an
  /// album into one request instead of two.
  ///
  /// Empty when the payload carries no `tracks` key at all -- absence is not an
  /// error, since not every endpoint includes it.
  final List<AudiusTrackDto> tracks;

  factory AudiusPlaylistDto.fromJson(Map<String, Object?> json, {String at = ''}) {
    final artwork = json.objectOrNull('artwork');
    final rawTracks = json.containsKey('tracks') && json['tracks'] != null
        ? json.objectList('tracks', at: at)
        : const <Map<String, Object?>>[];

    return AudiusPlaylistDto(
      id: json.string('id', at: at),
      name: json.string('playlist_name', at: at),
      ownerName: json.object('user', at: at).string('name', at: '$at.user'),
      description: json.stringOrNull('description'),
      isAlbum: json.boolean('is_album'),
      artworkUrl: artwork?.stringOrNull(AudiusTrackDto.preferredArtworkSize) ??
          artwork?.stringOrNull('1000x1000') ??
          artwork?.stringOrNull('150x150'),
      tracks: [
        for (final (index, track) in rawTracks.indexed)
          AudiusTrackDto.fromJson(track, at: '$at.tracks[$index]'),
      ],
    );
  }

  /// The card's second line.
  ///
  /// Mirrors what the hardcoded catalog did by hand: an album showed its artist
  /// ("Tame Impala"), a playlist showed a description ("Chill instrumental
  /// hip-hop"). Falls back to naming the curator, because most real playlists
  /// have no description and a blank second line reads as a loading glitch.
  String get subtitle {
    if (isAlbum) return ownerName;
    return description ?? 'By $ownerName';
  }

  CatalogItem toDomain() => CatalogItem(
        id: id,
        title: name,
        subtitle: subtitle,
        // Derived from the id, because a real catalog has no opinion about it.
        coverColor: CoverPalette.forSeed(id),
        coverUrl: artworkUrl,
      );
}
