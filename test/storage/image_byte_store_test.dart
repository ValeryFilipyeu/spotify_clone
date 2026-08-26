@TestOn('vm')
library;

import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:spotify_clone/storage/image_byte_store_io.dart';

Uint8List bytes(int length, {int fill = 7}) => Uint8List.fromList(List.filled(length, fill));

void main() {
  late Directory directory;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('cover_cache_test');
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  FileImageByteStore storeWith({int maxBytes = 1000}) =>
      FileImageByteStore(directory, maxBytes: maxBytes);

  /// Written times are what eviction sorts on, and a filesystem can hand two
  /// files created a microsecond apart the same one. Set them by hand so the
  /// order under test is the order the test asked for, not the order the
  /// filesystem happened to record.
  void ageOf(FileImageByteStore store, String url, Duration age) =>
      store.fileFor(url).setLastModifiedSync(DateTime(2026, 8, 20).subtract(age));

  group('keeping and returning bytes', () {
    test('gives back exactly what it was given', () async {
      final store = storeWith();
      await store.write('https://node/a.jpg', bytes(120));

      expect(await store.read('https://node/a.jpg'), bytes(120));
    });

    test('has nothing for a url it was never given', () async {
      expect(await storeWith().read('https://node/never.jpg'), isNull);
    });

    test('keeps two urls apart', () async {
      final store = storeWith();
      await store.write('https://one/a.jpg', bytes(10, fill: 1));
      await store.write('https://two/a.jpg', bytes(10, fill: 2));

      expect(await store.read('https://one/a.jpg'), bytes(10, fill: 1));
      expect(await store.read('https://two/a.jpg'), bytes(10, fill: 2));
    });

    test('overwrites rather than accumulating for the same url', () async {
      final store = storeWith();
      await store.write('https://node/a.jpg', bytes(100));
      await store.write('https://node/a.jpg', bytes(40));

      expect(await store.read('https://node/a.jpg'), hasLength(40));
      expect(directory.listSync(), hasLength(1));
      expect(store.bytesHeld, 40, reason: 'the replaced bytes are not still counted');
    });

    test('handles a url far longer than a filename may be', () async {
      // The entire reason the key is hashed. Every path component is capped at
      // 255 bytes and a real Audius cover url runs to about 110 -- but a url is
      // not bounded by anything, and one that overflows would fail at the
      // filesystem with an error nobody would connect to a cover.
      final store = storeWith();
      final url = 'https://node.example/content/${'Qm4rP7xK' * 40}/480x480.jpg';
      expect(url.length, greaterThan(300));

      await store.write(url, bytes(50));
      expect(await store.read(url), hasLength(50));
    });

    test('forgets one entry on request', () async {
      final store = storeWith();
      await store.write('https://node/a.jpg', bytes(60));
      await store.delete('https://node/a.jpg');

      expect(await store.read('https://node/a.jpg'), isNull);
      expect(store.bytesHeld, 0);
    });

    test('deleting something that is not there is not an error', () async {
      await expectLater(storeWith().delete('https://node/gone.jpg'), completes);
    });
  });

  group('surviving the OS', () {
    test('a file swept out from under it reads as a miss', () async {
      // Not hypothetical: these live in the cache directory precisely so the
      // system may reclaim them, so every read has to cope with the file having
      // vanished since it was written.
      final store = storeWith();
      await store.write('https://node/a.jpg', bytes(60));
      directory.listSync().whereType<File>().single.deleteSync();

      expect(await store.read('https://node/a.jpg'), isNull);
    });

    test('counts what a previous launch left behind', () async {
      final first = storeWith();
      await first.write('https://node/a.jpg', bytes(300));
      await first.write('https://node/b.jpg', bytes(200));

      // A fresh process, same directory. Without the measurement the budget
      // would be enforced against zero and the cache could grow without limit
      // across restarts.
      final second = storeWith();
      expect(second.bytesHeld, 0, reason: 'nothing is known before measuring');
      await second.measure();
      expect(second.bytesHeld, 500);
      expect(await second.read('https://node/a.jpg'), hasLength(300));
    });
  });

  group('the budget', () {
    test('sweeps the oldest away once it is over', () async {
      final store = storeWith(maxBytes: 1000);
      await store.write('a', bytes(400));
      ageOf(store, 'a', const Duration(days: 3));
      await store.write('b', bytes(400));
      ageOf(store, 'b', const Duration(days: 2));
      await store.write('c', bytes(400));

      expect(await store.read('a'), isNull, reason: 'oldest goes first');
      expect(await store.read('c'), isNotNull, reason: 'the one just written stays');
      expect(store.bytesHeld, lessThanOrEqualTo(800), reason: 'swept to 80% of the budget');
    });

    test('clears well past the limit when it does sweep', () async {
      // Deliberate hysteresis, and the reason the trigger and the target are
      // different numbers. Freeing exactly enough room for the newest file would
      // mean listing and stat-ing the whole directory on every write once the
      // cache is full, for the sake of deleting one cover.
      final store = storeWith(maxBytes: 1000);
      for (final (index, url) in ['a', 'b', 'c'].indexed) {
        await store.write(url, bytes(300));
        ageOf(store, url, Duration(days: 10 - index));
      }
      expect(store.bytesHeld, 900, reason: 'still under: nothing has been swept yet');

      await store.write('d', bytes(300));

      // 1200 over a 1000 budget, so it sweeps -- and takes two covers rather than
      // the one that would have been enough.
      expect(store.bytesHeld, 600);
      expect(await store.read('a'), isNull);
      expect(await store.read('b'), isNull);
      expect(await store.read('c'), isNotNull);
      expect(await store.read('d'), isNotNull);
    });

    test('never ends a write over budget, however many there are', () async {
      final store = storeWith(maxBytes: 1000);
      for (var index = 0; index < 25; index++) {
        await store.write('cover$index', bytes(180));
        ageOf(store, 'cover$index', Duration(minutes: 100 - index));
        expect(store.bytesHeld, lessThanOrEqualTo(1000));
      }
      // And the count on disk agrees with the running total it has been keeping
      // in memory all along -- which is the number the budget is enforced
      // against, so a drift between the two would be a leak nobody could see.
      final onDisk = directory.listSync().whereType<File>().fold(
        0,
        (total, file) => total + file.lengthSync(),
      );
      expect(store.bytesHeld, onDisk);
    });

    test('refuses a single file bigger than the whole budget', () async {
      // Writing it would evict everything else and then sweep the thing itself,
      // which is a lot of I/O to end up exactly where it started.
      final store = storeWith(maxBytes: 500);
      await store.write('a', bytes(100));
      await store.write('huge', bytes(600));

      expect(await store.read('huge'), isNull);
      expect(await store.read('a'), isNotNull, reason: 'and it took nothing down with it');
    });
  });
}
