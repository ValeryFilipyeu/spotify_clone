import '../../../network/api_client.dart';
import '../../../network/api_failure.dart';
import '../../../network/json_reader.dart';
import '../../models/catalog_detail.dart';
import '../../models/catalog_failure.dart';
import '../../models/catalog_item.dart';
import '../../models/catalog_section.dart';
import '../../models/search_results.dart';
import '../../models/track.dart';
import '../catalog_repository.dart';
import 'audius_playlist_dto.dart';
import 'audius_track_dto.dart';

/// The catalog, backed by the Audius API.
///
/// Audius is a public, keyless music API whose content is uploaded by its own
/// users. That shapes two things this class has to deal with, neither of which
/// a curated commercial catalog would have:
///
///  * there is no "Daily Mix" and no editorial personalisation, so Home is
///    *composed* here out of what the API does offer; and
///  * a "track" may be a three-hour DJ set, because nothing stops someone
///    uploading one. See [maxTrackDuration].
class AudiusCatalogRepository implements CatalogRepository {
  AudiusCatalogRepository({required this._client});

  /// The public entry point. Audius runs a network of interchangeable discovery
  /// nodes; this host redirects to a healthy one.
  static final Uri baseUrl = Uri.parse('https://api.audius.co/v1');

  /// Sent on every request. Audius asks callers to identify themselves; it is
  /// not a key and needs no registration.
  static const String appName = 'SpotifyCloneLearning';

  /// Longer than this and it is a mix or a podcast, not a song.
  ///
  /// Filtered here rather than in the mapper, which stays a faithful reading of
  /// what the server said. The live API really does return 10,940-second
  /// "tracks" next to three-minute ones, and one of those in a row of songs
  /// makes the whole screen look broken.
  static const Duration maxTrackDuration = Duration(minutes: 15);

  /// How many items each home row shows.
  static const int _rowLength = 10;

  /// Home's rows. The first is what Audius itself is featuring; the rest stand
  /// in for the genre rows a real service would personalise.
  static const List<({String title, String? query})> _homeRows = [
    (title: 'Trending playlists', query: null),
    (title: 'Lo-fi & chill', query: 'lofi'),
    (title: 'Jazz', query: 'jazz'),
    (title: 'Electronic', query: 'electronic'),
  ];

  final ApiClient _client;

  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    final rows = await Future.wait([
      for (final row in _homeRows) _sectionOrNull(row.title, row.query),
    ]);

