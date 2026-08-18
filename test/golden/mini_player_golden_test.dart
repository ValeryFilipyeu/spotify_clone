import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/widgets/mini_player.dart';

import '../player/fake_audio_controller.dart';
import 'golden_harness.dart';

const _track = Track(
  id: 't1',
  title: 'Song One',
  artist: 'Artist A',
  duration: Duration(minutes: 3),
  audioUrl: 'url-1',
);

/// A title with nowhere near enough room, which is what puts the marquee to
/// work and squeezes the row's other children.
const _longTrack = Track(
  id: 't2',
  title: 'A Song With A Title Considerably Wider Than The Bar It Has To Live In',
  artist: 'An Artist Whose Name Also Refuses To Be Short About It',
  duration: Duration(minutes: 4, seconds: 12),
  audioUrl: 'url-2',
);

/// A mini-player wired to a fake engine, with the two nudges a golden of it
/// needs.
class _Bar {
  _Bar(this.track) {
    _audio = FakeAudioController()..loadedDuration = track.duration;
    _bloc = PlayerBloc(audioController: _audio);
    addTearDown(_bloc.close);
    _bloc.add(PlayerTrackStarted(queue: [track], startIndex: 0));
  }

  final Track track;
  late final FakeAudioController _audio;
  late final PlayerBloc _bloc;

  Widget get widget => SizedBox(
    width: 390,
    child: BlocProvider.value(
      value: _bloc,
      child: MiniPlayer(onTap: () {}),
    ),
  );

  /// Puts it into "playing, 45 seconds in".
  ///
  /// Has to go through the fake's streams rather than a bloc event: the event
  /// for this, `PlayerPositionTicked`, carries no value and makes the bloc read
  /// the controller instead. And it has to happen once the tree is live -- the
  /// streams are broadcast, so anything emitted before the bloc subscribes is
  /// dropped on the floor.
  /// `emitBuffering(false)` is not optional dressing: a track start leaves
  /// `isLoading` set until the buffering stream says otherwise, and without it
  /// the bar photographs with a spinner where the play button should be.
  Future<void> play() async {
    _audio
      ..emitDuration(track.duration)
      ..emitBuffering(false)
      ..emitPlaying(true)
      ..emitPosition(const Duration(seconds: 45));
  }

  /// Stops the bloc's position ticker, which must happen before the test body
  /// ends.
  ///
  /// Going into `playing` starts a 250ms periodic timer, and flutter_test fails
  /// any test that leaves a timer pending. That check runs at the end of the
  /// body -- *before* `addTearDown` callbacks -- so closing the bloc in a
  /// teardown is too late to satisfy it.
  Future<void> stop(WidgetTester tester) async {
    _audio.emitPlaying(false);
    await tester.pump();
  }
}

/// The mini-player is the app's most crowded row: artwork with an equalizer
/// overlaid on it, a title block that has to marquee, controls, and a progress
/// bar underneath -- all in a fixed height above the tab bar.
///
/// It is also where a layout mistake is least likely to fail a test and most
/// likely to be noticed by a person. Every finder-based assertion about it
/// passes whether the row is laid out correctly or has its title overlapping
/// the play button, because either way all the widgets are present, tappable
/// and correctly labelled.
void main() {
  setUpAll(setUpGoldens);

  group('MiniPlayer', () {
    testWidgets('playing, part way through a track', (tester) async {
      final bar = _Bar(_track);
      await expectGolden(
        tester,
        'mini_player',
        size: const GoldenSize(390, 90),
        // The equalizer's ticker never stops while sound is coming out, so
        // pumpAndSettle would run to its timeout instead of returning.
        pumpFor: const Duration(milliseconds: 750),
        afterPump: bar.play,
        child: bar.widget,
      );
      await bar.stop(tester);
    });

    testWidgets('with a title far too long for the bar', (tester) async {
      // The case that decides whether the row degrades or breaks. The title
      // column is the only flexible child, so if it ever stops yielding, the
      // controls are what get pushed off the edge.
      final bar = _Bar(_longTrack);
      await expectGolden(
        tester,
        'mini_player_long_title',
        size: const GoldenSize(390, 90),
        pumpFor: const Duration(milliseconds: 750),
        afterPump: bar.play,
        child: bar.widget,
      );
      await bar.stop(tester);
    });
  });
}
