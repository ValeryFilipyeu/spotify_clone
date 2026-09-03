import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/images/cover_image_scope.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/local_likes_repository.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/view/full_player_page.dart';
import 'package:spotify_clone/player/widgets/mini_player.dart';

import '../../helpers/fake_key_value_store.dart';
import '../fake_audio_controller.dart';

const _pair = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

/// Bounded, not pumpAndSettle: once a track really plays the equalizer animates
/// forever and settling never returns.
Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

/// The play/pause button, whatever it currently says. IconButton builds its
/// Tooltip inside itself, so each finder walks back up to the button.
IconButton transportOf(WidgetTester tester) {
  for (final tooltip in ['Unavailable', 'Loading', 'Pause', 'Play']) {
    final finder = find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton));
    if (finder.evaluate().isNotEmpty) return tester.widget<IconButton>(finder);
  }
  throw StateError('no transport button on screen');
}

IconButton buttonOf(WidgetTester tester, String tooltip) => tester.widget<IconButton>(
  find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)),
);

/// The scrubber, told apart from the volume slider by its range: volume is
/// 0..1, the scrubber spans the track's duration in milliseconds.
Slider scrubberOf(WidgetTester tester) =>
    tester.widgetList<Slider>(find.byType(Slider)).firstWhere((slider) => slider.max > 1);

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  late FakeAudioController audio;
  late PlayerBloc bloc;

  /// Built in the test body: a bloc made in setUp belongs to the real async
  /// zone and its events never run under the fake clock.
  Future<void> pump(WidgetTester tester, Widget child, {required bool failing}) async {
    audio = FakeAudioController()..strictPlayingContract = true;
    bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);

    audio.failNextLoad = failing;
    bloc.add(const PlayerTrackStarted(queue: _pair, startIndex: 0));
    await tester.pumpWidget(
      MultiBlocProvider(
        providers: [
          BlocProvider<PlayerBloc>.value(value: bloc),
          // The full player draws a like button; nothing here is about likes.
          BlocProvider<LikesCubit>(
            create: (_) => LikesCubit(
              repository: LocalLikesRepository(FakeKeyValueStore()),
              authStateChanges: Stream<AppUser?>.value(null),
            ),
          ),
        ],
        child: MaterialApp(
          home: CoverImageScope(store: null, child: Scaffold(body: child)),
        ),
      ),
    );
    await settle(tester);

    // Leave the engine paused. A successful load starts the position ticker and
    // the equalizer animation, and both outlive the widget tree and trip the
    // pending-timer check. What is under test is whether the controls are
    // enabled, which paused answers just as well.
    audio.emitPlaying(false);
    await tester.pump();
  }

  group('the mini player', () {
    testWidgets('disables play on a track that will not load', (tester) async {
      await pump(tester, MiniPlayer(onTap: () {}), failing: true);

      expect(find.byTooltip('Unavailable'), findsOneWidget);
      expect(transportOf(tester).onPressed, isNull);
    });

    testWidgets('leaves play alone on a track that loads', (tester) async {
      await pump(tester, MiniPlayer(onTap: () {}), failing: false);

      expect(find.byTooltip('Unavailable'), findsNothing);
      expect(transportOf(tester).onPressed, isNotNull);
    });

    testWidgets('still lets the track be opened and dismissed', (tester) async {
      var opened = false;
      await pump(tester, MiniPlayer(onTap: () => opened = true), failing: true);

      await tester.tap(find.text('One'));
      await settle(tester);

      expect(opened, isTrue, reason: 'the row itself must stay tappable');
      expect(buttonOf(tester, 'Stop').onPressed, isNotNull);
    });
  });

  group('the full player', () {
    testWidgets('disables play and the scrubber', (tester) async {
      await pump(tester, const FullPlayerPage(), failing: true);

      expect(transportOf(tester).onPressed, isNull);
      expect(scrubberOf(tester).onChanged, isNull);
      expect(scrubberOf(tester).onChangeEnd, isNull);
    });

    testWidgets('keeps next reachable, which is the way out', (tester) async {
      await pump(tester, const FullPlayerPage(), failing: true);

      expect(buttonOf(tester, 'Next track').onPressed, isNotNull);
    });

    testWidgets('enables both when the track loads', (tester) async {
      await pump(tester, const FullPlayerPage(), failing: false);

      expect(find.byTooltip('Unavailable'), findsNothing);
      expect(transportOf(tester).onPressed, isNotNull);
      expect(scrubberOf(tester).onChanged, isNotNull);
    });

    testWidgets('re-enables them after moving on to a track that plays', (tester) async {
      await pump(tester, const FullPlayerPage(), failing: true);

      bloc.add(const PlayerNextRequested());
      await settle(tester);
      audio.emitPlaying(false); // as above: no ticker may outlive the tree
      await tester.pump();

      expect(find.byTooltip('Unavailable'), findsNothing);
      expect(transportOf(tester).onPressed, isNotNull);
      expect(scrubberOf(tester).onChanged, isNotNull);
    });
  });
}
