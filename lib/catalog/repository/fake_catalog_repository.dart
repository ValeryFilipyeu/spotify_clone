import '../models/catalog_detail.dart';
import '../models/catalog_failure.dart';
import '../models/catalog_item.dart';
import '../models/catalog_section.dart';
import '../models/track.dart';
import 'catalog_repository.dart';

/// An in-memory catalog with hardcoded, deterministic data. Simulates network
/// latency with a delay so loading states are real and visible, exactly like
/// [FakeAuthRepository] does for auth.
class FakeCatalogRepository implements CatalogRepository {
  const FakeCatalogRepository();

  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _sections;
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // Find the header item by scanning the same sections the home screen uses,
    // so the detail header is always consistent with the card that opened it.
    for (final section in _sections) {
      for (final item in section.items) {
        if (item.id == itemId) {
          return CatalogDetail(item: item, tracks: _tracksByItemId[itemId] ?? const []);
        }
      }
    }
    throw CatalogItemNotFound(itemId);
  }

  // ---------------------------------------------------------------------------
  // Fake data. `static const` so it is shared by both methods and allocated
  // once, not rebuilt per call.
  // ---------------------------------------------------------------------------

  static const List<CatalogSection> _sections = [
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

  static const Map<String, List<Track>> _tracksByItemId = {
    // --- Albums: real tracklists, single album artist ---
    'ab1': [
      Track(id: 'ab1-1', title: 'Let It Happen', artist: 'Tame Impala', duration: Duration(minutes: 7, seconds: 47)),
      Track(id: 'ab1-2', title: 'The Less I Know the Better', artist: 'Tame Impala', duration: Duration(minutes: 3, seconds: 36)),
      Track(id: 'ab1-3', title: 'Eventually', artist: 'Tame Impala', duration: Duration(minutes: 5, seconds: 19)),
      Track(id: 'ab1-4', title: "Cause I'm a Man", artist: 'Tame Impala', duration: Duration(minutes: 3, seconds: 54)),
      Track(id: 'ab1-5', title: 'New Person, Same Old Mistakes', artist: 'Tame Impala', duration: Duration(minutes: 6, seconds: 3)),
    ],
    'ab2': [
      Track(id: 'ab2-1', title: '15 Step', artist: 'Radiohead', duration: Duration(minutes: 3, seconds: 57)),
      Track(id: 'ab2-2', title: 'Bodysnatchers', artist: 'Radiohead', duration: Duration(minutes: 4, seconds: 2)),
      Track(id: 'ab2-3', title: 'Nude', artist: 'Radiohead', duration: Duration(minutes: 4, seconds: 15)),
      Track(id: 'ab2-4', title: 'Weird Fishes/Arpeggi', artist: 'Radiohead', duration: Duration(minutes: 5, seconds: 18)),
      Track(id: 'ab2-5', title: 'Reckoner', artist: 'Radiohead', duration: Duration(minutes: 4, seconds: 50)),
    ],
    'ab3': [
      Track(id: 'ab3-1', title: 'Give Life Back to Music', artist: 'Daft Punk', duration: Duration(minutes: 4, seconds: 34)),
      Track(id: 'ab3-2', title: 'Instant Crush', artist: 'Daft Punk', duration: Duration(minutes: 5, seconds: 37)),
      Track(id: 'ab3-3', title: 'Get Lucky', artist: 'Daft Punk', duration: Duration(minutes: 6, seconds: 7)),
      Track(id: 'ab3-4', title: 'Lose Yourself to Dance', artist: 'Daft Punk', duration: Duration(minutes: 5, seconds: 53)),
      Track(id: 'ab3-5', title: "Doin' It Right", artist: 'Daft Punk', duration: Duration(minutes: 4, seconds: 11)),
    ],
    'ab4': [
      Track(id: 'ab4-1', title: 'Nikes', artist: 'Frank Ocean', duration: Duration(minutes: 5, seconds: 14)),
      Track(id: 'ab4-2', title: 'Ivy', artist: 'Frank Ocean', duration: Duration(minutes: 4, seconds: 9)),
      Track(id: 'ab4-3', title: 'Pink + White', artist: 'Frank Ocean', duration: Duration(minutes: 3, seconds: 4)),
      Track(id: 'ab4-4', title: 'Solo', artist: 'Frank Ocean', duration: Duration(minutes: 4, seconds: 17)),
      Track(id: 'ab4-5', title: 'Self Control', artist: 'Frank Ocean', duration: Duration(minutes: 4, seconds: 9)),
    ],
    // --- Mixes / playlists: varied artists per track ---
    'dm1': [
      Track(id: 'dm1-1', title: 'Time to Pretend', artist: 'MGMT', duration: Duration(minutes: 4, seconds: 21)),
      Track(id: 'dm1-2', title: 'Feels Like We Only Go Backwards', artist: 'Tame Impala', duration: Duration(minutes: 3, seconds: 12)),
      Track(id: 'dm1-3', title: 'Electric Feel', artist: 'MGMT', duration: Duration(minutes: 3, seconds: 49)),
      Track(id: 'dm1-4', title: 'The Moment', artist: 'Tame Impala', duration: Duration(minutes: 4, seconds: 19)),
      Track(id: 'dm1-5', title: 'Kids', artist: 'MGMT', duration: Duration(minutes: 5, seconds: 2)),
    ],
    'dm2': [
      Track(id: 'dm2-1', title: 'Evil', artist: 'Interpol', duration: Duration(minutes: 3, seconds: 39)),
      Track(id: 'dm2-2', title: 'Karma Police', artist: 'Radiohead', duration: Duration(minutes: 4, seconds: 21)),
      Track(id: 'dm2-3', title: 'Obstacle 1', artist: 'Interpol', duration: Duration(minutes: 4, seconds: 11)),
      Track(id: 'dm2-4', title: 'No Surprises', artist: 'Radiohead', duration: Duration(minutes: 3, seconds: 48)),
      Track(id: 'dm2-5', title: 'Slow Hands', artist: 'Interpol', duration: Duration(minutes: 3, seconds: 4)),
    ],
    'dw': [
      Track(id: 'dw-1', title: 'Midnight City', artist: 'M83', duration: Duration(minutes: 4, seconds: 3)),
      Track(id: 'dw-2', title: 'Redbone', artist: 'Childish Gambino', duration: Duration(minutes: 5, seconds: 27)),
      Track(id: 'dw-3', title: 'Breathe', artist: 'Télépopmusik', duration: Duration(minutes: 4, seconds: 40)),
      Track(id: 'dw-4', title: 'Strobe', artist: 'deadmau5', duration: Duration(minutes: 10, seconds: 33)),
      Track(id: 'dw-5', title: 'Innerbloom', artist: 'RÜFÜS DU SOL', duration: Duration(minutes: 9, seconds: 38)),
    ],
    'rr': [
      Track(id: 'rr-1', title: 'Saturn', artist: 'SZA', duration: Duration(minutes: 3, seconds: 2)),
      Track(id: 'rr-2', title: 'Vampire', artist: 'Olivia Rodrigo', duration: Duration(minutes: 3, seconds: 39)),
      Track(id: 'rr-3', title: 'Paint the Town Red', artist: 'Doja Cat', duration: Duration(minutes: 3, seconds: 51)),
      Track(id: 'rr-4', title: 'Flowers', artist: 'Miley Cyrus', duration: Duration(minutes: 3, seconds: 20)),
      Track(id: 'rr-5', title: 'Snooze', artist: 'SZA', duration: Duration(minutes: 3, seconds: 22)),
    ],
    'lofi': [
      Track(id: 'lofi-1', title: 'Snowfall', artist: 'Øfdream', duration: Duration(minutes: 2, seconds: 14)),
      Track(id: 'lofi-2', title: 'Affection', artist: 'Jinsang', duration: Duration(minutes: 2, seconds: 1)),
      Track(id: 'lofi-3', title: 'Coffee', artist: 'Beabadoobee', duration: Duration(minutes: 3, seconds: 8)),
      Track(id: 'lofi-4', title: 'Sleepless', artist: 'Nymano', duration: Duration(minutes: 2, seconds: 33)),
      Track(id: 'lofi-5', title: 'Reflections', artist: 'Idealism', duration: Duration(minutes: 2, seconds: 45)),
    ],
    'focus': [
      Track(id: 'focus-1', title: 'Weightless', artist: 'Marconi Union', duration: Duration(minutes: 8, seconds: 8)),
      Track(id: 'focus-2', title: 'An Ending (Ascent)', artist: 'Brian Eno', duration: Duration(minutes: 4, seconds: 24)),
      Track(id: 'focus-3', title: 'Avril 14th', artist: 'Aphex Twin', duration: Duration(minutes: 2, seconds: 5)),
      Track(id: 'focus-4', title: 'Saman', artist: 'Ólafur Arnalds', duration: Duration(minutes: 6, seconds: 21)),
      Track(id: 'focus-5', title: 'Nuvole Bianche', artist: 'Ludovico Einaudi', duration: Duration(minutes: 5, seconds: 58)),
    ],
    'run': [
      Track(id: 'run-1', title: 'Titanium', artist: 'David Guetta, Sia', duration: Duration(minutes: 4, seconds: 5)),
      Track(id: 'run-2', title: "Can't Hold Us", artist: 'Macklemore & Ryan Lewis', duration: Duration(minutes: 4, seconds: 18)),
      Track(id: 'run-3', title: 'Stronger', artist: 'Kanye West', duration: Duration(minutes: 5, seconds: 12)),
      Track(id: 'run-4', title: 'Believer', artist: 'Imagine Dragons', duration: Duration(minutes: 3, seconds: 24)),
      Track(id: 'run-5', title: 'Physical', artist: 'Dua Lipa', duration: Duration(minutes: 3, seconds: 13)),
    ],
    'jazz': [
      Track(id: 'jazz-1', title: 'So What', artist: 'Miles Davis', duration: Duration(minutes: 9, seconds: 22)),
      Track(id: 'jazz-2', title: 'Take Five', artist: 'The Dave Brubeck Quartet', duration: Duration(minutes: 5, seconds: 24)),
      Track(id: 'jazz-3', title: 'My Favorite Things', artist: 'John Coltrane', duration: Duration(minutes: 13, seconds: 41)),
      Track(id: 'jazz-4', title: 'Feeling Good', artist: 'Nina Simone', duration: Duration(minutes: 2, seconds: 58)),
      Track(id: 'jazz-5', title: 'Blue in Green', artist: 'Miles Davis', duration: Duration(minutes: 5, seconds: 37)),
    ],
  };
}
