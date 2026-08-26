import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotify_clone/catalog/images/cover_image_provider.dart';

import '../../helpers/fake_image_byte_store.dart';

const _url = 'https://node.example/content/Qm123/480x480.jpg';

void main() {
  late FakeImageByteStore store;
  late List<Uri> fetched;

  setUp(() {
    store = FakeImageByteStore();
    fetched = [];
    // Providers are cached by key across a test file, and every test here uses
    // the same url on purpose -- so without this the second one would be handed
    // the first one's decoded image and prove nothing.
    PaintingBinding.instance.imageCache.clear();
  });

  /// Answers with a real PNG, and records that it was asked.
  Future<Uint8List> serving(Uri url) async {
    fetched.add(url);
    return tinyPng;
  }

  Future<ImageInfo> listen(ImageProvider provider) {
    final completed = Completer<ImageInfo>();
    provider
        .resolve(ImageConfiguration.empty)
        .addListener(
          ImageStreamListener(
            (info, _) {
              if (!completed.isCompleted) completed.complete(info);
            },
            onError: (error, stack) {
              if (!completed.isCompleted) completed.completeError(error);
            },
          ),
        );
    return completed.future;
  }

  /// Resolves [provider] to its first frame, or to whatever it threw.
  ///
  /// Through `runAsync`, and it has to be. A widget test runs its body on a fake
  /// clock, but decoding an image is real work on a real thread -- so awaiting a
  /// decode inside the fake one deadlocks: the future cannot complete until time
  /// advances, and time cannot advance until the future completes. The first
  /// version of this hung for five minutes and took every test after it down
  /// with it.
  Future<ImageInfo> load(WidgetTester tester, ImageProvider provider) async =>
      (await tester.runAsync(() => listen(provider)))!;

  /// Whatever [provider] failed with.
  ///
  /// The failure is caught *inside* the `runAsync` callback rather than around
  /// it, which is not a style choice: `runAsync` does not rethrow: it hands the
  /// exception to the test framework as an unhandled one and returns null. So
  /// `throwsA` cannot see through it, and the test would fail with the very error
  /// it was asserting.
  Future<Object?> loadFailure(WidgetTester tester, ImageProvider provider) =>
      tester.runAsync<Object?>(() async {
        try {
          await listen(provider);
          return null;
        } on Object catch (error) {
          return error;
        }
      });

  group('choosing a provider', () {
    test('with nowhere to cache, it is the plain network one', () {
      // The web's case, and every widget test written before this existed. Not a
      // degraded mode -- it is exactly what the app did before, including the web
      // fallback strategy that a cover on a CORS-shy host depends on.
      final provider = coverImageProvider(_url);

      expect(provider, isA<NetworkImage>());
      expect((provider as NetworkImage).webHtmlElementStrategy, WebHtmlElementStrategy.fallback);
    });

    test('with a store, it is the caching one', () {
      expect(coverImageProvider(_url, store: store), isA<CachedNetworkImage>());
    });
  });

  group('loading a cover', () {
    testWidgets('fetches it once and keeps it', (tester) async {
      final provider = coverImageProvider(_url, store: store, fetch: serving);

      final info = await load(tester, provider);
      expect(info.image.width, 2, reason: 'the real png decoded');
      expect(fetched, [Uri.parse(_url)]);
      expect(store.files.keys, [_url]);
    });

    testWidgets('serves a saved cover without going near the network', (tester) async {
      store.files[_url] = tinyPng;
      final provider = coverImageProvider(_url, store: store, fetch: serving);

      final info = await load(tester, provider);
      expect(info.image.width, 2);
      expect(fetched, isEmpty, reason: 'the whole point');
    });

    testWidgets('throws away a saved cover that will not decode, and refetches', (tester) async {
      // A write cut short by the process dying, or a file the OS truncated.
      // Without this the cover stays broken until the entry ages out, because
      // nothing would ever try to replace it.
      store.files[_url] = notAnImage;
      final provider = coverImageProvider(_url, store: store, fetch: serving);

      final info = await load(tester, provider);
      expect(info.image.width, 2);
      expect(store.deletes, [_url]);
      expect(fetched, [Uri.parse(_url)]);
      expect(store.files[_url], tinyPng, reason: 'and the good bytes replaced it');
    });

    testWidgets('reports a refusal as an error rather than a blank', (tester) async {
      // CoverArt's walk to the next host is driven by errorBuilder. A provider
      // that swallowed this and resolved to nothing would strand every cover on
      // the first dead node.
      final provider = coverImageProvider(
        _url,
        store: store,
        fetch: (url) async => throw NetworkImageLoadException(statusCode: 502, uri: url),
      );

      expect(await loadFailure(tester, provider), isA<NetworkImageLoadException>());
      expect(store.files, isEmpty, reason: 'nothing to save');
    });

    testWidgets('shows the cover even when it cannot be saved', (tester) async {
      store.failWrites = true;
      final provider = coverImageProvider(_url, store: store, fetch: serving);

      final info = await load(tester, provider);
      expect(info.image.width, 2);
    });
  });

  group('identity', () {
    test('two providers for the same url and store are the same one', () {
      // Not housekeeping. `evict()` finds its entry in the image cache by key, so
      // if the provider rebuilt each frame compared unequal to the one before it,
      // a failed load could never be evicted -- and cycling back to that host
      // later would be answered out of the cache with the old failure.
      expect(
        coverImageProvider(_url, store: store, fetch: serving),
        coverImageProvider(_url, store: store, fetch: serving),
      );
    });

    test('two urls are not', () {
      expect(
        coverImageProvider(_url, store: store, fetch: serving),
        isNot(coverImageProvider('$_url?2', store: store, fetch: serving)),
      );
    });

    test('the same url in two different caches is not', () {
      expect(
        coverImageProvider(_url, store: store, fetch: serving),
        isNot(coverImageProvider(_url, store: FakeImageByteStore(), fetch: serving)),
      );
    });
  });

  group('the real fetch', () {
    /// The default [ImageBytesFetch], which every test above replaces. It is the
    /// only part of this file that runs in the app, and it was untested until a
    /// sabotage deleted its status check and nothing noticed.
    Future<Uint8List> fetchFrom(http.Response Function(http.Request request) answer) =>
        fetchOverHttp(Uri.parse(_url), client: MockClient((request) async => answer(request)));

    test('hands back the body of a 200', () async {
      expect(await fetchFrom((_) => http.Response.bytes(tinyPng, 200)), tinyPng);
    });

    test('refuses a 502 rather than passing the error page to a decoder', () async {
      // A dead Audius node answers 502 with an HTML body. Handed on, the decoder
      // would complain about a codec; raised here it names the host and the
      // status, and CoverArt moves to the next mirror.
      await expectLater(
        fetchFrom((_) => http.Response('<html>bad gateway</html>', 502)),
        throwsA(isA<NetworkImageLoadException>().having((e) => e.statusCode, 'statusCode', 502)),
      );
    });

    test('refuses a 404', () async {
      await expectLater(
        fetchFrom((_) => http.Response('', 404)),
        throwsA(isA<NetworkImageLoadException>()),
      );
    });

    test('refuses a 200 with nothing in it', () async {
      // Seen from CDNs mid-deploy. Treated as a refusal so the walk continues,
      // rather than as an image so the decoder can fail confusingly.
      await expectLater(
        fetchFrom((_) => http.Response.bytes(const [], 200)),
        throwsA(isA<NetworkImageLoadException>()),
      );
    });
  });
}
