// Also run compiled to JavaScript in CI. Nothing here touches a platform channel
// -- the store is handed an in-memory map -- and the web is a place this layer
// genuinely matters, since browser storage is where a web build's cache lands.
@Tags(['web'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/caching_catalog_repository.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_cache_store.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_catalog_repository.dart';
import 'package:spotify_clone/network/api_failure.dart';

import '../../../helpers/fake_key_value_store.dart';

final _uri = Uri.parse('https://api.audius.co/v1/playlists/trending');

/// A catalog that answers from fields and records what it was asked.
class _FakeCatalog implements CatalogRepository {
  final List<String> calls = [];
  int invalidations = 0;

  /// Thrown by every fetch while it is set. One field rather than one per method
  /// because each test drives a single call.
  Object? failure;

  List<CatalogSection> sections = const [
    CatalogSection(
      title: 'Trending',
      items: [CatalogItem(id: 'p1', title: 'One', subtitle: 'first', coverColor: 0xFF001122)],
    ),
  ];

  /// Everything the catalog knows about, so the bulk lookups can behave like a
  /// real source and answer with the subset they recognise.
  Map<String, CatalogItem> knownItems = const {
    'p1': CatalogItem(id: 'p1', title: 'One', subtitle: 'first', coverColor: 1),
    'p2': CatalogItem(id: 'p2', title: 'Two', subtitle: 'second', coverColor: 2),
    'p3': CatalogItem(id: 'p3', title: 'Three', subtitle: 'third', coverColor: 3),
  };

  Map<String, TrackHit> knownHits = const {
    't1': TrackHit(
      track: Track(
        id: 't1',
        title: 'Track One',
        artist: 'A',
        duration: Duration(minutes: 3),
        audioUrl: 'stream/t1',
      ),
      album: CatalogItem(id: 't1', title: 'Track One', subtitle: 'A', coverColor: 4),
    ),
    't2': TrackHit(
      track: Track(
        id: 't2',
        title: 'Track Two',
        artist: 'B',
        duration: Duration(minutes: 4),
        audioUrl: 'stream/t2',
      ),
      album: CatalogItem(id: 't2', title: 'Track Two', subtitle: 'B', coverColor: 5),
    ),
  };

  int countOf(String prefix) => calls.where((call) => call.startsWith(prefix)).length;

  Future<T> _answer<T>(String call, T Function() value) async {
    calls.add(call);
    final error = failure;
    if (error != null) throw error;
    return value();
  }

  @override
  Future<List<CatalogSection>> fetchHomeSections() => _answer('home', () => sections);

  @override
  Future<CatalogDetail> fetchDetail(String itemId) =>
      _answer('detail:$itemId', () => detailFor(itemId));

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) => _answer(
    'items:${(ids.toList()..sort()).join(",")}',
    () => [for (final id in ids) ?knownItems[id]],
  );

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) => _answer(
    'tracks:${(ids.toList()..sort()).join(",")}',
    () => [for (final id in ids) ?knownHits[id]],
  );

  @override
  Future<SearchResults> search(String query) =>
      _answer('search:$query', () => const SearchResults());

  @override
  void invalidate() => invalidations++;

  /// A distinct album per id, so a test can tell a saved page apart from the one
  /// that was asked for.
  static CatalogDetail detailFor(String itemId) => CatalogDetail(
    item: CatalogItem(id: itemId, title: 'Album $itemId', subtitle: 's', coverColor: 7),
    tracks: [
      Track(
        id: '$itemId-t1',
        title: 'First',
        artist: 'A',
        duration: const Duration(minutes: 2),
        audioUrl: 'stream/$itemId',
      ),
    ],
  );
}

