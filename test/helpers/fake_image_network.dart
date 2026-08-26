import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// A 1x1 fully transparent PNG -- the smallest byte sequence Flutter's decoder
/// accepts as an image.
const List<int> _onePixelPng = [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // signature
  0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52, // IHDR length + type
  0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, // 1x1
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, // 8-bit RGBA + CRC
  0x00, 0x00, 0x00, 0x0A, 0x49, 0x44, 0x41, 0x54, // IDAT length + type
  0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00, 0x05, 0x00, 0x01, // zlib scanline
  0x0D, 0x0A, 0x2D, 0xB4, // IDAT CRC
  0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, // IEND
];

/// Pumps [widget] with every network image answered by a real (if tiny) PNG and
/// waits for them to load, so a test can assert on a *drawn* image.
///
/// Two reasons a plain `pumpWidget` + `pumpAndSettle` leaves every cover blank:
/// the hook is [debugNetworkImageHttpClientProvider], not `HttpOverrides` (
/// NetworkImage keeps one `static final` HttpClient a zone override never
/// reaches); and the load needs [WidgetTester.runAsync], because fetch and
/// decode finish on engine threads the fake clock never advances.
///
/// The client is hand-rolled with `noSuchMethod`: HttpClient has dozens of
/// members and this needs four.
Future<void> pumpWithNetworkImages(WidgetTester tester, Widget widget) async {
  final network = installFakeImageNetwork();
  try {
    await tester.runAsync(() async {
      await tester.pumpWidget(widget);
      // Real time, so the fetch and the decode above can finish.
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await tester.pump();
    });
    // Back on fake time to run the fade-in to completion.
    await tester.pumpAndSettle();
  } finally {
    network.restore();
  }
}

/// Answers network image requests, with a switch for failing the first few.
///
/// Handed back by [installFakeImageNetwork] for tests that have to drive the
/// pumping themselves -- a retry needs real time for each fetch and fake time
/// for the backoff in between, which [pumpWithNetworkImages] cannot do for you.
class FakeImageNetwork {
  /// Every url the widget under test actually put on the wire, in order. Which
  /// host each attempt went to is the whole question for a failover, so counting
  /// is not enough: a widget that retried the dead node three times and one that
  /// walked three mirrors make the same number of requests.
  final List<String> requestedUrls = [];

  int get requests => requestedUrls.length;

  /// How many of the first requests to answer with a 403, as a throttling CDN
  /// does. Counted, for tests about *how many* attempts happen.
  int failFirst = 0;

  /// How many to leave hanging: connected, no bytes, no error, for ever. This
  /// is what a failed image looks like on the web, where nothing reports an
  /// error -- so it is the case only the stall watchdog can get out of.
  int hangFirst = 0;

  /// Urls that always fail, however often they are asked. Keyed by url rather
  /// than counted, because that is how a dead content node behaves: it is not
  /// the third request that fails, it is that host, every time.
  Set<String> deadUrls = const {};

  /// Urls that always hang -- the same idea, for the web's silent failure.
  Set<String> stalledUrls = const {};

  /// MUST be called before the test body ends: flutter_test asserts no painting
  /// debug variable is left set, and it checks that before any tearDown runs.
  /// Clearing the cache also stops a url one test loaded standing in for a url
  /// the next test needs to fail.
  void restore() {
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
  }
}

FakeImageNetwork installFakeImageNetwork({
  int failFirst = 0,
  int hangFirst = 0,
  Set<String> deadUrls = const {},
  Set<String> stalledUrls = const {},
}) {
  // Entries are keyed by url, so a url some earlier test failed to load would
  // come straight back out of the cache as a failure.
  PaintingBinding.instance.imageCache.clear();
  final network = FakeImageNetwork()
    ..failFirst = failFirst
    ..hangFirst = hangFirst
    ..deadUrls = deadUrls
    ..stalledUrls = stalledUrls;
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient(network);
  return network;
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient(this._network);

  final FakeImageNetwork _network;

  @override
  bool autoUncompress = true;

  _FakeHttpClientRequest _request(Uri url) {
    _network.requestedUrls.add(url.toString());
    return _FakeHttpClientRequest(
      refused:
          _network.requests <= _network.failFirst || _network.deadUrls.contains(url.toString()),
      hangs:
          _network.requests <= _network.hangFirst || _network.stalledUrls.contains(url.toString()),
    );
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _request(url);

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _request(url);

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpClientRequest implements HttpClientRequest {
  _FakeHttpClientRequest({required this.refused, required this.hangs});

  final bool refused;
  final bool hangs;

  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() {
    if (hangs) return Completer<HttpClientResponse>().future;
    return Future.value(_FakeHttpClientResponse(refused: refused));
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Implements the [Stream] side too: this is what
/// `consolidateHttpClientResponseBytes` (which NetworkImage uses) actually
/// reads, along with [statusCode], [contentLength] and [compressionState].
class _FakeHttpClientResponse implements HttpClientResponse {
  _FakeHttpClientResponse({required this.refused});

  final bool refused;

  @override
  int get statusCode => refused ? HttpStatus.forbidden : HttpStatus.ok;

  @override
  int get contentLength => _onePixelPng.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return Stream<List<int>>.value(
      Uint8List.fromList(_onePixelPng),
    ).listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void noSuchMethod(Invocation invocation) {}
}
