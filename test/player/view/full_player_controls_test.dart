import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/auth/models/app_user.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/likes/cubit/likes_cubit.dart';
import 'package:spotify_clone/likes/repository/likes_repository.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';
import 'package:spotify_clone/player/view/full_player_page.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'u1'),
];

/// Minimal LikesRepository so the Now Playing heart can build.
class _FakeLikesRepository implements LikesRepository {
  final Set<String> _ids = {};

  @override
  Future<Set<String>> fetchLikedIds(String userId) async => {..._ids};

  @override
  Future<void> like(String userId, String id) async => _ids.add(id);

  @override
  Future<void> unlike(String userId, String id) async => _ids.remove(id);
}

/// Pumps the full player against a bloc already playing the first track.
///
/// [clearLoading] settles the initial buffering state, because the loading
/// spinner is an indefinite animation -- while it is on screen pumpAndSettle
/// can never return.
Future<PlayerBloc> _pumpPlayer(
  WidgetTester tester,
  FakeAudioController audio, {
  bool clearLoading = true,
}) async {
  final bloc = PlayerBloc(audioController: audio);
  addTearDown(bloc.close);
  bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));

  final likes = LikesCubit(
    repository: _FakeLikesRepository(),
    authStateChanges: Stream.value(const AppUser('u@spotify.com')),
  );
  addTearDown(likes.close);

  // Providers go ABOVE MaterialApp, mirroring MyApp -- modal routes (the queue
  // sheet) are pushed on MaterialApp's Navigator, so a provider placed under
  // `home:` would be invisible to them.
  await tester.pumpWidget(
    MultiBlocProvider(
      providers: [
        BlocProvider.value(value: bloc),
        BlocProvider.value(value: likes),
      ],
      child: const MaterialApp(home: FullPlayerPage()),
    ),
  );
  await tester.pump();
  if (clearLoading) {
    audio.emitBuffering(false);
    await tester.pump();
  }
  return bloc;
}

void main() {
  testWidgets('transport controls stay put when play/pause swaps to a loading spinner', (tester) async {
    final audio = FakeAudioController();
    await _pumpPlayer(tester, audio, clearLoading: false);

    // After a track start the state is loading -> the center button shows the
    // spinner. Record where every other control sits.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final shuffleLoading = tester.getCenter(find.byIcon(Icons.shuffle));
    final prevLoading = tester.getCenter(find.byIcon(Icons.skip_previous));
    final nextLoading = tester.getCenter(find.byIcon(Icons.skip_next));
    final repeatLoading = tester.getCenter(find.byIcon(Icons.repeat));

    // Loading clears -> the center button shows the play/pause glyph (a
    // different intrinsic size). Nothing around it may move.
    audio.emitBuffering(false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(tester.getCenter(find.byIcon(Icons.shuffle)), shuffleLoading);
    expect(tester.getCenter(find.byIcon(Icons.skip_previous)), prevLoading);
    expect(tester.getCenter(find.byIcon(Icons.skip_next)), nextLoading);
    expect(tester.getCenter(find.byIcon(Icons.repeat)), repeatLoading);
  });

  testWidgets('the shuffle button toggles shuffle without reloading the track', (tester) async {
    final audio = FakeAudioController();
    final bloc = await _pumpPlayer(tester, audio);
    audio.setUrls.clear(); // ignore the initial load

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();
    expect(bloc.state.isShuffled, isTrue);

    await tester.tap(find.byIcon(Icons.shuffle));
    await tester.pumpAndSettle();
    expect(bloc.state.isShuffled, isFalse);

    // Toggling order must never restart playback.
    expect(audio.setUrls, isEmpty);
  });

  testWidgets('the repeat button cycles off -> all -> one -> off and swaps its glyph', (tester) async {
    final audio = FakeAudioController();
    final bloc = await _pumpPlayer(tester, audio);

    // Off and all share the Icons.repeat glyph (they differ by colour); only
    // repeat-one swaps in Icons.repeat_one.
    expect(bloc.state.repeatMode, PlayerRepeatMode.off);
    expect(find.byIcon(Icons.repeat), findsOneWidget);

    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    expect(bloc.state.repeatMode, PlayerRepeatMode.all);
    expect(find.byIcon(Icons.repeat), findsOneWidget);

    await tester.tap(find.byIcon(Icons.repeat));
    await tester.pumpAndSettle();
    expect(bloc.state.repeatMode, PlayerRepeatMode.one);
    expect(find.byIcon(Icons.repeat_one), findsOneWidget);
    expect(find.byIcon(Icons.repeat), findsNothing);

    await tester.tap(find.byIcon(Icons.repeat_one));
    await tester.pumpAndSettle();
    expect(bloc.state.repeatMode, PlayerRepeatMode.off);
  });

  testWidgets('the queue button opens the Up next sheet', (tester) async {
    final audio = FakeAudioController();
    await _pumpPlayer(tester, audio);

    await tester.tap(find.byIcon(Icons.queue_music));
    await tester.pumpAndSettle();

    expect(find.text('Queue'), findsOneWidget);
    expect(find.text('Now playing'.toUpperCase()), findsOneWidget);
    // This test's queue holds a single track, so there is nothing after it.
    // (queue_sheet_test covers the populated sheet in depth.)
    expect(find.text('Nothing queued after this track.'), findsOneWidget);
  });

  testWidgets('the app bar action opens the playback settings sheet', (tester) async {
    final audio = FakeAudioController();
    await _pumpPlayer(tester, audio);

    await tester.tap(find.byIcon(Icons.tune));
    await tester.pumpAndSettle();

    expect(find.text('Playback'), findsOneWidget);
    expect(find.text('Crossfade'), findsOneWidget);
  });
}
