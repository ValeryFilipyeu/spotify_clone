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

  // Royalty-free demo audio, paired with each file's REAL duration (probed
  // with afinfo, floored to whole seconds to match how the UI renders m:ss).
  // Using the real length means the tracklist, the Now Playing screen, and
  // actual playback all show the same time -- previously the list showed
  // invented durations (e.g. 4:21) that didn't match the ~39s audio.
  //
  // Ten GENUINELY DIFFERENT recordings from reliable hosts (all verified to
  // return HTTP 200 + an audio content-type and to serve with a browser
  // Referer, so no hotlink blocking).
  static const List<(String url, Duration duration)> _audioPool = [
    ('https://download.samplelib.com/mp3/sample-15s.mp3', Duration(seconds: 19)),
    ('https://storage.googleapis.com/exoplayer-test-media-0/play.mp3', Duration(seconds: 59)),
    ('https://www.kozco.com/tech/LRMonoPhase4.mp3', Duration(seconds: 38)),
    ('https://filesamples.com/samples/audio/mp3/sample1.mp3', Duration(minutes: 2, seconds: 2)),
    ('https://filesamples.com/samples/audio/mp3/sample3.mp3', Duration(minutes: 1, seconds: 45)),
    ('https://archive.org/download/testmp3testfile/mpthreetest.mp3', Duration(seconds: 12)),
    ('https://filesamples.com/samples/audio/mp3/sample2.mp3', Duration(minutes: 3, seconds: 37)),
    ('https://filesamples.com/samples/audio/mp3/sample4.mp3', Duration(minutes: 4, seconds: 4)),
    ('https://www.kozco.com/tech/organfinale.mp3', Duration(seconds: 13)),
    ('https://www.kozco.com/tech/32.mp3', Duration(seconds: 32)),
  ];

  static final Map<String, List<Track>> _tracksByItemId = _buildTracks();

  /// Builds the tracklists once. Each playlist starts at a different offset
  /// into [_audioPool] (via [_playlist]'s `offset`), so different playlists
  /// use different audio rather than all sharing the same few files. Every
  /// track's [Track.duration] is the real length of its assigned audio.
  static Map<String, List<Track>> _buildTracks() {
    return {
      // --- Albums: real tracklists, single album artist ---
      'ab1': _playlist(0, const [
        ('ab1-1', 'Let It Happen', 'Tame Impala'),
        ('ab1-2', 'The Less I Know the Better', 'Tame Impala'),
        ('ab1-3', 'Eventually', 'Tame Impala'),
        ('ab1-4', "Cause I'm a Man", 'Tame Impala'),
        ('ab1-5', 'New Person, Same Old Mistakes', 'Tame Impala'),
      ]),
      'ab2': _playlist(1, const [
        ('ab2-1', '15 Step', 'Radiohead'),
        ('ab2-2', 'Bodysnatchers', 'Radiohead'),
        ('ab2-3', 'Nude', 'Radiohead'),
        ('ab2-4', 'Weird Fishes/Arpeggi', 'Radiohead'),
        ('ab2-5', 'Reckoner', 'Radiohead'),
      ]),
      'ab3': _playlist(2, const [
        ('ab3-1', 'Give Life Back to Music', 'Daft Punk'),
        ('ab3-2', 'Instant Crush', 'Daft Punk'),
        ('ab3-3', 'Get Lucky', 'Daft Punk'),
        ('ab3-4', 'Lose Yourself to Dance', 'Daft Punk'),
        ('ab3-5', "Doin' It Right", 'Daft Punk'),
      ]),
      'ab4': _playlist(3, const [
        ('ab4-1', 'Nikes', 'Frank Ocean'),
        ('ab4-2', 'Ivy', 'Frank Ocean'),
        ('ab4-3', 'Pink + White', 'Frank Ocean'),
        ('ab4-4', 'Solo', 'Frank Ocean'),
        ('ab4-5', 'Self Control', 'Frank Ocean'),
      ]),
      // --- Mixes / playlists: varied artists per track ---
      'dm1': _playlist(4, const [
        ('dm1-1', 'Time to Pretend', 'MGMT'),
        ('dm1-2', 'Feels Like We Only Go Backwards', 'Tame Impala'),
        ('dm1-3', 'Electric Feel', 'MGMT'),
        ('dm1-4', 'The Moment', 'Tame Impala'),
        ('dm1-5', 'Kids', 'MGMT'),
      ]),
      'dm2': _playlist(5, const [
        ('dm2-1', 'Evil', 'Interpol'),
        ('dm2-2', 'Karma Police', 'Radiohead'),
        ('dm2-3', 'Obstacle 1', 'Interpol'),
        ('dm2-4', 'No Surprises', 'Radiohead'),
        ('dm2-5', 'Slow Hands', 'Interpol'),
      ]),
      'dw': _playlist(6, const [
        ('dw-1', 'Midnight City', 'M83'),
        ('dw-2', 'Redbone', 'Childish Gambino'),
        ('dw-3', 'Breathe', 'Télépopmusik'),
        ('dw-4', 'Strobe', 'deadmau5'),
        ('dw-5', 'Innerbloom', 'RÜFÜS DU SOL'),
      ]),
      'rr': _playlist(7, const [
        ('rr-1', 'Saturn', 'SZA'),
        ('rr-2', 'Vampire', 'Olivia Rodrigo'),
        ('rr-3', 'Paint the Town Red', 'Doja Cat'),
        ('rr-4', 'Flowers', 'Miley Cyrus'),
        ('rr-5', 'Snooze', 'SZA'),
      ]),
      'lofi': _playlist(8, const [
        ('lofi-1', 'Snowfall', 'Øfdream'),
        ('lofi-2', 'Affection', 'Jinsang'),
        ('lofi-3', 'Coffee', 'Beabadoobee'),
        ('lofi-4', 'Sleepless', 'Nymano'),
        ('lofi-5', 'Reflections', 'Idealism'),
      ]),
      'focus': _playlist(9, const [
        ('focus-1', 'Weightless', 'Marconi Union'),
        ('focus-2', 'An Ending (Ascent)', 'Brian Eno'),
        ('focus-3', 'Avril 14th', 'Aphex Twin'),
        ('focus-4', 'Saman', 'Ólafur Arnalds'),
        ('focus-5', 'Nuvole Bianche', 'Ludovico Einaudi'),
      ]),
      'run': _playlist(10, const [
        ('run-1', 'Titanium', 'David Guetta, Sia'),
        ('run-2', "Can't Hold Us", 'Macklemore & Ryan Lewis'),
        ('run-3', 'Stronger', 'Kanye West'),
        ('run-4', 'Believer', 'Imagine Dragons'),
        ('run-5', 'Physical', 'Dua Lipa'),
      ]),
      'jazz': _playlist(11, const [
        ('jazz-1', 'So What', 'Miles Davis'),
        ('jazz-2', 'Take Five', 'The Dave Brubeck Quartet'),
        ('jazz-3', 'My Favorite Things', 'John Coltrane'),
        ('jazz-4', 'Feeling Good', 'Nina Simone'),
        ('jazz-5', 'Blue in Green', 'Miles Davis'),
      ]),
    };
  }

  /// Maps a playlist's (id, title, artist) metadata to [Track]s, assigning
  /// audio starting at [offset] in [_audioPool] and taking each track's
  /// duration from its assigned audio file.
  static List<Track> _playlist(int offset, List<(String, String, String)> metas) {
    final tracks = <Track>[];
    for (var i = 0; i < metas.length; i++) {
      final (id, title, artist) = metas[i];
      final (url, duration) = _audioPool[(offset + i) % _audioPool.length];
      tracks.add(Track(id: id, title: title, artist: artist, duration: duration, audioUrl: url));
    }
    return tracks;
  }
}
