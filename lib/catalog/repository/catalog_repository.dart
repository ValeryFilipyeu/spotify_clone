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

  /// Loads the items with these [ids], skipping any the catalog no longer has.
  ///
  /// This used to be `fetchAllItems()`, which returned the entire catalog. That
  /// worked only because the catalog was a hardcoded list: no real backend can
  /// hand over everything it has, and neither caller ever wanted it to. The
  /// Library resolves the ids the user liked and Home resolves the ids they
  /// recently played -- both were downloading a whole catalog to look up a
  /// handful of rows. A fake data source will keep an interface like that
  /// plausible indefinitely, which is worth remembering the next time one is
  /// designed against a fake.
  ///
  /// Missing ids are dropped rather than raising: an id outlives the thing it
  /// points at, so a playlist deleted since it was liked simply stops appearing.
  /// Implementations should tolerate an empty [ids] without making a request.
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids);

  /// Loads the tracks with these [ids], each paired with the album/playlist it
  /// belongs to. Backs the "liked songs" section of the Library.
  ///
  /// Missing ids are dropped, as in [fetchItemsByIds].
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids);

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

  /// Discards anything this source is holding on to, so the next read goes back
  /// to wherever the data really lives.
  ///
  /// Exists for one caller: a user pulling to refresh. That gesture means "I do
  /// not trust what is on screen", and without this it would be answered out of
  /// the very cache being distrusted.
  ///
  /// A source that remembers nothing has nothing to discard, so most
  /// implementations are an empty body. They still have to write it: `implements`
  /// in Dart demands every member of the interface whether or not the interface
  /// gave it a body, and all of these are `implements` rather than `extends`.
  /// Left abstract for that reason -- a default body here would be inherited by
  /// nobody while reading as though it were.
  void invalidate();
}
