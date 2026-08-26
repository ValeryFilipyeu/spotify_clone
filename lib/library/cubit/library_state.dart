import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/search_results.dart';

enum LibraryStatus { initial, loading, success, failure }

/// The items and tracks behind "Your Library", resolved from the liked ids.
///
/// The view still intersects these with the live [LikesCubit] set, which is not
/// redundant: unliking has to drop a row at once, without waiting for a refetch.
class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.initial,
    this.items = const [],
    this.tracks = const [],
    this.errorMessage,
  });

  final LibraryStatus status;

  /// Liked albums and playlists.
  final List<CatalogItem> items;

  /// Liked songs, each paired with the album or playlist it came from.
  final List<TrackHit> tracks;

  final String? errorMessage;

  LibraryState copyWith({
    LibraryStatus? status,
    List<CatalogItem>? items,
    List<TrackHit>? tracks,
    String? errorMessage,
  }) {
    return LibraryState(
      status: status ?? this.status,
      items: items ?? this.items,
      tracks: tracks ?? this.tracks,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, items, tracks, errorMessage];
}
