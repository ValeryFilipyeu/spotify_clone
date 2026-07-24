import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/search/cubit/search_cubit.dart';
import 'package:spotify_clone/search/cubit/search_state.dart';

const _album = CatalogItem(id: 'b', title: 'In Rainbows', subtitle: 'Radiohead', coverColor: 0);

const _items = [
  CatalogItem(id: 'a', title: 'Currents', subtitle: 'Tame Impala', coverColor: 0),
  _album,
  CatalogItem(id: 'c', title: 'Jazz Vibes', subtitle: 'Chill backdrop', coverColor: 0),
];

const _trackHits = [
  TrackHit(
    track: Track(id: 't-karma', title: 'Karma Police', artist: 'Radiohead', duration: Duration(minutes: 4), audioUrl: 'u'),
    album: _album,
  ),
  TrackHit(
    track: Track(id: 't-nude', title: 'Nude', artist: 'Radiohead', duration: Duration(minutes: 4), audioUrl: 'u'),
    album: _album,
  ),
];

/// Filters like the real fake (items by title/subtitle, songs by title/artist)
/// and records every query it was actually asked to search -- so a test can
/// assert debouncing collapsed a burst of keystrokes into a single call.
class _RecordingCatalogRepository implements CatalogRepository {
  _RecordingCatalogRepository({this.items = const [], this.trackHits = const []});

  final List<CatalogItem> items;
  final List<TrackHit> trackHits;
  final List<String> queries = [];

  @override
  Future<SearchResults> search(String query) async {
    queries.add(query);
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const SearchResults();
    return SearchResults(
      items: items
          .where((i) => i.title.toLowerCase().contains(needle) || i.subtitle.toLowerCase().contains(needle))
          .toList(),
      tracks: trackHits
          .where((h) => h.track.title.toLowerCase().contains(needle) || h.track.artist.toLowerCase().contains(needle))
          .toList(),
    );
  }

  @override
  Future<List<CatalogItem>> fetchAllItems() async => items;

  @override
  Future<List<TrackHit>> fetchAllTracks() => throw UnimplementedError();

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

class _ThrowingCatalogRepository implements CatalogRepository {
  @override
  Future<SearchResults> search(String query) async => throw Exception('down');

  @override
  Future<List<CatalogItem>> fetchAllItems() => throw UnimplementedError();

  @override
  Future<List<TrackHit>> fetchAllTracks() => throw UnimplementedError();

  @override
  Future<List<CatalogSection>> fetchHomeSections() => throw UnimplementedError();

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => throw UnimplementedError();
}

// Comfortably past the 350ms debounce so the timer fires within the test.
const _pastDebounce = Duration(milliseconds: 500);

void main() {
  group('SearchCubit', () {
    late _RecordingCatalogRepository repo;

    _RecordingCatalogRepository fullRepo() => _RecordingCatalogRepository(items: _items, trackHits: _trackHits);

    blocTest<SearchCubit, SearchState>(
      'a blank query returns to the prompt and never hits the repository',
      setUp: () => repo = fullRepo(),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('   '),
      wait: _pastDebounce,
      expect: () => [
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.initial)
            .having((s) => s.results.isEmpty, 'results empty', isTrue),
      ],
      verify: (_) => expect(repo.queries, isEmpty),
    );

    blocTest<SearchCubit, SearchState>(
      'debounces a burst of keystrokes into a single search for the final query',
      setUp: () => repo = fullRepo(),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) {
        cubit.queryChanged('r');
        cubit.queryChanged('ra');
        cubit.queryChanged('rad');
      },
      wait: _pastDebounce,
      verify: (_) => expect(repo.queries, ['rad']),
    );

    blocTest<SearchCubit, SearchState>(
      'a settled query returns matching albums AND songs',
      setUp: () => repo = fullRepo(),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('radiohead'), // album subtitle + song artist
      wait: _pastDebounce,
      skip: 1, // the immediate query echo
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.results.items.map((i) => i.id).toList(), 'album ids', ['b'])
            .having((s) => s.results.tracks.map((h) => h.track.id).toList(), 'song ids', ['t-karma', 't-nude']),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'a query that only matches a song returns songs with no albums',
      setUp: () => repo = fullRepo(),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('karma'), // only "Karma Police"
      wait: _pastDebounce,
      skip: 1,
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.results.items, 'albums', isEmpty)
            .having((s) => s.results.tracks.map((h) => h.track.id).toList(), 'song ids', ['t-karma']),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'a query with no matches settles on success with empty results',
      setUp: () => repo = fullRepo(),
      build: () => SearchCubit(catalogRepository: repo),
      act: (cubit) => cubit.queryChanged('zzzzz'),
      wait: _pastDebounce,
      skip: 1,
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.success)
            .having((s) => s.results.isEmpty, 'results empty', isTrue),
      ],
    );

    blocTest<SearchCubit, SearchState>(
      'emits [loading, failure] when the search call throws',
      build: () => SearchCubit(catalogRepository: _ThrowingCatalogRepository()),
      act: (cubit) => cubit.queryChanged('radio'),
      wait: _pastDebounce,
      skip: 1,
      expect: () => [
        isA<SearchState>().having((s) => s.status, 'status', SearchStatus.loading),
        isA<SearchState>()
            .having((s) => s.status, 'status', SearchStatus.failure)
            .having((s) => s.errorMessage, 'errorMessage', isNotNull),
      ],
    );
  });
}
