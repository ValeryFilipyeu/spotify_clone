import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/history/cubit/play_history_cubit.dart';
import 'package:spotify_clone/history/cubit/play_history_state.dart';
import 'package:spotify_clone/history/repository/play_history_repository.dart';

/// In-memory, per-account history. [failWrites] makes record() throw, to
/// exercise the cubit's optimistic-then-revert path.
class _FakeHistoryRepository implements PlayHistoryRepository {
  _FakeHistoryRepository({Map<String, List<String>>? seed, this.failWrites = false})
      : _byUser = {for (final e in (seed ?? const {}).entries) e.key: [...e.value]};

  final Map<String, List<String>> _byUser;
  final bool failWrites;

  int recordCount = 0;

  @override
  Future<List<String>> fetchRecentIds(String userId) async => [...?_byUser[userId]];

  @override
  Future<void> record(String userId, String itemId) async {
    recordCount++;
    if (failWrites) throw Exception('offline');
    _byUser[userId] = withMostRecent(_byUser[userId] ?? const [], itemId);
  }
}

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

/// Yields to the event loop so an auth event and the load it triggers both land.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlayHistoryCubit', () {
    test('starts empty', () {
      final cubit = PlayHistoryCubit(
        repository: _FakeHistoryRepository(),
        authStateChanges: Stream.value(null),
      );

      expect(cubit.state, const PlayHistoryState());
      cubit.close();
    });

    test("loads the signed-in account's history", () async {
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(
        repository: _FakeHistoryRepository(seed: {_alice: ['dm1', 'lofi']}),
        authStateChanges: auth.stream,
      );
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();

      expect(cubit.state.recentIds, ['dm1', 'lofi']);
    });

    test('records to the front, immediately', () async {
      final repository = _FakeHistoryRepository(seed: {_alice: ['dm1']});
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(repository: repository, authStateChanges: auth.stream);
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });
      auth.add(const AppUser(_alice));
      await _settle();

      await cubit.record('jazz');

      expect(cubit.state.recentIds, ['jazz', 'dm1']);
      expect(await repository.fetchRecentIds(_alice), ['jazz', 'dm1']);
    });

    test('replaying what is already at the front costs nothing', () async {
      final repository = _FakeHistoryRepository(seed: {_alice: ['dm1', 'lofi']});
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(repository: repository, authStateChanges: auth.stream);
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });
      auth.add(const AppUser(_alice));
      await _settle();

      await cubit.record('dm1');

      expect(cubit.state.recentIds, ['dm1', 'lofi']);
      expect(repository.recordCount, 0, reason: 'the list would not change');
    });

    // Nobody signed in means nobody to attribute the play to. It must not throw,
    // and it must not remember it for whoever signs in next.
    test('ignores a play with nobody signed in', () async {
      final repository = _FakeHistoryRepository();
      final cubit = PlayHistoryCubit(
        repository: repository,
        authStateChanges: Stream.value(null),
      );
      addTearDown(cubit.close);
      await _settle();

      await cubit.record('dm1');

      expect(cubit.state.recentIds, isEmpty);
      expect(repository.recordCount, 0);
    });

    test('a failed write reverts, so the row never lies about what was saved', () async {
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(
        repository: _FakeHistoryRepository(seed: {_alice: ['dm1']}, failWrites: true),
        authStateChanges: auth.stream,
      );
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });
      auth.add(const AppUser(_alice));
      await _settle();

      await cubit.record('jazz');

      expect(cubit.state.recentIds, ['dm1']);
    });

    test('forgets the previous account on sign-out', () async {
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(
        repository: _FakeHistoryRepository(seed: {_alice: ['dm1']}),
        authStateChanges: auth.stream,
      );
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      auth.add(null);
      await _settle();

      expect(cubit.state.recentIds, isEmpty);
    });

    test('never shows one account the other one is history', () async {
      final auth = StreamController<AppUser?>();
      final cubit = PlayHistoryCubit(
        repository: _FakeHistoryRepository(seed: {
          _alice: ['dm1'],
          _bob: ['jazz'],
        }),
        authStateChanges: auth.stream,
      );
      addTearDown(() async {
        await cubit.close();
        await auth.close();
      });

      auth.add(const AppUser(_alice));
      await _settle();
      expect(cubit.state.recentIds, ['dm1']);

      auth.add(null);
      await _settle();
      auth.add(const AppUser(_bob));
      await _settle();

      expect(cubit.state.recentIds, ['jazz']);
    });
  });
}
