import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/catalog.dart';
import 'package:spotify_clone/catalog/widgets/catalog_list_tile.dart';
import 'package:spotify_clone/detail/widgets/track_tile.dart';
import 'package:spotify_clone/history/cubit/play_history_cubit.dart';
import 'package:spotify_clone/history/repository/play_history_repository.dart';
import 'package:spotify_clone/home/cubit/home_cubit.dart';
import 'package:spotify_clone/home/view/home_view.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/widgets/spotify_primary_button.dart';
import 'package:spotify_clone/widgets/spotify_text_field.dart';

import '../player/fake_audio_controller.dart';
import 'semantics_probe.dart';

const _track = Track(
  id: 't1',
  title: 'Electric Feel',
  artist: 'MGMT',
  duration: Duration(minutes: 3, seconds: 7),
  audioUrl: 'u1',
);

const _item = CatalogItem(
  id: 'dm1',
  title: 'Daily Mix 1',
  subtitle: 'Tame Impala, MGMT & more',
  coverColor: 0xFF1DB954,
);

class _NoLikes implements LikesRepository {
  final Set<String> _ids = {};

  @override
  Future<Set<String>> fetchLikedIds(String userId) async => {..._ids};

  @override
  Future<void> like(String userId, String id) async => _ids.add(id);

  @override
  Future<void> unlike(String userId, String id) async => _ids.remove(id);
}

class _NoHistory implements PlayHistoryRepository {
  @override
  Future<List<String>> fetchRecentIds(String userId) async => const [];

  @override
  Future<void> record(String userId, String itemId) async {}
}

/// Pumps [child] with the app-wide cubits the catalog widgets read, with
/// semantics on, and releases the handle inside the test body (flutter_test
/// checks for a leaked handle before any tearDown runs).
Future<void> withCatalog(
  WidgetTester tester,
  Widget child, {
  required Future<void> Function() body,
}) async {
  final handle = tester.ensureSemantics();
  Stream<AppUser?> signedIn() => Stream.value(const AppUser('u@spotify.com'));

  final player = PlayerBloc(audioController: FakeAudioController());
  final likes = LikesCubit(repository: _NoLikes(), authStateChanges: signedIn());
  final history = PlayHistoryCubit(repository: _NoHistory(), authStateChanges: signedIn());
  addTearDown(player.close);
  addTearDown(likes.close);
  addTearDown(history.close);

  try {
    await tester.pumpWidget(MultiBlocProvider(
      providers: [
        BlocProvider.value(value: player),
        BlocProvider.value(value: likes),
        BlocProvider.value(value: history),
        BlocProvider(
          create: (_) => HomeCubit(catalogRepository: const FakeCatalogRepository())..loadSections(),
        ),
      ],
      child: MaterialApp(home: Scaffold(body: child)),
    ));
    await tester.pumpAndSettle();
    await body();
  } finally {
    handle.dispose();
  }
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('a tracklist row', () {
    testWidgets('names the heart and the overflow menu after its track',
        (tester) async {
      await withCatalog(
        tester,
        const TrackTile(position: 3, track: _track),
        body: () async {
          // Every row otherwise offers a column of buttons all announcing
          // "Save to Your Library" and "More", with nothing to tell them apart.
          expect(find.byTooltip('Save Electric Feel to Your Library'), findsOneWidget);
          expect(find.byTooltip('More options for Electric Feel'), findsOneWidget);
        },
      );
    });

    testWidgets('speaks its length instead of a clock time', (tester) async {
      await withCatalog(
        tester,
        const TrackTile(position: 3, track: _track),
        body: () async {
          // "3:07" aloud is a time of day, not a duration.
          expect(spokenText(tester), contains('3 minutes 7 seconds'));
          expect(spokenText(tester), contains('Track 3'));
        },
      );
    });

    testWidgets('says when it is the track playing right now', (tester) async {
      await withCatalog(
        tester,
        const TrackTile(position: 3, track: _track, isCurrent: true),
        body: () async {
          expect(
            rowIsSelected(tester, 'Electric Feel'),
            isTrue,
            reason: 'green text is the only visual cue',
          );
        },
      );
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withCatalog(
        tester,
        const TrackTile(position: 3, track: _track),
        body: () => expectAccessible(tester),
      );
    });
  });

  group('a catalog row', () {
    testWidgets('names its heart after the playlist', (tester) async {
      await withCatalog(
        tester,
        const CatalogListTile(item: _item),
        body: () async {
          expect(find.byTooltip('Save Daily Mix 1 to Your Library'), findsOneWidget);
        },
      );
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withCatalog(
        tester,
        const CatalogListTile(item: _item),
        body: () => expectAccessible(tester),
      );
    });
  });

  group('home', () {
    testWidgets('marks the greeting and every row title as a heading',
        (tester) async {
      await withCatalog(tester, const HomeView(), body: () async {
        await tester.pumpAndSettle(); // let the catalog load
        final found = headings(tester);

        expect(found, contains('Made for you'));
        expect(found, contains('Popular albums'));
        expect(
          found.any((heading) => heading.startsWith('Good ')),
          isTrue,
          reason: 'the greeting leads the screen, so it is its first heading',
        );
      });
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withCatalog(tester, const HomeView(), body: () async {
        await tester.pumpAndSettle();
        await expectAccessible(tester);
      });
    });
  });

  group('the auth form', () {
    testWidgets('names the password visibility toggle in both states',
        (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SpotifyTextField(
              labelText: 'Password',
              obscureText: true,
              onChanged: (_) {},
            ),
          ),
        ));

        expect(find.byTooltip('Show password'), findsOneWidget);

        await tester.tap(find.byTooltip('Show password'));
        await tester.pumpAndSettle();

        expect(find.byTooltip('Hide password'), findsOneWidget);
        await expectAccessible(tester);
      } finally {
        handle.dispose();
      }
    });

    // The spinner replaces the label outright, so without a name the button
    // becomes an anonymous disabled control at the moment of submitting.
    testWidgets('a submitting button keeps its name', (tester) async {
      final handle = tester.ensureSemantics();
      try {
        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: SpotifyPrimaryButton(label: 'Log in', onPressed: () {}, isLoading: true),
          ),
        ));
        await tester.pump();

        expect(spokenText(tester), contains('Log in, in progress'));
      } finally {
        handle.dispose();
      }
    });
  });
}

