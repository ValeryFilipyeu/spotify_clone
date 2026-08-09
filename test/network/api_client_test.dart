import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:spotify_clone/network/api_client.dart';
import 'package:spotify_clone/network/api_failure.dart';

final _base = Uri.parse('https://example.test/v1');

/// Builds a client whose every request is answered by [respond], recording the
/// urls it was asked for.
({ApiClient client, List<Uri> requested}) clientThat(
  Future<http.Response> Function(http.Request request) respond, {
  Map<String, String> defaultQuery = const {'app_name': 'TestApp'},
  Duration timeout = const Duration(seconds: 10),
}) {
  final requested = <Uri>[];
  final client = ApiClient(
    baseUrl: _base,
    defaultQuery: defaultQuery,
    timeout: timeout,
    httpClient: MockClient((request) {
      requested.add(request.url);
      return respond(request);
    }),
  );
  addTearDown(client.close);
  return (client: client, requested: requested);
}

Future<http.Response> _ok(Object? json) async => http.Response(jsonEncode(json), 200);

void main() {
  group('url building', () {
    test('appends the path to the base url instead of resolving against it', () async {
      // Uri.resolve would drop `/v1` here, because a final segment with no
      // trailing slash counts as a file and gets replaced.
      final fake = clientThat((_) => _ok({'data': []}));
      await fake.client.getJson('tracks/search');

      expect(fake.requested.single.path, '/v1/tracks/search');
    });

    test('merges the default query into every request', () async {
      final fake = clientThat((_) => _ok({'data': []}));
      await fake.client.getJson('tracks', query: {'query': 'lofi'});

      expect(fake.requested.single.queryParameters, {'app_name': 'TestApp', 'query': 'lofi'});
    });

    test('drops null query values so optional parameters need no branching', () async {
      final fake = clientThat((_) => _ok({'data': []}));
      await fake.client.getJson('tracks', query: {'genre': null, 'limit': '5'});

      expect(fake.requested.single.queryParameters.containsKey('genre'), isFalse);
      expect(fake.requested.single.queryParameters['limit'], '5');
    });

    test('repeats a list value, which is how the bulk endpoints take ids', () async {
      final fake = clientThat((_) => _ok({'data': []}));
      await fake.client.getJson('tracks', query: {'id': ['abc', 'def']});

      expect(fake.requested.single.queryParametersAll['id'], ['abc', 'def']);
    });

    test('percent-encodes a query value', () async {
      final fake = clientThat((_) => _ok({'data': []}));
      await fake.client.getJson('tracks/search', query: {'query': 'lo fi & jazz'});

      expect(fake.requested.single.query, contains('lo+fi+%26+jazz'));
      expect(fake.requested.single.queryParameters['query'], 'lo fi & jazz');
    });
  });

  group('decoding', () {
    test('returns the decoded object on success', () async {
      final fake = clientThat((_) => _ok({'data': [{'id': 'abc'}]}));

      expect(await fake.client.getJson('tracks'), {'data': [{'id': 'abc'}]});
    });

    test('a 200 that is not JSON is a MalformedResponse, not a crash', () async {
      final fake = clientThat((_) async => http.Response('<html>hello</html>', 200));

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<MalformedResponse>().having((f) => f.detail, 'detail', contains('not JSON'))),
      );
    });

    test('a 200 whose root is an array is a MalformedResponse', () async {
      // Every endpoint this app talks to wraps its payload in an object. A bare
      // array means we are talking to something other than what we think.
      final fake = clientThat((_) => _ok([1, 2, 3]));

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<MalformedResponse>().having((f) => f.detail, 'detail', contains('JSON object'))),
      );
    });
  });

  group('failure mapping', () {
    test('a 4xx carries the status and the server\'s own explanation', () async {
      final fake = clientThat(
        (_) async => http.Response(jsonEncode({'code': 400, 'error': 'invalid playlistId'}), 400),
      );

      await expectLater(
        fake.client.getJson('playlists/ZZZ'),
        throwsA(isA<HttpErrorStatus>()
            .having((f) => f.statusCode, 'statusCode', 400)
            .having((f) => f.serverMessage, 'serverMessage', 'invalid playlistId')
            .having((f) => f.isTransient, 'isTransient', isFalse)),
      );
    });

    test('an error body that is not JSON still reports the status', () async {
      // The status is the useful half. Trying to describe the failure must not
      // replace it with a parse error.
      final fake = clientThat((_) async => http.Response('502 Bad Gateway', 502));

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<HttpErrorStatus>()
            .having((f) => f.statusCode, 'statusCode', 502)
            .having((f) => f.serverMessage, 'serverMessage', isNull)
            .having((f) => f.isTransient, 'isTransient', isTrue)),
      );
    });

    test('429 counts as transient even though it is a 4xx', () async {
      final fake = clientThat((_) async => http.Response('slow down', 429));

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<HttpErrorStatus>().having((f) => f.isTransient, 'isTransient', isTrue)),
      );
    });

    test('a platform network error becomes NetworkUnreachable', () async {
      // ClientException is what package:http raises on every platform -- a
      // socket failure natively, a refused cross-origin request on the web.
      final fake = clientThat((request) async => throw http.ClientException('failed', request.url));

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<NetworkUnreachable>().having((f) => f.uri.path, 'uri.path', '/v1/tracks')),
      );
    });

    test('a request that never answers becomes RequestTimeout', () async {
      final fake = clientThat(
        (_) => Completer<http.Response>().future, // connected, never answers
        timeout: const Duration(milliseconds: 50),
      );

      await expectLater(
        fake.client.getJson('tracks'),
        throwsA(isA<RequestTimeout>().having((f) => f.limit.inMilliseconds, 'limit', 50)),
      );
    });

    test('the failure names the url that failed', () async {
      final fake = clientThat((_) async => http.Response('nope', 500));

      final failure = await fake.client.getJson('tracks/search', query: {'query': 'jazz'})
          .then<ApiFailure?>((_) => null, onError: (Object e) => e as ApiFailure);

      expect(failure!.uri.path, '/v1/tracks/search');
      expect(failure.uri.queryParameters['query'], 'jazz');
      expect(failure.toString(), contains('/v1/tracks/search'));
    });
  });

  group('in-flight de-duplication', () {
    test('two concurrent callers for the same url share one round trip', () async {
      final gate = Completer<http.Response>();
      final fake = clientThat((_) => gate.future);

      final first = fake.client.getJson('tracks/trending');
      final second = fake.client.getJson('tracks/trending');
      gate.complete(http.Response(jsonEncode({'data': ['x']}), 200));

      expect(await first, {'data': ['x']});
      expect(await second, {'data': ['x']});
      expect(fake.requested, hasLength(1));
    });

    test('different urls are not shared', () async {
      final fake = clientThat((_) => _ok({'data': []}));

      await Future.wait([
        fake.client.getJson('tracks/trending'),
        fake.client.getJson('tracks/trending', query: {'genre': 'Jazz'}),
      ]);

      expect(fake.requested, hasLength(2));
    });

    test('the entry is released once it completes, so a later call refetches', () async {
      final fake = clientThat((_) => _ok({'data': []}));

      await fake.client.getJson('tracks/trending');
      await fake.client.getJson('tracks/trending');

      expect(fake.requested, hasLength(2));
    });

    test('a failure is not cached: the next caller gets a fresh attempt', () async {
      // Holding on to a failed future would let one flaky moment break that url
      // for the rest of the session.
      var attempts = 0;
      final fake = clientThat((_) async {
        attempts++;
        if (attempts == 1) return http.Response('boom', 500);
        return http.Response(jsonEncode({'data': ['recovered']}), 200);
      });

      await expectLater(fake.client.getJson('tracks'), throwsA(isA<HttpErrorStatus>()));
      expect(await fake.client.getJson('tracks'), {'data': ['recovered']});
      expect(attempts, 2);
    });

    test('a failed request raises no second, unhandled async error', () async {
      // The bookkeeping that releases the in-flight entry chains off the same
      // future the caller holds. Both would complete with the error, but only
      // the caller's is handled -- so the other has to be explicitly ignored or
      // it surfaces as an unhandled async error and fails whatever test is
      // running at the time. This test is what catches that regressing.
      final fake = clientThat((_) async => http.Response('boom', 500));

      await expectLater(fake.client.getJson('tracks'), throwsA(isA<HttpErrorStatus>()));
      // Give the un-awaited chain a turn of the event loop to blow up in.
      await Future<void>.delayed(Duration.zero);
    });
  });
}
