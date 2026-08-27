import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/catalog/repository/offline/offline_status.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/widgets/playback_failure_listener.dart';

import '../../helpers/fake_offline_status.dart';
import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 3), audioUrl: 'url-2'),
];

void main() {
  late FakeAudioController audio;
  late PlayerBloc bloc;

  /// Everything is built *inside* the test body on purpose. A bloc constructed
  /// in setUp belongs to the real async zone, so the events it is handed never
  /// run under the fake clock and nothing this file asserts would ever happen.
  Future<void> pumpListener(WidgetTester tester, {bool offline = false}) async {
    audio = FakeAudioController();
    bloc = PlayerBloc(audioController: audio);
    final status = FakeOfflineStatus(offline: offline);
    addTearDown(bloc.close);
    addTearDown(status.close);

    await tester.pumpWidget(
      RepositoryProvider<OfflineStatus>.value(
        value: status,
        child: BlocProvider<PlayerBloc>.value(
          value: bloc,
          child: const MaterialApp(
            home: PlaybackFailureListener(child: Scaffold(body: SizedBox())),
          ),
        ),
      ),
    );
  }

  Future<void> play(WidgetTester tester) async {
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await tester.pumpAndSettle();
  }

  /// Lets a shown SnackBar time out, so no timer outlives the test.
  Future<void> letItExpire(WidgetTester tester) async {
    await tester.pump(const Duration(seconds: 6));
    await tester.pumpAndSettle();
  }

  testWidgets('says nothing when playback works', (tester) async {
    await pumpListener(tester);

    await play(tester);

    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('offline, gives the reason rather than the track', (tester) async {
    await pumpListener(tester, offline: true);
    audio.failNextLoad = true;

    await play(tester);

    expect(find.text('Not available offline.'), findsOneWidget);
    await letItExpire(tester);
  });

  testWidgets('online, names the track that would not play', (tester) async {
    await pumpListener(tester);
    audio.failNextLoad = true;

    await play(tester);

    // Online it is not about coverage, so which track is the useful part.
    expect(find.text('Could not play One.'), findsOneWidget);
    await letItExpire(tester);
  });

  testWidgets('one failure is one message', (tester) async {
    await pumpListener(tester);
    audio.failNextLoad = true;

    await play(tester);
    // Anything emitting afterwards must not re-announce the same failure.
    bloc.add(const PlayerVolumeChanged(0.5));
    await tester.pumpAndSettle();

    expect(find.byType(SnackBar), findsOneWidget);
    await letItExpire(tester);
  });
}
