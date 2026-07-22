import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/widgets/mini_player.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'Song One', artist: 'Artist A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
];

void main() {
  testWidgets('the close button stops playback and dismisses the mini-player', (tester) async {
    final bloc = PlayerBloc(audioController: FakeAudioController());
    addTearDown(bloc.close);
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));

    await tester.pumpWidget(
      MaterialApp(
        home: BlocProvider.value(
          value: bloc,
          child: Scaffold(
            body: Align(
              alignment: Alignment.bottomCenter,
              child: MiniPlayer(onTap: () {}),
            ),
          ),
        ),
      ),
    );
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
