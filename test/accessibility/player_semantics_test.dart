import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/view/full_player_page.dart';
import 'package:spotify_clone/player/view/queue_sheet.dart';
import 'package:spotify_clone/player/widgets/mini_player.dart';
import 'package:spotify_clone/likes/models/liked_id.dart';

import '../player/fake_audio_controller.dart';
import 'semantics_probe.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'Artist A', duration: Duration(minutes: 3), audioUrl: 'u1'),
  Track(id: 't2', title: 'Two', artist: 'Artist B', duration: Duration(minutes: 4), audioUrl: 'u2'),
  Track(
    id: 't3',
    title: 'Three',
    artist: 'Artist C',
    duration: Duration(minutes: 2),
    audioUrl: 'u3',
  ),
  Track(
    id: 't4',
    title: 'Four',
    artist: 'Artist D',
    duration: Duration(minutes: 5),
    audioUrl: 'u4',
  ),
];

class _FakeLikesRepository implements LikesRepository {
  final Set<LikedId> _ids = {};

  @override
  Future<Set<LikedId>> fetchLikedIds(String userId) async => {..._ids};

  @override
  Future<void> like(String userId, LikedId id) async => _ids.add(id);

  @override
  Future<void> unlike(String userId, LikedId id) async => _ids.remove(id);
}

/// Pumps [child] with the blocs the player surfaces read, playing `_queue` from
/// [startIndex], runs [body] against it, then tears everything down.
///
/// Two pieces of teardown have to happen inside the test BODY, because
/// flutter_test's end-of-body checks run before any tearDown: no SemanticsHandle
/// may be outstanding, and no timer may still be pending. Playback starts a
/// 250ms position ticker, so it is stopped here -- by telling the engine it has
/// paused, which is what cancels it. (Closing the bloc here instead deadlocks:
/// its close() awaits futures that never complete inside the test's fake async.)
Future<void> withPlayer(
  WidgetTester tester,
  Widget child, {
  int startIndex = 0,
  bool loading = false,
  required Future<void> Function(PlayerBloc bloc) body,
}) async {
  final handle = tester.ensureSemantics();
  // strictPlayingContract so pausing actually reports itself back, which is
  // what flips the play button's label.
  final audio = FakeAudioController()..strictPlayingContract = true;
  final bloc = PlayerBloc(audioController: audio);
  final likes = LikesCubit(
    repository: _FakeLikesRepository(),
    authStateChanges: Stream.value(const AppUser('u@spotify.com')),
  );
  addTearDown(bloc.close);
  addTearDown(likes.close);

  try {
    bloc.add(PlayerTrackStarted(queue: _queue, startIndex: startIndex));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider.value(value: bloc),
          BlocProvider.value(value: likes),
        ],
        child: MaterialApp(home: Scaffold(body: child)),
      ),
    );
    await tester.pump();

    if (loading) {
      audio.emitBuffering(true);
    } else {
      audio.emitBuffering(false);
      audio.emitPlaying(true);
    }
    // NOT pumpAndSettle: the position ticker keeps scheduling frames, so the
    // tree never goes quiet and pumpAndSettle would run until it timed out.
    await _flush(tester);

    await body(bloc);
  } finally {
    audio.emitPlaying(false); // cancels the position ticker
    await tester.pump();
    handle.dispose();
  }
}

