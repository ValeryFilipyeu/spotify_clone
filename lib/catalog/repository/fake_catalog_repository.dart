import '../models/catalog_item.dart';
import '../models/catalog_section.dart';
import 'catalog_repository.dart';

/// An in-memory catalog with hardcoded, deterministic data. Simulates network
/// latency with a delay so the home screen's loading state is real and
/// visible, exactly like [FakeAuthRepository] does for auth.
class FakeCatalogRepository implements CatalogRepository {
  const FakeCatalogRepository();

  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return const [
      CatalogSection(
        title: 'Made for you',
        items: [
          CatalogItem(id: 'dm1', title: 'Daily Mix 1', subtitle: 'Tame Impala, MGMT & more', coverColor: 0xFF1DB954),
          CatalogItem(id: 'dm2', title: 'Daily Mix 2', subtitle: 'Radiohead, Interpol & more', coverColor: 0xFFE13300),
          CatalogItem(id: 'dw', title: 'Discover Weekly', subtitle: 'Your weekly mixtape', coverColor: 0xFF7358FF),
          CatalogItem(id: 'rr', title: 'Release Radar', subtitle: 'New from artists you follow', coverColor: 0xFF2D46B9),
        ],
      ),
      CatalogSection(
        title: 'Recently played',
        items: [
          CatalogItem(id: 'lofi', title: 'Lo-Fi Beats', subtitle: 'Chill instrumental hip-hop', coverColor: 0xFFBA5D07),
          CatalogItem(id: 'focus', title: 'Deep Focus', subtitle: 'Keep calm and focus', coverColor: 0xFF503750),
          CatalogItem(id: 'run', title: 'Running Mix', subtitle: 'Uptempo motivation', coverColor: 0xFF8D67AB),
          CatalogItem(id: 'jazz', title: 'Jazz Vibes', subtitle: 'The perfect backdrop', coverColor: 0xFF477D95),
        ],
      ),
      CatalogSection(
        title: 'Popular albums',
        items: [
          CatalogItem(id: 'ab1', title: 'Currents', subtitle: 'Tame Impala', coverColor: 0xFFE8115B),
          CatalogItem(id: 'ab2', title: 'In Rainbows', subtitle: 'Radiohead', coverColor: 0xFF148A08),
          CatalogItem(id: 'ab3', title: 'Random Access Memories', subtitle: 'Daft Punk', coverColor: 0xFFDC148C),
          CatalogItem(id: 'ab4', title: 'Blonde', subtitle: 'Frank Ocean', coverColor: 0xFF056952),
        ],
      ),
    ];
  }
}
