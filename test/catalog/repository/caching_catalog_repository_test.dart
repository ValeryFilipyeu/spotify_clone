import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/repository/caching_catalog_repository.dart';

/// A source that counts what it was asked for, so a test can assert that a
/// second call never reached it.
class _CountingCatalog implements CatalogRepository {
  @override
  void invalidate() {}

  final List<String> calls = [];

  /// Set to make the next call of that kind fail once.
  final Set<String> failOnce = {};

  Future<T> _record<T>(String call, T Function() result) async {
    calls.add(call);
    if (failOnce.remove(call)) throw Exception('boom');
    return result();
  }

  int countOf(String prefix) => calls.where((c) => c.startsWith(prefix)).length;

  @override
  Future<List<CatalogSection>> fetchHomeSections() => _record('home', () {
    return const [
      CatalogSection(
        title: 'Trending',
        items: [CatalogItem(id: 'a', title: 'A', subtitle: 's', coverColor: 1)],
      ),
    ];
  });

  @override
  Future<CatalogDetail> fetchDetail(String itemId) => _record('detail:$itemId', () {
    return CatalogDetail(
      item: CatalogItem(id: itemId, title: itemId, subtitle: 's', coverColor: 1),
      tracks: const [],
    );
  });

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) =>
      _record('items:${ids.join(",")}', () => const []);

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) =>
      _record('tracks:${ids.join(",")}', () => const []);

  @override
  Future<SearchResults> search(String query) =>
      _record('search:$query', () => const SearchResults());
}

