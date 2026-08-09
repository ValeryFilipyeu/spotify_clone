import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/search_results.dart';

enum LibraryStatus { initial, loading, success, failure }

/// The catalog data behind the "Your Library" tab: the items and tracks the
/// user has liked, resolved from their ids.
///
/// This used to hold the *entire* catalog, which the view then intersected with
/// the liked set. That only worked because the catalog was a hardcoded list --
/// a real one cannot be downloaded to find a dozen rows in it.
///
/// The view still intersects what is here with the live [LikesCubit] set, and
/// that is deliberate rather than redundant: unliking something has to remove it
/// from the list instantly, without waiting for a refetch to come back.
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
