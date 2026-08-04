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

/// Pumps [widget] with every network image answered by a real (if tiny) PNG, and
/// waits until those images have actually loaded -- so a widget test can assert
/// on a *drawn* [Image.network], not merely on one being in the tree.
///
/// Two things here are less obvious than they look, and both are why a plain
/// `pumpWidget` + `pumpAndSettle` silently leaves every cover unloaded:
///
///  * The client hook is [debugNetworkImageHttpClientProvider], NOT
///    `HttpOverrides`. NetworkImage keeps a single `static final` HttpClient,
///    created the first time anything resolves an image, so a zone-scoped
///    override never reaches it. This is the seam Flutter provides for exactly
///    that reason.
///  * The load has to happen under [WidgetTester.runAsync]. Fetching and
///    *decoding* an image both complete on the engine's own threads, which the
///    test's fake clock never advances -- so inside an ordinary pump the frame
///    simply never arrives.
///
/// The fake client itself is hand-rolled with `noSuchMethod` rather than pulling
/// in a mocking package: HttpClient and friends have dozens of members between
/// them and this needs exactly four.
Future<void> pumpWithNetworkImages(WidgetTester tester, Widget widget) async {
  // Entries are keyed by url, so a url some earlier test failed to load would
  // come straight back out of the cache as a failure.
  PaintingBinding.instance.imageCache.clear();
  debugNetworkImageHttpClientProvider = () => _FakeHttpClient();
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
    // Both undone here rather than in a tearDown: flutter_test asserts that no
    // painting debug variable is still set when the test BODY ends, which is
    // before any tearDown runs. Clearing the cache on the way out also stops a
    // successfully-loaded url leaking into a later test that needs it to fail.
    debugNetworkImageHttpClientProvider = null;
    PaintingBinding.instance.imageCache.clear();
  }
}

class _FakeHttpClient implements HttpClient {
  @override
  bool autoUncompress = true;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async => _FakeHttpClientRequest();

  @override
  Future<HttpClientRequest> openUrl(String method, Uri url) async => _FakeHttpClientRequest();

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpClientRequest implements HttpClientRequest {
  @override
  final HttpHeaders headers = _FakeHttpHeaders();

  @override
  Future<HttpClientResponse> close() async => _FakeHttpClientResponse();

  @override
  void noSuchMethod(Invocation invocation) {}
}

/// Implements the [Stream] side too: this is what
/// `consolidateHttpClientResponseBytes` (which NetworkImage uses) actually
/// reads, along with [statusCode], [contentLength] and [compressionState].
class _FakeHttpClientResponse implements HttpClientResponse {
  @override
  int get statusCode => HttpStatus.ok;

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
    return Stream<List<int>>.value(Uint8List.fromList(_onePixelPng)).listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  void noSuchMethod(Invocation invocation) {}
}

class _FakeHttpHeaders implements HttpHeaders {
  @override
  void noSuchMethod(Invocation invocation) {}
}
