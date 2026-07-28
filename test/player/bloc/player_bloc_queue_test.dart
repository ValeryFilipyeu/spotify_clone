import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/bloc/player_state.dart';

import '../fake_audio_controller.dart';

const _t1 = Track(id: 't1', title: 'One', artist: 'A', duration: Duration(minutes: 3), audioUrl: 'url-1');
const _t2 = Track(id: 't2', title: 'Two', artist: 'B', duration: Duration(minutes: 4), audioUrl: 'url-2');
const _t3 = Track(id: 't3', title: 'Three', artist: 'C', duration: Duration(minutes: 2), audioUrl: 'url-3');
const _t4 = Track(id: 't4', title: 'Four', artist: 'D', duration: Duration(minutes: 5), audioUrl: 'url-4');
const _tx = Track(id: 'tx', title: 'Extra', artist: 'X', duration: Duration(minutes: 1), audioUrl: 'url-x');

const _queue = [_t1, _t2, _t3, _t4];

List<String> _ids(PlayerState state) => state.queue.map((t) => t.id).toList();

void main() {
  group('PlayerBloc queue', () {
    late FakeAudioController audio;

    setUp(() => audio = FakeAudioController());

    test('upNext lists only the tracks after the current one', () {
      const state = PlayerState(queue: _queue, currentIndex: 1);
      expect(state.upNext.map((t) => t.id).toList(), ['t3', 't4']);
      // Nothing after the last track.
      expect(const PlayerState(queue: _queue, currentIndex: 3).upNext, isEmpty);
    });

    // --- Reordering ---

    blocTest<PlayerBloc, PlayerState>(
      'reordering the queue keeps the same track playing and never reloads audio',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1), // t2 playing
      // Drag t4 (index 3) to sit right after the current track (index 2).
      act: (bloc) => bloc.add(const PlayerQueueReordered(oldIndex: 3, newIndex: 2)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't2', 't4', 't3']);
        // t2 is untouched at index 1 and still playing -- no reload.
        expect(bloc.state.currentTrack?.id, 't2');
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'dragging a track from before the current one shifts the current index down',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 2), // t3 playing
      // Move t1 (before current) to the very end.
      act: (bloc) => bloc.add(const PlayerQueueReordered(oldIndex: 0, newIndex: 3)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t2', 't3', 't4', 't1']);
        expect(bloc.state.currentTrack?.id, 't3'); // followed its track
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'dragging the current track itself moves the index with it',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0), // t1 playing
      act: (bloc) => bloc.add(const PlayerQueueReordered(oldIndex: 0, newIndex: 2)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t2', 't3', 't1', 't4']);
        expect(bloc.state.currentTrack?.id, 't1');
        expect(bloc.state.currentIndex, 2);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'out-of-range reorders are ignored',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerQueueReordered(oldIndex: 0, newIndex: 9)),
      verify: (bloc) => expect(_ids(bloc.state), ['t1', 't2', 't3', 't4']),
    );

    // --- Removing ---

    blocTest<PlayerBloc, PlayerState>(
      'removing a track after the current one leaves playback alone',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1),
      act: (bloc) => bloc.add(const PlayerQueueItemRemoved(3)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't2', 't3']);
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'removing a track before the current one shifts the index down',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 2), // t3
      act: (bloc) => bloc.add(const PlayerQueueItemRemoved(0)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t2', 't3', 't4']);
        expect(bloc.state.currentTrack?.id, 't3'); // same track still playing
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'removing the playing track plays whatever shifts into its slot',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1), // t2 playing
      act: (bloc) => bloc.add(const PlayerQueueItemRemoved(1)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't3', 't4']);
        expect(bloc.state.currentTrack?.id, 't3');
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, ['url-3']); // it did have to load
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'removing the playing track when it is last falls back to the new last track',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 3),
      act: (bloc) => bloc.add(const PlayerQueueItemRemoved(3)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't2', 't3']);
        expect(bloc.state.currentTrack?.id, 't3');
        expect(audio.setUrls, ['url-3']);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'removing the only track stops playback and clears the player',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: [_t1], volume: 0.5),
      act: (bloc) => bloc.add(const PlayerQueueItemRemoved(0)),
      verify: (bloc) {
        expect(bloc.state.queue, isEmpty);
        expect(bloc.state.hasTrack, isFalse);
        expect(audio.stopCount, 1);
        expect(bloc.state.volume, 0.5); // preference survives
      },
    );

    // --- Jumping ---

    blocTest<PlayerBloc, PlayerState>(
      'selecting a queue entry jumps straight to it',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 0),
      act: (bloc) => bloc.add(const PlayerQueueIndexSelected(2)),
      verify: (bloc) {
        expect(bloc.state.currentIndex, 2);
        expect(bloc.state.position, Duration.zero);
        expect(audio.setUrls, ['url-3']);
        expect(audio.playCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'selecting the already-playing entry does not restart it',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 2),
      act: (bloc) => bloc.add(const PlayerQueueIndexSelected(2)),
      verify: (bloc) => expect(audio.setUrls, isEmpty),
    );

    // --- Adding ---

    blocTest<PlayerBloc, PlayerState>(
      'add-to-queue appends without disturbing playback',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1),
      act: (bloc) => bloc.add(const PlayerQueueAppended(_tx)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't2', 't3', 't4', 'tx']);
        expect(bloc.state.currentIndex, 1);
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'play-next inserts directly after the current track',
      build: () => PlayerBloc(audioController: audio),
      seed: () => const PlayerState(queue: _queue, currentIndex: 1),
      act: (bloc) => bloc.add(const PlayerPlayNextEnqueued(_tx)),
      verify: (bloc) {
        expect(_ids(bloc.state), ['t1', 't2', 'tx', 't3', 't4']);
        expect(bloc.state.currentIndex, 1);
        expect(bloc.state.upNext.first.id, 'tx');
        expect(audio.setUrls, isEmpty);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'queueing onto an empty player starts playing that track',
      build: () => PlayerBloc(audioController: audio),
      act: (bloc) => bloc.add(const PlayerQueueAppended(_tx)),
      verify: (bloc) {
        expect(bloc.state.currentTrack?.id, 'tx');
        expect(audio.setUrls, ['url-x']);
        expect(audio.playCount, 1);
      },
    );

    blocTest<PlayerBloc, PlayerState>(
      'play-next on an empty player starts playing that track',
      build: () => PlayerBloc(audioController: audio),
      act: (bloc) => bloc.add(const PlayerPlayNextEnqueued(_tx)),
      verify: (bloc) {
        expect(bloc.state.currentTrack?.id, 'tx');
        expect(audio.setUrls, ['url-x']);
      },
    );
  });
}
