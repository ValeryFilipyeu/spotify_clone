import 'package:equatable/equatable.dart';

import '../../catalog/models/catalog_item.dart';
import '../../catalog/models/search_results.dart';

enum LibraryStatus { initial, loading, success, failure }

/// Holds the *whole* catalog (all items and all tracks). The Library screen
/// itself shows only the liked subset, but which ids are liked is app-wide
/// state ([LikesCubit]); the view intersects these lists with the live liked
/// set at build time, so unliking something removes it from the list instantly
/// without this cubit reloading.
class LibraryState extends Equatable {
  const LibraryState({
    this.status = LibraryStatus.initial,
    this.allItems = const [],
    this.allTracks = const [],
    this.errorMessage,
  });

  final LibraryStatus status;
  final List<CatalogItem> allItems;
  final List<TrackHit> allTracks;
  final String? errorMessage;

  LibraryState copyWith({
    LibraryStatus? status,
    List<CatalogItem>? allItems,
    List<TrackHit>? allTracks,
    String? errorMessage,
  }) {
    return LibraryState(
      status: status ?? this.status,
      allItems: allItems ?? this.allItems,
      allTracks: allTracks ?? this.allTracks,
      errorMessage: errorMessage,
    );
  }

  @override
  List<Object?> get props => [status, allItems, allTracks, errorMessage];
}
