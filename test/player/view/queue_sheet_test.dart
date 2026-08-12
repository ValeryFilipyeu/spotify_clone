import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/view/queue_sheet.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 4), audioUrl: 'url-2'),
  Track(id: 't3', title: 'Three', artist: 'C', duration: Duration(minutes: 2), audioUrl: 'url-3'),
  Track(id: 't4', title: 'Four', artist: 'D', duration: Duration(minutes: 5), audioUrl: 'url-4'),
];

/// Boots a bloc playing `_queue[startIndex]` and renders the sheet against it.
Future<PlayerBloc> _pumpSheet(
  WidgetTester tester,
  FakeAudioController audio,
  int startIndex,
) async {
  final bloc = PlayerBloc(audioController: audio);
  addTearDown(bloc.close);
  bloc.add(PlayerTrackStarted(queue: _queue, startIndex: startIndex));

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: QueueSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  audio.setUrls.clear(); // ignore the initial load
  return bloc;
}

void main() {
  late FakeAudioController audio;

  setUp(() => audio = FakeAudioController());

  testWidgets('lists the playing track and only what comes after it', (tester) async {
    await _pumpSheet(tester, audio, 1); // 't2' playing

    expect(find.text('Now playing'.toUpperCase()), findsOneWidget);
    expect(find.text('Two'), findsOneWidget);
    // Later tracks are queued up...
    expect(find.text('Three'), findsOneWidget);
    expect(find.text('Four'), findsOneWidget);
    // ...but an already-played track is not part of "up next".
    expect(find.text('One'), findsNothing);
  });

  testWidgets('tapping an up-next row jumps to that absolute queue index', (tester) async {
    final bloc = await _pumpSheet(tester, audio, 1); // 't2' playing, up next: t3, t4

    // 'Four' is index 1 of the up-next sublist but index 3 of the real queue --
    // the sheet has to translate before dispatching.
    await tester.tap(find.text('Four'));
    await tester.pumpAndSettle();

    expect(bloc.state.currentIndex, 3);
    expect(bloc.state.currentTrack?.id, 't4');
    expect(audio.setUrls, ['url-4']);
  });

  testWidgets('the remove button drops the right track and leaves playback alone', (tester) async {
    final bloc = await _pumpSheet(tester, audio, 1); // 't2' playing, up next: t3, t4

    final fourRow = find.ancestor(of: find.text('Four'), matching: find.byType(ListTile));
    await tester.tap(
      find.descendant(of: fourRow, matching: find.byIcon(Icons.remove_circle_outline)),
    );
    await tester.pumpAndSettle();

    expect(bloc.state.queue.map((t) => t.id).toList(), ['t1', 't2', 't3']);
    expect(bloc.state.currentTrack?.id, 't2'); // still playing
    expect(audio.setUrls, isEmpty); // and never reloaded
    expect(find.text('Four'), findsNothing);
  });

  testWidgets('the playing track has no remove button of its own', (tester) async {
    await _pumpSheet(tester, audio, 2); // 't3' playing, up next: t4

    final currentRow = find.ancestor(of: find.text('Three'), matching: find.byType(ListTile));
    expect(
      find.descendant(of: currentRow, matching: find.byIcon(Icons.remove_circle_outline)),
      findsNothing,
    );
    // Exactly one removable row (the single up-next entry).
    expect(find.byIcon(Icons.remove_circle_outline), findsOneWidget);
  });

  testWidgets('shows an empty hint when nothing is queued after the current track', (tester) async {
    await _pumpSheet(tester, audio, 3); // last track playing

    expect(find.text('Nothing queued after this track.'), findsOneWidget);
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
  });
}
