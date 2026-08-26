import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/likes/models/liked_id.dart';
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
      await repo.like(_alice, const LikedId.item('ab1'));
      await repo.like(_alice, const LikedId.track('dm2-2'));

      // A brand-new repository (cold cache) reads the same persisted set back.
      final reloaded = LocalLikesRepository(store);
      expect(await reloaded.fetchLikedIds(_alice), {
        const LikedId.item('ab1'),
        const LikedId.track('dm2-2'),
      });

      await reloaded.unlike(_alice, const LikedId.item('ab1'));
      final reloadedAgain = LocalLikesRepository(store);
      expect(await reloadedAgain.fetchLikedIds(_alice), {const LikedId.track('dm2-2')});
    });

    test('keeps each account\'s likes separate', () async {
      final store = _FakeStore();
      final repo = LocalLikesRepository(store);

      await repo.like(_alice, const LikedId.item('ab1'));
      await repo.like(_bob, const LikedId.item('jazz-1'));

      expect(await repo.fetchLikedIds(_alice), {const LikedId.item('ab1')});
      expect(await repo.fetchLikedIds(_bob), {const LikedId.item('jazz-1')});

      // Survives a cold reload, still separated per user.
      final reloaded = LocalLikesRepository(store);
      expect(await reloaded.fetchLikedIds(_alice), {const LikedId.item('ab1')});
      expect(await reloaded.fetchLikedIds(_bob), {const LikedId.item('jazz-1')});
    });

    test('liking an already-liked id does not write again', () async {
      final store = _FakeStore();
      final repo = LocalLikesRepository(store);

      await repo.like(_alice, const LikedId.item('ab1'));
      expect(store.writes, 1);

      await repo.like(_alice, const LikedId.item('ab1')); // no-op
      expect(store.writes, 1);

      await repo.unlike(_alice, const LikedId.item('nope')); // not present -> no-op
      expect(store.writes, 1);
    });

    test('restores a previously persisted set', () async {
      final store = _FakeStore({'liked_ids:$_alice': '["item:ab1","track:jazz-1"]'});
      final repo = LocalLikesRepository(store);

      expect(await repo.fetchLikedIds(_alice), {
        const LikedId.item('ab1'),
        const LikedId.track('jazz-1'),
      });
    });

    test('the same id liked as an item and as a track are two separate likes', () async {
      // The whole reason likes carry a kind. Against the real catalog one id can
      // name a playlist AND a song -- `aA8xa` is both *LATIN ELECTRONIC MUSIC*
      // and *Reflxt Ride Nb. 08*. When likes were bare ids, saving the playlist
      // put the song in the user's library too.
      final store = _FakeStore();
      final repo = LocalLikesRepository(store);

      await repo.like(_alice, const LikedId.item('aA8xa'));

      expect(await repo.fetchLikedIds(_alice), {const LikedId.item('aA8xa')});

      await repo.unlike(_alice, const LikedId.track('aA8xa'));
      expect(await repo.fetchLikedIds(_alice), {
        const LikedId.item('aA8xa'),
      }, reason: 'unliking the song must not remove the playlist');
    });

    test('drops entries left behind by the untyped version', () async {
      // A bare id cannot be resolved to a kind here, and guessing is the bug
      // this format exists to prevent -- see LikedId.tryParse.
      final store = _FakeStore({'liked_ids:$_alice': '["aA8xa","item:keep-me","","nonsense:x"]'});
      final repo = LocalLikesRepository(store);

      expect(await repo.fetchLikedIds(_alice), {const LikedId.item('keep-me')});
    });

    test('a payload that is not JSON reads as an empty library', () async {
      // Rather than throwing on startup, where the only screen that could show
      // the error is the one that needs the answer.
      final repo = LocalLikesRepository(_FakeStore({'liked_ids:$_alice': 'not json'}));

      expect(await repo.fetchLikedIds(_alice), isEmpty);
    });
  });
}
