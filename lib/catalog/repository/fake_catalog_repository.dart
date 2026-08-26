import '../models/catalog_detail.dart';
import '../models/catalog_failure.dart';
import '../models/catalog_item.dart';
import '../models/catalog_section.dart';
import '../models/search_results.dart';
import '../models/track.dart';
import 'catalog_repository.dart';

/// An in-memory catalog with deterministic data, behind a simulated delay so
/// loading states are real and visible.
class FakeCatalogRepository implements CatalogRepository {
  const FakeCatalogRepository();

  @override
  void invalidate() {
    // Nothing is remembered here; caching lives in the decorator above.
  }

  @override
  Future<List<CatalogSection>> fetchHomeSections() async {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    return _sections;
  }

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async {
    if (ids.isEmpty) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final wanted = ids.toSet();
    // Filtered, not looked up per id, so order is kept and duplicates collapse.
    return [
      for (final item in _allItems)
        if (wanted.contains(item.id)) item,
    ];
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) async {
    if (ids.isEmpty) return const [];
    await Future<void>.delayed(const Duration(milliseconds: 400));

    final wanted = ids.toSet();
    return [
      for (final item in _allItems)
        for (final track in _tracksByItemId[item.id] ?? const <Track>[])
          if (wanted.contains(track.id)) TrackHit(track: track, album: item),
    ];
  }

  @override
  Future<SearchResults> search(String query) async {
    // Enough latency that a per-keystroke search visibly thrashes, which is what
    // SearchCubit's debounce is for.
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final needle = query.trim().toLowerCase();
    if (needle.isEmpty) return const SearchResults();

    // Albums/playlists: match on title or subtitle.
    final items = [
      for (final item in _allItems)
        if (item.title.toLowerCase().contains(needle) ||
            item.subtitle.toLowerCase().contains(needle))
          item,
    ];

    // Songs: scan every tracklist, carrying each hit's album for context.
    final tracks = [
      for (final item in _allItems)
        for (final track in _tracksByItemId[item.id] ?? const <Track>[])
          if (track.title.toLowerCase().contains(needle) ||
              track.artist.toLowerCase().contains(needle))
            TrackHit(track: track, album: item),
    ];

    return SearchResults(items: items, tracks: tracks);
  }

  @override
  Future<CatalogDetail> fetchDetail(String itemId) async {
    await Future<void>.delayed(const Duration(milliseconds: 500));
    // The same sections Home uses, so the header matches the card that opened it.
    for (final section in _sections) {
      for (final item in section.items) {
        if (item.id == itemId) {
          return CatalogDetail(item: item, tracks: _tracksByItemId[itemId] ?? const []);
        }
      }
    }
    throw CatalogItemNotFound(itemId);
  }

  // --- Fake data. `static const`, so it is allocated once. ---

  /// Every section's items, flattened and de-duplicated by id. Having the whole
  /// catalog to scan is a luxury of being hardcoded.
  static final List<CatalogItem> _allItems = _buildAllItems();

  static List<CatalogItem> _buildAllItems() {
    final seen = <String>{};
    return [
      for (final section in _sections)
        for (final item in section.items)
          if (seen.add(item.id)) item,
    ];
  }

  /// Deterministic demo artwork: Picsum returns the same photograph per seed for
  /// ever, and sends the CORS header Flutter web needs to decode an image.
  ///
  /// 600px, sized for the largest consumer (the full player); [CoverArt] decodes
  /// down. One url, because Picsum is one host and inventing mirrors that do not
  /// exist would make the fake less like the real thing.
  static List<String> _cover(String id) => ['https://picsum.photos/seed/$id/600/600'];

