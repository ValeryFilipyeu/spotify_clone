@TestOn('vm')
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotify_clone/player/audio/audio_cache_io.dart';

// See audio_cache_io.dart: the class this exercises is marked experimental
// upstream, which is a fact about just_audio and not a reason to shout here.
// ignore_for_file: experimental_member_use

const _a = 'https://api.audius.co/v1/tracks/aaa/stream';
const _b = 'https://api.audius.co/v1/tracks/bbb/stream';

/// A clock the test moves by hand, so "least recently played" is something it
/// decides rather than something the filesystem happens to record.
class _FakeClock {
  DateTime value = DateTime(2026, 8, 21, 10);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

void main() {
  late Directory directory;
  late _FakeClock clock;

  setUp(() {
    directory = Directory.systemTemp.createTempSync('audio_cache_test');
    clock = _FakeClock();
    addTearDown(() {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    });
  });

  FileAudioCache cacheWith({int keepTracks = 5}) =>
      FileAudioCache(directory, keepTracks: keepTracks, clock: clock.call);

  /// A track already fully downloaded, played [age] ago.
  void alreadyHave(FileAudioCache cache, String url, {Duration age = Duration.zero}) {
    final file = cache.fileFor(url)..writeAsBytesSync(List.filled(64, 0));
    File('${file.path}.mime').writeAsStringSync('audio/mpeg');
    file.setLastModifiedSync(clock.value.subtract(age));
  }

  group('choosing a source', () {
    test('a track never played is streamed and written down as it goes', () async {
      final cache = cacheWith();

      final source = await cache.sourceFor(_a);

      expect(source, isA<LockCachingAudioSource>());
      // Into our directory, not just_audio's own -- which is what makes the
      // eviction below possible at all.
      // By path: dart:io's File compares by identity, not by what it points at.
      expect((await (source as LockCachingAudioSource).cacheFile).path, cache.fileFor(_a).path);
    });

    test('a track already on disk is served from that file, not fetched again', () async {
      final cache = cacheWith();
      alreadyHave(cache, _a);

      final source = await cache.sourceFor(_a);

      expect(source, isA<LockCachingAudioSource>());
      expect((await (source as LockCachingAudioSource).cacheFile).path, cache.fileFor(_a).path);
    });

    test('a cached track is never handed over as a bare file uri', () async {
      // This is the whole reason the case above goes back through
      // LockCachingAudioSource rather than taking the obvious shortcut of
      // AudioSource.uri(Uri.file(path)).
      //
      // AVFoundation reads a local file's container format off its path
      // EXTENSION, and these files are named by hash and have none -- so
      // AVURLAsset refuses every one of them with -11828, and a cached track
      // loads, appears in the player, and plays silence. Measured on a
      // simulator; nothing in this suite noticed, because the old test asserted
      // the shape of the source and never that it could be opened.
      //
      // The shape is still what is asserted here -- a unit test cannot make a
      // sound -- but it is now the shape that carries the MIME type recorded
      // with the bytes, so the platform is never left to guess.
      final cache = cacheWith();
      alreadyHave(cache, _a);

      final source = await cache.sourceFor(_a);

      expect(
        source,
        isNot(isA<UriAudioSource>()),
        reason:
            'a UriAudioSource here would be either a file the platform '
            'cannot identify or a needless re-download',
      );
    });

    test('a second player asking for a download in flight streams it uncached', () async {
      // The narrow window the guard exists for: repeat-one plus crossfade on a
      // track being heard for the first time. Two caching sources would
      // interleave into one `.part` file, and the rename at the end would
      // publish the mess as a finished track.
      final cache = cacheWith();
      await cache.sourceFor(_a);

      final second = await cache.sourceFor(_a);

      expect(second, isA<UriAudioSource>());
      expect(
        (second as UriAudioSource).uri.isScheme('https'),
        isTrue,
        reason: 'straight to the network',
      );
    });
  });

  group('keeping the last few', () {
    test('replaying a track counts as playing it', () async {
      // Otherwise "oldest" would mean least recently *downloaded*, and a
      // favourite played daily would be evicted the moment five new tracks
      // appeared behind it.
      final cache = cacheWith();
      alreadyHave(cache, _a, age: const Duration(days: 2));

      clock.advance(const Duration(hours: 1));
      await cache.sourceFor(_a);

      expect(cache.fileFor(_a).lastModifiedSync(), clock.value);
    });

    test('makes room before adding, so the limit is never exceeded', () async {
      final cache = cacheWith(keepTracks: 3);
      for (final (index, url) in ['t0', 't1', 't2'].indexed) {
        alreadyHave(cache, url, age: Duration(hours: 10 - index));
      }

      await cache.sourceFor(_b);

      expect(cache.fileFor('t0').existsSync(), isFalse, reason: 'least recently played');
      expect(cache.fileFor('t1').existsSync(), isTrue);
      expect(cache.fileFor('t2').existsSync(), isTrue);
    });

    test('takes the mime file with it', () async {
      // Left behind, these accumulate silently: nothing counts them, so the
      // directory grows litter that no eviction will ever notice.
      final cache = cacheWith(keepTracks: 1);
      alreadyHave(cache, 't0', age: const Duration(hours: 5));

      await cache.sourceFor(_b);

      expect(cache.fileFor('t0').existsSync(), isFalse);
      expect(File('${cache.fileFor('t0').path}.mime').existsSync(), isFalse);
    });

    test('never deletes a download in progress', () async {
      // A `.part` is somebody's open file handle. Counting it as a track would
      // also mean counting the same download twice.
      final cache = cacheWith(keepTracks: 1);
      final inFlight = File('${cache.fileFor('t9').path}.part')..writeAsBytesSync([1, 2, 3]);
      alreadyHave(cache, 't0', age: const Duration(hours: 5));

      await cache.sourceFor(_b);

      expect(inFlight.existsSync(), isTrue);
    });

    test('leaves a cache under the limit alone', () async {
      final cache = cacheWith(keepTracks: 5);
      alreadyHave(cache, 't0', age: const Duration(hours: 5));
      alreadyHave(cache, 't1', age: const Duration(hours: 4));

      await cache.sourceFor(_b);

      expect(cache.fileFor('t0').existsSync(), isTrue);
      expect(cache.fileFor('t1').existsSync(), isTrue);
    });
  });

  group('filenames', () {
    test('two urls do not collide, and one url is stable', () {
      final cache = cacheWith();

      expect(cache.fileFor(_a).path, isNot(cache.fileFor(_b).path));
      expect(cache.fileFor(_a).path, cache.fileFor(_a).path);
    });

    test('a url far longer than a filename may be still works', () {
      final cache = cacheWith();
      final url = 'https://node.example/v1/tracks/${'Qm4rP7xK' * 40}/stream';

      expect(cache.fileFor(url).path.split('/').last.length, lessThan(255));
    });
  });
}
