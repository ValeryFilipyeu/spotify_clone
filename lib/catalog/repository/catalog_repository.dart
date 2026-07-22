import '../models/catalog_item.dart';
import '../models/catalog_detail.dart';
import '../models/catalog_section.dart';

/// The seam a real catalog backend (a REST API, Spotify's Web API, ...) would
/// plug into later. As with [AuthRepository], nothing above this interface
/// references the concrete implementation -- only main.dart/app.dart's
/// composition point names the fake.
abstract class CatalogRepository {
  /// Loads the sections shown on the home screen.
  Future<List<CatalogSection>> fetchHomeSections();

  /// Loads every browsable item once, de-duplicated across sections. Backs the
  /// Search (client-side filtered) and Library screens.
  Future<List<CatalogItem>> fetchAllItems();

  /// Loads a single album/playlist (its header item plus its tracks).
  /// Throws [CatalogItemNotFound] if no item matches [itemId].
  Future<CatalogDetail> fetchDetail(String itemId);
}
