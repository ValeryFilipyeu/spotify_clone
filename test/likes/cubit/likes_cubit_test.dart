import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/cubit/likes_state.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/likes/models/liked_id.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';

/// In-memory, per-user LikesRepository. [failMutations] makes like/unlike throw,
/// to exercise the cubit's optimistic-then-revert path.
class _FakeLikesRepository implements LikesRepository {
  _FakeLikesRepository({Map<String, Set<LikedId>>? seed, this.failMutations = false})
    : _byUser = {
        for (final e in (seed ?? const {}).entries) e.key: {...e.value},
      };

  final Map<String, Set<LikedId>> _byUser;
  final bool failMutations;

  Set<LikedId> _for(String userId) => _byUser.putIfAbsent(userId, () => <LikedId>{});

  @override
  Future<Set<LikedId>> fetchLikedIds(String userId) async => {..._for(userId)};

  @override
  Future<void> like(String userId, LikedId id) async {
    if (failMutations) throw Exception('offline');
    _for(userId).add(id);
  }

  @override
  Future<void> unlike(String userId, LikedId id) async {
    if (failMutations) throw Exception('offline');
    _for(userId).remove(id);
  }
}

/// Records what the catalog was asked about, so a test can show that liking
/// something fetches it -- which is the only thing that puts it within reach of
/// the offline cache.
class _RecordingCatalog extends FakeCatalogRepository {
  _RecordingCatalog();

  final List<Set<String>> itemIdsAsked = [];
  final List<Set<String>> trackIdsAsked = [];

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) {
    itemIdsAsked.add(ids.toSet());
    return super.fetchItemsByIds(ids);
  }

  @override
  Future<List<TrackHit>> fetchTracksByIds(Iterable<String> ids) {
    trackIdsAsked.add(ids.toSet());
    return super.fetchTracksByIds(ids);
  }
}

/// A catalog that is down, for the "a like still succeeds" case.
class _DownCatalog extends FakeCatalogRepository {
  const _DownCatalog();

