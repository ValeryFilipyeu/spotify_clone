import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/view/full_player_page.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'u1'),
];

void main() {
  testWidgets('transport controls stay put when play/pause swaps to a loading spinner', (tester) async {
    final audio = FakeAudioController();
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));

    await tester.pumpWidget(
      MaterialApp(home: BlocProvider.value(value: bloc, child: const FullPlayerPage())),
    );
    await tester.pump();

    // After a track start the state is loading -> the center button shows the
    // spinner. Record where prev/next sit.
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final prevLoading = tester.getCenter(find.byIcon(Icons.skip_previous));
    final nextLoading = tester.getCenter(find.byIcon(Icons.skip_next));

    // Loading clears -> the center button shows the play/pause glyph (a
    // different intrinsic size). Prev/next must not have moved.
    audio.emitBuffering(false);
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(tester.getCenter(find.byIcon(Icons.skip_previous)), prevLoading);
    expect(tester.getCenter(find.byIcon(Icons.skip_next)), nextLoading);
  });
}
