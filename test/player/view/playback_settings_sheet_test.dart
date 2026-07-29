import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/view/playback_settings_sheet.dart';

import '../fake_audio_controller.dart';

Future<PlayerBloc> _pumpSheet(WidgetTester tester, FakeAudioController audio) async {
  final bloc = PlayerBloc(audioController: audio);
  addTearDown(bloc.close);

  await tester.pumpWidget(
    MaterialApp(
      home: BlocProvider.value(
        value: bloc,
        child: const Scaffold(body: PlaybackSettingsSheet()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return bloc;
}

void main() {
  testWidgets('shows crossfade as Off by default', (tester) async {
    await _pumpSheet(tester, FakeAudioController(supportsCrossfade: true));

    expect(find.text('Crossfade'), findsOneWidget);
    expect(find.text('Off'), findsOneWidget);
  });

  testWidgets('reflects the current crossfade duration in seconds', (tester) async {
    final bloc = await _pumpSheet(tester, FakeAudioController(supportsCrossfade: true));

    bloc.add(const PlayerCrossfadeDurationChanged(Duration(seconds: 7)));
    await tester.pumpAndSettle();

    expect(find.text('7 s'), findsOneWidget);
    expect(find.text('Off'), findsNothing);
  });

  testWidgets('dragging the slider sets a crossfade duration', (tester) async {
    final bloc = await _pumpSheet(tester, FakeAudioController(supportsCrossfade: true));
    expect(bloc.state.crossfadeDuration, Duration.zero);

    // Drag from the left end towards the middle of the track.
    final slider = find.byType(Slider);
    final topLeft = tester.getTopLeft(slider);
    final size = tester.getSize(slider);
    await tester.dragFrom(
      Offset(topLeft.dx + 8, topLeft.dy + size.height / 2),
      Offset(size.width / 2, 0),
    );
    await tester.pumpAndSettle();

    expect(bloc.state.crossfadeDuration, greaterThan(Duration.zero));
    expect(bloc.state.isCrossfadeEnabled, isTrue);
  });
}
