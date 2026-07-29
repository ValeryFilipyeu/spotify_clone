import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/audio/crossfade_audio_controller.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import 'fake_audio_controller.dart';

/// Scaled-down "Daily Mix 1": a short first track, then longer ones.
const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(milliseconds: 1500), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(milliseconds: 1500), audioUrl: 'url-2'),
  Track(id: 't3', title: 'Three', artist: 'C', duration: Duration(milliseconds: 1500), audioUrl: 'url-3'),
];

const _durations = {
  'url-1': Duration(milliseconds: 1500),
  'url-2': Duration(milliseconds: 1500),
  'url-3': Duration(milliseconds: 1500),
};

const _fade = Duration(milliseconds: 300);

Future<void> _settle() => Future<void>.delayed(Duration.zero);
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  late List<FakeAudioController> players;
  late CrossfadeAudioController controller;
  late PlayerBloc bloc;

  setUp(() {
    players = [];
    controller = CrossfadeAudioController(
      createPlayer: () {
        final player = FakeAudioController()
          ..durationsByUrl.addAll(_durations)
          ..loadDelay = const Duration(milliseconds: 40);
        players.add(player);
        return player;
      },
      rampStep: const Duration(milliseconds: 20),
    );
    bloc = PlayerBloc(audioController: controller);
  });

  tearDown(() => bloc.close());

  /// The engine reports readiness on whichever player is active; emitting on both
  /// is harmless because the decorator only forwards the active one's events.
  void engineReady() {
    for (final player in players) {
      player.emitPlaying(true);
      player.emitBuffering(false);
    }
  }

  Future<void> start() async {
    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    bloc.add(const PlayerCrossfadeDurationChanged(_fade));
    await _settle();
    engineReady();
    await _wait(120);
  }

  test('the real decorator crossfades, and keeps doing so after pause/next/prev', () async {
    await start();

    // 1. First crossfade: t1 -> t2.
    await _wait(1500);
    expect(bloc.state.currentIndex, 1, reason: 'first crossfade should have happened');
    expect(players[1].setUrls, contains('url-2'), reason: 'incoming track loads on the spare player');

    // 2. Pause and resume.
    bloc.add(const PlayerPlayPauseToggled());
    await _wait(60);
    for (final p in players) {
      p.emitPlaying(false);
    }
    await _wait(60);
    bloc.add(const PlayerPlayPauseToggled());
    await _wait(60);
    engineReady();
    await _wait(60);

    // 3. Next, then back to the very first track.
    bloc.add(const PlayerNextRequested());
    await _wait(150);
    engineReady();
    await _wait(60);
    expect(bloc.state.currentIndex, 2);

    bloc.add(const PlayerPreviousRequested());
    await _wait(150);
    engineReady();
    await _wait(60);
    bloc.add(const PlayerPreviousRequested());
    await _wait(150);
    engineReady();
    await _wait(60);

    expect(bloc.state.currentIndex, 0, reason: 'back on the first track');
    // A stale duration here silently moves the fade window out of reach.
    expect(bloc.state.duration, const Duration(milliseconds: 1500),
        reason: 'duration must be the playing track\'s own');
    expect(bloc.state.isLoading, isFalse, reason: 'a stuck isLoading freezes the ticker');
    expect(bloc.state.crossfadeDuration, _fade, reason: 'the setting must survive');

    // 4. THE POINT: a crossfade must still happen from here.
    final loadsBefore = players.expand((p) => p.setUrls).length;
    await _wait(1600);

    expect(bloc.state.currentIndex, 1,
        reason: 'crossfade (or at least advance) must still work after all that');
    expect(players.expand((p) => p.setUrls).length, greaterThan(loadsBefore));
  });
}
