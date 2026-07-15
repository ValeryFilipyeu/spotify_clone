import '../models/catalog_section.dart';

/// The seam a real catalog backend (a REST API, Spotify's Web API, ...) would
/// plug into later. As with [AuthRepository], nothing above this interface
/// references the concrete implementation -- only main.dart/app.dart's
/// composition point names the fake.
abstract class CatalogRepository {
  /// Loads the sections shown on the home screen.
  Future<List<CatalogSection>> fetchHomeSections();
}
