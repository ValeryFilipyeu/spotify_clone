import '../models/catalog_item.dart';
import '../models/catalog_detail.dart';
import '../models/catalog_section.dart';
import '../models/search_results.dart';

/// The seam a catalog backend plugs into. Nothing above this interface names a
/// concrete implementation; only the composition point does.
abstract class CatalogRepository {
  /// Loads the sections shown on the home screen.
  Future<List<CatalogSection>> fetchHomeSections();

  /// Loads the items with these [ids], dropping any the catalog no longer has --
  /// an id outlives the thing it points at, so a deleted playlist just stops
  /// appearing. An empty [ids] must not make a request.
  ///
  /// (This was `fetchAllItems()` until the catalog stopped being a hardcoded
  /// list. A fake data source keeps an interface like that plausible for ever.)
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids);

  /// Loads the tracks with these [ids], each paired with the album/playlist it
  /// belongs to. Backs the "liked songs" section of the Library.
  ///
  /// Missing ids are dropped, as in [fetchItemsByIds].
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids);

  /// Case-insensitive search over albums/playlists (title, subtitle) and songs
  /// (title, artist). A blank query returns empty [SearchResults].
  Future<SearchResults> search(String query);

  /// Loads a single album/playlist (its header item plus its tracks).
  /// Throws [CatalogItemNotFound] if no item matches [itemId].
  Future<CatalogDetail> fetchDetail(String itemId);

  /// Discards anything this source is holding, so the next read goes back to
  /// where the data lives. For pull-to-refresh, which otherwise gets answered out
  /// of the very cache being distrusted.
  ///
  /// Abstract rather than given an empty default: every implementation here is
  /// `implements`, so a default body would be inherited by nobody while reading
  /// as though it were.
  void invalidate();
}
