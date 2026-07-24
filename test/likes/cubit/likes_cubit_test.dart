import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/cubit/likes_state.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';

/// In-memory, per-user LikesRepository. [failMutations] makes like/unlike throw,
/// to exercise the cubit's optimistic-then-revert path.
class _FakeLikesRepository implements LikesRepository {
  _FakeLikesRepository({Map<String, Set<String>>? seed, this.failMutations = false})
      : _byUser = {for (final e in (seed ?? const {}).entries) e.key: {...e.value}};

  final Map<String, Set<String>> _byUser;
  final bool failMutations;

  Set<String> _for(String userId) => _byUser.putIfAbsent(userId, () => <String>{});

  @override
  Future<Set<String>> fetchLikedIds(String userId) async => {..._for(userId)};

  @override
  Future<void> like(String userId, String id) async {
    if (failMutations) throw Exception('offline');
    _for(userId).add(id);
  }

  @override
  Future<void> unlike(String userId, String id) async {
    if (failMutations) throw Exception('offline');
    _for(userId).remove(id);
  }
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

/// Yields to the event loop so a stream event and the async load it triggers
/// both complete.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('LikesCubit', () {
    test('initial state is loading with no likes', () {
      final cubit = LikesCubit(repository: _FakeLikesRepository(), authStateChanges: Stream.value(null));
      expect(cubit.state, const LikesState());
      expect(cubit.state.status, LikesStatus.loading);
      cubit.close();
    });

    test("loads the signed-in account's likes on sign-in", () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(seed: {
          _alice: {'ab1', 'dm2-2'},
        }),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();

      expect(cubit.state.status, LikesStatus.ready);
      expect(cubit.state.likedIds, {'ab1', 'dm2-2'});
    });

    test('clears likes on sign-out', () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(seed: {
          _alice: {'ab1'},
        }),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      expect(cubit.state.likedIds, {'ab1'});

      auth.add(null);
      await _settle();
      expect(cubit.state.status, LikesStatus.ready);
      expect(cubit.state.likedIds, isEmpty);
    });

    test("switching accounts loads the new account's likes, not the old", () async {
      final auth = StreamController<AppUser?>();
      final cubit = LikesCubit(
        repository: _FakeLikesRepository(seed: {
          _alice: {'ab1'},
          _bob: {'jazz-1'},
        }),
        authStateChanges: auth.stream,
      );
      addTearDown(() {
        auth.close();
        cubit.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      expect(cubit.state.likedIds, {'ab1'});

      auth.add(const AppUser(_bob));
      await _settle();
      expect(cubit.state.likedIds, {'jazz-1'});
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

      await cubit.toggle('ab1');
      expect(cubit.state.likedIds, {'ab1'});
      expect(await repo.fetchLikedIds(_alice), {'ab1'});

      await cubit.toggle('ab1');
      expect(cubit.state.likedIds, isEmpty);
      expect(await repo.fetchLikedIds(_alice), isEmpty);
    });

    test('toggle before sign-in is a no-op', () async {
      final cubit = LikesCubit(repository: _FakeLikesRepository(), authStateChanges: Stream.value(null));
      addTearDown(cubit.close);

      await cubit.toggle('ab1');
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

      await cubit.toggle('ab1');

      // Ends reverted...
      expect(cubit.state.likedIds, isEmpty);
      // ...but showed the optimistic "liked" state at some point.
      expect(states.any((s) => s.likedIds.contains('ab1')), isTrue);
    });
  });
}