    final sections = rows.nonNulls.toList();
    // One row failing is survivable -- three of four is still a home screen.
    // All of them failing is not: that is the network being down, and the
    // screen should say so rather than render blank.
    if (sections.isEmpty) {
      throw NetworkUnreachable(_client.uriFor('playlists/trending'), 'every home row failed');
    }
    return sections;
  }

  Future<CatalogSection?> _sectionOrNull(String title, String? query) async {
    try {
      final path = query == null ? 'playlists/trending' : 'playlists/search';
      final data = await _getData(path, query: {
        // Null-aware element: the trending row takes no query at all, and
        // ApiClient drops a null value rather than sending `query=`.
        'query': ?query,
        'limit': '$_rowLength',
      });

      final items = _read(
        _client.uriFor(path),
        () => [
          for (final (index, json) in data.indexed)
            AudiusPlaylistDto.fromJson(json, at: 'data[$index]').toDomain(),
        ],
      );
      return items.isEmpty ? null : CatalogSection(title: title, items: items);
    } on ApiFailure {
      return null;
    }
  }

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async {
    final wanted = ids.toSet().toList();
    if (wanted.isEmpty) return const [];

    // One request for the lot: `?id=a&id=b`. Ids Audius does not recognise are
    // simply absent from the response, which is exactly the contract.
    final data = await _getData('playlists', query: {'id': wanted});
    return _read(
      _client.uriFor('playlists'),
      () => [
        for (final (index, json) in data.indexed)
          AudiusPlaylistDto.fromJson(json, at: 'data[$index]').toDomain(),
      ],
    );
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) async {
    final wanted = ids.toSet().toList();
    if (wanted.isEmpty) return const [];

    final data = await _getData('tracks', query: {'id': wanted});
    final dtos = _read(
      _client.uriFor('tracks'),
      () => [
        for (final (index, json) in data.indexed)
          AudiusTrackDto.fromJson(json, at: 'data[$index]'),
      ],
    );

    return [for (final dto in dtos) _hitFor(dto)];
  }

  @override
  Future<SearchResults> search(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) return const SearchResults();

    // Songs and playlists are separate endpoints, asked for together: the two
    // halves of the results screen have no reason to wait for each other.
    final (tracks, items) = await (
      _searchTracks(needle),
      _searchPlaylists(needle),
    ).wait;

    return SearchResults(items: items, tracks: tracks);
  }

  Future<List<TrackHit>> _searchTracks(String query) async {
    final data = await _getData('tracks/search', query: {'query': query, 'limit': '20'});
    final dtos = _read(
      _client.uriFor('tracks/search'),
      () => [
        for (final (index, json) in data.indexed)
          AudiusTrackDto.fromJson(json, at: 'data[$index]'),
      ],
    );

    return [for (final dto in _playable(dtos)) _hitFor(dto)];
  }

  Future<List<CatalogItem>> _searchPlaylists(String query) async {
    final data = await _getData('playlists/search', query: {'query': query, 'limit': '20'});
    return _read(
      _client.uriFor('playlists/search'),
      () => [
        for (final (index, json) in data.indexed)
          AudiusPlaylistDto.fromJson(json, at: 'data[$index]').toDomain(),
      ],
    );
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) async {
    final List<Map<String, Object?>> data;
    try {
      // The tracklist comes embedded in this response, so opening an album is
      // one request rather than a fetch-then-fetch-its-tracks pair.
      data = await _getData('playlists/$itemId');
    } on HttpErrorStatus catch (failure) {
      // A malformed id is answered with 400 ("invalid playlistId"), not 404.
      // Either way the caller asked for something that is not there, and the
      // interface has a type for that.
      if (failure.statusCode == 400 || failure.statusCode == 404) {
        throw CatalogItemNotFound(itemId);
      }
      rethrow;
    }
    if (data.isEmpty) throw CatalogItemNotFound(itemId);

    final playlist = _read(
      _client.uriFor('playlists/$itemId'),
      () => AudiusPlaylistDto.fromJson(data.first, at: 'data[0]'),
    );

    return CatalogDetail(
      item: playlist.toDomain(),
      tracks: [for (final dto in _playable(playlist.tracks)) _toTrack(dto)],
    );
  }

  /// Drops what cannot or should not be played: gated tracks, and uploads long
  /// enough to be a mix rather than a song.
  Iterable<AudiusTrackDto> _playable(Iterable<AudiusTrackDto> tracks) => tracks.where(
        (track) =>
            track.isStreamable && Duration(seconds: track.durationSeconds) <= maxTrackDuration,
      );

  Track _toTrack(AudiusTrackDto dto) =>
      dto.toDomain(streamUrl: _client.uriFor('tracks/${dto.id}/stream'));

  /// Pairs a track with something to show as its album.
  ///
  /// An Audius track is a standalone upload: it has no reliable backlink to a
  /// containing album, so there is nothing to look up. The stand-in is built
  /// from the track itself, which is what the two surfaces that use it actually
  /// want -- the search row prints `artist - album` and the library tile shows a
  /// cover, and both read correctly this way.
  TrackHit _hitFor(AudiusTrackDto dto) => TrackHit(
        track: _toTrack(dto),
        album: CatalogItem(
          id: dto.id,
          title: dto.title,
          subtitle: dto.artist,
          coverColor: 0xFF282828,
          coverUrl: dto.artworkUrl,
        ),
      );

  /// GETs [path] and returns its `data` array, which is how every Audius
  /// endpoint wraps a result.
  Future<List<Map<String, Object?>>> _getData(
    String path, {
    Map<String, Object?> query = const {},
  }) async {
    final json = await _client.getJson(path, query: query);
    return _read(_client.uriFor(path, query: query), () => json.objectList('data'));
  }

  /// Runs a read and re-throws its [JsonFormatError] as an [ApiFailure].
  ///
  /// The reader knows which field was wrong but not which request produced it;
  /// this is the layer that knows both, and callers above only ever have to
  /// handle [ApiFailure].
  T _read<T>(Uri uri, T Function() read) {
    try {
      return read();
    } on JsonFormatError catch (error) {
      throw MalformedResponse(uri, '$error');
    }
  }
}
