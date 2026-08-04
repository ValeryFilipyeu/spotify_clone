import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/history/repository/local_play_history_repository.dart';
import 'package:spotify_clone/history/repository/play_history_repository.dart';
import 'package:spotify_clone/storage/key_value_store.dart';

/// In-memory KeyValueStore, seedable so a test can start from persisted state --
/// the same test double shape the likes repository's tests use.
class _FakeStore implements KeyValueStore {
  _FakeStore([Map<String, String>? seed]) : _store = {...?seed};

  final Map<String, String> _store;
  int writes = 0;

  @override
  Future<String?> read(String key) async => _store[key];

  @override
  Future<void> write(String key, String value) async {
    writes++;
    _store[key] = value;
  }

  @override
  Future<void> delete(String key) async => _store.remove(key);
}

/// Throws on write, to exercise the "storage failed" path.
class _OfflineStore extends _FakeStore {
  @override
  Future<void> write(String key, String value) async => throw Exception('offline');
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

void main() {
  group('LocalPlayHistoryRepository', () {
    test('an account that has played nothing has no history', () async {
      final repo = LocalPlayHistoryRepository(_FakeStore());

      expect(await repo.fetchRecentIds(_alice), isEmpty);
    });

    test('records most recent first', () async {
      final repo = LocalPlayHistoryRepository(_FakeStore());

      await repo.record(_alice, 'dm1');
      await repo.record(_alice, 'lofi');
      await repo.record(_alice, 'ab1');

      expect(await repo.fetchRecentIds(_alice), ['ab1', 'lofi', 'dm1']);
    });

    // Replaying something you played a while ago should move it up the row, not
    // add a second copy of it.
    test('replaying an item moves it to the front instead of duplicating it', () async {
      final repo = LocalPlayHistoryRepository(_FakeStore());

      await repo.record(_alice, 'dm1');
      await repo.record(_alice, 'lofi');
      await repo.record(_alice, 'dm1');

      expect(await repo.fetchRecentIds(_alice), ['dm1', 'lofi']);
    });

    test('survives a fresh repository instance over the same store', () async {
      final store = _FakeStore();
      await LocalPlayHistoryRepository(store).record(_alice, 'dm1');

      expect(await LocalPlayHistoryRepository(store).fetchRecentIds(_alice), ['dm1']);
    });

    test('keeps accounts apart', () async {
      final store = _FakeStore();
      final repo = LocalPlayHistoryRepository(store);

      await repo.record(_alice, 'dm1');
      await repo.record(_bob, 'jazz');

      expect(await repo.fetchRecentIds(_alice), ['dm1']);
      expect(await repo.fetchRecentIds(_bob), ['jazz']);
    });

    test('forgets the oldest entry past the cap', () async {
      final repo = LocalPlayHistoryRepository(_FakeStore());
      final max = PlayHistoryRepository.maxEntries;

      for (var i = 0; i < max + 3; i++) {
        await repo.record(_alice, 'item-$i');
      }

      final ids = await repo.fetchRecentIds(_alice);
      expect(ids, hasLength(max));
      expect(ids.first, 'item-${max + 2}', reason: 'newest survives');
      expect(ids, isNot(contains('item-0')), reason: 'oldest is gone');
    });

    // Guards a build with a smaller cap reading a list an older build wrote.
    test('caps an over-long stored list on read', () async {
      final max = PlayHistoryRepository.maxEntries;
      final stored = List.generate(max + 5, (i) => '"item-$i"').join(',');
      final repo = LocalPlayHistoryRepository(_FakeStore({'play_history:$_alice': '[$stored]'}));

      expect(await repo.fetchRecentIds(_alice), hasLength(max));
    });

    test('a failed write leaves memory agreeing with storage', () async {
      final repo = LocalPlayHistoryRepository(_OfflineStore());

      await expectLater(repo.record(_alice, 'dm1'), throwsException);

      expect(
        await repo.fetchRecentIds(_alice),
        isEmpty,
        reason: 'nothing was persisted, so nothing may be cached',
      );
    });

    test('reads storage once per account, then serves from memory', () async {
      final store = _FakeStore({'play_history:$_alice': '["dm1"]'});
      final repo = LocalPlayHistoryRepository(store);

      await repo.fetchRecentIds(_alice);
      await repo.fetchRecentIds(_alice);
      await repo.record(_alice, 'lofi');

      expect(store.writes, 1, reason: 'one record, one write');
    });
  });

  group('withMostRecent', () {
    test('prepends something new', () {
      expect(withMostRecent(const ['a', 'b'], 'c'), ['c', 'a', 'b']);
    });

    test('moves something already there', () {
      expect(withMostRecent(const ['a', 'b', 'c'], 'c'), ['c', 'a', 'b']);
    });

    test('is a no-op in effect when it is already first', () {
      expect(withMostRecent(const ['a', 'b'], 'a'), ['a', 'b']);
    });

    test('never grows past the cap', () {
      final full = List.generate(PlayHistoryRepository.maxEntries, (i) => 'item-$i');

      expect(withMostRecent(full, 'new'), hasLength(PlayHistoryRepository.maxEntries));
      expect(withMostRecent(full, 'new').first, 'new');
    });
  });
}
