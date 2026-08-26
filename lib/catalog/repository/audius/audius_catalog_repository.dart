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
/// Audius is keyless and user-uploaded, which shapes two things: there is no
/// editorial personalisation, so Home is *composed* here out of what the API
/// offers; and a "track" may be a three-hour DJ set. See [maxTrackDuration].
class AudiusCatalogRepository implements CatalogRepository {
  AudiusCatalogRepository({required this._client});

  /// Redirects to a healthy node from Audius' discovery network.
  static final Uri baseUrl = Uri.parse('https://api.audius.co/v1');

  /// Audius asks callers to identify themselves. Not a key, no registration.
  static const String appName = 'SpotifyCloneLearning';

  /// Longer than this is a mix or a podcast, not a song. The live API really
  /// does return 10,940-second "tracks" beside three-minute ones.
  ///
  /// Filtered here, not in the mapper, which stays a faithful reading.
  static const Duration maxTrackDuration = Duration(minutes: 15);

  /// How many items each home row shows.
  static const int _rowLength = 10;

  /// The first row is what Audius features; the rest stand in for the genre
  /// rows a real service would personalise.
  static const List<({String title, String? query})> _homeRows = [
    (title: 'Trending playlists', query: null),
    (title: 'Lo-fi & chill', query: 'lofi'),
    (title: 'Jazz', query: 'jazz'),
    (title: 'Electronic', query: 'electronic'),
  ];

  final ApiClient _client;

  @override
  void invalidate() {
    // Nothing is remembered here; caching lives in the decorator above.
  }

  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    final rows = await Future.wait([
      for (final row in _homeRows) _sectionOrNull(row.title, row.query),
    ]);

    final sections = rows.nonNulls.toList();
    // Three rows of four is still a home screen. Zero is the network being
    // down, and should say so rather than render blank.
    if (sections.isEmpty) {
      throw NetworkUnreachable(_client.uriFor('playlists/trending'), 'every home row failed');
    }
    return sections;
  }

  Future<CatalogSection?> _sectionOrNull(String title, String? query) async {
    try {
      final path = query == null ? 'playlists/trending' : 'playlists/search';
      final data = await _getData(
        path,
        query: {
          // The trending row takes no query; ApiClient drops a null value.
          'query': ?query,
          'limit': '$_rowLength',
        },
      );

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

    // One request for the lot. Unrecognised ids are simply absent, which is the
    // contract.
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
        for (final (index, json) in data.indexed) AudiusTrackDto.fromJson(json, at: 'data[$index]'),
      ],
    );

    return [for (final dto in dtos) _hitFor(dto)];
  }

  @override
  Future<SearchResults> search(String query) async {
    final needle = query.trim();
    if (needle.isEmpty) return const SearchResults();

    // Separate endpoints, asked together: neither half should wait.
    final (tracks, items) = await (_searchTracks(needle), _searchPlaylists(needle)).wait;

    return SearchResults(items: items, tracks: tracks);
  }

  Future<List<TrackHit>> _searchTracks(String query) async {
    final data = await _getData('tracks/search', query: {'query': query, 'limit': '20'});
    final dtos = _read(
      _client.uriFor('tracks/search'),
      () => [
        for (final (index, json) in data.indexed) AudiusTrackDto.fromJson(json, at: 'data[$index]'),
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
      // The tracklist is embedded, so opening an album is one request.
      data = await _getData('playlists/$itemId');
    } on HttpErrorStatus catch (failure) {
      // A malformed id gets 400, not 404. Either way it is not there.
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

  /// Drops gated tracks and anything long enough to be a mix.
  Iterable<AudiusTrackDto> _playable(Iterable<AudiusTrackDto> tracks) => tracks.where(
    (track) => track.isStreamable && Duration(seconds: track.durationSeconds) <= maxTrackDuration,
  );

  Track _toTrack(AudiusTrackDto dto) =>
      dto.toDomain(streamUrl: _client.uriFor('tracks/${dto.id}/stream'));

  /// Pairs a track with a stand-in album built from the track itself: an Audius
  /// upload has no reliable backlink to one. Both surfaces that use it -- a
  /// search row and a library tile -- read correctly this way.
  TrackHit _hitFor(AudiusTrackDto dto) => TrackHit(
    track: _toTrack(dto),
    album: CatalogItem(
      id: dto.id,
      title: dto.title,
      subtitle: dto.artist,
      coverColor: 0xFF282828,
      coverUrls: dto.artworkUrls,
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

  /// Re-throws a [JsonFormatError] as an [ApiFailure]. The reader knows the
  /// field, this layer knows the request, and callers above see only one type.
  T _read<T>(Uri uri, T Function() read) {
    try {
      return read();
    } on JsonFormatError catch (error) {
      throw MalformedResponse(uri, '$error');
    }
  }
}
