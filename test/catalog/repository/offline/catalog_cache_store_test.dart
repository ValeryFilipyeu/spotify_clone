// Also run compiled to JavaScript in CI: this is where the cache's timestamps
// live, and `DateTime.millisecondsSinceEpoch` is an `int` -- which on the web is
// a double. Reads no fixtures, so it can run there.
@Tags(['web'])
library;

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/repository/offline/catalog_cache_store.dart';

import '../../../helpers/fake_key_value_store.dart';

/// A clock the test moves by hand, so an entry can age without waiting for it.
class _FakeClock {
  DateTime value = DateTime(2026, 8, 19, 9);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

void main() {
  late FakeKeyValueStore backing;
  late _FakeClock clock;

  setUp(() {
    backing = FakeKeyValueStore();
    clock = _FakeClock();
  });

  CatalogCacheStore storeWith({Duration? maxAge, int maxEvictableEntries = 24}) =>
      CatalogCacheStore(
        backing,
        maxAge: maxAge ?? const Duration(days: 7),
        maxEvictableEntries: maxEvictableEntries,
        clock: clock.call,
      );

  group('reading back what was written', () {
    test('returns the payload it was given', () async {
      final store = storeWith();
      await store.write('home', {'sections': [], 'note': 'anything'});

      expect(await store.read('home'), {'sections': [], 'note': 'anything'});
    });

    test('has nothing to say about a key never written', () async {
      expect(await storeWith().read('detail:nope'), isNull);
    });

    test('namespaces its keys so it can share a store with likes and settings', () async {
      final store = storeWith();
      await store.write('home', {'a': 1});

      // Worth pinning rather than assuming: this store is the same
      // shared_preferences instance the liked-id sets and the volume live in, and
      // a bare key called `home` is an accident waiting for a second author.
      expect(backing.keys.every((key) => key.startsWith('catalog_cache:')), isTrue);
    });

    test('a later write replaces the earlier one', () async {
      final store = storeWith();
      await store.write('home', {'v': 'first'});
      await store.write('home', {'v': 'second'});

      expect(await store.read('home'), {'v': 'second'});
    });
  });

  group('entries it refuses to trust', () {
    /// Every case here plants a value the store's own API could not produce,
    /// which is the situation this is actually built for: the code that wrote a
    /// persisted value is not the code reading it. It may be a build from six
    /// months ago, or a process that died mid-write.
    test('treats a payload that is not JSON as a miss, and deletes it', () async {
      backing.values['catalog_cache:home'] = 'not json {';
      final store = storeWith();

      expect(await store.read('home'), isNull);
      // Deleted rather than left: it cannot become readable later, and a key that
      // fails every single read is worse than an absent one.
      expect(backing.keys, isNot(contains('catalog_cache:home')));
    });

    test('treats a payload from an older schema as a miss', () async {
      backing.values['catalog_cache:home'] = jsonEncode({
        'v': CatalogCacheStore.schemaVersion - 1,
        'at': clock.value.millisecondsSinceEpoch,
        'data': {'sections': []},
      });

      // The whole reason the version is in there. An app update that renames a
      // field would otherwise read yesterday's payload with today's decoder and
      // either throw or, worse, succeed with the wrong answer.
      expect(await storeWith().read('home'), isNull);
      expect(backing.keys, isNot(contains('catalog_cache:home')));
    });

    test('treats an entry with no usable timestamp as a miss', () async {
      backing.values['catalog_cache:home'] = jsonEncode({
        'v': CatalogCacheStore.schemaVersion,
        'at': 'yesterday',
        'data': {'sections': []},
      });

      // Without a readable timestamp there is no way to tell whether it is a
      // minute old or a year, and maxAge cannot be enforced on it at all.
      expect(await storeWith().read('home'), isNull);
    });

    test('treats a payload that is not an object as a miss', () async {
      backing.values['catalog_cache:home'] = jsonEncode({
        'v': CatalogCacheStore.schemaVersion,
        'at': clock.value.millisecondsSinceEpoch,
        'data': ['a', 'list'],
      });

      expect(await storeWith().read('home'), isNull);
    });

    test('reads nothing and throws nothing when the whole envelope is a bare string', () async {
      backing.values['catalog_cache:home'] = jsonEncode('surprise');
      expect(await storeWith().read('home'), isNull);
    });
  });

  group('ageing out', () {
    test('serves an entry right up to the limit', () async {
      final store = storeWith(maxAge: const Duration(days: 7));
      await store.write('home', {'a': 1});

      clock.advance(const Duration(days: 7));
      expect(await store.read('home'), isNotNull);
    });

    test('stops serving it past the limit, and deletes it', () async {
      final store = storeWith(maxAge: const Duration(days: 7));
      await store.write('home', {'a': 1});

      clock.advance(const Duration(days: 7, seconds: 1));
      expect(await store.read('home'), isNull);
      expect(backing.keys, isNot(contains('catalog_cache:home')));
    });

    test('a rewrite resets the clock on it', () async {
      final store = storeWith(maxAge: const Duration(hours: 1));
      await store.write('home', {'a': 1});

      clock.advance(const Duration(minutes: 55));
      await store.write('home', {'a': 2});
      clock.advance(const Duration(minutes: 55));

      expect(await store.read('home'), {'a': 2}, reason: 'the second write is 55 minutes old');
    });
  });

  group('the cap on evictable entries', () {
    test('drops the oldest once there are more than the cap', () async {
      final store = storeWith(maxEvictableEntries: 2);
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.write('detail:b', {'n': 2}, evictable: true);
      await store.write('detail:c', {'n': 3}, evictable: true);

      expect(await store.read('detail:a'), isNull);
      expect(await store.read('detail:b'), isNotNull);
      expect(await store.read('detail:c'), isNotNull);
    });

    test('re-writing an entry moves it out of the firing line', () async {
      final store = storeWith(maxEvictableEntries: 2);
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.write('detail:b', {'n': 2}, evictable: true);
      // `a` was written first, so it is next to go -- until it is written again.
      await store.write('detail:a', {'n': 3}, evictable: true);
      await store.write('detail:c', {'n': 4}, evictable: true);

      expect(await store.read('detail:b'), isNull);
      expect(await store.read('detail:a'), {'n': 3});
      expect(await store.read('detail:c'), isNotNull);
    });

    test('leaves the fixed keys out of it entirely', () async {
      // The point of the distinction. Home and the two id-keyed collections are
      // three keys and can never be more, and they are the entries most worth
      // keeping -- counting them alongside the albums would let a long browse
      // evict the home screen.
      final store = storeWith(maxEvictableEntries: 2);
      await store.write('home', {'n': 0});
      await store.write('items', {'n': 0});
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.write('detail:b', {'n': 2}, evictable: true);
      await store.write('detail:c', {'n': 3}, evictable: true);

      expect(await store.read('home'), isNotNull);
      expect(await store.read('items'), isNotNull);
      expect(await store.read('detail:a'), isNull, reason: 'the cap still applies to albums');
    });

    test('a read does not reorder anything', () async {
      // Recency here is by write, not by read, and this is the test that says so
      // out loud. Bumping the order on a read would mean a disk write every time
      // the cache is consulted -- a strange price for having avoided a network
      // call.
      final store = storeWith(maxEvictableEntries: 2);
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.write('detail:b', {'n': 2}, evictable: true);

      backing.clearLog();
      await store.read('detail:a');
      expect(backing.writes, isEmpty);

      await store.write('detail:c', {'n': 3}, evictable: true);
      expect(await store.read('detail:a'), isNull, reason: 'reading it did not save it');
    });

    test('survives an index it cannot read', () async {
      backing.values['catalog_cache:index'] = 'not json';
      final store = storeWith(maxEvictableEntries: 2);

      // A lost index costs the eviction order, not the entries: worst case a few
      // stale albums outlive their turn until they age out.
      await store.write('detail:a', {'n': 1}, evictable: true);
      expect(await store.read('detail:a'), isNotNull);
    });
  });

  group('remove', () {
    test('forgets the entry', () async {
      final store = storeWith();
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.remove('detail:a');

      expect(await store.read('detail:a'), isNull);
    });

    test('gives up its place in the order, not just its contents', () async {
      // The *newest* entry is removed here, and that is the whole trick. An index
      // that keeps a phantom entry for a deleted key still passes the obvious
      // version of this test: the phantom sits at the front, so it is the first
      // thing evicted and absorbs exactly one slot without anyone noticing.
      // Removing from the back leaves the phantom behind a live entry, and now the
      // live one is what gets thrown away.
      final store = storeWith(maxEvictableEntries: 2);
      await store.write('detail:a', {'n': 1}, evictable: true);
      await store.write('detail:b', {'n': 2}, evictable: true);
      await store.remove('detail:b');
      await store.write('detail:c', {'n': 3}, evictable: true);

      expect(await store.read('detail:a'), isNotNull, reason: 'only two are being kept');
      expect(await store.read('detail:c'), isNotNull);
    });
  });
}
