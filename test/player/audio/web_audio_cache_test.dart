@TestOn('vm')
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:just_audio/just_audio.dart';
import 'package:spotify_clone/player/audio/web/audio_blob_store.dart';
import 'package:spotify_clone/player/audio/web/web_audio_cache.dart';

import '../../helpers/fake_key_value_store.dart';

const _a = 'https://api.audius.co/v1/tracks/aaa/stream';
const _b = 'https://api.audius.co/v1/tracks/bbb/stream';
const _c = 'https://api.audius.co/v1/tracks/ccc/stream';

/// A clock the test moves by hand, so "least recently played" is something it
/// decides rather than something a wall clock happens to record.
class _FakeClock {
  DateTime value = DateTime(2026, 8, 26, 10);
  DateTime call() => value;
  void advance(Duration by) => value = value.add(by);
}

/// Hands out a *fresh* handle per call, so a test can tell one lookup from two.
class _FakeBlobStore implements AudioBlobStore {
  final Map<String, String> stored = {};
  final List<String> downloads = [];
  final List<String> released = [];

  bool failDownloads = false;
  int _handles = 0;

  @override
  Future<void> download(String url) async {
    downloads.add(url);
    if (failDownloads) throw StateError('offline');
    stored[url] = url;
  }

  @override
  Future<String?> localUrlFor(String url) async =>
      stored.containsKey(url) ? 'blob:${_handles++}:$url' : null;

  @override
  Future<void> delete(String url) async => stored.remove(url);

  @override
  Future<List<String>> keys() async => stored.keys.toList();

  @override
  void release(String localUrl) => released.add(localUrl);
}

/// Lets the fire-and-forget download in [WebAudioCache.sourceFor] finish.
Future<void> settle() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

String uriOf(AudioSource source) => (source as UriAudioSource).uri.toString();

void main() {
  late _FakeBlobStore blobs;
  late FakeKeyValueStore played;
  late _FakeClock clock;

  WebAudioCache build({int keepTracks = 5}) =>
      WebAudioCache(blobs, played, keepTracks: keepTracks, clock: clock.call);

  setUp(() {
    blobs = _FakeBlobStore();
    played = FakeKeyValueStore();
    clock = _FakeClock();
  });

  group('first play', () {
    test('streams from the network rather than waiting for the download', () async {
      final cache = build();

      final source = await cache.sourceFor(_a);

      expect(uriOf(source), _a);
    });

    test('saves the track for next time', () async {
      final cache = build();

      await cache.sourceFor(_a);
      await settle();

      expect(blobs.stored.keys, [_a]);
    });
  });

  group('once saved', () {
    test('is played from storage, not fetched again', () async {
      final cache = build();
      await cache.sourceFor(_a);
      await settle();
      blobs.downloads.clear();

      final source = await cache.sourceFor(_a);

      expect(uriOf(source), startsWith('blob:'));
      expect(blobs.downloads, isEmpty);
    });

    test('a replay reuses one handle instead of copying the bytes again', () async {
      final cache = build();
      await cache.sourceFor(_a);
      await settle();

      final first = uriOf(await cache.sourceFor(_a));
      final second = uriOf(await cache.sourceFor(_a));

      expect(second, first);
    });
  });

  group('eviction', () {
    test('keeps only the newest keepTracks', () async {
      final cache = build(keepTracks: 2);

      for (final url in [_a, _b, _c]) {
        await cache.sourceFor(url);
        await settle();
        clock.advance(const Duration(minutes: 1));
      }

      expect(blobs.stored.keys, unorderedEquals([_b, _c]));
    });

    test('oldest means least recently played, not least recently downloaded', () async {
      final cache = build(keepTracks: 2);
      for (final url in [_a, _b]) {
        await cache.sourceFor(url);
        await settle();
        clock.advance(const Duration(minutes: 1));
      }

      // Replay the older one, then add a third: _b is now the stale one.
      await cache.sourceFor(_a);
      clock.advance(const Duration(minutes: 1));
      await cache.sourceFor(_c);
      await settle();

      expect(blobs.stored.keys, unorderedEquals([_a, _c]));
    });

    test('releases the handle of a track it evicts', () async {
      final cache = build(keepTracks: 1);
      await cache.sourceFor(_a);
      await settle();
      final handle = uriOf(await cache.sourceFor(_a));

      clock.advance(const Duration(minutes: 1));
      await cache.sourceFor(_b);
      await settle();

      expect(blobs.released, [handle]);
    });

    test('drops a track stored with no recorded play before one with', () async {
      // Survived an index that was cleared: treating it as new would make it
      // immortal.
      blobs.stored[_a] = _a;
      final cache = build(keepTracks: 1);

      await cache.sourceFor(_b);
      await settle();

      expect(blobs.stored.keys, [_b]);
    });

    test('forgets timestamps for tracks it no longer holds', () async {
      final cache = build(keepTracks: 1);
      for (final url in [_a, _b]) {
        await cache.sourceFor(url);
        await settle();
        clock.advance(const Duration(minutes: 1));
      }

      expect(played.values.values.single, isNot(contains('aaa')));
    });
  });

  group('when things go wrong', () {
    test('a failed download still plays from the network', () async {
      blobs.failDownloads = true;
      final cache = build();

      final source = await cache.sourceFor(_a);
      await settle();

      expect(uriOf(source), _a);
      expect(blobs.stored, isEmpty);
    });

    test('two players asking at once download once', () async {
      final cache = build();

      await Future.wait([cache.sourceFor(_a), cache.sourceFor(_a)]);
      await settle();

      expect(blobs.downloads, [_a]);
    });

    test('an unreadable index is an empty history, not a crash', () async {
      played.values['audio_cache_played'] = 'not json at all';
      final cache = build();

      final source = await cache.sourceFor(_a);
      await settle();

      expect(uriOf(source), _a);
      expect(blobs.stored.keys, [_a]);
    });

    test('a store that cannot be written to still plays', () async {
      played.failWrites = true;
      final cache = build();

      await cache.sourceFor(_a);
      await settle();
      final source = await cache.sourceFor(_a);

      expect(uriOf(source), startsWith('blob:'));
    });
  });
}