  @override
  Future<List<CatalogItem>> fetchItemsByIds(Iterable<String> ids) async =>
      throw Exception('offline');
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

/// Yields to the event loop so a stream event and the async load it triggers
/// both complete.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('LikesCubit', () {
    test('initial state is loading with no likes', () {
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(),
        authStateChanges: Stream.value(null),
      );
      expect(cubit.state, const LikesState());
      expect(cubit.state.status, LikesStatus.loading);
      cubit.close();
    });

    test("loads the signed-in account's likes on sign-in", () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(
          seed: {
            _alice: {const LikedId.item('ab1'), const LikedId.track('dm2-2')},
          },
        ),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();

      expect(cubit.state.status, LikesStatus.ready);
      expect(cubit.state.likedIds, {const LikedId.item('ab1'), const LikedId.track('dm2-2')});
    });

    test('clears likes on sign-out', () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(
          seed: {
            _alice: {const LikedId.item('ab1')},
          },
        ),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      expect(cubit.state.likedIds, {const LikedId.item('ab1')});

      auth.add(null);
      await _settle();
      expect(cubit.state.status, LikesStatus.ready);
      expect(cubit.state.likedIds, isEmpty);
    });

    test("switching accounts loads the new account's likes, not the old", () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(
          seed: {
            _alice: {const LikedId.item('ab1')},
            _bob: {const LikedId.item('jazz-1')},
          },
        ),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      expect(cubit.state.likedIds, {const LikedId.item('ab1')});

      auth.add(const AppUser(_bob));
      await _settle();
      expect(cubit.state.likedIds, {const LikedId.item('jazz-1')});
    });

    test('toggle adds then removes for the signed-in user, persisting each change', () async {
      final auth = StreamController<AppUser?>();
      final repo = _FakeLikesRepository();
      final cubit = LikesCubit(repository: repo, authStateChanges: auth.stream);
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();

      await cubit.toggle(const LikedId.item('ab1'));
      expect(cubit.state.likedIds, {const LikedId.item('ab1')});
      expect(await repo.fetchLikedIds(_alice), {const LikedId.item('ab1')});

      await cubit.toggle(const LikedId.item('ab1'));
      expect(cubit.state.likedIds, isEmpty);
      expect(await repo.fetchLikedIds(_alice), isEmpty);
    });

    test('toggle before sign-in is a no-op', () async {
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(),
        authStateChanges: Stream.value(null),
      );
      addTearDown(cubit.close);

      await cubit.toggle(const LikedId.item('ab1'));
      expect(cubit.state.likedIds, isEmpty);
    });

    test('reverts the optimistic update when persistence fails', () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(failMutations: true),
        authStateChanges: auth.stream,
      );
      final states = <LikesState>[];
      final sub = cubit.stream.listen(states.add);
      addTearDown(() {
        sub.cancel();
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();

      await cubit.toggle(const LikedId.item('ab1'));

      // Ends reverted...
      expect(cubit.state.likedIds, isEmpty);
      // ...but showed the optimistic "liked" state at some point.
      expect(states.any((s) => s.likedIds.contains(const LikedId.item('ab1'))), isTrue);
    });
  });

  group('LikesCubit keeping likes reachable offline', () {
    Future<void> signIn(StreamController<AppUser?> auth) async {
      auth.add(const AppUser(_alice));
      await _settle();
    }

    test('liking something fetches it, so the offline layer can save it', () async {
      // Nothing else puts a liked entry on disk except a successful Library
      // load. Liking on Home and going offline would otherwise leave it missing
      // from the one screen that promised to have it, with no way to fetch it
      // by then.
      final auth = StreamController<AppUser?>();
      final catalog = _RecordingCatalog();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(),
        authStateChanges: auth.stream,
        catalogRepository: catalog,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });
      await signIn(auth);

      await cubit.toggle(const LikedId.item('dm1'));
      await _settle();

      expect(catalog.itemIdsAsked, [
        {'dm1'},
      ]);
      expect(catalog.trackIdsAsked, isEmpty, reason: 'an album is not a song');
    });

    test('liking a song asks the track lookup, not the item one', () async {
      final auth = StreamController<AppUser?>();
      final catalog = _RecordingCatalog();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(),
        authStateChanges: auth.stream,
        catalogRepository: catalog,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });
      await signIn(auth);

      await cubit.toggle(const LikedId.track('dm1-1'));
      await _settle();

      expect(catalog.trackIdsAsked, [
        {'dm1-1'},
      ]);
      expect(catalog.itemIdsAsked, isEmpty);
    });

    test('unliking fetches nothing', () async {
      final auth = StreamController<AppUser?>();
      final catalog = _RecordingCatalog();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(
          seed: {
            _alice: {const LikedId.item('dm1')},
          },
        ),
        authStateChanges: auth.stream,
        catalogRepository: catalog,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });
      await signIn(auth);

      await cubit.toggle(const LikedId.item('dm1'));
      await _settle();

      expect(catalog.itemIdsAsked, isEmpty);
    });

    test('a like still succeeds when the catalog cannot be reached', () async {
      // The like is the user's, and it is already saved. All that is lost is
      // being able to see it without a network.
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(),
        authStateChanges: auth.stream,
        catalogRepository: const _DownCatalog(),
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });
      await signIn(auth);

      await cubit.toggle(const LikedId.item('dm1'));
      await _settle();

      expect(cubit.state.likedIds, {const LikedId.item('dm1')});
    });

    test('works with no catalog at all', () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(repository: _FakeLikesRepository(), authStateChanges: auth.stream);
      addTearDown(() {
        auth.close();
        cubit.close();
      });
      await signIn(auth);

      await cubit.toggle(const LikedId.item('dm1'));

      expect(cubit.state.likedIds, {const LikedId.item('dm1')});
    });
  });
}
