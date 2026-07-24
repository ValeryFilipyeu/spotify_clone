import '../models/catalog_item.dart';
import '../models/catalog_detail.dart';
import '../models/catalog_section.dart';
import '../models/search_results.dart';

/// The seam a real catalog backend (a REST API, Spotify's Web API, ...) would
/// plug into later. As with [AuthRepository], nothing above this interface
/// references the concrete implementation -- only main.dart/app.dart's
/// composition point names the fake.
abstract class CatalogRepository {
  /// Loads the sections shown on the home screen.
  Future<List<CatalogSection>> fetchHomeSections();

  /// Loads every browsable item once, de-duplicated across sections. Backs the
  /// Library screen.
  Future<List<CatalogItem>> fetchAllItems();

  /// Loads every track across every catalog, each paired with its containing
  /// album/playlist. Backs the "liked songs" section of the Library, which
  /// resolves liked track ids back to their tracks.
  Future<List<TrackHit>> fetchAllTracks();

  /// Searches the catalog for a [query] (case-insensitive), matching both
  /// albums/playlists (by title or subtitle) and individual songs across every
  /// catalog (by track title or artist). Returns empty [SearchResults] for a
  /// blank query. A real backend would run this server-side; even the fake
  /// answers behind a simulated network delay -- that latency is exactly what
  /// makes debouncing the calls (see SearchCubit) worthwhile.
  Future<SearchResults> search(String query);

  /// Loads a single album/playlist (its header item plus its tracks).
  /// Throws [CatalogItemNotFound] if no item matches [itemId].
  Future<CatalogDetail> fetchDetail(String itemId);
}