class _FakeClock {
  DateTime value = DateTime(2026, 8, 19, 9);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

void main() {
  late _FakeCatalog source;
  late FakeKeyValueStore backing;
  late _FakeClock clock;

  setUp(() {
    source = _FakeCatalog();
    backing = FakeKeyValueStore();
    clock = _FakeClock();
  });

  /// The breaker is off by default here, so that a test about falling back is not
  /// also a test about short-circuiting. It has its own group below.
  OfflineCatalogRepository build({
    Duration retryAfter = Duration.zero,
    Duration maxAge = const Duration(days: 7),
    int maxEntities = 64,
  }) {
    final repository = OfflineCatalogRepository(
      source,
      store: CatalogCacheStore(backing, maxAge: maxAge, clock: clock.call),
      retryAfter: retryAfter,
      maxEntities: maxEntities,
      clock: clock.call,
    );
    addTearDown(repository.close);
    return repository;
  }

  /// Fetches once with the network working, which is how anything gets saved in
  /// the first place, then breaks it.
  Future<OfflineCatalogRepository> primed({
    Duration retryAfter = Duration.zero,
    Duration maxAge = const Duration(days: 7),
  }) async {
    final repository = build(retryAfter: retryAfter, maxAge: maxAge);
    await repository.fetchHomeSections();
    source.failure = NetworkUnreachable(_uri, 'down');
    return repository;
  }

  group('home sections', () {
    test('goes to the network and keeps what it got', () async {
      final repository = build();

      expect(await repository.fetchHomeSections(), source.sections);
      expect(source.countOf('home'), 1);
      expect(backing.keys, contains('catalog_cache:home'));
    });

    test('serves the saved copy when the catalog cannot be reached', () async {
      final saved = source.sections;
      final repository = await primed();

      expect(await repository.fetchHomeSections(), saved);
      expect(source.countOf('home'), 2, reason: 'the network is asked first, every time');
    });

    test('asks the network first even with a perfectly good saved copy', () async {
      // The mistake this layer would be easiest to write: a read-through cache
      // that shows yesterday's home screen to someone with five bars of signal.
      final repository = build();
      await repository.fetchHomeSections();

      source.sections = const [CatalogSection(title: 'Fresh', items: [])];
      expect(await repository.fetchHomeSections(), source.sections);
    });

    test('lets the failure stand when nothing was ever saved', () async {
      final repository = build();
      source.failure = NetworkUnreachable(_uri, 'down');

      await expectLater(repository.fetchHomeSections(), throwsA(isA<NetworkUnreachable>()));
    });

    test('does not serve a saved copy with no rows in it', () async {
      // An empty list is not an answer: Home would take it for a successful load
      // of an empty catalog and draw a blank screen with no explanation, where the
      // failure at least offers a retry.
      source.sections = const [];
      final repository = build();
      await expectLater(repository.fetchHomeSections(), completion(isEmpty));

      source.failure = NetworkUnreachable(_uri, 'down');
      await expectLater(repository.fetchHomeSections(), throwsA(isA<NetworkUnreachable>()));
    });
  });

  group('which failures the cache is allowed to answer', () {
    /// Each case saves a copy first, then fails in one specific way. The split is
    /// the point of the class: too eager and a deleted album keeps reappearing,
    /// too strict and a train journey is four error screens.
    Future<void> expectServed(Object failure) async {
      final repository = build();
      final saved = await repository.fetchHomeSections();
      source.failure = failure;

      expect(await repository.fetchHomeSections(), saved);
      expect(repository.isOffline, isTrue);
    }

    Future<void> expectRethrown(Object failure) async {
      final repository = build();
      await repository.fetchHomeSections();
      source.failure = failure;

      await expectLater(repository.fetchHomeSections(), throwsA(same(failure)));
      expect(repository.isOffline, isFalse, reason: 'the catalog answered; it is not unreachable');
    }

    test('an unreachable server is answered from the cache', () async {
      await expectServed(NetworkUnreachable(_uri, 'no route to host'));
    });

    test('a timeout is answered from the cache', () async {
      await expectServed(RequestTimeout(_uri, const Duration(seconds: 10)));
    });

    test('a 503 is answered from the cache', () async {
      // Reached, but momentarily unable to answer -- which from here is the same
      // situation as unreachable.
      await expectServed(HttpErrorStatus(_uri, 503, 'upstream unavailable'));
    });

    test('a 429 is answered from the cache', () async {
      await expectServed(HttpErrorStatus(_uri, 429, 'slow down'));
    });

    test('a 404 is not', () async {
      // A real answer, and the truth is that the thing is gone. Serving a saved
      // copy over the top of it hides the only useful fact in the exchange.
      await expectRethrown(HttpErrorStatus(_uri, 404, null));
    });

    test('a 400 is not', () async {
      await expectRethrown(HttpErrorStatus(_uri, 400, 'invalid playlistId'));
    });

    test('a response we cannot parse is not', () async {
      // Retrying will not fix it and stale data would hide the parsing bug behind
      // a screen that looks fine.
      await expectRethrown(MalformedResponse(_uri, 'expected an object'));
    });

    test('anything that is not an ApiFailure at all is not', () async {
      // A bug in the layer below is not evidence about the network, and a cache
      // that papers over one is a cache that hides it for a week.
      await expectRethrown(StateError('bug'));
    });
  });

  group('album detail', () {
    test('keeps each album under its own key', () async {
      final repository = build();
      await repository.fetchDetail('a');
      await repository.fetchDetail('b');
      source.failure = NetworkUnreachable(_uri, 'down');

      expect(await repository.fetchDetail('a'), _FakeCatalog.detailFor('a'));
      expect(await repository.fetchDetail('b'), _FakeCatalog.detailFor('b'));
    });

    test('does not answer for an album it never saved', () async {
      final repository = await primed();

      await expectLater(repository.fetchDetail('never-opened'), throwsA(isA<NetworkUnreachable>()));
    });

    test('does not paper over an album that is genuinely gone', () async {
      final repository = build();
      await repository.fetchDetail('a');
      source.failure = const CatalogItemNotFound('a');

      // The one case where the cache holds the answer and must not give it: the
      // album was deleted, and its saved copy is precisely the wrong thing to show.
      await expectLater(repository.fetchDetail('a'), throwsA(isA<CatalogItemNotFound>()));
    });
  });

  group('the id-keyed collections', () {
    test('remembers each entity, so a later call for a subset is answerable', () async {
      final repository = build();
      await repository.fetchItemsByIds({'p1', 'p2', 'p3'});
      source.failure = NetworkUnreachable(_uri, 'down');

      // A different question entirely -- caching the *call* would have missed.
      final answer = await repository.fetchItemsByIds({'p2'});
      expect(answer, [source.knownItems['p2']]);
    });

    test('merges what each caller resolved instead of replacing it', () async {
      // Home resolves a couple of recently-played ids and Library resolves
      // everything liked. Replacing would let each wipe the other's work on every
      // visit, which is the bug this is written to prevent.
      final repository = build();
      await repository.fetchItemsByIds({'p1'});
      await repository.fetchItemsByIds({'p2'});
      source.failure = NetworkUnreachable(_uri, 'down');

      final answer = await repository.fetchItemsByIds({'p1', 'p2'});
      expect(answer.map((item) => item.id), unorderedEquals(['p1', 'p2']));
    });

    test('answers with the ids it has and drops the rest', () async {
      final repository = build();
      await repository.fetchItemsByIds({'p1'});
      source.failure = NetworkUnreachable(_uri, 'down');

      // Half a Library is a valid response to this interface -- both bulk methods
      // already promise to drop ids they have nothing for -- and a better one than
      // an error page.
      expect(await repository.fetchItemsByIds({'p1', 'p3'}), [source.knownItems['p1']]);
    });

    test('lets the failure stand when it holds none of the ids', () async {
      final repository = build();
      await repository.fetchItemsByIds({'p1'});
      source.failure = NetworkUnreachable(_uri, 'down');

      // Not an empty list: "we could not ask" and "there is nothing" look
      // identical on screen and mean opposite things.
      await expectLater(repository.fetchItemsByIds({'p3'}), throwsA(isA<NetworkUnreachable>()));
    });

    test('drops the least recently written once it is full', () async {
      final repository = build(maxEntities: 2);
      await repository.fetchItemsByIds({'p1'});
      await repository.fetchItemsByIds({'p2'});
      await repository.fetchItemsByIds({'p3'});
      source.failure = NetworkUnreachable(_uri, 'down');

      await expectLater(repository.fetchItemsByIds({'p1'}), throwsA(isA<NetworkUnreachable>()));
      expect(await repository.fetchItemsByIds({'p2', 'p3'}), hasLength(2));
    });

    test('track hits get the same treatment, keyed by track id', () async {
      final repository = build();
      await repository.fetchTracksByIds({'t1', 't2'});
      source.failure = NetworkUnreachable(_uri, 'down');

      expect(await repository.fetchTracksByIds({'t2'}), [source.knownHits['t2']]);
    });

    test('an empty request is passed straight through and saves nothing', () async {
      final repository = build();

      expect(await repository.fetchItemsByIds(const []), isEmpty);
      expect(source.countOf('items'), 1, reason: 'the interface says to tolerate it, not skip it');
      expect(backing.writes, isEmpty, reason: 'no request was made, so nothing was learned');
    });
  });

  group('search', () {
    test('is never saved', () async {
      final repository = build();
      await repository.search('lofi');

      expect(backing.writes, isEmpty);
    });

    test('fails rather than pretending, and reports why', () async {
      final repository = await primed();

      await expectLater(repository.search('lofi'), throwsA(isA<NetworkUnreachable>()));
      // Nothing to serve -- a search asks about the whole catalog, which a few
      // saved pages cannot answer -- but the banner can still explain itself.
      expect(repository.isOffline, isTrue);
    });

    test('clears the offline state when it is the first thing to get through', () async {
      final repository = await primed();
      await expectLater(repository.fetchHomeSections(), completion(isNotEmpty));
      expect(repository.isOffline, isTrue);

      source.failure = null;
      await repository.search('lofi');
      expect(repository.isOffline, isFalse);
    });

    test('a blank query says nothing about reachability either way', () async {
      final repository = await primed();
      await repository.fetchHomeSections();
      expect(repository.isOffline, isTrue);

      // Answered without a request, so it is not evidence of anything.
      source.failure = null;
      await repository.search('   ');
      expect(repository.isOffline, isTrue);
    });
  });

  group('the retry breaker', () {
    test('a second read within the window does not wait for the network again', () async {
      final repository = await primed(retryAfter: const Duration(seconds: 20));
      await repository.fetchHomeSections();
      final asked = source.countOf('home');

      await repository.fetchHomeSections();
      // The whole point: without this, every screen opened while offline waits out
      // its own ten-second timeout before falling back.
      expect(source.countOf('home'), asked);
    });

    test('tries again once the window has passed', () async {
      final repository = await primed(retryAfter: const Duration(seconds: 20));
      await repository.fetchHomeSections();
      final asked = source.countOf('home');

      clock.advance(const Duration(seconds: 21));
      await repository.fetchHomeSections();
      expect(source.countOf('home'), asked + 1);
    });

    test('does not short-circuit a read it has no answer for', () async {
      final repository = await primed(retryAfter: const Duration(seconds: 20));
      await repository.fetchHomeSections();

      // Skipping the attempt here would turn "probably offline" into a guaranteed
      // error for every album not opened before.
      await expectLater(repository.fetchDetail('new'), throwsA(isA<NetworkUnreachable>()));
      expect(source.countOf('detail:new'), 1);
    });

    test('a success closes it', () async {
      final repository = await primed(retryAfter: const Duration(seconds: 20));
      await repository.fetchHomeSections();

      source.failure = null;
      await repository.fetchDetail('a');

      final asked = source.countOf('home');
      await repository.fetchHomeSections();
      expect(source.countOf('home'), asked + 1);
    });

    test('a pull-to-refresh closes it early', () async {
      final repository = await primed(retryAfter: const Duration(seconds: 20));
      await repository.fetchHomeSections();
      final asked = source.countOf('home');

      // Someone explicitly asking to try the network outranks a verdict reached
      // fifteen seconds ago.
      repository.invalidate();
      await repository.fetchHomeSections();
      expect(source.countOf('home'), asked + 1);
    });
  });

  group('invalidate', () {
    test('passes the gesture down the chain', () async {
      build().invalidate();
      expect(source.invalidations, 1);
    });

    test('leaves the saved copy alone', () async {
      // Deliberately backwards from what it does to the memory cache. A refresh is
      // most likely to be used when the screen looks wrong, which is most likely to
      // be when the connection is bad -- so wiping the fallback deletes the offline
      // library at the exact moment it is needed.
      final repository = await primed();
      repository.invalidate();

      expect(await repository.fetchHomeSections(), isNotEmpty);
    });
  });

  group('the offline signal', () {
    test('starts online and says nothing', () async {
      final repository = build();
      expect(repository.isOffline, isFalse);
    });

    test('reports one change, not one per request', () async {
      final repository = await primed();
      final seen = <bool>[];
      repository.changes.listen(seen.add);

      await repository.fetchHomeSections();
      await repository.fetchHomeSections();
      await repository.fetchHomeSections();
      await pumpEventQueue();

      // A screen making four calls while the network is down is one event. Without
      // the dedupe, a banner watching this rebuilds on every request.
      expect(seen, [true]);
    });

    test('flips back on the next success', () async {
      final repository = await primed();
      final seen = <bool>[];
      repository.changes.listen(seen.add);

      await repository.fetchHomeSections();
      source.failure = null;
      await repository.fetchHomeSections();
      await pumpEventQueue();

      expect(seen, [true, false]);
      expect(repository.isOffline, isFalse);
    });
  });

  group('when the cache itself is the problem', () {
    test('a fetch that worked is not failed by a write that did not', () async {
      final repository = build();
      backing.failWrites = true;

      // A full disk is a reason to have no cache, not a reason for the screen to
      // show an error over data it is holding.
      expect(await repository.fetchHomeSections(), source.sections);
    });

    test('an unreadable saved payload leaves the real error intact', () async {
      final repository = await primed();
      // Stamped with *now*, which the first version of this test got wrong: with a
      // timestamp of 0 the store aged the entry out before the codec ever saw it,
      // so the test passed while proving nothing about a decode failure.
      backing.values['catalog_cache:home'] = jsonEncode({
        'v': CatalogCacheStore.schemaVersion,
        'at': clock.value.millisecondsSinceEpoch,
        'data': {
          'sections': [
            {'nope': 1},
          ],
        },
      });

      // Specifically not a JsonFormatError: the caller is handling a network
      // problem it can explain, and a parse error from a layer it does not know
      // exists is noise on top of it.
      await expectLater(repository.fetchHomeSections(), throwsA(isA<NetworkUnreachable>()));
    });

    test('a saved copy past its age is not served', () async {
      final repository = await primed(maxAge: const Duration(days: 7));

      clock.advance(const Duration(days: 8));
      await expectLater(repository.fetchHomeSections(), throwsA(isA<NetworkUnreachable>()));
    });
  });

  group('in the chain the app actually builds', () {
    /// Everything above tests this layer against the source directly. The app puts
    /// the in-memory cache in between, and *which side* of it this sits on is a
    /// decision main() makes and nothing else checks.
    const ttl = Duration(minutes: 5);

    OfflineCatalogRepository buildChain() {
      final repository = OfflineCatalogRepository(
        CachingCatalogRepository(source, ttl: ttl, clock: clock.call),
        store: CatalogCacheStore(backing, clock: clock.call),
        retryAfter: Duration.zero,
        clock: clock.call,
      );
      addTearDown(repository.close);
      return repository;
    }

    test('a warm memory cache hides an outage completely', () async {
      // Found by writing the test below and having it fail. While the layer
      // underneath still has an answer, nothing here is asked and nothing here
      // learns anything -- the app carries on with data that is under five minutes
      // old and never mentions the network, which is the right outcome and not one
      // this class arranges.
      final repository = buildChain();
      final fresh = await repository.fetchHomeSections();
      source.failure = NetworkUnreachable(_uri, 'down');

      expect(await repository.fetchHomeSections(), fresh);
      expect(source.countOf('home'), 1);
      expect(repository.isOffline, isFalse, reason: 'nothing has failed yet, as far as this knows');
    });

    test('once that lapses, a fallback is remembered by nobody and each read retries', () async {
      // The reason this layer is on the outside. Underneath the memory cache, the
      // saved copy would be stored as that cache's own answer for a full TTL, and
      // the app would come back online on a five-minute timer rather than on the
      // facts.
      final repository = buildChain();
      await repository.fetchHomeSections();
      clock.advance(ttl + const Duration(minutes: 1));
      source.failure = NetworkUnreachable(_uri, 'down');

      await repository.fetchHomeSections();
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 3, reason: 'one good fetch and two genuine retries');
    });

    test('the chain main() ships really does have this layer on the outside', () async {
      // buildChain above spells the order out, which documents it without pinning
      // the one the app runs. This uses the factory main() calls, and detects the
      // order by the one thing that differs without any clock involved: from the
      // outside, a memory-cache *hit* still passes through here and is saved again.
      // From the inside it would never be seen, and there would be one write.
      final repository = OfflineCatalogRepository.chain(
        source,
        store: CatalogCacheStore(backing, clock: clock.call),
      );
      addTearDown(repository.close);

      await repository.fetchHomeSections();
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 1, reason: 'the memory cache answered the second read');
      expect(
        backing.writes.where((key) => key.endsWith('home')),
        hasLength(2),
        reason: 'and this layer saw both, which is only true from the outside',
      );
    });

    test('a good answer is still remembered by the layer whose job that is', () async {
      final repository = buildChain();
      await repository.fetchHomeSections();
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 1);
    });

    test('a refresh reaches all the way to the bottom', () async {
      final repository = buildChain();
      await repository.fetchHomeSections();

      repository.invalidate();
      await repository.fetchHomeSections();

      // Two layers of forwarding: this one passes the gesture to the memory cache,
      // which clears itself and passes it on again.
      expect(source.countOf('home'), 2);
      expect(source.invalidations, 1);
    });
  });
}