  // `final`, not `const`: cover urls are computed from each id. Still built once.
  static final List<CatalogSection> _sections = [
    CatalogSection(
      title: 'Made for you',
      items: [
        CatalogItem(
          id: 'dm1',
          title: 'Daily Mix 1',
          subtitle: 'Tame Impala, MGMT & more',
          coverColor: 0xFF1DB954,
          coverUrls: _cover('dm1'),
        ),
        CatalogItem(
          id: 'dm2',
          title: 'Daily Mix 2',
          subtitle: 'Radiohead, Interpol & more',
          coverColor: 0xFFE13300,
          coverUrls: _cover('dm2'),
        ),
        CatalogItem(
          id: 'dw',
          title: 'Discover Weekly',
          subtitle: 'Your weekly mixtape',
          coverColor: 0xFF7358FF,
          coverUrls: _cover('dw'),
        ),
        CatalogItem(
          id: 'rr',
          title: 'Release Radar',
          subtitle: 'New from artists you follow',
          coverColor: 0xFF2D46B9,
          coverUrls: _cover('rr'),
        ),
      ],
    ),
    // "Recently played" is built per account from history now (see HomeView).
    // These keep their place under an honest title: deleting the section would
    // take the four playlists out of Search, Library and detail as well.
    CatalogSection(
      title: 'Popular playlists',
      items: [
        CatalogItem(
          id: 'lofi',
          title: 'Lo-Fi Beats',
          subtitle: 'Chill instrumental hip-hop',
          coverColor: 0xFFBA5D07,
          coverUrls: _cover('lofi'),
        ),
        CatalogItem(
          id: 'focus',
          title: 'Deep Focus',
          subtitle: 'Keep calm and focus',
          coverColor: 0xFF503750,
          coverUrls: _cover('focus'),
        ),
        CatalogItem(
          id: 'run',
          title: 'Running Mix',
          subtitle: 'Uptempo motivation',
          coverColor: 0xFF8D67AB,
          coverUrls: _cover('run'),
        ),
        CatalogItem(
          id: 'jazz',
          title: 'Jazz Vibes',
          subtitle: 'The perfect backdrop',
          coverColor: 0xFF477D95,
          coverUrls: _cover('jazz'),
        ),
      ],
    ),
    CatalogSection(
      title: 'Popular albums',
      items: [
        CatalogItem(
          id: 'ab1',
          title: 'Currents',
          subtitle: 'Tame Impala',
          coverColor: 0xFFE8115B,
          coverUrls: _cover('ab1'),
        ),
        CatalogItem(
          id: 'ab2',
          title: 'In Rainbows',
          subtitle: 'Radiohead',
          coverColor: 0xFF148A08,
          coverUrls: _cover('ab2'),
        ),
        CatalogItem(
          id: 'ab3',
          title: 'Random Access Memories',
          subtitle: 'Daft Punk',
          coverColor: 0xFFDC148C,
          coverUrls: _cover('ab3'),
        ),
        CatalogItem(
          id: 'ab4',
          title: 'Blonde',
          subtitle: 'Frank Ocean',
          coverColor: 0xFF056952,
          coverUrls: _cover('ab4'),
        ),
      ],
    ),
  ];

  // Royalty-free demo audio with each file's real duration (probed with afinfo,
  // floored to whole seconds), so the tracklist, the player and playback agree.
  //
  // Every host must answer a Range request with 206, not just a GET with 200: on
  // web a media element can only seek -- and therefore resume -- if the server
  // honours Range, and a host that answers 200 restarts the track from 0:00.
  // Check `curl -I -H 'Range: bytes=0-1' <url>` before adding one.
  static const List<(String url, Duration duration)> _audioPool = [
    ('https://storage.googleapis.com/exoplayer-test-media-0/play.mp3', Duration(seconds: 59)),
    ('https://www.kozco.com/tech/LRMonoPhase4.mp3', Duration(seconds: 38)),
    ('https://www.kozco.com/tech/32.mp3', Duration(seconds: 32)),
    ('https://www.kozco.com/tech/organfinale.mp3', Duration(seconds: 13)),
    ('https://archive.org/download/testmp3testfile/mpthreetest.mp3', Duration(seconds: 12)),
    (
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-1.mp3',
      Duration(minutes: 6, seconds: 12),
    ),
    (
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-2.mp3',
      Duration(minutes: 7, seconds: 5),
    ),
    (
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-3.mp3',
      Duration(minutes: 5, seconds: 44),
    ),
    (
      'https://www.soundhelix.com/examples/mp3/SoundHelix-Song-5.mp3',
      Duration(minutes: 5, seconds: 53),
    ),
    ('https://www.soundhelix.com/examples/mp3/SoundHelix-Song-7.mp3', Duration(minutes: 7)),
  ];

  static final Map<String, List<Track>> _tracksByItemId = _withCovers(_buildTracks());

  /// Stamps each track with its item's cover, so a queue of bare [Track]s can
  /// show artwork. Applied over the finished map, which keeps the tracklists
  /// below as pure metadata.
  static Map<String, List<Track>> _withCovers(Map<String, List<Track>> byItemId) {
    return {
      for (final entry in byItemId.entries)
        entry.key: [
          for (final track in entry.value)
            Track(
              id: track.id,
              title: track.title,
              artist: track.artist,
              duration: track.duration,
              audioUrl: track.audioUrl,
              coverUrls: _cover(entry.key),
            ),
        ],
    };
  }

  /// Builds the tracklists once. Each playlist starts at a different offset into
  /// [_audioPool], so they do not all share the same few files.
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

  /// Maps (id, title, artist) metadata to [Track]s, assigning audio from
  /// [offset] in [_audioPool] and taking each duration from its file.
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
