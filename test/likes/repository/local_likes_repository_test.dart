import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
import 'package:spotify_clone/storage/key_value_store.dart';

/// In-memory KeyValueStore that also counts writes, so a test can assert that
/// no-op toggles don't hit storage. Can be seeded to simulate persisted state.
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

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

void main() {
  group('LocalLikesRepository', () {
    test('starts empty when nothing is persisted', () async {
      final repo = LocalLikesRepository(_FakeStore());
      expect(await repo.fetchLikedIds(_alice), isEmpty);
    });

    test('like then unlike persists across a fresh repository instance', () async {
      final store = _FakeStore();

      final repo = LocalLikesRepository(store);
      await repo.like(_alice, 'ab1');
      await repo.like(_alice, 'dm2-2');

      // A brand-new repository (cold cache) reads the same persisted set back.
      final reloaded = LocalLikesRepository(store);
      expect(await reloaded.fetchLikedIds(_alice), {'ab1', 'dm2-2'});

      await reloaded.unlike(_alice, 'ab1');
      final reloadedAgain = LocalLikesRepository(store);
      expect(await reloadedAgain.fetchLikedIds(_alice), {'dm2-2'});
    });

    test('keeps each account\'s likes separate', () async {
      final store = _FakeStore();
      final repo = LocalLikesRepository(store);

      await repo.like(_alice, 'ab1');
      await repo.like(_bob, 'jazz-1');

      expect(await repo.fetchLikedIds(_alice), {'ab1'});
      expect(await repo.fetchLikedIds(_bob), {'jazz-1'});

      // Survives a cold reload, still separated per user.
      final reloaded = LocalLikesRepository(store);
      expect(await reloaded.fetchLikedIds(_alice), {'ab1'});
      expect(await reloaded.fetchLikedIds(_bob), {'jazz-1'});
    });

    test('liking an already-liked id does not write again', () async {
      final store = _FakeStore();
      final repo = LocalLikesRepository(store);

      await repo.like(_alice, 'ab1');
      expect(store.writes, 1);

      await repo.like(_alice, 'ab1'); // no-op
      expect(store.writes, 1);

      await repo.unlike(_alice, 'nope'); // not present -> no-op
      expect(store.writes, 1);
    });

    test('restores a previously persisted set', () async {
      final store = _FakeStore({'liked_ids:$_alice': '["ab1","jazz-1"]'});
      final repo = LocalLikesRepository(store);
      expect(await repo.fetchLikedIds(_alice), {'ab1', 'jazz-1'});
    });
  });
}
