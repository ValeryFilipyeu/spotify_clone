import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/bloc/player_bloc.dart';
import 'package:spotify_clone/player/bloc/player_event.dart';
import 'package:spotify_clone/player/repository/playback_queue_repository.dart';

import '../fake_audio_controller.dart';

const _alice = 'alice@spotify.com';

/// Longer than the bloc's 400ms save debounce.
const _pastDebounce = Duration(milliseconds: 600);

Future<void> _settle() => Future<void>.delayed(Duration.zero);

Track _track(String id) => Track(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  audioUrl: 'stream/$id',
);

/// Records what the player asked to be remembered.
class _FakeQueueRepository implements PlaybackQueueRepository {
  final Map<String, SavedQueue> saved = {};
  final List<SavedQueue> queueWrites = [];
  final List<({int index, Duration position})> positionWrites = [];
  int clears = 0;

  @override
  Future<SavedQueue?> fetchQueue(String userId) async => saved[userId];

  @override
  Future<void> saveQueue(String userId, SavedQueue queue) async {
    queueWrites.add(queue);
    saved[userId] = queue;
  }

  @override
  Future<void> savePosition(
    String userId, {
    required int currentIndex,
    required Duration position,
  }) async {
    positionWrites.add((index: currentIndex, position: position));
    final existing = saved[userId];
    if (existing != null) {
      saved[userId] = SavedQueue(
        queue: existing.queue,
        sourceQueue: existing.sourceQueue,
        currentIndex: currentIndex,
        position: position,
        isShuffled: existing.isShuffled,
      );
    }
  }

  @override
  Future<void> clear(String userId) async {
    clears++;
    saved.remove(userId);
  }
}