/// Two frames, for the same reason [withPlayer] uses them instead of pumpAndSettle.
Future<void> _flush(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

void main() {
  group('the full player', () {
    testWidgets('names every icon-only control', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        startIndex: 1,
        body: (_) async {
          // Every one of these was an unnamed glyph before this pass.
          for (final name in [
            'Close Now Playing',
            'Previous track',
            'Next track',
            'Pause',
            'Queue',
            'Playback settings',
          ]) {
            expect(find.byTooltip(name), findsOneWidget, reason: name);
          }
        },
      );
    });

    testWidgets('the play button says which action it offers', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (bloc) async {
          expect(spokenName(tester, find.byTooltip('Pause')), contains('Pause'));

          bloc.add(const PlayerPlayPauseToggled());
          await _flush(tester);

          expect(find.byTooltip('Play'), findsOneWidget);
          expect(find.byTooltip('Pause'), findsNothing);
        },
      );
    });

    // The spinner replaces the glyph, and ProgressIndicator emits no semantics
    // of its own -- so without a tooltip this button would be nameless exactly
    // when a user most needs to know what it is doing.
    testWidgets('is still named while loading', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        loading: true,
        body: (_) async {
          expect(find.byTooltip('Loading'), findsWidgets);
        },
      );
    });

    testWidgets('shuffle and repeat announce their state, not just their colour', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (bloc) async {
          bool selected(String tooltip) =>
              tester.getSemantics(find.byTooltip(tooltip)).flagsCollection.isSelected ==
              Tristate.isTrue;

          expect(selected('Enable shuffle'), isFalse);
          expect(selected('Repeat off'), isFalse);

          bloc.add(const PlayerShuffleToggled());
          bloc.add(const PlayerRepeatModeCycled()); // off -> all
          await _flush(tester);

          expect(selected('Disable shuffle'), isTrue);
          expect(selected('Repeat all tracks'), isTrue);
        },
      );
    });

    // The old labels described the NEXT action, which read as a plain lie out
    // loud: repeat-all announced itself as "Repeat one track".
    testWidgets('repeat names the mode it is actually in', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (bloc) async {
          bloc.add(const PlayerRepeatModeCycled()); // -> all
          await _flush(tester);
          expect(find.byTooltip('Repeat all tracks'), findsOneWidget);

          bloc.add(const PlayerRepeatModeCycled()); // -> one
          await _flush(tester);
          expect(find.byTooltip('Repeat this track'), findsOneWidget);
        },
      );
    });

    testWidgets('the sliders speak positions and volume, not raw numbers', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (_) async {
          // Was "124000" or a bare percentage before: the slider's raw value is
          // milliseconds.
          expect(spokenText(tester), contains('Position 0 seconds of 3 minutes'));
          expect(spokenText(tester), contains('Volume 100 percent'));
        },
      );
    });

    testWidgets('the like button says what it would like', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (_) async {
          expect(find.byTooltip('Save One to Your Library'), findsOneWidget);

          await tester.tap(find.byTooltip('Save One to Your Library'));
          await _flush(tester);

          final heart = find.byTooltip('Remove One from Your Library');
          expect(heart, findsOneWidget);
          expect(tester.getSemantics(heart).flagsCollection.isSelected == Tristate.isTrue, isTrue);
        },
      );
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withPlayer(
        tester,
        const FullPlayerPage(),
        body: (_) async {
          await expectAccessible(tester);
        },
      );
    });
  });

  group('the mini player', () {
    Widget bar() => Align(
      alignment: Alignment.bottomCenter,
      child: MiniPlayer(onTap: () {}),
    );

    testWidgets('names its play button', (tester) async {
      await withPlayer(
        tester,
        bar(),
        body: (_) async {
          expect(find.byTooltip('Pause'), findsOneWidget);
        },
      );
    });

    testWidgets('announces a track change nobody asked for', (tester) async {
      await withPlayer(
        tester,
        bar(),
        body: (bloc) async {
          final node = tester.getSemantics(find.bySemanticsLabel('Now playing: One by Artist A'));
          expect(
            node.flagsCollection.isLiveRegion,
            isTrue,
            reason: 'an auto-advance moves no focus, so it has to announce itself',
          );

          bloc.add(const PlayerNextRequested());
          await _flush(tester);

          expect(find.bySemanticsLabel('Now playing: Two by Artist B'), findsOneWidget);
        },
      );
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withPlayer(
        tester,
        bar(),
        body: (_) async {
          await expectAccessible(tester);
        },
      );
    });
  });

  group('the queue sheet', () {
    testWidgets('labels the remove button and the drag handle per track', (tester) async {
      await withPlayer(
        tester,
        const QueueSheet(),
        body: (_) async {
          expect(find.byTooltip('Remove Two from queue'), findsOneWidget);
          // The drag handle is deliberately not in the tree: it would be a
          // focusable stop offering an interaction nobody can perform by ear.
          expect(find.bySemanticsLabel(RegExp('[Rr]eorder')), findsNothing);
        },
      );
    });

    // Dragging a handle is not something you can do without sight. Flutter's own
    // SliverReorderableList attaches these move actions; this guards against a
    // change to the sheet dropping them.
    testWidgets('rows can be reordered without dragging', (tester) async {
      // Up next: Two, Three, Four -- three rows, so there is somewhere to move.
      await withPlayer(
        tester,
        const QueueSheet(),
        body: (_) async {
          expect(customActionLabels(tester), containsAll(<String>['Move down', 'Move to the end']));
        },
      );
    });

    testWidgets('marks the playing row as selected', (tester) async {
      await withPlayer(
        tester,
        const QueueSheet(),
        body: (_) async {
          expect(
            rowIsSelected(tester, 'One'),
            isTrue,
            reason: 'green text is otherwise the only cue that this one is playing',
          );
          expect(rowIsSelected(tester, 'Three'), isFalse, reason: 'and only that row');
        },
      );
    });

    testWidgets('meets the tap-target and labelling guidelines', (tester) async {
      await withPlayer(
        tester,
        const QueueSheet(),
        body: (_) async {
          await expectAccessible(tester);
        },
      );
    });
  });
}
