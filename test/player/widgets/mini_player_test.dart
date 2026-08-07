import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/widgets/equalizer_bars.dart';
import 'package:spotify_clone/player/widgets/mini_player.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'Song One', artist: 'Artist A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
];

Widget _host(PlayerBloc bloc) => MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: Scaffold(
          body: Align(
            alignment: Alignment.bottomCenter,
            child: MiniPlayer(onTap: () {}),
          ),
        ),
      ),
    );

void main() {
  testWidgets('the equalizer over the artwork runs only while sound is coming out',
      (tester) async {
    // strictPlayingContract so isPlaying comes from the engine's own reporting
    // rather than being poked in by hand.
    final audio = FakeAudioController()..strictPlayingContract = true;
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));

    await tester.pumpWidget(_host(bloc));
    await tester.pump(); // the bloc processes PlayerTrackStarted
    // A track start leaves isLoading set until bufferingStream says otherwise,
    // which is how a real engine reports a source becoming ready.
    audio.emitBuffering(false);
    await tester.pump();

    bool isActive() => tester.widget<EqualizerBars>(find.byType(EqualizerBars)).isActive;

    expect(bloc.state.isPlaying, isTrue);
    expect(bloc.state.isLoading, isFalse);
    expect(isActive(), isTrue);

    // Paused: the bars settle and the ticker winds down (its own test covers the
    // stopping; here it is the wiring that matters).
    bloc.add(const PlayerPlayPauseToggled());
    await tester.pump();
    await tester.pump();

    expect(bloc.state.isPlaying, isFalse);
    expect(isActive(), isFalse);

    // A mid-track buffer stall: still "playing", but nothing is audible, so the
    // bars should hold still rather than lie.
    bloc.add(const PlayerPlayPauseToggled());
    await tester.pump();
    await tester.pump();
    expect(isActive(), isTrue);

    audio.emitBuffering(true);
    await tester.pump();
    expect(bloc.state.isLoading, isTrue);
    expect(isActive(), isFalse);

    // Leave nothing ticking into the next test.
    audio.emitPlaying(false);
    await tester.pump(const Duration(milliseconds: 500));
  });

  testWidgets('the close button stops playback and dismisses the mini-player', (tester) async {
    final bloc = PlayerBloc(audioController: FakeAudioController());
    addTearDown(bloc.close);
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));

    await tester.pumpWidget(_host(bloc));
    await tester.pump(); // let the bloc process PlayerTrackStarted

    // The bar is visible with the track loaded.
    expect(find.text('Song One'), findsOneWidget);
    expect(find.byIcon(Icons.close), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close));
    await tester.pump();

    // Playback cleared -> the whole bar collapses to nothing.
    expect(bloc.state.hasTrack, isFalse);
    expect(find.text('Song One'), findsNothing);
  });
}
