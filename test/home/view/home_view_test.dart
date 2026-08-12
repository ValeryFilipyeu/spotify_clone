import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/history/cubit/play_history_cubit.dart';
import 'package:spotify_clone/history/repository/play_history_repository.dart';
import 'package:spotify_clone/home/cubit/home_cubit.dart';
import 'package:spotify_clone/home/view/home_view.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';

/// In-memory history, seedable so a test can start from an account that has
/// already played things.
class _FakeHistoryRepository implements PlayHistoryRepository {
  _FakeHistoryRepository([Map<String, List<String>>? seed])
    : _byUser = {
        for (final e in (seed ?? const {}).entries) e.key: [...e.value],
      };

  final Map<String, List<String>> _byUser;

  @override
  Future<List<String>> fetchRecentIds(String userId) async => [...?_byUser[userId]];

  @override
  Future<void> record(String userId, String itemId) async {
    _byUser[userId] = withMostRecent(_byUser[userId] ?? const [], itemId);
  }
}

class _NoLikesRepository implements LikesRepository {
  @override
  Future<Set<String>> fetchLikedIds(String userId) async => {};

  @override
  Future<void> like(String userId, String id) async {}

  @override
  Future<void> unlike(String userId, String id) async {}
}

const _alice = 'alice@spotify.com';

/// Home with the two app-wide cubits it composes, and nothing else: no router
/// and no AuthBloc, since both are only touched by taps these tests don't make.
Future<PlayHistoryCubit> _pumpHome(WidgetTester tester, {List<String> history = const []}) async {
  // A stream each: Stream.value is single-subscription, and both cubits listen.
  Stream<AppUser?> signedIn() => Stream.value(const AppUser(_alice));
  final playHistory = PlayHistoryCubit(
    repository: _FakeHistoryRepository({_alice: history}),
    authStateChanges: signedIn(),
  );
  final likes = LikesCubit(repository: _NoLikesRepository(), authStateChanges: signedIn());
  addTearDown(() async {
    await playHistory.close();
    await likes.close();
  });

  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: playHistory),
        BlocProvider.value(value: likes),
        BlocProvider(
          create: (_) =>
              HomeCubit(catalogRepository: const FakeCatalogRepository())..loadSections(),
        ),
      ],
      child: const MaterialApp(home: HomeView()),
    ),
  );
  await tester.pumpAndSettle();

  return playHistory;
}

void main() {
  setUpAll(() {
    // No runtime font fetch: keeps this hermetic (covers fail to load here too,
    // which CoverArt is built to survive -- see its own test).
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('HomeView', () {
    testWidgets('greets the user above the first row', (tester) async {
      await _pumpHome(tester);

      expect(find.textContaining('Good '), findsOneWidget);
    });

    testWidgets('shows the catalog rows', (tester) async {
      await _pumpHome(tester);

      expect(find.text('Made for you'), findsOneWidget);
      // The row that used to be a hardcoded "Recently played" for everybody.
      expect(find.text('Popular playlists'), findsOneWidget);
    });

    testWidgets('has no Recently played row for an account that has played nothing', (
      tester,
    ) async {
      await _pumpHome(tester);

      expect(find.text('Recently played'), findsNothing);
    });

    testWidgets("shows what this account actually played, before the catalog's own rows", (
      tester,
    ) async {
      await _pumpHome(tester, history: ['jazz']);

      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Jazz Vibes'), findsOneWidget);
      // Above "Made for you", which is the catalog's first row.
      expect(
        tester.getTopLeft(find.text('Recently played')).dy,
        lessThan(tester.getTopLeft(find.text('Made for you')).dy),
      );
    });

    // The point of composing this in the view rather than in HomeCubit: playing
    // something reorders Home with no reload of the catalog.
    testWidgets('picks up a play with no reload', (tester) async {
      final history = await _pumpHome(tester);
      expect(find.text('Recently played'), findsNothing);

      await history.record('lofi');
      await tester.pumpAndSettle();

      expect(find.text('Recently played'), findsOneWidget);
      expect(find.text('Lo-Fi Beats'), findsWidgets);
    });
  });
}