/// A clock the test moves by hand, so a TTL can expire without sleeping.
class _FakeClock {
  DateTime value = DateTime(2026, 1, 1, 12);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

void main() {
  late _CountingCatalog source;
  late _FakeClock clock;

  setUp(() {
    source = _CountingCatalog();
    clock = _FakeClock();
  });

  CachingCatalogRepository build({
    Duration ttl = const Duration(minutes: 5),
    int maxEntries = 64,
  }) => CachingCatalogRepository(source, ttl: ttl, maxEntries: maxEntries, clock: clock.call);

  group('the tab-switch case this exists for', () {
    test('a second load of Home does not reach the network', () async {
      final repository = build();

      final first = await repository.fetchHomeSections();
      final second = await repository.fetchHomeSections();

      expect(source.countOf('home'), 1);
      expect(second, same(first));
    });

    test('it does reach the network again once the answer is stale', () async {
      final repository = build(ttl: const Duration(minutes: 5));

      await repository.fetchHomeSections();
      clock.advance(const Duration(minutes: 5, seconds: 1));
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 2);
    });

    test('an answer just under the ttl is still used', () async {
      final repository = build(ttl: const Duration(minutes: 5));

      await repository.fetchHomeSections();
      clock.advance(const Duration(minutes: 4, seconds: 59));
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 1);
    });
  });

  group('keys', () {
    test('detail is remembered per item', () async {
      final repository = build();

      await repository.fetchDetail('one');
      await repository.fetchDetail('two');
      await repository.fetchDetail('one');

      expect(source.countOf('detail:one'), 1);
      expect(source.countOf('detail:two'), 1);
    });

    test('the same ids in a different order are the same call', () async {
      // Callers build these by iterating a liked or recently-played set, and
      // neither promises an order.
      final repository = build();

      await repository.fetchItemsByIds(['b', 'a']);
      await repository.fetchItemsByIds(['a', 'b']);

      expect(source.countOf('items:'), 1);
    });

    test('a repeated id does not make a different key', () async {
      final repository = build();

      await repository.fetchItemsByIds(['a', 'b']);
      await repository.fetchItemsByIds(['a', 'b', 'a']);

      expect(source.countOf('items:'), 1);
    });

    test('items and tracks with the same ids do not collide', () async {
      final repository = build();

      await repository.fetchItemsByIds(['a']);
      await repository.fetchTracksByIds(['a']);

      expect(source.countOf('items:'), 1);
      expect(source.countOf('tracks:'), 1);
    });

    test('search is remembered per query, ignoring case and surrounding space', () async {
      final repository = build();

      await repository.search('Jazz');
      await repository.search('  jazz ');

      expect(source.countOf('search:'), 1);
    });

    test('search for something else is a different call', () async {
      final repository = build();

      await repository.search('jazz');
      await repository.search('lofi');

      expect(source.countOf('search:'), 2);
    });
  });

  group('what is deliberately not cached', () {
    test('an empty id set is passed straight through', () async {
      // The source answers it without a request; caching it would only occupy
      // an entry something else could use.
      final repository = build(maxEntries: 2);

      await repository.fetchItemsByIds(const []);
      await repository.fetchItemsByIds(const []);

      expect(source.countOf('items:'), 2);
    });

    test('a blank query is passed straight through', () async {
      final repository = build();

      await repository.search('   ');
      await repository.search('');

      expect(source.countOf('search:'), 2);
    });

    test('a failure is not remembered, so a retry actually retries', () async {
      // Caching a failure would turn one dropped connection into a screen that
      // stays broken for the whole TTL and cannot be retried.
      final repository = build();
      source.failOnce.add('home');

      await expectLater(repository.fetchHomeSections(), throwsA(isA<Exception>()));
      final recovered = await repository.fetchHomeSections();

      expect(source.countOf('home'), 2);
      expect(recovered, isNotEmpty);
    });

    test('a failure raises no second, unhandled async error', () async {
      // The bookkeeping that forgets a failed entry chains off the same future
      // the caller holds; both would carry the error, and only one is awaited.
      final repository = build();
      source.failOnce.add('home');

      await expectLater(repository.fetchHomeSections(), throwsA(isA<Exception>()));
      await Future<void>.delayed(Duration.zero);
    });
  });

  group('invalidate', () {
    test('forgets everything, so a pull-to-refresh really refetches', () async {
      // The gesture means "I do not trust what is on screen". Answering it out
      // of the cache being distrusted would make it a no-op.
      final repository = build();
      await repository.fetchHomeSections();
      await repository.fetchDetail('one');

      repository.invalidate();
      await repository.fetchHomeSections();
      await repository.fetchDetail('one');

      expect(source.countOf('home'), 2);
      expect(source.countOf('detail:one'), 2);
    });

    test('leaves the cache usable afterwards', () async {
      final repository = build();
      await repository.fetchHomeSections();
      repository.invalidate();

      await repository.fetchHomeSections();
      await repository.fetchHomeSections();

      expect(source.countOf('home'), 2, reason: 'the post-invalidate answer should be cached too');
    });
  });

  group('concurrency', () {
    test('two callers arriving together share one call', () async {
      final repository = build();

      final results = await Future.wait([
        repository.fetchHomeSections(),
        repository.fetchHomeSections(),
      ]);

      expect(source.countOf('home'), 1);
      expect(results.first, same(results.last));
    });
  });

  group('bounded size', () {
    test('it evicts rather than growing without limit', () async {
      // One entry per playlist opened and one per search typed: unbounded keys.
      final repository = build(maxEntries: 3);

      for (final id in ['a', 'b', 'c', 'd']) {
        await repository.fetchDetail(id);
      }
      // 'a' is the oldest, so it should have been dropped.
      await repository.fetchDetail('a');

      expect(source.countOf('detail:a'), 2);
      expect(source.countOf('detail:d'), 1);
    });

    test('using an entry keeps it from being the next evicted', () async {
      final repository = build(maxEntries: 3);

      await repository.fetchDetail('a');
      await repository.fetchDetail('b');
      await repository.fetchDetail('c');
      await repository.fetchDetail('a'); // a hit: 'a' becomes most recent
      await repository.fetchDetail('d'); // pushes out the oldest, now 'b'

      await repository.fetchDetail('a');
      expect(source.countOf('detail:a'), 1, reason: 'a was used, so it should have survived');

      await repository.fetchDetail('b');
      expect(source.countOf('detail:b'), 2, reason: 'b was the least recently used');
    });
  });
}