void main() {
  late FakeAudioController audio;
  late _FakeQueueRepository queues;
  late StreamController<String?> users;

  setUp(() {
    audio = FakeAudioController();
    queues = _FakeQueueRepository();
    users = StreamController<String?>.broadcast();
  });

  tearDown(() => users.close());

  PlayerBloc build() {
    final bloc = PlayerBloc(
      audioController: audio,
      queueRepository: queues,
      userIdChanges: users.stream,
    );
    addTearDown(bloc.close);
    return bloc;
  }

  /// Signs [userId] in and lets the restore finish.
  Future<PlayerBloc> signedIn({String? userId = _alice}) async {
    final bloc = build();
    users.add(userId);
    await _settle();
    await _settle();
    return bloc;
  }

  group('coming back to a saved session', () {
    setUp(() {
      queues.saved[_alice] = SavedQueue(
        queue: [_track('a'), _track('b'), _track('c')],
        currentIndex: 1,
        position: const Duration(seconds: 42),
      );
    });

    test('puts the queue back where it was', () async {
      final bloc = await signedIn();

      expect(bloc.state.queue.map((t) => t.id), ['a', 'b', 'c']);
      expect(bloc.state.currentIndex, 1);
      expect(bloc.state.position, const Duration(seconds: 42));
      // Seeded from the track, because the engine has not been asked -- without
      // it the scrubber would have a thumb and no scale.
      expect(bloc.state.duration, const Duration(minutes: 3));
    });

    test('does not start playing, or even load anything', () async {
      final bloc = await signedIn();

      expect(bloc.state.isPlaying, isFalse);
      expect(bloc.state.isLoading, isFalse);
      // The point of restoring lazily: a launch does not spend a network round
      // trip on audio nobody has asked to hear.
      expect(audio.setUrls, isEmpty);
      expect(audio.playCount, 0);
    });

    test('presses play by loading the track and jumping to where it was', () async {
      final bloc = await signedIn();

      bloc.add(const PlayerResumeRequested());
      await _settle();

      expect(audio.setUrls, ['stream/b']);
      expect(audio.seeks, [const Duration(seconds: 42)]);
      expect(audio.playCount, 1);
    });

    test('play/pause reaches the same loader', () async {
      // Two events lead here -- the transport button and the lock screen -- and
      // only one of them was wired up in the first attempt.
      final bloc = await signedIn();

      bloc.add(const PlayerPlayPauseToggled());
      await _settle();

      expect(audio.setUrls, ['stream/b']);
    });

    test('only loads once, however many times play is pressed', () async {
      final bloc = await signedIn();

      bloc.add(const PlayerResumeRequested());
      await _settle();
      audio.emitPlaying(true);
      await _settle();
      bloc.add(const PlayerPlayPauseToggled());
      await _settle();
      bloc.add(const PlayerResumeRequested());
      await _settle();

      expect(audio.setUrls, ['stream/b'], reason: 'the engine has it now');
    });

    test('scrubbing before pressing play moves the thumb and nothing else', () async {
      final bloc = await signedIn();

      bloc.add(const PlayerSeekRequested(Duration(seconds: 90)));
      await _settle();

      expect(bloc.state.position, const Duration(seconds: 90));
      expect(audio.seeks, isEmpty, reason: 'there is nothing loaded to seek');

      // ...and the eventual load starts from there rather than from the saved
      // position, which is now stale.
      bloc.add(const PlayerResumeRequested());
      await _settle();
      expect(audio.seeks, [const Duration(seconds: 90)]);
    });

    test('a shuffled session comes back shuffled', () async {
      queues.saved[_alice] = SavedQueue(
        queue: [_track('c'), _track('a')],
        sourceQueue: [_track('a'), _track('b'), _track('c')],
        isShuffled: true,
      );
      final bloc = await signedIn();

      expect(bloc.state.isShuffled, isTrue);
      expect(bloc.state.queue.map((t) => t.id), ['c', 'a']);
      // Without the source order the shuffle button would un-shuffle into the
      // shuffled order, which is to say not at all.
      expect(bloc.state.sourceQueue.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('an account with nothing saved starts empty', () async {
      queues.saved.clear();
      final bloc = await signedIn();

      expect(bloc.state.queue, isEmpty);
      expect(bloc.state.hasTrack, isFalse);
    });

    test('restoring does not write the session straight back out', () async {
      await signedIn();
      // Past the debounce. Without this wait the assertion below passes whether
      // or not the guard exists, because the write it is looking for has not had
      // time to happen yet -- which is exactly how the first version of this test
      // survived having the guard deleted.
      await Future<void>.delayed(_pastDebounce);

      expect(queues.queueWrites, isEmpty);
      expect(queues.positionWrites, isEmpty);
    });
  });

  group('writing the session down', () {
    test('a new queue is saved', () async {
      final bloc = await signedIn();

      bloc.add(PlayerTrackStarted(queue: [_track('a'), _track('b')], startIndex: 1));
      await Future<void>.delayed(_pastDebounce);

      expect(queues.saved[_alice]!.queue.map((t) => t.id), ['a', 'b']);
      expect(queues.saved[_alice]!.currentIndex, 1);
    });

    test('so is an edit to it', () async {
      // Through onChange rather than from each handler, so that the six places
      // that edit a queue cannot each forget.
      final bloc = await signedIn();
      bloc.add(PlayerTrackStarted(queue: [_track('a'), _track('b')], startIndex: 0));
      await Future<void>.delayed(_pastDebounce);
      queues.queueWrites.clear();

      bloc.add(PlayerQueueAppended(_track('c')));
      await Future<void>.delayed(_pastDebounce);

      expect(queues.queueWrites.single.queue.map((t) => t.id), ['a', 'b', 'c']);
    });

    test('the position is written every few seconds, not every tick', () async {
      final bloc = await signedIn();
      bloc.add(PlayerTrackStarted(queue: [_track('a')], startIndex: 0));
      await _settle();
      // Both, and buffering is the one that is easy to forget: a track start
      // leaves isLoading set, and the ticker refuses to advance the position
      // while it is -- so without this the 24 ticks below do nothing at all.
      audio.emitBuffering(false);
      audio.emitPlaying(true);
      // Past the debounce, so the save the track start queued has landed and
      // been counted before the clear below.
      await Future<void>.delayed(_pastDebounce);
      queues.positionWrites.clear();

      // Six seconds of playback: the ticker fires 24 times.
      for (var tick = 0; tick < 24; tick++) {
        bloc.add(const PlayerPositionTicked());
      }
      await Future<void>.delayed(_pastDebounce);

      // Once, not 24 times. Writing four times a second would rewrite the whole
      // preferences file -- catalog cache included -- 240 times a minute.
      expect(queues.positionWrites, hasLength(1));
      expect(queues.positionWrites.single.position, const Duration(seconds: 5));
    });

    test('moving to another track records where we are without rewriting the list', () async {
      final bloc = await signedIn();
      bloc.add(PlayerTrackStarted(queue: [_track('a'), _track('b')], startIndex: 0));
      await Future<void>.delayed(_pastDebounce);
      queues.queueWrites.clear();
      queues.positionWrites.clear();

      bloc.add(const PlayerNextRequested());
      await Future<void>.delayed(_pastDebounce);

      expect(queues.positionWrites.last.index, 1);
      expect(queues.queueWrites, isEmpty, reason: 'the tracklist did not change');
    });

    test('stopping forgets the session rather than saving an empty one', () async {
      // Closing the app is not stopping. Dismissing playback is, and a queue that
      // came back after being dismissed would be a bug with a long memory.
      final bloc = await signedIn();
      bloc.add(PlayerTrackStarted(queue: [_track('a')], startIndex: 0));
      await Future<void>.delayed(_pastDebounce);

      bloc.add(const PlayerStopped());
      await Future<void>.delayed(_pastDebounce);

      expect(queues.clears, 1);
      expect(queues.saved[_alice], isNull);
    });

    test('nothing is written for a signed-out player', () async {
      final bloc = await signedIn(userId: null);

      bloc.add(PlayerTrackStarted(queue: [_track('a')], startIndex: 0));
      await Future<void>.delayed(_pastDebounce);

      expect(queues.queueWrites, isEmpty);
      expect(queues.positionWrites, isEmpty);
    });
  });

  group('without a repository at all', () {
    test('the player behaves exactly as it did before', () async {
      // The optional dependency has to stay genuinely optional: every widget test
      // in the suite builds a PlayerBloc without one.
      final bloc = PlayerBloc(audioController: audio);
      addTearDown(bloc.close);

      bloc.add(PlayerTrackStarted(queue: [_track('a')], startIndex: 0));
      await _settle();

      expect(bloc.state.currentTrack?.id, 'a');
      expect(audio.setUrls, ['stream/a']);
    });
  });
}
