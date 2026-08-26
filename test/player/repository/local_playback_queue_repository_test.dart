import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/catalog/models/track.dart';
import 'package:spotify_clone/player/repository/local_playback_queue_repository.dart';
import 'package:spotify_clone/player/repository/playback_queue_repository.dart';

import '../../helpers/fake_key_value_store.dart';

const _alice = 'alice@spotify.com';
const _bob = 'bob@spotify.com';

Track _track(String id) => Track(
  id: id,
  title: 'Track $id',
  artist: 'Artist $id',
  duration: const Duration(minutes: 3),
  audioUrl: 'https://api.audius.co/v1/tracks/$id/stream',
  coverUrls: ['https://node.example/content/$id/480x480.jpg'],
);

void main() {
  late FakeKeyValueStore store;
  late LocalPlaybackQueueRepository repository;

  setUp(() {
    store = FakeKeyValueStore();
    repository = LocalPlaybackQueueRepository(store);
  });

  group('a session that was saved', () {
    test('comes back whole', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a'), _track('b')]));
      await repository.savePosition(_alice, currentIndex: 1, position: const Duration(seconds: 42));

      final restored = await repository.fetchQueue(_alice);
      expect(restored!.queue, [_track('a'), _track('b')]);
      expect(restored.currentIndex, 1);
      expect(restored.position, const Duration(seconds: 42));
      expect(restored.isShuffled, isFalse);
    });

    test('keeps the unshuffled order apart from the playing one', () async {
      await repository.saveQueue(
        _alice,
        SavedQueue(
          queue: [_track('c'), _track('a'), _track('b')],
          sourceQueue: [_track('a'), _track('b'), _track('c')],
          isShuffled: true,
        ),
      );

      final restored = await repository.fetchQueue(_alice);
      expect(restored!.queue.map((t) => t.id), ['c', 'a', 'b']);
      expect(restored.effectiveSourceQueue.map((t) => t.id), ['a', 'b', 'c']);
      expect(restored.isShuffled, isTrue);
    });

    test('does not write the same list twice when nothing shuffled it', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a'), _track('b')]));

      final written = store.values['playback_queue:$_alice']!;
      expect(written, isNot(contains('sourceQueue')));
      // And it still reads back as a usable source order, rather than as nothing.
      final restored = await repository.fetchQueue(_alice);
      expect(restored!.effectiveSourceQueue, restored.queue);
    });

    test('belongs to one account', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a')]));

      expect(await repository.fetchQueue(_bob), isNull);
    });
  });

  group('the split between the tracklist and the position', () {
    test('moving the position leaves the tracklist alone', () async {
      // The entire reason there are two keys. The position moves four times a
      // second and the tracklist is tens of kilobytes: writing them together
      // would rewrite the whole preferences file, catalog cache and all, every
      // few seconds of playback.
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a'), _track('b')]));
      store.clearLog();

      await repository.savePosition(_alice, currentIndex: 1, position: const Duration(seconds: 9));

      expect(store.writes, ['playback_position:$_alice']);
    });

    test('a position with no tracklist behind it is not a session', () async {
      await repository.savePosition(_alice, currentIndex: 3, position: const Duration(seconds: 9));

      expect(await repository.fetchQueue(_alice), isNull);
    });

    test('an index pointing past a shorter queue is pulled back into it', () async {
      // The two keys can disagree: a crash between writing a new, shorter queue
      // and writing its position leaves an index from the old one. Restoring
      // that would index past the end and take the player down at launch.
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a'), _track('b')]));
      await repository.savePosition(_alice, currentIndex: 9, position: Duration.zero);

      expect((await repository.fetchQueue(_alice))!.currentIndex, 1);
    });

    test('a missing position just means the beginning', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a')]));

      final restored = await repository.fetchQueue(_alice);
      expect(restored!.currentIndex, 0);
      expect(restored.position, Duration.zero);
    });
  });

  group('nothing usable', () {
    test('an account that has never played anything', () async {
      expect(await repository.fetchQueue(_alice), isNull);
    });

    test('a payload that is not JSON', () async {
      store.values['playback_queue:$_alice'] = 'not json {';

      // Silence rather than an exception: a player that refused to start because
      // a stale session would not parse is worse than one that starts empty, and
      // the next thing played overwrites it.
      expect(await repository.fetchQueue(_alice), isNull);
    });

    test('a payload from an older version of the format', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a')]));
      store.values['playback_queue:$_alice'] = store.values['playback_queue:$_alice']!.replaceFirst(
        '"v":1',
        '"v":0',
      );

      expect(await repository.fetchQueue(_alice), isNull);
    });

    test('a track missing something it cannot be played without', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a')]));
      store.values['playback_queue:$_alice'] = store.values['playback_queue:$_alice']!.replaceFirst(
        '"audioUrl"',
        '"audioUrlWas"',
      );

      expect(await repository.fetchQueue(_alice), isNull);
    });

    test('an empty tracklist', () async {
      store.values['playback_queue:$_alice'] = '{"v":1,"queue":[],"isShuffled":false}';

      // Restoring it would leave a player that believes it has a session and
      // cannot say what is in it.
      expect(await repository.fetchQueue(_alice), isNull);
    });
  });

  group('clear', () {
    test('takes both keys with it', () async {
      await repository.saveQueue(_alice, SavedQueue(queue: [_track('a')]));
      await repository.savePosition(_alice, currentIndex: 0, position: const Duration(seconds: 5));

      await repository.clear(_alice);

      expect(await repository.fetchQueue(_alice), isNull);
      expect(store.keys, isEmpty, reason: 'including the position, which nothing else clears');
    });
  });
}
