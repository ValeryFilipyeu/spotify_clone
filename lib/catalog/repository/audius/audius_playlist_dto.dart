import '../../../network/json_reader.dart';
import '../../../theme/cover_palette.dart';
import '../../models/catalog_item.dart';
import 'audius_artwork.dart';
import 'audius_track_dto.dart';

/// One playlist or album as Audius sends it. Both map onto [CatalogItem]; the
/// `is_album` flag survives only because it decides the subtitle.
class AudiusPlaylistDto {
  const AudiusPlaylistDto({
    required this.id,
    required this.name,
    required this.ownerName,
    required this.description,
    required this.isAlbum,
    required this.artworkUrls,
    required this.tracks,
  });

  final String id;
  final String name;

  /// The credited artist for an album, the curator for a playlist.
  final String ownerName;

  /// The curator's blurb. Usually null: most playlists have none.
  final String? description;

  final bool isAlbum;

  /// Every host that will serve this cover, best first. See [AudiusArtwork].
  final List<String> artworkUrls;

  /// Embedded in full by both endpoints that return a playlist, so reading it
  /// here makes opening an album one request instead of two. Empty when the
  /// payload has no `tracks` key: not every endpoint includes it.
  final List<AudiusTrackDto> tracks;

  factory AudiusPlaylistDto.fromJson(Map<String, Object?> json, {String at = ''}) {
    final rawTracks = json.containsKey('tracks') && json['tracks'] != null
        ? json.objectList('tracks', at: at)
        : const <Map<String, Object?>>[];

    return AudiusPlaylistDto(
      id: json.string('id', at: at),
      name: json.string('playlist_name', at: at),
      ownerName: json.object('user', at: at).string('name', at: '$at.user'),
      description: json.stringOrNull('description'),
      isAlbum: json.boolean('is_album'),
      artworkUrls: AudiusArtwork.urlsFrom(json.objectOrNull('artwork')),
      tracks: [
        for (final (index, track) in rawTracks.indexed)
          AudiusTrackDto.fromJson(track, at: '$at.tracks[$index]'),
      ],
    );
  }

  /// The card's second line: an album shows its artist, a playlist its
  /// description -- falling back to the curator, since most have no description
  /// and a blank line reads as a loading glitch.
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
    coverUrls: artworkUrls,
  );
}
