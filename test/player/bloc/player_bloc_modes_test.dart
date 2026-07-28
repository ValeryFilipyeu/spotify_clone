import 'dart:math';

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
  Track(id: 't3', title: 'Three', artist: 'C', duration: Duration(minutes: 2), audioUrl: 'url-3'),
  Track(id: 't4', title: 'Four', artist: 'D', duration: Duration(minutes: 5), audioUrl: 'url-4'),
];

/// Lets the async handlers (which await setUrl) settle between events.
Future<void> _settle() => Future<void>.delayed(Duration.zero);

void main() {
  group('PlayerBloc shuffle', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController());

    blocTest<PlayerBloc, PlayerState>(
      'moves the playing track to the front, keeps every track, and does not touch the audio',
      // Seeded Random keeps the shuffled order deterministic for this test.
      build: () => PlayerBloc(audioController: audio, random: Random(42)),
      seed: () => const PlayerState(queue: _queue, sourceQueue: _queue, currentIndex: 1),
      act: (bloc) => bloc.add(const PlayerShuffleToggled()),
      verify: (bloc) {
        final state = bloc.state;
        expect(state.isShuffled, isTrue);
        // The track that was playing is now first and still current.
        expect(state.currentIndex, 0);
        expect(state.currentTrack?.id, 't2');
        // Nothing gained or lost -- just reordered.
        expect(state.queue.length, _queue.length);
        expect(state.queue.map((t) => t.id).toSet(), {'t1', 't2', 't3', 't4'});
        // Crucially: shuffling must NOT reload or restart playback.
        expect(audio.setUrls, isEmpty);
        expect(audio.playCount, 0);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'toggling off restores the original order with the same track current',
      build: () => PlayerBloc(audioController: audio, random: Random(7)),
      seed: () => const PlayerState(queue: _queue, sourceQueue: _queue, currentIndex: 2),
      act: (bloc) async {
        bloc.add(const PlayerShuffleToggled()); // on
        await _settle();
        bloc.add(const PlayerShuffleToggled()); // off
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state.isShuffled, isFalse);
        expect(state.queue.map((t) => t.id).toList(), ['t1', 't2', 't3', 't4']);
        // 't3' was playing before the shuffle and is still playing after.
        expect(state.currentTrack?.id, 't3');
        expect(state.currentIndex, 2);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'un-shuffling keeps tracks that were added to the queue while shuffled',
      build: () => PlayerBloc(audioController: audio, random: Random(1)),
      act: (bloc) async {
        // Start a real queue so sourceQueue is populated.
        bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0));
        await _settle();
        bloc.add(const PlayerShuffleToggled());
        await _settle();
        bloc.add(const PlayerQueueAppended(
          Track(id: 'tx', title: 'Extra', artist: 'X', duration: Duration(minutes: 1), audioUrl: 'url-x'),
        ));
        await _settle();
        bloc.add(const PlayerShuffleToggled()); // back off
      },
      verify: (bloc) {
        // Source order restored, with the queue-added track kept at the end
        // (sourceQueue never knew about it).
        expect(bloc.state.queue.map((t) => t.id).toList(), ['t1', 't2', 't3', 't4', 'tx']);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'starting a queue while shuffle is on plays the tapped track first',
      build: () => PlayerBloc(audioController: audio, random: Random(3)),
      seed: () => const PlayerState(isShuffled: true),
      act: (bloc) => bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 2)),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 0);
        expect(bloc.state.currentTrack?.id, 't3');
        expect(audio.setUrls, ['url-3']);
        expect(bloc.state.queue.map((t) => t.id).toSet(), {'t1', 't2', 't3', 't4'});
      },
    );
  });

  group('PlayerBloc repeat', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController());

    blocTest<PlayerBloc, PlayerState>(
      'cycles off -> all -> one -> off',
      build: () => PlayerBloc(audioController: audio),
      act: (bloc) async {
        expect(bloc.state.repeatMode, PlayerRepeatMode.off);
        bloc.add(const PlayerRepeatModeCycled());
        await _settle();
        expect(bloc.state.repeatMode, PlayerRepeatMode.all);
        bloc.add(const PlayerRepeatModeCycled());
        await _settle();
        expect(bloc.state.repeatMode, PlayerRepeatMode.one);
        bloc.add(const PlayerRepeatModeCycled());
      },
      verify: (bloc) => expect(bloc.state.repeatMode, PlayerRepeatMode.off),
    );

    blocTest<PlayerBloc, PlayerState>(
      'repeat-one replays the same track when it completes',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(
        queue: _queue,
        currentIndex: 1,
        repeatMode: PlayerRepeatMode.one,
        isPlaying: true,
      ),
      act: (bloc) => audio.emitCompleted(),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, ['url-2']); // reloaded itself
        expect(audio.playCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'repeat-all wraps to the first track after the last one completes',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(
        queue: _queue,
        currentIndex: 3, // last
        repeatMode: PlayerRepeatMode.all,
        isPlaying: true,
      ),
      act: (bloc) => audio.emitCompleted(),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 0);
        expect(audio.setUrls, ['url-1']);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'repeat-off stops at the end of the queue',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 3, isPlaying: true),
      act: (bloc) => audio.emitCompleted(),
      verify: (bloc) {
        expect(bloc.state.isPlaying, isFalse);
        expect(bloc.state.position, Duration.zero);
        expect(audio.setUrls, isEmpty); // nothing new loaded
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'Next wraps around when repeat-all is on',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 3, repeatMode: PlayerRepeatMode.all),
      act: (bloc) => bloc.add(const PlayerNextRequested()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 0);
        expect(audio.setUrls, ['url-1']);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'Previous wraps to the last track when repeat-all is on',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, repeatMode: PlayerRepeatMode.all),
      act: (bloc) => bloc.add(const PlayerPreviousRequested()),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 3);
        expect(audio.setUrls, ['url-4']);
      },
    );

    test('hasNext/hasPrevious open up at the queue edges under repeat-all', () {
      const off = PlayerState(queue: _queue, currentIndex: 3);
      expect(off.hasNext, isFalse);

      const all = PlayerState(queue: _queue, currentIndex: 3, repeatMode: PlayerRepeatMode.all);
      expect(all.hasNext, isTrue);
      expect(const PlayerState(queue: _queue, repeatMode: PlayerRepeatMode.all).hasPrevious, isTrue);
      expect(const PlayerState(queue: _queue).hasPrevious, isFalse);
    });
  });

  group('PlayerBloc volume', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController());

    blocTest<PlayerBloc, PlayerState>(
      'applies volume to state and the engine, clamped to 0..1',
      build: () => PlayerBloc(audioController: audio),
      act: (bloc) async {
        bloc.add(const PlayerVolumeChanged(0.4));
        await _settle();
        bloc.add(const PlayerVolumeChanged(1.7)); // over the top -> clamped
        await _settle();
        bloc.add(const PlayerVolumeChanged(-0.2)); // under -> clamped
      },
      verify: (bloc) {
        expect(bloc.state.volume, 0);
        expect(audio.volumes, [0.4, 1.0, 0.0]);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      're-asserts a non-default volume after loading a track',
      // On web a source switch rebuilds the underlying player, which would
      // otherwise reset volume to full.
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(volume: 0.3),
      act: (bloc) => bloc.add(const PlayerTrackStarted(queue: _queue, startIndex: 0)),
      verify: (bloc) => expect(audio.volumes, [0.3]),
    );

    blocTest<PlayerBloc, PlayerState>(
      'clearing the queue keeps playback preferences',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(
        queue: _queue,
        currentIndex: 1,
        volume: 0.25,
        isShuffled: true,
        repeatMode: PlayerRepeatMode.all,
      ),
      act: (bloc) => bloc.add(const PlayerStopped()),
      verify: (bloc) {
        expect(bloc.state.hasTrack, isFalse);
        expect(bloc.state.queue, isEmpty);
        // Preferences are not part of the listening session.
        expect(bloc.state.volume, 0.25);
        expect(bloc.state.isShuffled, isTrue);
        expect(bloc.state.repeatMode, PlayerRepeatMode.all);
      },
    );
  });
}
