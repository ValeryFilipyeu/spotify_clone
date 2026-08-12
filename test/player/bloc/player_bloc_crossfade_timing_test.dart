import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';

import '../fake_audio_controller.dart';

/// Mirrors "Daily Mix 1": a very short first track followed by long ones.
/// Scaled down so the real 250ms ticker gets through it quickly.
const _queue = [
  Track(
    id: 't1',
    title: 'Short',
    artist: 'A',
    duration: Duration(milliseconds: 1200),
    audioUrl: 'url-1',
  ),
  Track(id: 't2', title: 'Long', artist: 'B', duration: Duration(seconds: 30), audioUrl: 'url-2'),
  Track(id: 't3', title: 'Long2', artist: 'C', duration: Duration(seconds: 30), audioUrl: 'url-3'),
];

const _fade = Duration(milliseconds: 300);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  test('the real ticker starts exactly one crossfade per track', () async {
    final audio = FakeAudioController(supportsCrossfade: true);
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);

    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    bloc.add(const PlayerCrossfadeDurationChanged(_fade));
    await _settle();

    // Drive it like the engine does: playing starts the wall-clock ticker.
    audio.emitPlaying(true);
    audio.emitBuffering(false);
    await _settle();

    // Let the 1200ms track run past its fade window (900ms) and well beyond.
    await Future<void>.delayed(const Duration(milliseconds: 2500));

    expect(
      audio.crossfades.map((c) => c.url).toList(),
      ['url-2'],
      reason:
          'the short first track should hand over to t2 once, and t2 '
          '(30s long) should not immediately hand over again',
    );
    expect(bloc.state.currentIndex, 1);
  });

  // Regression: "Daily Mix 1" starts with a 12s track, and the 6-minute track
  // after it takes a moment to load. The outgoing track therefore reached its
  // natural end *while the incoming one was still loading* -- and that
  // completion, arriving after state had already advanced, advanced it a second
  // time. Result: the track we faded into was skipped after about a second.
  test('a completion arriving mid-load does not skip the track being faded in', () async {
    final audio = FakeAudioController(supportsCrossfade: true)
      // The incoming track takes a while to load, as a real one does.
      ..loadDelay = const Duration(milliseconds: 400);
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);

    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    bloc.add(const PlayerCrossfadeDurationChanged(_fade));
    await _settle();
    audio.emitPlaying(true);
    audio.emitBuffering(false);
    await _settle();

    // Let the short track reach its fade window and start handing over.
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(bloc.state.currentIndex, 1, reason: 'the crossfade should have started');

    // Now the outgoing track ends, mid-load -- exactly the real-world race.
    audio.emitCompleted();
    await Future<void>.delayed(const Duration(milliseconds: 800));

    expect(bloc.state.currentIndex, 1, reason: 'must stay on the track we faded into');
    expect(bloc.state.currentTrack?.id, 't2');
    expect(audio.crossfades.map((c) => c.url).toList(), ['url-2']);
    expect(audio.setUrls, isNot(contains('url-3')), reason: 't3 must never have been loaded');
  });

  test('a completion after a crossfade has settled still advances normally', () async {
    final audio = FakeAudioController(supportsCrossfade: true);
    final bloc = PlayerBloc(audioController: audio);
    addTearDown(bloc.close);

    bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
    await _settle();
    bloc.add(const PlayerCrossfadeDurationChanged(_fade));
    await _settle();
    audio.emitPlaying(true);
    audio.emitBuffering(false);
    await _settle();
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    expect(bloc.state.currentIndex, 1);

    // Long after the fade finished, t2 genuinely ends: that must advance.
    audio.emitCompleted();
    await _settle();

    expect(bloc.state.currentIndex, 2);
    expect(bloc.state.currentTrack?.id, 't3');
  });
}
