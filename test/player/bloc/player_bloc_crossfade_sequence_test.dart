import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import '../fake_audio_controller.dart';

/// Scaled-down stand-ins for a real playlist: every track is long enough to be
/// crossfade-eligible (more than 2x the fade).
const _queue = [
  Track(
    id: 't1',
    title: 'One',
    artist: 'A',
    duration: Duration(milliseconds: 1500),
    audioUrl: 'url-1',
  ),
  Track(
    id: 't2',
    title: 'Two',
    artist: 'B',
    duration: Duration(milliseconds: 1500),
    audioUrl: 'url-2',
  ),
  Track(id: 't3', title: 'Three', artist: 'C', duration: Duration(seconds: 30), audioUrl: 'url-3'),
];

const _fade = Duration(milliseconds: 300);

Future<void> _settle() => Future<void>.delayed(Duration.zero);
Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  // Replays the reported sequence end to end: crossfade, pause mid-fade, resume,
  // Next to cut a fade short, back to the first track -- and then checks that
  // crossfade STILL works. Any state left stuck by that journey shows up here.
  test('crossfade still works after pause/resume, Next, and going back', () async {
    final audio = FakeAudioController(supportsCrossfade: true)
      // The engine reports each source's real length, as just_audio does.
      ..durationsByUrl.addAll({
        'url-1': const Duration(milliseconds: 1500),
        'url-2': const Duration(milliseconds: 1500),
        'url-3': const Duration(seconds: 30),
      })
      // Loads take time, so supersession races are real.
      ..loadDelay = const Duration(milliseconds: 150);
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);

    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    bloc.add(const PlayerCrossfadeDurationChanged(_fade));
    await _settle();
    audio.emitPlaying(true);
    audio.emitBuffering(false);
    await _wait(200);

    // 1. Let track 1 crossfade into track 2.
    await _wait(1300);
    expect(bloc.state.currentIndex, 1, reason: 'first crossfade should have happened');
    expect(audio.crossfades, hasLength(1));

    // 2. Pause mid-playback and resume.
    bloc.add(const PlayerPlayPauseToggled());
    await _settle();
    audio.emitPlaying(false);
    await _wait(50);
    bloc.add(const PlayerPlayPauseToggled());
    await _settle();
    audio.emitPlaying(true);
    await _wait(50);

    // 3. Press Next, cutting things short.
    bloc.add(const PlayerNextRequested());
    await _wait(250);
    expect(bloc.state.currentIndex, 2);

    // 4. Go back to the first track.
    bloc.add(const PlayerPreviousRequested());
    await _wait(250);
    bloc.add(const PlayerPreviousRequested());
    await _wait(250);
    expect(bloc.state.currentIndex, 0, reason: 'back on the first track');
    expect(bloc.state.currentTrack?.id, 't1');

    // The duration must be track 1's own -- a stale value here silently moves
    // the fade window out of reach and looks exactly like "crossfade is gone".
    expect(
      bloc.state.duration,
      const Duration(milliseconds: 1500),
      reason: 'duration must belong to the track actually playing',
    );

    // 5. THE POINT: crossfade must still fire from here.
    audio.emitBuffering(false);
    final crossfadesBefore = audio.crossfades.length;
    await _wait(1600);

    expect(
      audio.crossfades.length,
      greaterThan(crossfadesBefore),
      reason: 'crossfade must still work after all that navigation',
    );
  });
}
