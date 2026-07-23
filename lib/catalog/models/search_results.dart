import 'package:equatable/equatable.dart';

import 'catalog_item.dart';
import 'track.dart';

/// A song that matched a search, paired with the album/playlist it lives in.
/// The [album] gives the results row its context (`artist • album`) and lets us
/// attribute the song without a second lookup.
class TrackHit extends Equatable {
  const TrackHit({required this.track, required this.album});

  final Track track;
  final CatalogItem album;

  @override
  List<Object?> get props => [track, album];
}

/// The outcome of [CatalogRepository.search]: albums/playlists whose title or
/// subtitle matched, plus individual songs whose title or artist matched. The
/// two are kept apart so the UI can label and lay them out as separate sections
/// (like Spotify's "Songs" / "Playlists" groups).
class SearchResults extends Equatable {
  const SearchResults({this.items = const [], this.tracks = const []});

  final List<CatalogItem> items;
  final List<TrackHit> tracks;

  bool get isEmpty => items.isEmpty && tracks.isEmpty;
  bool get isNotEmpty => !isEmpty;

  @override
  List<Object?> get props => [items, tracks];
}
