import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';

import '../fake_audio_controller.dart';

const _queue = [
  Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1'),
  Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 4), audioUrl: 'url-2'),
];

void main() {
  group('PlayerBloc', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController());

    test('initial state has no track', () {
      final bloc = PlayerBloc(audioController: audio);
      expect(bloc.state.hasTrack, isFalse);
      bloc.close();
    });

    blocTest<PlayerBloc, PlayerState>(
      'PlayerTrackStarted loads the tapped track and starts playback',
      build: () => PlayerBloc(audioController: audio),
      act: (bloc) => bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0)),
      verify: (bloc) {
        expect(bloc.state.currentTrack?.id, 't1');
        expect(audio.setUrls, ['url-1']);
        expect(audio.playCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'PlayerNextRequested advances to and plays the next track',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerNextRequested()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, ['url-2']);
        expect(audio.playCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'PlayerPreviousRequested is a no-op on the first track',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerPreviousRequested()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 0);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'toggling play/pause while playing calls pause',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0, isPlaying: true),
      act: (bloc) => bloc.add(const PlayerPlayPauseToggled()),
      verify: (bloc) => expect(audio.pauseCount, 1),
    );

    blocTest<PlayerBloc, PlayerState>(
      'completion auto-advances to the next track',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerCompleted()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, ['url-2']);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'completion on the last track stops instead of advancing',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1, isPlaying: true),
      act: (bloc) => bloc.add(const PlayerCompleted()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 1);
        expect(bloc.state.isPlaying, isFalse);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'PlayerStopped clears the queue and stops audio',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1, isPlaying: true),
      act: (bloc) => bloc.add(const PlayerStopped()),
      verify: (bloc) {
        expect(bloc.state.hasTrack, isFalse);
        expect(audio.stopCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'seeking updates state.position and seeks the engine',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerSeekRequested(Duration(seconds: 42))),
      verify: (bloc) {
        expect(bloc.state.position, const Duration(seconds: 42));
        expect(audio.seeks, [const Duration(seconds: 42)]);
      },
    );

    // The position ticker (not the engine's position stream, which is broken
    // on iOS) advances position while playing.
    blocTest<PlayerBloc, PlayerState>(
      'the position ticker advances position while playing',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0, duration: Duration(minutes: 3)),
      act: (bloc) => audio.emitPlaying(true),
      wait: const Duration(milliseconds: 700),
      verify: (bloc) {
        expect(bloc.state.isPlaying, isTrue);
        expect(bloc.state.position, greaterThan(Duration.zero));
      },
    );

    // Regression: while a track is still buffering (isLoading), the ticker
    // must NOT advance -- otherwise the scrubber moves before the auto-advanced
    // track's audio has started.
    blocTest<PlayerBloc, PlayerState>(
      'the position ticker does not advance while buffering',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0, duration: Duration(minutes: 3), isLoading: true),
      act: (bloc) => audio.emitPlaying(true),
      wait: const Duration(milliseconds: 700),
      verify: (bloc) => expect(bloc.state.position, Duration.zero),
    );

    // Regression: the loader must clear from the buffering stream, not from
    // `playing` (which stays true across an auto-advance track boundary).
    blocTest<PlayerBloc, PlayerState>(
      'buffering=false clears isLoading even while already playing',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0, isLoading: true, isPlaying: true),
      act: (bloc) => audio.emitBuffering(false),
      verify: (bloc) => expect(bloc.state.isLoading, isFalse),
    );

    // Regression: duration must come from setUrl's return value so the
    // scrubber has a scale even if durationStream is slow (as on web).
    blocTest<PlayerBloc, PlayerState>(
      'duration is taken from setUrl return value on track start',
      build: () {
        audio.loadedDuration = const Duration(minutes: 2, seconds: 30);
        return PlayerBloc(audioController: audio);
      },
      act: (bloc) => bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0)),
      verify: (bloc) => expect(bloc.state.duration, const Duration(minutes: 2, seconds: 30)),
    );
  });
}
